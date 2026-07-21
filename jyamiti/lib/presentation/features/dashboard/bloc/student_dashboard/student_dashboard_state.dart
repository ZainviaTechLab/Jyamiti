import 'package:equatable/equatable.dart';

abstract class StudentDashboardState extends Equatable {
  const StudentDashboardState();
  
  @override
  List<Object?> get props => [];
}

class StudentDashboardInitial extends StudentDashboardState {}

class StudentDashboardLoading extends StudentDashboardState {}

class StudentDashboardLoaded extends StudentDashboardState {
  final Map<String, dynamic> summaryData;

  const StudentDashboardLoaded(this.summaryData);

  @override
  List<Object?> get props => [summaryData];
}

class StudentDashboardError extends StudentDashboardState {
  final String message;

  const StudentDashboardError(this.message);

  @override
  List<Object?> get props => [message];
}
