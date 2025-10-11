import 'dart:io';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final fileIngestServiceProvider = Provider<FileIngestService>((ref) {
  return FileIngestService();
});

class FileIngestService {
  Future<String?> pickAndRead() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['txt', 'md', 'json', 'csv', 'pdf'],
      withData: false,
    );
    if (result == null || result.files.isEmpty) {
      return null;
    }
    final file = result.files.first;
    final path = file.path;
    if (path == null) {
      return null;
    }
    final extension = path.split('.').last.toLowerCase();
    if (extension == 'pdf') {
      return 'Вложение PDF получено. Пожалуйста, сформулируйте вопрос по документу.';
    }
    final bytes = await File(path).readAsBytes();
    return utf8.decode(bytes, allowMalformed: true);
  }
}
