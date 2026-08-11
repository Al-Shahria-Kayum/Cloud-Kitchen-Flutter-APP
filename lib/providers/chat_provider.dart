import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/chat.dart';

class ChatProvider extends ChangeNotifier {
  final SupabaseClient _client = Supabase.instance.client;

  List<Message> _messages = [];
  final bool _isLoading = false;
  String? _errorMessage;
  StreamSubscription<List<Map<String, dynamic>>>? _messagesSubscription;

  RealtimeChannel? _typingChannel;
  DateTime? _lastTypingBroadcastAt;

  List<Message> get messages => _messages;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  /// Looks up an already-loaded message by id (used to render reply-preview
  /// snippets without an extra round trip).
  Message? messageById(String id) {
    for (final m in _messages) {
      if (m.id == id) return m;
    }
    return null;
  }

  /// Fetches or creates a chat session for a given order ID.
  Future<String?> getOrCreateChat(String orderId) async {
    try {
      final existing = await _client
          .from('chats')
          .select()
          .eq('order_id', orderId)
          .maybeSingle();

      if (existing != null) {
        return existing['id'] as String;
      }

      // Try creating new chat (often handled automatically by rpc/trigger, but fallback is good)
      final created = await _client
          .from('chats')
          .insert({'order_id': orderId})
          .select()
          .single();
      return created['id'] as String;
    } catch (e) {
      _errorMessage = e.toString();
      notifyListeners();
      return null;
    }
  }

  /// Subscribes to real-time messages in a specific chat.
  void subscribeToMessages(String chatId) {
    _messagesSubscription?.cancel();
    _messagesSubscription = _client
        .from('messages')
        .stream(primaryKey: ['id'])
        .eq('chat_id', chatId)
        .order('created_at', ascending: true)
        .listen((List<Map<String, dynamic>> data) async {
          final List<Message> resolved = [];
          for (var item in data) {
            try {
              // Resolve sender name
              final profileData = await _client
                  .from('profiles')
                  .select('full_name')
                  .eq('id', item['sender_id'])
                  .single();

              final combined = Map<String, dynamic>.from(item);
              combined['profiles'] = {'full_name': profileData['full_name']};
              resolved.add(Message.fromJson(combined));
            } catch (e) {
              resolved.add(Message.fromJson(item));
            }
          }
          _messages = resolved;
          notifyListeners();
        });
  }

  /// Sends a message in the current chat. [replyToMessageId] optionally
  /// links this message to the one it is replying to (swipe-to-reply).
  /// [imageUrl] optionally attaches a shared photo — in that case [text] may
  /// be empty (the DB requires at least one of the two to be non-empty).
  Future<bool> sendMessage(
    String chatId,
    String senderId,
    String text, {
    String? replyToMessageId,
    String? imageUrl,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty && (imageUrl == null || imageUrl.isEmpty)) return false;
    try {
      await _client.from('messages').insert({
        'chat_id': chatId,
        'sender_id': senderId,
        'message_text': trimmed,
        if (replyToMessageId != null) 'reply_to_message_id': replyToMessageId,
        if (imageUrl != null && imageUrl.isNotEmpty) 'image_url': imageUrl,
      });
      return true;
    } catch (e) {
      _errorMessage = e.toString();
      notifyListeners();
      return false;
    }
  }

  /// Uploads a photo shared in the chat to the `chat-photos` bucket, under
  /// `{chatId}/{senderId}/` (mirrors the review-photo upload pattern
  /// elsewhere). Returns the public URL, or null on failure.
  Future<String?> uploadChatImage(Uint8List imageBytes, String fileName, String chatId, String senderId) async {
    final ext = fileName.contains('.') ? fileName.split('.').last : 'jpg';
    final unique = DateTime.now().microsecondsSinceEpoch;
    final objectName = '$unique.$ext';
    final path = '$chatId/$senderId/$objectName';

    try {
      await _client.storage
          .from('chat-photos')
          .uploadBinary(path, imageBytes, fileOptions: const FileOptions(cacheControl: '3600', upsert: true))
          .timeout(const Duration(seconds: 15));
      return _client.storage.from('chat-photos').getPublicUrl(path);
    } on TimeoutException {
      final files = await _client.storage.from('chat-photos').list(path: '$chatId/$senderId');
      if (files.any((f) => f.name == objectName)) {
        return _client.storage.from('chat-photos').getPublicUrl(path);
      }
      _errorMessage = 'Photo upload timed out. Please try again.';
      notifyListeners();
      return null;
    } catch (e) {
      _errorMessage = e.toString();
      notifyListeners();
      return null;
    }
  }

  /// Marks every message in [chatId] that wasn't sent by [myUserId] and
  /// hasn't been read yet as read. Safe to call repeatedly — matches 0 rows
  /// once everything is already marked.
  Future<void> markMessagesRead(String chatId, String myUserId) async {
    try {
      await _client
          .from('messages')
          .update({'read_at': DateTime.now().toUtc().toIso8601String()})
          .eq('chat_id', chatId)
          .neq('sender_id', myUserId)
          .isFilter('read_at', null);
    } catch (e) {
      // Read receipts are best-effort; don't surface this as a chat error.
      debugPrint('markMessagesRead failed: $e');
    }
  }

  /// Opens (or re-opens) an ephemeral broadcast channel scoped to this chat
  /// used purely for the "is typing…" indicator — no database table involved.
  void subscribeToTyping(
    String chatId,
    String myUserId,
    void Function(String name) onTypingReceived,
  ) {
    _typingChannel?.unsubscribe();
    final channel = _client.channel('typing:$chatId');
    channel.onBroadcast(
      event: 'typing',
      callback: (payload) {
        final uid = payload['user_id'] as String?;
        final name = payload['name'] as String? ?? 'Someone';
        if (uid != null && uid != myUserId) {
          onTypingReceived(name);
        }
      },
    );
    channel.subscribe();
    _typingChannel = channel;
  }

  /// Broadcasts a "typing" event, throttled to at most once every 2 seconds.
  void broadcastTyping(String myUserId, String myName) {
    final now = DateTime.now();
    if (_lastTypingBroadcastAt != null &&
        now.difference(_lastTypingBroadcastAt!) < const Duration(seconds: 2)) {
      return;
    }
    _lastTypingBroadcastAt = now;
    _typingChannel?.sendBroadcastMessage(
      event: 'typing',
      payload: {'user_id': myUserId, 'name': myName},
    );
  }

  void unsubscribe() {
    _messagesSubscription?.cancel();
    _messagesSubscription = null;
    _typingChannel?.unsubscribe();
    _typingChannel = null;
    _messages = [];
  }

  @override
  void dispose() {
    _messagesSubscription?.cancel();
    _typingChannel?.unsubscribe();
    super.dispose();
  }
}
