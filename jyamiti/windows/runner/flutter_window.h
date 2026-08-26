#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>

#include <memory>

#include "live_ink_overlay.h"
#include "win32_window.h"

// A window that does nothing but host a Flutter view.
class FlutterWindow : public Win32Window {
 public:
  // Creates a new FlutterWindow hosting a Flutter view running |project|.
  explicit FlutterWindow(const flutter::DartProject& project);
  virtual ~FlutterWindow();

 protected:
  // Win32Window:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  // The project to run.
  flutter::DartProject project_;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;

  // The custom MethodChannel for window theme syncing.
  std::unique_ptr<flutter::MethodChannel<>> window_channel_;

  // Native low-latency overlay for the currently-being-drawn Pen stroke on
  // MathPad's canvas (see live_ink_overlay.h) and its own MethodChannel,
  // separate from window_channel_ above -- unrelated concerns.
  std::unique_ptr<LiveInkOverlay> live_ink_overlay_;
  std::unique_ptr<flutter::MethodChannel<>> live_ink_channel_;
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
