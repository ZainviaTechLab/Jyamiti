import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:jyamiti/providers/theme_provider.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import '../bloc/user/user_bloc.dart';
import '../bloc/user/user_event.dart';
import '../bloc/user/user_state.dart';

class UserRoleList extends StatefulWidget {
  final String role;
  final int refreshCounter;
  final Function(Map<String, dynamic>) onEdit;
  final Function(String, String) onDelete;

  const UserRoleList({
    super.key,
    required this.role,
    required this.refreshCounter,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  State<UserRoleList> createState() => _UserRoleListState();
}

class _UserRoleListState extends State<UserRoleList> {
  final ScrollController _scrollController = ScrollController();
  late UserBloc _userBloc;
  int _page = 1;

  @override
  void initState() {
    super.initState();
    _userBloc = UserBloc()..add(FetchUsers(role: widget.role, page: 1, limit: 20));
    _scrollController.addListener(_onScroll);
  }

  @override
  void didUpdateWidget(UserRoleList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshCounter != widget.refreshCounter) {
      _page = 1;
      _userBloc.add(FetchUsers(role: widget.role, page: 1, limit: 20, isRefresh: true));
    }
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
      final state = _userBloc.state;
      if (state is UserLoaded && state.hasMore) {
        _page++;
        _userBloc.add(FetchUsers(role: widget.role, page: _page, limit: 20));
      }
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _userBloc.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider.value(
      value: _userBloc,
      child: BlocBuilder<UserBloc, UserState>(
        builder: (context, state) {
          if (state is UserInitial || (state is UserLoading && state.isFirstFetch)) {
            return const Center(child: CircularProgressIndicator(color: Color(0xFF6366F1)));
          }

          if (state is UserError) {
            return Center(child: Text(state.message, style: const TextStyle(color: Colors.redAccent)));
          }

          List<dynamic> users = [];
          bool hasMore = false;

          if (state is UserLoaded) {
            users = state.users;
            hasMore = state.hasMore;
          } else if (state is UserLoading) {
            users = state.oldUsers;
            hasMore = true; // assume has more while loading next page
          }

          if (users.isEmpty) {
            return Center(child: Text('No users found', style: TextStyle(color: context.textColor70)));
          }

          return ListView.builder(
            controller: _scrollController,
            padding: EdgeInsets.only(top: 24, left: 16, right: 16, bottom: 100),
            itemCount: users.length + (hasMore ? 1 : 0),
            itemBuilder: (ctx, idx) {
              if (idx == users.length) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Center(child: CircularProgressIndicator(color: Color(0xFF6366F1))),
                );
              }

              final user = users[idx];
              Color roleColor = const Color(0xFF3B82F6);
              if (user['role'] == 'TUTOR') roleColor = const Color(0xFFF59E0B);
              if (user['role'] == 'MENTOR') roleColor = const Color(0xFF10B981);
              if (user['role'] == 'ADMIN') roleColor = Colors.redAccent;

              final animationDelay = (idx % 10) * 50;

              return Container(
                margin: EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: context.glassBg,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: roleColor.withOpacity(0.3)),
                  boxShadow: [
                    BoxShadow(color: roleColor.withOpacity(0.05), blurRadius: 10, spreadRadius: 0),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                    child: Material(
                      type: MaterialType.transparency,
                      child: Slidable(
                        key: ValueKey(user['id'] ?? user['_id']),
                        endActionPane: ActionPane(
                          motion: const DrawerMotion(),
                          extentRatio: 0.45,
                          children: [
                            SlidableAction(
                              onPressed: (context) => widget.onEdit(user),
                              backgroundColor: Colors.blueAccent.withOpacity(0.15),
                              foregroundColor: Colors.blueAccent,
                              icon: Icons.edit_outlined,
                              label: 'Edit',
                            ),
                            SlidableAction(
                              onPressed: (context) => widget.onDelete(user['id'] ?? user['_id'], user['name']),
                              backgroundColor: Colors.redAccent.withOpacity(0.15),
                              foregroundColor: Colors.redAccent,
                              icon: Icons.delete_outline_rounded,
                              label: 'Delete',
                            ),
                          ],
                        ),
                        child: ListTile(
                          contentPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                          leading: CircleAvatar(
                            radius: 24,
                            backgroundColor: roleColor.withOpacity(0.15),
                            child: Text(
                              user['role'][0],
                              style: TextStyle(color: roleColor, fontWeight: FontWeight.bold, fontSize: 18),
                            ),
                          ),
                          title: Text(user['name'], style: TextStyle(color: context.textColor, fontWeight: FontWeight.bold, fontSize: 16)),
                          subtitle: Padding(
                            padding: EdgeInsets.only(top: 8.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(user['phone']?.toString() ?? 'No phone number', style: TextStyle(color: context.textColor70, fontSize: 13)),    
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ).animate().fade(duration: 400.ms, delay: animationDelay.ms).slideX(begin: 0.1, end: 0);
            },
          );
        },
      ),
    );
  }
}
