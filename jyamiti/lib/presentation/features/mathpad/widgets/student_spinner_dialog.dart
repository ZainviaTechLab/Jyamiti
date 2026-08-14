import 'dart:math';
import 'package:flutter/material.dart';

import 'student_spinner_group_storage_service.dart';

/// Wraps either a batch (`Map` from `auth.profile['batches']`, shape
/// `{name/title, students: [{name, ...}]}`) or a tutor-defined
/// [SpinnerGroup] so the dialog can treat both uniformly in the dropdown
/// and roster-management UI.
class _SpinnerSource {
  final String label;
  final List<String> allStudents;
  final SpinnerGroup? group; // null for a batch source

  _SpinnerSource.batch(dynamic batch)
      : label = (batch['name'] ?? batch['title'] ?? 'Unknown Batch').toString(),
        allStudents = ((batch['students'] as List?) ?? [])
            .map((s) => (s['name'] ?? 'Unknown').toString())
            .toList(),
        group = null;

  _SpinnerSource.group(SpinnerGroup g)
      : label = g.name,
        allStudents = g.studentNames,
        group = g;

  bool get isCustom => group != null;
}

/// Sentinel dropdown value for the "+ New Group" entry -- selecting it
/// doesn't change `_selectedSource`, it just opens the create-group flow.
const Object _kAddGroupSentinel = Object();

class StudentSpinnerDialog extends StatefulWidget {
  final List<dynamic> batches;

  const StudentSpinnerDialog({super.key, required this.batches});

  @override
  State<StudentSpinnerDialog> createState() => _StudentSpinnerDialogState();
}

class _StudentSpinnerDialogState extends State<StudentSpinnerDialog>
    with SingleTickerProviderStateMixin {
  final _groupStorage = StudentSpinnerGroupStorageService();

  List<SpinnerGroup> _customGroups = [];
  bool _loadingGroups = true;

  _SpinnerSource? _selectedSource;
  /// Students excluded from the currently selected source for this spin --
  /// resets whenever the source changes. Doesn't touch the underlying
  /// batch roster or a saved group's membership.
  final Set<String> _excludedNames = {};

  late AnimationController _controller;
  late Animation<double> _animation;

  double _currentAngle = 0;
  String? _winnerName;

  @override
  void initState() {
    super.initState();
    if (widget.batches.isNotEmpty) {
      _selectedSource = _SpinnerSource.batch(widget.batches.first);
    }

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    );

    _controller.addListener(() {
      setState(() {
        _currentAngle = _animation.value;
      });
    });

    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _calculateWinner();
      }
    });

    _loadGroups();
  }

  Future<void> _loadGroups() async {
    final groups = await _groupStorage.loadGroups();
    if (!mounted) return;
    setState(() {
      _customGroups = groups;
      _loadingGroups = false;
      _selectedSource ??= groups.isNotEmpty ? _SpinnerSource.group(groups.first) : null;
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  List<String> get _currentStudents {
    final source = _selectedSource;
    if (source == null) return [];
    return source.allStudents.where((s) => !_excludedNames.contains(s)).toList();
  }

  /// All student names across every batch, deduped, for building a new
  /// custom group.
  List<String> get _allBatchStudentNames {
    final seen = <String>{};
    for (final b in widget.batches) {
      final students = (b['students'] as List?) ?? [];
      for (final s in students) {
        seen.add((s['name'] ?? 'Unknown').toString());
      }
    }
    final list = seen.toList()..sort();
    return list;
  }

  void _spin() {
    if (_currentStudents.isEmpty) return;

    setState(() {
      _winnerName = null;
    });

    final random = Random();
    // Spin at least 3 full circles, plus a random fraction
    final extraSpins = 3 + random.nextInt(3);
    final randomFraction = random.nextDouble() * 2 * pi;
    final targetAngle = _currentAngle + (extraSpins * 2 * pi) + randomFraction;

    _animation = Tween<double>(
      begin: _currentAngle,
      end: targetAngle,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));

    _controller.forward(from: 0);
  }

  void _calculateWinner() {
    final students = _currentStudents;
    if (students.isEmpty) return;

    final sweepAngle = 2 * pi / students.length;
    final normalizedAngle = _currentAngle % (2 * pi);

    // The top pointer is at -pi/2 in our drawing space.
    final pointerAngle = (2 * pi - normalizedAngle) % (2 * pi);
    final winnerIndex = (pointerAngle / sweepAngle).floor() % students.length;

    setState(() {
      _winnerName = students[winnerIndex];
    });
  }

  Future<void> _openCreateGroupDialog() async {
    final newGroup = await showDialog<SpinnerGroup>(
      context: context,
      builder: (_) => _CreateGroupDialog(allStudentNames: _allBatchStudentNames),
    );
    if (newGroup == null) return;

    final updated = [..._customGroups, newGroup];
    await _groupStorage.saveGroups(updated);
    if (!mounted) return;
    setState(() {
      _customGroups = updated;
      _selectedSource = _SpinnerSource.group(newGroup);
      _excludedNames.clear();
      _currentAngle = 0;
      _winnerName = null;
    });
  }

  Future<void> _deleteSelectedGroup() async {
    final source = _selectedSource;
    if (source == null || !source.isCustom) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Group?'),
        content: Text(
          'This removes "${source.label}" permanently. It won\'t affect any batch rosters.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final updated = _customGroups.where((g) => g.id != source.group!.id).toList();
    await _groupStorage.saveGroups(updated);
    if (!mounted) return;
    setState(() {
      _customGroups = updated;
      _selectedSource = widget.batches.isNotEmpty
          ? _SpinnerSource.batch(widget.batches.first)
          : (updated.isNotEmpty ? _SpinnerSource.group(updated.first) : null);
      _excludedNames.clear();
      _currentAngle = 0;
      _winnerName = null;
    });
  }

  Future<void> _openManageRosterDialog() async {
    final source = _selectedSource;
    if (source == null || source.allStudents.isEmpty) return;

    final updatedExcluded = await showDialog<Set<String>>(
      context: context,
      builder: (_) => _ManageRosterDialog(
        allStudents: source.allStudents,
        initiallyExcluded: _excludedNames,
      ),
    );
    if (updatedExcluded == null) return;
    setState(() {
      _excludedNames
        ..clear()
        ..addAll(updatedExcluded);
      _currentAngle = 0;
      _winnerName = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final students = _currentStudents;
    final source = _selectedSource;
    final hasAnySource = widget.batches.isNotEmpty || _customGroups.isNotEmpty;

    return Dialog(
      backgroundColor: isDark ? const Color(0xFF1E1E2C) : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Student Spinner',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            if (hasAnySource)
              Row(
                children: [
                  Expanded(
                    child: DropdownButton<Object>(
                      value: source?.isCustom == true ? source!.group : source?.label,
                      isExpanded: true,
                      dropdownColor: isDark ? const Color(0xFF2A2A3C) : Colors.white,
                      items: [
                        ...widget.batches.map((b) {
                          final s = _SpinnerSource.batch(b);
                          return DropdownMenuItem<Object>(
                            value: s.label,
                            child: Text(
                              s.label,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: isDark ? Colors.white : Colors.black87),
                            ),
                          );
                        }),
                        ..._customGroups.map((g) {
                          return DropdownMenuItem<Object>(
                            value: g,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.group_rounded,
                                  size: 16,
                                  color: Colors.deepPurpleAccent,
                                ),
                                const SizedBox(width: 6),
                                Flexible(
                                  child: Text(
                                    g.name,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(color: isDark ? Colors.white : Colors.black87),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),
                        DropdownMenuItem<Object>(
                          value: _kAddGroupSentinel,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.add_circle_outline_rounded, size: 16, color: Colors.green),
                              const SizedBox(width: 6),
                              Text(
                                'New Group…',
                                style: TextStyle(color: isDark ? Colors.white : Colors.black87),
                              ),
                            ],
                          ),
                        ),
                      ],
                      onChanged: _controller.isAnimating
                          ? null
                          : (value) {
                              if (value == _kAddGroupSentinel) {
                                _openCreateGroupDialog();
                                return;
                              }
                              setState(() {
                                if (value is SpinnerGroup) {
                                  _selectedSource = _SpinnerSource.group(value);
                                } else {
                                  final batch = widget.batches.firstWhere(
                                    (b) =>
                                        (b['name'] ?? b['title'] ?? 'Unknown Batch').toString() ==
                                        value,
                                  );
                                  _selectedSource = _SpinnerSource.batch(batch);
                                }
                                _excludedNames.clear();
                                _currentAngle = 0;
                                _winnerName = null;
                              });
                            },
                    ),
                  ),
                  if (source != null && source.allStudents.isNotEmpty)
                    IconButton(
                      tooltip: 'Include/exclude students',
                      icon: const Icon(Icons.checklist_rtl_rounded),
                      onPressed: _controller.isAnimating ? null : _openManageRosterDialog,
                    ),
                  if (source != null && source.isCustom)
                    IconButton(
                      tooltip: 'Delete group',
                      icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
                      onPressed: _controller.isAnimating ? null : _deleteSelectedGroup,
                    ),
                ],
              )
            else if (_loadingGroups)
              const SizedBox(
                height: 24,
                width: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              const Text('No assigned batches found.'),

            if (source != null && _excludedNames.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  '${_excludedNames.length} excluded this round',
                  style: TextStyle(fontSize: 12, color: isDark ? Colors.white54 : Colors.black54),
                ),
              ),

            const SizedBox(height: 32),

            if (students.isEmpty)
              SizedBox(
                height: 250,
                child: Center(
                  child: Text(
                    source == null
                        ? 'No students in this batch.'
                        : 'All students excluded -- adjust the list above.',
                    textAlign: TextAlign.center,
                  ),
                ),
              )
            else
              SizedBox(
                height: 250,
                width: 250,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Transform.rotate(
                      angle: _currentAngle,
                      child: CustomPaint(
                        size: const Size(250, 250),
                        painter: _RoulettePainter(
                          students: students,
                          isDark: isDark,
                        ),
                      ),
                    ),
                    Positioned(
                      top: -12,
                      child: CustomPaint(
                        size: const Size(24, 24),
                        painter: _PointerPainter(),
                      ),
                    ),
                  ],
                ),
              ),

            const SizedBox(height: 24),

            SizedBox(
              height: 32,
              child: _winnerName != null
                  ? Text(
                      '🎉 $_winnerName 🎉',
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Colors.green,
                      ),
                    )
                  : const SizedBox.shrink(),
            ),

            const SizedBox(height: 24),

            FilledButton.icon(
              onPressed: students.isEmpty || _controller.isAnimating
                  ? null
                  : _spin,
              icon: const Icon(Icons.casino_rounded),
              label: const Text('SPIN'),
              style: FilledButton.styleFrom(
                minimumSize: const Size(200, 48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Lets the tutor tick students in/out of the current spin without
/// touching the underlying batch roster or saved group membership.
class _ManageRosterDialog extends StatefulWidget {
  final List<String> allStudents;
  final Set<String> initiallyExcluded;

  const _ManageRosterDialog({required this.allStudents, required this.initiallyExcluded});

  @override
  State<_ManageRosterDialog> createState() => _ManageRosterDialogState();
}

class _ManageRosterDialogState extends State<_ManageRosterDialog> {
  late Set<String> _excluded;

  @override
  void initState() {
    super.initState();
    _excluded = {...widget.initiallyExcluded};
  }

  @override
  Widget build(BuildContext context) {
    final includedCount = widget.allStudents.length - _excluded.length;
    return AlertDialog(
      title: const Text('Include/Exclude Students'),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(child: Text('$includedCount of ${widget.allStudents.length} included')),
                TextButton(
                  onPressed: () => setState(() => _excluded.clear()),
                  child: const Text('Select All'),
                ),
                TextButton(
                  onPressed: () => setState(() => _excluded = widget.allStudents.toSet()),
                  child: const Text('Clear'),
                ),
              ],
            ),
            const Divider(),
            SizedBox(
              height: 320,
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: widget.allStudents.length,
                itemBuilder: (context, i) {
                  final name = widget.allStudents[i];
                  final included = !_excluded.contains(name);
                  return CheckboxListTile(
                    dense: true,
                    value: included,
                    title: Text(name),
                    onChanged: (checked) {
                      setState(() {
                        if (checked == true) {
                          _excluded.remove(name);
                        } else {
                          _excluded.add(name);
                        }
                      });
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: () => Navigator.pop(context, _excluded),
          child: const Text('Apply'),
        ),
      ],
    );
  }
}

/// Create a new named custom group. Members are typed in one at a time via
/// "Add Student" -- this group doesn't have to mirror any batch roster, so
/// there's no mandatory pick-from-everyone list. A batch's existing names
/// are offered only as optional tap-to-add suggestion chips, to save
/// re-typing someone who's already enrolled somewhere.
class _CreateGroupDialog extends StatefulWidget {
  final List<String> allStudentNames;

  const _CreateGroupDialog({required this.allStudentNames});

  @override
  State<_CreateGroupDialog> createState() => _CreateGroupDialogState();
}

class _CreateGroupDialogState extends State<_CreateGroupDialog> {
  final _nameController = TextEditingController();
  final _studentController = TextEditingController();
  final List<String> _members = [];
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    _studentController.dispose();
    super.dispose();
  }

  void _addStudent([String? typed]) {
    final name = (typed ?? _studentController.text).trim();
    if (name.isEmpty) return;
    if (_members.any((m) => m.toLowerCase() == name.toLowerCase())) {
      setState(() => _error = '"$name" is already in this group.');
      return;
    }
    setState(() {
      _members.add(name);
      _studentController.clear();
      _error = null;
    });
  }

  void _removeStudent(String name) {
    setState(() => _members.remove(name));
  }

  void _save() {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Give the group a name.');
      return;
    }
    if (_members.isEmpty) {
      setState(() => _error = 'Add at least one student.');
      return;
    }
    Navigator.pop(
      context,
      SpinnerGroup(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        name: name,
        studentNames: _members,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final suggestions = widget.allStudentNames
        .where((n) => !_members.any((m) => m.toLowerCase() == n.toLowerCase()))
        .toList();

    return AlertDialog(
      title: const Text('New Group'),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _nameController,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Group name',
                hintText: 'e.g. "Front Row" or "Advanced"',
              ),
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
            ),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    controller: _studentController,
                    decoration: const InputDecoration(
                      labelText: 'Add student',
                      hintText: 'Type a name and press Add',
                    ),
                    onSubmitted: (_) => _addStudent(),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () => _addStudent(),
                  child: const Text('Add'),
                ),
              ],
            ),
            if (suggestions.isNotEmpty) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: suggestions.map((name) {
                    return ActionChip(
                      label: Text(name, style: const TextStyle(fontSize: 12)),
                      avatar: const Icon(Icons.add, size: 14),
                      onPressed: () => _addStudent(name),
                    );
                  }).toList(),
                ),
              ),
            ],
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '${_members.length} in this group',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 8),
            if (_members.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text('No students added yet.'),
              )
            else
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 220),
                child: SingleChildScrollView(
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: _members.map((name) {
                      return InputChip(
                        label: Text(name),
                        onDeleted: () => _removeStudent(name),
                      );
                    }).toList(),
                  ),
                ),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_error!, style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _save, child: const Text('Create')),
      ],
    );
  }
}

class _RoulettePainter extends CustomPainter {
  final List<String> students;
  final bool isDark;

  _RoulettePainter({required this.students, required this.isDark});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final center = rect.center;
    final radius = size.width / 2;
    final sweepAngle = 2 * pi / students.length;

    final colors = [
      Colors.redAccent,
      Colors.blueAccent,
      Colors.greenAccent.shade700,
      Colors.orangeAccent,
      Colors.purpleAccent,
      Colors.tealAccent.shade700,
      Colors.amberAccent.shade700,
      Colors.pinkAccent,
    ];

    for (int i = 0; i < students.length; i++) {
      final paint = Paint()
        ..color = colors[i % colors.length]
        ..style = PaintingStyle.fill;

      final startAngle = -pi / 2 + (i * sweepAngle);

      canvas.drawArc(rect, startAngle, sweepAngle, true, paint);

      final borderPaint = Paint()
        ..color = isDark ? const Color(0xFF1E1E2C) : Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;
      canvas.drawArc(rect, startAngle, sweepAngle, true, borderPaint);

      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(startAngle + sweepAngle / 2);

      final textPainter = TextPainter(
        text: TextSpan(
          text: students[i].length > 12
              ? '${students[i].substring(0, 10)}...'
              : students[i],
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      textPainter.layout(maxWidth: radius - 30);

      canvas.translate(
        radius / 2 - textPainter.width / 2 + 10,
        -textPainter.height / 2,
      );
      textPainter.paint(canvas, Offset.zero);

      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _RoulettePainter oldDelegate) {
    return oldDelegate.students != students || oldDelegate.isDark != isDark;
  }
}

class _PointerPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    final borderPaint = Paint()
      ..color = Colors.black45
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    final path = Path()
      ..moveTo(size.width / 2, size.height) // tip pointing down
      ..lineTo(0, 0)
      ..lineTo(size.width, 0)
      ..close();

    canvas.drawPath(path, paint);
    canvas.drawPath(path, borderPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
