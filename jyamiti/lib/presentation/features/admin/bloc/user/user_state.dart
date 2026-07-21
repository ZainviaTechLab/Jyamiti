import 'package:equatable/equatable.dart';

abstract class UserState extends Equatable {
  const UserState();
  
  @override
  List<Object?> get props => [];
}

class UserInitial extends UserState {}

class UserLoading extends UserState {
  final List<dynamic> oldUsers;
  final bool isFirstFetch;

  const UserLoading(this.oldUsers, {this.isFirstFetch = false});

  @override
  List<Object?> get props => [oldUsers, isFirstFetch];
}

class UserLoaded extends UserState {
  final List<dynamic> users;
  final bool hasMore;

  const UserLoaded(this.users, this.hasMore);

  @override
  List<Object?> get props => [users, hasMore];
}

class UserError extends UserState {
  final String message;

  const UserError(this.message);

  @override
  List<Object?> get props => [message];
}

// Side effect states for CRUD operations
class UserOperationSuccess extends UserState {
  final String message;
  const UserOperationSuccess(this.message);
  @override
  List<Object?> get props => [message];
}

class UserOperationFailure extends UserState {
  final String message;
  const UserOperationFailure(this.message);
  @override
  List<Object?> get props => [message];
}
