import 'dart:convert';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../../../services/api_service.dart';
import 'student_payments_event.dart';
import 'student_payments_state.dart';

class StudentPaymentsBloc extends Bloc<StudentPaymentsEvent, StudentPaymentsState> {
  StudentPaymentsBloc() : super(StudentPaymentsInitial()) {
    on<FetchStudentPayments>(_onFetchPayments);
  }

  Future<void> _onFetchPayments(FetchStudentPayments event, Emitter<StudentPaymentsState> emit) async {
    emit(StudentPaymentsLoading());
    try {
      final response = await ApiService.get('/payments/me');
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        emit(StudentPaymentsLoaded(data));
      } else {
        emit(StudentPaymentsError('Failed to load payments'));
      }
    } catch (e) {
      emit(StudentPaymentsError(e.toString()));
    }
  }
}
