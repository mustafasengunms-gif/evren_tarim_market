import 'dart:io';

class FileWrapper {
  final File file;
  FileWrapper(String path) : file = File(path);

  Future<bool> exists() async => file.exists();
}