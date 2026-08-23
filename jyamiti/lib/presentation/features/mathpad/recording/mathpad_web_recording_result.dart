import 'dart:typed_data';

/// What `MathPadWebRecordingService.stop()` hands back -- raw bytes, not a
/// `package:web` `Blob`, so this stays usable from the stub (and anything
/// that imports the barrel) without pulling `package:web` in. What the
/// caller does with the bytes (save to `MathPadWebRecordingsStorageService`,
/// trigger a download, etc.) is deliberately not this class's concern.
class MathPadWebRecordingResult {
  const MathPadWebRecordingResult({
    required this.bytes,
    required this.mimeType,
    required this.fileExtension,
  });

  final Uint8List bytes;
  final String mimeType;
  final String fileExtension;
}
