import 'package:equatable/equatable.dart';

abstract class SchedulesState extends Equatable {
  const SchedulesState();
  
  @override
  List<Object?> get props => [];
}

class SchedulesInitial extends SchedulesState {}

class SchedulesLoading extends SchedulesState {}

class SchedulesLoaded extends SchedulesState {
  final List<dynamic> schedules;
  final List<dynamic> attendances;
  final List<dynamic> leaveRequests;
  final List<dynamic> noteSubmissions;

  SchedulesLoaded({
    required this.schedules,
    required this.attendances,
    required this.leaveRequests,
    required this.noteSubmissions,
  });

  @override
  List<Object?> get props => [schedules, attendances, leaveRequests, noteSubmissions];
}

class SchedulesError extends SchedulesState {
  final String message;

  const SchedulesError(this.message);

  @override
  List<Object?> get props => [message];
}

class SchedulesActionSuccess extends SchedulesState {
  final String message;

  const SchedulesActionSuccess(this.message);

  @override
  List<Object?> get props => [message];
}

class SchedulesActionError extends SchedulesState {
  final String message;

  const SchedulesActionError(this.message);

  @override
  List<Object?> get props => [message];
}
