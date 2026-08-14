import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// A tutor-defined roster for the Student Spinner that isn't tied to any
/// one batch -- e.g. "Group A" mixing students pulled from several batches,
/// or a trimmed-down list for a small activity. Membership is a flat list
/// of names (the spinner only ever needs names, not student IDs), so this
/// stays independent of batch data and survives a student being removed
/// from/renamed in a batch elsewhere.
class SpinnerGroup {
  final String id;
  String name;
  List<String> studentNames;

  SpinnerGroup({required this.id, required this.name, required this.studentNames});

  factory SpinnerGroup.fromJson(Map<String, dynamic> json) => SpinnerGroup(
        id: json['id'] as String,
        name: json['name'] as String? ?? 'Untitled Group',
        studentNames: (json['studentNames'] as List?)?.map((e) => e.toString()).toList() ?? [],
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'studentNames': studentNames,
      };
}

/// On-device (SharedPreferences, so it works on web too) persistence for
/// custom Student Spinner groups. One flat JSON array under a single key --
/// tutors typically keep a handful of these, so no need for the file-backed
/// index/blob-store pattern used by the Asset/Notebook libraries.
class StudentSpinnerGroupStorageService {
  static const _prefsKey = 'mathpad_spinner_custom_groups';

  Future<List<SpinnerGroup>> loadGroups() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw) as List;
      return decoded.map((e) => SpinnerGroup.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {
      // Corrupt/unrecognized data shouldn't crash the spinner -- just start fresh.
      return [];
    }
  }

  Future<void> saveGroups(List<SpinnerGroup> groups) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, jsonEncode(groups.map((g) => g.toJson()).toList()));
  }
}
