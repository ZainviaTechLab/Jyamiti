class Chat {
  final String id;
  final String type;
  final String? name;
  final Map<String, dynamic>? batch;
  final List<dynamic> participants;
  final Map<String, dynamic>? latestMessage;
  final int unreadCount;

  Chat({
    required this.id,
    required this.type,
    this.name,
    this.batch,
    required this.participants,
    this.latestMessage,
    required this.unreadCount,
  });

  factory Chat.fromJson(Map<String, dynamic> json, String currentUserId) {
    int count = 0;
    if (json['unreadCounts'] != null && json['unreadCounts'][currentUserId] != null) {
      count = json['unreadCounts'][currentUserId];
    }

    return Chat(
      id: json['_id'],
      type: json['type'],
      name: json['name'],
      batch: json['batch'],
      participants: json['participants'] ?? [],
      latestMessage: json['latestMessage'],
      unreadCount: count,
    );
  }
}

class ChatMessage {
  final String id;
  final String chatId;
  final Map<String, dynamic> sender;
  final String content;
  final DateTime createdAt;

  ChatMessage({
    required this.id,
    required this.chatId,
    required this.sender,
    required this.content,
    required this.createdAt,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      id: json['_id'],
      chatId: json['chat'],
      sender: json['sender'],
      content: json['content'],
      createdAt: DateTime.parse(json['createdAt']),
    );
  }
}
