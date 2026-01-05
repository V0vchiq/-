import 'dart:io';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final fileIngestServiceProvider = Provider<FileIngestService>((ref) {
  return FileIngestService();
});

class PickedFile {
  final String name;
  final String path;
  final String? content;
  final bool isSupported;
  
  const PickedFile({
    required this.name,
    required this.path,
    this.content,
    this.isSupported = true,
  });
}

class FileIngestService {
  static const _textExtensions = ['txt', 'md', 'json', 'csv', 'xml', 'html', 'css', 'js', 'dart', 'py', 'java', 'kt', 'swift', 'c', 'cpp', 'h', 'yml', 'yaml', 'toml', 'ini', 'conf', 'log'];
  
  Future<PickedFile?> pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
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
    final isText = _textExtensions.contains(extension);
    
    if (!isText) {
      return PickedFile(
        name: file.name,
        path: path,
        content: null,
        isSupported: false,
      );
    }
    
    try {
      final bytes = await File(path).readAsBytes();
      final content = utf8.decode(bytes, allowMalformed: true);
      return PickedFile(
        name: file.name,
        path: path,
        content: content,
        isSupported: true,
      );
    } catch (e) {
      return PickedFile(
        name: file.name,
        path: path,
        content: null,
        isSupported: false,
      );
    }
  }
}
