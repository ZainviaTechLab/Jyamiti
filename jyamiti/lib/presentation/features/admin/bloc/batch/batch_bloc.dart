import 'dart:convert';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../../../services/api_service.dart';
import 'batch_event.dart';
import 'batch_state.dart';

class BatchBloc extends Bloc<BatchEvent, BatchState> {
  static const int _pageSize = 30;

  BatchBloc() : super(BatchInitial()) {
    on<FetchBatches>(_onFetchBatches);
    on<LoadMoreBatches>(_onLoadMoreBatches);
    on<CreateBatch>(_onCreateBatch);
    on<UpdateBatch>(_onUpdateBatch);
    on<DeleteBatch>(_onDeleteBatch);
    on<AddStudentToBatch>(_onAddStudentToBatch);
    on<RemoveStudentFromBatch>(_onRemoveStudentFromBatch);
  }

  String _pagePath(int page, String search) {
    final query = {
      'page': '$page',
      'limit': '$_pageSize',
      if (search.isNotEmpty) 'search': search,
    };
    final queryString = query.entries
        .map((e) => '${e.key}=${Uri.encodeQueryComponent(e.value)}')
        .join('&');
    return '/batches?$queryString';
  }

  Future<void> _onFetchBatches(FetchBatches event, Emitter<BatchState> emit) async {
    emit(BatchLoading());
    try {
      final res = await ApiService.get(_pagePath(1, event.search));
      if (res.statusCode == 200) {
        final Map<String, dynamic> body = jsonDecode(res.body);
        emit(
          BatchLoaded(
            body['data'] ?? [],
            hasMore: body['hasMore'] == true,
            page: 1,
            total: body['total'] ?? 0,
            search: event.search,
          ),
        );
      } else {
        emit(BatchError('Failed to load batches: ${res.statusCode}'));
      }
    } catch (e) {
      emit(BatchError('Error fetching batches: $e'));
    }
  }

  Future<void> _onLoadMoreBatches(
    LoadMoreBatches event,
    Emitter<BatchState> emit,
  ) async {
    final currentState = state;
    if (currentState is! BatchLoaded ||
        !currentState.hasMore ||
        currentState.isLoadingMore) {
      return;
    }

    emit(currentState.copyWith(isLoadingMore: true));
    try {
      final nextPage = currentState.page + 1;
      final res = await ApiService.get(_pagePath(nextPage, currentState.search));
      if (res.statusCode == 200) {
        final Map<String, dynamic> body = jsonDecode(res.body);
        final List<dynamic> nextBatch = body['data'] ?? [];
        emit(
          currentState.copyWith(
            batches: [...currentState.batches, ...nextBatch],
            hasMore: body['hasMore'] == true,
            page: nextPage,
            total: body['total'] ?? currentState.total,
            isLoadingMore: false,
          ),
        );
      } else {
        emit(currentState.copyWith(isLoadingMore: false));
      }
    } catch (e) {
      emit(currentState.copyWith(isLoadingMore: false));
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
      emit(currentState);
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
      emit(currentState);
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
      emit(currentState);
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
      emit(currentState);
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
      emit(currentState);
    }
  }
}
