import 'dart:convert';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../../../services/api_service.dart';
import 'course_event.dart';
import 'course_state.dart';

class CourseBloc extends Bloc<CourseEvent, CourseState> {
  CourseBloc() : super(CourseInitial()) {
    on<FetchCourses>(_onFetchCourses);
    on<CreateCourse>(_onCreateCourse);
    on<UpdateCourse>(_onUpdateCourse);
    on<DeleteCourse>(_onDeleteCourse);
    on<UpdateCourseSyllabus>(_onUpdateCourseSyllabus);
  }

  Future<void> _onFetchCourses(FetchCourses event, Emitter<CourseState> emit) async {
    emit(CourseLoading());
    try {
      final res = await ApiService.get('/courses');
      if (res.statusCode == 200) {
        final List<dynamic> courses = jsonDecode(res.body);
        emit(CourseLoaded(courses));
      } else {
        emit(CourseError('Failed to load courses: ${res.statusCode}'));
      }
    } catch (e) {
      emit(CourseError('Error fetching courses: $e'));
    }
  }

  Future<void> _onCreateCourse(CreateCourse event, Emitter<CourseState> emit) async {
    final currentState = state;
    try {
      final res = await ApiService.post('/courses', {
        'name': event.title,
        'description': event.description,
        'grade': event.grade,
        'subject': event.subject,
      });

      if (res.statusCode == 201) {
        emit(const CourseOperationSuccess('Course created successfully'));
      } else {
        final data = jsonDecode(res.body);
        emit(CourseOperationFailure(data['message'] ?? 'Error creating course'));
      }
    } catch (e) {
      emit(CourseOperationFailure('Error: $e'));
    }

    if (currentState is CourseLoaded) {
      emit(CourseLoaded(currentState.courses));
    }
  }

  Future<void> _onUpdateCourse(UpdateCourse event, Emitter<CourseState> emit) async {
    final currentState = state;
    try {
      final res = await ApiService.put('/courses/${event.id}', {
        'name': event.title,
        'description': event.description,
        'grade': event.grade,
        'subject': event.subject,
      });

      if (res.statusCode == 200) {
        emit(const CourseOperationSuccess('Course updated successfully'));
      } else {
        final data = jsonDecode(res.body);
        emit(CourseOperationFailure(data['message'] ?? 'Error updating course'));
      }
    } catch (e) {
      emit(CourseOperationFailure('Error: $e'));
    }

    if (currentState is CourseLoaded) {
      emit(CourseLoaded(currentState.courses));
    }
  }

  Future<void> _onDeleteCourse(DeleteCourse event, Emitter<CourseState> emit) async {
    final currentState = state;
    try {
      final res = await ApiService.delete('/courses/${event.id}');
      if (res.statusCode == 200) {
        emit(const CourseOperationSuccess('Course deleted successfully'));
      } else {
        emit(const CourseOperationFailure('Failed to delete course'));
      }
    } catch (e) {
      emit(CourseOperationFailure('Error: $e'));
    }

    if (currentState is CourseLoaded) {
      emit(CourseLoaded(currentState.courses));
    }
  }

  Future<void> _onUpdateCourseSyllabus(UpdateCourseSyllabus event, Emitter<CourseState> emit) async {
    final currentState = state;
    try {
      final res = await ApiService.put('/courses/${event.id}', {
        'syllabus': event.syllabus,
      });

      if (res.statusCode == 200) {
        final updatedCourse = jsonDecode(res.body);
        emit(const CourseOperationSuccess('Syllabus updated successfully'));
        if (currentState is CourseLoaded) {
          final updatedCourses = currentState.courses.map((c) {
            final cid = c['id'] ?? c['_id'];
            final updatedId = updatedCourse['id'] ?? updatedCourse['_id'];
            if (cid == updatedId) {
              return updatedCourse;
            }
            return c;
          }).toList();
          emit(CourseLoaded(updatedCourses));
          return;
        }
      } else {
        emit(const CourseOperationFailure('Failed to update syllabus'));
      }
    } catch (e) {
      emit(CourseOperationFailure('Error: $e'));
    }

    if (currentState is CourseLoaded) {
      emit(CourseLoaded(currentState.courses));
    }
  }
}
