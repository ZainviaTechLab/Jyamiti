import 'package:equatable/equatable.dart';

abstract class UserEvent extends Equatable {
  const UserEvent();

  @override
  List<Object?> get props => [];
}

class FetchUsers extends UserEvent {
  final String? role;
  final int page;
  final int limit;
  final bool isRefresh;

  const FetchUsers({
    this.role,
    this.page = 1,
    this.limit = 10,
    this.isRefresh = false,
  });

  @override
  List<Object?> get props => [role, page, limit, isRefresh];
}

class CreateUser extends UserEvent {
  final String name;
  final String email;
  final String role;
  final String phone;

  const CreateUser({
    required this.name,
    required this.email,
    required this.role,
    required this.phone,
  });

  @override
  List<Object?> get props => [name, email, role, phone];
}

class UpdateUser extends UserEvent {
  final String id;
  final String name;
  final String email;
  final String phone;

  const UpdateUser({
    required this.id,
    required this.name,
    required this.email,
    required this.phone,
  });

  @override
  List<Object?> get props => [id, name, email, phone];
}

class DeleteUser extends UserEvent {
  final String id;

  const DeleteUser(this.id);

  @override
  List<Object?> get props => [id];
}
