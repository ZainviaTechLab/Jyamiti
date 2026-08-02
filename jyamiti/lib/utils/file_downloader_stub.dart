import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';

Future<bool> saveAndDownloadFile({
  required String fileName,
  required String content,
  List<int>? bytes,
}) async {
  try {
    final fileBytes = bytes ?? utf8.encode(content);
    final Uint8List uint8bytes = Uint8List.fromList(fileBytes);

    String? outputFile = await FilePicker.saveFile(
      dialogTitle: 'Save $fileName',
      fileName: fileName,
      bytes: uint8bytes,
    );

    if (outputFile != null) {
      final file = File(outputFile);
      await file.writeAsBytes(uint8bytes);
      return true;
    }
    return false;
  } catch (e) {
    return false;
  }
}
