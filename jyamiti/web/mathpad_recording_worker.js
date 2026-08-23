// Off-main-thread compositor for MathPadWebRecordingService's Insertable-
// Streams path -- see mathpad_web_recording_service_web.dart's header
// comment ("OFF-THREAD PATH") for the full picture. Plain JavaScript, not
// Dart -- Flutter's web build only compiles lib/main.dart; anything under
// web/ is just copied as a static asset with ZERO compile-time checking.
// This means this file has had LESS verification than anything else in
// this app, including the native C++ modules (those at least got manual
// review against documented APIs I'm confident about; this is the same
// tier of confidence but with no compiler catching typos/syntax errors
// either). Treat it as unverified in the fullest sense.
//
// Protocol (all messages are plain objects via postMessage):
//   -> {type: 'start', screenStream: ReadableStream<VideoFrame>,
//       cameraStream: ReadableStream<VideoFrame> | null,
//       outputWidth, outputHeight,
//       cropRect: {x, y, w, h} | null}
//   -> {type: 'stop'}
//   <- {type: 'frame', bitmap: ImageBitmap}   (transferred, one per composited frame)
//   <- {type: 'error', message: string}
//
// Compositing matches the exact same PIP spec every other camera-overlay
// path in this app uses (crop=ih:ih, scale to 240x240, white border,
// top-right 24px inset) -- see drawFrame() below.

let screenReader = null;
let cameraReader = null;
let cropRect = null;
let outputWidth = 0;
let outputHeight = 0;
let running = false;
let latestCameraFrame = null;
let canvas = null;
let ctx = null;

self.onmessage = function (e) {
  const msg = e.data;
  if (msg.type === 'start') {
    try {
      screenReader = msg.screenStream.getReader();
      cameraReader = msg.cameraStream ? msg.cameraStream.getReader() : null;
      cropRect = msg.cropRect || null;
      outputWidth = msg.outputWidth;
      outputHeight = msg.outputHeight;
      canvas = new OffscreenCanvas(outputWidth, outputHeight);
      ctx = canvas.getContext('2d');
      running = true;
      if (cameraReader) pumpCamera();
      runScreenLoop();
    } catch (err) {
      self.postMessage({ type: 'error', message: String(err) });
    }
  } else if (msg.type === 'stop') {
    running = false;
    try { if (screenReader) screenReader.cancel(); } catch (err) {}
    try { if (cameraReader) cameraReader.cancel(); } catch (err) {}
    if (latestCameraFrame) {
      try { latestCameraFrame.close(); } catch (err) {}
      latestCameraFrame = null;
    }
  }
};

// Runs independently of the screen loop -- the composited output should
// always use whatever the MOST RECENT camera frame is, not block waiting
// for one on every single screen frame (camera and screen tracks don't
// necessarily deliver frames at the same rate).
async function pumpCamera() {
  while (running) {
    let result;
    try {
      result = await cameraReader.read();
    } catch (err) {
      break;
    }
    if (result.done) break;
    if (latestCameraFrame) {
      try { latestCameraFrame.close(); } catch (err) {}
    }
    latestCameraFrame = result.value;
  }
}

async function runScreenLoop() {
  while (running) {
    let result;
    try {
      result = await screenReader.read();
    } catch (err) {
      self.postMessage({ type: 'error', message: String(err) });
      break;
    }
    if (result.done) break;
    const screenFrame = result.value;
    try {
      drawFrame(screenFrame);
    } finally {
      screenFrame.close();
    }

    let bitmap;
    try {
      bitmap = canvas.transferToImageBitmap();
    } catch (err) {
      self.postMessage({ type: 'error', message: String(err) });
      break;
    }
    self.postMessage({ type: 'frame', bitmap: bitmap }, [bitmap]);
  }
}

function drawFrame(screenFrame) {
  if (cropRect) {
    ctx.drawImage(
      screenFrame,
      cropRect.x, cropRect.y, cropRect.w, cropRect.h,
      0, 0, outputWidth, outputHeight
    );
  } else {
    ctx.drawImage(screenFrame, 0, 0, outputWidth, outputHeight);
  }

  if (latestCameraFrame) {
    const camW = latestCameraFrame.displayWidth || latestCameraFrame.codedWidth;
    const camH = latestCameraFrame.displayHeight || latestCameraFrame.codedHeight;
    if (camW > 0 && camH > 0) {
      const cropSize = Math.min(camW, camH);
      const camCropX = (camW - cropSize) / 2;
      const boxSize = 240, inset = 24;
      const destX = outputWidth - inset - boxSize;
      const destY = inset;
      ctx.drawImage(
        latestCameraFrame,
        camCropX, 0, cropSize, cropSize,
        destX, destY, boxSize, boxSize
      );
      ctx.strokeStyle = 'rgba(255, 255, 255, 0.9)';
      ctx.lineWidth = 4;
      ctx.strokeRect(destX, destY, boxSize, boxSize);
    }
  }
}
