import 'package:equatable/equatable.dart';

abstract class StudentDashboardEvent extends Equatable {
  const StudentDashboardEvent();

  @override
  List<Object?> get props => [];
}

class FetchStudentDashboardSummary extends StudentDashboardEvent {}
