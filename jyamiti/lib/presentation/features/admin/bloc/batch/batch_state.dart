import 'package:equatable/equatable.dart';

abstract class BatchState extends Equatable {
  const BatchState();
  
  @override
  List<Object?> get props => [];
}

class BatchInitial extends BatchState {}

class BatchLoading extends BatchState {}

class BatchLoaded extends BatchState {
  final List<dynamic> batches;
  final bool hasMore;
  final int page;
  final int total;
  final String search;
  final bool isLoadingMore;

  const BatchLoaded(
    this.batches, {
    this.hasMore = false,
    this.page = 1,
    this.total = 0,
    this.search = '',
    this.isLoadingMore = false,
  });

  BatchLoaded copyWith({
    List<dynamic>? batches,
    bool? hasMore,
    int? page,
    int? total,
    String? search,
    bool? isLoadingMore,
  }) {
    return BatchLoaded(
      batches ?? this.batches,
      hasMore: hasMore ?? this.hasMore,
      page: page ?? this.page,
      total: total ?? this.total,
      search: search ?? this.search,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
    );
  }

  @override
  List<Object?> get props =>
      [batches, hasMore, page, total, search, isLoadingMore];
}

class BatchError extends BatchState {
  final String message;

  const BatchError(this.message);

  @override
  List<Object?> get props => [message];
}

class BatchOperationSuccess extends BatchState {
  final String message;
  const BatchOperationSuccess(this.message);
  @override
  List<Object?> get props => [message];
}

class BatchOperationFailure extends BatchState {
  final String message;
  const BatchOperationFailure(this.message);
  @override
  List<Object?> get props => [message];
}
