import 'dart:convert';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../../../services/api_service.dart';
import 'batch_category_event.dart';
import 'batch_category_state.dart';

class BatchCategoryBloc extends Bloc<BatchCategoryEvent, BatchCategoryState> {
  BatchCategoryBloc() : super(BatchCategoryInitial()) {
    on<FetchBatchCategories>(_onFetchCategories);
    on<CreateBatchCategory>(_onCreateCategory);
    on<UpdateBatchCategory>(_onUpdateCategory);
    on<DeleteBatchCategory>(_onDeleteCategory);
  }

  Future<void> _onFetchCategories(FetchBatchCategories event, Emitter<BatchCategoryState> emit) async {
    emit(BatchCategoryLoading());
    try {
      final res = await ApiService.get('/batch-categories');
      if (res.statusCode == 200) {
        final List<dynamic> categories = jsonDecode(res.body);
        emit(BatchCategoryLoaded(categories));
      } else {
        emit(BatchCategoryError('Failed to load categories: ${res.statusCode}'));
      }
    } catch (e) {
      emit(BatchCategoryError('Error fetching categories: $e'));
    }
  }

  Future<void> _onCreateCategory(CreateBatchCategory event, Emitter<BatchCategoryState> emit) async {
    final currentState = state;
    try {
      final res = await ApiService.post('/batch-categories', {
        'name': event.name,
        'maxMembers': event.maxMembers,
        'fees': event.fees,
      });

      if (res.statusCode == 201) {
        emit(const BatchCategoryOperationSuccess('Category created successfully'));
      } else {
        final data = jsonDecode(res.body);
        emit(BatchCategoryOperationFailure(data['message'] ?? 'Error creating category'));
      }
    } catch (e) {
      emit(BatchCategoryOperationFailure('Error: $e'));
    }

    if (currentState is BatchCategoryLoaded) {
      emit(BatchCategoryLoaded(currentState.categories));
    }
  }

  Future<void> _onUpdateCategory(UpdateBatchCategory event, Emitter<BatchCategoryState> emit) async {
    final currentState = state;
    try {
      final res = await ApiService.put('/batch-categories/${event.id}', {
        'name': event.name,
        'maxMembers': event.maxMembers,
        'fees': event.fees,
      });

      if (res.statusCode == 200) {
        emit(const BatchCategoryOperationSuccess('Category updated successfully'));
      } else {
        final data = jsonDecode(res.body);
        emit(BatchCategoryOperationFailure(data['message'] ?? 'Error updating category'));
      }
    } catch (e) {
      emit(BatchCategoryOperationFailure('Error: $e'));
    }

    if (currentState is BatchCategoryLoaded) {
      emit(BatchCategoryLoaded(currentState.categories));
    }
  }

  Future<void> _onDeleteCategory(DeleteBatchCategory event, Emitter<BatchCategoryState> emit) async {
    final currentState = state;
    try {
      final res = await ApiService.delete('/batch-categories/${event.id}');
      if (res.statusCode == 200) {
        emit(const BatchCategoryOperationSuccess('Category deleted successfully'));
      } else {
        emit(const BatchCategoryOperationFailure('Failed to delete category'));
      }
    } catch (e) {
      emit(BatchCategoryOperationFailure('Error: $e'));
    }

    if (currentState is BatchCategoryLoaded) {
      emit(BatchCategoryLoaded(currentState.categories));
    }
  }
}
