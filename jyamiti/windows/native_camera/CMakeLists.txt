# Native precise-sync capture DLL, used by MathPadRecordingService's
# "precise" camera sync method for BOTH the webcam and the microphone
# (despite the `jyamiti_camera` target/file name -- kept as-is to avoid
# reshuffling an already-wired CMake target + Dart DynamicLibrary.open()
# path for a rename), and also the "external compositor" native window+
# camera capture used by CameraEncodeMode.externalCompositor. See
# camera_capture.cpp / audio_capture.cpp / external_compositor.cpp for
# why each exists as a standalone native module rather than an ffmpeg
# flag or Flutter-side widget.
add_library(jyamiti_camera SHARED
  "camera_capture.cpp"
  "audio_capture.cpp"
  "external_compositor.cpp"
)

apply_standard_settings(jyamiti_camera)

# external_compositor.cpp uses C++/WinRT (Windows Graphics Capture),
# which needs real C++20 coroutine support -- raises the whole target's
# standard from apply_standard_settings' default of C++17 (a strict
# superset; camera_capture.cpp/audio_capture.cpp, which only use plain
# COM, build identically under it).
target_compile_features(jyamiti_camera PUBLIC cxx_std_20)

set_target_properties(jyamiti_camera PROPERTIES
  CXX_VISIBILITY_PRESET hidden
)

target_link_libraries(jyamiti_camera PRIVATE
  mfplat.lib
  mfreadwrite.lib
  mfuuid.lib
  mf.lib
  ole32.lib
  d3d11.lib
  d2d1.lib
  dxgi.lib
  windowsapp.lib
  avrt.lib
)
