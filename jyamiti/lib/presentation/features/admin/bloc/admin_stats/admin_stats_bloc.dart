import 'dart:convert';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../../../services/api_service.dart';
import 'admin_stats_event.dart';
import 'admin_stats_state.dart';

class AdminStatsBloc extends Bloc<AdminStatsEvent, AdminStatsState> {
  AdminStatsBloc() : super(AdminStatsInitial()) {
    on<FetchAdminStats>(_onFetchAdminStats);
  }

  Future<void> _onFetchAdminStats(
    FetchAdminStats event,
    Emitter<AdminStatsState> emit,
  ) async {
    emit(AdminStatsLoading());
    try {
      final res = await ApiService.get('/stats/dashboard');
      if (res.statusCode == 200) {
        final Map<String, dynamic> stats = jsonDecode(res.body);
        emit(AdminStatsLoaded(stats));
      } else {
        emit(AdminStatsError('Failed to load stats: ${res.statusCode}'));
      }
    } catch (e) {
      emit(AdminStatsError('Error fetching stats: $e'));
    }
  }
}
