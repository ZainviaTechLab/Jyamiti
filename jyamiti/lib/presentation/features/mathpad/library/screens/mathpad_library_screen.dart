import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import 'package:jyamiti/presentation/widgets/jyamiti_loader.dart';
import 'package:jyamiti/providers/theme_provider.dart';
import 'package:jyamiti/services/api_service.dart';

import '../models/mathpad_library_models.dart';
import '../services/mathpad_library_storage_service.dart';
import '../widgets/mathpad_library_tree_view.dart';
import 'mathpad_page_editor_page.dart';

/// Per-batch Book -> Chapter -> Topic -> Sub-topic -> Pages navigator for a
/// tutor's Math Pad drawings, persisted entirely on-device (see
/// `MathPadLibraryStorageService`). Not available on web (no real
/// filesystem there) -- gated on `kIsWeb` both here and at the call site.
///
/// The actual book/chapter/topic/sub-topic tree UI lives in
/// `MathPadLibraryTreeView`, shared with the in-pad library drawer opened
/// from `MathPadPageEditorPage` -- this screen just owns batch selection
/// and loading/seeding the index before handing it to that shared view.
class MathPadLibraryScreen extends StatefulWidget {
  final List<dynamic>? batches;
  final bool isInline;

  const MathPadLibraryScreen({super.key, this.batches, this.isInline = true});

  @override
  State<MathPadLibraryScreen> createState() => _MathPadLibraryScreenState();
}

class _MathPadLibraryScreenState extends State<MathPadLibraryScreen> {
  final _storage = MathPadLibraryStorageService();

  String? _selectedBatchId;
  bool _loading = false;
  String? _errorMessage;
  MathPadLibraryIndex? _index;

  List<dynamic> get _batches => widget.batches ?? [];

  @override
  void initState() {
    super.initState();
    _resolveEntry();
  }

  /// Decides what to show the moment Math Pad is opened from the sidebar,
  /// preferring to land straight in the pad over making the tutor browse
  /// for it every time:
  /// 1. Resume the exact last-worked-on page, if it (and its batch) still
  ///    exist.
  /// 2. Otherwise, if that batch (or the tutor's only batch) already has
  ///    at least one book with a chapter, jump into the most-recently-added
  ///    level (deepest existing node).
  /// 3. Otherwise there's nothing to resume into -- fall through to the
  ///    normal browser, which itself prompts to create a book/chapter when
  ///    empty (multiple batches with no history also lands here, since
  ///    there's no single batch to guess at).
  Future<void> _resolveEntry() async {
    setState(() => _loading = true);

    final lastWorked = await _storage.loadLastWorked();
    final lastWorkedBatchValid =
        lastWorked != null &&
        _batches.any((b) => (b['id'] ?? b['_id']).toString() == lastWorked.batchId);

    if (lastWorkedBatchValid) {
      final index = await _loadIndexForBatch(lastWorked.batchId);
      if (index != null) {
        if (!mounted) return;
        setState(() {
          _selectedBatchId = lastWorked.batchId;
          _index = index;
          _loading = false;
        });
        final node = index.findNodeById(lastWorked.nodeId) ?? index.findLatestNode();
        if (node != null) {
          await _openNodePad(
            node,
            initialPageId: node.nodeId == lastWorked.nodeId ? lastWorked.pageId : null,
          );
        }
        // else: batch loaded fine but has nothing created in it yet --
        // the tree view's own empty-state ("New Book") handles that.
        return;
      }
    }

    // No usable last-worked pointer. With exactly one batch, still try to
    // jump straight to its latest level; with several, there's no single
    // batch to guess at, so just show the picker.
    if (_batches.length == 1) {
      final id = (_batches.first['id'] ?? _batches.first['_id']).toString();
      final index = await _loadIndexForBatch(id);
      if (!mounted) return;
      setState(() {
        _selectedBatchId = id;
        _index = index;
        _loading = false;
        _errorMessage = index == null ? 'Failed to load library.' : null;
      });
      final latest = index?.findLatestNode();
      if (latest != null) {
        await _openNodePad(latest);
      }
    } else {
      setState(() => _loading = false);
    }
  }

  Future<MathPadLibraryIndex?> _loadIndexForBatch(String batchId) async {
    try {
      final batch = _batches.firstWhere(
        (b) => (b['id'] ?? b['_id']).toString() == batchId,
      );
      final courseMap = batch['course'] as Map<String, dynamic>?;
      final courseName =
          courseMap?['name'] as String? ?? batch['name'] as String? ?? 'My Book';
      final courseId = (courseMap?['id'] ?? courseMap?['_id'])?.toString();

      // The batch's populated `course` only carries name/description, not
      // its syllabus -- fetch the full course list separately to seed the
      // default book's chapters/topics/sub-topics.
      List<dynamic>? syllabus;
      if (courseId != null) {
        try {
          final res = await ApiService.get('/courses');
          if (res.statusCode == 200) {
            final List<dynamic> courses = jsonDecode(res.body);
            final course = courses.firstWhere(
              (c) => (c['id'] ?? c['_id']).toString() == courseId,
              orElse: () => null,
            );
            syllabus = course?['syllabus'] as List?;
          }
        } catch (_) {
          // Fall through with no syllabus -- the default book still gets
          // created (with zero chapters), the tutor can add them manually.
        }
      }

      return await _storage.loadOrSeedIndex(
        batchId,
        batchCourseName: courseName,
        courseId: courseId,
        courseSyllabus: syllabus,
      );
    } catch (_) {
      return null;
    }
  }

  /// Manual batch switch (dropdown) -- unlike [_resolveEntry], this never
  /// auto-opens a node: picking a different batch on purpose means the
  /// tutor wants to browse it, not be redirected somewhere unexpected.
  Future<void> _selectBatch(String batchId) async {
    setState(() {
      _selectedBatchId = batchId;
      _index = null;
      _loading = true;
      _errorMessage = null;
    });
    final index = await _loadIndexForBatch(batchId);
    if (!mounted) return;
    setState(() {
      _index = index;
      _loading = false;
      _errorMessage = index == null ? 'Failed to load library.' : null;
    });
  }

  Future<void> _persistIndex() async {
    if (_selectedBatchId == null || _index == null) return;
    await _storage.saveIndex(_selectedBatchId!, _index!);
  }

  /// Opens the Math Pad directly for a Chapter/Topic/Sub-topic picked in
  /// the tree view (double-click target). Page creation/switching/deletion
  /// all happen INSIDE the pad itself from here on -- the library tree has
  /// no page UI of its own.
  Future<void> _openNodePad(MathPadFoundNode node, {String? initialPageId}) async {
    final batchId = _selectedBatchId;
    final index = _index;
    if (batchId == null || index == null) return;

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MathPadPageEditorPage(
          nodeId: node.nodeId,
          nodeTitle: node.nodeTitle,
          pages: node.pages,
          batchId: batchId,
          libraryIndex: index,
          storage: _storage,
          onPagesChanged: _persistIndex,
          initialPageId: initialPageId,
        ),
      ),
    );
    if (mounted) setState(() {}); // refresh any displayed metadata
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) return _buildWebFallback(context);

    if (_batches.isEmpty) {
      return _buildEmptyState(
        context,
        icon: Icons.class_outlined,
        message: 'No batches assigned yet.',
      );
    }

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeaderRow(context),
          const SizedBox(height: 16),
          Expanded(child: _buildBody(context)),
        ],
      ),
    );
  }

  Widget _buildHeaderRow(BuildContext context) {
    return Row(
      children: [
        Text(
          'Math Pad Library',
          style: TextStyle(
            color: context.textColor,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        const Spacer(),
        if (_batches.length > 1)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            decoration: BoxDecoration(
              color: context.isDark ? const Color(0xFF1E293B) : Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFF6366F1).withValues(alpha: 0.3)),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _selectedBatchId,
                hint: const Text('Select a batch'),
                dropdownColor: context.isDark ? const Color(0xFF1E293B) : Colors.white,
                icon: const Icon(Icons.expand_more_rounded, color: Color(0xFF6366F1)),
                items: _batches.map<DropdownMenuItem<String>>((b) {
                  final id = (b['id'] ?? b['_id']).toString();
                  final name = (b['name'] ?? 'Batch').toString();
                  return DropdownMenuItem(value: id, child: Text(name));
                }).toList(),
                onChanged: (val) {
                  if (val != null) _selectBatch(val);
                },
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loading) {
      return const Center(child: JyamitiLoader(color: Color(0xFF6366F1)));
    }
    if (_errorMessage != null) {
      return _buildEmptyState(context, icon: Icons.error_outline_rounded, message: _errorMessage!);
    }
    final batchId = _selectedBatchId;
    final index = _index;
    if (batchId == null || index == null) {
      return _buildEmptyState(
        context,
        icon: Icons.class_outlined,
        message: 'Select a batch to see its Math Pad library.',
      );
    }
    // Keyed by batch so switching batches resets the tree view's own
    // drilled-in navigation state instead of reusing it against a
    // different batch's chapters/topics.
    return MathPadLibraryTreeView(
      key: ValueKey(batchId),
      batchId: batchId,
      index: index,
      storage: _storage,
      onPersistIndex: _persistIndex,
      onOpenNode: _openNodePad,
    );
  }

  Widget _buildEmptyState(BuildContext context, {required IconData icon, required String message}) {
    return Center(
      child: Container(
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: context.isDark ? Colors.white.withValues(alpha: 0.03) : Colors.white.withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: context.glassBorder),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: context.textColor60),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: context.textColor60, fontSize: 15),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWebFallback(BuildContext context) {
    return _buildEmptyState(
      context,
      icon: Icons.desktop_windows_rounded,
      message:
          "Math Pad Library isn't available on the web version yet.\nPlease use the Windows/macOS/Linux desktop app or the Android/iOS app.",
    );
  }
}
