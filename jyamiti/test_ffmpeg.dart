import 'dart:io';

void main() async {
  final process = await Process.start(
    r'build\windows\x64\runner\Debug\ffmpeg.exe',
    [
      '-y',
      '-f', 'dshow',
      '-i', 'video=HP Wide Vision HD Camera',
      '-c:v', 'libx264',
      '-preset', 'veryfast',
      '-pix_fmt', 'yuv420p',
      'test_camera2.mp4',
    ],
  );

  process.stdout.listen((event) => stdout.add(event));
  process.stderr.listen((event) => stderr.add(event));

  print('Started, waiting 3s');
  await Future.delayed(const Duration(seconds: 3));

  print('Sending q');
  process.stdin.write('q');
  await process.stdin.flush();

  try {
    await process.exitCode.timeout(const Duration(seconds: 3));
    print('Exited cleanly');
  } catch (_) {
    print('Timeout, killing');
    process.kill();
  }

  print('File exists: ${await File('test_camera2.mp4').exists()}');
}
