#include "flutter_window.h"

#include <optional>
#include <flutter/standard_method_codec.h>

#include "flutter/generated_plugin_registrant.h"

namespace {

// EncodableValue's numeric variants can arrive as int32_t, int64_t, or
// double depending on what Dart's standard method codec picked for a given
// value -- this pulls a double out of whichever one actually landed.
double GetDoubleArg(const flutter::EncodableMap& args, const char* key,
                    double fallback = 0.0) {
  auto it = args.find(flutter::EncodableValue(key));
  if (it == args.end()) return fallback;
  if (const auto* d = std::get_if<double>(&it->second)) return *d;
  if (const auto* i32 = std::get_if<int32_t>(&it->second)) return *i32;
  if (const auto* i64 = std::get_if<int64_t>(&it->second)) return static_cast<double>(*i64);
  return fallback;
}

}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  window_channel_ = std::make_unique<flutter::MethodChannel<>>(
      flutter_controller_->engine()->messenger(),
      "com.jyamiti.app/window",
      &flutter::StandardMethodCodec::GetInstance());

  window_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<>& call,
             std::unique_ptr<flutter::MethodResult<>> result) {
        if (call.method_name() == "updateTheme") {
          const auto* arguments = std::get_if<flutter::EncodableMap>(call.arguments());
          if (arguments) {
            auto is_dark_it = arguments->find(flutter::EncodableValue("isDark"));
            if (is_dark_it != arguments->end()) {
              bool is_dark = std::get<bool>(is_dark_it->second);
              this->SetTitleBarTheme(is_dark);
            }
          }
          result->Success();
        } else {
          result->NotImplemented();
        }
      });

  // Native low-latency overlay for MathPad's currently-being-drawn Pen
  // stroke -- see live_ink_overlay.h for the full design. Owned here
  // (rather than by MathPad's own Dart code) because it needs this
  // window's real HWND; Dart only ever talks to it through
  // live_ink_channel_ below.
  live_ink_overlay_ = std::make_unique<LiveInkOverlay>(GetHandle());
  live_ink_channel_ = std::make_unique<flutter::MethodChannel<>>(
      flutter_controller_->engine()->messenger(), "jyamiti.com/live_ink_overlay",
      &flutter::StandardMethodCodec::GetInstance());

  // Forwards a finished stroke's captured points back into Dart -- see
  // LiveInkOverlay::CompletionCallback's doc comment for the flattened
  // [x, y, pressure, ...] shape and coordinate space.
  live_ink_overlay_->SetCompletionCallback(
      [this](const std::vector<double>& points) {
        flutter::EncodableList encoded;
        encoded.reserve(points.size());
        for (double v : points) encoded.push_back(flutter::EncodableValue(v));
        live_ink_channel_->InvokeMethod(
            "onStrokeComplete",
            std::make_unique<flutter::EncodableValue>(std::move(encoded)));
      });

  live_ink_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<>& call,
             std::unique_ptr<flutter::MethodResult<>> result) {
        const auto* arguments = std::get_if<flutter::EncodableMap>(call.arguments());
        if (call.method_name() == "updateTransform") {
          if (arguments && this->live_ink_overlay_) {
            this->live_ink_overlay_->UpdateTransform(
                GetDoubleArg(*arguments, "clientLeft"),
                GetDoubleArg(*arguments, "clientTop"),
                GetDoubleArg(*arguments, "width"),
                GetDoubleArg(*arguments, "height"));
          }
          result->Success();
        } else if (call.method_name() == "armStroke") {
          bool armed = false;
          if (arguments && this->live_ink_overlay_) {
            uint32_t argb = static_cast<uint32_t>(
                GetDoubleArg(*arguments, "argbColor"));
            armed = this->live_ink_overlay_->ArmStroke(
                GetDoubleArg(*arguments, "startX"),
                GetDoubleArg(*arguments, "startY"),
                GetDoubleArg(*arguments, "startPressure", 0.5), argb,
                GetDoubleArg(*arguments, "strokeWidthPx", 4.0));
          }
          result->Success(flutter::EncodableValue(armed));
        } else if (call.method_name() == "cancelStroke") {
          if (this->live_ink_overlay_) this->live_ink_overlay_->CancelStroke();
          result->Success();
        } else {
          result->NotImplemented();
        }
      });

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  live_ink_overlay_ = nullptr;
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
