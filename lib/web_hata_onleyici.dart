// lib/web_hata_onleyici.dart
import 'dart:typed_data';

class File {
  final String path;
  File(this.path);

  Future<File> copy(String newPath) async => this;
  Future<bool> exists() async => false;
  bool existsSync() => false;
  Future<Uint8List> readAsBytes() async => Uint8List(0);
  Future<File> writeAsBytes(List<int> bytes) async => this;
}

class Directory {
  final String path;
  Directory(this.path);
}

class FileImage {
  final dynamic file;
  FileImage(this.file);
}