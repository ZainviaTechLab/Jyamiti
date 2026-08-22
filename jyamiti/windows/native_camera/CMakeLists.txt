# Native precise-sync capture DLL, used by MathPadRecordingService's
# "precise" camera sync method for BOTH the webcam and the microphone
# (despite the `jyamiti_camera` target/file name -- kept as-is to avoid
# reshuffling an already-wired CMake target + Dart DynamicLibrary.open()
# path for a rename). See camera_capture.cpp / audio_capture.cpp for why
# each exists as a standalone native module rather than an ffmpeg flag.
add_library(jyamiti_camera SHARED
  "camera_capture.cpp"
  "audio_capture.cpp"
)

apply_standard_settings(jyamiti_camera)

set_target_properties(jyamiti_camera PROPERTIES
  CXX_VISIBILITY_PRESET hidden
)

target_link_libraries(jyamiti_camera PRIVATE
  mfplat.lib
  mfreadwrite.lib
  mfuuid.lib
  mf.lib
  ole32.lib
)
