import 'package:equatable/equatable.dart';

abstract class StudentPerformanceEvent extends Equatable {
  const StudentPerformanceEvent();

  @override
  List<Object?> get props => [];
}

class FetchStudentPerformance extends StudentPerformanceEvent {}
