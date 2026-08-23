// Conditional-import barrel -- picks the real dart:io/path_provider-based
// implementation (mathpad_library_storage_service_io.dart) on every
// platform where dart:io is available, and the IndexedDB-backed
// implementation (mathpad_library_storage_service_web.dart) on web, where
// it isn't. Same public API (MathPadLibraryStorageService,
// MathPadLastWorked) either way -- callers never branch on platform
// themselves. See mathpad_library_storage_service_io.dart's doc comment
// for the on-disk layout, and _web.dart's for the IndexedDB schema and its
// web-specific risks (eviction, no cross-device portability).
export 'mathpad_library_storage_service_web.dart'
    if (dart.library.io) 'mathpad_library_storage_service_io.dart';
