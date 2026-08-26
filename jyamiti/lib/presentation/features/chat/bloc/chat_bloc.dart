import 'dart:convert';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import '../../../../services/api_service.dart';
import '../models/chat_model.dart';
import 'chat_event.dart';
import 'chat_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ChatBloc extends Bloc<ChatEvent, ChatState> {
  IO.Socket? socket;
  String? currentUserId;

  ChatBloc() : super(const ChatState()) {
    on<ConnectSocket>(_onConnectSocket);
    on<DisconnectSocket>(_onDisconnectSocket);
    on<LoadChats>(_onLoadChats);
    on<LoadMessages>(_onLoadMessages);
    on<SendMessage>(_onSendMessage);
    on<ReceiveMessage>(_onReceiveMessage);
    on<MarkChatAsRead>(_onMarkChatAsRead);
  }

  void _onConnectSocket(ConnectSocket event, Emitter<ChatState> emit) {
    if (socket != null && socket!.connected) {
      if (currentUserId == event.userId) {
        return;
      }
      socket!.disconnect();
    }

    currentUserId = event.userId;
    final serverUrl = ApiService.serverBaseUrl;

    socket = IO.io(serverUrl, <String, dynamic>{
      'transports': ['websocket'],
      'autoConnect': false,
      'forceNew': true,
    });

    socket!.clearListeners();

    socket!.onConnect((_) {
      print('Socket Connected');
      socket!.emit('setup', event.userId);
    });

    socket!.onConnectError((err) => print('Socket Connect Error: $err'));
    socket!.onError((err) => print('Socket Error: $err'));

    socket!.on('message_received', (data) {
      final msg = ChatMessage.fromJson(data);
      add(ReceiveMessage(msg));
    });

    socket!.on('new_message_notification', (data) {
      // Background notification update logic
      final chatId = data['chatId'];
      final msg = ChatMessage.fromJson(data['message']);
      
      // Update chat list if we are not actively in that chat room
      if (state.activeChatId != chatId) {
        add(LoadChats());
      }
    });
  }

  void _onDisconnectSocket(DisconnectSocket event, Emitter<ChatState> emit) {
    socket?.disconnect();
    socket = null;
    currentUserId = null;
    emit(const ChatState());
  }

  Future<void> _onLoadChats(LoadChats event, Emitter<ChatState> emit) async {
    if (currentUserId == null) return;
    
    emit(state.copyWith(isLoading: true, error: null));
    try {
      final response = await ApiService.get('/chats');
      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        final chats = data.map((json) => Chat.fromJson(json, currentUserId!)).toList();
        emit(state.copyWith(isLoading: false, chats: chats));
      } else {
        emit(state.copyWith(isLoading: false, error: 'Failed to load chats'));
      }
    } catch (e) {
      emit(state.copyWith(isLoading: false, error: e.toString()));
    }
  }

  Future<void> _onLoadMessages(LoadMessages event, Emitter<ChatState> emit) async {
    emit(state.copyWith(isLoading: true, activeChatId: event.chatId, error: null));
    try {
      final response = await ApiService.get('/chats/${event.chatId}/messages');
      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        final messages = data.map((json) => ChatMessage.fromJson(json)).toList();
        
        socket?.emit('join_chat', event.chatId);
        
        emit(state.copyWith(isLoading: false, activeMessages: messages));
      } else {
        emit(state.copyWith(isLoading: false, error: 'Failed to load messages'));
      }
    } catch (e) {
      emit(state.copyWith(isLoading: false, error: e.toString()));
    }
  }

  void _onSendMessage(SendMessage event, Emitter<ChatState> emit) {
    if (socket == null || currentUserId == null) return;

    socket!.emit('new_message', {
      'chatId': event.chatId,
      'senderId': currentUserId,
      'content': event.content,
    });
  }

  void _onReceiveMessage(ReceiveMessage event, Emitter<ChatState> emit) {
    if (state.activeChatId == event.message.chatId) {
      final updatedMessages = List<ChatMessage>.from(state.activeMessages)..add(event.message);
      emit(state.copyWith(activeMessages: updatedMessages));
      // Reorder chat list
      add(LoadChats());
    }
  }

  Future<void> _onMarkChatAsRead(MarkChatAsRead event, Emitter<ChatState> emit) async {
    // Calling load messages intrinsically marks the chat as read on backend
    add(LoadChats());
  }

  @override
  Future<void> close() {
    socket?.dispose();
    return super.close();
  }
}
