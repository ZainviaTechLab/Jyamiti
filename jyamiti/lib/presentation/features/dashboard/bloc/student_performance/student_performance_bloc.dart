import 'dart:convert';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../../../services/api_service.dart';
import 'student_performance_event.dart';
import 'student_performance_state.dart';

class StudentPerformanceBloc extends Bloc<StudentPerformanceEvent, StudentPerformanceState> {
  StudentPerformanceBloc() : super(StudentPerformanceInitial()) {
    on<FetchStudentPerformance>(_onFetchPerformance);
  }

  Future<void> _onFetchPerformance(FetchStudentPerformance event, Emitter<StudentPerformanceState> emit) async {
    emit(StudentPerformanceLoading());
    try {
      final response = await ApiService.get('/exams/performance');
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        emit(StudentPerformanceLoaded(data));
      } else {
        emit(StudentPerformanceError('Failed to load performance data'));
      }
    } catch (e) {
      emit(StudentPerformanceError(e.toString()));
    }
  }
}
