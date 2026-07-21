import 'package:equatable/equatable.dart';

abstract class BatchEvent extends Equatable {
  const BatchEvent();

  @override
  List<Object?> get props => [];
}

class FetchBatches extends BatchEvent {}

class CreateBatch extends BatchEvent {
  final Map<String, dynamic> batchData;

  const CreateBatch(this.batchData);

  @override
  List<Object?> get props => [batchData];
}

class UpdateBatch extends BatchEvent {
  final String id;
  final Map<String, dynamic> batchData;

  const UpdateBatch(this.id, this.batchData);

  @override
  List<Object?> get props => [id, batchData];
}

class DeleteBatch extends BatchEvent {
  final String id;

  const DeleteBatch(this.id);

  @override
  List<Object?> get props => [id];
}

class AddStudentToBatch extends BatchEvent {
  final String batchId;
  final String studentId;

  const AddStudentToBatch({required this.batchId, required this.studentId});

  @override
  List<Object?> get props => [batchId, studentId];
}

class RemoveStudentFromBatch extends BatchEvent {
  final String batchId;
  final String studentId;

  const RemoveStudentFromBatch({required this.batchId, required this.studentId});

  @override
  List<Object?> get props => [batchId, studentId];
}
