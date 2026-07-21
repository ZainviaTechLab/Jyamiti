import 'package:equatable/equatable.dart';
import '../models/chat_model.dart';

class ChatState extends Equatable {
  final bool isLoading;
  final List<Chat> chats;
  final List<ChatMessage> activeMessages;
  final String? activeChatId;
  final String? error;

  const ChatState({
    this.isLoading = false,
    this.chats = const [],
    this.activeMessages = const [],
    this.activeChatId,
    this.error,
  });

  ChatState copyWith({
    bool? isLoading,
    List<Chat>? chats,
    List<ChatMessage>? activeMessages,
    String? activeChatId,
    String? error,
  }) {
    return ChatState(
      isLoading: isLoading ?? this.isLoading,
      chats: chats ?? this.chats,
      activeMessages: activeMessages ?? this.activeMessages,
      activeChatId: activeChatId ?? this.activeChatId,
      error: error ?? this.error,
    );
  }

  @override
  List<Object?> get props => [isLoading, chats, activeMessages, activeChatId, error];
}
