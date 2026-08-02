import 'file_downloader_stub.dart'
    if (dart.library.html) 'file_downloader_web.dart';

class FileDownloader {
  static Future<bool> downloadFile({
    required String fileName,
    required String content,
    List<int>? bytes,
  }) {
    return saveAndDownloadFile(
      fileName: fileName,
      content: content,
      bytes: bytes,
    );
  }
}
