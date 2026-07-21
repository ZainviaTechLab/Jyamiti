import 'dart:convert';
import 'package:http/http.dart' as http;

class DeepseekService {
  static const String _apiKey = 'sk-6c733e978e1c4bdeaaf4a5f5084d3184';
  static const String _endpoint = 'https://api.deepseek.com/chat/completions';

  static Future<List<Map<String, dynamic>>> generateSimilarQuestions(Map<String, dynamic> baseQuestion) async {
    final systemPrompt = '''
You are an expert mathematics teacher and curriculum developer.
Your task is to take a base practice question represented as a JSON object, and generate exactly 3 new, unique, and mathematically correct questions of the exact same type, difficulty level, and structure (same pattern).

Guidelines:
1. Make sure all generated questions are unique and have different values, text, context, or numbers, but follow the exact same logic/pattern as the base question.
2. The JSON schema for the generated questions must perfectly match the base question's schema.
3. Keep all fields like 'isSvg' as false, 'questionImage' as "", and option images as "" since AI cannot generate images.
4. Output must be a valid JSON object containing a single key "questions", which contains a list of exactly 3 question objects.
5. Do not include any explanation, markdown formatting, or comments outside of the JSON block. Return ONLY the JSON object.
6. Check correctness:
   - For MCQ_SINGLE / MCQ_MULTI: the 'correctAnswers' must be list of string indices of the correct options (e.g., ["0"]).
   - For SHORT_ANSWER: the 'correctAnswers' must have the correct value (e.g. ["15"]).
   - For ORDERING: the 'options' are the items, and 'correctAnswers' must be the list of sequential index strings in correct order (e.g. ["0", "1", "2"]).
   - For MATCHING: 'options' are left side items, 'rightOptions' are right side items. Each index matches the corresponding index. 'correctAnswers' should be populated with values.
   - For MATRIX_MCQ: 'options' are rows, 'rightOptions' are columns. 'correctAnswers' are string indices of the correct column for each row.
   - For MATRIX_INPUT: 'options' texts are JSON-encoded strings of lists of cell maps like [{"value":"cell_val","isInput":bool}]. 'rightOptions' are column headers. 'correctAnswers' are string answers in row-major order for cells with 'isInput' = true. Make sure to generate the 'text' key inside 'options' as a valid JSON-encoded string of lists.
   - For EQUATION: 'options' are steps containing "[INPUT:answer]" tags. 'correctAnswers' are answers extracted in order.
   - For STATEMENT_DROPDOWN: 'options' are statements containing "[SELECT:choices:correct]" tags. 'correctAnswers' are the correct choices.
   - For INLINE_SELECT: 'text' contains "[SELECT:choices:correct]" tags. 'correctAnswers' are the correct choices.
''';

    final userPrompt = '''
Base Question JSON:
${jsonEncode(baseQuestion)}

Please generate 3 similar questions.
''';

    final response = await http.post(
      Uri.parse(_endpoint),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $_apiKey',
      },
      body: jsonEncode({
        'model': 'deepseek-chat',
        'messages': [
          {'role': 'system', 'content': systemPrompt},
          {'role': 'user', 'content': userPrompt},
        ],
        'response_format': {
          'type': 'json_object'
        },
        'temperature': 0.7,
      }),
    );

    if (response.statusCode == 200) {
      final body = jsonDecode(response.body);
      final content = body['choices'][0]['message']['content'] as String;
      final parsed = jsonDecode(content);
      if (parsed['questions'] != null && parsed['questions'] is List) {
        return List<Map<String, dynamic>>.from(
          (parsed['questions'] as List).map((q) {
            final map = Map<String, dynamic>.from(q);
            // Ensure essential structures are correct type
            if (map['options'] != null && map['options'] is List) {
              map['options'] = List<Map<String, dynamic>>.from(
                (map['options'] as List).map((o) => Map<String, dynamic>.from(o))
              );
            }
            if (map['rightOptions'] != null && map['rightOptions'] is List) {
              map['rightOptions'] = List<Map<String, dynamic>>.from(
                (map['rightOptions'] as List).map((o) => Map<String, dynamic>.from(o))
              );
            }
            if (map['correctAnswers'] != null && map['correctAnswers'] is List) {
              map['correctAnswers'] = List<String>.from(
                (map['correctAnswers'] as List).map((e) => e.toString())
              );
            }
            return map;
          }),
        );
      }
      throw Exception('Response does not contain questions list');
    } else {
      throw Exception('Failed to generate questions: ${response.statusCode} - ${response.body}');
    }
  }
}
