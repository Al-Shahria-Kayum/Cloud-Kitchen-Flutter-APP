import 'dart:async';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../../models/chat.dart';
import '../../providers/auth_provider.dart';
import '../../providers/chat_provider.dart';
import '../../theme/app_theme.dart';
import '../../utils/error_mapper.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/section_header.dart';

/// A handful of common emoji for the quick-insert bar — intentionally not a
/// full emoji keyboard, just fast taps for the reactions people actually use.
const List<String> _kQuickEmoji = [
  '😀', '😂', '😍', '👍', '🙏', '🎉',
  '😢', '😮', '❤️', '🔥', '👌', '🤔',
];

class ChatScreen extends StatefulWidget {
  final String orderId;
  final String senderId;
  const ChatScreen({super.key, required this.orderId, required this.senderId});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _msgController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _inputFocus = FocusNode();
  final ImagePicker _picker = ImagePicker();

  String? _chatId;
  bool _loadingChat = true;
  bool _sending = false;
  bool _uploadingPhoto = false;

  Message? _replyingTo;
  String? _expandedMessageId;

  String? _typingUserName;
  Timer? _typingClearTimer;

  ChatProvider? _chatProvider;
  String? _lastMarkedReadSignature;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeChat();
    });
  }

  @override
  void dispose() {
    _chatProvider?.removeListener(_onMessagesChanged);
    _typingClearTimer?.cancel();
    _msgController.dispose();
    _scrollController.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  String get _myName {
    final profile = context.read<AuthProvider>().profile;
    return profile?.fullName ?? 'Someone';
  }

  bool _initError = false;

  Future<void> _initializeChat() async {
    final chatProvider = Provider.of<ChatProvider>(context, listen: false);
    _chatProvider = chatProvider;
    try {
      final id = await chatProvider.getOrCreateChat(widget.orderId);

      if (id != null) {
        _chatId = id;
        chatProvider.subscribeToMessages(id);
        // Typing indicator is a nice-to-have — never let it block the chat
        // itself from loading if the realtime broadcast channel misbehaves.
        try {
          chatProvider.subscribeToTyping(id, widget.senderId, _onTypingReceived);
        } catch (_) {
          // Ignored: chat still works without the "is typing…" indicator.
        }
        chatProvider.addListener(_onMessagesChanged);
      } else {
        _initError = true;
      }
    } catch (_) {
      _initError = true;
    }

    if (!mounted) return;
    setState(() {
      _loadingChat = false;
    });
  }

  void _onTypingReceived(String name) {
    if (!mounted) return;
    setState(() => _typingUserName = name);
    _typingClearTimer?.cancel();
    _typingClearTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _typingUserName = null);
    });
  }

  void _onMessagesChanged() {
    final provider = _chatProvider;
    if (provider == null || _chatId == null) return;
    final msgs = provider.messages;
    if (msgs.isEmpty) return;

    final signature = '${msgs.length}:${msgs.last.id}';
    if (signature != _lastMarkedReadSignature) {
      _lastMarkedReadSignature = signature;
      provider.markMessagesRead(_chatId!, widget.senderId);
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: AppMotion.base,
          curve: AppMotion.curve,
        );
      }
    });
  }

  void _onInputChanged(String text) {
    if (text.trim().isEmpty) return;
    _chatProvider?.broadcastTyping(widget.senderId, _myName);
  }

  void _insertEmoji(String emoji) {
    final text = _msgController.text;
    final selection = _msgController.selection;
    final cursor = selection.isValid ? selection.start : text.length;
    final newText = text.replaceRange(cursor, selection.isValid ? selection.end : text.length, emoji);
    _msgController.text = newText;
    _msgController.selection = TextSelection.collapsed(offset: cursor + emoji.length);
  }

  void _startReply(Message message) {
    setState(() => _replyingTo = message);
    _inputFocus.requestFocus();
  }

  void _cancelReply() => setState(() => _replyingTo = null);

  Future<void> _sendMessage() async {
    if (_chatId == null || _sending) return;
    final text = _msgController.text.trim();
    if (text.isEmpty) return;

    setState(() => _sending = true);
    final replyId = _replyingTo?.id;

    final chatProvider = Provider.of<ChatProvider>(context, listen: false);
    final success = await chatProvider.sendMessage(_chatId!, widget.senderId, text, replyToMessageId: replyId);

    if (!mounted) return;
    setState(() => _sending = false);

    if (success) {
      // Only clear the composer once we know the message actually went
      // through — previously this cleared unconditionally, so a failed send
      // (RLS error, dropped connection, etc.) silently discarded the text
      // with no feedback at all, which just looked like "sending is broken".
      _msgController.clear();
      setState(() => _replyingTo = null);
      _scrollToBottom();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(friendlyErrorMessage(chatProvider.errorMessage, fallback: 'Failed to send message. Please try again.')),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  Future<void> _pickAndSendPhoto() async {
    if (_chatId == null || _uploadingPhoto) return;
    final XFile? file = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (file == null || !mounted) return;

    setState(() => _uploadingPhoto = true);
    final chatProvider = Provider.of<ChatProvider>(context, listen: false);
    final bytes = await file.readAsBytes();
    final url = await chatProvider.uploadChatImage(bytes, file.name, _chatId!, widget.senderId);

    if (url == null) {
      if (!mounted) return;
      setState(() => _uploadingPhoto = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(friendlyErrorMessage(chatProvider.errorMessage, fallback: 'Failed to upload photo. Please try again.')),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
      return;
    }

    final replyId = _replyingTo?.id;
    final success = await chatProvider.sendMessage(_chatId!, widget.senderId, '', replyToMessageId: replyId, imageUrl: url);

    if (!mounted) return;
    setState(() => _uploadingPhoto = false);

    if (success) {
      setState(() => _replyingTo = null);
      _scrollToBottom();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(friendlyErrorMessage(chatProvider.errorMessage, fallback: 'Failed to send photo. Please try again.')),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  void _openImageViewer(String url) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(backgroundColor: Colors.black, iconTheme: const IconThemeData(color: Colors.white)),
        body: Center(child: InteractiveViewer(child: Image.network(url))),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final chatProvider = context.watch<ChatProvider>();
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Order Chat'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(20),
          child: AnimatedSwitcher(
            duration: AppMotion.fast,
            child: _typingUserName != null
                ? Padding(
                    key: const ValueKey('typing'),
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: Text(
                      '$_typingUserName is typing…',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(color: scheme.primary),
                    ),
                  )
                : const SizedBox(key: ValueKey('no-typing'), height: 1),
          ),
        ),
      ),
      body: _loadingChat
          ? const Center(child: CircularProgressIndicator())
          : _initError
              ? Center(
                  child: EmptyState(
                    icon: Icons.error_outline_rounded,
                    title: 'Couldn\'t open this chat',
                    message: 'Check your connection and try again.',
                    actionLabel: 'Retry',
                    onAction: () {
                      setState(() {
                        _initError = false;
                        _loadingChat = true;
                      });
                      _initializeChat();
                    },
                  ),
                )
              : Column(
              children: [
                Expanded(
                  child: chatProvider.messages.isEmpty
                      ? const EmptyState(
                          icon: Icons.chat_bubble_outline_rounded,
                          title: 'No messages yet',
                          message: 'Send a greeting to get the conversation started.',
                        )
                      : ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.all(AppSpacing.lg),
                          itemCount: chatProvider.messages.length,
                          itemBuilder: (context, index) {
                            final msg = chatProvider.messages[index];
                            final prev = index > 0 ? chatProvider.messages[index - 1] : null;
                            final next = index < chatProvider.messages.length - 1
                                ? chatProvider.messages[index + 1]
                                : null;
                            final isMe = msg.senderId == widget.senderId;

                            final groupedWithPrev = prev != null &&
                                prev.senderId == msg.senderId &&
                                msg.createdAt.difference(prev.createdAt) < const Duration(minutes: 5);
                            final groupedWithNext = next != null &&
                                next.senderId == msg.senderId &&
                                next.createdAt.difference(msg.createdAt) < const Duration(minutes: 5);

                            return _MessageBubble(
                              key: ValueKey(msg.id),
                              message: msg,
                              isMe: isMe,
                              showAvatar: !isMe && !groupedWithNext,
                              showTail: !groupedWithNext,
                              tightTop: groupedWithPrev,
                              expanded: _expandedMessageId == msg.id,
                              quotedMessage: msg.replyToMessageId != null
                                  ? chatProvider.messageById(msg.replyToMessageId!)
                                  : null,
                              onTap: () => setState(() {
                                _expandedMessageId = _expandedMessageId == msg.id ? null : msg.id;
                              }),
                              onSwipeReply: () => _startReply(msg),
                              onImageTap: msg.hasImage ? () => _openImageViewer(msg.imageUrl!) : null,
                            );
                          },
                        ),
                ),
                _ComposerBar(
                  controller: _msgController,
                  focusNode: _inputFocus,
                  sending: _sending,
                  uploadingPhoto: _uploadingPhoto,
                  replyingTo: _replyingTo,
                  onCancelReply: _cancelReply,
                  onChanged: _onInputChanged,
                  onEmojiTap: _insertEmoji,
                  onSend: _sendMessage,
                  onAttachPhoto: _pickAndSendPhoto,
                ),
              ],
            ),
    );
  }
}

/// The message bubble, with grouping-aware corner treatment, a swipe-to-reply
/// gesture, a tap-to-reveal timestamp, and a one-time entrance animation that
/// plays only the first time a given message id is mounted (its [ValueKey]
/// lets Flutter preserve state across rebuilds once already animated in).
class _MessageBubble extends StatefulWidget {
  final Message message;
  final bool isMe;
  final bool showAvatar;
  final bool showTail;
  final bool tightTop;
  final bool expanded;
  final Message? quotedMessage;
  final VoidCallback onTap;
  final VoidCallback onSwipeReply;
  final VoidCallback? onImageTap;

  const _MessageBubble({
    super.key,
    required this.message,
    required this.isMe,
    required this.showAvatar,
    required this.showTail,
    required this.tightTop,
    required this.expanded,
    required this.quotedMessage,
    required this.onTap,
    required this.onSwipeReply,
    this.onImageTap,
  });

  @override
  State<_MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<_MessageBubble> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;
  double _dragExtent = 0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: AppMotion.base);
    _fade = CurvedAnimation(parent: _controller, curve: AppMotion.curve);
    _slide = Tween<Offset>(begin: const Offset(0, 0.15), end: Offset.zero)
        .animate(CurvedAnimation(parent: _controller, curve: AppMotion.curve));
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String _formatTime(DateTime dt) {
    final local = dt.toLocal();
    final h = local.hour.toString().padLeft(2, '0');
    final m = local.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  String _formatFull(DateTime dt) {
    final local = dt.toLocal();
    return '${local.day}/${local.month}/${local.year} ${_formatTime(dt)}';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final isMe = widget.isMe;

    final radius = BorderRadius.only(
      topLeft: const Radius.circular(AppRadius.md),
      topRight: const Radius.circular(AppRadius.md),
      bottomLeft: Radius.circular(isMe || widget.showTail ? AppRadius.md : AppRadius.sm),
      bottomRight: Radius.circular(!isMe || widget.showTail ? AppRadius.md : AppRadius.sm),
    );

    final bubbleColor = isMe ? scheme.primary : scheme.surfaceContainerHighest;
    final onBubble = isMe ? scheme.onPrimary : scheme.onSurface;

    final avatarSlot = SizedBox(
      width: 32,
      child: widget.showAvatar
          ? InitialsAvatar(name: widget.message.senderName ?? '?', size: 28)
          : null,
    );

    final bubble = GestureDetector(
      onTap: widget.onTap,
      onHorizontalDragUpdate: (details) {
        setState(() => _dragExtent = (_dragExtent + details.delta.dx).clamp(-56.0, 56.0));
      },
      onHorizontalDragEnd: (details) {
        if (_dragExtent.abs() > 36) widget.onSwipeReply();
        setState(() => _dragExtent = 0);
      },
      child: Transform.translate(
        offset: Offset(_dragExtent, 0),
        child: Container(
          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.72),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md + 2, vertical: AppSpacing.sm + 2),
          decoration: BoxDecoration(color: bubbleColor, borderRadius: radius),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!isMe && widget.showAvatar)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                  child: Text(
                    widget.message.senderName ?? 'User',
                    style: text.labelMedium?.copyWith(color: onBubble.withValues(alpha: 0.75)),
                  ),
                ),
              if (widget.quotedMessage != null)
                Container(
                  margin: const EdgeInsets.only(bottom: AppSpacing.xs),
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
                  decoration: BoxDecoration(
                    color: onBubble.withValues(alpha: 0.08),
                    borderRadius: AppRadius.smBr,
                    border: Border(left: BorderSide(color: onBubble.withValues(alpha: 0.4), width: 2)),
                  ),
                  child: Text(
                    widget.quotedMessage!.hasImage && widget.quotedMessage!.messageText.isEmpty
                        ? '📷 Photo'
                        : widget.quotedMessage!.messageText,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: text.bodySmall?.copyWith(color: onBubble.withValues(alpha: 0.8)),
                  ),
                ),
              if (widget.message.hasImage)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                  child: GestureDetector(
                    onTap: widget.onImageTap,
                    child: ClipRRect(
                      borderRadius: AppRadius.smBr,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 220, minWidth: 160),
                        child: Image.network(
                          widget.message.imageUrl!,
                          fit: BoxFit.cover,
                          loadingBuilder: (context, child, progress) => progress == null
                              ? child
                              : Container(
                                  height: 160,
                                  width: 160,
                                  alignment: Alignment.center,
                                  color: onBubble.withValues(alpha: 0.08),
                                  child: const CircularProgressIndicator(strokeWidth: 2),
                                ),
                          errorBuilder: (context, error, stackTrace) => Container(
                            height: 120,
                            width: 160,
                            alignment: Alignment.center,
                            color: onBubble.withValues(alpha: 0.08),
                            child: Icon(Icons.broken_image_outlined, color: onBubble.withValues(alpha: 0.5)),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              if (widget.message.messageText.isNotEmpty)
                Text(widget.message.messageText, style: text.bodyMedium?.copyWith(color: onBubble)),
              const SizedBox(height: 2),
              AnimatedSize(
                duration: AppMotion.fast,
                child: widget.expanded
                    ? Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          _formatFull(widget.message.createdAt),
                          style: text.labelSmall?.copyWith(color: onBubble.withValues(alpha: 0.65)),
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _formatTime(widget.message.createdAt),
                    style: text.labelSmall?.copyWith(color: onBubble.withValues(alpha: 0.6)),
                  ),
                  if (isMe) ...[
                    const SizedBox(width: 4),
                    Icon(
                      widget.message.isRead ? Icons.done_all_rounded : Icons.done_rounded,
                      size: 14,
                      color: widget.message.isRead ? onBubble : onBubble.withValues(alpha: 0.6),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );

    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(
        position: _slide,
        child: Padding(
          padding: EdgeInsets.only(top: widget.tightTop ? 2 : AppSpacing.md),
          child: Row(
            mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: isMe
                ? [Flexible(child: bubble)]
                : [avatarSlot, const SizedBox(width: AppSpacing.xs), Flexible(child: bubble)],
          ),
        ),
      ),
    );
  }
}

/// The bottom composer: optional reply-preview strip, emoji quick-bar, and a
/// rounded input row with a send button that scales down on press.
class _ComposerBar extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool sending;
  final bool uploadingPhoto;
  final Message? replyingTo;
  final VoidCallback onCancelReply;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onEmojiTap;
  final VoidCallback onSend;
  final VoidCallback onAttachPhoto;

  const _ComposerBar({
    required this.controller,
    required this.focusNode,
    required this.sending,
    required this.uploadingPhoto,
    required this.replyingTo,
    required this.onCancelReply,
    required this.onChanged,
    required this.onEmojiTap,
    required this.onSend,
    required this.onAttachPhoto,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return SafeArea(
      top: false,
      child: Container(
        decoration: BoxDecoration(
          color: scheme.surface,
          border: Border(top: BorderSide(color: scheme.outline.withValues(alpha: 0.6))),
        ),
        padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.md, AppSpacing.sm),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedSize(
              duration: AppMotion.fast,
              child: replyingTo == null
                  ? const SizedBox.shrink()
                  : Container(
                      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
                      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
                      decoration: BoxDecoration(
                        color: scheme.primaryContainer.withValues(alpha: 0.5),
                        borderRadius: AppRadius.smBr,
                        border: Border(left: BorderSide(color: scheme.primary, width: 3)),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Replying to ${replyingTo!.senderName ?? 'message'}',
                                    style: text.labelSmall?.copyWith(color: scheme.primary)),
                                Text(
                                  replyingTo!.messageText,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: text.bodySmall,
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close_rounded, size: 18),
                            onPressed: onCancelReply,
                            visualDensity: VisualDensity.compact,
                          ),
                        ],
                      ),
                    ),
            ),
            SizedBox(
              height: 40,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _kQuickEmoji.length,
                separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.xs),
                itemBuilder: (context, i) {
                  final emoji = _kQuickEmoji[i];
                  return InkWell(
                    borderRadius: AppRadius.pillBr,
                    onTap: () => onEmojiTap(emoji),
                    child: Container(
                      width: 34,
                      alignment: Alignment.center,
                      child: Text(emoji, style: const TextStyle(fontSize: 20)),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                IconButton(
                  onPressed: uploadingPhoto ? null : onAttachPhoto,
                  tooltip: 'Share a photo',
                  icon: uploadingPhoto
                      ? SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: scheme.primary),
                        )
                      : Icon(Icons.add_photo_alternate_outlined, color: scheme.primary),
                ),
                Expanded(
                  child: TextField(
                    controller: controller,
                    focusNode: focusNode,
                    onChanged: onChanged,
                    minLines: 1,
                    maxLines: 4,
                    decoration: InputDecoration(
                      hintText: 'Type your message…',
                      border: OutlineInputBorder(borderRadius: AppRadius.pillBr, borderSide: BorderSide.none),
                      enabledBorder: OutlineInputBorder(borderRadius: AppRadius.pillBr, borderSide: BorderSide.none),
                      focusedBorder: OutlineInputBorder(borderRadius: AppRadius.pillBr, borderSide: BorderSide.none),
                      fillColor: scheme.surfaceContainerHighest,
                      filled: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.sm + 2),
                    ),
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => onSend(),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                _SendButton(onPressed: sending ? null : onSend, sending: sending),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SendButton extends StatefulWidget {
  final VoidCallback? onPressed;
  final bool sending;
  const _SendButton({required this.onPressed, required this.sending});

  @override
  State<_SendButton> createState() => _SendButtonState();
}

class _SendButtonState extends State<_SendButton> {
  double _scale = 1;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTapDown: widget.onPressed == null ? null : (_) => setState(() => _scale = 0.85),
      onTapUp: widget.onPressed == null ? null : (_) => setState(() => _scale = 1),
      onTapCancel: () => setState(() => _scale = 1),
      onTap: widget.onPressed,
      child: AnimatedScale(
        scale: _scale,
        duration: AppMotion.fast,
        curve: AppMotion.curve,
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(color: scheme.primary, shape: BoxShape.circle),
          alignment: Alignment.center,
          child: widget.sending
              ? SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: scheme.onPrimary),
                )
              : Icon(Icons.send_rounded, color: scheme.onPrimary, size: 20),
        ),
      ),
    );
  }
}
