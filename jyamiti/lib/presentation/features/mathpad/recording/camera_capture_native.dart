// Conditional-import barrel -- picks the real dart:ffi/win32-based native
// bridge (camera_capture_native_io.dart) on every platform where dart:io
// (and therefore dart:ffi) is available, and a web-safe stub
// (camera_capture_native_web.dart) on web, where neither exists. See
// camera_capture_native_io.dart's doc comment for why this split exists at
// all -- the short version: `Only JS interop members may be 'external'` is
// a hard dart2js/dart2wasm restriction that package:ffi's own internals
// hit, independent of whether any of this code ever actually runs on web.
export 'camera_capture_native_web.dart'
    if (dart.library.io) 'camera_capture_native_io.dart';
