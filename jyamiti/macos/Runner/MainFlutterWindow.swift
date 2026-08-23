import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  /// This app's own window, set once created below -- used by
  /// ExternalCompositor.swift (see its doc comment) to find its own window
  /// for ScreenCaptureKit without any PID-enumeration dance, since Cocoa
  /// hands the object to us directly. UNVERIFIED, same caveat as
  /// ExternalCompositor.swift itself -- see that file's header comment.
  static weak var sharedInstance: NSWindow?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    MainFlutterWindow.sharedInstance = self
    // Guarded: ExternalCompositorChannel itself requires macOS 12.3+
    // (ScreenCaptureKit) -- see ExternalCompositor.swift's header comment.
    // On an older macOS, this is simply never registered, and Dart's
    // MethodChannel call would fail with a "channel not found"-style
    // error -- acceptable degradation for a mode that isn't reachable
    // from the UI yet regardless (see that same header comment).
    if #available(macOS 12.3, *) {
      ExternalCompositorChannel.register(with: flutterViewController)
    }

    super.awakeFromNib()
  }
}

/// MethodChannel bridge to ExternalCompositor.swift (macOS's answer to
/// CameraEncodeMode.externalCompositor -- see that Swift file's header
/// comment for the full explanation and, importantly, its UNVERIFIED
/// status). One compositor instance at a time, matching how
/// MathPadRecordingService only ever runs one recording at a time on the
/// Dart side.
///
/// Channel name: "jyamiti.com/external_compositor". Methods:
///   - "start": { cameraDeviceName: String, outputPath: String, fps: Int,
///                cropX/cropY/cropW/cropH: Int } -> Bool
///   - "setCrop": { x/y/w/h: Int } -> nil
///   - "stop": {} -> Bool
///   - "lastError": {} -> String?
@available(macOS 12.3, *)
enum ExternalCompositorChannel {
  private static var compositor: ExternalCompositor?

  static func register(with controller: FlutterViewController) {
    let channel = FlutterMethodChannel(
      name: "jyamiti.com/external_compositor",
      binaryMessenger: controller.engine.binaryMessenger
    )
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "start":
        guard let args = call.arguments as? [String: Any],
              let outputPath = args["outputPath"] as? String,
              let fps = args["fps"] as? Int
        else {
          result(FlutterError(code: "bad_args", message: "Missing required arguments", details: nil))
          return
        }
        let cameraDeviceName = args["cameraDeviceName"] as? String ?? ""
        let cropX = args["cropX"] as? Int ?? 0
        let cropY = args["cropY"] as? Int ?? 0
        let cropW = args["cropW"] as? Int ?? 0
        let cropH = args["cropH"] as? Int ?? 0
        let newCompositor = ExternalCompositor()
        compositor = newCompositor
        newCompositor.start(
          cameraDeviceName: cameraDeviceName, outputPath: outputPath, fps: fps,
          cropX: cropX, cropY: cropY, cropW: cropW, cropH: cropH
        ) { ok in
          DispatchQueue.main.async { result(ok) }
        }
      case "setCrop":
        guard let args = call.arguments as? [String: Any] else {
          result(FlutterError(code: "bad_args", message: "Missing required arguments", details: nil))
          return
        }
        let x = args["x"] as? Int ?? 0
        let y = args["y"] as? Int ?? 0
        let w = args["w"] as? Int ?? 0
        let h = args["h"] as? Int ?? 0
        compositor?.setCrop(x: x, y: y, w: w, h: h)
        result(nil)
      case "stop":
        guard let active = compositor else {
          result(false)
          return
        }
        active.stop { ok in
          DispatchQueue.main.async { result(ok) }
        }
      case "lastError":
        result(compositor?.lastError)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}
