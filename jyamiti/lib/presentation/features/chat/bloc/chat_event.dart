import 'package:equatable/equatable.dart';
import '../models/chat_model.dart';

abstract class ChatEvent extends Equatable {
  const ChatEvent();

  @override
  List<Object?> get props => [];
}

class ConnectSocket extends ChatEvent {
  final String userId;
  const ConnectSocket(this.userId);
}

class DisconnectSocket extends ChatEvent {}

class LoadChats extends ChatEvent {}

class LoadMessages extends ChatEvent {
  final String chatId;
  const LoadMessages(this.chatId);
}

class SendMessage extends ChatEvent {
  final String chatId;
  final String content;
  const SendMessage({required this.chatId, required this.content});
}

class ReceiveMessage extends ChatEvent {
  final ChatMessage message;
  const ReceiveMessage(this.message);
}

class MarkChatAsRead extends ChatEvent {
  final String chatId;
  const MarkChatAsRead(this.chatId);
}
