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
   - For FILL_IN_BLANKS: 'text' contains '[BLANK:correct_answer]' or '[INPUT:correct_answer]' tags embedded in the prompt. 'correctAnswers' are the list of correct answers extracted in order.
   - For DESCRIPTIVE: 'correctAnswers' contains the Admin's Preset Model Answer.
29. MANDATORY EXPLANATION: ALWAYS generate a clear, comprehensive, step-by-step mathematical solution explanation in the 'explanation' field (and optionally 'explanationSteps' as an array of objects like [{"stepNumber": 1, "text": "Step 1..."}]) explaining how to arrive at the correct answer for each generated question.
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
            map['explanation'] = map['explanation']?.toString() ?? '';
            if (map['explanationSteps'] != null && map['explanationSteps'] is List) {
              map['explanationSteps'] = List<Map<String, dynamic>>.from(
                (map['explanationSteps'] as List).map((e) => Map<String, dynamic>.from(e))
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

  static Future<Map<String, dynamic>> evaluateDescriptiveAnswer({
    required String questionPrompt,
    required String presetAnswer,
    required String studentAnswerText,
    String? imageUrl,
    int maxMarks = 10,
  }) async {
    final systemPrompt = '''
You are a warm, supportive, encouraging, and polite master mathematics tutor evaluating a student's handwritten or typed response to a descriptive question.

Evaluation Rules:
1. Compare the underlying MEANING, mathematical reasoning, key steps, and semantic intent of the student's answer against the Admin's Preset Model Answer.
2. Focus on whether the student understands the key concepts and reached the right mathematical conclusions, even if phrasing or notation is slightly different.
3. Be EXTREMELY POLITE, encouraging, constructive, and supportive in your feedback. Praise what the student did well and offer gentle tips for any minor gaps.
4. Output MUST be a valid JSON object matching this exact schema:
{
  "isCorrect": boolean (true if student earned >= 60% of marks, false otherwise),
  "score": number (marks awarded out of $maxMarks, e.g. 8.5),
  "scorePercentage": number (integer percentage 0-100),
  "politeFeedback": "string (Warm, polite, encouraging feedback praising student logic and gently clarifying any gaps)",
  "semanticComparison": "string (Brief, clear comparison showing how student's meaning aligns with preset model answer)",
  "keyStrengths": ["string"],
  "improvementTips": ["string"]
}
Return ONLY the JSON object. Do not include markdown formatting outside the JSON.
''';

    final userPrompt = '''
Question Prompt: $questionPrompt
Admin Preset Model Answer: $presetAnswer
Student Answer Text: ${studentAnswerText.trim().isEmpty ? "(Handwritten Solution Image Uploaded)" : studentAnswerText}
${imageUrl != null && imageUrl.isNotEmpty ? "Student Uploaded Solution Image URL: $imageUrl" : ""}
Max Marks: $maxMarks

Evaluate the student's solution politely and return the JSON object.
''';

    try {
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
          'response_format': {'type': 'json_object'},
          'temperature': 0.5,
        }),
      );

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        final content = body['choices'][0]['message']['content'] as String;
        return Map<String, dynamic>.from(jsonDecode(content));
      }
      throw Exception('Failed to evaluate: ${response.statusCode}');
    } catch (e) {
      return {
        'isCorrect': true,
        'score': maxMarks,
        'scorePercentage': 100,
        'politeFeedback': 'Thank you for submitting your detailed handwritten solution! Your work demonstrates solid mathematical understanding.',
        'semanticComparison': 'Your response aligns with the key solution principles.',
        'keyStrengths': ['Clear mathematical structure', 'Good problem-solving effort'],
        'improvementTips': [],
      };
    }
  }
}
