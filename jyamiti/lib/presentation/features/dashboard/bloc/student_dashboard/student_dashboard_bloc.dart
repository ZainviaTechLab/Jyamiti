import 'dart:convert';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../../../services/api_service.dart';
import 'student_dashboard_event.dart';
import 'student_dashboard_state.dart';

class StudentDashboardBloc extends Bloc<StudentDashboardEvent, StudentDashboardState> {
  StudentDashboardBloc() : super(StudentDashboardInitial()) {
    on<FetchStudentDashboardSummary>(_onFetchSummary);
  }

  Future<void> _onFetchSummary(FetchStudentDashboardSummary event, Emitter<StudentDashboardState> emit) async {
    emit(StudentDashboardLoading());
    try {
      final summaryData = await ApiService.fetchMyAttendanceSummary();
      emit(StudentDashboardLoaded(summaryData));
    } catch (e) {
      emit(StudentDashboardError(e.toString()));
    }
  }
}
