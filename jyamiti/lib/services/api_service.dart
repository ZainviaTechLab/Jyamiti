import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class ApiService {
  // Production API Endpoint
  static const String baseUrl = 'https://api.jyamitimath.com/api';

  // static const String baseUrl = 'http://10.51.176.77:5000/api';


  static Future<Map<String, dynamic>> fetchMyAttendanceSummary() async {
    final response = await http.get(
      Uri.parse('$baseUrl/schedules/my-attendance-summary'),
      headers: await _headers(),
    );
    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw Exception('Failed to load attendance summary');
    }
  }

  static Future<Map<String, String>> _headers() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  static Future<http.Response> get(String path) async {
    final url = Uri.parse('$baseUrl$path');
    return await http.get(url, headers: await _headers());
  }

  static Future<http.Response> post(
    String path,
    Map<String, dynamic> body,
  ) async {
    final url = Uri.parse('$baseUrl$path');
    return await http.post(
      url,
      headers: await _headers(),
      body: jsonEncode(body),
    );
  }

  static Future<http.Response> put(
    String path,
    Map<String, dynamic> body,
  ) async {
    final url = Uri.parse('$baseUrl$path');
    return await http.put(
      url,
      headers: await _headers(),
      body: jsonEncode(body),
    );
  }

  static Future<http.Response> delete(String path) async {
    final url = Uri.parse('$baseUrl$path');
    return await http.delete(url, headers: await _headers());
  }

  static Future<http.Response> patch(
    String path, [
    Map<String, dynamic>? body,
  ]) async {
    final url = Uri.parse('$baseUrl$path');
    return await http.patch(
      url,
      headers: await _headers(),
      body: body != null ? jsonEncode(body) : null,
    );
  }

  static Future<http.StreamedResponse> uploadFile(
    String path,
    List<int> bytes,
    String filename, {
    String fieldName = 'pdf',
  }) async {
    final url = Uri.parse('$baseUrl$path');
    final request = http.MultipartRequest('POST', url);

    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');
    if (token != null) {
      request.headers['Authorization'] = 'Bearer $token';
    }

    request.files.add(
      http.MultipartFile.fromBytes(fieldName, bytes, filename: filename),
    );
    return await request.send();
  }

  static Future<http.StreamedResponse> uploadWorksheet(
    String path,
    Map<String, String> fields,
    List<int>? bytes,
    String? filename, {
    String method = 'POST',
  }) async {
    final url = Uri.parse('$baseUrl$path');
    final request = http.MultipartRequest(method, url);

    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');
    if (token != null) {
      request.headers['Authorization'] = 'Bearer $token';
    }

    request.fields.addAll(fields);

    if (bytes != null && filename != null) {
      request.files.add(
        http.MultipartFile.fromBytes('file', bytes, filename: filename),
      );
    }
    return await request.send();
  }

  // --- Assignments ---
  
  static Future<http.Response> createAssignment(Map<String, dynamic> body) async {
    return await post('/assignments', body);
  }
  
  static Future<http.Response> getStudentAssignments(String studentId) async {
    return await get('/assignments/student/$studentId');
  }

  static Future<http.Response> getBatchAssignments(String batchId) async {
    return await get('/assignments/batch/$batchId');
  }

  static Future<http.Response> getTutorAssignments() async {
    return await get('/assignments/tutor');
  }

  static Future<http.Response> updateAssignmentDueDate(String assignmentId, String dueDate) async {
    return await put('/assignments/$assignmentId', {'dueDate': dueDate});
  }

  static Future<http.Response> deleteAssignment(String assignmentId) async {
    return await delete('/assignments/$assignmentId');
  }

  static Future<http.Response> completeAssignment(String assignmentId, {int? score, int? totalQuestions}) async {
    // Uses PATCH /:id/complete — a student-accessible route that sets status=completed
    final body = <String, dynamic>{};
    if (score != null) body['score'] = score;
    if (totalQuestions != null) body['totalQuestions'] = totalQuestions;
    return await patch('/assignments/$assignmentId/complete', body);
  }

  static Future<http.Response> getBatchPerformances(String batchId) async {
    return await get('/assignments/batch/$batchId/performances');
  }
}
