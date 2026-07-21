import 'package:equatable/equatable.dart';

abstract class CourseEvent extends Equatable {
  const CourseEvent();

  @override
  List<Object?> get props => [];
}

class FetchCourses extends CourseEvent {}

class CreateCourse extends CourseEvent {
  final String title;
  final String description;
  final String grade;
  final String subject;

  const CreateCourse({required this.title, required this.description, required this.grade, required this.subject});

  @override
  List<Object?> get props => [title, description, grade, subject];
}

class UpdateCourse extends CourseEvent {
  final String id;
  final String title;
  final String description;
  final String grade;
  final String subject;

  const UpdateCourse({required this.id, required this.title, required this.description, required this.grade, required this.subject});

  @override
  List<Object?> get props => [id, title, description, grade, subject];
}

class DeleteCourse extends CourseEvent {
  final String id;

  const DeleteCourse(this.id);

  @override
  List<Object?> get props => [id];
}

class UpdateCourseSyllabus extends CourseEvent {
  final String id;
  final List<dynamic> syllabus;

  const UpdateCourseSyllabus({required this.id, required this.syllabus});

  @override
  List<Object?> get props => [id, syllabus];
}
