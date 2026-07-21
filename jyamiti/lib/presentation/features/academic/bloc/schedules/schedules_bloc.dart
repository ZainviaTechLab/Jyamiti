import 'dart:convert';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../../../services/api_service.dart';
import 'schedules_event.dart';
import 'schedules_state.dart';

class SchedulesBloc extends Bloc<SchedulesEvent, SchedulesState> {
  SchedulesBloc() : super(SchedulesInitial()) {
    on<FetchSchedules>(_onFetchSchedules);
    on<SubmitLeaveRequest>(_onSubmitLeaveRequest);
    on<UpdateLeaveRequestStatus>(_onUpdateLeaveRequestStatus);
    on<MarkAttendance>(_onMarkAttendance);
    on<SubmitNoteUpload>(_onSubmitNoteUpload);
    on<UpdateClassLink>(_onUpdateClassLink);
    on<CancelSchedule>(_onCancelSchedule);
    on<PostponeSchedule>(_onPostponeSchedule);
  }

  Future<void> _onFetchSchedules(FetchSchedules event, Emitter<SchedulesState> emit) async {
    emit(SchedulesLoading());
    try {
      final res = await ApiService.get('/schedules/my-schedules');
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        emit(SchedulesLoaded(
          schedules: data['schedules'] ?? [],
          attendances: data['attendances'] ?? [],
          leaveRequests: data['leaveRequests'] ?? [],
          noteSubmissions: data['noteSubmissions'] ?? [],
        ));
      } else {
        emit(SchedulesError('Failed to fetch schedules'));
      }
    } catch (e) {
      emit(SchedulesError(e.toString()));
    }
  }

  Future<void> _onSubmitLeaveRequest(SubmitLeaveRequest event, Emitter<SchedulesState> emit) async {
    try {
      final res = await ApiService.post('/schedules/${event.scheduleId}/leave', {
        'reason': event.reason,
      });
      if (res.statusCode == 201) {
        emit(SchedulesActionSuccess('Leave request submitted successfully'));
        add(FetchSchedules());
      } else {
        final data = jsonDecode(res.body);
        emit(SchedulesActionError(data['message'] ?? 'Failed to submit leave request'));
        add(FetchSchedules()); // refresh to go back to loaded state
      }
    } catch (e) {
      emit(SchedulesActionError(e.toString()));
      add(FetchSchedules());
    }
  }

  Future<void> _onUpdateLeaveRequestStatus(UpdateLeaveRequestStatus event, Emitter<SchedulesState> emit) async {
    try {
      final res = await ApiService.put('/schedules/${event.scheduleId}/leave/${event.leaveId}', {
        'status': event.status,
      });
      if (res.statusCode == 200) {
        emit(SchedulesActionSuccess('Leave request ${event.status.toLowerCase()}'));
        add(FetchSchedules());
      } else {
        final data = jsonDecode(res.body);
        emit(SchedulesActionError(data['message'] ?? 'Failed to update leave request'));
        add(FetchSchedules());
      }
    } catch (e) {
      emit(SchedulesActionError(e.toString()));
      add(FetchSchedules());
    }
  }

  Future<void> _onMarkAttendance(MarkAttendance event, Emitter<SchedulesState> emit) async {
    try {
      final res = await ApiService.put('/schedules/${event.scheduleId}/attendance', {
        'attendanceData': event.attendanceData,
      });
      if (res.statusCode == 200) {
        emit(SchedulesActionSuccess('Attendance marked successfully'));
        add(FetchSchedules());
      } else {
        emit(SchedulesActionError('Failed to mark attendance'));
        add(FetchSchedules());
      }
    } catch (e) {
      emit(SchedulesActionError(e.toString()));
      add(FetchSchedules());
    }
  }

  Future<void> _onSubmitNoteUpload(SubmitNoteUpload event, Emitter<SchedulesState> emit) async {
    try {
      final fields = {
        'batchId': event.batchId,
        'sessionId': event.sessionId,
        'title': event.title,
        'description': event.description,
      };
      
      final res = await ApiService.uploadWorksheet(
        '/notes/student-upload', 
        fields, 
        event.fileBytes, 
        event.fileName
      );
      
      if (res.statusCode == 201) {
        emit(SchedulesActionSuccess('Note uploaded successfully'));
        add(FetchSchedules());
      } else {
        emit(SchedulesActionError('Failed to upload note'));
        add(FetchSchedules());
      }
    } catch (e) {
      emit(SchedulesActionError(e.toString()));
      add(FetchSchedules());
    }
  }

  Future<void> _onUpdateClassLink(UpdateClassLink event, Emitter<SchedulesState> emit) async {
    try {
      final res = await ApiService.put('/batches/${event.batchId}/link', {
        'classLink': event.link,
      });
      if (res.statusCode == 200) {
        emit(SchedulesActionSuccess('Class link updated'));
        add(FetchSchedules());
      } else {
        final data = jsonDecode(res.body);
        emit(SchedulesActionError(data['message'] ?? 'Failed to update link'));
        add(FetchSchedules());
      }
    } catch (e) {
      emit(SchedulesActionError(e.toString()));
      add(FetchSchedules());
    }
  }

  Future<void> _onCancelSchedule(CancelSchedule event, Emitter<SchedulesState> emit) async {
    try {
      final res = await ApiService.put('/schedules/${event.scheduleId}/cancel', {});
      if (res.statusCode == 200) {
        emit(SchedulesActionSuccess('Schedule cancelled successfully'));
        add(FetchSchedules());
      } else {
        final data = jsonDecode(res.body);
        emit(SchedulesActionError(data['message'] ?? 'Failed to cancel schedule'));
        add(FetchSchedules());
      }
    } catch (e) {
      emit(SchedulesActionError(e.toString()));
      add(FetchSchedules());
    }
  }

  Future<void> _onPostponeSchedule(PostponeSchedule event, Emitter<SchedulesState> emit) async {
    try {
      final res = await ApiService.post('/schedules/${event.scheduleId}/postpone', {
        'newDate': event.newDate,
      });
      if (res.statusCode == 200) {
        emit(SchedulesActionSuccess('Schedule postponed successfully'));
        add(FetchSchedules());
      } else {
        final data = jsonDecode(res.body);
        emit(SchedulesActionError(data['message'] ?? 'Failed to postpone schedule'));
        add(FetchSchedules());
      }
    } catch (e) {
      emit(SchedulesActionError(e.toString()));
      add(FetchSchedules());
    }
  }
}

