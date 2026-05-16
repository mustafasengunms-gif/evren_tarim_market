import 'package:cloud_firestore/cloud_firestore.dart';

// 1. Durum ve Tip Enum'ları
enum CekTipi { cek, senet }
enum CekDurumu { beklemede, odendi, iptal ,iade}

class CekModel {
  final int id;
  final String firmaAd;
  final CekTipi tip;
  final DateTime kesideTarihi;
  final DateTime vadeTarihi;
  final double tutar;
  CekDurumu durum;
  String? resimYolu;

  CekModel({
    required this.id,
    required this.firmaAd,
    required this.tip,
    required this.kesideTarihi,
    required this.vadeTarihi,
    required this.tutar,
    this.durum = CekDurumu.beklemede,
    this.resimYolu,
  });

  // --- SQL VE FIREBASE'E YAZARKEN KULLANILAN (TO MAP) ---
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'firmaAd': firmaAd,
      'tip': tip.name, // Enum'ı string saklar (cek / senet)
      'kesideTarihi': kesideTarihi.toIso8601String(),
      'vadeTarihi': vadeTarihi.toIso8601String(),
      'tutar': tutar,
      'durum': durum.name, // Enum'ı string saklar (beklemede / odendi)
      'resimYolu': resimYolu,
    };
  }

  // --- SQL VEYA FIREBASE'DEN VERİ OKURKEN KULLANILAN (FROM MAP) ---
  factory CekModel.fromMap(Map<String, dynamic> map) {
    return CekModel(
      id: map['id'] is String ? int.parse(map['id']) : (map['id'] as int),
      firmaAd: map['firmaAd'] ?? '',
      tip: map['tip'] == 'senet' ? CekTipi.senet : CekTipi.cek,
      kesideTarihi: _tarihCoz(map['kesideTarihi']),
      vadeTarihi: _tarihCoz(map['vadeTarihi']),
      tutar: (map['tutar'] as num).toDouble(),
      durum: _durumCoz(map['durum']),
      resimYolu: map['resimYolu'],
    );
  }

  // Yardımcı Metot: Tarih formatını (Timestamp veya String) çözer
  static DateTime _tarihCoz(dynamic data) {
    if (data == null) return DateTime.now();
    if (data is Timestamp) return data.toDate();
    if (data is String) return DateTime.parse(data);
    return DateTime.now();
  }

  // Yardımcı Metot: Durum stringini Enum'a çevirir
  static CekDurumu _durumCoz(String? durumStr) {
    if (durumStr == 'odendi') return CekDurumu.odendi;
    if (durumStr == 'iptal') return CekDurumu.iptal;
    if (durumStr == 'iade') return CekDurumu.iade; // <--- burayı ekle
    return CekDurumu.beklemede;
  }
}