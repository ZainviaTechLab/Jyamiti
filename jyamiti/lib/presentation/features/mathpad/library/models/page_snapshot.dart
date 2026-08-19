import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart' show Offset, Color, Rect;

import '../../instruments/instrument_models.dart';
import '../../instruments/media_embed_models.dart';
import '../../screens/mathpad.dart';

/// Everything visible on one Math Pad canvas -- the full content of one
/// saved "page" in the library. Pure in-memory representation; no file I/O
/// happens here (see `MathPadLibraryStorageService` for that), so this is
/// easy to reason about/test independent of `path_provider`/`dart:io`.
class MathPadPageSnapshot {
  final List<MathsPadLine> lines;
  final List<InstrumentState> instruments;
  final List<MathsPadTextLabel> textLabels;
  final List<MathsPadFixedAngleLabel> fixedAngleLabels;
  final CanvasBgMode bgMode;
  final MathPadTheme themeMode;

  MathPadPageSnapshot({
    required this.lines,
    required this.instruments,
    required this.textLabels,
    required this.fixedAngleLabels,
    required this.bgMode,
    required this.themeMode,
  });

  /// A blank page. [bgMode]/[themeMode] default to the app's own defaults,
  /// but callers creating a new page alongside existing ones (see
  /// `_addPage` in `mathpad_page_editor_page.dart`) should pass the
  /// previous page's values instead, so a freshly added page continues the
  /// tutor's current look rather than jumping back to light/grid.
  factory MathPadPageSnapshot.empty({
    CanvasBgMode bgMode = CanvasBgMode.grid,
    MathPadTheme themeMode = MathPadTheme.light,
  }) => MathPadPageSnapshot(
    lines: [],
    instruments: [],
    textLabels: [],
    fixedAngleLabels: [],
    bgMode: bgMode,
    themeMode: themeMode,
  );
}

const Map<CanvasBgMode, String> _bgModeNames = {
  CanvasBgMode.grid: 'grid',
  CanvasBgMode.ruled: 'ruled',
  CanvasBgMode.blank: 'blank',
};

CanvasBgMode _bgModeFromName(String? name) {
  if (name == 'jyamitiCosmos') return CanvasBgMode.blank; // Migration
  return _bgModeNames.entries
      .firstWhere((e) => e.value == name, orElse: () => const MapEntry(CanvasBgMode.grid, 'grid'))
      .key;
}

const Map<MathPadTheme, String> _themeModeNames = {
  MathPadTheme.light: 'light',
  MathPadTheme.dark: 'dark',
  MathPadTheme.cosmos: 'cosmos',
  MathPadTheme.aswadLail: 'aswadLail',
};

MathPadTheme _themeModeFromName(String? name) => _themeModeNames.entries
    .firstWhere((e) => e.value == name, orElse: () => const MapEntry(MathPadTheme.light, 'light'))
    .key;

Map<String, dynamic> _offsetToJson(Offset o) => {'dx': o.dx, 'dy': o.dy};

Offset _offsetFromJson(Map<String, dynamic> json) =>
    Offset((json['dx'] as num).toDouble(), (json['dy'] as num).toDouble());

/// Encodes [snapshot] to the `page.json` map shape. Any line with a
/// [MathsPadLine.fillImage] has its PNG bytes handed to [writeImageBytes]
/// (which the storage service uses to actually write the sibling image
/// file) and the JSON records only the relative filename.
Future<Map<String, dynamic>> encodePageSnapshot(
  MathPadPageSnapshot snapshot, {
  required Future<void> Function(String relativePath, Uint8List pngBytes) writeImageBytes,
}) async {
  final List<Map<String, dynamic>> lineJsons = [];
  for (int i = 0; i < snapshot.lines.length; i++) {
    final line = snapshot.lines[i];
    String? fillImageFile;
    if (line.fillImage != null) {
      final ByteData? byteData = await line.fillImage!.toByteData(
        format: ui.ImageByteFormat.png,
      );
      if (byteData != null) {
        fillImageFile = 'images/line_$i.png';
        await writeImageBytes(fillImageFile, byteData.buffer.asUint8List());
      }
    }
    lineJsons.add({
      'points': line.points
          .map(
            (p) => {
              ..._offsetToJson(p.offset),
              if (p.pressure != null) 'pr': p.pressure,
            },
          )
          .toList(),
      'color': line.color.toARGB32(),
      'strokeWidth': line.strokeWidth,
      'isEraser': line.isEraser,
      'isShape': line.isShape,
      'isPencil': line.isPencil,
      'fillImageFile': fillImageFile,
      'rotation': line.rotation,
      'isPastedImage': line.isPastedImage,
    });
  }

  final List<Map<String, dynamic>> instrumentJsons = snapshot.instruments
      .map(_encodeInstrument)
      .whereType<Map<String, dynamic>>()
      .toList();

  final List<Map<String, dynamic>> textLabelJsons = snapshot.textLabels
      .map(
        (l) => {
          'dx': l.position.dx,
          'dy': l.position.dy,
          'text': l.text,
          'color': l.color.toARGB32(),
          'fontSize': l.fontSize,
        },
      )
      .toList();

  final List<Map<String, dynamic>> fixedAngleLabelJsons = snapshot.fixedAngleLabels
      .map((label) {
        final sourceLineIndices = label.sourceLines
            .map((l) => snapshot.lines.indexOf(l))
            .where((idx) => idx != -1)
            .toList();
        return {
          'vertexDx': label.vertex.dx,
          'vertexDy': label.vertex.dy,
          'startAngle': label.startAngle,
          'sweepAngle': label.sweepAngle,
          'text': label.text,
          'sourceLineIndices': sourceLineIndices,
        };
      })
      .toList();

  return {
    'version': 1,
    'bgMode': _bgModeNames[snapshot.bgMode],
    'themeMode': _themeModeNames[snapshot.themeMode],
    'lines': lineJsons,
    'instruments': instrumentJsons,
    'textLabels': textLabelJsons,
    'fixedAngleLabels': fixedAngleLabelJsons,
  };
}

Map<String, dynamic>? _encodeInstrument(InstrumentState inst) {
  final base = {'pivotDx': inst.pivot.dx, 'pivotDy': inst.pivot.dy, 'rotation': inst.rotation};
  if (inst is RulerState) {
    return {
      ...base,
      'type': 'ruler',
      'lengthCm': inst.lengthCm,
      'pencilArmed': inst.pencilArmed,
      'pencilOffsetPx': inst.pencilOffsetPx,
    };
  } else if (inst is ProtractorState) {
    return {...base, 'type': 'protractor', 'radius': inst.radius};
  } else if (inst is CompassState) {
    return {
      ...base,
      'type': 'compass',
      'radiusCm': inst.radiusCm,
      'armAngle': inst.armAngle,
      'locked': inst.locked,
      'tracedArcPoints': inst.tracedArcPoints.map(_offsetToJson).toList(),
    };
  } else if (inst is SetSquareState) {
    return {
      ...base,
      'type': 'setSquare',
      'kind': inst.kind == SetSquareKind.fortyFive ? 'fortyFive' : 'thirtySixty',
      'scale': inst.scale,
      'pencilArmed': inst.pencilArmed,
      'pencilEdgeIndex': inst.pencilEdgeIndex,
      'pencilOffsetPx': inst.pencilOffsetPx,
    };
  } else if (inst is MediaEmbedState) {
    // No byte-duplication here, unlike a pasted image's `fillImageFile` --
    // `assetId` is a reference into the *global* Asset Library, resolved
    // lazily at render time, so replacing/editing that asset is reflected
    // everywhere it's embedded instead of freezing a copy per page.
    return {
      ...base,
      'type': 'mediaEmbed',
      'assetId': inst.assetId,
      'isGif': inst.isGif,
      'baseWidth': inst.baseWidth,
      'baseHeight': inst.baseHeight,
      'scale': inst.scale,
    };
  }
  return null;
}

InstrumentState? _decodeInstrument(Map<String, dynamic> json) {
  final pivot = Offset((json['pivotDx'] as num).toDouble(), (json['pivotDy'] as num).toDouble());
  final rotation = (json['rotation'] as num).toDouble();
  switch (json['type'] as String?) {
    case 'ruler':
      return RulerState(
        pivot: pivot,
        rotation: rotation,
        lengthCm: (json['lengthCm'] as num).toDouble(),
        pencilArmed: json['pencilArmed'] as bool? ?? false,
        pencilOffsetPx: (json['pencilOffsetPx'] as num?)?.toDouble(),
      );
    case 'protractor':
      return ProtractorState(
        pivot: pivot,
        rotation: rotation,
        radius: (json['radius'] as num).toDouble(),
      );
    case 'compass':
      return CompassState(
        pivot: pivot,
        rotation: rotation,
        radiusCm: (json['radiusCm'] as num).toDouble(),
        armAngle: (json['armAngle'] as num).toDouble(),
        locked: json['locked'] as bool? ?? false,
        tracedArcPoints: (json['tracedArcPoints'] as List? ?? [])
            .map((p) => _offsetFromJson(p as Map<String, dynamic>))
            .toList(),
      );
    case 'setSquare':
      return SetSquareState(
        pivot: pivot,
        rotation: rotation,
        kind: json['kind'] == 'thirtySixty' ? SetSquareKind.thirtySixty : SetSquareKind.fortyFive,
        scale: (json['scale'] as num).toDouble(),
        pencilArmed: json['pencilArmed'] as bool? ?? false,
        pencilEdgeIndex: json['pencilEdgeIndex'] as int? ?? 0,
        pencilOffsetPx: (json['pencilOffsetPx'] as num?)?.toDouble(),
      );
    case 'mediaEmbed':
      return MediaEmbedState(
        pivot: pivot,
        rotation: rotation,
        assetId: json['assetId'] as String,
        isGif: json['isGif'] as bool,
        baseWidth: (json['baseWidth'] as num).toDouble(),
        baseHeight: (json['baseHeight'] as num).toDouble(),
        scale: (json['scale'] as num?)?.toDouble() ?? 1.0,
      );
  }
  return null;
}

/// Decodes a `page.json` map (as produced by [encodePageSnapshot]) back
/// into a live [MathPadPageSnapshot]. Any line with a `fillImageFile`
/// reference has its PNG bytes fetched via [readImageBytes] and decoded
/// back into a `ui.Image` using the same codec pattern as
/// `_insertPastedImageBytes` in `mathpad.dart`.
Future<MathPadPageSnapshot> decodePageSnapshot(
  Map<String, dynamic> json, {
  required Future<Uint8List?> Function(String relativePath) readImageBytes,
}) async {
  final List<MathsPadLine> lines = [];
  for (final raw in (json['lines'] as List? ?? [])) {
    final lineJson = raw as Map<String, dynamic>;
    final points = (lineJson['points'] as List).map((p) {
      final ptJson = p as Map<String, dynamic>;
      return MathsPadStrokePoint(
        _offsetFromJson(ptJson),
        (ptJson['pr'] as num?)?.toDouble(),
      );
    }).toList();

    ui.Image? fillImage;
    Rect? fillWorldBounds;
    final fillImageFile = lineJson['fillImageFile'] as String?;
    if (fillImageFile != null) {
      final bytes = await readImageBytes(fillImageFile);
      if (bytes != null) {
        final codec = await ui.instantiateImageCodec(bytes);
        final frame = await codec.getNextFrame();
        fillImage = frame.image;
        if (points.length >= 2) {
          fillWorldBounds = Rect.fromPoints(points[0].offset, points[1].offset);
        }
      }
    }

    lines.add(
      MathsPadLine(
        points: points,
        color: Color(lineJson['color'] as int),
        strokeWidth: (lineJson['strokeWidth'] as num).toDouble(),
        isEraser: lineJson['isEraser'] as bool? ?? false,
        isShape: lineJson['isShape'] as bool? ?? false,
        isPencil: lineJson['isPencil'] as bool? ?? false,
        fillImage: fillImage,
        fillWorldBounds: fillWorldBounds,
        rotation: (lineJson['rotation'] as num?)?.toDouble() ?? 0,
        // Defaults false for pages saved before this flag existed --
        // indistinguishable from a Fill Tool result in that old data, so
        // it just keeps rendering underneath ink as it always did until
        // the page is saved again.
        isPastedImage: lineJson['isPastedImage'] as bool? ?? false,
      ),
    );
  }

  final instruments = (json['instruments'] as List? ?? [])
      .map((i) => _decodeInstrument(i as Map<String, dynamic>))
      .whereType<InstrumentState>()
      .toList();

  final textLabels = (json['textLabels'] as List? ?? [])
      .map(
        (raw) => MathsPadTextLabel(
          position: _offsetFromJson({'dx': raw['dx'], 'dy': raw['dy']}),
          text: raw['text'] as String,
          color: Color(raw['color'] as int),
          fontSize: (raw['fontSize'] as num?)?.toDouble() ?? 20,
        ),
      )
      .toList();

  final fixedAngleLabels = <MathsPadFixedAngleLabel>[];
  for (final raw in (json['fixedAngleLabels'] as List? ?? [])) {
    final labelJson = raw as Map<String, dynamic>;
    final indices = (labelJson['sourceLineIndices'] as List? ?? []).cast<int>();
    final sourceLines = indices
        .where((idx) => idx >= 0 && idx < lines.length)
        .map((idx) => lines[idx])
        .toList();
    if (sourceLines.length != 2) {
      // Orphaned/corrupt reference -- drop this label defensively rather
      // than throwing, matching how a fixed angle label is already treated
      // as disposable if either source line goes away at runtime.
      continue;
    }
    fixedAngleLabels.add(
      MathsPadFixedAngleLabel(
        vertex: _offsetFromJson({
          'dx': labelJson['vertexDx'],
          'dy': labelJson['vertexDy'],
        }),
        startAngle: (labelJson['startAngle'] as num).toDouble(),
        sweepAngle: (labelJson['sweepAngle'] as num).toDouble(),
        text: labelJson['text'] as String,
        sourceLines: sourceLines,
      ),
    );
  }

  final bgModeStr = json['bgMode'] as String?;
  final isLegacyCosmos = bgModeStr == 'jyamitiCosmos';

  return MathPadPageSnapshot(
    lines: lines,
    instruments: instruments,
    textLabels: textLabels,
    fixedAngleLabels: fixedAngleLabels,
    bgMode: _bgModeFromName(bgModeStr),
    themeMode: isLegacyCosmos 
        ? MathPadTheme.cosmos 
        : (json['themeMode'] != null ? _themeModeFromName(json['themeMode'] as String?) : MathPadTheme.light),
  );
}
