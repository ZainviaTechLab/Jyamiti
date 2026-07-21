import 'dart:convert';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:jyamiti/providers/theme_provider.dart';
import 'package:provider/provider.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../../../providers/auth_provider.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../bloc/user/user_bloc.dart';
import '../bloc/user/user_event.dart';
import '../bloc/user/user_state.dart';
import 'user_role_list.dart';

// ==========================================
// USERS MANAGEMENT TAB
// ==========================================
class UsersTab extends StatefulWidget {
  const UsersTab({super.key});

  @override
  State<UsersTab> createState() => _UsersTabState();
}

class _UsersTabState extends State<UsersTab>
    with SingleTickerProviderStateMixin {
  int _refreshCounter = 0;
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(() {
      if (_tabController.indexIsChanging ||
          _tabController.animation?.value == _tabController.index) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _triggerRefresh() {
    setState(() {
      _refreshCounter++;
    });
  }

  void _createUser(String name, String email, String role, String phone) {
    context.read<UserBloc>().add(
      CreateUser(name: name, email: email, role: role, phone: phone),
    );
  }

  void _deleteUser(String id) {
    context.read<UserBloc>().add(DeleteUser(id));
  }

  void _updateUser(String id, String name, String email, String phone) {
    context.read<UserBloc>().add(
      UpdateUser(id: id, name: name, email: email, phone: phone),
    );
  }

  void _confirmDelete(
    BuildContext context,
    String itemName,
    VoidCallback onConfirm,
  ) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            bool isDeleting = false;
            return BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: AlertDialog(
                backgroundColor: context.isDark ? const Color(0xFF0F172A).withValues(alpha: 0.35) : Colors.white.withOpacity(0.95),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                  side: BorderSide(color: context.glassBorder, width: 1.5),
                ),
                title: Text(
                  'Delete $itemName?',
                  style: TextStyle(color: context.textColor),
                ),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Please type "$itemName" to confirm deletion.',
                      style: TextStyle(color: context.textColor70),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: controller,
                      style: TextStyle(color: context.textColor),
                      decoration: InputDecoration(
                        labelText: 'Confirm Name',
                        labelStyle: TextStyle(color: context.textColor54),
                        enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: context.glassBorder),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: Colors.redAccent),
                        ),
                      ),
                    ),
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: isDeleting ? null : () => Navigator.pop(ctx),
                    child: Text(
                      'Cancel',
                      style: TextStyle(color: context.textColor60),
                    ),
                  ),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.redAccent.withOpacity(0.8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onPressed: isDeleting
                        ? null
                        : () {
                            if (controller.text.trim() == itemName) {
                              setDialogState(() => isDeleting = true);
                              onConfirm();
                              Navigator.of(ctx).pop();
                            } else {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Name does not match!'),
                                  backgroundColor: Colors.orange,
                                ),
                              );
                            }
                          },
                    child: isDeleting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : Text(
                            'Delete',
                            style: TextStyle(color: context.textColor),
                          ),
                  ),
                ],
              ).animate().fade().scale(begin: const Offset(0.9, 0.9)),
            );
          },
        );
      },
    );
  }

  void _showEditUserDialog(Map<String, dynamic> user) {
    final formKey = GlobalKey<FormState>();
    final nameController = TextEditingController(text: user['name']);
    final emailController = TextEditingController(text: user['email']);
    final phoneController = TextEditingController(text: user['phone'] ?? '');

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            bool isSaving = false;
            return BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: AlertDialog(
                backgroundColor: context.isDark ? const Color(0xFF0F172A).withValues(alpha: 0.35) : Colors.white.withOpacity(0.95),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                  side: BorderSide(color: context.glassBorder, width: 1.5),
                ),
                title: Text(
                  'Edit User',
                  style: TextStyle(color: context.textColor),
                ),
                content: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextFormField(
                        controller: nameController,
                        style: TextStyle(color: context.textColor),
                        decoration: InputDecoration(
                          labelText: 'Name',
                          labelStyle: TextStyle(color: context.textColor70),
                        ),
                        validator: (v) =>
                            v == null || v.isEmpty ? 'Required' : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: emailController,
                        style: TextStyle(color: context.textColor),
                        decoration: InputDecoration(
                          labelText: 'Email',
                          labelStyle: TextStyle(color: context.textColor70),
                        ),
                        validator: (v) =>
                            v == null || v.isEmpty ? 'Required' : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: phoneController,
                        style: TextStyle(color: context.textColor),
                        decoration: InputDecoration(
                          labelText: 'Phone Number',
                          hintText: '+1 234 567 8900',
                          hintStyle: TextStyle(color: context.textColor54.withValues(alpha: 0.5)),
                          labelStyle: TextStyle(color: context.textColor70),
                        ),
                        keyboardType: TextInputType.phone,
                        validator: (v) {
                          if (v == null || v.isEmpty) return 'Required';
                          if (!v.trim().startsWith('+'))
                            return 'Must start with + and country code';
                          return null;
                        },
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: isSaving ? null : () => Navigator.pop(ctx),
                    child: Text(
                      'Cancel',
                      style: TextStyle(color: context.textColor60),
                    ),
                  ),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF6366F1).withOpacity(0.8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onPressed: isSaving
                        ? null
                        : () {
                            if (formKey.currentState!.validate()) {
                              setDialogState(() => isSaving = true);
                              _updateUser(
                                user['id'] ?? user['_id'],
                                nameController.text.trim(),
                                emailController.text.trim(),
                                phoneController.text.trim(),
                              );
                              Navigator.of(ctx).pop();
                            }
                          },
                    child: isSaving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : Text(
                            'Save',
                            style: TextStyle(color: context.textColor),
                          ),
                  ),
                ],
              ).animate().fade().scale(begin: const Offset(0.9, 0.9)),
            );
          },
        );
      },
    );
  }

  void _showAddUserDialog(String role) {
    final formKey = GlobalKey<FormState>();
    final nameController = TextEditingController();
    final emailController = TextEditingController();
    final phoneController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            bool isCreating = false;
            return BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: AlertDialog(
                backgroundColor: context.isDark ? const Color(0xFF0F172A).withValues(alpha: 0.35) : Colors.white.withOpacity(0.95),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                  side: BorderSide(color: context.glassBorder, width: 1.5),
                ),
                title: Text(
                  'Add New ${role[0].toUpperCase()}${role.substring(1).toLowerCase()}',
                  style: TextStyle(color: context.textColor),
                ),
                content: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextFormField(
                        controller: nameController,
                        style: TextStyle(color: context.textColor),
                        decoration: InputDecoration(
                          labelText: 'Name',
                          labelStyle: TextStyle(color: context.textColor70),
                        ),
                        validator: (v) =>
                            v == null || v.isEmpty ? 'Required' : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: emailController,
                        style: TextStyle(color: context.textColor),
                        decoration: InputDecoration(
                          labelText: 'Email',
                          labelStyle: TextStyle(color: context.textColor70),
                        ),
                        validator: (v) =>
                            v == null || v.isEmpty ? 'Required' : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: phoneController,
                        style: TextStyle(color: context.textColor),
                        decoration: InputDecoration(
                          labelText: 'Phone Number',
                          hintText: '+1 234 567 8900',
                          hintStyle: TextStyle(color: context.textColor54.withValues(alpha: 0.5)),
                          labelStyle: TextStyle(color: context.textColor70),
                        ),
                        keyboardType: TextInputType.phone,
                        validator: (v) {
                          if (v == null || v.isEmpty) return 'Required';
                          if (!v.trim().startsWith('+'))
                            return 'Must start with + and country code';
                          return null;
                        },
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: isCreating ? null : () => Navigator.pop(ctx),
                    child: Text(
                      'Cancel',
                      style: TextStyle(color: context.textColor60),
                    ),
                  ),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF6366F1).withOpacity(0.8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onPressed: isCreating
                        ? null
                        : () {
                            if (formKey.currentState!.validate()) {
                              setDialogState(() => isCreating = true);
                              _createUser(
                                nameController.text.trim(),
                                emailController.text.trim(),
                                role,
                                phoneController.text.trim(),
                              );
                              Navigator.of(ctx).pop();
                            }
                          },
                    child: isCreating
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : Text(
                            'Create',
                            style: TextStyle(color: context.textColor),
                          ),
                  ),
                ],
              ).animate().fade().scale(begin: const Offset(0.9, 0.9)),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final roles = ['STUDENT', 'TUTOR', 'MENTOR', 'ADMIN'];
    final roleNames = ['Student', 'Tutor', 'Mentor', 'Admin'];
    final currentRole = roles[_tabController.index];
    final currentRoleName = roleNames[_tabController.index];

    return BlocListener<UserBloc, UserState>(
      listener: (context, state) {
        if (state is UserOperationSuccess) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(state.message),
              backgroundColor: Colors.green,
            ),
          );
          _triggerRefresh();
        } else if (state is UserOperationFailure) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(state.message),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
      },
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Column(
          children: [
            Container(
              color: Colors.white.withOpacity(0.02),
              child: TabBar(
                controller: _tabController,
                indicatorColor: const Color(0xFF6366F1),
                labelColor: context.textColor,
                unselectedLabelColor: context.textColor60,
                indicatorWeight: 3,
                tabs: [
                  Tab(text: 'Students'),
                  Tab(text: 'Tutors'),
                  Tab(text: 'Mentors'),
                  Tab(text: 'Admins'),
                ],
              ),
            ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  UserRoleList(
                    role: 'STUDENT',
                    refreshCounter: _refreshCounter,
                    onEdit: _showEditUserDialog,
                    onDelete: (id, name) =>
                        _confirmDelete(context, name, () => _deleteUser(id)),
                  ),
                  UserRoleList(
                    role: 'TUTOR',
                    refreshCounter: _refreshCounter,
                    onEdit: _showEditUserDialog,
                    onDelete: (id, name) =>
                        _confirmDelete(context, name, () => _deleteUser(id)),
                  ),
                  UserRoleList(
                    role: 'MENTOR',
                    refreshCounter: _refreshCounter,
                    onEdit: _showEditUserDialog,
                    onDelete: (id, name) =>
                        _confirmDelete(context, name, () => _deleteUser(id)),
                  ),
                  UserRoleList(
                    role: 'ADMIN',
                    refreshCounter: _refreshCounter,
                    onEdit: _showEditUserDialog,
                    onDelete: (id, name) =>
                        _confirmDelete(context, name, () => _deleteUser(id)),
                  ),
                ],
              ),
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          backgroundColor: const Color(0xFF6366F1),
          onPressed: () => _showAddUserDialog(currentRole),
          icon: const Icon(Icons.person_add_rounded, color: Colors.white),
          label: Text(
            'Add $currentRoleName',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
        ).animate().scale(delay: 500.ms),
      ),
    );
  }
}
