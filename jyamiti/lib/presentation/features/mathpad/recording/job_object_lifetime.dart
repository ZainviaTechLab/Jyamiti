// Conditional-import barrel -- picks the real dart:ffi/win32-based
// implementation on every platform where dart:io (and therefore dart:ffi)
// is available (Windows, macOS, Linux, Android, iOS), and a no-op stub on
// web, where neither exists. See job_object_lifetime_io.dart's doc comment
// for why this split exists at all.
export 'job_object_lifetime_web.dart'
    if (dart.library.io) 'job_object_lifetime_io.dart';
