import 'package:flutter/foundation.dart';
import 'dart:io' show File;

class FileWrapper {
  final String path;
  FileWrapper(this.path);

  bool existsSync() {
    if (kIsWeb) return false;
    return File(path).existsSync();
  }
}

FileWrapper createFile(String path) => FileWrapper(path);