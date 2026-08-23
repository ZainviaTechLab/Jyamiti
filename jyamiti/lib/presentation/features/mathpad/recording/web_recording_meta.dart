/// One saved web recording's metadata, WITHOUT its video bytes -- kept
/// separate so listing recordings stays cheap regardless of how large
/// individual recordings get (see web_recordings_storage_service_web.dart's
/// doc comment for the actual storage split). Platform-agnostic (pure
/// Dart, no package:web types) -- its own file, imported by the barrel and
/// both platform variants, so none of them need to import each other.
class WebRecordingMeta {
  const WebRecordingMeta({
    required this.id,
    required this.name,
    required this.mimeType,
    required this.sizeBytes,
    required this.createdAt,
  });

  final String id;
  final String name;
  final String mimeType;
  final int sizeBytes;
  final DateTime createdAt;
}
