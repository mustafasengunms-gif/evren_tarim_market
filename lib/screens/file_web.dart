class FileWrapper {
  final String path;
  FileWrapper(this.path);

  Future<bool> exists() async => false;
}