class Chat {
  final String id;
  final String orderId;
  final DateTime createdAt;

  Chat({
    required this.id,
    required this.orderId,
    required this.createdAt,
  });

  factory Chat.fromJson(Map<String, dynamic> json) {
    return Chat(
      id: json['id'] as String,
      orderId: json['order_id'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}

class Message {
  final String id;
  final String chatId;
  final String senderId;
  final String messageText;
  final String? imageUrl;
  final DateTime createdAt;
  final String? senderName;
  final DateTime? readAt;
  final String? replyToMessageId;

  Message({
    required this.id,
    required this.chatId,
    required this.senderId,
    required this.messageText,
    this.imageUrl,
    required this.createdAt,
    this.senderName,
    this.readAt,
    this.replyToMessageId,
  });

  /// Whether the recipient has read this message (only meaningful for
  /// messages the local user sent).
  bool get isRead => readAt != null;

  /// Whether this message carries a shared photo (text may be empty in that case).
  bool get hasImage => imageUrl != null && imageUrl!.isNotEmpty;

  factory Message.fromJson(Map<String, dynamic> json) {
    return Message(
      id: json['id'] as String,
      chatId: json['chat_id'] as String,
      senderId: json['sender_id'] as String,
      messageText: json['message_text'] as String? ?? '',
      imageUrl: json['image_url'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      senderName: json['profiles'] != null ? json['profiles']['full_name'] as String? : null,
      readAt: json['read_at'] != null ? DateTime.parse(json['read_at'] as String) : null,
      replyToMessageId: json['reply_to_message_id'] as String?,
    );
  }
}
