import 'dart:convert';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../../../services/api_service.dart';
import 'user_event.dart';
import 'user_state.dart';

class UserBloc extends Bloc<UserEvent, UserState> {
  int _currentPage = 1;
  bool _isFetching = false;

  UserBloc() : super(UserInitial()) {
    on<FetchUsers>(_onFetchUsers);
    on<CreateUser>(_onCreateUser);
    on<UpdateUser>(_onUpdateUser);
    on<DeleteUser>(_onDeleteUser);
  }

  Future<void> _onFetchUsers(FetchUsers event, Emitter<UserState> emit) async {
    if (_isFetching) return;
    _isFetching = true;

    try {
      List<dynamic> currentUsers = [];
      if (state is UserLoaded && !event.isRefresh) {
        currentUsers = (state as UserLoaded).users;
      }

      if (event.isRefresh) {
        _currentPage = 1;
        emit(UserLoading([], isFirstFetch: true));
      } else {
        _currentPage = event.page;
        emit(UserLoading(currentUsers, isFirstFetch: _currentPage == 1));
      }

      String url = '/users?page=$_currentPage&limit=${event.limit}';
      if (event.role != null && event.role!.isNotEmpty) {
        url += '&role=${event.role}';
      }

      final res = await ApiService.get(url);
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final List<dynamic> fetchedUsers = data['data'] ?? [];
        final bool hasMore = data['hasMore'] ?? false;

        if (event.isRefresh || _currentPage == 1) {
          emit(UserLoaded(fetchedUsers, hasMore));
        } else {
          emit(UserLoaded([...currentUsers, ...fetchedUsers], hasMore));
        }
      } else {
        emit(UserError('Failed to fetch users: ${res.statusCode}'));
      }
    } catch (e) {
      emit(UserError('Error fetching users: $e'));
    } finally {
      _isFetching = false;
    }
  }

  Future<void> _onCreateUser(CreateUser event, Emitter<UserState> emit) async {
    final currentState = state;
    try {
      final res = await ApiService.post('/users', {
        'name': event.name,
        'email': event.email,
        'role': event.role,
        'phone': event.phone,
      });

      if (res.statusCode == 201) {
        emit(const UserOperationSuccess('User created successfully. Credentials logged in backend!'));
      } else {
        final data = jsonDecode(res.body);
        emit(UserOperationFailure(data['message'] ?? 'Error creating user'));
      }
    } catch (e) {
      emit(UserOperationFailure('Error: $e'));
    }
    
    // Restore previous loaded state after emitting side effect
    if (currentState is UserLoaded) {
      emit(UserLoaded(currentState.users, currentState.hasMore));
    }
  }

  Future<void> _onUpdateUser(UpdateUser event, Emitter<UserState> emit) async {
    final currentState = state;
    try {
      final res = await ApiService.put('/users/${event.id}', {
        'name': event.name,
        'email': event.email,
        'phone': event.phone,
      });

      if (res.statusCode == 200) {
        emit(const UserOperationSuccess('User updated successfully!'));
      } else {
        final data = jsonDecode(res.body);
        emit(UserOperationFailure(data['message'] ?? 'Error updating user'));
      }
    } catch (e) {
      emit(UserOperationFailure('Error: $e'));
    }

    if (currentState is UserLoaded) {
      emit(UserLoaded(currentState.users, currentState.hasMore));
    }
  }

  Future<void> _onDeleteUser(DeleteUser event, Emitter<UserState> emit) async {
    final currentState = state;
    try {
      final res = await ApiService.delete('/users/${event.id}');
      if (res.statusCode == 200) {
        emit(const UserOperationSuccess('User deleted successfully'));
      } else {
        emit(const UserOperationFailure('Failed to delete user'));
      }
    } catch (e) {
      emit(UserOperationFailure('Error: $e'));
    }

    if (currentState is UserLoaded) {
      emit(UserLoaded(currentState.users, currentState.hasMore));
    }
  }
}
