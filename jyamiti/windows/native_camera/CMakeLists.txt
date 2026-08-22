# Native Media Foundation webcam capture+encode DLL, used by
# MathPadRecordingService's "precise" camera sync method. See
# camera_capture.cpp for why this exists as a standalone native module
# rather than an ffmpeg flag.
add_library(jyamiti_camera SHARED
  "camera_capture.cpp"
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
