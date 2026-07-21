import 'package:equatable/equatable.dart';

abstract class StudentPaymentsState extends Equatable {
  const StudentPaymentsState();
  
  @override
  List<Object?> get props => [];
}

class StudentPaymentsInitial extends StudentPaymentsState {}

class StudentPaymentsLoading extends StudentPaymentsState {}

class StudentPaymentsLoaded extends StudentPaymentsState {
  final List<dynamic> payments;

  const StudentPaymentsLoaded(this.payments);

  @override
  List<Object?> get props => [payments];
}

class StudentPaymentsError extends StudentPaymentsState {
  final String message;

  const StudentPaymentsError(this.message);

  @override
  List<Object?> get props => [message];
}
