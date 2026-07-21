import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:jyamiti/providers/theme_provider.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import '../../../../providers/auth_provider.dart';
import '../bloc/chat_bloc.dart';
import '../bloc/chat_event.dart';
import '../bloc/chat_state.dart';
import 'chat_detail_screen.dart';
import 'package:intl/intl.dart';

class ChatListScreen extends StatefulWidget {
  final bool isInline;
  const ChatListScreen({super.key, this.isInline = false});

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> {
  @override
  void initState() {
    super.initState();
    final auth = Provider.of<AuthProvider>(context, listen: false);
    if (auth.userId != null) {
      context.read<ChatBloc>().add(ConnectSocket(auth.userId!));
      context.read<ChatBloc>().add(LoadChats());
    }
  }

  String _formatTime(DateTime? time) {
    if (time == null) return '';
    return DateFormat('hh:mm a').format(time.toLocal());
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = Provider.of<AuthProvider>(context, listen: false).userId;

    return Scaffold(
      backgroundColor: widget.isInline ? Colors.transparent : (context.isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9)),
      appBar: widget.isInline
          ? null
          : AppBar(
              title: const Text(
                'Communications',
                style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1),
              ).animate().fade().slideY(),
              backgroundColor: Colors.transparent,
              elevation: 0,
              centerTitle: true,
            ),
      body: BlocBuilder<ChatBloc, ChatState>(
        builder: (context, state) {
          if (state.isLoading && state.chats.isEmpty) {
            return const Center(child: CircularProgressIndicator(color: Colors.blueAccent));
          }

          if (state.error != null && state.chats.isEmpty) {
            return Center(child: Text(state.error!, style: const TextStyle(color: Colors.redAccent)));
          }

          if (state.chats.isEmpty) {
            return Center(
              child: Text(
                'No conversations yet.',
                style: TextStyle(color: context.textColor60, fontSize: 16),
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            itemCount: state.chats.length,
            itemBuilder: (context, index) {
              final chat = state.chats[index];
              
              // Determine Chat Name
              String chatName = chat.name ?? 'Chat';
              if (chat.type == 'direct') {
                final otherUser = chat.participants.firstWhere(
                  (p) => p['_id'] != currentUserId,
                  orElse: () => {'name': 'Unknown'},
                );
                chatName = otherUser['name'] ?? 'Unknown';
              }

              // Latest Message logic
              String latestMessageContent = 'Start a conversation...';
              String latestMessageTime = '';
              if (chat.latestMessage != null) {
                latestMessageContent = chat.latestMessage!['content'];
                latestMessageTime = _formatTime(DateTime.tryParse(chat.latestMessage!['createdAt']));
              }

              final bool hasUnread = chat.unreadCount > 0;

              return Padding(
                padding: const EdgeInsets.only(bottom: 12.0),
                child: GestureDetector(
                  onTap: () {
                    context.read<ChatBloc>().add(LoadMessages(chat.id));
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ChatDetailScreen(chatId: chat.id, chatName: chatName),
                      ),
                    );
                  },
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: context.isDark ? const Color(0xFF1E293B) : Colors.white.withOpacity(0.6),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: hasUnread 
                                ? const Color(0xFF00F0FF).withOpacity(0.5) 
                                : context.glassBorder,
                            width: hasUnread ? 1.5 : 1,
                          ),
                          boxShadow: hasUnread
                              ? [
                                  BoxShadow(
                                    color: const Color(0xFF00F0FF).withOpacity(0.2),
                                    blurRadius: 10,
                                    spreadRadius: 1,
                                  )
                                ]
                              : [],
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 50,
                              height: 50,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: LinearGradient(
                                  colors: chat.type == 'group' 
                                      ? [const Color(0xFF8B5CF6), const Color(0xFFEC4899)]
                                      : [const Color(0xFF3B82F6), const Color(0xFF2DD4BF)],
                                ),
                              ),
                              child: Center(
                                child: Text(
                                  chatName.isNotEmpty ? chatName[0].toUpperCase() : 'C',
                                  style: TextStyle(color: context.textColor, fontWeight: FontWeight.bold,
                                    fontSize: 20,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Expanded(
                                        child: Text(
                                          chatName,
                                          style: TextStyle(color: context.textColor, fontWeight: FontWeight.bold,
                                            fontSize: 16,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      Text(
                                        latestMessageTime,
                                        style: TextStyle(
                                          color: hasUnread ? const Color(0xFF00F0FF) : Colors.white54,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          latestMessageContent,
                                          style: TextStyle(
                                            color: hasUnread ? Colors.white : Colors.white54,
                                            fontWeight: hasUnread ? FontWeight.w600 : FontWeight.normal,
                                            fontSize: 14,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      if (hasUnread)
                                        Container(
                                          margin: const EdgeInsets.only(left: 8),
                                          padding: const EdgeInsets.all(6),
                                          decoration: const BoxDecoration(
                                            color: Color(0xFF00F0FF),
                                            shape: BoxShape.circle,
                                          ),
                                          child: Text(
                                            '${chat.unreadCount}',
                                            style: const TextStyle(
                                              color: Colors.black,
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ).animate().fade(duration: 300.ms).slideX(begin: 0.1, end: 0),
              );
            },
          );
        },
      ),
    );
  }
}
