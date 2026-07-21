import 'package:equatable/equatable.dart';

abstract class SchedulesEvent extends Equatable {
  const SchedulesEvent();

  @override
  List<Object?> get props => [];
}

class FetchSchedules extends SchedulesEvent {}

class SubmitLeaveRequest extends SchedulesEvent {
  final String scheduleId;
  final String reason;

  const SubmitLeaveRequest({required this.scheduleId, required this.reason});

  @override
  List<Object?> get props => [scheduleId, reason];
}

class UpdateLeaveRequestStatus extends SchedulesEvent {
  final String scheduleId;
  final String leaveId;
  final String status;

  UpdateLeaveRequestStatus({required this.scheduleId, required this.leaveId, required this.status});

  @override
  List<Object?> get props => [scheduleId, leaveId, status];
}

class MarkAttendance extends SchedulesEvent {
  final String scheduleId;
  final List<Map<String, dynamic>> attendanceData;

  const MarkAttendance({required this.scheduleId, required this.attendanceData});

  @override
  List<Object?> get props => [scheduleId, attendanceData];
}

class SubmitNoteUpload extends SchedulesEvent {
  final String batchId;
  final String sessionId;
  final String title;
  final String description;
  final List<int> fileBytes;
  final String fileName;

  const SubmitNoteUpload({
    required this.batchId,
    required this.sessionId,
    required this.title,
    required this.description,
    required this.fileBytes,
    required this.fileName,
  });

  @override
  List<Object?> get props => [batchId, sessionId, title, description, fileBytes, fileName];
}

class UpdateClassLink extends SchedulesEvent {
  final String batchId;
  final String link;

  const UpdateClassLink({required this.batchId, required this.link});

  @override
  List<Object?> get props => [batchId, link];
}

class CancelSchedule extends SchedulesEvent {
  final String scheduleId;

  const CancelSchedule({required this.scheduleId});

  @override
  List<Object?> get props => [scheduleId];
}

class PostponeSchedule extends SchedulesEvent {
  final String scheduleId;
  final String newDate; // ISO string

  const PostponeSchedule({required this.scheduleId, required this.newDate});

  @override
  List<Object?> get props => [scheduleId, newDate];
}
