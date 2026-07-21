import 'package:equatable/equatable.dart';

abstract class BatchCategoryEvent extends Equatable {
  const BatchCategoryEvent();

  @override
  List<Object?> get props => [];
}

class FetchBatchCategories extends BatchCategoryEvent {}

class CreateBatchCategory extends BatchCategoryEvent {
  final String name;
  final int maxMembers;
  final int fees;

  const CreateBatchCategory({
    required this.name,
    required this.maxMembers,
    required this.fees,
  });

  @override
  List<Object?> get props => [name, maxMembers, fees];
}

class UpdateBatchCategory extends BatchCategoryEvent {
  final String id;
  final String name;
  final int maxMembers;
  final int fees;

  const UpdateBatchCategory({
    required this.id,
    required this.name,
    required this.maxMembers,
    required this.fees,
  });

  @override
  List<Object?> get props => [id, name, maxMembers, fees];
}

class DeleteBatchCategory extends BatchCategoryEvent {
  final String id;

  const DeleteBatchCategory(this.id);

  @override
  List<Object?> get props => [id];
}
