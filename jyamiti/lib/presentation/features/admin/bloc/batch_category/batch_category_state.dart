import 'package:equatable/equatable.dart';

abstract class BatchCategoryState extends Equatable {
  const BatchCategoryState();
  
  @override
  List<Object?> get props => [];
}

class BatchCategoryInitial extends BatchCategoryState {}

class BatchCategoryLoading extends BatchCategoryState {}

class BatchCategoryLoaded extends BatchCategoryState {
  final List<dynamic> categories;

  const BatchCategoryLoaded(this.categories);

  @override
  List<Object?> get props => [categories];
}

class BatchCategoryError extends BatchCategoryState {
  final String message;

  const BatchCategoryError(this.message);

  @override
  List<Object?> get props => [message];
}

class BatchCategoryOperationSuccess extends BatchCategoryState {
  final String message;
  const BatchCategoryOperationSuccess(this.message);
  @override
  List<Object?> get props => [message];
}

class BatchCategoryOperationFailure extends BatchCategoryState {
  final String message;
  const BatchCategoryOperationFailure(this.message);
  @override
  List<Object?> get props => [message];
}
