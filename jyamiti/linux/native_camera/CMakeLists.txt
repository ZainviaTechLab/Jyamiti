# Native external-compositor library for CameraEncodeMode.externalCompositor
# on Linux -- see external_compositor.cc's header comment (UNVERIFIED, no
# Linux machine was available to build or run this). X11/XComposite window
# capture + best-effort V4L2 camera + a piped ffmpeg process, same C ABI as
# the Windows module (windows/native_camera/external_compositor.cpp) so
# camera_capture_native.dart's existing FFI bindings are reused almost
# unchanged.
add_library(jyamiti_camera SHARED
  "external_compositor.cc"
)

apply_standard_settings(jyamiti_camera)

find_package(PkgConfig REQUIRED)
pkg_check_modules(X11 REQUIRED IMPORTED_TARGET x11)
pkg_check_modules(XCOMPOSITE REQUIRED IMPORTED_TARGET xcomposite)

# Deliberately NOT setting CXX_VISIBILITY_PRESET hidden the way the Windows
# target does -- that would hide the extern "C" jyamiti_compositor_* entry
# points from dart:ffi's DynamicLibrary.open()/lookupFunction() (Windows
# avoids the equivalent problem via explicit __declspec(dllexport) on each
# one; this file doesn't use the matching
# __attribute__((visibility("default"))), so leaving the whole library at
# its default -- everything exported -- is the safer choice here).

target_link_libraries(jyamiti_camera PRIVATE
  PkgConfig::X11
  PkgConfig::XCOMPOSITE
)
