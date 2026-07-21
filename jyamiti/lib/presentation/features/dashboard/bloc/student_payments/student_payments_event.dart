import 'package:equatable/equatable.dart';

abstract class StudentPaymentsEvent extends Equatable {
  const StudentPaymentsEvent();

  @override
  List<Object?> get props => [];
}

class FetchStudentPayments extends StudentPaymentsEvent {}
