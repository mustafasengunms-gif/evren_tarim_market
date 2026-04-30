import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'dart:io' show File;

Widget buildImage(String path, {BoxFit fit = BoxFit.cover}) {
  if (path.isEmpty) {
    return const Icon(Icons.image_not_supported);
  }

  if (kIsWeb) {
    return Image.network(
      path,
      fit: fit,
      errorBuilder: (_, __, ___) => const Icon(Icons.broken_image),
    );
  }

  return Image.file(
    File(path),
    fit: fit,
    errorBuilder: (_, __, ___) => const Icon(Icons.broken_image),
  );
}