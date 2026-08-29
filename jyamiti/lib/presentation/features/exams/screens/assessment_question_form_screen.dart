import 'package:jyamiti/presentation/widgets/jyamiti_loader.dart';
import 'package:jyamiti/presentation/widgets/symbol_picker_toolbar.dart';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../../../services/api_service.dart';
import '../../../../widgets/svg_label_editor_dialog.dart';
import '../../../../providers/theme_provider.dart';
import '../../../../services/deepseek_service.dart';

class AssessmentQuestionFormScreen extends StatefulWidget {
  final int initialGrade;
  final Map<String, dynamic>? existingQuestion;
  final bool isPracticeMode;

  const AssessmentQuestionFormScreen({
    super.key,
    required this.initialGrade,
    this.existingQuestion,
    this.isPracticeMode = false,
  });

  @override
  State<AssessmentQuestionFormScreen> createState() =>
      _AssessmentQuestionFormScreenState();
}

class _AssessmentQuestionFormScreenState
    extends State<AssessmentQuestionFormScreen> {
  final _formKey = GlobalKey<FormState>();

  late int _grade;
  late String _type;
  late TextEditingController _descriptiveTextCtrl;
  late TextEditingController _textCtrl;
  late TextEditingController _marksCtrl;
  late TextEditingController _shortAnswerCtrl;
  late TextEditingController _prefixCtrl;
  late TextEditingController _suffixCtrl;
  late TextEditingController _hintCtrl;

  // Image upload state for the Question itself
  String _questionImage = '';
  bool _isQuestionSvg = false;
  bool _isUploadingQuestionImage = false;
  List<Map<String, dynamic>> _svgLabels = [];

  // Options list state (each option has text, imageUrl, isSvg)
  List<Map<String, dynamic>> _options = [];
  List<Map<String, dynamic>> _rightOptions = [];
  List<bool> _correctAnswerSelection = []; // tracks correctness checkbox/radio

  // TRUE_FALSE question state: true = correct answer is "True"
  bool _trueFalseAnswer = true;

  // Geometry question state
  List<Map<String, dynamic>> _geometryNodes = [];
  int _geometryLinesCount = 1;
  bool _hideGeometryNodes = false;
  List<String> _geometryConnections = [];

  // Matrix MCQ question state
  List<String> _matrixCorrectAnswers = [];

  // Matrix Input question state
  List<List<Map<String, dynamic>>> _matrixInputCells = [];

  // Equation completion steps controllers
  List<TextEditingController> _equationStepControllers = [];

  // Statement dropdown question state
  List<TextEditingController> _statementStepControllers = [];

  // Explanation and Step-by-Step Solution state
  TextEditingController _explanationCtrl = TextEditingController();
  List<Map<String, dynamic>> _explanationSteps = [];
  bool _isClasswork = false;

  bool _isLoading = false;

  // AI similar questions & Ditto cloned questions generation state
  List<Map<String, dynamic>> _dittoQuestions = [];
  // Persistent per-ditto-question controllers (kept in lockstep with
  // _dittoQuestions by index) so the math symbol toolbar can attach to them.
  final List<TextEditingController> _dittoDescriptiveTextCtrls = [];
  final List<TextEditingController> _dittoTextCtrls = [];
  final List<TextEditingController> _dittoExplanationCtrls = [];
  final List<TextEditingController> _dittoShortAnswerCtrls = [];
  final List<List<TextEditingController>> _dittoOptionCtrls = [];
  final List<List<TextEditingController>> _dittoRightPairCtrls = [];
  final List<TextEditingController> _dittoPrefixCtrls = [];
  final List<TextEditingController> _dittoSuffixCtrls = [];
  final List<TextEditingController> _dittoHintCtrls = [];
  final List<TextEditingController> _dittoMarksCtrls = [];
  final List<bool> _dittoTrueFalseAnswers = [];
  final List<List<TextEditingController>> _dittoEquationStepCtrls = [];
  final List<List<TextEditingController>> _dittoStatementStepCtrls = [];
  final List<List<String>> _dittoMatrixCorrectAnswers = [];
  final List<List<List<Map<String, dynamic>>>> _dittoMatrixInputCells = [];
  bool _isGeneratingAI = false;
  List<Map<String, dynamic>> _generatedQuestions = [];
  List<bool> _selectedGeneratedQuestions = [true, true, true];

  // Tracks the TextEditingController behind whichever text field last had
  // focus, ANYWHERE on this screen (main form, every Ditto card, MCQ options,
  // Matrix grids, Matching pairs, AI/Ditto review fields — all of them,
  // including fields with no controller of their own, since every
  // TextField/TextFormField always creates one internally even when none is
  // passed explicitly). Updated passively via a global FocusManager listener
  // (no setState — this screen is too large to rebuild on every focus
  // change), so the shared toolbar in the AppBar can insert into it without
  // requiring each field to opt in individually.
  TextEditingController? _globalActiveCtrl;
  // The focused field's own EditableText.onChanged (i.e. exactly what a real
  // keystroke would invoke — TextField/TextFormField's onChanged, wired down
  // to whatever data model that specific field writes into, e.g.
  // `cell['value'] = val` for a Matrix Input cell). Mutating the controller
  // alone updates the on-screen text (the field listens to its own
  // controller) but does NOT reliably re-run this callback, so without
  // calling it explicitly the backing map/list never sees the inserted
  // symbol and it silently gets dropped on save — matching the established
  // pattern in SymbolToolbarStrip._onSymbolTap, which does the same dual step.
  ValueChanged<String>? _globalActiveOnChanged;

  void _handleGlobalFocusChange() {
    final BuildContext? focusContext = FocusManager.instance.primaryFocus?.context;
    if (focusContext == null) return;
    final EditableTextState? editableState =
        focusContext.findAncestorStateOfType<EditableTextState>();
    if (editableState != null && editableState.mounted) {
      _globalActiveCtrl = editableState.widget.controller;
      _globalActiveOnChanged = editableState.widget.onChanged;
    }
  }

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addListener(_handleGlobalFocusChange);
    final q = widget.existingQuestion;

    _grade = q?['grade'] ?? widget.initialGrade;
    _type = q?['type'] ?? 'MCQ_SINGLE';
    _descriptiveTextCtrl = TextEditingController(
      text: q?['descriptiveText'] ?? '',
    );
    _textCtrl = TextEditingController(text: q?['text'] ?? '');
    _marksCtrl = TextEditingController(text: q?['marks']?.toString() ?? '1');
    _shortAnswerCtrl = TextEditingController();
    _prefixCtrl = TextEditingController(text: q?['shortAnswerPrefix'] ?? '');
    _suffixCtrl = TextEditingController(text: q?['shortAnswerSuffix'] ?? '');
    _hintCtrl = TextEditingController(text: q?['shortAnswerHint'] ?? '');
    _explanationCtrl = TextEditingController(text: q?['explanation'] ?? '');
    if (q != null && q['explanationSteps'] != null && q['explanationSteps'] is List) {
      _explanationSteps = List<Map<String, dynamic>>.from(
        (q['explanationSteps'] as List).map((e) => Map<String, dynamic>.from(e)),
      );
    }
    _isClasswork = q?['isClasswork'] == true || q?['forTutorOnly'] == true;

    _questionImage = q?['questionImage'] ?? '';
    _isQuestionSvg = q?['isSvg'] ?? false;

    if (q != null && q['svgLabels'] != null) {
      final List<dynamic> labelsRaw = q['svgLabels'];
      _svgLabels = labelsRaw.map((l) => Map<String, dynamic>.from(l)).toList();
    }

    if (q != null) {
      if (_type == 'SHORT_ANSWER' || _type == 'DESCRIPTIVE') {
        _shortAnswerCtrl.text = (q['correctAnswers'] as List).isNotEmpty
            ? q['correctAnswers'][0].toString()
            : '';
      } else if (_type == 'TRUE_FALSE') {
        final List<dynamic> ca = q['correctAnswers'] ?? [];
        _trueFalseAnswer = ca.isEmpty || ca.first.toString() == '0';
      } else if (_type == 'MATCHING') {
        final List<dynamic> opts = q['options'] ?? [];
        final List<dynamic> rightOpts = q['rightOptions'] ?? [];

        for (var o in opts) {
          _options.add({
            'text': o['text'] ?? '',
            'imageUrl': o['imageUrl'] ?? '',
            'isSvg': o['isSvg'] ?? false,
          });
        }
        for (var o in rightOpts) {
          _rightOptions.add({
            'text': o['text'] ?? '',
            'imageUrl': o['imageUrl'] ?? '',
            'isSvg': o['isSvg'] ?? false,
          });
        }
      } else if (_type == 'MATRIX_MCQ') {
        final List<dynamic> opts = q['options'] ?? [];
        final List<dynamic> rightOpts = q['rightOptions'] ?? [];

        for (var o in opts) {
          _options.add({
            'text': o['text'] ?? '',
            'imageUrl': o['imageUrl'] ?? '',
            'isSvg': o['isSvg'] ?? false,
          });
        }
        for (var o in rightOpts) {
          _rightOptions.add({
            'text': o['text'] ?? '',
            'imageUrl': o['imageUrl'] ?? '',
            'isSvg': o['isSvg'] ?? false,
          });
        }
        final List<dynamic> correct = q['correctAnswers'] ?? [];
        _matrixCorrectAnswers = correct.map((e) => e.toString()).toList();
      } else if (_type == 'MATRIX_INPUT') {
        final List<dynamic> opts = q['options'] ?? [];
        final List<dynamic> rightOpts = q['rightOptions'] ?? [];

        for (var o in opts) {
          _options.add({
            'text': o['text'] ?? '',
            'imageUrl': o['imageUrl'] ?? '',
            'isSvg': o['isSvg'] ?? false,
          });

          final String jsonStr = o['text'] ?? '[]';
          List<dynamic> cells = [];
          try {
            cells = json.decode(jsonStr);
          } catch (_) {}

          final List<Map<String, dynamic>> rowCells = [];
          for (var cell in cells) {
            rowCells.add({
              'value': cell['value'] ?? '',
              'isInput': cell['isInput'] == true,
            });
          }
          while (rowCells.length < rightOpts.length) {
            rowCells.add({'value': '', 'isInput': false});
          }
          _matrixInputCells.add(rowCells);
        }
        for (var o in rightOpts) {
          _rightOptions.add({
            'text': o['text'] ?? '',
            'imageUrl': o['imageUrl'] ?? '',
            'isSvg': o['isSvg'] ?? false,
          });
        }
      } else if (_type == 'EQUATION') {
        final List<dynamic> opts = q['options'] ?? [];
        for (var o in opts) {
          final String txt = o['text'] ?? '';
          _options.add({'text': txt, 'imageUrl': '', 'isSvg': false});
          _equationStepControllers.add(TextEditingController(text: txt));
        }
      } else if (_type == 'STATEMENT_DROPDOWN') {
        final List<dynamic> opts = q['options'] ?? [];
        for (var o in opts) {
          final String txt = o['text'] ?? '';
          _options.add({'text': txt, 'imageUrl': '', 'isSvg': false});
          _statementStepControllers.add(TextEditingController(text: txt));
        }
      } else if (_type == 'GEOMETRIC') {
        _geometryLinesCount = q['geometryLinesCount'] as int? ?? 1;
        _hideGeometryNodes = q['hideGeometryNodes'] == true;
        final List<dynamic> nodes = q['geometryNodes'] ?? [];
        for (var n in nodes) {
          _geometryNodes.add({
            'id': n['id'] ?? '',
            'label': n['label'] ?? '',
            'x': (n['x'] as num?)?.toDouble() ?? 0.0,
            'y': (n['y'] as num?)?.toDouble() ?? 0.0,
            'isFixed': n['isFixed'] == true,
          });
        }
        final List<dynamic> correct = q['correctAnswers'] ?? [];
        for (var c in correct) {
          _geometryConnections.add(c.toString());
        }
      } else {
        // Load MCQ options
        final List<dynamic> opts = q['options'] ?? [];
        final List<dynamic> correct = q['correctAnswers'] ?? [];

        for (var o in opts) {
          _options.add({
            'text': o['text'] ?? '',
            'imageUrl': o['imageUrl'] ?? '',
            'isSvg': o['isSvg'] ?? false,
          });
        }

        // Track which options are selected as correct
        _correctAnswerSelection = List.generate(_options.length, (idx) {
          return correct.map((e) => e.toString()).contains(idx.toString());
        });
      }
    } else {
      // Default to 4 empty options for MCQ
      _addEmptyOption();
      _addEmptyOption();
      _addEmptyOption();
      _addEmptyOption();
    }
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_handleGlobalFocusChange);
    _descriptiveTextCtrl.dispose();
    _textCtrl.dispose();
    _marksCtrl.dispose();
    _shortAnswerCtrl.dispose();
    _prefixCtrl.dispose();
    _suffixCtrl.dispose();
    _hintCtrl.dispose();
    for (var ctrl in _equationStepControllers) {
      ctrl.dispose();
    }
    for (var ctrl in _statementStepControllers) {
      ctrl.dispose();
    }
    for (var ctrl in _dittoDescriptiveTextCtrls) {
      ctrl.dispose();
    }
    for (var ctrl in _dittoTextCtrls) {
      ctrl.dispose();
    }
    for (var ctrl in _dittoExplanationCtrls) {
      ctrl.dispose();
    }
    for (var ctrl in _dittoShortAnswerCtrls) {
      ctrl.dispose();
    }
    for (var list in _dittoOptionCtrls) {
      for (var ctrl in list) {
        ctrl.dispose();
      }
    }
    for (var list in _dittoRightPairCtrls) {
      for (var ctrl in list) {
        ctrl.dispose();
      }
    }
    for (var ctrl in _dittoPrefixCtrls) {
      ctrl.dispose();
    }
    for (var ctrl in _dittoSuffixCtrls) {
      ctrl.dispose();
    }
    for (var ctrl in _dittoHintCtrls) {
      ctrl.dispose();
    }
    for (var ctrl in _dittoMarksCtrls) {
      ctrl.dispose();
    }
    for (var list in _dittoEquationStepCtrls) {
      for (var ctrl in list) {
        ctrl.dispose();
      }
    }
    for (var list in _dittoStatementStepCtrls) {
      for (var ctrl in list) {
        ctrl.dispose();
      }
    }
    super.dispose();
  }

  // Inserts [symbol] into whichever text field last had focus anywhere on
  // this screen — works for every field, including the ones that only ever
  // used initialValue/onChanged with no explicit controller (MCQ options,
  // Matrix MCQ/Input grids, Matching pairs, Geometry labels, AI/Ditto review
  // fields), since Flutter always creates a real TextEditingController
  // internally for a TextField/TextFormField even when none is passed in.
  void _insertGlobalSymbol(String symbol) {
    final TextEditingController? ctrl = _globalActiveCtrl;
    if (ctrl == null) {
      _showSnackBar('Tap into a text field first, then pick a symbol.');
      return;
    }
    MathSymbolsData.insertSymbol(ctrl, symbol);
    _globalActiveOnChanged?.call(ctrl.text);
  }

  void _showGlobalSymbolPicker() {
    final TextEditingController? ctrl = _globalActiveCtrl;
    if (ctrl == null) {
      _showSnackBar('Tap into a text field first, then pick a symbol.');
      return;
    }
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => FullSymbolPickerModal(
        controller: ctrl,
        onChanged: () => _globalActiveOnChanged?.call(ctrl.text),
      ),
    );
  }

  // Shared math-symbol toolbar pinned in the AppBar beside "Save Question(s)".
  // This is IN ADDITION to every field's own inline toolbar (unchanged) — it
  // exists so fields without an inline toolbar (options, matrix cells, etc.)
  // still have a way to insert symbols.
  Widget _buildGlobalSymbolToolbar() {
    final isDark = context.isDark;
    return Container(
      height: 36,
      constraints: const BoxConstraints(maxWidth: 230),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 4),
            child: Icon(Icons.functions_rounded, size: 16, color: Color(0xFF6366F1)),
          ),
          Flexible(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: MathSymbolsData.quickSymbols.map((symbol) {
                  return Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: InkWell(
                      onTap: () => _insertGlobalSymbol(symbol),
                      borderRadius: BorderRadius.circular(6),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF0F172A) : Colors.white,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: isDark ? const Color(0xFF475569) : const Color(0xFFE2E8F0),
                          ),
                        ),
                        child: Text(
                          symbol,
                          style: TextStyle(
                            color: context.textColor,
                            fontWeight: FontWeight.bold,
                            fontSize: symbol.length > 3 ? 10 : 12,
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
          const SizedBox(width: 4),
          InkWell(
            onTap: _showGlobalSymbolPicker,
            borderRadius: BorderRadius.circular(6),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFF6366F1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Icon(Icons.grid_view_rounded, size: 13, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  void _addEmptyOption() {
    setState(() {
      _options.add({'text': '', 'imageUrl': '', 'isSvg': false});
      _correctAnswerSelection.add(false);
    });
  }

  void _removeOption(int idx) {
    setState(() {
      _options.removeAt(idx);
      _correctAnswerSelection.removeAt(idx);
    });
  }

  // Get dynamic image server URL
  String _getImageUrl(String relativeUrl) {
    if (relativeUrl.isEmpty) return '';
    if (relativeUrl.startsWith('http://') ||
        relativeUrl.startsWith('https://')) {
      return relativeUrl;
    }
    String origin = ApiService.baseUrl;
    if (origin.endsWith('/api')) {
      origin = origin.substring(0, origin.length - 4);
    }
    return '$origin/$relativeUrl';
  }

  // Pick and upload file using file_picker
  Future<void> _pickAndUploadQuestionFile() async {
    setState(() => _isUploadingQuestionImage = true);
    try {
      FilePickerResult? result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['svg', 'png', 'jpg', 'jpeg'],
        withData: true, // Necessary for cross-platform bytes access
      );

      if (result != null && result.files.single.bytes != null) {
        final fileBytes = result.files.single.bytes!;
        final fileName = result.files.single.name;

        final res = await ApiService.uploadFile(
          '/assessment-questions/upload',
          fileBytes,
          fileName,
          fieldName: 'file',
        );

        if (res.statusCode == 200) {
          final resBody = await res.stream.bytesToString();
          final data = jsonDecode(resBody);
          setState(() {
            _questionImage = data['fileUrl'] ?? '';
            _isQuestionSvg = fileName.toLowerCase().endsWith('.svg');
            _svgLabels = [];
          });
        } else {
          _showSnackBar('Failed to upload question image');
        }
      }
    } catch (e) {
      _showSnackBar('Error picking file: $e');
    } finally {
      setState(() => _isUploadingQuestionImage = false);
    }
  }

  // Pick and upload file for an MCQ Option
  Future<void> _pickAndUploadOptionFile(int idx) async {
    try {
      FilePickerResult? result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['svg', 'png', 'jpg', 'jpeg'],
        withData: true,
      );

      if (result != null && result.files.single.bytes != null) {
        final fileBytes = result.files.single.bytes!;
        final fileName = result.files.single.name;

        // Show indicator on the button
        _showSnackBar('Uploading option file...', duration: 1);

        final res = await ApiService.uploadFile(
          '/assessment-questions/upload',
          fileBytes,
          fileName,
          fieldName: 'file',
        );

        if (res.statusCode == 200) {
          final resBody = await res.stream.bytesToString();
          final data = jsonDecode(resBody);
          setState(() {
            _options[idx]['imageUrl'] = data['fileUrl'] ?? '';
            _options[idx]['isSvg'] = fileName.toLowerCase().endsWith('.svg');
          });
          _showSnackBar('Option file uploaded successfully!', isSuccess: true);
        } else {
          _showSnackBar('Failed to upload option image');
        }
      }
    } catch (e) {
      _showSnackBar('Error picking option file: $e');
    }
  }

  void _showSnackBar(String msg, {bool isSuccess = false, int duration = 3}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isSuccess ? Colors.green : Colors.redAccent,
        duration: Duration(seconds: duration),
      ),
    );
  }

  // Save the question
  Future<void> _saveQuestion() async {
    if (!_formKey.currentState!.validate()) return;

    List<String> correctAnswers = [];

    if (_type == 'SHORT_ANSWER') {
      if (_shortAnswerCtrl.text.trim().isEmpty) {
        _showSnackBar(
          'Please provide correct answer for Short Answer question.',
        );
        return;
      }
      correctAnswers = [_shortAnswerCtrl.text.trim()];
    } else if (_type == 'ORDERING') {
      if (_options.isEmpty) {
        _showSnackBar('Please add at least one item to order.');
        return;
      }
      // Populate correct answers sequence (0, 1, 2, 3...)
      correctAnswers = List.generate(_options.length, (i) => i.toString());
    } else if (_type == 'GEOMETRIC') {
      if (_questionImage.isEmpty) {
        _showSnackBar(
          'Please upload a background image/diagram for the geometric question.',
        );
        return;
      }
      if (_geometryNodes.length < 2) {
        _showSnackBar('Please place at least two nodes on the canvas.');
        return;
      }
      if (_geometryConnections.isEmpty) {
        _showSnackBar('Please specify at least one correct connection.');
        return;
      }
      correctAnswers = _geometryConnections;
    } else if (_type == 'MATRIX_MCQ') {
      if (_options.isEmpty) {
        _showSnackBar('Please add at least one row for the grid question.');
        return;
      }
      if (_rightOptions.isEmpty) {
        _showSnackBar('Please add at least one column for the grid question.');
        return;
      }
      // Align matrix correct answers list length
      if (_matrixCorrectAnswers.length < _options.length) {
        final List<String> aligned = List.from(_matrixCorrectAnswers);
        while (aligned.length < _options.length) {
          aligned.add("0");
        }
        correctAnswers = aligned;
      } else {
        correctAnswers = _matrixCorrectAnswers.sublist(0, _options.length);
      }
    } else if (_type == 'MATRIX_INPUT') {
      if (_options.isEmpty) {
        _showSnackBar('Please add at least one row for the table.');
        return;
      }
      if (_rightOptions.isEmpty) {
        _showSnackBar('Please add at least one column for the table.');
        return;
      }
      final List<String> inputs = [];
      for (int r = 0; r < _options.length; r++) {
        final List<Map<String, dynamic>> rowCells = _matrixInputCells[r];
        for (var cell in rowCells) {
          if (cell['isInput'] == true) {
            inputs.add(cell['value'].toString().trim());
          }
        }
      }
      correctAnswers = inputs;
    } else if (_type == 'EQUATION') {
      if (_options.isEmpty) {
        _showSnackBar('Please add at least one equation step.');
        return;
      }
      final List<String> inputs = [];
      final regExp = RegExp(r'\[INPUT:(.*?)\]');
      for (int i = 0; i < _options.length; i++) {
        // Sync values from controllers
        while (_equationStepControllers.length <= i) {
          _equationStepControllers.add(TextEditingController());
        }
        final String stepText = _equationStepControllers[i].text;
        _options[i]['text'] = stepText;

        final Iterable<Match> matches = regExp.allMatches(stepText);
        for (var m in matches) {
          final String val = m.group(1) ?? '';
          inputs.add(val.trim());
        }
      }
      if (inputs.isEmpty) {
        _showSnackBar(
          'Please insert at least one input box using [INPUT:answer] tag.',
        );
        return;
      }
      correctAnswers = inputs;
    } else if (_type == 'INLINE_SELECT') {
      final String textVal = _textCtrl.text.trim();
      if (textVal.isEmpty) {
        _showSnackBar('Please write the question text.');
        return;
      }
      final List<String> inputs = [];
      final regExp = RegExp(r'\[SELECT:(.*?):(.*?)\]');
      final Iterable<Match> matches = regExp.allMatches(textVal);
      for (var m in matches) {
        final String choicesRaw = m.group(1) ?? '';
        final String correctVal = m.group(2) ?? '';
        final List<String> choices = choicesRaw
            .split(',')
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList();
        final String trimmedCorrect = correctVal.trim();

        if (choices.isEmpty) {
          _showSnackBar('Dropdown tag is missing choices. e.g. [SELECT:a,b:b]');
          return;
        }
        if (trimmedCorrect.isEmpty) {
          _showSnackBar(
            'Dropdown tag is missing a correct option. e.g. [SELECT:a,b:b]',
          );
          return;
        }
        if (!choices.contains(trimmedCorrect)) {
          _showSnackBar(
            'The correct choice "$trimmedCorrect" is not present in the list of choices: ${choices.join(", ")}.',
          );
          return;
        }
        inputs.add(trimmedCorrect);
      }
      if (inputs.isEmpty) {
        _showSnackBar(
          'Please insert at least one dropdown box using [SELECT:choices:correct] tag in the question text.',
        );
        return;
      }
      correctAnswers = inputs;
    } else if (_type == 'FILL_IN_BLANKS') {
      final String textVal = _textCtrl.text.trim();
      if (textVal.isEmpty) {
        _showSnackBar('Please write the question text.');
        return;
      }
      final List<String> inputs = [];
      final regExp = RegExp(r'\[(?:BLANK|INPUT)(?::([^\]]*))?\]', caseSensitive: false);
      final Iterable<Match> matches = regExp.allMatches(textVal);

      for (var m in matches) {
        final String val = (m.group(1) ?? '').trim();
        inputs.add(val);
      }

      if (inputs.isEmpty) {
        _showSnackBar(
          'Please insert at least one blank using [BLANK:answer] or [INPUT:answer] tag in question text.',
        );
        return;
      }

      if (inputs.any((ans) => ans.isEmpty)) {
        _showSnackBar(
          'Please specify the correct answer inside each blank tag e.g. [BLANK:180].',
        );
        return;
      }
      correctAnswers = inputs;
    } else if (_type == 'DESCRIPTIVE') {
      final String textVal = _textCtrl.text.trim();
      if (textVal.isEmpty) {
        _showSnackBar('Please write the question prompt.');
        return;
      }
      final String presetAns = _shortAnswerCtrl.text.trim();
      if (presetAns.isEmpty) {
        _showSnackBar('Please provide the Admin Preset Model Answer.');
        return;
      }
      correctAnswers = [presetAns];
    } else if (_type == 'STATEMENT_DROPDOWN') {
      if (_options.isEmpty) {
        _showSnackBar('Please add at least one statement.');
        return;
      }
      final List<String> inputs = [];
      final regExp = RegExp(r'\[SELECT:(.*?):(.*?)\]');
      for (int i = 0; i < _options.length; i++) {
        while (_statementStepControllers.length <= i) {
          _statementStepControllers.add(TextEditingController());
        }
        final String stepText = _statementStepControllers[i].text;
        _options[i]['text'] = stepText;

        final Iterable<Match> matches = regExp.allMatches(stepText);
        for (var m in matches) {
          final String choicesRaw = m.group(1) ?? '';
          final String correctVal = m.group(2) ?? '';

          final List<String> choices = choicesRaw
              .split(',')
              .map((e) => e.trim())
              .where((e) => e.isNotEmpty)
              .toList();
          final String trimmedCorrect = correctVal.trim();

          if (choices.isEmpty) {
            _showSnackBar(
              'Dropdown tag is missing choices. e.g. [SELECT:a,b:b]',
            );
            return;
          }
          if (trimmedCorrect.isEmpty) {
            _showSnackBar(
              'Dropdown tag is missing a correct option. e.g. [SELECT:a,b:b]',
            );
            return;
          }
          if (!choices.contains(trimmedCorrect)) {
            _showSnackBar(
              'The correct choice "$trimmedCorrect" is not present in the list of choices: ${choices.join(", ")}.',
            );
            return;
          }
          inputs.add(trimmedCorrect);
        }
      }
      if (inputs.isEmpty) {
        _showSnackBar(
          'Please insert at least one dropdown box using [SELECT:choices:correct] tag.',
        );
        return;
      }
      correctAnswers = inputs;
    } else if (_type == 'TRUE_FALSE') {
      correctAnswers = [_trueFalseAnswer ? '0' : '1'];
    } else {
      // Validate that at least one option is correct
      bool hasCorrect = _correctAnswerSelection.any((val) => val);
      if (!hasCorrect) {
        _showSnackBar('Please mark at least one option as correct.');
        return;
      }

      // Collect indices of correct options
      for (int i = 0; i < _correctAnswerSelection.length; i++) {
        if (_correctAnswerSelection[i]) {
          correctAnswers.add(i.toString());
        }
      }
    }

    setState(() => _isLoading = true);

    final List<Map<String, dynamic>> matrixInputOptions = [];
    if (_type == 'MATRIX_INPUT') {
      for (int r = 0; r < _options.length; r++) {
        matrixInputOptions.add({
          'text': json.encode(_matrixInputCells[r]),
          'imageUrl': '',
          'isSvg': false,
        });
      }
    }

    final List<Map<String, dynamic>> trueFalseOptions = [
      {'text': 'True', 'imageUrl': '', 'isSvg': false},
      {'text': 'False', 'imageUrl': '', 'isSvg': false},
    ];

    final reqBody = {
      'grade': _grade,
      'type': _type,
      'descriptiveText': _descriptiveTextCtrl.text.trim(),
      'text': _textCtrl.text.trim(),
      'isSvg': _isQuestionSvg,
      'questionImage': _questionImage,
      'options': _type == 'MATRIX_INPUT'
          ? matrixInputOptions
          : _type == 'TRUE_FALSE'
          ? trueFalseOptions
          : ((_type == 'SHORT_ANSWER' || _type == 'GEOMETRIC') ? [] : _options),
      'rightOptions':
          (_type == 'MATCHING' ||
              _type == 'MATRIX_MCQ' ||
              _type == 'MATRIX_INPUT')
          ? _rightOptions
          : [],
      'geometryNodes': _type == 'GEOMETRIC' ? _geometryNodes : [],
      'geometryLinesCount': _type == 'GEOMETRIC' ? _geometryLinesCount : 1,
      'hideGeometryNodes': _type == 'GEOMETRIC' ? _hideGeometryNodes : false,
      'correctAnswers': correctAnswers,
      'marks': int.tryParse(_marksCtrl.text) ?? 1,
      'shortAnswerPrefix': _prefixCtrl.text.trim(),
      'shortAnswerSuffix': _suffixCtrl.text.trim(),
      'shortAnswerHint': _hintCtrl.text.trim(),
      'svgLabels': _svgLabels,
      'explanation': _explanationCtrl.text.trim(),
      'explanationSteps': _explanationSteps,
      'isClasswork': _isClasswork,
      'category': _isClasswork ? 'classwork' : 'practice',
    };

    if (widget.isPracticeMode) {
      final localQuestion = Map<String, dynamic>.from(reqBody);
      localQuestion['_id'] =
          widget.existingQuestion?['_id'] ?? _generateMongoObjectId();

      final List<Map<String, dynamic>> questionsToSave = [localQuestion];

      // Append all Ditto questions
      for (final dq in _dittoQuestions) {
        final textVal = (dq['text'] ?? '').toString().trim();
        if (textVal.isNotEmpty) {
          final clonedDq = Map<String, dynamic>.from(dq);
          clonedDq['_id'] = _generateMongoObjectId();
          questionsToSave.add(clonedDq);
        }
      }

      // Append AI generated questions
      for (int i = 0; i < _generatedQuestions.length; i++) {
        if (_selectedGeneratedQuestions[i]) {
          final gq = Map<String, dynamic>.from(_generatedQuestions[i]);
          gq['_id'] = _generateMongoObjectId();
          questionsToSave.add(gq);
        }
      }

      if (questionsToSave.length > 1) {
        // Original base question goes to Classwork (Tutor Only)
        questionsToSave[0]['isClasswork'] = true;
        questionsToSave[0]['category'] = 'classwork';

        // All similar / ditto / AI generated variations go to Student Practice
        for (int i = 1; i < questionsToSave.length; i++) {
          questionsToSave[i]['isClasswork'] = false;
          questionsToSave[i]['category'] = 'practice';
        }
      } else if (questionsToSave.isNotEmpty) {
        bool setAsClasswork = _isClasswork;
        if (!_isClasswork) {
          final bool? choice = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              title: Row(
                children: const [
                  Icon(Icons.help_outline_rounded, color: Color(0xFF6366F1)),
                  SizedBox(width: 8),
                  Text('Save Question As'),
                ],
              ),
              content: const Text(
                'Would you like to add this single question as a Tutor Only (Classwork) question or as a Student Practice question?',
              ),
              actions: [
                TextButton.icon(
                  onPressed: () => Navigator.pop(ctx, false),
                  icon: const Icon(Icons.school_rounded, size: 16),
                  label: const Text('Student Practice'),
                ),
                ElevatedButton.icon(
                  onPressed: () => Navigator.pop(ctx, true),
                  icon: const Icon(Icons.cast_for_education_rounded, size: 16),
                  label: const Text('Tutor Only (Classwork)'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF10B981),
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          );
          if (choice != null) {
            setAsClasswork = choice;
          }
        }
        questionsToSave[0]['isClasswork'] = setAsClasswork;
        questionsToSave[0]['category'] =
            setAsClasswork ? 'classwork' : 'practice';
      }

      final String snackMessage = widget.existingQuestion != null
          ? 'Question updated'
          : (questionsToSave.length > 1
                ? 'Saved ${questionsToSave.length} questions (${_dittoQuestions.length} ditto cloned)'
                : 'Saved 1 practice question');

      _showSnackBar(snackMessage, isSuccess: true);
      Navigator.pop(context, questionsToSave);
      return;
    }

    try {
      final bool isEdit = widget.existingQuestion != null;
      int count = 0;

      final res = isEdit
          ? await ApiService.put(
              '/assessment-questions/${widget.existingQuestion!['_id']}',
              reqBody,
            )
          : await ApiService.post('/assessment-questions', reqBody);

      if (res.statusCode == 200 || res.statusCode == 201) {
        count++;
        for (final dq in _dittoQuestions) {
          final textVal = (dq['text'] ?? '').toString().trim();
          if (textVal.isNotEmpty) {
            await ApiService.post('/assessment-questions', dq);
            count++;
          }
        }

        _showSnackBar(
          isEdit ? 'Question updated' : 'Saved $count question(s) to database',
          isSuccess: true,
        );
        Navigator.pop(context, true);
      } else {
        final err = jsonDecode(res.body);
        _showSnackBar(err['message'] ?? 'Failed to save question');
      }
    } catch (e) {
      _showSnackBar('Network error saving question: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Map<String, dynamic>? _buildCurrentQuestionPayload() {
    List<String> correctAnswers = [];

    if (_type == 'SHORT_ANSWER') {
      correctAnswers = [_shortAnswerCtrl.text.trim()];
    } else if (_type == 'ORDERING') {
      correctAnswers = List.generate(_options.length, (i) => i.toString());
    } else if (_type == 'GEOMETRIC') {
      correctAnswers = _geometryConnections;
    } else if (_type == 'MATRIX_MCQ') {
      if (_matrixCorrectAnswers.length < _options.length) {
        final List<String> aligned = List.from(_matrixCorrectAnswers);
        while (aligned.length < _options.length) {
          aligned.add("0");
        }
        correctAnswers = aligned;
      } else {
        correctAnswers = _matrixCorrectAnswers.sublist(0, _options.length);
      }
    } else if (_type == 'MATRIX_INPUT') {
      final List<String> inputs = [];
      for (int r = 0; r < _options.length; r++) {
        final List<Map<String, dynamic>> rowCells = _matrixInputCells[r];
        for (var cell in rowCells) {
          if (cell['isInput'] == true) {
            inputs.add(cell['value'].toString().trim());
          }
        }
      }
      correctAnswers = inputs;
    } else if (_type == 'EQUATION') {
      final List<String> inputs = [];
      final regExp = RegExp(r'\[INPUT:(.*?)\]');
      for (int i = 0; i < _options.length; i++) {
        final String stepText = _equationStepControllers.length <= i
            ? ""
            : _equationStepControllers[i].text;
        final Iterable<Match> matches = regExp.allMatches(stepText);
        for (var m in matches) {
          inputs.add((m.group(1) ?? '').trim());
        }
      }
      correctAnswers = inputs;
    } else if (_type == 'INLINE_SELECT') {
      final String textVal = _textCtrl.text.trim();
      final List<String> inputs = [];
      final regExp = RegExp(r'\[SELECT:(.*?):(.*?)\]');
      final Iterable<Match> matches = regExp.allMatches(textVal);
      for (var m in matches) {
        inputs.add((m.group(2) ?? '').trim());
      }
      correctAnswers = inputs;
    } else if (_type == 'STATEMENT_DROPDOWN') {
      final List<String> inputs = [];
      final regExp = RegExp(r'\[SELECT:(.*?):(.*?)\]');
      for (int i = 0; i < _options.length; i++) {
        final String stepText = _statementStepControllers.length <= i
            ? ""
            : _statementStepControllers[i].text;
        final Iterable<Match> matches = regExp.allMatches(stepText);
        for (var m in matches) {
          inputs.add((m.group(2) ?? '').trim());
        }
      }
      correctAnswers = inputs;
    } else if (_type == 'TRUE_FALSE') {
      correctAnswers = [_trueFalseAnswer ? '0' : '1'];
    } else {
      for (int i = 0; i < _correctAnswerSelection.length; i++) {
        if (_correctAnswerSelection[i]) {
          correctAnswers.add(i.toString());
        }
      }
    }

    final List<Map<String, dynamic>> matrixInputOptions = [];
    if (_type == 'MATRIX_INPUT') {
      for (int r = 0; r < _options.length; r++) {
        matrixInputOptions.add({
          'text': json.encode(_matrixInputCells[r]),
          'imageUrl': '',
          'isSvg': false,
        });
      }
    }

    final List<Map<String, dynamic>> trueFalseOptions = [
      {'text': 'True', 'imageUrl': '', 'isSvg': false},
      {'text': 'False', 'imageUrl': '', 'isSvg': false},
    ];

    return {
      'grade': _grade,
      'type': _type,
      'descriptiveText': _descriptiveTextCtrl.text.trim(),
      'text': _textCtrl.text.trim(),
      'isSvg': _isQuestionSvg,
      'questionImage': _questionImage,
      'options': _type == 'MATRIX_INPUT'
          ? matrixInputOptions
          : _type == 'TRUE_FALSE'
          ? trueFalseOptions
          : ((_type == 'SHORT_ANSWER' || _type == 'GEOMETRIC') ? [] : _options),
      'rightOptions':
          (_type == 'MATCHING' ||
              _type == 'MATRIX_MCQ' ||
              _type == 'MATRIX_INPUT')
          ? _rightOptions
          : [],
      'geometryNodes': _type == 'GEOMETRIC' ? _geometryNodes : [],
      'geometryLinesCount': _type == 'GEOMETRIC' ? _geometryLinesCount : 1,
      'hideGeometryNodes': _type == 'GEOMETRIC' ? _hideGeometryNodes : false,
      'correctAnswers': correctAnswers,
      'marks': int.tryParse(_marksCtrl.text) ?? 1,
      'shortAnswerPrefix': _prefixCtrl.text.trim(),
      'shortAnswerSuffix': _suffixCtrl.text.trim(),
      'shortAnswerHint': _hintCtrl.text.trim(),
      'svgLabels': _svgLabels,
      'explanation': _explanationCtrl.text.trim(),
      'explanationSteps': _explanationSteps,
    };
  }

  Future<void> _generateSimilarQuestions() async {
    if (!_formKey.currentState!.validate()) {
      _showSnackBar('Please fix the validation errors in the form first.');
      return;
    }

    if (_type == 'SHORT_ANSWER' && _shortAnswerCtrl.text.trim().isEmpty) {
      _showSnackBar('Please provide correct answer for Short Answer question.');
      return;
    }
    if (_type == 'MCQ_SINGLE' || _type == 'MCQ_MULTI') {
      bool hasCorrect = _correctAnswerSelection.any((val) => val);
      if (!hasCorrect) {
        _showSnackBar('Please mark at least one option as correct.');
        return;
      }
    }

    final baseQuestion = _buildCurrentQuestionPayload();
    if (baseQuestion == null) return;

    setState(() {
      _isGeneratingAI = true;
    });

    try {
      final questions = await DeepseekService.generateSimilarQuestions(
        baseQuestion,
      );
      setState(() {
        _generatedQuestions = questions;
        _selectedGeneratedQuestions = List.generate(
          questions.length,
          (index) => true,
        );
      });
      _showSnackBar('AI successfully generated 3 questions!', isSuccess: true);
    } catch (e) {
      _showSnackBar('AI Generation failed: $e');
    } finally {
      setState(() {
        _isGeneratingAI = false;
      });
    }
  }

  void _addDittoQuestion() {
    if (!_formKey.currentState!.validate()) {
      _showSnackBar(
        'Please fix validation errors in the main question form first.',
      );
      return;
    }

    if (_type == 'SHORT_ANSWER' && _shortAnswerCtrl.text.trim().isEmpty) {
      _showSnackBar('Please provide correct answer for Short Answer question.');
      return;
    }
    if (_type == 'MCQ_SINGLE' || _type == 'MCQ_MULTI') {
      bool hasCorrect = _correctAnswerSelection.any((val) => val);
      if (!hasCorrect) {
        _showSnackBar('Please mark at least one option as correct.');
        return;
      }
    }

    final baseQuestion = _buildCurrentQuestionPayload();
    if (baseQuestion == null) return;

    final Map<String, dynamic> ditto = jsonDecode(jsonEncode(baseQuestion));
    ditto['text'] = '';
    ditto['explanation'] = _explanationCtrl.text.trim();
    // Deep clone (not a shallow List.from) so editing this Ditto's steps
    // later can never mutate the main question's own _explanationSteps maps,
    // and vice versa.
    ditto['explanationSteps'] = (jsonDecode(jsonEncode(_explanationSteps)) as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();

    final List optionsList = ditto['options'] is List ? ditto['options'] as List : [];
    final List rightOptionsList =
        ditto['rightOptions'] is List ? ditto['rightOptions'] as List : [];

    setState(() {
      _dittoQuestions.add(ditto);
      _dittoDescriptiveTextCtrls.add(
        TextEditingController(text: ditto['descriptiveText']?.toString() ?? ''),
      );
      _dittoTextCtrls.add(TextEditingController(text: ditto['text']?.toString() ?? ''));
      _dittoExplanationCtrls.add(
        TextEditingController(text: ditto['explanation']?.toString() ?? ''),
      );
      final String initialShortAnswer =
          (ditto['correctAnswers'] is List &&
              (ditto['correctAnswers'] as List).isNotEmpty)
          ? ditto['correctAnswers'][0].toString()
          : '';
      _dittoShortAnswerCtrls.add(TextEditingController(text: initialShortAnswer));
      _dittoOptionCtrls.add(
        List.generate(
          optionsList.length,
          (i) => TextEditingController(text: (optionsList[i]['text'] ?? '').toString()),
        ),
      );
      _dittoRightPairCtrls.add(
        List.generate(
          optionsList.length,
          (i) => TextEditingController(
            text: i < rightOptionsList.length
                ? (rightOptionsList[i]['text'] ?? '').toString()
                : '',
          ),
        ),
      );
      _dittoPrefixCtrls.add(
        TextEditingController(text: ditto['shortAnswerPrefix']?.toString() ?? ''),
      );
      _dittoSuffixCtrls.add(
        TextEditingController(text: ditto['shortAnswerSuffix']?.toString() ?? ''),
      );
      _dittoHintCtrls.add(
        TextEditingController(text: ditto['shortAnswerHint']?.toString() ?? ''),
      );
      _dittoMarksCtrls.add(
        TextEditingController(text: ditto['marks']?.toString() ?? '1'),
      );

      final List<dynamic> correctAnswersList =
          ditto['correctAnswers'] is List ? ditto['correctAnswers'] as List : [];
      _dittoTrueFalseAnswers.add(
        correctAnswersList.isEmpty || correctAnswersList.first.toString() == '0',
      );

      _dittoEquationStepCtrls.add(
        ditto['type'] == 'EQUATION'
            ? List.generate(
                optionsList.length,
                (i) => TextEditingController(
                  text: (optionsList[i]['text'] ?? '').toString(),
                ),
              )
            : <TextEditingController>[],
      );
      _dittoStatementStepCtrls.add(
        ditto['type'] == 'STATEMENT_DROPDOWN'
            ? List.generate(
                optionsList.length,
                (i) => TextEditingController(
                  text: (optionsList[i]['text'] ?? '').toString(),
                ),
              )
            : <TextEditingController>[],
      );

      _dittoMatrixCorrectAnswers.add(
        ditto['type'] == 'MATRIX_MCQ'
            ? List.generate(
                optionsList.length,
                (i) => i < correctAnswersList.length
                    ? correctAnswersList[i].toString()
                    : '0',
              )
            : <String>[],
      );

      if (ditto['type'] == 'MATRIX_INPUT') {
        final List<List<Map<String, dynamic>>> cellsForDitto = [];
        for (int r = 0; r < optionsList.length; r++) {
          final String jsonStr = optionsList[r]['text']?.toString() ?? '[]';
          List<dynamic> decoded = [];
          try {
            decoded = json.decode(jsonStr);
          } catch (_) {}
          final List<Map<String, dynamic>> rowCells = decoded
              .map<Map<String, dynamic>>(
                (c) => {'value': c['value'] ?? '', 'isInput': c['isInput'] == true},
              )
              .toList();
          while (rowCells.length < rightOptionsList.length) {
            rowCells.add({'value': '', 'isInput': false});
          }
          cellsForDitto.add(rowCells);
        }
        _dittoMatrixInputCells.add(cellsForDitto);
      } else {
        _dittoMatrixInputCells.add([]);
      }
    });

    _showSnackBar(
      'Added Ditto Question #${_dittoQuestions.length}! Scroll down to edit text.',
      isSuccess: true,
    );
  }

  Widget _buildDittoQuestionsSection() {
    if (_dittoQuestions.isEmpty) return const SizedBox();

    final isDark = context.isDark;
    return Container(
      margin: const EdgeInsets.only(top: 24),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF10B981).withOpacity(0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.control_point_duplicate_rounded,
                color: Color(0xFF10B981),
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                'Ditto Cloned Questions (${_dittoQuestions.length})',
                style: TextStyle(
                  color: context.textColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: () {
                  setState(() {
                    _dittoQuestions.clear();
                    for (var ctrl in _dittoDescriptiveTextCtrls) {
                      ctrl.dispose();
                    }
                    _dittoDescriptiveTextCtrls.clear();
                    for (var ctrl in _dittoTextCtrls) {
                      ctrl.dispose();
                    }
                    _dittoTextCtrls.clear();
                    for (var ctrl in _dittoExplanationCtrls) {
                      ctrl.dispose();
                    }
                    _dittoExplanationCtrls.clear();
                    for (var ctrl in _dittoShortAnswerCtrls) {
                      ctrl.dispose();
                    }
                    _dittoShortAnswerCtrls.clear();
                    for (var list in _dittoOptionCtrls) {
                      for (var ctrl in list) {
                        ctrl.dispose();
                      }
                    }
                    _dittoOptionCtrls.clear();
                    for (var list in _dittoRightPairCtrls) {
                      for (var ctrl in list) {
                        ctrl.dispose();
                      }
                    }
                    _dittoRightPairCtrls.clear();
                    for (var ctrl in _dittoPrefixCtrls) {
                      ctrl.dispose();
                    }
                    _dittoPrefixCtrls.clear();
                    for (var ctrl in _dittoSuffixCtrls) {
                      ctrl.dispose();
                    }
                    _dittoSuffixCtrls.clear();
                    for (var ctrl in _dittoHintCtrls) {
                      ctrl.dispose();
                    }
                    _dittoHintCtrls.clear();
                    for (var ctrl in _dittoMarksCtrls) {
                      ctrl.dispose();
                    }
                    _dittoMarksCtrls.clear();
                    _dittoTrueFalseAnswers.clear();
                    for (var list in _dittoEquationStepCtrls) {
                      for (var ctrl in list) {
                        ctrl.dispose();
                      }
                    }
                    _dittoEquationStepCtrls.clear();
                    for (var list in _dittoStatementStepCtrls) {
                      for (var ctrl in list) {
                        ctrl.dispose();
                      }
                    }
                    _dittoStatementStepCtrls.clear();
                    _dittoMatrixCorrectAnswers.clear();
                    _dittoMatrixInputCells.clear();
                  });
                },
                icon: const Icon(
                  Icons.delete_outline,
                  size: 16,
                  color: Colors.redAccent,
                ),
                label: const Text(
                  'Clear All Ditto',
                  style: TextStyle(color: Colors.redAccent, fontSize: 12),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...List.generate(_dittoQuestions.length, (idx) {
            final q = _dittoQuestions[idx];
            return Card(
              margin: const EdgeInsets.only(bottom: 16),
              color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
                side: BorderSide(
                  color: const Color(0xFF10B981).withOpacity(0.3),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(14.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF10B981).withOpacity(0.15),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            'Ditto #${idx + 1}',
                            style: const TextStyle(
                              color: Color(0xFF10B981),
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          q['type'] ?? '',
                          style: TextStyle(
                            color: context.textColor60,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const Spacer(),
                        IconButton(
                          icon: const Icon(
                            Icons.delete_outline,
                            color: Colors.redAccent,
                            size: 20,
                          ),
                          onPressed: () {
                            setState(() {
                              _dittoQuestions.removeAt(idx);
                              _dittoDescriptiveTextCtrls.removeAt(idx).dispose();
                              _dittoTextCtrls.removeAt(idx).dispose();
                              _dittoExplanationCtrls.removeAt(idx).dispose();
                              _dittoShortAnswerCtrls.removeAt(idx).dispose();
                              for (var ctrl in _dittoOptionCtrls.removeAt(idx)) {
                                ctrl.dispose();
                              }
                              for (var ctrl in _dittoRightPairCtrls.removeAt(idx)) {
                                ctrl.dispose();
                              }
                              _dittoPrefixCtrls.removeAt(idx).dispose();
                              _dittoSuffixCtrls.removeAt(idx).dispose();
                              _dittoHintCtrls.removeAt(idx).dispose();
                              _dittoMarksCtrls.removeAt(idx).dispose();
                              _dittoTrueFalseAnswers.removeAt(idx);
                              for (var ctrl in _dittoEquationStepCtrls.removeAt(idx)) {
                                ctrl.dispose();
                              }
                              for (var ctrl in _dittoStatementStepCtrls.removeAt(idx)) {
                                ctrl.dispose();
                              }
                              _dittoMatrixCorrectAnswers.removeAt(idx);
                              _dittoMatrixInputCells.removeAt(idx);
                            });
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    if (q['descriptiveText'] != null &&
                        q['descriptiveText'].toString().isNotEmpty) ...[
                      SymbolInputFieldWrapper(
                        controller: _dittoDescriptiveTextCtrls[idx],
                        onChanged: () => q['descriptiveText'] =
                            _dittoDescriptiveTextCtrls[idx].text,
                        child: TextFormField(
                          controller: _dittoDescriptiveTextCtrls[idx],
                          decoration: InputDecoration(
                            labelText: 'Descriptive Context Text',
                            labelStyle: TextStyle(
                              fontSize: 11,
                              color: context.textColor70,
                            ),
                            border: const OutlineInputBorder(),
                            isDense: true,
                          ),
                          style: TextStyle(
                            color: context.textColor,
                            fontSize: 13,
                          ),
                          maxLines: 2,
                          onChanged: (val) {
                            q['descriptiveText'] = val;
                          },
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    SymbolInputFieldWrapper(
                      controller: _dittoTextCtrls[idx],
                      onChanged: () {
                        q['text'] = _dittoTextCtrls[idx].text;
                        _syncDittoTextDerivedAnswers(q);
                      },
                      child: TextFormField(
                        controller: _dittoTextCtrls[idx],
                        decoration: InputDecoration(
                          labelText: 'Question Text',
                          hintText: 'Enter question text for Ditto #${idx + 1}',
                          labelStyle: TextStyle(
                            fontSize: 11,
                            color: context.textColor70,
                          ),
                          border: const OutlineInputBorder(),
                          isDense: true,
                        ),
                        style: TextStyle(color: context.textColor, fontSize: 13),
                        maxLines: 3,
                        onChanged: (val) {
                          q['text'] = val;
                          _syncDittoTextDerivedAnswers(q);
                        },
                      ),
                    ),
                    if (q['type'] == 'FILL_IN_BLANKS') ...[
                      const SizedBox(height: 10),
                      _buildDittoTipBox(
                        'Insert blanks using [BLANK:answer] or [INPUT:answer] tags. Example: "The area is [BLANK:\\pi r^2]."',
                      ),
                    ],
                    if (q['type'] == 'INLINE_SELECT') ...[
                      const SizedBox(height: 10),
                      _buildDittoTipBox(
                        'Insert dropdowns using [SELECT:choice1,choice2:correctChoice] tags. Example: "\$\\pi\$ is approx [SELECT:3.14,4.13:3.14]."',
                      ),
                    ],
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _dittoMarksCtrls[idx],
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Marks',
                        labelStyle: TextStyle(fontSize: 11),
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      style: TextStyle(color: context.textColor, fontSize: 13),
                      onChanged: (val) {
                        q['marks'] = int.tryParse(val) ?? 1;
                      },
                    ),
                    const SizedBox(height: 12),
                    if ((q['type'] == 'MCQ_SINGLE' ||
                            q['type'] == 'MCQ_MULTI') &&
                        q['options'] != null &&
                        q['options'] is List) ...[
                      Text(
                        'Options (Check/Uncheck to mark correct):',
                        style: TextStyle(
                          color: context.textColor70,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 6),
                      ...List.generate((q['options'] as List).length, (optIdx) {
                        final opt = q['options'][optIdx];
                        final List<String> correct = List<String>.from(
                          q['correctAnswers'] ?? [],
                        );
                        final bool isCorrect = correct.contains(
                          optIdx.toString(),
                        );

                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8.0),
                          child: Row(
                            children: [
                              Checkbox(
                                activeColor: Colors.green,
                                value: isCorrect,
                                onChanged: (val) {
                                  setState(() {
                                    final updatedCorrect = List<String>.from(
                                      q['correctAnswers'] ?? [],
                                    );
                                    if (val == true) {
                                      if (q['type'] == 'MCQ_SINGLE') {
                                        updatedCorrect.clear();
                                      }
                                      if (!updatedCorrect.contains(
                                        optIdx.toString(),
                                      )) {
                                        updatedCorrect.add(optIdx.toString());
                                      }
                                    } else {
                                      updatedCorrect.remove(optIdx.toString());
                                    }
                                    q['correctAnswers'] = updatedCorrect;
                                  });
                                },
                              ),
                              Expanded(
                                child: SymbolInputFieldWrapper(
                                  controller: _dittoOptionCtrls[idx][optIdx],
                                  onChanged: () => opt['text'] =
                                      _dittoOptionCtrls[idx][optIdx].text,
                                  child: TextFormField(
                                    controller: _dittoOptionCtrls[idx][optIdx],
                                    decoration: InputDecoration(
                                      labelText: 'Option ${optIdx + 1}',
                                      labelStyle: const TextStyle(fontSize: 11),
                                      border: const OutlineInputBorder(),
                                      isDense: true,
                                    ),
                                    style: TextStyle(
                                      color: context.textColor,
                                      fontSize: 13,
                                    ),
                                    onChanged: (val) {
                                      opt['text'] = val;
                                    },
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                    ] else if (q['type'] == 'SHORT_ANSWER') ...[
                      _buildDittoShortAnswerFields(idx),
                    ] else if (q['type'] == 'DESCRIPTIVE') ...[
                      _buildDittoShortAnswerFields(idx),
                    ] else if (q['type'] == 'TRUE_FALSE') ...[
                      _buildDittoTrueFalseInput(idx),
                    ] else if (q['type'] == 'EQUATION') ...[
                      _buildDittoEquationEditor(idx),
                    ] else if (q['type'] == 'STATEMENT_DROPDOWN') ...[
                      _buildDittoStatementDropdownEditor(idx),
                    ] else if (q['type'] == 'MATRIX_MCQ') ...[
                      _buildDittoMatrixMCQEditor(idx),
                    ] else if (q['type'] == 'MATRIX_INPUT') ...[
                      _buildDittoMatrixInputEditor(idx),
                    ] else if (q['type'] == 'MATCHING' &&
                        q['options'] != null &&
                        q['rightOptions'] != null) ...[
                      Text(
                        'Matching Pairs (Left <-> Right):',
                        style: TextStyle(
                          color: context.textColor70,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 6),
                      ...List.generate((q['options'] as List).length, (pIdx) {
                        final leftOpt = q['options'][pIdx];
                        final rightOpt =
                            (pIdx < (q['rightOptions'] as List).length)
                            ? q['rightOptions'][pIdx]
                            : {'text': ''};
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8.0),
                          child: Row(
                            children: [
                              Expanded(
                                child: SymbolInputFieldWrapper(
                                  controller: _dittoOptionCtrls[idx][pIdx],
                                  onChanged: () => leftOpt['text'] =
                                      _dittoOptionCtrls[idx][pIdx].text,
                                  child: TextFormField(
                                    controller: _dittoOptionCtrls[idx][pIdx],
                                    decoration: InputDecoration(
                                      labelText: 'Left Pair ${pIdx + 1}',
                                      labelStyle: const TextStyle(fontSize: 11),
                                      border: const OutlineInputBorder(),
                                      isDense: true,
                                    ),
                                    style: TextStyle(
                                      color: context.textColor,
                                      fontSize: 13,
                                    ),
                                    onChanged: (val) {
                                      leftOpt['text'] = val;
                                    },
                                  ),
                                ),
                              ),
                              const Padding(
                                padding: EdgeInsets.symmetric(horizontal: 6.0),
                                child: Icon(
                                  Icons.arrow_forward,
                                  size: 14,
                                  color: Colors.grey,
                                ),
                              ),
                              Expanded(
                                child: SymbolInputFieldWrapper(
                                  controller: _dittoRightPairCtrls[idx][pIdx],
                                  onChanged: () => rightOpt['text'] =
                                      _dittoRightPairCtrls[idx][pIdx].text,
                                  child: TextFormField(
                                    controller: _dittoRightPairCtrls[idx][pIdx],
                                    decoration: InputDecoration(
                                      labelText: 'Right Pair ${pIdx + 1}',
                                      labelStyle: const TextStyle(fontSize: 11),
                                      border: const OutlineInputBorder(),
                                      isDense: true,
                                    ),
                                    style: TextStyle(
                                      color: context.textColor,
                                      fontSize: 13,
                                    ),
                                    onChanged: (val) {
                                      rightOpt['text'] = val;
                                    },
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                    ] else ...[
                      Text(
                        'Answers: ${q['correctAnswers']}',
                        style: TextStyle(
                          color: context.textColor60,
                          fontSize: 11,
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    SymbolInputFieldWrapper(
                      controller: _dittoExplanationCtrls[idx],
                      onChanged: () =>
                          q['explanation'] = _dittoExplanationCtrls[idx].text,
                      child: TextFormField(
                        controller: _dittoExplanationCtrls[idx],
                        decoration: InputDecoration(
                          labelText: 'General Solution Explanation (Optional)',
                          hintText: 'Enter step-by-step solution explanation for Ditto #${idx + 1}',
                          labelStyle: TextStyle(
                            fontSize: 11,
                            color: context.textColor70,
                          ),
                          border: const OutlineInputBorder(),
                          isDense: true,
                        ),
                        style: TextStyle(color: context.textColor, fontSize: 13),
                        maxLines: 3,
                        onChanged: (val) {
                          q['explanation'] = val;
                        },
                      ),
                    ),
                    const SizedBox(height: 12),
                    _buildDittoExplanationStepsEditor(idx),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  // Small instructional tip box, mirroring the main form's own tip boxes for
  // FILL_IN_BLANKS / INLINE_SELECT question text tags.
  Widget _buildDittoTipBox(String message) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF10B981).withOpacity(0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF10B981).withOpacity(0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline_rounded, color: Color(0xFF10B981), size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: context.textColor, fontSize: 11, height: 1.3),
            ),
          ),
        ],
      ),
    );
  }

  // FILL_IN_BLANKS / INLINE_SELECT store their correct answers as tags
  // embedded directly in the question text (matching the main form's own
  // _saveQuestion logic) rather than as separate input fields, so recompute
  // q['correctAnswers'] straight from q['text'] whenever it changes.
  void _syncDittoTextDerivedAnswers(Map<String, dynamic> q) {
    final String textVal = (q['text'] ?? '').toString();
    if (q['type'] == 'INLINE_SELECT') {
      final regExp = RegExp(r'\[SELECT:(.*?):(.*?)\]');
      final List<String> inputs = [];
      for (final m in regExp.allMatches(textVal)) {
        inputs.add((m.group(2) ?? '').trim());
      }
      q['correctAnswers'] = inputs;
    } else if (q['type'] == 'FILL_IN_BLANKS') {
      final regExp = RegExp(r'\[(?:BLANK|INPUT)(?::([^\]]*))?\]', caseSensitive: false);
      final List<String> inputs = [];
      for (final m in regExp.allMatches(textVal)) {
        inputs.add((m.group(1) ?? '').trim());
      }
      q['correctAnswers'] = inputs;
    }
  }

  // Re-encodes _dittoMatrixInputCells[idx] back into q['options'][r]['text']
  // (JSON, mirroring the main form's matrixInputOptions construction) and
  // recomputes the flattened correctAnswers list of every input-flagged cell.
  void _syncDittoMatrixInputRows(int idx) {
    final q = _dittoQuestions[idx];
    final List<List<Map<String, dynamic>>> cells = _dittoMatrixInputCells[idx];
    final List optionsList = q['options'] is List ? q['options'] as List : [];
    for (int r = 0; r < optionsList.length && r < cells.length; r++) {
      optionsList[r]['text'] = json.encode(cells[r]);
    }
    final List<String> inputs = [];
    for (final row in cells) {
      for (final cell in row) {
        if (cell['isInput'] == true) {
          inputs.add((cell['value'] ?? '').toString().trim());
        }
      }
    }
    q['correctAnswers'] = inputs;
  }

  // EQUATION stores its answers as [INPUT:x] tags embedded in each step's
  // text (see _saveQuestion's save-time recompute for the main question);
  // since Ditto questions are POSTed as-is with no equivalent recompute
  // step, correctAnswers must be kept in sync here on every step edit.
  void _syncDittoEquationAnswers(int idx) {
    final q = _dittoQuestions[idx];
    final List optionsList = q['options'] is List ? q['options'] as List : [];
    final regExp = RegExp(r'\[INPUT:(.*?)\]');
    final List<String> inputs = [];
    for (final opt in optionsList) {
      final String stepText = (opt['text'] ?? '').toString();
      for (final m in regExp.allMatches(stepText)) {
        inputs.add((m.group(1) ?? '').trim());
      }
    }
    q['correctAnswers'] = inputs;
  }

  // Same idea as _syncDittoEquationAnswers but for STATEMENT_DROPDOWN's
  // [SELECT:choices:correct] tags.
  void _syncDittoStatementDropdownAnswers(int idx) {
    final q = _dittoQuestions[idx];
    final List optionsList = q['options'] is List ? q['options'] as List : [];
    final regExp = RegExp(r'\[SELECT:(.*?):(.*?)\]');
    final List<String> inputs = [];
    for (final opt in optionsList) {
      final String stepText = (opt['text'] ?? '').toString();
      for (final m in regExp.allMatches(stepText)) {
        inputs.add((m.group(2) ?? '').trim());
      }
    }
    q['correctAnswers'] = inputs;
  }

  // SHORT_ANSWER and DESCRIPTIVE both use _dittoShortAnswerCtrls for their
  // answer text, matching the main form's shared prefill logic; only
  // SHORT_ANSWER additionally gets Prefix/Suffix/Hint fields (DESCRIPTIVE's
  // main-form counterpart, _buildDescriptiveAnswerInput, has none).
  Widget _buildDittoShortAnswerFields(int idx) {
    final q = _dittoQuestions[idx];
    final bool isDescriptive = q['type'] == 'DESCRIPTIVE';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SymbolInputFieldWrapper(
          controller: _dittoShortAnswerCtrls[idx],
          onChanged: () =>
              q['correctAnswers'] = [_dittoShortAnswerCtrls[idx].text.trim()],
          child: TextFormField(
            controller: _dittoShortAnswerCtrls[idx],
            maxLines: isDescriptive ? 4 : 1,
            decoration: InputDecoration(
              labelText: isDescriptive ? 'Admin Preset Model Answer' : 'Correct Answer',
              labelStyle: const TextStyle(fontSize: 11),
              border: const OutlineInputBorder(),
              isDense: true,
            ),
            style: TextStyle(color: context.textColor, fontSize: 13),
            onChanged: (val) {
              q['correctAnswers'] = [val.trim()];
            },
          ),
        ),
        if (!isDescriptive) ...[
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: SymbolInputFieldWrapper(
                  controller: _dittoPrefixCtrls[idx],
                  onChanged: () =>
                      q['shortAnswerPrefix'] = _dittoPrefixCtrls[idx].text,
                  child: TextFormField(
                    controller: _dittoPrefixCtrls[idx],
                    decoration: const InputDecoration(
                      labelText: 'Prefix',
                      labelStyle: TextStyle(fontSize: 11),
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    style: TextStyle(color: context.textColor, fontSize: 13),
                    onChanged: (val) => q['shortAnswerPrefix'] = val,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SymbolInputFieldWrapper(
                  controller: _dittoSuffixCtrls[idx],
                  onChanged: () =>
                      q['shortAnswerSuffix'] = _dittoSuffixCtrls[idx].text,
                  child: TextFormField(
                    controller: _dittoSuffixCtrls[idx],
                    decoration: const InputDecoration(
                      labelText: 'Suffix',
                      labelStyle: TextStyle(fontSize: 11),
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    style: TextStyle(color: context.textColor, fontSize: 13),
                    onChanged: (val) => q['shortAnswerSuffix'] = val,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SymbolInputFieldWrapper(
            controller: _dittoHintCtrls[idx],
            onChanged: () => q['shortAnswerHint'] = _dittoHintCtrls[idx].text,
            child: TextFormField(
              controller: _dittoHintCtrls[idx],
              decoration: const InputDecoration(
                labelText: 'Hint (optional)',
                labelStyle: TextStyle(fontSize: 11),
                border: OutlineInputBorder(),
                isDense: true,
              ),
              style: TextStyle(color: context.textColor, fontSize: 13),
              onChanged: (val) => q['shortAnswerHint'] = val,
            ),
          ),
        ],
      ],
    );
  }

  // TRUE_FALSE: fixed True/False options, tap to pick which is correct.
  Widget _buildDittoTrueFalseInput(int idx) {
    final q = _dittoQuestions[idx];

    Widget buildChoiceCard(String label, bool valueForTrue) {
      final bool isSelected = _dittoTrueFalseAnswers[idx] == valueForTrue;
      return Expanded(
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () {
            setState(() {
              _dittoTrueFalseAnswers[idx] = valueForTrue;
              q['correctAnswers'] = [valueForTrue ? '0' : '1'];
            });
          },
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              color: isSelected
                  ? const Color(0xFF10B981).withOpacity(0.15)
                  : (context.isDark ? const Color(0xFF1E293B) : Colors.white),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isSelected ? const Color(0xFF10B981) : context.glassBorder,
                width: isSelected ? 2 : 1,
              ),
            ),
            child: Column(
              children: [
                Icon(
                  isSelected
                      ? Icons.check_circle_rounded
                      : Icons.radio_button_unchecked_rounded,
                  color: isSelected ? const Color(0xFF10B981) : context.textColor54,
                  size: 20,
                ),
                const SizedBox(height: 6),
                Text(
                  label,
                  style: TextStyle(
                    color: isSelected ? const Color(0xFF10B981) : context.textColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Correct Answer:',
          style: TextStyle(
            color: context.textColor70,
            fontWeight: FontWeight.bold,
            fontSize: 11,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            buildChoiceCard('True', true),
            const SizedBox(width: 10),
            buildChoiceCard('False', false),
          ],
        ),
      ],
    );
  }

  // Equation-completion step editor, mirroring _buildEquationEditor() but
  // operating on this ditto's own q['options'] / _dittoEquationStepCtrls[idx].
  Widget _buildDittoEquationEditor(int idx) {
    final q = _dittoQuestions[idx];
    final List optionsList = q['options'] is List ? q['options'] as List : [];
    final List<TextEditingController> stepCtrls = _dittoEquationStepCtrls[idx];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Equation Steps:',
              style: TextStyle(
                color: context.textColor70,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
            TextButton.icon(
              icon: const Icon(Icons.add, size: 14, color: Color(0xFF818CF8)),
              label: const Text(
                'Add Step',
                style: TextStyle(color: Color(0xFF818CF8), fontSize: 12),
              ),
              onPressed: () {
                setState(() {
                  optionsList.add({'text': '', 'imageUrl': '', 'isSvg': false});
                  stepCtrls.add(TextEditingController());
                  _syncDittoEquationAnswers(idx);
                });
              },
            ),
          ],
        ),
        _buildDittoTipBox(
          'Use [INPUT:answer] to add an input box. Example: "= [INPUT:35] + 14"',
        ),
        const SizedBox(height: 8),
        ...List.generate(optionsList.length, (stepIdx) {
          final ctrl = stepCtrls[stepIdx];
          return Card(
            color: context.isDark ? const Color(0xFF1E293B) : Colors.white,
            margin: const EdgeInsets.only(bottom: 8),
            child: Padding(
              padding: const EdgeInsets.all(10.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Step ${stepIdx + 1}',
                        style: TextStyle(
                          color: context.textColor70,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                      if (optionsList.length > 1)
                        IconButton(
                          icon: const Icon(
                            Icons.delete,
                            color: Colors.redAccent,
                            size: 16,
                          ),
                          onPressed: () {
                            setState(() {
                              optionsList.removeAt(stepIdx);
                              stepCtrls.removeAt(stepIdx).dispose();
                              _syncDittoEquationAnswers(idx);
                            });
                          },
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  SymbolInputFieldWrapper(
                    controller: ctrl,
                    onChanged: () {
                      optionsList[stepIdx]['text'] = ctrl.text;
                      _syncDittoEquationAnswers(idx);
                    },
                    child: TextFormField(
                      controller: ctrl,
                      style: TextStyle(color: context.textColor, fontSize: 13),
                      decoration: const InputDecoration(
                        hintText: 'e.g. = [INPUT:35] + 14',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (val) {
                        optionsList[stepIdx]['text'] = val;
                        _syncDittoEquationAnswers(idx);
                      },
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  // Statement-dropdown step editor, mirroring _buildStatementDropdownEditor().
  Widget _buildDittoStatementDropdownEditor(int idx) {
    final q = _dittoQuestions[idx];
    final List optionsList = q['options'] is List ? q['options'] as List : [];
    final List<TextEditingController> stepCtrls = _dittoStatementStepCtrls[idx];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Statements:',
              style: TextStyle(
                color: context.textColor70,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
            TextButton.icon(
              icon: const Icon(Icons.add, size: 14, color: Color(0xFF818CF8)),
              label: const Text(
                'Add Statement',
                style: TextStyle(color: Color(0xFF818CF8), fontSize: 12),
              ),
              onPressed: () {
                setState(() {
                  optionsList.add({'text': '', 'imageUrl': '', 'isSvg': false});
                  stepCtrls.add(TextEditingController());
                  _syncDittoStatementDropdownAnswers(idx);
                });
              },
            ),
          ],
        ),
        _buildDittoTipBox(
          'Use [SELECT:choice1,choice2:correctChoice] for an inline dropdown. Example: "-4.4 is [SELECT:above,below:below] 1.2"',
        ),
        const SizedBox(height: 8),
        ...List.generate(optionsList.length, (stepIdx) {
          final ctrl = stepCtrls[stepIdx];
          return Card(
            color: context.isDark ? const Color(0xFF1E293B) : Colors.white,
            margin: const EdgeInsets.only(bottom: 8),
            child: Padding(
              padding: const EdgeInsets.all(10.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Statement ${stepIdx + 1}',
                        style: TextStyle(
                          color: context.textColor70,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                      if (optionsList.length > 1)
                        IconButton(
                          icon: const Icon(
                            Icons.delete,
                            color: Colors.redAccent,
                            size: 16,
                          ),
                          onPressed: () {
                            setState(() {
                              optionsList.removeAt(stepIdx);
                              stepCtrls.removeAt(stepIdx).dispose();
                              _syncDittoStatementDropdownAnswers(idx);
                            });
                          },
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  SymbolInputFieldWrapper(
                    controller: ctrl,
                    onChanged: () {
                      optionsList[stepIdx]['text'] = ctrl.text;
                      _syncDittoStatementDropdownAnswers(idx);
                    },
                    child: TextFormField(
                      controller: ctrl,
                      style: TextStyle(color: context.textColor, fontSize: 13),
                      decoration: const InputDecoration(
                        hintText: 'e.g. -4.4 is [SELECT:above,below:below] 1.2',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (val) {
                        optionsList[stepIdx]['text'] = val;
                        _syncDittoStatementDropdownAnswers(idx);
                      },
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  // Matrix MCQ grid editor, mirroring _buildMatrixMCQEditor(). Rows/columns
  // use initialValue+onChanged directly against q['options']/q['rightOptions']
  // (no persistent controllers), matching the main form's own pattern there.
  Widget _buildDittoMatrixMCQEditor(int idx) {
    final q = _dittoQuestions[idx];
    final List optionsList = q['options'] is List ? q['options'] as List : [];
    final List rightOptionsList =
        q['rightOptions'] is List ? q['rightOptions'] as List : [];
    final List<String> correctAnswers = _dittoMatrixCorrectAnswers[idx];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Grid Rows:',
              style: TextStyle(
                color: context.textColor70,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
            TextButton.icon(
              icon: const Icon(Icons.add, size: 14, color: Color(0xFF818CF8)),
              label: const Text('Add Row', style: TextStyle(color: Color(0xFF818CF8), fontSize: 12)),
              onPressed: () {
                setState(() {
                  optionsList.add({'text': '', 'imageUrl': '', 'isSvg': false});
                  correctAnswers.add('0');
                });
              },
            ),
          ],
        ),
        ...List.generate(optionsList.length, (rowIdx) {
          final row = optionsList[rowIdx];
          return Padding(
            padding: const EdgeInsets.only(bottom: 6.0),
            child: Row(
              children: [
                Expanded(
                  child: TextFormField(
                    initialValue: row['text'],
                    style: TextStyle(color: context.textColor, fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'Row ${rowIdx + 1} label',
                      isDense: true,
                      border: const OutlineInputBorder(),
                    ),
                    onChanged: (val) => row['text'] = val,
                  ),
                ),
                if (optionsList.length > 1)
                  IconButton(
                    icon: const Icon(Icons.delete, color: Colors.redAccent, size: 16),
                    onPressed: () {
                      setState(() {
                        optionsList.removeAt(rowIdx);
                        if (rowIdx < correctAnswers.length) {
                          correctAnswers.removeAt(rowIdx);
                        }
                        q['correctAnswers'] = List<String>.from(correctAnswers);
                      });
                    },
                  ),
              ],
            ),
          );
        }),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Grid Columns:',
              style: TextStyle(
                color: context.textColor70,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
            TextButton.icon(
              icon: const Icon(Icons.add, size: 14, color: Color(0xFF818CF8)),
              label: const Text('Add Column', style: TextStyle(color: Color(0xFF818CF8), fontSize: 12)),
              onPressed: () {
                setState(() {
                  rightOptionsList.add({'text': '', 'imageUrl': '', 'isSvg': false});
                });
              },
            ),
          ],
        ),
        ...List.generate(rightOptionsList.length, (colIdx) {
          final col = rightOptionsList[colIdx];
          return Padding(
            padding: const EdgeInsets.only(bottom: 6.0),
            child: Row(
              children: [
                Expanded(
                  child: TextFormField(
                    initialValue: col['text'],
                    style: TextStyle(color: context.textColor, fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'Column ${colIdx + 1} label',
                      isDense: true,
                      border: const OutlineInputBorder(),
                    ),
                    onChanged: (val) => col['text'] = val,
                  ),
                ),
                if (rightOptionsList.length > 1)
                  IconButton(
                    icon: const Icon(Icons.delete, color: Colors.redAccent, size: 16),
                    onPressed: () {
                      setState(() {
                        rightOptionsList.removeAt(colIdx);
                        for (int i = 0; i < correctAnswers.length; i++) {
                          final int sel = int.tryParse(correctAnswers[i]) ?? 0;
                          if (sel >= rightOptionsList.length) {
                            correctAnswers[i] = (rightOptionsList.length - 1)
                                .clamp(0, 1 << 30)
                                .toString();
                          }
                        }
                        q['correctAnswers'] = List<String>.from(correctAnswers);
                      });
                    },
                  ),
              ],
            ),
          );
        }),
        const SizedBox(height: 12),
        Text(
          'Select correct answer for each row:',
          style: TextStyle(color: context.textColor60, fontSize: 11),
        ),
        const SizedBox(height: 6),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Table(
            defaultColumnWidth: const FixedColumnWidth(90.0),
            border: TableBorder.all(color: context.glassBorder),
            children: [
              TableRow(
                children: [
                  const TableCell(child: Padding(padding: EdgeInsets.all(6), child: Text(''))),
                  ...List.generate(rightOptionsList.length, (colIdx) {
                    final colText = rightOptionsList[colIdx]['text'] ?? '';
                    return TableCell(
                      child: Padding(
                        padding: const EdgeInsets.all(6.0),
                        child: Center(
                          child: Text(
                            colText.isNotEmpty ? colText : 'Col ${colIdx + 1}',
                            style: TextStyle(
                              color: context.textColor70,
                              fontWeight: FontWeight.bold,
                              fontSize: 11,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    );
                  }),
                ],
              ),
              ...List.generate(optionsList.length, (rowIdx) {
                if (rowIdx >= correctAnswers.length) {
                  correctAnswers.add('0');
                }
                final int currentSel = int.tryParse(correctAnswers[rowIdx]) ?? 0;
                final rowText = optionsList[rowIdx]['text'] ?? '';
                return TableRow(
                  children: [
                    TableCell(
                      verticalAlignment: TableCellVerticalAlignment.middle,
                      child: Padding(
                        padding: const EdgeInsets.all(6.0),
                        child: Text(
                          rowText.isNotEmpty ? rowText : 'Row ${rowIdx + 1}',
                          style: TextStyle(color: context.textColor, fontSize: 11),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    ...List.generate(rightOptionsList.length, (colIdx) {
                      return TableCell(
                        child: Center(
                          child: Radio<int>(
                            value: colIdx,
                            groupValue: currentSel,
                            activeColor: const Color(0xFF6366F1),
                            onChanged: (val) {
                              if (val != null) {
                                setState(() {
                                  correctAnswers[rowIdx] = val.toString();
                                  q['correctAnswers'] = List<String>.from(correctAnswers);
                                });
                              }
                            },
                          ),
                        ),
                      );
                    }),
                  ],
                );
              }),
            ],
          ),
        ),
      ],
    );
  }

  // Matrix Input grid editor, mirroring _buildMatrixInputEditor(). Cells use
  // initialValue+onChanged (no persistent controllers), matching the main
  // form's own pattern; every edit re-encodes back into q['options'][r]['text']
  // and recomputes q['correctAnswers'] via _syncDittoMatrixInputRows.
  Widget _buildDittoMatrixInputEditor(int idx) {
    final q = _dittoQuestions[idx];
    final List optionsList = q['options'] is List ? q['options'] as List : [];
    final List rightOptionsList =
        q['rightOptions'] is List ? q['rightOptions'] as List : [];
    final List<List<Map<String, dynamic>>> cells = _dittoMatrixInputCells[idx];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Table Columns:',
              style: TextStyle(
                color: context.textColor70,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
            TextButton.icon(
              icon: const Icon(Icons.add, size: 14, color: Color(0xFF818CF8)),
              label: const Text('Add Column', style: TextStyle(color: Color(0xFF818CF8), fontSize: 12)),
              onPressed: () {
                setState(() {
                  rightOptionsList.add({'text': '', 'imageUrl': '', 'isSvg': false});
                  for (final row in cells) {
                    row.add({'value': '', 'isInput': false});
                  }
                  _syncDittoMatrixInputRows(idx);
                });
              },
            ),
          ],
        ),
        ...List.generate(rightOptionsList.length, (colIdx) {
          final col = rightOptionsList[colIdx];
          return Padding(
            padding: const EdgeInsets.only(bottom: 6.0),
            child: Row(
              children: [
                Expanded(
                  child: TextFormField(
                    initialValue: col['text'],
                    style: TextStyle(color: context.textColor, fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'Column ${colIdx + 1} header',
                      isDense: true,
                      border: const OutlineInputBorder(),
                    ),
                    onChanged: (val) => col['text'] = val,
                  ),
                ),
                if (rightOptionsList.length > 1)
                  IconButton(
                    icon: const Icon(Icons.delete, color: Colors.redAccent, size: 16),
                    onPressed: () {
                      setState(() {
                        rightOptionsList.removeAt(colIdx);
                        for (final row in cells) {
                          if (colIdx < row.length) row.removeAt(colIdx);
                        }
                        _syncDittoMatrixInputRows(idx);
                      });
                    },
                  ),
              ],
            ),
          );
        }),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Table Rows & Cells:',
              style: TextStyle(
                color: context.textColor70,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
            TextButton.icon(
              icon: const Icon(Icons.add, size: 14, color: Color(0xFF818CF8)),
              label: const Text('Add Row', style: TextStyle(color: Color(0xFF818CF8), fontSize: 12)),
              onPressed: () {
                setState(() {
                  optionsList.add({'text': '', 'imageUrl': '', 'isSvg': false});
                  cells.add(
                    List.generate(
                      rightOptionsList.length,
                      (c) => {'value': '', 'isInput': false},
                    ),
                  );
                  _syncDittoMatrixInputRows(idx);
                });
              },
            ),
          ],
        ),
        _buildDittoTipBox('Check "Input?" for cells students must fill in.'),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Table(
            defaultColumnWidth: const FixedColumnWidth(120.0),
            border: TableBorder.all(color: context.glassBorder),
            children: [
              TableRow(
                children: [
                  const TableCell(child: Padding(padding: EdgeInsets.all(6), child: Text(''))),
                  ...List.generate(rightOptionsList.length, (colIdx) {
                    final colText = rightOptionsList[colIdx]['text'] ?? '';
                    return TableCell(
                      child: Padding(
                        padding: const EdgeInsets.all(6.0),
                        child: Center(
                          child: Text(
                            colText.isNotEmpty ? colText : 'Col ${colIdx + 1}',
                            style: TextStyle(
                              color: context.textColor70,
                              fontWeight: FontWeight.bold,
                              fontSize: 11,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    );
                  }),
                  const TableCell(child: Padding(padding: EdgeInsets.all(6), child: Text(''))),
                ],
              ),
              ...List.generate(optionsList.length, (rowIdx) {
                while (cells.length <= rowIdx) {
                  cells.add(
                    List.generate(rightOptionsList.length, (c) => {'value': '', 'isInput': false}),
                  );
                }
                while (cells[rowIdx].length < rightOptionsList.length) {
                  cells[rowIdx].add({'value': '', 'isInput': false});
                }
                return TableRow(
                  children: [
                    TableCell(
                      verticalAlignment: TableCellVerticalAlignment.middle,
                      child: Padding(
                        padding: const EdgeInsets.all(6.0),
                        child: Text('Row ${rowIdx + 1}', style: TextStyle(color: context.textColor60, fontSize: 11)),
                      ),
                    ),
                    ...List.generate(rightOptionsList.length, (colIdx) {
                      final cell = cells[rowIdx][colIdx];
                      final bool isInput = cell['isInput'] == true;
                      return TableCell(
                        child: Padding(
                          padding: const EdgeInsets.all(4.0),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              TextFormField(
                                initialValue: cell['value'],
                                style: TextStyle(color: context.textColor, fontSize: 12),
                                decoration: InputDecoration(
                                  hintText: isInput ? 'Correct value' : 'Label value',
                                  isDense: true,
                                  contentPadding: const EdgeInsets.all(6),
                                ),
                                onChanged: (val) {
                                  cell['value'] = val;
                                  _syncDittoMatrixInputRows(idx);
                                },
                              ),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text('Input?', style: TextStyle(color: context.textColor54, fontSize: 9)),
                                  Checkbox(
                                    value: isInput,
                                    activeColor: const Color(0xFF6366F1),
                                    onChanged: (val) {
                                      setState(() {
                                        cell['isInput'] = val == true;
                                        _syncDittoMatrixInputRows(idx);
                                      });
                                    },
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                    TableCell(
                      verticalAlignment: TableCellVerticalAlignment.middle,
                      child: Center(
                        child: IconButton(
                          icon: const Icon(Icons.delete, color: Colors.redAccent, size: 16),
                          onPressed: () {
                            setState(() {
                              optionsList.removeAt(rowIdx);
                              cells.removeAt(rowIdx);
                              _syncDittoMatrixInputRows(idx);
                            });
                          },
                        ),
                      ),
                    ),
                  ],
                );
              }),
            ],
          ),
        ),
      ],
    );
  }

  // Step-by-step (numbered, block-based) solution editor for a Ditto
  // question, mirroring _buildExplanationEditorCard()'s step/block section
  // but operating on this ditto's own q['explanationSteps'] instead of the
  // main question's _explanationSteps. Text blocks use an ephemeral
  // per-rebuild controller seeded from block['content'], matching the exact
  // pattern the main form itself already uses for `blockTextCtrl`.
  Widget _buildDittoExplanationStepsEditor(int idx) {
    final q = _dittoQuestions[idx];
    final bool isDark = context.isDark;
    if (q['explanationSteps'] == null || q['explanationSteps'] is! List) {
      q['explanationSteps'] = <Map<String, dynamic>>[];
    }
    final List<dynamic> steps = q['explanationSteps'];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Numbered Solution Steps (${steps.length}):',
              style: TextStyle(
                color: context.textColor70,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
            TextButton.icon(
              onPressed: () {
                setState(() {
                  steps.add({
                    'stepNumber': steps.length + 1,
                    'title': '',
                    'text': '',
                    'imageUrl': '',
                    'isSvg': false,
                  });
                });
              },
              icon: const Icon(Icons.add_rounded, size: 14, color: Color(0xFF3B82F6)),
              label: const Text('Add Step', style: TextStyle(color: Color(0xFF3B82F6), fontSize: 12)),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ...List.generate(steps.length, (sIdx) {
          final Map<String, dynamic> step = steps[sIdx] as Map<String, dynamic>;
          step['stepNumber'] = sIdx + 1;

          if (step['blocks'] == null) {
            final List<Map<String, dynamic>> initialBlocks = [];
            if ((step['text'] ?? '').toString().isNotEmpty) {
              initialBlocks.add({'type': 'TEXT', 'content': step['text'], 'isSvg': false});
            }
            if ((step['imageUrl'] ?? '').toString().isNotEmpty) {
              initialBlocks.add({
                'type': 'IMAGE',
                'content': step['imageUrl'],
                'isSvg': step['isSvg'] == true,
              });
            }
            if (initialBlocks.isEmpty) {
              initialBlocks.add({'type': 'TEXT', 'content': '', 'isSvg': false});
            }
            step['blocks'] = initialBlocks;
          }
          final List<dynamic> blocks = step['blocks'];

          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: BorderSide(color: const Color(0xFF3B82F6).withOpacity(0.35)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFF3B82F6).withOpacity(0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          'Step ${sIdx + 1}',
                          style: const TextStyle(
                            color: Color(0xFF3B82F6),
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const Spacer(),
                      OutlinedButton.icon(
                        onPressed: () {
                          setState(() {
                            blocks.add({'type': 'TEXT', 'content': '', 'isSvg': false});
                          });
                        },
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          side: const BorderSide(color: Color(0xFF3B82F6)),
                        ),
                        icon: const Icon(Icons.add_circle_outline, size: 14, color: Color(0xFF3B82F6)),
                        label: const Text('+ Text', style: TextStyle(fontSize: 11, color: Color(0xFF3B82F6))),
                      ),
                      const SizedBox(width: 6),
                      OutlinedButton.icon(
                        onPressed: () {
                          setState(() {
                            blocks.add({'type': 'IMAGE', 'content': '', 'isSvg': false});
                          });
                        },
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          side: const BorderSide(color: Color(0xFF10B981)),
                        ),
                        icon: const Icon(Icons.add_photo_alternate_outlined, size: 14, color: Color(0xFF10B981)),
                        label: const Text('+ Image', style: TextStyle(fontSize: 11, color: Color(0xFF10B981))),
                      ),
                      const SizedBox(width: 4),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 18),
                        onPressed: () {
                          setState(() {
                            steps.removeAt(sIdx);
                          });
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  ...List.generate(blocks.length, (bIdx) {
                    final block = blocks[bIdx] as Map<String, dynamic>;
                    final String bType = block['type'] ?? 'TEXT';

                    if (bType == 'IMAGE') {
                      final String imgContent = block['content'] ?? '';
                      final bool isSvg = block['isSvg'] == true;
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF1E293B) : Colors.white,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFF10B981).withOpacity(0.4)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.image_rounded, color: Color(0xFF10B981), size: 20),
                            const SizedBox(width: 8),
                            Expanded(
                              child: imgContent.isNotEmpty
                                  ? Row(
                                      children: [
                                        ClipRRect(
                                          borderRadius: BorderRadius.circular(6),
                                          child: SizedBox(
                                            height: 50,
                                            width: 70,
                                            child: _renderQuestionImagePreview(imgContent, isSvg: isSvg),
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Text(
                                            imgContent,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(fontSize: 11, color: context.textColor70),
                                          ),
                                        ),
                                      ],
                                    )
                                  : const Text(
                                      'No diagram uploaded yet',
                                      style: TextStyle(fontSize: 12, color: Colors.grey),
                                    ),
                            ),
                            ElevatedButton.icon(
                              onPressed: () async {
                                try {
                                  final result = await FilePicker.pickFiles(type: FileType.image);
                                  if (result != null && result.files.single.bytes != null) {
                                    final bytes = result.files.single.bytes!;
                                    final filename = result.files.single.name;
                                    final isSvgFile = filename.toLowerCase().endsWith('.svg');

                                    final res = await ApiService.uploadFile(
                                      '/assessment-questions/upload',
                                      bytes,
                                      filename,
                                      fieldName: 'file',
                                    );

                                    if (res.statusCode == 200) {
                                      final resBody = await res.stream.bytesToString();
                                      final data = jsonDecode(resBody);
                                      setState(() {
                                        block['content'] = data['fileUrl'];
                                        block['isSvg'] = isSvgFile;
                                      });
                                    }
                                  }
                                } catch (e) {
                                  _showSnackBar('Upload error: $e');
                                }
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF10B981),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              ),
                              icon: const Icon(Icons.upload_file_rounded, size: 14),
                              label: Text(imgContent.isEmpty ? 'Upload Image' : 'Change', style: const TextStyle(fontSize: 11)),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close_rounded, size: 16, color: Colors.redAccent),
                              onPressed: () {
                                setState(() {
                                  blocks.removeAt(bIdx);
                                });
                              },
                            ),
                          ],
                        ),
                      );
                    }

                    // TEXT Block
                    final blockTextCtrl = TextEditingController(text: block['content'] ?? '');
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: SymbolInputFieldWrapper(
                              controller: blockTextCtrl,
                              onChanged: () {
                                block['content'] = blockTextCtrl.text;
                              },
                              child: TextFormField(
                                controller: blockTextCtrl,
                                decoration: InputDecoration(
                                  labelText: 'Text Block #${bIdx + 1}',
                                  hintText: 'e.g., 53 is between 50 and 60...',
                                  labelStyle: TextStyle(fontSize: 11, color: context.textColor70),
                                  border: const OutlineInputBorder(),
                                  isDense: true,
                                ),
                                style: TextStyle(color: context.textColor, fontSize: 13),
                                maxLines: 2,
                                onChanged: (val) {
                                  block['content'] = val;
                                },
                              ),
                            ),
                          ),
                          if (blocks.length > 1) ...[
                            const SizedBox(width: 4),
                            IconButton(
                              icon: const Icon(Icons.close_rounded, size: 16, color: Colors.redAccent),
                              onPressed: () {
                                setState(() {
                                  blocks.removeAt(bIdx);
                                });
                              },
                            ),
                          ],
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isEdit = widget.existingQuestion != null;
    final isDark = context.isDark;

    return Scaffold(
      backgroundColor: isDark
          ? const Color(0xFF0F172A)
          : const Color(0xFFF1F5F9),
      appBar: AppBar(
        title: Text(
          isEdit ? 'Edit Assessment Question' : 'Add Assessment Question',
          style: TextStyle(
            color: context.textColor,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
        elevation: isDark ? 0 : 1,
        shadowColor: isDark ? Colors.transparent : Colors.black12,
        iconTheme: IconThemeData(color: context.textColor),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: _buildGlobalSymbolToolbar(),
          ),
          if (_isLoading)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: JyamitiLoader(
                    color: context.textColor,
                    strokeWidth: 2,
                  ),
                ),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.only(right: 12.0),
              child: ElevatedButton.icon(
                onPressed: _saveQuestion,
                icon: const Icon(
                  Icons.check_circle_rounded,
                  size: 18,
                  color: Colors.white,
                ),
                label: const Text(
                  'Save Question(s)',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6366F1),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final bool isWide = constraints.maxWidth >= 900;
          final double horizontalPadding = isWide ? 32.0 : 16.0;

          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1280),
              child: SingleChildScrollView(
                padding: EdgeInsets.all(horizontalPadding),
                child: Form(
                  key: _formKey,
                  child: isWide
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Left Column: Metadata, Question Prompt & Media
                            Expanded(
                              flex: 5,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  _buildMetadataCard(isDark),
                                  const SizedBox(height: 20),
                                  _buildPromptCard(isDark),
                                  const SizedBox(height: 20),
                                  _buildExplanationEditorCard(isDark),
                                  const SizedBox(height: 20),
                                  _buildQuestionImageUploadSection(),
                                ],
                              ),
                            ),
                            const SizedBox(width: 24),
                            // Right Column: Answer Options & Actions
                            Expanded(
                              flex: 6,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  _buildAnswerOptionsCard(isDark),
                                  const SizedBox(height: 20),
                                  _buildActionButtonsRow(),
                                  _buildDittoQuestionsSection(),
                                  if (widget.isPracticeMode) ...[
                                    const SizedBox(height: 20),
                                    _buildAIGenerationSection(),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _buildMetadataCard(isDark),
                            const SizedBox(height: 20),
                            _buildPromptCard(isDark),
                            const SizedBox(height: 20),
                            _buildExplanationEditorCard(isDark),
                            const SizedBox(height: 20),
                            _buildQuestionImageUploadSection(),
                            const SizedBox(height: 20),
                            _buildAnswerOptionsCard(isDark),
                            const SizedBox(height: 20),
                            _buildActionButtonsRow(),
                            _buildDittoQuestionsSection(),
                            if (widget.isPracticeMode) ...[
                              const SizedBox(height: 20),
                              _buildAIGenerationSection(),
                            ],
                          ],
                        ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildMetadataCard(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.glassBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.3 : 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF6366F1).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.tune_rounded,
                  color: Color(0xFF6366F1),
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                'Question Configuration',
                style: TextStyle(
                  color: context.textColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (ctx, constraints) {
              final bool isRow = constraints.maxWidth > 520;
              return isRow
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (!widget.isPracticeMode) ...[
                          Expanded(child: _buildGradeDropdown()),
                          const SizedBox(width: 12),
                        ],
                        Expanded(flex: 2, child: _buildTypeDropdown()),
                        const SizedBox(width: 12),
                        Expanded(child: _buildMarksField()),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (!widget.isPracticeMode) ...[
                          _buildGradeDropdown(),
                          const SizedBox(height: 12),
                        ],
                        _buildTypeDropdown(),
                        const SizedBox(height: 12),
                        _buildMarksField(),
                      ],
                    );
            },
          ),
          const SizedBox(height: 12),
          SwitchListTile(
            title: Text(
              'Tutor Only (Classwork Question)',
              style: TextStyle(
                color: context.textColor,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
            subtitle: Text(
              'Visible exclusively in Tutor Mode for classroom teaching & demonstrations.',
              style: TextStyle(
                color: context.textColor60,
                fontSize: 11,
              ),
            ),
            value: _isClasswork,
            activeColor: const Color(0xFF10B981),
            contentPadding: EdgeInsets.zero,
            onChanged: (val) => setState(() => _isClasswork = val),
          ),
        ],
      ),
    );
  }

  Widget _buildGradeDropdown() {
    return DropdownButtonFormField<int>(
      value: _grade,
      dropdownColor: context.isDark ? const Color(0xFF1E293B) : Colors.white,
      style: TextStyle(color: context.textColor),
      decoration: InputDecoration(
        labelText: 'Grade Level',
        labelStyle: TextStyle(color: context.textColor70),
        filled: true,
        fillColor: context.isDark
            ? const Color(0xFF0F172A)
            : const Color(0xFFF8FAFC),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        isDense: true,
      ),
      items: List.generate(12, (index) {
        final grade = index + 1;
        return DropdownMenuItem<int>(
          value: grade,
          child: Text(
            'Grade $grade',
            style: TextStyle(color: context.textColor),
          ),
        );
      }),
      onChanged: (val) {
        if (val != null) setState(() => _grade = val);
      },
    );
  }

  Widget _buildTypeDropdown() {
    return DropdownButtonFormField<String>(
      value: _type,
      dropdownColor: context.isDark ? const Color(0xFF1E293B) : Colors.white,
      style: TextStyle(color: context.textColor),
      decoration: InputDecoration(
        labelText: 'Question Type',
        labelStyle: TextStyle(color: context.textColor70),
        filled: true,
        fillColor: context.isDark
            ? const Color(0xFF0F172A)
            : const Color(0xFFF8FAFC),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        isDense: true,
      ),
      items: const [
        DropdownMenuItem(
          value: 'MCQ_SINGLE',
          child: Text('Single Choice MCQ'),
        ),
        DropdownMenuItem(
          value: 'MCQ_MULTI',
          child: Text('Multiple Choice MCQ'),
        ),
        DropdownMenuItem(
          value: 'TRUE_FALSE',
          child: Text('True / False'),
        ),
        DropdownMenuItem(
          value: 'SHORT_ANSWER',
          child: Text('Short Answer'),
        ),
        DropdownMenuItem(
          value: 'ORDERING',
          child: Text('Ordering / Sequencing'),
        ),
        DropdownMenuItem(
          value: 'MATCHING',
          child: Text('Match the Following'),
        ),
        DropdownMenuItem(
          value: 'GEOMETRIC',
          child: Text('Geometric Construction'),
        ),
        DropdownMenuItem(
          value: 'MATRIX_MCQ',
          child: Text('Grid / Matrix MCQ'),
        ),
        DropdownMenuItem(
          value: 'MATRIX_INPUT',
          child: Text('Matrix / Table Input'),
        ),
        DropdownMenuItem(
          value: 'EQUATION',
          child: Text('Multi-Step Equation'),
        ),
        DropdownMenuItem(
          value: 'STATEMENT_DROPDOWN',
          child: Text('Statement Dropdown'),
        ),
        DropdownMenuItem(
          value: 'INLINE_SELECT',
          child: Text('Inline Select'),
        ),
        DropdownMenuItem(
          value: 'FILL_IN_BLANKS',
          child: Text('Fill in the Blanks ([BLANK:answer])'),
        ),
        DropdownMenuItem(
          value: 'DESCRIPTIVE',
          child: Text('Descriptive / Handwritten (AI Evaluated)'),
        ),
      ],
      onChanged: (v) {
        if (v != null) {
          setState(() {
            _type = v;
            if (_type == 'MATCHING' && _rightOptions.isEmpty) {
              _rightOptions = List.generate(
                _options.length,
                (index) => {
                  'text': '',
                  'imageUrl': '',
                  'isSvg': false,
                },
              );
            }
            if (_type == 'MATRIX_MCQ') {
              if (_options.isEmpty) {
                _options = [
                  {'text': 'Row 1', 'imageUrl': '', 'isSvg': false},
                ];
              }
              if (_rightOptions.isEmpty) {
                _rightOptions = [
                  {
                    'text': 'Column 1',
                    'imageUrl': '',
                    'isSvg': false,
                  },
                ];
              }
              _matrixCorrectAnswers = List.generate(
                _options.length,
                (idx) => "0",
              );
            }
            if (_type == 'MATRIX_INPUT') {
              if (_options.isEmpty) {
                _options = [
                  {'text': '', 'imageUrl': '', 'isSvg': false},
                ];
              }
              if (_rightOptions.isEmpty) {
                _rightOptions = [
                  {
                    'text': 'Header 1',
                    'imageUrl': '',
                    'isSvg': false,
                  },
                ];
              }
              _matrixInputCells = List.generate(
                _options.length,
                (r) => List.generate(
                  _rightOptions.length,
                  (c) => {'value': '', 'isInput': false},
                ),
              );
            }
            if (_type == 'EQUATION') {
              if (_options.isEmpty) {
                _options = [
                  {'text': '', 'imageUrl': '', 'isSvg': false},
                ];
              }
              _equationStepControllers = List.generate(
                _options.length,
                (idx) => TextEditingController(
                  text: _options[idx]['text'] ?? '',
                ),
              );
            }
            if (_type == 'STATEMENT_DROPDOWN') {
              if (_options.isEmpty) {
                _options = [
                  {'text': '', 'imageUrl': '', 'isSvg': false},
                ];
              }
              _statementStepControllers = List.generate(
                _options.length,
                (idx) => TextEditingController(
                  text: _options[idx]['text'] ?? '',
                ),
              );
            }
          });
        }
      },
    );
  }

  Widget _buildMarksField() {
    return TextFormField(
      controller: _marksCtrl,
      style: TextStyle(color: context.textColor),
      keyboardType: TextInputType.number,
      decoration: InputDecoration(
        labelText: 'Marks / Points',
        labelStyle: TextStyle(color: context.textColor70),
        filled: true,
        fillColor: context.isDark
            ? const Color(0xFF0F172A)
            : const Color(0xFFF8FAFC),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        isDense: true,
      ),
      validator: (v) => (v == null || int.tryParse(v) == null)
          ? 'Enter a valid number'
          : null,
    );
  }

  Widget _buildPromptCard(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.glassBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.3 : 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF3B82F6).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.edit_note_rounded,
                  color: Color(0xFF3B82F6),
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                'Question Text & Context',
                style: TextStyle(
                  color: context.textColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SymbolInputFieldWrapper(
            controller: _descriptiveTextCtrl,
            child: TextFormField(
              controller: _descriptiveTextCtrl,
              style: TextStyle(color: context.textColor),
              decoration: InputDecoration(
                labelText: 'Descriptive Context Text (Optional)',
                hintText: 'e.g., Read the instructions or passage below...',
                labelStyle: TextStyle(color: context.textColor70),
                filled: true,
                fillColor: isDark
                    ? const Color(0xFF0F172A)
                    : const Color(0xFFF8FAFC),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
              maxLines: 2,
            ),
          ),
          const SizedBox(height: 16),
          SymbolInputFieldWrapper(
            controller: _textCtrl,
            child: TextFormField(
              controller: _textCtrl,
              style: TextStyle(color: context.textColor),
              decoration: InputDecoration(
                labelText: 'Question Text *',
                hintText: 'Enter the main question prompt here...',
                labelStyle: TextStyle(color: context.textColor70),
                filled: true,
                fillColor: isDark
                    ? const Color(0xFF0F172A)
                    : const Color(0xFFF8FAFC),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
              maxLines: 4,
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? 'Please enter question text'
                  : null,
            ),
          ),
          if (_type == 'FILL_IN_BLANKS') ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF10B981).withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF10B981).withOpacity(0.4)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline_rounded, color: Color(0xFF10B981), size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Insert blanks in your text using [BLANK:answer] or [INPUT:answer] or [BLANK] tags.\nExample: "The area of a circle with radius \$r\$ is [BLANK:\\pi r^2] and perimeter is [BLANK:2\\pi r]."',
                      style: TextStyle(
                        color: context.textColor,
                        fontSize: 12,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (_type == 'INLINE_SELECT') ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF10B981).withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF10B981).withOpacity(0.4)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline_rounded, color: Color(0xFF10B981), size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Insert dropdown boxes in your text using [SELECT:choice1,choice2,...:correctChoice] tags.\nExample: "The value of \$\\pi\$ is approximately [SELECT:3.14,4.13,2.71:3.14]."',
                      style: TextStyle(
                        color: context.textColor,
                        fontSize: 12,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (_type == 'DESCRIPTIVE') ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF6366F1).withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF6366F1).withOpacity(0.4)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.auto_awesome, color: Color(0xFF6366F1), size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Descriptive / Handwritten Question: Students write on paper or drawing pad and upload an image of their solution. DeepSeek AI will evaluate the semantic meaning of their answer against your Preset Model Answer gently and politely.',
                      style: TextStyle(
                        color: context.textColor,
                        fontSize: 12,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildExplanationEditorCard(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.glassBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.3 : 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF3B82F6).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.lightbulb_outline_rounded,
                  color: Color(0xFF3B82F6),
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                'Step-by-Step Solution & Explanation',
                style: TextStyle(
                  color: context.textColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // General Solution Explanation Text
          SymbolInputFieldWrapper(
            controller: _explanationCtrl,
            child: TextFormField(
              controller: _explanationCtrl,
              style: TextStyle(color: context.textColor),
              decoration: InputDecoration(
                labelText: 'General Solution Explanation (Optional)',
                hintText: 'e.g., To round 53 to the nearest ten, look at the ones digit...',
                labelStyle: TextStyle(color: context.textColor70),
                filled: true,
                fillColor: isDark
                    ? const Color(0xFF0F172A)
                    : const Color(0xFFF8FAFC),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
              maxLines: 3,
            ),
          ),
          const SizedBox(height: 16),

          // Step-by-Step Explanation Items Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Numbered Solution Steps (${_explanationSteps.length}):',
                style: TextStyle(
                  color: context.textColor70,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
              ElevatedButton.icon(
                onPressed: () {
                  setState(() {
                    _explanationSteps.add({
                      'stepNumber': _explanationSteps.length + 1,
                      'title': '',
                      'text': '',
                      'imageUrl': '',
                      'isSvg': false,
                    });
                  });
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF3B82F6),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                icon: const Icon(Icons.add_rounded, size: 16),
                label: const Text('Add Step', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 10),

          ...List.generate(_explanationSteps.length, (sIdx) {
            final step = _explanationSteps[sIdx];
            step['stepNumber'] = sIdx + 1;

            if (step['blocks'] == null) {
              final List<Map<String, dynamic>> initialBlocks = [];
              if ((step['text'] ?? '').toString().isNotEmpty) {
                initialBlocks.add({'type': 'TEXT', 'content': step['text'], 'isSvg': false});
              }
              if ((step['imageUrl'] ?? '').toString().isNotEmpty) {
                initialBlocks.add({'type': 'IMAGE', 'content': step['imageUrl'], 'isSvg': step['isSvg'] == true});
              }
              if (initialBlocks.isEmpty) {
                initialBlocks.add({'type': 'TEXT', 'content': '', 'isSvg': false});
              }
              step['blocks'] = initialBlocks;
            }

            final List<dynamic> blocks = step['blocks'];

            return Card(
              margin: const EdgeInsets.only(bottom: 16),
              color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(
                  color: const Color(0xFF3B82F6).withOpacity(0.35),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(14.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFF3B82F6).withOpacity(0.15),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            'Step ${sIdx + 1}',
                            style: const TextStyle(
                              color: Color(0xFF3B82F6),
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const Spacer(),
                        OutlinedButton.icon(
                          onPressed: () {
                            setState(() {
                              blocks.add({'type': 'TEXT', 'content': '', 'isSvg': false});
                            });
                          },
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            side: const BorderSide(color: Color(0xFF3B82F6)),
                          ),
                          icon: const Icon(Icons.add_circle_outline, size: 14, color: Color(0xFF3B82F6)),
                          label: const Text('+ Text Block', style: TextStyle(fontSize: 11, color: Color(0xFF3B82F6))),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          onPressed: () {
                            setState(() {
                              blocks.add({'type': 'IMAGE', 'content': '', 'isSvg': false});
                            });
                          },
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            side: const BorderSide(color: Color(0xFF10B981)),
                          ),
                          icon: const Icon(Icons.add_photo_alternate_outlined, size: 14, color: Color(0xFF10B981)),
                          label: const Text('+ Image Block', style: TextStyle(fontSize: 11, color: Color(0xFF10B981))),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
                          onPressed: () {
                            setState(() {
                              _explanationSteps.removeAt(sIdx);
                            });
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Block Items Rendering inside Step
                    ...List.generate(blocks.length, (bIdx) {
                      final block = blocks[bIdx] as Map<String, dynamic>;
                      final String bType = block['type'] ?? 'TEXT';

                      if (bType == 'IMAGE') {
                        final String imgContent = block['content'] ?? '';
                        final bool isSvg = block['isSvg'] == true;

                        return Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: isDark ? const Color(0xFF1E293B) : Colors.white,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFF10B981).withOpacity(0.4)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.image_rounded, color: Color(0xFF10B981), size: 20),
                              const SizedBox(width: 8),
                              Expanded(
                                child: imgContent.isNotEmpty
                                    ? Row(
                                        children: [
                                          ClipRRect(
                                            borderRadius: BorderRadius.circular(6),
                                            child: SizedBox(
                                              height: 50,
                                              width: 70,
                                              child: _renderQuestionImagePreview(imgContent, isSvg: isSvg),
                                            ),
                                          ),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: Text(
                                              imgContent,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(fontSize: 11, color: context.textColor70),
                                            ),
                                          ),
                                        ],
                                      )
                                    : const Text(
                                        'No diagram uploaded yet',
                                        style: TextStyle(fontSize: 12, color: Colors.grey),
                                      ),
                              ),
                              ElevatedButton.icon(
                                onPressed: () async {
                                  try {
                                    final result = await FilePicker.pickFiles(type: FileType.image);
                                    if (result != null && result.files.single.bytes != null) {
                                      final bytes = result.files.single.bytes!;
                                      final filename = result.files.single.name;
                                      final isSvgFile = filename.toLowerCase().endsWith('.svg');

                                      final res = await ApiService.uploadFile(
                                        '/assessment-questions/upload',
                                        bytes,
                                        filename,
                                        fieldName: 'file',
                                      );

                                      if (res.statusCode == 200) {
                                        final resBody = await res.stream.bytesToString();
                                        final data = jsonDecode(resBody);
                                        setState(() {
                                          block['content'] = data['fileUrl'];
                                          block['isSvg'] = isSvgFile;
                                        });
                                      }
                                    }
                                  } catch (e) {
                                    _showSnackBar('Upload error: $e');
                                  }
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF10B981),
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                ),
                                icon: const Icon(Icons.upload_file_rounded, size: 14),
                                label: Text(imgContent.isEmpty ? 'Upload Image' : 'Change', style: const TextStyle(fontSize: 11)),
                              ),
                              IconButton(
                                icon: const Icon(Icons.close_rounded, size: 16, color: Colors.redAccent),
                                onPressed: () {
                                  setState(() {
                                    blocks.removeAt(bIdx);
                                  });
                                },
                              ),
                            ],
                          ),
                        );
                      }

                      // TEXT Block
                      final blockTextCtrl = TextEditingController(text: block['content'] ?? '');
                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: SymbolInputFieldWrapper(
                                controller: blockTextCtrl,
                                onChanged: () {
                                  block['content'] = blockTextCtrl.text;
                                },
                                child: TextFormField(
                                  controller: blockTextCtrl,
                                  decoration: InputDecoration(
                                    labelText: 'Text Block #${bIdx + 1}',
                                    hintText: 'e.g., 53 is between 50 and 60...',
                                    labelStyle: TextStyle(fontSize: 11, color: context.textColor70),
                                    border: const OutlineInputBorder(),
                                    isDense: true,
                                  ),
                                  style: TextStyle(color: context.textColor, fontSize: 13),
                                  maxLines: 2,
                                  onChanged: (val) {
                                    block['content'] = val;
                                  },
                                ),
                              ),
                            ),
                            if (blocks.length > 1) ...[
                              const SizedBox(width: 4),
                              IconButton(
                                icon: const Icon(Icons.close_rounded, size: 16, color: Colors.redAccent),
                                onPressed: () {
                                  setState(() {
                                    blocks.removeAt(bIdx);
                                  });
                                },
                              ),
                            ],
                          ],
                        ),
                      );
                    }),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _renderQuestionImagePreview(String path, {required bool isSvg}) {
    if (path.isEmpty) return const SizedBox();
    final fullUrl = (path.startsWith('http://') || path.startsWith('https://'))
        ? path
        : 'https://api.jyamitimath.com${path.startsWith('/') ? path : '/$path'}';
    if (isSvg) {
      return SvgPicture.network(
        fullUrl,
        fit: BoxFit.contain,
        placeholderBuilder: (_) => const Icon(Icons.image, size: 20),
      );
    }
    return Image.network(
      fullUrl,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, size: 20),
    );
  }

  Widget _buildAnswerOptionsCard(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.glassBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.3 : 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.task_alt_rounded,
                  color: Color(0xFF10B981),
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                'Answer Key & Options',
                style: TextStyle(
                  color: context.textColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_type == 'SHORT_ANSWER')
            _buildShortAnswerInput()
          else if (_type == 'MATCHING')
            _buildMatchingPairsInput()
          else if (_type == 'GEOMETRIC')
            _buildGeometricEditor()
          else if (_type == 'MATRIX_MCQ')
            _buildMatrixMCQEditor()
          else if (_type == 'MATRIX_INPUT')
            _buildMatrixInputEditor()
          else if (_type == 'EQUATION')
            _buildEquationEditor()
          else if (_type == 'STATEMENT_DROPDOWN')
            _buildStatementDropdownEditor()
          else if (_type == 'DESCRIPTIVE')
            _buildDescriptiveAnswerInput()
          else if (_type == 'TRUE_FALSE')
            _buildTrueFalseInput()
          else
            _buildMCQOptionsInput(),
        ],
      ),
    );
  }

  Widget _buildActionButtonsRow() {
    return LayoutBuilder(
      builder: (ctx, constraints) {
        final bool isRow = constraints.maxWidth > 400;
        return isRow
            ? Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _addDittoQuestion,
                      icon: const Icon(
                        Icons.control_point_duplicate_rounded,
                        size: 18,
                        color: Colors.white,
                      ),
                      label: const Text(
                        'Add Ditto Question',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF10B981),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ),
                  if (widget.isPracticeMode) ...[
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _generateSimilarQuestions,
                        icon: const Icon(
                          Icons.auto_awesome,
                          size: 18,
                          color: Colors.white,
                        ),
                        label: const Text(
                          'Generate 3 (AI)',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF6366F1),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ElevatedButton.icon(
                    onPressed: _addDittoQuestion,
                    icon: const Icon(
                      Icons.control_point_duplicate_rounded,
                      size: 18,
                      color: Colors.white,
                    ),
                    label: const Text(
                      'Add Ditto Question (Same Structure)',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF10B981),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                  if (widget.isPracticeMode) ...[
                    const SizedBox(height: 12),
                    ElevatedButton.icon(
                      onPressed: _generateSimilarQuestions,
                      icon: const Icon(
                        Icons.auto_awesome,
                        size: 18,
                        color: Colors.white,
                      ),
                      label: const Text(
                        'Generate 3 Similar Questions (AI)',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF6366F1),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ],
                ],
              );
      },
    );
  }

  Widget _buildAIGenerationSection() {
    final isDark = context.isDark;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.glassBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.auto_awesome,
                color: const Color(0xFF6366F1),
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                'AI Similar Questions Generator',
                style: TextStyle(
                  color: context.textColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_isGeneratingAI)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 24),
              width: double.infinity,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  JyamitiLoader(color: Color(0xFF6366F1)),
                  const SizedBox(height: 16),
                  Text(
                    'AI is creating similar questions...',
                    style: TextStyle(color: context.textColor70, fontSize: 13),
                  ),
                ],
              ),
            )
          else if (_generatedQuestions.isEmpty)
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Need extra practice questions of the same type? Generate 3 similar questions automatically using AI.',
                  style: TextStyle(color: context.textColor60, fontSize: 12),
                ),
                if (_type == 'GEOMETRIC') ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.amber.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.amber.withOpacity(0.5)),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.warning_amber_rounded,
                          color: Colors.amber,
                          size: 16,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Warning: Geometric construction questions rely on manual diagram placements. Generated questions will use empty coordinate systems.',
                            style: TextStyle(
                              color: isDark
                                  ? Colors.amber[200]
                                  : Colors.amber[800],
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  onPressed: _generateSimilarQuestions,
                  icon: const Icon(
                    Icons.auto_awesome,
                    size: 16,
                    color: Colors.white,
                  ),
                  label: const Text(
                    'Generate 3 Similar Questions',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF6366F1),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ],
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'AI Generated Variations',
                      style: TextStyle(
                        color: context.textColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () {
                        setState(() {
                          _generatedQuestions = [];
                          _selectedGeneratedQuestions = [true, true, true];
                        });
                      },
                      icon: const Icon(
                        Icons.refresh,
                        size: 14,
                        color: Colors.redAccent,
                      ),
                      label: const Text(
                        'Clear / Regenerate',
                        style: TextStyle(color: Colors.redAccent, fontSize: 12),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ...List.generate(_generatedQuestions.length, (idx) {
                  final q = _generatedQuestions[idx];
                  final isSelected = _selectedGeneratedQuestions[idx];
                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    color: isDark
                        ? const Color(0xFF0F172A)
                        : const Color(0xFFF8FAFC),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                      // side: Border.all(
                      //   color: isSelected
                      //       ? const Color(0xFF6366F1).withOpacity(0.5)
                      //       : context.glassBorder,
                      //   width: isSelected ? 1.5 : 1.0,
                      // ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Checkbox(
                                activeColor: const Color(0xFF6366F1),
                                value: isSelected,
                                onChanged: (val) {
                                  setState(() {
                                    _selectedGeneratedQuestions[idx] =
                                        val ?? false;
                                  });
                                },
                              ),
                              Text(
                                'Variation #${idx + 1}',
                                style: TextStyle(
                                  color: context.textColor,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                              const Spacer(),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(
                                    0xFF6366F1,
                                  ).withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  q['type'] ?? '',
                                  style: const TextStyle(
                                    color: Color(0xFF818CF8),
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (isSelected) ...[
                            const SizedBox(height: 8),
                            if (q['descriptiveText'] != null &&
                                q['descriptiveText'].toString().isNotEmpty) ...[
                              TextFormField(
                                initialValue: q['descriptiveText'],
                                decoration: InputDecoration(
                                  labelText: 'Descriptive Context Text',
                                  labelStyle: TextStyle(
                                    fontSize: 11,
                                    color: context.textColor70,
                                  ),
                                  border: const OutlineInputBorder(),
                                  isDense: true,
                                ),
                                style: TextStyle(
                                  color: context.textColor,
                                  fontSize: 13,
                                ),
                                maxLines: 2,
                                onChanged: (val) {
                                  q['descriptiveText'] = val;
                                },
                              ),
                              const SizedBox(height: 12),
                            ],
                            TextFormField(
                              initialValue: q['text'],
                              decoration: InputDecoration(
                                labelText: 'Question Text',
                                labelStyle: TextStyle(
                                  fontSize: 11,
                                  color: context.textColor70,
                                ),
                                border: const OutlineInputBorder(),
                                isDense: true,
                              ),
                              style: TextStyle(
                                color: context.textColor,
                                fontSize: 13,
                              ),
                              maxLines: 3,
                              onChanged: (val) {
                                q['text'] = val;
                              },
                            ),
                            const SizedBox(height: 12),
                            if ((q['type'] == 'MCQ_SINGLE' ||
                                    q['type'] == 'MCQ_MULTI') &&
                                q['options'] != null &&
                                q['options'] is List) ...[
                              Text(
                                'Options (Check/Uncheck to mark correct):',
                                style: TextStyle(
                                  color: context.textColor70,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 6),
                              ...List.generate((q['options'] as List).length, (
                                optIdx,
                              ) {
                                final opt = q['options'][optIdx];
                                final List<String> correct = List<String>.from(
                                  q['correctAnswers'] ?? [],
                                );
                                final bool isCorrect = correct.contains(
                                  optIdx.toString(),
                                );

                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 8.0),
                                  child: Row(
                                    children: [
                                      Checkbox(
                                        activeColor: Colors.green,
                                        value: isCorrect,
                                        onChanged: (val) {
                                          setState(() {
                                            final updatedCorrect =
                                                List<String>.from(
                                                  q['correctAnswers'] ?? [],
                                                );
                                            if (val == true) {
                                              if (q['type'] == 'MCQ_SINGLE') {
                                                updatedCorrect.clear();
                                              }
                                              if (!updatedCorrect.contains(
                                                optIdx.toString(),
                                              )) {
                                                updatedCorrect.add(
                                                  optIdx.toString(),
                                                );
                                              }
                                            } else {
                                              updatedCorrect.remove(
                                                optIdx.toString(),
                                              );
                                            }
                                            q['correctAnswers'] =
                                                updatedCorrect;
                                          });
                                        },
                                      ),
                                      Expanded(
                                        child: TextFormField(
                                          initialValue: opt['text'] ?? '',
                                          decoration: InputDecoration(
                                            labelText: 'Option ${optIdx + 1}',
                                            labelStyle: const TextStyle(
                                              fontSize: 11,
                                            ),
                                            border: const OutlineInputBorder(),
                                            isDense: true,
                                          ),
                                          style: TextStyle(
                                            color: context.textColor,
                                            fontSize: 13,
                                          ),
                                          onChanged: (val) {
                                            opt['text'] = val;
                                          },
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              }),
                            ] else if (q['type'] == 'SHORT_ANSWER') ...[
                              TextFormField(
                                initialValue:
                                    (q['correctAnswers'] is List &&
                                        (q['correctAnswers'] as List)
                                            .isNotEmpty)
                                    ? q['correctAnswers'][0]
                                    : '',
                                decoration: InputDecoration(
                                  labelText: 'Correct Answer',
                                  labelStyle: const TextStyle(fontSize: 11),
                                  border: const OutlineInputBorder(),
                                  isDense: true,
                                ),
                                style: TextStyle(
                                  color: context.textColor,
                                  fontSize: 13,
                                ),
                                onChanged: (val) {
                                  q['correctAnswers'] = [val.trim()];
                                },
                              ),
                            ] else ...[
                              Text(
                                'Answers: ${q['correctAnswers']}',
                                style: TextStyle(
                                  color: context.textColor60,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                            const SizedBox(height: 12),
                            TextFormField(
                              initialValue: q['explanation'] ?? '',
                              decoration: InputDecoration(
                                labelText: 'AI Solution Explanation',
                                hintText: 'AI generated solution explanation for Variation #${idx + 1}',
                                labelStyle: TextStyle(
                                  fontSize: 11,
                                  color: context.textColor70,
                                ),
                                border: const OutlineInputBorder(),
                                isDense: true,
                              ),
                              style: TextStyle(color: context.textColor, fontSize: 13),
                              maxLines: 3,
                              onChanged: (val) {
                                q['explanation'] = val;
                              },
                            ),
                          ],
                        ],
                      ),
                    ),
                  );
                }),
              ],
            ),
        ],
      ),
    );
  }

  // Question file upload & preview widget
  Widget _buildQuestionImageUploadSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: context.glassBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Question Image / SVG (Optional)',
            style: TextStyle(
              color: context.textColor70,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
          SizedBox(height: 12),
          if (_questionImage.isNotEmpty) ...[
            Center(
              child: Stack(
                alignment: Alignment.topRight,
                children: [
                  Container(
                    margin: EdgeInsets.only(top: 8, right: 8),
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: context.glassBg,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: context.textColor54.withOpacity(0.4),
                      ),
                    ),
                    height: 120,
                    width: 200,
                    child: _renderImageOrSvg(_questionImage, _isQuestionSvg),
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.cancel,
                      color: Colors.redAccent,
                      size: 24,
                    ),
                    onPressed: () {
                      setState(() {
                        _questionImage = '';
                        _isQuestionSvg = false;
                      });
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _isUploadingQuestionImage
                      ? null
                      : _pickAndUploadQuestionFile,
                  icon: Icon(Icons.file_upload, color: context.textColor),
                  label: Text(
                    _isUploadingQuestionImage
                        ? 'Uploading...'
                        : 'Choose SVG or Image File',
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF6366F1),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
              if (_questionImage.isNotEmpty && _isQuestionSvg) ...[
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      final result =
                          await Navigator.push<List<Map<String, dynamic>>>(
                            context,
                            MaterialPageRoute(
                              builder: (context) => SvgLabelEditorDialog(
                                imagePath: _questionImage,
                                isSvg: _isQuestionSvg,
                                initialLabels: _svgLabels,
                              ),
                            ),
                          );
                      if (result != null) {
                        setState(() {
                          _svgLabels = result;
                        });
                      }
                    },
                    icon: Icon(
                      Icons.label_important_outline,
                      color: context.textColor,
                    ),
                    label: Text('Edit Labels (${_svgLabels.length})'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF10B981),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  // Short answer text fields
  Widget _buildShortAnswerInput() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Correct Answer for Student to Match:',
          style: TextStyle(
            color: context.textColor70,
            fontWeight: FontWeight.bold,
            fontSize: 15,
          ),
        ),
        const SizedBox(height: 12),
        SymbolInputFieldWrapper(
          controller: _shortAnswerCtrl,
          child: TextFormField(
            controller: _shortAnswerCtrl,
            style: TextStyle(color: context.textColor),
            decoration: InputDecoration(
              labelText: 'Correct Answer text',
              labelStyle: TextStyle(color: context.textColor70),
              filled: true,
              fillColor: context.isDark ? const Color(0xFF1E293B) : Colors.white,
              border: OutlineInputBorder(),
            ),
            validator: (v) => (v == null || v.trim().isEmpty)
                ? 'Please enter correct answer match'
                : null,
          ),
        ),
        const SizedBox(height: 24),
        Text(
          'Optional Prefix & Suffix:',
          style: TextStyle(
            color: context.textColor70,
            fontWeight: FontWeight.bold,
            fontSize: 15,
          ),
        ),
        const Padding(
          padding: EdgeInsets.only(top: 4, bottom: 12),
          child: Text(
            'Add optional text that will be shown immediately before or after the input field to guide the student (e.g., prefix "Area = " or suffix " cm²").',
            style: TextStyle(color: Colors.white38, fontSize: 12),
          ),
        ),
        Row(
          children: [
            Expanded(
              child: SymbolInputFieldWrapper(
                controller: _prefixCtrl,
                child: TextFormField(
                  controller: _prefixCtrl,
                  style: TextStyle(color: context.textColor),
                  decoration: InputDecoration(
                    labelText: 'Prefix (e.g. Area =)',
                    labelStyle: TextStyle(color: context.textColor70),
                    filled: true,
                    fillColor: context.isDark
                        ? const Color(0xFF1E293B)
                        : Colors.white,
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: SymbolInputFieldWrapper(
                controller: _suffixCtrl,
                child: TextFormField(
                  controller: _suffixCtrl,
                  style: TextStyle(color: context.textColor),
                  decoration: InputDecoration(
                    labelText: 'Suffix (e.g. cm²)',
                    labelStyle: TextStyle(color: context.textColor70),
                    filled: true,
                    fillColor: context.isDark
                        ? const Color(0xFF1E293B)
                        : Colors.white,
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        Text(
          'Optional Hint:',
          style: TextStyle(
            color: context.textColor70,
            fontWeight: FontWeight.bold,
            fontSize: 15,
          ),
        ),
        const Padding(
          padding: EdgeInsets.only(top: 4, bottom: 12),
          child: Text(
            'Provide an optional hint. The student will see this hint in a glowing popup when they tap/focus on the answer input field. The hint will disappear once they start typing.',
            style: TextStyle(color: Colors.white38, fontSize: 12),
          ),
        ),
        SymbolInputFieldWrapper(
          controller: _hintCtrl,
          child: TextFormField(
            controller: _hintCtrl,
            style: TextStyle(color: context.textColor),
            decoration: InputDecoration(
              labelText: 'Hint (e.g. Think of a prime number)',
              labelStyle: TextStyle(color: context.textColor70),
              filled: true,
              fillColor: context.isDark ? const Color(0xFF1E293B) : Colors.white,
              border: OutlineInputBorder(),
            ),
          ),
        ),
      ],
    );
  }

  // Admin preset model answer for DESCRIPTIVE (handwritten) questions,
  // used by DeepSeek AI to evaluate the student's typed/handwritten answer.
  Widget _buildDescriptiveAnswerInput() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Admin Preset Model Answer:',
          style: TextStyle(
            color: context.textColor70,
            fontWeight: FontWeight.bold,
            fontSize: 15,
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 12),
          child: Text(
            'Write the ideal/model answer here. DeepSeek AI will gently and politely compare the student\'s typed or handwritten (uploaded image) answer against this for semantic meaning, not exact wording.',
            style: TextStyle(color: context.textColor60, fontSize: 12),
          ),
        ),
        SymbolInputFieldWrapper(
          controller: _shortAnswerCtrl,
          child: TextFormField(
            controller: _shortAnswerCtrl,
            maxLines: 5,
            style: TextStyle(color: context.textColor),
            decoration: InputDecoration(
              labelText: 'Model Answer',
              labelStyle: TextStyle(color: context.textColor70),
              filled: true,
              fillColor: context.isDark ? const Color(0xFF1E293B) : Colors.white,
              border: OutlineInputBorder(),
              alignLabelWithHint: true,
            ),
            validator: (v) => (v == null || v.trim().isEmpty)
                ? 'Please provide the Admin Preset Model Answer'
                : null,
          ),
        ),
      ],
    );
  }

  // TRUE_FALSE: fixed True/False options, just pick which one is correct.
  Widget _buildTrueFalseInput() {
    Widget buildChoiceCard(String label, bool valueForTrue) {
      final bool isSelected = _trueFalseAnswer == valueForTrue;
      return Expanded(
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => setState(() => _trueFalseAnswer = valueForTrue),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 18),
            decoration: BoxDecoration(
              color: isSelected
                  ? const Color(0xFF10B981).withOpacity(0.15)
                  : (context.isDark ? const Color(0xFF1E293B) : Colors.white),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isSelected
                    ? const Color(0xFF10B981)
                    : context.glassBorder,
                width: isSelected ? 2 : 1,
              ),
            ),
            child: Column(
              children: [
                Icon(
                  isSelected
                      ? Icons.check_circle_rounded
                      : Icons.radio_button_unchecked_rounded,
                  color: isSelected ? const Color(0xFF10B981) : context.textColor54,
                ),
                const SizedBox(height: 8),
                Text(
                  label,
                  style: TextStyle(
                    color: isSelected ? const Color(0xFF10B981) : context.textColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Correct Answer:',
          style: TextStyle(
            color: context.textColor70,
            fontWeight: FontWeight.bold,
            fontSize: 15,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            buildChoiceCard('True', true),
            const SizedBox(width: 12),
            buildChoiceCard('False', false),
          ],
        ),
      ],
    );
  }

  // MCQ options fields with individual image uploads
  Widget _buildMCQOptionsInput() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              _type == 'ORDERING'
                  ? 'Sequence Items (Write in CORRECT order):'
                  : 'Answers Options & Correct Answers:',
              style: TextStyle(
                color: context.textColor70,
                fontWeight: FontWeight.bold,
                fontSize: 15,
              ),
            ),
            TextButton.icon(
              icon: const Icon(Icons.add, size: 16, color: Color(0xFF818CF8)),
              label: const Text(
                'Add Option',
                style: TextStyle(color: Color(0xFF818CF8)),
              ),
              onPressed: _addEmptyOption,
            ),
          ],
        ),
        if (_type == 'ORDERING')
          const Padding(
            padding: EdgeInsets.only(top: 4, bottom: 12),
            child: Text(
              'Please add items in their correct, final sorted order (e.g. from smallest to largest). The app will automatically shuffle them for students.',
              style: TextStyle(
                color: Colors.white38,
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ),
        const SizedBox(height: 8),
        ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _options.length,
          itemBuilder: (ctx, idx) {
            final opt = _options[idx];
            final optImg = opt['imageUrl'] ?? '';
            final optSvg = opt['isSvg'] ?? false;

            return Card(
              color: context.isDark ? const Color(0xFF1E293B) : Colors.white,
              margin: const EdgeInsets.only(bottom: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        // Rank indicator for Ordering, Checkbox/Radio for MCQ
                        if (_type == 'ORDERING')
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: CircleAvatar(
                              radius: 12,
                              backgroundColor: const Color(
                                0xFF6366F1,
                              ).withOpacity(0.15),
                              child: Text(
                                '${idx + 1}',
                                style: const TextStyle(
                                  color: Color(0xFF818CF8),
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          )
                        else
                          _type == 'MCQ_SINGLE'
                              ? Radio<int>(
                                  value: idx,
                                  groupValue: _correctAnswerSelection
                                      .indexWhere((val) => val),
                                  activeColor: const Color(0xFF6366F1),
                                  onChanged: (val) {
                                    setState(() {
                                      for (
                                        int i = 0;
                                        i < _correctAnswerSelection.length;
                                        i++
                                      ) {
                                        _correctAnswerSelection[i] = (i == val);
                                      }
                                    });
                                  },
                                )
                              : Checkbox(
                                  value: _correctAnswerSelection[idx],
                                  activeColor: const Color(0xFF6366F1),
                                  onChanged: (val) {
                                    setState(() {
                                      _correctAnswerSelection[idx] =
                                          val ?? false;
                                    });
                                  },
                                ),

                        // Option text controller
                        Expanded(
                          child: TextFormField(
                            initialValue: opt['text'],
                            style: TextStyle(color: context.textColor),
                            decoration: InputDecoration(
                              hintText: 'Option ${idx + 1} text',
                              hintStyle: TextStyle(
                                color: context.textColor54.withOpacity(0.5),
                              ),
                              isDense: true,
                              border: const UnderlineInputBorder(),
                            ),
                            onChanged: (val) {
                              _options[idx]['text'] = val;
                            },
                          ),
                        ),

                        // Remove option button
                        if (_options.length > 1)
                          IconButton(
                            icon: const Icon(
                              Icons.delete,
                              color: Colors.redAccent,
                              size: 20,
                            ),
                            onPressed: () => _removeOption(idx),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Option image upload details
                    Row(
                      children: [
                        const SizedBox(width: 48), // align with inputs
                        if (optImg.isNotEmpty) ...[
                          Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: context.glassBorder,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            height: 40,
                            width: 60,
                            child: _renderImageOrSvg(optImg, optSvg),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            icon: const Icon(
                              Icons.cancel,
                              color: Colors.redAccent,
                              size: 18,
                            ),
                            onPressed: () {
                              setState(() {
                                _options[idx]['imageUrl'] = '';
                                _options[idx]['isSvg'] = false;
                              });
                            },
                          ),
                          const SizedBox(width: 8),
                        ],
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => _pickAndUploadOptionFile(idx),
                            icon: Icon(
                              Icons.image,
                              size: 14,
                              color: context.textColor70,
                            ),
                            label: Text(
                              optImg.isNotEmpty
                                  ? 'Change SVG/Image'
                                  : 'Add SVG/Image option',
                              style: const TextStyle(fontSize: 12),
                            ),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.white70,
                              side: BorderSide(color: context.glassBorder),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  // Option/Question Image SVG renderer helper
  Widget _renderImageOrSvg(String path, bool isSvg) {
    final fullUrl = _getImageUrl(path);

    if (isSvg) {
      if (path.contains('<svg') || path.contains('<path')) {
        return SvgPicture.string(path, fit: BoxFit.contain);
      }
      return SvgPicture.network(
        fullUrl,
        fit: BoxFit.contain,
        placeholderBuilder: (context) => const Center(
          child: SizedBox(
            width: 15,
            height: 15,
            child: JyamitiLoader(strokeWidth: 1.5),
          ),
        ),
        errorBuilder: (context, error, stackTrace) => Icon(
          Icons.broken_image,
          size: 16,
          color: context.textColor54.withOpacity(0.5),
        ),
      );
    } else {
      return Image.network(
        fullUrl,
        fit: BoxFit.contain,
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return const Center(
            child: SizedBox(
              width: 15,
              height: 15,
              child: JyamitiLoader(strokeWidth: 1.5),
            ),
          );
        },
        errorBuilder: (context, error, stackTrace) => Icon(
          Icons.broken_image,
          size: 16,
          color: context.textColor54.withOpacity(0.5),
        ),
      );
    }
  }

  void _addEmptyRow() {
    setState(() {
      _options.add({'text': '', 'imageUrl': '', 'isSvg': false});
      _matrixCorrectAnswers.add("0");
    });
  }

  void _removeRow(int idx) {
    setState(() {
      if (_options.length > 1) {
        _options.removeAt(idx);
        if (idx < _matrixCorrectAnswers.length) {
          _matrixCorrectAnswers.removeAt(idx);
        }
      }
    });
  }

  void _addEmptyColumn() {
    setState(() {
      _rightOptions.add({'text': '', 'imageUrl': '', 'isSvg': false});
    });
  }

  void _removeColumn(int idx) {
    setState(() {
      if (_rightOptions.length > 1) {
        _rightOptions.removeAt(idx);
        for (int i = 0; i < _matrixCorrectAnswers.length; i++) {
          final int currentSel = int.tryParse(_matrixCorrectAnswers[i]) ?? 0;
          if (currentSel >= _rightOptions.length) {
            _matrixCorrectAnswers[i] = (_rightOptions.length - 1).toString();
          }
        }
      }
    });
  }

  void _addEmptyRowForInput() {
    setState(() {
      _options.add({'text': '', 'imageUrl': '', 'isSvg': false});
      _matrixInputCells.add(
        List.generate(
          _rightOptions.length,
          (c) => {'value': '', 'isInput': false},
        ),
      );
    });
  }

  void _removeRowForInput(int idx) {
    setState(() {
      if (_options.length > 1) {
        _options.removeAt(idx);
        _matrixInputCells.removeAt(idx);
      }
    });
  }

  void _addEmptyColumnForInput() {
    setState(() {
      _rightOptions.add({'text': '', 'imageUrl': '', 'isSvg': false});
      for (int r = 0; r < _matrixInputCells.length; r++) {
        _matrixInputCells[r].add({'value': '', 'isInput': false});
      }
    });
  }

  void _removeColumnForInput(int idx) {
    setState(() {
      if (_rightOptions.length > 1) {
        _rightOptions.removeAt(idx);
        for (int r = 0; r < _matrixInputCells.length; r++) {
          if (idx < _matrixInputCells[r].length) {
            _matrixInputCells[r].removeAt(idx);
          }
        }
      }
    });
  }

  Widget _buildEquationEditor() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Equation Steps:',
              style: TextStyle(
                color: context.textColor70,
                fontWeight: FontWeight.bold,
                fontSize: 15,
              ),
            ),
            TextButton.icon(
              icon: const Icon(Icons.add, size: 16, color: Color(0xFF818CF8)),
              label: const Text(
                'Add Step',
                style: TextStyle(color: Color(0xFF818CF8)),
              ),
              onPressed: () {
                setState(() {
                  _options.add({'text': '', 'imageUrl': '', 'isSvg': false});
                  _equationStepControllers.add(TextEditingController());
                });
              },
            ),
          ],
        ),
        Card(
          color: context.isDark ? const Color(0xFF1E293B) : Colors.white,
          child: Padding(
            padding: EdgeInsets.all(12.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      color: Color(0xFF6366F1),
                      size: 16,
                    ),
                    SizedBox(width: 8),
                    Text(
                      'How to create inputs:',
                      style: TextStyle(
                        color: context.textColor70,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 6),
                Text(
                  'Write your step text freely. To add an input box for students to fill in, use the tag: [INPUT:answer]\n'
                  'Example:\n'
                  'Line 1: 7 x 7 = (5 x 7) + (2 x 7)\n'
                  'Line 2: = [INPUT:35] + 14\n'
                  'Line 3: = [INPUT:49]',
                  style: TextStyle(
                    color: Colors.white38,
                    fontSize: 11,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _options.length,
          itemBuilder: (ctx, idx) {
            while (_equationStepControllers.length <= idx) {
              _equationStepControllers.add(
                TextEditingController(text: _options[idx]['text'] ?? ''),
              );
            }
            final ctrl = _equationStepControllers[idx];

            return Card(
              color: context.isDark ? const Color(0xFF1E293B) : Colors.white,
              margin: const EdgeInsets.only(bottom: 12),
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Step ${idx + 1}',
                          style: TextStyle(
                            color: context.textColor70,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                        if (_options.length > 1)
                          IconButton(
                            icon: const Icon(
                              Icons.delete,
                              color: Colors.redAccent,
                              size: 18,
                            ),
                            onPressed: () {
                              setState(() {
                                _options.removeAt(idx);
                                _equationStepControllers[idx].dispose();
                                _equationStepControllers.removeAt(idx);
                              });
                            },
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    SymbolInputFieldWrapper(
                      controller: ctrl,
                      onChanged: () => _options[idx]['text'] = ctrl.text,
                      child: TextFormField(
                        controller: ctrl,
                        style: TextStyle(color: context.textColor, fontSize: 14),
                        decoration: InputDecoration(
                          hintText: 'e.g. = [INPUT:35] + 14',
                          hintStyle: TextStyle(
                            color: context.textColor54.withOpacity(0.4),
                          ),
                          filled: true,
                          fillColor: context.isDark
                              ? const Color(0xFF0F172A)
                              : Colors.white,
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (val) {
                          _options[idx]['text'] = val;
                        },
                      ),
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        icon: const Icon(
                          Icons.add_box,
                          size: 16,
                          color: Color(0xFF10B981),
                        ),
                        label: const Text(
                          'Insert Input Box',
                          style: TextStyle(
                            color: Color(0xFF10B981),
                            fontSize: 12,
                          ),
                        ),
                        onPressed: () {
                          setState(() {
                            final int cursorPosition =
                                ctrl.selection.baseOffset;
                            const String token = '[INPUT:value]';
                            if (cursorPosition >= 0) {
                              final String currentText = ctrl.text;
                              final String newText =
                                  currentText.substring(0, cursorPosition) +
                                  token +
                                  currentText.substring(cursorPosition);
                              ctrl.text = newText;
                              ctrl.selection = TextSelection.fromPosition(
                                TextPosition(
                                  offset: cursorPosition + token.length,
                                ),
                              );
                            } else {
                              ctrl.text += token;
                            }
                            _options[idx]['text'] = ctrl.text;
                          });
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildStatementDropdownEditor() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Statements:',
              style: TextStyle(
                color: context.textColor70,
                fontWeight: FontWeight.bold,
                fontSize: 15,
              ),
            ),
            TextButton.icon(
              icon: const Icon(Icons.add, size: 16, color: Color(0xFF818CF8)),
              label: const Text(
                'Add Statement',
                style: TextStyle(color: Color(0xFF818CF8)),
              ),
              onPressed: () {
                setState(() {
                  _options.add({'text': '', 'imageUrl': '', 'isSvg': false});
                  _statementStepControllers.add(TextEditingController());
                });
              },
            ),
          ],
        ),
        Card(
          color: context.isDark ? const Color(0xFF1E293B) : Colors.white,
          child: Padding(
            padding: EdgeInsets.all(12.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      color: Color(0xFF6366F1),
                      size: 16,
                    ),
                    SizedBox(width: 8),
                    Text(
                      'How to create dropdown choices:',
                      style: TextStyle(
                        color: context.textColor70,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 6),
                Text(
                  'Write your statement text freely. To add an inline dropdown selection, use the tag:\n'
                  '[SELECT:choice1,choice2:correctChoice]\n'
                  'Example:\n'
                  'On the number line, -4.4 is [SELECT:above,below:below] 1.2',
                  style: TextStyle(
                    color: Colors.white38,
                    fontSize: 11,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _options.length,
          itemBuilder: (ctx, idx) {
            while (_statementStepControllers.length <= idx) {
              _statementStepControllers.add(
                TextEditingController(text: _options[idx]['text'] ?? ''),
              );
            }
            final ctrl = _statementStepControllers[idx];

            return Card(
              color: context.isDark ? const Color(0xFF1E293B) : Colors.white,
              margin: const EdgeInsets.only(bottom: 12),
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Statement ${idx + 1}',
                          style: TextStyle(
                            color: context.textColor70,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                        if (_options.length > 1)
                          IconButton(
                            icon: const Icon(
                              Icons.delete,
                              color: Colors.redAccent,
                              size: 18,
                            ),
                            onPressed: () {
                              setState(() {
                                _options.removeAt(idx);
                                _statementStepControllers[idx].dispose();
                                _statementStepControllers.removeAt(idx);
                              });
                            },
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    SymbolInputFieldWrapper(
                      controller: ctrl,
                      onChanged: () => _options[idx]['text'] = ctrl.text,
                      child: TextFormField(
                        controller: ctrl,
                        style: TextStyle(color: context.textColor, fontSize: 14),
                        decoration: InputDecoration(
                          hintText: 'e.g. -4.4 is [SELECT:above,below:below] 1.2',
                          hintStyle: TextStyle(
                            color: context.textColor54.withOpacity(0.4),
                          ),
                          filled: true,
                          fillColor: context.isDark
                              ? const Color(0xFF0F172A)
                              : Colors.white,
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (val) {
                          _options[idx]['text'] = val;
                        },
                      ),
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        icon: const Icon(
                          Icons.add_box,
                          size: 16,
                          color: Color(0xFF10B981),
                        ),
                        label: const Text(
                          'Insert Dropdown Tag',
                          style: TextStyle(
                            color: Color(0xFF10B981),
                            fontSize: 12,
                          ),
                        ),
                        onPressed: () {
                          setState(() {
                            final int cursorPosition =
                                ctrl.selection.baseOffset;
                            const String token =
                                '[SELECT:choice1,choice2:choice2]';
                            if (cursorPosition >= 0) {
                              final String currentText = ctrl.text;
                              final String newText =
                                  currentText.substring(0, cursorPosition) +
                                  token +
                                  currentText.substring(cursorPosition);
                              ctrl.text = newText;
                              ctrl.selection = TextSelection.fromPosition(
                                TextPosition(
                                  offset: cursorPosition + token.length,
                                ),
                              );
                            } else {
                              ctrl.text += token;
                            }
                            _options[idx]['text'] = ctrl.text;
                          });
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildMatrixInputEditor() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 1. Column configuration
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Table Columns (Headers):',
              style: TextStyle(
                color: context.textColor70,
                fontWeight: FontWeight.bold,
                fontSize: 15,
              ),
            ),
            TextButton.icon(
              icon: const Icon(Icons.add, size: 16, color: Color(0xFF818CF8)),
              label: const Text(
                'Add Column',
                style: TextStyle(color: Color(0xFF818CF8)),
              ),
              onPressed: _addEmptyColumnForInput,
            ),
          ],
        ),
        const SizedBox(height: 8),
        ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _rightOptions.length,
          itemBuilder: (ctx, idx) {
            final col = _rightOptions[idx];
            return Card(
              color: context.isDark ? const Color(0xFF1E293B) : Colors.white,
              margin: const EdgeInsets.only(bottom: 8),
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 12,
                      backgroundColor: const Color(
                        0xFF10B981,
                      ).withOpacity(0.15),
                      child: Text(
                        '${String.fromCharCode(65 + idx)}',
                        style: const TextStyle(
                          color: Color(0xFF34D399),
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        initialValue: col['text'],
                        style: TextStyle(
                          color: context.textColor,
                          fontSize: 14,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Column header (e.g. Hours of sleep)',
                          hintStyle: TextStyle(
                            color: context.textColor54.withOpacity(0.4),
                          ),
                          isDense: true,
                        ),
                        onChanged: (val) {
                          _rightOptions[idx]['text'] = val;
                        },
                      ),
                    ),
                    if (_rightOptions.length > 1)
                      IconButton(
                        icon: const Icon(
                          Icons.delete,
                          color: Colors.redAccent,
                          size: 18,
                        ),
                        onPressed: () => _removeColumnForInput(idx),
                      ),
                  ],
                ),
              ),
            );
          },
        ),

        const SizedBox(height: 24),

        // 2. Rows configuration
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Table Rows & Cells:',
              style: TextStyle(
                color: context.textColor70,
                fontWeight: FontWeight.bold,
                fontSize: 15,
              ),
            ),
            TextButton.icon(
              icon: const Icon(Icons.add, size: 16, color: Color(0xFF818CF8)),
              label: const Text(
                'Add Row',
                style: TextStyle(color: Color(0xFF818CF8)),
              ),
              onPressed: _addEmptyRowForInput,
            ),
          ],
        ),
        const Padding(
          padding: EdgeInsets.only(top: 4, bottom: 12),
          child: Text(
            'Specify values for each cell. Check the "Input?" checkbox if students should fill in that cell during the test.',
            style: TextStyle(color: Colors.white38, fontSize: 12, height: 1.4),
          ),
        ),

        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Table(
            defaultColumnWidth: const FixedColumnWidth(140.0),
            border: TableBorder.all(color: context.glassBorder),
            children: [
              // Header row
              TableRow(
                decoration: BoxDecoration(
                  color: context.isDark
                      ? const Color(0xFF0F172A)
                      : Colors.white,
                ),
                children: [
                  TableCell(
                    child: Padding(
                      padding: EdgeInsets.all(8.0),
                      child: Center(
                        child: Text(
                          'Row Index',
                          style: TextStyle(
                            color: context.textColor70,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ),
                  ),
                  ...List.generate(_rightOptions.length, (colIdx) {
                    final colText = _rightOptions[colIdx]['text'] ?? '';
                    return TableCell(
                      child: Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Center(
                          child: Text(
                            colText.isNotEmpty ? colText : 'Col ${colIdx + 1}',
                            style: TextStyle(
                              color: context.textColor70,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    );
                  }),
                  // Action space
                  TableCell(
                    child: Padding(
                      padding: EdgeInsets.all(8.0),
                      child: Center(
                        child: Text(
                          'Actions',
                          style: TextStyle(
                            color: context.textColor70,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),

              // Data rows
              ...List.generate(_options.length, (rowIdx) {
                return TableRow(
                  children: [
                    TableCell(
                      verticalAlignment: TableCellVerticalAlignment.middle,
                      child: Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Center(
                          child: Text(
                            'Row ${rowIdx + 1}',
                            style: TextStyle(
                              color: context.textColor60,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ),
                    ),
                    ...List.generate(_rightOptions.length, (colIdx) {
                      while (_matrixInputCells.length <= rowIdx) {
                        _matrixInputCells.add(
                          List.generate(
                            _rightOptions.length,
                            (c) => {'value': '', 'isInput': false},
                          ),
                        );
                      }
                      while (_matrixInputCells[rowIdx].length <= colIdx) {
                        _matrixInputCells[rowIdx].add({
                          'value': '',
                          'isInput': false,
                        });
                      }

                      final cell = _matrixInputCells[rowIdx][colIdx];
                      final bool isInput = cell['isInput'] == true;

                      return TableCell(
                        child: Padding(
                          padding: const EdgeInsets.all(6.0),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              TextFormField(
                                initialValue: cell['value'],
                                style: TextStyle(
                                  color: context.textColor,
                                  fontSize: 13,
                                ),
                                decoration: InputDecoration(
                                  hintText: isInput
                                      ? 'Correct value'
                                      : 'Label value',
                                  hintStyle: TextStyle(
                                    color: context.textColor54.withOpacity(0.4),
                                    fontSize: 11,
                                  ),
                                  isDense: true,
                                  contentPadding: const EdgeInsets.all(8),
                                ),
                                onChanged: (val) {
                                  _matrixInputCells[rowIdx][colIdx]['value'] =
                                      val;
                                },
                              ),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Text(
                                    'Input?',
                                    style: TextStyle(
                                      color: Colors.white38,
                                      fontSize: 10,
                                    ),
                                  ),
                                  Checkbox(
                                    value: isInput,
                                    activeColor: const Color(0xFF6366F1),
                                    onChanged: (val) {
                                      setState(() {
                                        _matrixInputCells[rowIdx][colIdx]['isInput'] =
                                            val == true;
                                      });
                                    },
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                    // Actions column
                    TableCell(
                      verticalAlignment: TableCellVerticalAlignment.middle,
                      child: Center(
                        child: IconButton(
                          icon: const Icon(
                            Icons.delete,
                            color: Colors.redAccent,
                            size: 18,
                          ),
                          onPressed: () => _removeRowForInput(rowIdx),
                        ),
                      ),
                    ),
                  ],
                );
              }),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMatrixMCQEditor() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 1. Rows Config
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Grid Rows (Matrix Items):',
              style: TextStyle(
                color: context.textColor70,
                fontWeight: FontWeight.bold,
                fontSize: 15,
              ),
            ),
            TextButton.icon(
              icon: const Icon(Icons.add, size: 16, color: Color(0xFF818CF8)),
              label: const Text(
                'Add Row',
                style: TextStyle(color: Color(0xFF818CF8)),
              ),
              onPressed: _addEmptyRow,
            ),
          ],
        ),
        const SizedBox(height: 8),
        ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _options.length,
          itemBuilder: (ctx, idx) {
            final row = _options[idx];
            return Card(
              color: context.isDark ? const Color(0xFF1E293B) : Colors.white,
              margin: const EdgeInsets.only(bottom: 8),
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 12,
                      backgroundColor: const Color(
                        0xFF6366F1,
                      ).withOpacity(0.15),
                      child: Text(
                        '${idx + 1}',
                        style: const TextStyle(
                          color: Color(0xFF818CF8),
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        initialValue: row['text'],
                        style: TextStyle(
                          color: context.textColor,
                          fontSize: 14,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Row label (e.g. 5)',
                          hintStyle: TextStyle(
                            color: context.textColor54.withOpacity(0.4),
                          ),
                          isDense: true,
                        ),
                        onChanged: (val) {
                          _options[idx]['text'] = val;
                        },
                      ),
                    ),
                    if (_options.length > 1)
                      IconButton(
                        icon: const Icon(
                          Icons.delete,
                          color: Colors.redAccent,
                          size: 18,
                        ),
                        onPressed: () => _removeRow(idx),
                      ),
                  ],
                ),
              ),
            );
          },
        ),

        const SizedBox(height: 24),

        // 2. Columns Config
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Grid Columns (Matrix Headers):',
              style: TextStyle(
                color: context.textColor70,
                fontWeight: FontWeight.bold,
                fontSize: 15,
              ),
            ),
            TextButton.icon(
              icon: const Icon(Icons.add, size: 16, color: Color(0xFF818CF8)),
              label: const Text(
                'Add Column',
                style: TextStyle(color: Color(0xFF818CF8)),
              ),
              onPressed: _addEmptyColumn,
            ),
          ],
        ),
        const SizedBox(height: 8),
        ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _rightOptions.length,
          itemBuilder: (ctx, idx) {
            final col = _rightOptions[idx];
            return Card(
              color: context.isDark ? const Color(0xFF1E293B) : Colors.white,
              margin: const EdgeInsets.only(bottom: 8),
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 12,
                      backgroundColor: const Color(
                        0xFF10B981,
                      ).withOpacity(0.15),
                      child: Text(
                        '${String.fromCharCode(65 + idx)}',
                        style: const TextStyle(
                          color: Color(0xFF34D399),
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        initialValue: col['text'],
                        style: TextStyle(
                          color: context.textColor,
                          fontSize: 14,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Column label (e.g. Prime)',
                          hintStyle: TextStyle(
                            color: context.textColor54.withOpacity(0.4),
                          ),
                          isDense: true,
                        ),
                        onChanged: (val) {
                          _rightOptions[idx]['text'] = val;
                        },
                      ),
                    ),
                    if (_rightOptions.length > 1)
                      IconButton(
                        icon: const Icon(
                          Icons.delete,
                          color: Colors.redAccent,
                          size: 18,
                        ),
                        onPressed: () => _removeColumn(idx),
                      ),
                  ],
                ),
              ),
            );
          },
        ),

        const SizedBox(height: 24),

        // 3. Grid Selection Preview
        Text(
          'Select Matrix Correct Answers:',
          style: TextStyle(
            color: context.textColor70,
            fontWeight: FontWeight.bold,
            fontSize: 15,
          ),
        ),
        const Padding(
          padding: EdgeInsets.only(top: 4, bottom: 12),
          child: Text(
            'Select the correct radio button connection for each row.',
            style: TextStyle(color: Colors.white38, fontSize: 12),
          ),
        ),

        // Render preview table
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Table(
            defaultColumnWidth: const FixedColumnWidth(120.0),
            border: TableBorder.all(color: context.glassBorder),
            children: [
              // Header Row
              TableRow(
                decoration: BoxDecoration(
                  color: context.isDark
                      ? const Color(0xFF0F172A)
                      : Colors.white,
                ),
                children: [
                  TableCell(
                    child: Padding(
                      padding: EdgeInsets.all(8.0),
                      child: Center(
                        child: Text(
                          'Row / Col',
                          style: TextStyle(
                            color: context.textColor70,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ),
                  ),
                  ...List.generate(_rightOptions.length, (colIdx) {
                    final colText = _rightOptions[colIdx]['text'] ?? '';
                    return TableCell(
                      child: Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Center(
                          child: Text(
                            colText.isNotEmpty ? colText : 'Col ${colIdx + 1}',
                            style: TextStyle(
                              color: context.textColor70,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    );
                  }),
                ],
              ),

              // Data Rows
              ...List.generate(_options.length, (rowIdx) {
                final rowText = _options[rowIdx]['text'] ?? '';

                // Align selection list safety guard
                if (rowIdx >= _matrixCorrectAnswers.length) {
                  _matrixCorrectAnswers.add("0");
                }
                final int currentSel =
                    int.tryParse(_matrixCorrectAnswers[rowIdx]) ?? 0;

                return TableRow(
                  children: [
                    TableCell(
                      verticalAlignment: TableCellVerticalAlignment.middle,
                      child: Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Text(
                          rowText.isNotEmpty ? rowText : 'Row ${rowIdx + 1}',
                          style: TextStyle(
                            color: context.textColor,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    ...List.generate(_rightOptions.length, (colIdx) {
                      return TableCell(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4.0),
                          child: Center(
                            child: Radio<int>(
                              value: colIdx,
                              groupValue: currentSel,
                              activeColor: const Color(0xFF6366F1),
                              onChanged: (val) {
                                if (val != null) {
                                  setState(() {
                                    _matrixCorrectAnswers[rowIdx] = val
                                        .toString();
                                  });
                                }
                              },
                            ),
                          ),
                        ),
                      );
                    }),
                  ],
                );
              }),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildGeometricEditor() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Canvas Snapping Nodes Config:',
          style: TextStyle(
            color: context.textColor70,
            fontWeight: FontWeight.bold,
            fontSize: 15,
          ),
        ),
        const Padding(
          padding: EdgeInsets.only(top: 4, bottom: 12),
          child: Text(
            'Upload a background image first, then tap on the preview box to place snapping points. You can label vertices (e.g. A, B, C) and toggle whether they are blue fixed points or black targets.',
            style: TextStyle(color: Colors.white38, fontSize: 12, height: 1.4),
          ),
        ),
        const SizedBox(height: 8),

        // Node Placer Canvas Box (4:3 aspect ratio)
        LayoutBuilder(
          builder: (ctx, constraints) {
            final double width = constraints.maxWidth;
            final double height = width * 0.75; // 4:3 Aspect Ratio
            return GestureDetector(
              onTapUp: (details) {
                if (_questionImage.isEmpty) {
                  _showSnackBar(
                    'Please upload a background image first to place nodes.',
                  );
                  return;
                }
                final double xPct = (details.localPosition.dx / width) * 100;
                final double yPct = (details.localPosition.dy / height) * 100;
                setState(() {
                  final String newId =
                      'n${DateTime.now().millisecondsSinceEpoch}';
                  _geometryNodes.add({
                    'id': newId,
                    'label': '',
                    'x': double.parse(xPct.toStringAsFixed(1)),
                    'y': double.parse(yPct.toStringAsFixed(1)),
                    'isFixed': false,
                  });
                });
              },
              child: Container(
                width: width,
                height: height,
                decoration: BoxDecoration(
                  color: context.isDark
                      ? const Color(0xFF1E293B)
                      : Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: context.textColor54.withOpacity(0.4),
                  ),
                ),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    if (_questionImage.isNotEmpty)
                      Positioned.fill(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(11),
                          child: _renderImageOrSvg(
                            _questionImage,
                            _isQuestionSvg,
                          ),
                        ),
                      )
                    else
                      Center(
                        child: Text(
                          'Upload background image/diagram\nto enable tapping points',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: context.textColor54.withOpacity(0.4),
                            fontSize: 13,
                          ),
                        ),
                      ),

                    // Render nodes on canvas
                    ..._geometryNodes.map((node) {
                      final double left = (node['x'] / 100) * width;
                      final double top = (node['y'] / 100) * height;
                      final bool isFixed = node['isFixed'] == true;
                      return Positioned(
                        left: left - 12,
                        top: top - 12,
                        child: Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isFixed
                                ? Colors.blue.withOpacity(
                                    _hideGeometryNodes ? 0.35 : 0.85,
                                  )
                                : Colors.black.withOpacity(
                                    _hideGeometryNodes ? 0.35 : 0.85,
                                  ),
                            border: Border.all(
                              color: _hideGeometryNodes
                                  ? Colors.white54
                                  : Colors.white,
                              width: 1.5,
                            ),
                            boxShadow: const [
                              BoxShadow(
                                color: Colors.black26,
                                blurRadius: 4,
                                offset: Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Center(
                            child: Text(
                              node['label'] ?? '',
                              style: TextStyle(
                                color: context.textColor,
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ],
                ),
              ),
            );
          },
        ),

        const SizedBox(height: 24),

        // Node Cards List
        if (_geometryNodes.isNotEmpty) ...[
          Text(
            'Nodes Coordinates & Settings:',
            style: TextStyle(
              color: context.textColor70,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 12),
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _geometryNodes.length,
            itemBuilder: (ctx, idx) {
              final node = _geometryNodes[idx];
              final bool isFixed = node['isFixed'] == true;
              return Card(
                color: context.isDark ? const Color(0xFF1E293B) : Colors.white,
                margin: const EdgeInsets.only(bottom: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      // Node avatar preview
                      CircleAvatar(
                        radius: 12,
                        backgroundColor: isFixed ? Colors.blue : Colors.black54,
                        child: Text(
                          node['label'] ?? '',
                          style: TextStyle(
                            color: context.textColor,
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),

                      // Label field
                      Expanded(
                        child: TextFormField(
                          initialValue: node['label'],
                          style: TextStyle(
                            color: context.textColor,
                            fontSize: 13,
                          ),
                          decoration: InputDecoration(
                            labelText: 'Label',
                            labelStyle: TextStyle(
                              color: context.textColor54.withOpacity(0.5),
                              fontSize: 12,
                            ),
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(vertical: 8),
                          ),
                          onChanged: (val) {
                            setState(() {
                              _geometryNodes[idx]['label'] = val;
                            });
                          },
                        ),
                      ),
                      const SizedBox(width: 12),

                      // Fixed node toggle
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Fixed (Blue)',
                            style: TextStyle(
                              color: context.textColor54,
                              fontSize: 11,
                            ),
                          ),
                          Switch(
                            value: isFixed,
                            activeColor: Colors.blue,
                            onChanged: (val) {
                              setState(() {
                                _geometryNodes[idx]['isFixed'] = val;
                              });
                            },
                          ),
                        ],
                      ),

                      // Delete
                      IconButton(
                        icon: const Icon(
                          Icons.delete,
                          color: Colors.redAccent,
                          size: 18,
                        ),
                        onPressed: () {
                          setState(() {
                            final String deletedId = _geometryNodes[idx]['id'];
                            _geometryNodes.removeAt(idx);
                            // Also clear any invalid connections associated with this node
                            _geometryConnections.removeWhere((conn) {
                              final parts = conn.split('-');
                              return parts.contains(deletedId);
                            });
                          });
                        },
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],

        const SizedBox(height: 24),

        // Movable lines count
        DropdownButtonFormField<int>(
          value: _geometryLinesCount,
          dropdownColor: context.isDark
              ? const Color(0xFF1E293B)
              : Colors.white,
          style: TextStyle(color: context.textColor),
          decoration: InputDecoration(
            labelText: 'Movable Lines Count',
            labelStyle: TextStyle(color: context.textColor70),
            filled: true,
            fillColor: context.isDark ? const Color(0xFF1E293B) : Colors.white,
            border: OutlineInputBorder(),
          ),
          items: const [
            DropdownMenuItem(value: 1, child: Text('1 Movable Line Segment')),
            DropdownMenuItem(value: 2, child: Text('2 Movable Line Segments')),
          ],
          onChanged: (val) {
            if (val != null) {
              setState(() {
                _geometryLinesCount = val;
              });
            }
          },
        ),

        SwitchListTile(
          title: Text(
            'Hide Geometry Nodes (Use SVG background dots)',
            style: TextStyle(
              color: context.textColor,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
          subtitle: Text(
            'Draggable endpoints will still snap, but the overlay circles will be invisible so the student only sees the SVG background dots.',
            style: TextStyle(
              color: context.textColor54.withOpacity(0.5),
              fontSize: 11,
            ),
          ),
          value: _hideGeometryNodes,
          activeColor: const Color(0xFF6366F1),
          onChanged: (val) {
            setState(() {
              _hideGeometryNodes = val;
            });
          },
        ),
        const SizedBox(height: 24),

        // Connections List (Correct Solution)
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Correct Answer Connections (Solution):',
              style: TextStyle(
                color: context.textColor70,
                fontWeight: FontWeight.bold,
                fontSize: 15,
              ),
            ),
            TextButton.icon(
              icon: const Icon(Icons.add, size: 16, color: Color(0xFF818CF8)),
              label: const Text(
                'Add Connection',
                style: TextStyle(color: Color(0xFF818CF8)),
              ),
              onPressed: () {
                if (_geometryNodes.length < 2) {
                  _showSnackBar('Need at least 2 nodes to add a connection.');
                  return;
                }
                setState(() {
                  final String defaultConn =
                      '${_geometryNodes[0]['id']}-${_geometryNodes[1]['id']}';
                  _geometryConnections.add(defaultConn);
                });
              },
            ),
          ],
        ),
        const Padding(
          padding: EdgeInsets.only(top: 4, bottom: 12),
          child: Text(
            'Specify the exact line connections the student must build to earn points. (e.g. Node A connects to Node C).',
            style: TextStyle(color: Colors.white38, fontSize: 12, height: 1.4),
          ),
        ),

        if (_geometryConnections.isEmpty)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: context.glassBg,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: context.glassBorder),
            ),
            child: Center(
              child: Text(
                'No solution connections added yet. Click Add Connection.',
                style: TextStyle(
                  color: context.textColor54.withOpacity(0.4),
                  fontSize: 13,
                ),
              ),
            ),
          )
        else
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _geometryConnections.length,
            itemBuilder: (ctx, idx) {
              final connection = _geometryConnections[idx];
              final parts = connection.split('-');
              String node1 = parts.length > 0 ? parts[0] : '';
              String node2 = parts.length > 1 ? parts[1] : '';

              // Safely ensure nodes are valid/exist
              final bool node1Exists = _geometryNodes.any(
                (n) => n['id'] == node1,
              );
              final bool node2Exists = _geometryNodes.any(
                (n) => n['id'] == node2,
              );
              if (!node1Exists && _geometryNodes.isNotEmpty) {
                node1 = _geometryNodes[0]['id'];
              }
              if (!node2Exists && _geometryNodes.length > 1) {
                node2 = _geometryNodes[1]['id'];
              }

              return Card(
                color: context.isDark ? const Color(0xFF1E293B) : Colors.white,
                margin: const EdgeInsets.only(bottom: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Row(
                    children: [
                      // Node 1 Dropdown
                      Expanded(
                        child: DropdownButton<String>(
                          isExpanded: true,
                          value: node1,
                          dropdownColor: context.isDark
                              ? const Color(0xFF1E293B)
                              : Colors.white,
                          style: TextStyle(
                            color: context.textColor,
                            fontSize: 13,
                          ),
                          underline: const SizedBox(),
                          items: _geometryNodes.map((n) {
                            final label =
                                n['label'] != null &&
                                    n['label'].toString().isNotEmpty
                                ? n['label']
                                : 'Node (${n['x']}%, ${n['y']}%)';
                            return DropdownMenuItem<String>(
                              value: n['id'],
                              child: Text(label),
                            );
                          }).toList(),
                          onChanged: (val) {
                            if (val != null) {
                              setState(() {
                                // Keep sorted order n1-n2
                                final list = [val, node2]..sort();
                                _geometryConnections[idx] =
                                    '${list[0]}-${list[1]}';
                              });
                            }
                          },
                        ),
                      ),

                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 12),
                        child: Icon(
                          Icons.arrow_forward_rounded,
                          color: context.textColor54.withOpacity(0.5),
                          size: 16,
                        ),
                      ),

                      // Node 2 Dropdown
                      Expanded(
                        child: DropdownButton<String>(
                          isExpanded: true,
                          value: node2,
                          dropdownColor: context.isDark
                              ? const Color(0xFF1E293B)
                              : Colors.white,
                          style: TextStyle(
                            color: context.textColor,
                            fontSize: 13,
                          ),
                          underline: const SizedBox(),
                          items: _geometryNodes.map((n) {
                            final label =
                                n['label'] != null &&
                                    n['label'].toString().isNotEmpty
                                ? n['label']
                                : 'Node (${n['x']}%, ${n['y']}%)';
                            return DropdownMenuItem<String>(
                              value: n['id'],
                              child: Text(label),
                            );
                          }).toList(),
                          onChanged: (val) {
                            if (val != null) {
                              setState(() {
                                final list = [node1, val]..sort();
                                _geometryConnections[idx] =
                                    '${list[0]}-${list[1]}';
                              });
                            }
                          },
                        ),
                      ),

                      // Delete connection
                      IconButton(
                        icon: const Icon(
                          Icons.delete,
                          color: Colors.redAccent,
                          size: 18,
                        ),
                        onPressed: () {
                          setState(() {
                            _geometryConnections.removeAt(idx);
                          });
                        },
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
      ],
    );
  }

  void _addEmptyMatchingPair() {
    setState(() {
      _options.add({'text': '', 'imageUrl': '', 'isSvg': false});
      _rightOptions.add({'text': '', 'imageUrl': '', 'isSvg': false});
    });
  }

  void _removeMatchingPair(int idx) {
    setState(() {
      _options.removeAt(idx);
      _rightOptions.removeAt(idx);
    });
  }

  Future<void> _pickAndUploadMatchingFile(
    int idx, {
    required bool isLeft,
  }) async {
    try {
      FilePickerResult? result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['svg', 'png', 'jpg', 'jpeg'],
        withData: true,
      );

      if (result != null && result.files.single.bytes != null) {
        final fileBytes = result.files.single.bytes!;
        final fileName = result.files.single.name;

        _showSnackBar('Uploading file...', duration: 1);

        final res = await ApiService.uploadFile(
          '/assessment-questions/upload',
          fileBytes,
          fileName,
          fieldName: 'file',
        );

        if (res.statusCode == 200) {
          final resBody = await res.stream.bytesToString();
          final data = jsonDecode(resBody);
          setState(() {
            if (isLeft) {
              _options[idx]['imageUrl'] = data['fileUrl'] ?? '';
              _options[idx]['isSvg'] = fileName.toLowerCase().endsWith('.svg');
            } else {
              _rightOptions[idx]['imageUrl'] = data['fileUrl'] ?? '';
              _rightOptions[idx]['isSvg'] = fileName.toLowerCase().endsWith(
                '.svg',
              );
            }
          });
          _showSnackBar('File uploaded successfully!', isSuccess: true);
        } else {
          _showSnackBar('Failed to upload image');
        }
      }
    } catch (e) {
      _showSnackBar('Error picking file: $e');
    }
  }

  Widget _buildFormImagePicker({
    required String imageUrl,
    required bool isSvg,
    required VoidCallback onPick,
    required VoidCallback onClear,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (imageUrl.isNotEmpty) ...[
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: context.glassBorder,
              borderRadius: BorderRadius.circular(6),
            ),
            height: 40,
            child: Row(
              children: [
                Expanded(child: _renderImageOrSvg(imageUrl, isSvg)),
                IconButton(
                  icon: const Icon(
                    Icons.cancel,
                    color: Colors.redAccent,
                    size: 16,
                  ),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: onClear,
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
        ],
        OutlinedButton.icon(
          onPressed: onPick,
          icon: Icon(Icons.image, size: 12, color: context.textColor70),
          label: Text(
            imageUrl.isNotEmpty ? 'Change SVG/Img' : 'Add SVG/Img',
            style: const TextStyle(fontSize: 11),
          ),
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.white70,
            side: BorderSide(color: context.glassBorder),
            padding: const EdgeInsets.symmetric(vertical: 8),
          ),
        ),
      ],
    );
  }

  Widget _buildMatchingPairsInput() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Match Pairs (Left Item ➔ Right Item):',
              style: TextStyle(
                color: context.textColor70,
                fontWeight: FontWeight.bold,
                fontSize: 15,
              ),
            ),
            TextButton.icon(
              icon: const Icon(Icons.add, size: 16, color: Color(0xFF818CF8)),
              label: const Text(
                'Add Pair',
                style: TextStyle(color: Color(0xFF818CF8)),
              ),
              onPressed: _addEmptyMatchingPair,
            ),
          ],
        ),
        const Padding(
          padding: EdgeInsets.only(top: 4, bottom: 12),
          child: Text(
            'Write each matching pair side-by-side. The app will automatically separate and shuffle the right column for students.',
            style: TextStyle(color: Colors.white38, fontSize: 12, height: 1.4),
          ),
        ),
        const SizedBox(height: 8),
        ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _options.length,
          itemBuilder: (ctx, idx) {
            final leftOpt = _options[idx];

            // Safety guard: ensure _rightOptions index matches _options
            if (idx >= _rightOptions.length) {
              _rightOptions.add({'text': '', 'imageUrl': '', 'isSvg': false});
            }
            final rightOpt = _rightOptions[idx];

            return Card(
              color: context.isDark ? const Color(0xFF1E293B) : Colors.white,
              margin: const EdgeInsets.only(bottom: 20),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 12,
                          backgroundColor: const Color(
                            0xFF6366F1,
                          ).withOpacity(0.15),
                          child: Text(
                            '${idx + 1}',
                            style: const TextStyle(
                              color: Color(0xFF818CF8),
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Pair Item Details',
                          style: TextStyle(
                            color: context.textColor60,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                        const Spacer(),
                        if (_options.length > 1)
                          IconButton(
                            icon: const Icon(
                              Icons.delete,
                              color: Colors.redAccent,
                              size: 20,
                            ),
                            onPressed: () => _removeMatchingPair(idx),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Left Item Column
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                'Left Side',
                                style: TextStyle(
                                  color: context.textColor54,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 6),
                              TextFormField(
                                initialValue: leftOpt['text'],
                                style: TextStyle(
                                  color: context.textColor,
                                  fontSize: 13,
                                ),
                                decoration: InputDecoration(
                                  hintText: 'Left item text',
                                  hintStyle: TextStyle(
                                    color: context.textColor54.withOpacity(0.5),
                                  ),
                                  isDense: true,
                                  border: OutlineInputBorder(),
                                ),
                                onChanged: (val) => _options[idx]['text'] = val,
                              ),
                              const SizedBox(height: 8),
                              _buildFormImagePicker(
                                imageUrl: leftOpt['imageUrl'] ?? '',
                                isSvg: leftOpt['isSvg'] == true,
                                onPick: () => _pickAndUploadMatchingFile(
                                  idx,
                                  isLeft: true,
                                ),
                                onClear: () {
                                  setState(() {
                                    _options[idx]['imageUrl'] = '';
                                    _options[idx]['isSvg'] = false;
                                  });
                                },
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(width: 8),

                        Padding(
                          padding: EdgeInsets.only(top: 24),
                          child: Icon(
                            Icons.arrow_forward_rounded,
                            color: context.textColor54.withOpacity(0.4),
                            size: 16,
                          ),
                        ),

                        const SizedBox(width: 8),

                        // Right Item Column
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                'Right Side',
                                style: TextStyle(
                                  color: context.textColor54,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 6),
                              TextFormField(
                                initialValue: rightOpt['text'],
                                style: TextStyle(
                                  color: context.textColor,
                                  fontSize: 13,
                                ),
                                decoration: InputDecoration(
                                  hintText: 'Right item text',
                                  hintStyle: TextStyle(
                                    color: context.textColor54.withOpacity(0.5),
                                  ),
                                  isDense: true,
                                  border: OutlineInputBorder(),
                                ),
                                onChanged: (val) =>
                                    _rightOptions[idx]['text'] = val,
                              ),
                              const SizedBox(height: 8),
                              _buildFormImagePicker(
                                imageUrl: rightOpt['imageUrl'] ?? '',
                                isSvg: rightOpt['isSvg'] == true,
                                onPick: () => _pickAndUploadMatchingFile(
                                  idx,
                                  isLeft: false,
                                ),
                                onClear: () {
                                  setState(() {
                                    _rightOptions[idx]['imageUrl'] = '';
                                    _rightOptions[idx]['isSvg'] = false;
                                  });
                                },
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  String _generateMongoObjectId() {
    final random = Random();
    final buffer = StringBuffer();
    for (int i = 0; i < 24; i++) {
      buffer.write(random.nextInt(16).toRadixString(16));
    }
    return buffer.toString();
  }
}
