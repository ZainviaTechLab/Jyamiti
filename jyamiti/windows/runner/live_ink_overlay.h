#ifndef RUNNER_LIVE_INK_OVERLAY_H_
#define RUNNER_LIVE_INK_OVERLAY_H_

#include <windows.h>
#include <d2d1.h>
#include <wrl/client.h>

#include <functional>
#include <vector>

// Native, low-latency overlay for the CURRENTLY-being-drawn Pen stroke on
// MathPad's canvas -- the "big company" (OneNote/PencilKit-style) answer to
// Flutter's own draw pipeline never being quite as immediate as a native
// app's for high-frequency pointer input, no matter how cheap the Dart-side
// work is made (see the two `_kLiveBakeEvery`/`shouldRepaint` fixes that
// preceded this): Flutter still batches input -> build -> layout -> paint ->
// raster -> present through its own vsync-locked engine pipeline, adding up
// to roughly a frame of latency a true zero-copy native draw doesn't pay.
//
// This is a plain, borderless, layered Win32 popup window, OWNED by (not a
// child of) the Flutter window, always kept exactly positioned over the
// canvas and click-through (`WS_EX_TRANSPARENT`) while idle -- Flutter's own
// gesture handling is completely unaffected in that state. The moment Dart's
// OWN pointer-down handler decides "this is a plain freehand Pen stroke
// starting" (every other tool/mode is untouched -- see `ArmStroke`'s doc
// comment), it calls `ArmStroke`, which steals Win32 pointer capture for
// that already-in-progress gesture and starts drawing directly from raw
// `WM_POINTER*` messages with Direct2D, entirely outside Flutter's engine.
// When the pen lifts, the full captured point list is handed back to Dart
// (via a `FlutterWindow`-owned `MethodChannel`, not this class directly),
// which commits it through MathPad's EXISTING stroke-commit path exactly as
// if it had been drawn the normal way -- undo history, chunking/baking,
// persistence are all completely unmodified by this.
//
// Compile/link-verified and smoke-tested for "app launches, overlay window
// creates without crashing" in this environment (windows/CI has an actual
// Windows build+run pipeline, unlike macOS/Linux) -- but drawing WITH a real
// pen/touchscreen has NOT been hands-on verified here (no stylus hardware in
// this environment). Report anything that looks visually wrong (offset
// trail, wrong color/width, trail not clearing, window stuck visible) and
// it can be iterated on directly.
class LiveInkOverlay {
 public:
  // Invoked once a stroke finishes (pen lifted, or capture lost
  // unexpectedly -- see `WM_POINTERCAPTURECHANGED` handling) with the
  // captured points flattened as [x0, y0, pressure0, x1, y1, pressure1,
  // ...], in the SAME canvas-local, logical-pixel coordinate space
  // `UpdateTransform`'s rect and `ArmStroke`'s start point use. Always
  // invoked on the same thread that pumps this window's messages (the
  // app's single UI thread, same as Flutter's own platform thread), so
  // it's safe to forward straight into a `MethodChannel::InvokeMethod`
  // call without any extra thread-hopping.
  using CompletionCallback = std::function<void(const std::vector<double>&)>;

  explicit LiveInkOverlay(HWND owner);
  ~LiveInkOverlay();

  // Not copyable/movable -- owns a real HWND and GPU/GDI resources.
  LiveInkOverlay(const LiveInkOverlay&) = delete;
  LiveInkOverlay& operator=(const LiveInkOverlay&) = delete;

  void SetCompletionCallback(CompletionCallback callback);

  // Repositions/resizes the (while idle, hidden and click-through) overlay
  // to exactly cover the canvas. `clientLeft/clientTop/width/height` are
  // LOGICAL pixels relative to the owner window's CLIENT AREA -- the same
  // coordinate space Flutter's own `localPosition`/`_screenToWorld` already
  // use, and the same one `MathPadRecordingService._measureCanvasCropRect`
  // computes for the (separate, output-only) external compositor's crop
  // rect. Converts to an absolute physical-pixel screen rect internally via
  // `ClientToScreen` + the owner's current per-monitor DPI, the same
  // correction `external_compositor.cpp`'s crop-to-canvas fix already
  // established for this exact class of problem. Safe to call at any time,
  // including while idle, while armed, or before the overlay window has
  // been created yet (lazily created on first call).
  void UpdateTransform(double clientLeft, double clientTop, double width,
                       double height);

  // Arms the overlay for a new stroke and steals Win32 pointer capture for
  // the gesture ALREADY in progress -- Flutter's own window received the
  // real `WM_POINTERDOWN` and its Dart-side handler decided this is a
  // plain, unmodified, single-pointer Pen freehand stroke (never Pencil,
  // Eraser, shapes, selection, pan, or a stylus-hold-to-snap candidate --
  // ALL of those stay 100% on the existing Flutter-side path, untouched;
  // see `mathpad.dart`'s call site for the exact gating). `startX/startY`
  // are in the same canvas-local logical-pixel space `UpdateTransform`
  // uses -- the down-point Flutter's own handler already computed, since
  // this class never sees the actual down-event itself. `argbColor` is
  // 0xAARRGGBB. Returns false (and leaves the overlay untouched, still
  // click-through) if arming fails for any reason -- e.g. the overlay
  // window doesn't exist yet because `UpdateTransform` was never called,
  // or `SetCapture` didn't take. Callers MUST fall back to normal
  // Flutter-side drawing for this stroke whenever this returns false.
  bool ArmStroke(double startX, double startY, double startPressure,
                uint32_t argbColor, double strokeWidthPx);

  // Cancels an in-progress armed stroke WITHOUT invoking the completion
  // callback -- e.g. the page/widget is being torn down mid-stroke. A
  // no-op if not currently armed.
  void CancelStroke();

  bool IsArmed() const { return armed_; }

  // Public only so the free function that registers the window class
  // (live_ink_overlay.cpp's anonymous-namespace `EnsureClassRegistered`)
  // can pass it to `WNDCLASSEXW::lpfnWndProc` -- not meant to be called
  // directly by anything else.
  static LRESULT CALLBACK WndProc(HWND hwnd, UINT message, WPARAM wparam,
                                  LPARAM lparam);

 private:
  LRESULT HandleMessage(UINT message, WPARAM wparam, LPARAM lparam);

  void EnsureWindow();
  void EnsureBackBuffer(int pixelWidth, int pixelHeight);
  void ReleaseBackBuffer();
  void ClearBackBuffer();
  void DrawSegment(double x0, double y0, double x1, double y1);
  void Present();
  void AppendHistoricalPenSamples(WPARAM wparam);
  void FinishStroke(bool invokeCallback);

  HWND owner_ = nullptr;
  HWND hwnd_ = nullptr;
  CompletionCallback completion_callback_;

  Microsoft::WRL::ComPtr<ID2D1Factory> d2d_factory_;
  Microsoft::WRL::ComPtr<ID2D1DCRenderTarget> render_target_;
  HDC back_dc_ = nullptr;
  HBITMAP back_bitmap_ = nullptr;
  HBITMAP back_bitmap_old_ = nullptr;
  int back_buffer_w_ = 0;
  int back_buffer_h_ = 0;

  bool armed_ = false;
  UINT32 active_pointer_id_ = 0;
  std::vector<double> points_;  // flattened x, y, pressure (logical px)
  double last_x_ = 0, last_y_ = 0;

  // Cached from the most recent `UpdateTransform`, used to convert raw
  // WM_POINTER physical screen coordinates back into the same
  // canvas-local logical-pixel space the rest of this class/Dart use.
  double window_screen_left_px_ = 0;
  double window_screen_top_px_ = 0;
  double dpi_scale_ = 1.0;

  D2D1_COLOR_F stroke_color_ = D2D1::ColorF(0, 0, 0, 1.0f);
  float stroke_width_ = 4.0f;
};

#endif  // RUNNER_LIVE_INK_OVERLAY_H_
