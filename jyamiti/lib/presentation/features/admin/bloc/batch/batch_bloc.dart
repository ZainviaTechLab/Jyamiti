import 'dart:convert';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../../../services/api_service.dart';
import 'batch_event.dart';
import 'batch_state.dart';

class BatchBloc extends Bloc<BatchEvent, BatchState> {
  BatchBloc() : super(BatchInitial()) {
    on<FetchBatches>(_onFetchBatches);
    on<CreateBatch>(_onCreateBatch);
    on<UpdateBatch>(_onUpdateBatch);
    on<DeleteBatch>(_onDeleteBatch);
    on<AddStudentToBatch>(_onAddStudentToBatch);
    on<RemoveStudentFromBatch>(_onRemoveStudentFromBatch);
  }

  Future<void> _onFetchBatches(FetchBatches event, Emitter<BatchState> emit) async {
    emit(BatchLoading());
    try {
      final res = await ApiService.get('/batches');
      if (res.statusCode == 200) {
        final List<dynamic> batches = jsonDecode(res.body);
        emit(BatchLoaded(batches));
      } else {
        emit(BatchError('Failed to load batches: ${res.statusCode}'));
      }
    } catch (e) {
      emit(BatchError('Error fetching batches: $e'));
    }
  }

  Future<void> _onCreateBatch(CreateBatch event, Emitter<BatchState> emit) async {
    final currentState = state;
    try {
      final res = await ApiService.post('/batches', event.batchData);
      if (res.statusCode == 201) {
        emit(const BatchOperationSuccess('Batch created successfully'));
      } else {
        final data = jsonDecode(res.body);
        emit(BatchOperationFailure(data['message'] ?? 'Error creating batch'));
      }
    } catch (e) {
      emit(BatchOperationFailure('Error: $e'));
    }

    if (currentState is BatchLoaded) {
      emit(BatchLoaded(currentState.batches));
    }
  }

  Future<void> _onUpdateBatch(UpdateBatch event, Emitter<BatchState> emit) async {
    final currentState = state;
    try {
      final res = await ApiService.put('/batches/${event.id}', event.batchData);
      if (res.statusCode == 200) {
        emit(const BatchOperationSuccess('Batch updated successfully'));
      } else {
        final data = jsonDecode(res.body);
        emit(BatchOperationFailure(data['message'] ?? 'Error updating batch'));
      }
    } catch (e) {
      emit(BatchOperationFailure('Error: $e'));
    }

    if (currentState is BatchLoaded) {
      emit(BatchLoaded(currentState.batches));
    }
  }

  Future<void> _onDeleteBatch(DeleteBatch event, Emitter<BatchState> emit) async {
    final currentState = state;
    try {
      final res = await ApiService.delete('/batches/${event.id}');
      if (res.statusCode == 200) {
        emit(const BatchOperationSuccess('Batch deleted successfully'));
      } else {
        emit(const BatchOperationFailure('Failed to delete batch'));
      }
    } catch (e) {
      emit(BatchOperationFailure('Error: $e'));
    }

    if (currentState is BatchLoaded) {
      emit(BatchLoaded(currentState.batches));
    }
  }

  Future<void> _onAddStudentToBatch(AddStudentToBatch event, Emitter<BatchState> emit) async {
    final currentState = state;
    try {
      final res = await ApiService.post('/batches/${event.batchId}/students', {
        'studentId': event.studentId,
      });

      if (res.statusCode == 200) {
        emit(const BatchOperationSuccess('Student added to batch'));
      } else {
        final data = jsonDecode(res.body);
        emit(BatchOperationFailure(data['message'] ?? 'Failed to add student'));
      }
    } catch (e) {
      emit(BatchOperationFailure('Error: $e'));
    }

    if (currentState is BatchLoaded) {
      emit(BatchLoaded(currentState.batches));
    }
  }

  Future<void> _onRemoveStudentFromBatch(RemoveStudentFromBatch event, Emitter<BatchState> emit) async {
    final currentState = state;
    try {
      final res = await ApiService.delete('/batches/${event.batchId}/students/${event.studentId}');
      if (res.statusCode == 200) {
        emit(const BatchOperationSuccess('Student removed from batch'));
      } else {
        final data = jsonDecode(res.body);
        emit(BatchOperationFailure(data['message'] ?? 'Failed to remove student'));
      }
    } catch (e) {
      emit(BatchOperationFailure('Error: $e'));
    }

    if (currentState is BatchLoaded) {
      emit(BatchLoaded(currentState.batches));
    }
  }
}
