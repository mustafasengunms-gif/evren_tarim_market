// io_utils.dart
import 'package:flutter/foundation.dart';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'dart:io' show File;

class PlatformKontrol {
  static bool get isWeb => kIsWeb;

  // Web'de File sınıfı yerine boş bir nesne döndürür, mobilde gerçek File'ı kullanır
  static dynamic dosyaOlustur(String path) {
    if (kIsWeb) return null;
    return File(path);
  }
}