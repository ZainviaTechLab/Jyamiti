import 'package:equatable/equatable.dart';

abstract class BatchEvent extends Equatable {
  const BatchEvent();

  @override
  List<Object?> get props => [];
}

/// Fetches page 1, replacing whatever batches were previously loaded.
/// [search] is resolved server-side (matches batch name, course, tutor,
/// mentor, or category name) so it searches the *whole* dataset, not just
/// whatever page happens to be loaded on the client.
class FetchBatches extends BatchEvent {
  final String search;

  const FetchBatches({this.search = ''});

  @override
  List<Object?> get props => [search];
}

/// Fetches the next page and appends it to the currently loaded batches.
/// No-ops (via the bloc) if there's no next page or a load is already in
/// flight.
class LoadMoreBatches extends BatchEvent {}

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
