import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:path/path.dart' as path;

import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:path/path.dart' as path;
import 'package:flutter/foundation.dart';

enum FotoKategori {
  musteriler,
  stoklar,
  stoklistesi,
  stok_tanimlari,
  firmalar,
  faturalar,
  firmahareketleri,
  firma_hareketleri,
  tarim_firmalari,
  tahsilatlar,
  cekler,
  foto,
  formal,
  tarlalar,
  tarla_hareketleri,
  tarla_hasatlari,
  proforma,
  proformalar,
  satislar,
  kasa_hareketleri,
  stok_hareketleri,
  musteri_hareketleri,
  alislar,
  bicer_bakimlar,
  bicer_musterileri,
  bicer_isleri,
  bicer_tahsilatlari,
  bicermusteri_hareketleri,
  bicerler,
  eksper_kayitlari,
  adaciklar, // <-- 'ı' harfini 'i' yaptık
  musteri_faturalari,
  araclar,
  bakimlar,
  evren_ticaret,
  bicer_mazotlar,
  mazot_takibi,
  isletmeler,
  personel_hareketleri,
  cek_senetler,
  personel

}

class FirebaseFotoService {
  static final FirebaseFotoService _instance = FirebaseFotoService._internal();
  factory FirebaseFotoService() => _instance;
  FirebaseFotoService._internal();

  final FirebaseStorage _storage = FirebaseStorage.instance;

  /// Fotoğraf Yükleme Fonksiyonu
  /// [kategori]: FotoKategori.stoklar gibi yukarıdaki listeden seçilir.
  /// [dosya]: Yüklenecek File objesi.
  Future<String?> fotoYukle(FotoKategori kategori, File dosya) async {
    try {
      // Klasör adını enumdan alıyoruz (Örn: 'bicer_isleri')
      String klasorAdi = kategori.name;

      // Dosya adını benzersiz yap
      String dosyaAdi = "${DateTime.now().millisecondsSinceEpoch}${path.extension(dosya.path)}";

      // Kayıt yerini belirle
      Reference ref = _storage.ref().child(klasorAdi).child(dosyaAdi);

      // Yükle
      UploadTask yukleme = ref.putFile(dosya);
      TaskSnapshot snapshot = await yukleme;

      // İnternet Linkini al
      String downloadUrl = await snapshot.ref.getDownloadURL();

      debugPrint("✅ Yüklendi: $klasorAdi -> $downloadUrl");
      return downloadUrl;
    } catch (e) {
      debugPrint("❌ Yükleme Hatası (${kategori.name}): $e");
      return null;
    }
  }

  /// Mevcut fotoğrafı siler (Storage temizliği için)
  Future<void> fotoSil(String? fotoUrl) async {
    if (fotoUrl == null || fotoUrl.isEmpty || !fotoUrl.startsWith('http')) return;
    try {
      await _storage.refFromURL(fotoUrl).delete();
      debugPrint("🗑️ Fotoğraf Storage'dan silindi.");
    } catch (e) {
      debugPrint("⚠️ Silme Hatası (Muhtemelen dosya yok): $e");
    }
  }
}