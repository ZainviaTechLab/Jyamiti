#include "live_ink_overlay.h"

#include <windowsx.h>

#include <algorithm>
#include <cmath>

namespace {

constexpr wchar_t kWindowClassName[] = L"JyamitiLiveInkOverlay";

// Registers the overlay window class exactly once for the process's
// lifetime -- CreateWindowExW is called once per LiveInkOverlay instance
// (there's only ever one, owned by FlutterWindow), but guarding this
// defensively costs nothing.
void EnsureClassRegistered(HINSTANCE instance) {
  static bool registered = false;
  if (registered) return;
  WNDCLASSEXW wc = {};
  wc.cbSize = sizeof(WNDCLASSEXW);
  wc.lpfnWndProc = LiveInkOverlay::WndProc;
  wc.hInstance = instance;
  wc.lpszClassName = kWindowClassName;
  wc.hCursor = LoadCursorW(nullptr, IDC_ARROW);
  RegisterClassExW(&wc);
  registered = true;
}

}  // namespace

LiveInkOverlay::LiveInkOverlay(HWND owner) : owner_(owner) {
  D2D1CreateFactory(D2D1_FACTORY_TYPE_SINGLE_THREADED, d2d_factory_.GetAddressOf());
}

LiveInkOverlay::~LiveInkOverlay() {
  CancelStroke();
  ReleaseBackBuffer();
  if (hwnd_) {
    DestroyWindow(hwnd_);
    hwnd_ = nullptr;
  }
}

void LiveInkOverlay::SetCompletionCallback(CompletionCallback callback) {
  completion_callback_ = std::move(callback);
}

void LiveInkOverlay::EnsureWindow() {
  if (hwnd_ || !owner_) return;
  HINSTANCE instance =
      reinterpret_cast<HINSTANCE>(GetWindowLongPtr(owner_, GWLP_HINSTANCE));
  EnsureClassRegistered(instance);
  // WS_POPUP + an owner (not a true WS_CHILD parent) keeps this window
  // ABOVE the owner in z-order and hidden/restored/minimized together with
  // it, without being clipped to the owner's client area the way a real
  // child window would be, and without needing HWND_TOPMOST (which would
  // float it above every other app's windows too, not just this one).
  // WS_EX_TRANSPARENT starts ON (click-through) -- ArmStroke removes it
  // only for the duration of an actual captured stroke.
  hwnd_ = CreateWindowExW(
      WS_EX_LAYERED | WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE | WS_EX_TRANSPARENT,
      kWindowClassName, L"", WS_POPUP, 0, 0, 1, 1, owner_, nullptr, instance,
      this);
}

// static
LRESULT CALLBACK LiveInkOverlay::WndProc(HWND hwnd, UINT message,
                                         WPARAM wparam, LPARAM lparam) {
  LiveInkOverlay* self = nullptr;
  if (message == WM_NCCREATE) {
    auto* cs = reinterpret_cast<CREATESTRUCTW*>(lparam);
    self = reinterpret_cast<LiveInkOverlay*>(cs->lpCreateParams);
    SetWindowLongPtr(hwnd, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(self));
  } else {
    self = reinterpret_cast<LiveInkOverlay*>(
        GetWindowLongPtr(hwnd, GWLP_USERDATA));
  }
  if (self) {
    return self->HandleMessage(message, wparam, lparam);
  }
  return DefWindowProc(hwnd, message, wparam, lparam);
}

LRESULT LiveInkOverlay::HandleMessage(UINT message, WPARAM wparam,
                                      LPARAM lparam) {
  switch (message) {
    case WM_POINTERUPDATE: {
      if (armed_) {
        UINT32 pointerId = GET_POINTERID_WPARAM(wparam);
        if (active_pointer_id_ == 0) active_pointer_id_ = pointerId;
        if (pointerId == active_pointer_id_) {
          AppendHistoricalPenSamples(wparam);
          Present();
        }
      }
      return 0;
    }
    case WM_POINTERUP: {
      if (armed_) {
        UINT32 pointerId = GET_POINTERID_WPARAM(wparam);
        if (active_pointer_id_ == 0 || pointerId == active_pointer_id_) {
          AppendHistoricalPenSamples(wparam);
          FinishStroke(/*invokeCallback=*/true);
        }
      }
      return 0;
    }
    case WM_POINTERCAPTURECHANGED: {
      // Capture was taken away from us unexpectedly (another window/app
      // grabbed it, or a system gesture interrupted). Commit whatever was
      // captured so far rather than silently losing the user's stroke.
      FinishStroke(/*invokeCallback=*/true);
      return 0;
    }
    default:
      return DefWindowProc(hwnd_, message, wparam, lparam);
  }
}

void LiveInkOverlay::UpdateTransform(double clientLeft, double clientTop,
                                     double width, double height) {
  EnsureWindow();
  if (!hwnd_ || !owner_) return;

  UINT dpi = GetDpiForWindow(owner_);
  double scale = dpi > 0 ? dpi / 96.0 : 1.0;
  dpi_scale_ = scale;

  POINT origin = {0, 0};
  ClientToScreen(owner_, &origin);
  window_screen_left_px_ = origin.x + clientLeft * scale;
  window_screen_top_px_ = origin.y + clientTop * scale;

  int wPx = std::max(1, static_cast<int>(std::round(width * scale)));
  int hPx = std::max(1, static_cast<int>(std::round(height * scale)));

  SetWindowPos(hwnd_, nullptr, static_cast<int>(std::round(window_screen_left_px_)),
              static_cast<int>(std::round(window_screen_top_px_)), wPx, hPx,
              SWP_NOZORDER | SWP_NOACTIVATE | (armed_ ? 0 : SWP_HIDEWINDOW));
}

void LiveInkOverlay::EnsureBackBuffer(int pixelWidth, int pixelHeight) {
  if (pixelWidth == back_buffer_w_ && pixelHeight == back_buffer_h_ &&
      back_dc_) {
    return;
  }
  ReleaseBackBuffer();
  back_buffer_w_ = pixelWidth;
  back_buffer_h_ = pixelHeight;
  if (pixelWidth <= 0 || pixelHeight <= 0) return;

  HDC screenDc = GetDC(nullptr);
  back_dc_ = CreateCompatibleDC(screenDc);

  BITMAPINFO bmi = {};
  bmi.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
  bmi.bmiHeader.biWidth = pixelWidth;
  bmi.bmiHeader.biHeight = -pixelHeight;  // top-down
  bmi.bmiHeader.biPlanes = 1;
  bmi.bmiHeader.biBitCount = 32;
  bmi.bmiHeader.biCompression = BI_RGB;

  void* bits = nullptr;
  back_bitmap_ = CreateDIBSection(back_dc_, &bmi, DIB_RGB_COLORS, &bits,
                                  nullptr, 0);
  back_bitmap_old_ =
      static_cast<HBITMAP>(SelectObject(back_dc_, back_bitmap_));
  ReleaseDC(nullptr, screenDc);

  D2D1_RENDER_TARGET_PROPERTIES props = D2D1::RenderTargetProperties(
      D2D1_RENDER_TARGET_TYPE_DEFAULT,
      D2D1::PixelFormat(DXGI_FORMAT_B8G8R8A8_UNORM,
                        D2D1_ALPHA_MODE_PREMULTIPLIED));
  render_target_.Reset();
  d2d_factory_->CreateDCRenderTarget(&props, render_target_.GetAddressOf());
  if (render_target_) {
    float dpi = static_cast<float>(96.0 * dpi_scale_);
    render_target_->SetDpi(dpi, dpi);
  }
}

void LiveInkOverlay::ReleaseBackBuffer() {
  render_target_.Reset();
  if (back_dc_) {
    if (back_bitmap_old_) SelectObject(back_dc_, back_bitmap_old_);
    DeleteDC(back_dc_);
    back_dc_ = nullptr;
  }
  if (back_bitmap_) {
    DeleteObject(back_bitmap_);
    back_bitmap_ = nullptr;
  }
  back_bitmap_old_ = nullptr;
  back_buffer_w_ = 0;
  back_buffer_h_ = 0;
}

void LiveInkOverlay::ClearBackBuffer() {
  if (!render_target_ || !back_dc_) return;
  RECT bindRect = {0, 0, back_buffer_w_, back_buffer_h_};
  render_target_->BindDC(back_dc_, &bindRect);
  render_target_->BeginDraw();
  render_target_->Clear(D2D1::ColorF(0, 0, 0, 0.0f));
  render_target_->EndDraw();
}

void LiveInkOverlay::DrawSegment(double x0, double y0, double x1, double y1) {
  if (!render_target_ || !back_dc_) return;
  RECT bindRect = {0, 0, back_buffer_w_, back_buffer_h_};
  render_target_->BindDC(back_dc_, &bindRect);
  render_target_->BeginDraw();

  Microsoft::WRL::ComPtr<ID2D1SolidColorBrush> brush;
  render_target_->CreateSolidColorBrush(stroke_color_, brush.GetAddressOf());
  if (brush) {
    Microsoft::WRL::ComPtr<ID2D1StrokeStyle> strokeStyle;
    D2D1_STROKE_STYLE_PROPERTIES styleProps = D2D1::StrokeStyleProperties(
        D2D1_CAP_STYLE_ROUND, D2D1_CAP_STYLE_ROUND, D2D1_CAP_STYLE_ROUND,
        D2D1_LINE_JOIN_ROUND);
    d2d_factory_->CreateStrokeStyle(styleProps, nullptr, 0,
                                    strokeStyle.GetAddressOf());
    render_target_->DrawLine(D2D1::Point2F(static_cast<float>(x0), static_cast<float>(y0)),
                             D2D1::Point2F(static_cast<float>(x1), static_cast<float>(y1)),
                             brush.Get(), stroke_width_, strokeStyle.Get());
  }
  render_target_->EndDraw();
}

void LiveInkOverlay::Present() {
  if (!back_dc_ || !hwnd_) return;
  SIZE size = {back_buffer_w_, back_buffer_h_};
  POINT srcPos = {0, 0};
  BLENDFUNCTION blend = {AC_SRC_OVER, 0, 255, AC_SRC_ALPHA};
  HDC screenDc = GetDC(nullptr);
  UpdateLayeredWindow(hwnd_, screenDc, nullptr, &size, back_dc_, &srcPos, 0,
                      &blend, ULW_ALPHA);
  ReleaseDC(nullptr, screenDc);
}

void LiveInkOverlay::AppendHistoricalPenSamples(WPARAM wparam) {
  UINT32 pointerId = GET_POINTERID_WPARAM(wparam);

  POINTER_INPUT_TYPE type = PT_POINTER;
  GetPointerType(pointerId, &type);

  UINT32 count = 0;
  if (type == PT_PEN) {
    GetPointerPenInfoHistory(pointerId, &count, nullptr);
    if (count == 0) return;
    count = std::min<UINT32>(count, 64);
    std::vector<POINTER_PEN_INFO> history(count);
    if (!GetPointerPenInfoHistory(pointerId, &count, history.data())) return;
    // History is most-recent-first -- replay oldest-to-newest so the
    // drawn trail (and the buffered points handed back to Dart) come out
    // in the correct temporal order.
    for (UINT32 i = count; i-- > 0;) {
      const POINTER_PEN_INFO& info = history[i];
      double x =
          (info.pointerInfo.ptPixelLocation.x - window_screen_left_px_) /
          dpi_scale_;
      double y =
          (info.pointerInfo.ptPixelLocation.y - window_screen_top_px_) /
          dpi_scale_;
      float pressure =
          (info.penMask & PEN_MASK_PRESSURE)
              ? std::clamp(info.pressure / 1024.0f, 0.0f, 1.0f)
              : 0.5f;
      DrawSegment(last_x_, last_y_, x, y);
      last_x_ = x;
      last_y_ = y;
      points_.push_back(x);
      points_.push_back(y);
      points_.push_back(pressure);
    }
  } else {
    GetPointerInfoHistory(pointerId, &count, nullptr);
    if (count == 0) return;
    count = std::min<UINT32>(count, 64);
    std::vector<POINTER_INFO> history(count);
    if (!GetPointerInfoHistory(pointerId, &count, history.data())) return;
    for (UINT32 i = count; i-- > 0;) {
      const POINTER_INFO& info = history[i];
      double x = (info.ptPixelLocation.x - window_screen_left_px_) / dpi_scale_;
      double y = (info.ptPixelLocation.y - window_screen_top_px_) / dpi_scale_;
      DrawSegment(last_x_, last_y_, x, y);
      last_x_ = x;
      last_y_ = y;
      points_.push_back(x);
      points_.push_back(y);
      points_.push_back(0.5);
    }
  }
}

bool LiveInkOverlay::ArmStroke(double startX, double startY,
                               double startPressure, uint32_t argbColor,
                               double strokeWidthPx) {
  EnsureWindow();
  if (!hwnd_) return false;
  if (armed_) FinishStroke(/*invokeCallback=*/true);

  RECT wr;
  if (!GetWindowRect(hwnd_, &wr)) return false;
  EnsureBackBuffer(wr.right - wr.left, wr.bottom - wr.top);
  if (back_buffer_w_ <= 0 || back_buffer_h_ <= 0) return false;

  stroke_color_ = D2D1::ColorF(
      static_cast<float>((argbColor >> 16) & 0xFF) / 255.0f,
      static_cast<float>((argbColor >> 8) & 0xFF) / 255.0f,
      static_cast<float>(argbColor & 0xFF) / 255.0f,
      static_cast<float>((argbColor >> 24) & 0xFF) / 255.0f);
  stroke_width_ = static_cast<float>(strokeWidthPx);

  points_.clear();
  points_.push_back(startX);
  points_.push_back(startY);
  points_.push_back(startPressure);
  last_x_ = startX;
  last_y_ = startY;
  active_pointer_id_ = 0;  // learned from the first WM_POINTERUPDATE/UP

  ClearBackBuffer();
  DrawSegment(startX, startY, startX, startY);  // initial dot
  Present();

  ShowWindow(hwnd_, SW_SHOWNOACTIVATE);
  LONG_PTR ex = GetWindowLongPtr(hwnd_, GWL_EXSTYLE);
  SetWindowLongPtr(hwnd_, GWL_EXSTYLE, ex & ~WS_EX_TRANSPARENT);
  SetCapture(hwnd_);

  armed_ = true;
  return true;
}

void LiveInkOverlay::CancelStroke() { FinishStroke(/*invokeCallback=*/false); }

void LiveInkOverlay::FinishStroke(bool invokeCallback) {
  if (!armed_) return;
  armed_ = false;
  active_pointer_id_ = 0;
  ReleaseCapture();
  if (hwnd_) {
    ShowWindow(hwnd_, SW_HIDE);
    LONG_PTR ex = GetWindowLongPtr(hwnd_, GWL_EXSTYLE);
    SetWindowLongPtr(hwnd_, GWL_EXSTYLE, ex | WS_EX_TRANSPARENT);
  }
  std::vector<double> finished = std::move(points_);
  points_.clear();
  if (invokeCallback && completion_callback_ && finished.size() >= 6) {
    completion_callback_(finished);
  }
}
