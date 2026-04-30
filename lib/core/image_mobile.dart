import 'package:flutter/material.dart';
import 'dart:io';

Widget buildImage(String path, {BoxFit fit = BoxFit.cover}) {
  if (path.isEmpty) {
    return const Icon(Icons.image_not_supported);
  }

  return Image.file(
    File(path),
    fit: fit,
    errorBuilder: (c, e, s) => const Icon(Icons.broken_image),
  );
}