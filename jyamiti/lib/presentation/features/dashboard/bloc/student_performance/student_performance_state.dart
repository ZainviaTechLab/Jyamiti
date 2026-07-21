import 'package:equatable/equatable.dart';

abstract class StudentPerformanceState extends Equatable {
  const StudentPerformanceState();
  
  @override
  List<Object?> get props => [];
}

class StudentPerformanceInitial extends StudentPerformanceState {}

class StudentPerformanceLoading extends StudentPerformanceState {}

class StudentPerformanceLoaded extends StudentPerformanceState {
  final Map<String, dynamic> performanceData;

  const StudentPerformanceLoaded(this.performanceData);

  @override
  List<Object?> get props => [performanceData];
}

class StudentPerformanceError extends StudentPerformanceState {
  final String message;

  const StudentPerformanceError(this.message);

  @override
  List<Object?> get props => [message];
}
