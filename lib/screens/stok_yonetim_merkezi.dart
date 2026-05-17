import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../db/database_helper.dart';
import 'stok_giris_sayfasi.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'dart:typed_data'; // Uint8List için şart
import 'package:flutter/services.dart'; // rootBundle (Logo okuma) için şart
import 'package:pdf/pdf.dart'; // PdfColors ve PdfPageFormat için
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import 'stok_tanimla_sayfasi.dart';
import 'package:sqflite/sqflite.dart';
import 'alis_islem_sayfasi.dart'; // Eğer aynı klasördeyseler
import 'package:path_provider/path_provider.dart'; // En üste ekle
import 'package:path/path.dart' as p; // Dosya adı işlemleri için
import 'package:flutter/foundation.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:firebase_storage/firebase_storage.dart';
import 'package:path/path.dart' as path;
import 'dart:convert'; // Bu satır en üstte olmalı
import '../services/firebase_foto_service.dart';
import '../utils/pdf_helper.dart';

class StokYonetimMerkezi extends StatefulWidget {
  final int seciliSube;
  const StokYonetimMerkezi({super.key, required this.seciliSube});

  @override
  State<StokYonetimMerkezi> createState() => _StokYonetimMerkeziState();
}

class _StokYonetimMerkeziState extends State<StokYonetimMerkezi> {
  final TextEditingController _araC = TextEditingController();

  int _aktifFiltreSube = 2;
  String seciliSube = "HEPSİ"; // Başlangıç ismini de düzelttik
  List<Map<String, dynamic>> _asilListe = [];
  List<Map<String, dynamic>> _filtreli = [];

  // KATEGORİLER BURADA DA OLSUN (Gerekirse diye)
  List<String> _kategoriler = [];
  bool _tutarGozuksun = false;

  @override
  void initState() {
    super.initState();
    _aktifFiltreSube = 2;
    _verileriYukle();

    // 🎯 KRİTİK: Web platformunda senkronizasyon motorunu hiç tetikleme!
    if (!kIsWeb) {
      _firebaseSenkronizeEt();
    }
  }

  void _subeTransfer(Map<String, dynamic> urun) {
    final TextEditingController miktarC = TextEditingController();

    double mevcutAdet =
        double.tryParse(urun['adet'].toString()) ?? 0;

    String suankiSube =
    urun['sube'].toString().trim().toUpperCase();

    String hedefSube =
    suankiSube == "TEFENNİ" ? "AKSU" : "TEFENNİ";

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(15),
        ),
        title: const Text(
          "ŞUBELER ARASI SEVKİYAT",
          textAlign: TextAlign.center,
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [

              Container(
                padding: const EdgeInsets.symmetric(
                    vertical: 10,
                    horizontal: 15),
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: Colors.blue[200]!,
                  ),
                ),
                child: Row(
                  mainAxisAlignment:
                  MainAxisAlignment.spaceEvenly,
                  children: [
                    Column(
                      children: [
                        const Text(
                          "ÇIKIŞ",
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.red,
                          ),
                        ),
                        Text(
                          suankiSube,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),

                    const Icon(
                      Icons.double_arrow,
                      color: Colors.blue,
                    ),

                    Column(
                      children: [
                        const Text(
                          "VARIŞ",
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.green,
                          ),
                        ),
                        Text(
                          hedefSube,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              Text(
                "${urun['marka']} ${urun['model']}",
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),

              Text(
                "Mevcut: $mevcutAdet Adet",
                style: const TextStyle(color: Colors.grey),
              ),

              const SizedBox(height: 20),

              TextField(
                controller: miktarC,
                keyboardType:
                const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: "Sevk Miktarı",
                  border: OutlineInputBorder(),
                  suffixText: "Adet",
                ),
              ),
            ],
          ),
        ),

        actions: [

          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);
            },
            child: const Text("İPTAL"),
          ),

          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue[900],
            ),

            onPressed: () async {

              double miktar =
                  double.tryParse(
                    miktarC.text.replaceAll(',', '.'),
                  ) ??
                      0;

              if (miktar <= 0 || miktar > mevcutAdet) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text("Hatalı miktar!"),
                  ),
                );
                return;
              }

              try {

                Map<String, dynamic> temizUrun = Map<String, dynamic>.from(urun);

// SQLite'da olmayan ve hata veren sütunları temizliyoruz
                temizUrun.remove('alis_fiyatı');
                temizUrun.remove('firma_unvani'); // 👈 Bu satırı buraya ekle!

                String markaM =
                (temizUrun['marka'] ?? "")
                    .toString()
                    .trim()
                    .toUpperCase();

                String modelM =
                (temizUrun['model'] ?? "")
                    .toString()
                    .trim()
                    .toUpperCase();

                String altM =
                (temizUrun['alt_model'] ?? "")
                    .toString()
                    .trim()
                    .toUpperCase();

                String yeniMuhur =
                "${markaM}_${modelM}_${altM}_$hedefSube"
                    .replaceAll(' ', '_');

                final db =
                await DatabaseHelper.instance.database;
// ===================================================
// 1. MEVCUT ŞUBEDEN DÜŞ
// ===================================================

                debugPrint("=================================================");
                debugPrint("TRANSFER BAŞLADI");
                debugPrint("ÜRÜN: ${temizUrun['urun']}");
                debugPrint("MEVCUT ŞUBE: ${temizUrun['sube']}");
                debugPrint("HEDEF ŞUBE: $hedefSube");
                debugPrint("MİKTAR: $miktar");
                debugPrint("STOK ID: ${temizUrun['id']}");
                debugPrint("STOK KODU: ${temizUrun['stok_kodu']}");
                debugPrint("=================================================");

                await db.rawUpdate('''
UPDATE stoklar
SET adet = adet - ?
WHERE id = ?
''', [
                  miktar,
                  temizUrun['id'],
                ]);

                debugPrint("✅ Mevcut şubeden düşüldü");

// ===================================================
// 2. EĞER ADET 0 OLDUYSA SATIRI PASİF YAP
// ===================================================

                await db.rawUpdate('''
UPDATE stoklar
SET silindi = 1
WHERE id = ?
AND adet <= 0
''', [
                  temizUrun['id'],
                ]);

                debugPrint("✅ Adet kontrolü yapıldı");

// ===================================================
// 3. HEDEF ŞUBEDE VAR MI KONTROL
// ===================================================

                debugPrint("🔍 Hedef şube kontrol ediliyor...");

                final hedefKontrol = await db.query(
                  'stoklar',
                  where:
                  'marka = ? AND model = ? AND alt_model = ? AND sube = ? AND silindi = 0',
                  whereArgs: [
                    temizUrun['marka'],
                    temizUrun['model'],
                    temizUrun['alt_model'],
                    hedefSube,
                  ],
                );

                debugPrint("🔍 Hedef Kontrol Sonucu:");
                debugPrint(hedefKontrol.toString());

// ===================================================
// 4. VARSA SADECE ADET ARTIR
// ===================================================

                if (hedefKontrol.isNotEmpty) {

                  debugPrint("✅ Hedef şubede ürün VAR");
                  debugPrint("➡️ SADECE ADET ARTIRILACAK");

                  int hedefId = int.parse(
                    hedefKontrol.first['id'].toString(),
                  );

                  debugPrint("HEDEF ID: $hedefId");

                  await db.rawUpdate('''
  UPDATE stoklar
  SET adet = adet + ?
  WHERE id = ?
  ''', [
                    miktar,
                    hedefId,
                  ]);

                  debugPrint("✅ Hedef stok adedi artırıldı");
                }

// ===================================================
// 5. YOKSA YENİ ŞUBE KAYDI OLUŞTUR
// ===================================================

                else {

                  debugPrint("❌ Hedef şubede ürün YOK");
                  debugPrint("➡️ YENİ STOK KAYDI OLUŞTURULUYOR");

                  final yeniStokKodu =
                      "TRF-${DateTime.now().millisecondsSinceEpoch}";

                  debugPrint("🆕 Yeni Stok Kodu: $yeniStokKodu");

                  await db.insert(
                    'stoklar',
                    {

                      'firebase_id': yeniMuhur,

                      'urun':
                      temizUrun['urun'],

                      // BURASI ÇOK ÖNEMLİ
                      'stok_kodu':
                      yeniStokKodu,

                      'cari_kod':
                      temizUrun['cari_kod'],

                      'kategori':
                      temizUrun['kategori'],

                      'marka':
                      temizUrun['marka'],

                      'model':
                      temizUrun['model'],

                      'alt_model':
                      temizUrun['alt_model'],

                      'adet':
                      miktar,

                      'fiyat':
                      temizUrun['fiyat'],

                      'alis_fiyati':
                      temizUrun['alis_fiyati'],

                      'sube':
                      hedefSube,

                      'durum':
                      temizUrun['durum'],

                      'tarih':
                      temizUrun['tarih'],

                      'fatura_no':
                      temizUrun['fatura_no'],

                      'foto':
                      temizUrun['foto'],

                      'is_synced': 0,

                      'silindi': 0,
                    },
                  );

                  debugPrint("✅ Yeni şube kaydı oluşturuldu");
                }

// ===================================================
// 6. FIREBASE ESKİ ŞUBE DÜŞ
// ===================================================

                if (temizUrun['firebase_id'] != null &&
                    temizUrun['firebase_id']
                        .toString()
                        .isNotEmpty) {

                  debugPrint("☁️ Firebase eski şube düşülüyor");

                  await FirebaseFirestore.instance
                      .collection('stoklar')
                      .doc(
                    temizUrun['firebase_id']
                        .toString(),
                  )
                      .update({

                    'adet':
                    FieldValue.increment(
                      -miktar,
                    ),

                    'is_synced': 1,
                  });

                  debugPrint("✅ Firebase eski şube güncellendi");
                }

// ===================================================
// 7. FIREBASE HEDEF ŞUBE EKLE
// ===================================================

                debugPrint("☁️ Firebase hedef şube ekleniyor");

                await FirebaseFirestore.instance
                    .collection('stoklar')
                    .doc(yeniMuhur)
                    .set({

                  ...temizUrun,

                  'adet':
                  FieldValue.increment(
                    miktar,
                  ),

                  'sube': hedefSube,

                  'firebase_id': yeniMuhur,

                  'is_synced': 1,

                }, SetOptions(merge: true));

                debugPrint("✅ Firebase hedef şube güncellendi");

// ===================================================
// 8. YENİLE
// ===================================================

                debugPrint("🔄 VERİLER YENİLENİYOR");

                if (context.mounted) {

                  Navigator.of(
                    context,
                    rootNavigator: true,
                  ).pop();

                  await _verileriYukle();

                  debugPrint("✅ TRANSFER TAMAMLANDI");

                  ScaffoldMessenger.of(context)
                      .showSnackBar(
                    const SnackBar(
                      content:
                      Text("Transfer Başarılı ✅"),
                      backgroundColor:
                      Colors.green,
                    ),
                  );
                }

              } catch (e) {

                debugPrint(
                    "Transfer Hatası: $e");

                if (context.mounted) {

                  Navigator.of(
                    context,
                    rootNavigator: true,
                  ).pop();

                  ScaffoldMessenger.of(context)
                      .showSnackBar(
                    SnackBar(
                      content:
                      Text("Transfer Hatası: $e"),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },

            child: const Text(
              "ONAYLA",
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _verileriYukle() async {

    // =========================================================
    // WEB İÇİN: FIREBASE'DEN VERİ ÇEK
    // =========================================================
    if (kIsWeb) {
      try {
        final firmaSnapshot =
        await FirebaseFirestore.instance.collection('tarim_firmalari').get();

        // hem doc.id hem cari_kod mühürlerini yakalayan akıllı harita
        Map<String, String> firmaMap = {};
        for (var doc in firmaSnapshot.docs) {
          final d = doc.data();
          String unvan = (d['ad'] ?? d['reklam'] ?? 'BİLİNMEYEN FİRMA').toString().toUpperCase().trim();

          firmaMap[doc.id.toUpperCase().trim()] = unvan;
          if (d['cari_kod'] != null) {
            firmaMap[d['cari_kod'].toString().toUpperCase().trim()] = unvan;
          }
        }

        final snapshot = await FirebaseFirestore.instance
            .collection('stoklar')
            .where('silindi', isEqualTo: 0)
            .get();

        final stoklar = snapshot.docs.map((doc) {

          final data = doc.data();

          String cKod = (data['cari_kod'] ?? '').toString().toUpperCase().trim();

          // =====================================================
          // FİYAT GARANTİ MOTORU (WEB)
          // =====================================================

          double fiyat1 =
              double.tryParse(
                  (data['fiyat'] ?? '')
                      .toString()
                      .replaceAll(',', '.')
              ) ?? 0.0;

          double fiyat2 =
              double.tryParse(
                  (data['alis_fiyati'] ?? '')
                      .toString()
                      .replaceAll(',', '.')
              ) ?? 0.0;

          double fiyat3 =
              double.tryParse(
                  (data['alis_fiyatı'] ?? '')
                      .toString()
                      .replaceAll(',', '.')
              ) ?? 0.0;

          double gercekFiyat = 0.0;

          if (fiyat1 > 0) {
            gercekFiyat = fiyat1;
          } else if (fiyat2 > 0) {
            gercekFiyat = fiyat2;
          } else if (fiyat3 > 0) {
            gercekFiyat = fiyat3;
          }

          debugPrint("🌐 WEB FİYAT KONTROL");
          debugPrint("Ürün: ${data['urun']}");
          debugPrint("fiyat: $fiyat1");
          debugPrint("alis_fiyati: $fiyat2");
          debugPrint("alis_fiyatı: $fiyat3");
          debugPrint("SONUÇ: $gercekFiyat");

          // Haritada firma eşleşmezse stok içindeki yedek alanlara bakar
          String yedekFirma = (data['tarim_firmalari'] ?? data['firma_unvani'] ?? 'GENEL').toString().toUpperCase();
          String firmaUnvani = firmaMap[cKod] ?? yedekFirma;

          return {
            ...data,

            'firebase_id': doc.id,
            'id': doc.id, // Web listeleme ve döngü güvenliği için eklendi

            // UYGULAMA HER YERDE BUNU KULLANACAK
            'fiyat': gercekFiyat,

            // EK GARANTİ
            'alis_fiyati': fiyat2,
            'alis_fiyatı': fiyat3,

            // Sayı dönüşüm güvenliği (Toplam adetlerin doğru hesaplanması için)
            'adet': double.tryParse((data['adet'] ?? '0').toString().replaceAll(',', '.')) ?? 0.0,
            'sube': (data['sube'] ?? 'TEFENNİ').toString().toUpperCase().trim(),
            'silindi': int.tryParse((data['silindi'] ?? '0').toString()) ?? 0,

            'firma_unvani': firmaUnvani,
          };

        }).toList();

        if (mounted) {
          setState(() {
            _asilListe = List.from(stoklar);
            _listeyiYenile();
          });
        }
      } catch (e) {
        debugPrint("❌ WEB VERİ YÜKLEME HATASI: $e");
      }

      return;
    }

    // =========================================================
    // MOBİL İÇİN: SQL VERİLERİ ÇEK
    // =========================================================

    final db = await DatabaseHelper.instance.database;

    // Sorguyu COALESCE ile güçlendirdik, firma adı yoksa 'GENEL' yazacak
    final List<Map<String, dynamic>> stoklar = await db.rawQuery('''
  SELECT 
    s.*, 
    COALESCE(f.ad, s.marka, 'GENEL') as firma_unvani
  FROM stoklar s
  LEFT JOIN tarim_firmalari f ON s.cari_kod = f.cari_kod
  WHERE s.silindi = 0
  ORDER BY s.id DESC
''');

    // =========================================================
    // FİYAT NORMALİZASYONU
    // =========================================================

    final normalizeEdilmisStoklar = stoklar.map((s) {

      double fiyat1 =
          double.tryParse(
              (s['fiyat'] ?? '')
                  .toString()
                  .replaceAll(',', '.')
          ) ?? 0.0;

      double fiyat2 =
          double.tryParse(
              (s['alis_fiyati'] ?? '')
                  .toString()
                  .replaceAll(',', '.')
          ) ?? 0.0;

      double fiyat3 =
          double.tryParse(
              (s['alis_fiyatı'] ?? '')
                  .toString()
                  .replaceAll(',', '.')
          ) ?? 0.0;

      // =====================================================
      // HANGİSİ DOLUYSA ONU AL
      // =====================================================

      double gercekBirimFiyat = 0.0;

      if (fiyat1 > 0) {
        gercekBirimFiyat = fiyat1;
      } else if (fiyat2 > 0) {
        gercekBirimFiyat = fiyat2;
      } else if (fiyat3 > 0) {
        gercekBirimFiyat = fiyat3;
      }

      debugPrint("📱 SQL FİYAT KONTROL");
      debugPrint("Ürün: ${s['urun']}");
      debugPrint("fiyat: $fiyat1");
      debugPrint("alis_fiyati: $fiyat2");
      debugPrint("alis_fiyatı: $fiyat3");
      debugPrint("SONUÇ: $gercekBirimFiyat");

      return {

        ...s,

        // ANA FİYAT
        'fiyat': gercekBirimFiyat,

        // EK GARANTİ
        'alis_fiyati': fiyat2,
        'alis_fiyatı': fiyat3,
      };

    }).toList();

    // =========================================================
    // KATEGORİLER
    // =========================================================

    final tazeKategoriler =
    await DatabaseHelper.instance.kategorileriGetirGaranti();

    // =========================================================
    // STATE
    // =========================================================

    if (mounted) {
      setState(() {

        _asilListe = List.from(normalizeEdilmisStoklar);

        _kategoriler = tazeKategoriler;

        _listeyiYenile();

      });
    }
  }

  double temizFiyat(dynamic veri) {
    if (veri == null) return 0.0;

    String v = veri.toString()
        .replaceAll('₺', '')
        .replaceAll('TL', '')
        .replaceAll(' ', '')
        .replaceAll('.', '')
        .replaceAll(',', '.');

    return double.tryParse(v) ?? 0.0;
  }

  Future<void> _firebaseSenkronizeEt() async {
    if (kIsWeb) return;

    try {
      final db = await DatabaseHelper.instance.database;

      // 1. ADIM: Sadece silinmemiş kayıtları buluttan çek
      final snapshot = await FirebaseFirestore.instance
          .collection('stoklar')
          .where('silindi', isEqualTo: 0)
          .get();

      // Yereldeki mevcut kayıtların listesini alıyoruz
      final existingLocal = await db.query('stoklar', columns: ['firebase_id']);
      final existingIds = existingLocal.map((e) => e['firebase_id'].toString()).toSet();

      await db.transaction((txn) async {
        for (var doc in snapshot.docs) {
          final data = doc.data();

          // 1. GÜVENLİK: Silinenleri atla
          int silindiMi = int.tryParse(data['silindi']?.toString() ?? "0") ?? 0;
          if (silindiMi == 1) continue;

          // --- DURUM MANTIĞI ---
          String gelenDurum = (data['durum'] ?? "").toString().toUpperCase().trim();
          if (gelenDurum == "") {
            gelenDurum = "SIFIR";
          }

          // --- ÇİFT MÜHÜRLÜ FİYAT YAKALAMA ---
          // Hangi fiyat alanı doluysa onu yakalayan akıllı motor
          double kaydedilecekFiyat = 0.0;
          double fiyat1 = double.tryParse((data['fiyat'] ?? '0').toString().replaceAll(',', '.')) ?? 0.0;
          double fiyat2 = double.tryParse((data['alis_fiyati'] ?? '0').toString().replaceAll(',', '.')) ?? 0.0;
          double fiyat3 = double.tryParse((data['alis_fiyatı'] ?? '0').toString().replaceAll(',', '.')) ?? 0.0;

          if (fiyat1 > 0) {
            kaydedilecekFiyat = fiyat1;
          } else if (fiyat2 > 0) {
            kaydedilecekFiyat = fiyat2;
          } else if (fiyat3 > 0) {
            kaydedilecekFiyat = fiyat3;
          }

          // 🔥 GÜVENLİK ADIMI: SQLite şemasına %100 uyumlu Map oluşturma
          // Tabloda olmayan 'alis_fiyatı' ve 'firma_unvani' gibi alanları buraya EKLEMİYORUZ.
          Map<String, dynamic> stokVerisi = {
            'urun': (data['urun'] ?? '').toString().toUpperCase(),
            'marka': (data['marka'] ?? '').toString().toUpperCase(),
            'model': (data['model'] ?? '').toString().toUpperCase(),

            'alt_model': (data['alt_model'] ?? data['altmodel'] ?? '').toString().toUpperCase(),
            'ana_stok_id': data['ana_stok_id'],
            'kategori': (data['kategori'] ?? 'GENEL').toString().toUpperCase(),

            // ADET MANTIĞI
            'adet': double.tryParse(data['adet']?.toString().replaceAll(',', '.') ?? '0') ?? 0.0,

            // FİYAT GARANTİSİ (Sadece SQLite'ın tanıdığı sütunlar)
            'fiyat': kaydedilecekFiyat,
            'alis_fiyati': kaydedilecekFiyat, // Sadece i'li olan sütun

            'sube': (data['sube'] ?? 'TEFENNİ').toString().toUpperCase(),
            'durum': gelenDurum,
            'cari_kod': data['cari_kod'],
            'fatura_no': data['fatura_no'] ?? 'EXCEL_YUKLEME',
            'stok_kodu': data['stok_kodu'] ?? doc.id,
            'barkod': data['barkod'],
            'foto': data['foto'],

            'is_synced': 1,
            'silindi': 0,
            'son_guncelleme': data['son_guncelleme'] != null ? data['son_guncelleme'].toString() : '16.05.2026',
            'firebase_id': doc.id,
          };

          if (existingIds.contains(doc.id)) {
            // Yerelde zaten varsa güncelle
            await txn.update(
              'stoklar',
              stokVerisi,
              where: 'firebase_id = ?',
              whereArgs: [doc.id],
            );
            debugPrint("🔄 Yereldeki stok buluttan GÜNCELLENDİ (Fiyat: $kaydedilecekFiyat): ${doc.id}");
          } else {
            // Yerelde hiç yoksa (Yeni Transfer Edilen Ürünler Buraya Düşer) sıfırdan ekle
            await txn.insert(
              'stoklar',
              stokVerisi,
              conflictAlgorithm: ConflictAlgorithm.replace,
            );
            debugPrint("📥 Yeni stok yerelde OLUŞTURULDU (Fiyat: $kaydedilecekFiyat): ${doc.id}");
          }
        }
      });

      // Her şey bitince ekranı tazelemek için yerel verileri yeniden yükle
      await _verileriYukle();

    } catch (e) {
      debugPrint("⚠️ Firebase Senkronizasyon Hatası: $e");
    }
  }

  void _listeyiYenile() {
    setState(() {
      String arama = _araC.text.trim().toUpperCase();
      _filtreli = _asilListe.where((s) {

        // 1. MÜHÜR KONTROLÜ (Silinenleri Gizle)
        int silindiMi = int.tryParse(s['silindi']?.toString() ?? "0") ?? 0;
        if (silindiMi == 1) return false;

        // 2. ŞUBE FİLTRESİ
        bool subeUyuyor = (_aktifFiltreSube == 2) ||
            (_aktifFiltreSube == 0 && s['sube'].toString().toUpperCase() == "TEFENNİ") ||
            (_aktifFiltreSube == 1 && s['sube'].toString().toUpperCase() == "AKSU");

        // 3. ARAMA FİLTRESİ
        String urunAdi = (s['urun'] ?? '').toString().toUpperCase();
        String marka = (s['marka'] ?? '').toString().toUpperCase();
        String model = (s['model'] ?? '').toString().toUpperCase();
        String alt = (s['alt_model'] ?? s['altmodel'] ?? '').toString().toUpperCase();
        String firmaUnvani = (s['firma_unvani'] ?? '').toString().toUpperCase();

        bool aramaUyuyor = arama.isEmpty ||
            urunAdi.contains(arama) ||
            marka.contains(arama) ||
            model.contains(arama) ||
            alt.contains(arama) ||
            firmaUnvani.contains(arama);

        return subeUyuyor && aramaUyuyor;
      }).toList();
    });
  }

// --- HESAPLAMA GETTER'I ---
// Bu fonksiyonun State sınıfının süslü parantezi ( } ) kapanmadan önce yazıldığına emin ol.
  double get _toplamStokDegeri {
    double toplam = 0;
    for (var s in _filtreli) {
      double adet = double.tryParse(s['adet']?.toString() ?? "0") ?? 0;
      double fiyat = double.tryParse(s['fiyat']?.toString() ?? "0") ?? 0;
      toplam += (adet * fiyat);
    }
    return toplam;
  }

  @override
  Widget build(BuildContext context) {
    final Color anaRenk = widget.seciliSube == 0 ? Colors.green[800]! : Colors.blue[900]!;

    return Scaffold(
      backgroundColor: Colors.grey[200],
      appBar: AppBar(
        title: const Text("STOK GİRİŞİ"),
        backgroundColor: anaRenk,
        foregroundColor: Colors.white,
        actions: [
          // 🔥 İSTEDİĞİN FOTOĞRAF KLASÖRÜ BURADA
          IconButton(
            icon: const Icon(Icons.folder_open, size: 28),
            onPressed: () => _tumFotolariGoster(),
          ),
          const SizedBox(width: 10),
        ],
      ),
      body: Column(
        children: [
          // 1. ÖZET PANELİ (GÜNCELLENDİ: GİZLİ TUTAR EKLENDİ)
          Container(
            padding: const EdgeInsets.all(15), color: Colors.white,
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
              _ozetKutu("ÇEŞİT", "${_filtreli.length}", Colors.blue),
              _ozetKutu(
                  "TOPLAM ADET",
                  _filtreli.fold<num>(0, (p, e) => p + (num.tryParse(e['adet'].toString()) ?? 0)).toString(),
                  Colors.orange
              ),
              // 🔥 GİZLİ TOPLAM TUTAR (DOKUNUNCA AÇILIR)
              GestureDetector(
                onTap: () => setState(() => _tutarGozuksun = !_tutarGozuksun),
                child: _ozetKutu(
                    "TOPLAM TUTAR (GİZLİ)",
                    _tutarGozuksun
                        ? NumberFormat.currency(locale: "tr_TR", symbol: "₺").format(_toplamStokDegeri)
                        : "****** ₺",
                    Colors.green[700]!
                ),
              ),
            ]),
          ),

          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              _ustButon("STOK GİRİŞ", Icons.add_box, Colors.orange[800]!, () {
                Navigator.push(
                    context,
                    MaterialPageRoute(builder: (c) => DetayliStokGirisSayfasi(seciliSube: widget.seciliSube))
                ).then((_) => _verileriYukle()); // BURASI ÇOK ÖNEMLİ: Geri gelince listeyi tazelemeli!
              }),
              _ustButon("STOK TANIMLA EVREN", Icons.app_registration, Colors.purple[700]!, () async {
                // Önce gerekli verileri hazırlıyoruz
                final firmalar = await DatabaseHelper.instance.tarimFirmaListesiGetir();
                final tanimlar = await DatabaseHelper.instance.stokTanimlariniGetir();

                if (context.mounted) {
                  Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (c) => StokTanimlaSayfasi(
                              mevcutFirmalar: firmalar,
                              tanimliStoklar: tanimlar,
                              onKaydet: (yeni) {
                                _verileriYukle();
                              }
                          )
                      )
                  ).then((_) {
                    // Sayfadan geri çıkınca ana sayfayı tazele
                    _verileriYukle();
                  });
                }
              }),
              const SizedBox(width: 8),
              _ustButon("RAPOR", Icons.picture_as_pdf, Colors.teal[700]!, () => _pdfOnizlemeGoster(context)),
            ]),
          ),

          _subeSecimBar(),
          _aramaCubugu(),

          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 15, vertical: 8),
            child: Align(alignment: Alignment.centerLeft, child: Text("MEVCUT STOKLAR (SADECE VARDA OLANLAR)", style: TextStyle(fontWeight: FontWeight.bold))),
          ),

          Expanded(child: _stokListesi(anaRenk)),
        ],
      ),
    );
  }
  void _pdfOnizlemeGoster(BuildContext context) async {
    final pdf = pw.Document();

    // 1. Yazı Tipleri (Türkçe karakterler için)
    final font = await PdfGoogleFonts.robotoRegular();
    final boldFont = await PdfGoogleFonts.robotoBold();

    // 2. Logo Yükleme (assets içinde logo.png olduğunu varsayıyoruz)
    // Eğer logo dosya yolun farklıysa burayı düzelt abi
    final ByteData bytes = await rootBundle.load('assets/images/logo.png');
    final Uint8List byteList = bytes.buffer.asUint8List();
    final logoResmi = pw.MemoryImage(byteList);

    // 3. TL Formatlayıcı (Parayı 1.500,00 ₺ şeklinde yazar)
    final formatTR = NumberFormat.currency(locale: "tr_TR", symbol: "₺");

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        theme: pw.ThemeData.withFont(base: font, bold: boldFont),
        build: (pw.Context context) => [
          // --- LOGO VE BAŞLIK ---
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Row(
                children: [
                  pw.Container(width: 50, height: 50, child: pw.Image(logoResmi)),
                  pw.SizedBox(width: 10),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text("EVREN TARIM ALETLERİ",
                          style: pw.TextStyle(font: boldFont, fontSize: 20, color: PdfColors.blue900)),
                      pw.Text("Evren Özçoban | Tefenni - BURDUR",
                          style: pw.TextStyle(fontSize: 10)),
                    ],
                  ),
                ],
              ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text("GÜNCEL STOK RAPORU",
                      style: pw.TextStyle(font: boldFont, fontSize: 12)),
                  pw.Text("Tarih: ${DateFormat('dd.MM.yyyy').format(DateTime.now())}",
                      style: pw.TextStyle(fontSize: 10)),
                ],
              ),
            ],
          ),
          pw.Divider(thickness: 2, color: PdfColors.blue900),
          pw.SizedBox(height: 15),

          // --- TABLO ---
          pw.TableHelper.fromTextArray(
            headers: ['MARKA / MODEL', 'ADET', 'SUBE', 'BİRİM FİYAT'],
            headerStyle: pw.TextStyle(font: boldFont, color: PdfColors.white),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.blue900),
            cellAlignment: pw.Alignment.centerLeft,
            // Sütun genişliklerini ayarla (Ürün ismi daha geniş olsun)
            columnWidths: {
              0: const pw.FlexColumnWidth(4),
              1: const pw.FlexColumnWidth(1),
              2: const pw.FlexColumnWidth(2),
              3: const pw.FlexColumnWidth(2),
            },
            data: _filtreli.map((s) {
              double fiyat = double.tryParse(s['fiyat']?.toString() ?? "0") ?? 0;
              return [
                "${s['marka'] ?? ''} ${s['model'] ?? ''} ${s['alt_model'] ?? ''}".trim(),
                s['adet']?.toString() ?? '0',
                s['sube'] ?? '-',
                formatTR.format(fiyat), // ₺ Formatı burada basılıyor
              ];
            }).toList(),
          ),

          pw.SizedBox(height: 20),

          // --- TOPLAM TUTAR BİLGİSİ ---
          pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Container(
              padding: const pw.EdgeInsets.all(8),
              decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.grey400),
                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4))
              ),
              child: pw.Text(
                "GENEL TOPLAM: ${formatTR.format(_toplamStokDegeri)}",
                style: pw.TextStyle(font: boldFont, fontSize: 13, color: PdfColors.blue900),
              ),
            ),
          ),
        ],
      ),
    );

    // Önizleme Ekranına Gönder
    if (mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => Scaffold(
            appBar: AppBar(
              title: const Text("PDF ÖNİZLEME"),
              backgroundColor: Colors.blueGrey[900],
            ),
            body: PdfPreview(
              build: (format) => pdf.save(),
              canDebug: false, // Kenardaki kırmızı debug çizgilerini kapatır
              pdfFileName: "Evren_Tarim_Stok_Listesi.pdf",
            ),
          ),
        ),
      );
    }
  }




  void _stokGuncelle(Map<String, dynamic> urun) {
    final TextEditingController adetC = TextEditingController(text: urun['adet'].toString());
    final TextEditingController fiyatC = TextEditingController(text: urun['fiyat'].toString());
    showDialog(context: context, builder: (context) => AlertDialog(
      title: Text("${urun['marka']} ${urun['model']} DÜZENLE"),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: adetC, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: "Yeni Adet")),
        const SizedBox(height: 10),
        TextField(controller: fiyatC, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: "Yeni Birim Fiyat (₺)")),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text("İPTAL")),
        ElevatedButton(
            onPressed: () async {
              double yeniAdet = double.tryParse(adetC.text) ?? 0;
              double yeniFiyat = double.tryParse(fiyatC.text.replaceAll(',', '.')) ?? 0;

              // 1. SQL Güncelle (Yerel veritabanı fiyat sütununu kullanır)
              await DatabaseHelper.instance.stokGuncelle(urun['id'], yeniAdet.toInt(), yeniFiyat, urun['tarim_firmalari'] ?? '');

              // 2. FIREBASE GÜNCELLE (Bulut hem 'alis_fiyati' hem 'fiyat' görsün, risk sıfırlansın)
              if (urun['firebase_id'] != null) {
                await FirebaseFirestore.instance
                    .collection('stoklar')
                    .doc(urun['firebase_id'])
                    .update({
                  'adet': yeniAdet,
                  'fiyat': yeniFiyat,         // İleride web geçişi için yedek
                  'alis_fiyati': yeniFiyat,   // 🎯 ARANAN KAN: Esas bulut sütun adı
                  'alis_fiyatı': yeniFiyat,   // Türkçe karakter ihtimaline karşı garanti
                });
              }

              await _verileriYukle();
              if (mounted) Navigator.pop(context);
            },
            child: const Text("GÜNCELLE")
        )
      ],
    ));
  }

  // --- MÜHÜR: SİLME MOTORU (STATE İÇİNE YAPIŞTIR) ---
  void _stokSil(int id) async {
    // Onay alıyoruz
    bool? onay = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text("KAYIT SİLİNECEK"),
        content: const Text("Bu stok kaydı ve bağlı borç silinecektir. Emin misin abi?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text("VAZGEÇ")),
          TextButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text("SİL", style: TextStyle(color: Colors.red))
          ),
        ],
      ),
    );

    if (onay == true) {
      try {
        // DatabaseHelper'daki fonksiyonu çağırıyoruz
        // Eğer sende ismi farklıysa (mesela 'db' ise) ona göre düzelt
        bool sonuc = await DatabaseHelper.instance.stokKesinSil(id);

        if (sonuc) {
          _verileriYukle(); // Listeyi tazele
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("Kayıt ve Borç Bilgisi Temizlendi! ✅"))
            );
          }
        }
      } catch (e) {
        debugPrint("Silerken hata çıktı: $e");
      }
    }
  }

  Widget _subeSecimBar() => Row(mainAxisAlignment: MainAxisAlignment.center, children: [_fChip("TEFENNİ", 0), const SizedBox(width: 5), _fChip("AKSU", 1), const SizedBox(width: 5), _fChip("HEPSİ", 2)]);
  Widget _aramaCubugu() => Padding(padding: const EdgeInsets.all(12), child: TextField(controller: _araC, onChanged: (_) => _listeyiYenile(), decoration: InputDecoration(hintText: "Marka/Model Ara...", prefixIcon: const Icon(Icons.search), filled: true, fillColor: Colors.white, border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)))));
  Widget _stokListesi(Color anaRenk) => ListView.builder(
    padding: const EdgeInsets.symmetric(vertical: 8),
    itemCount: _filtreli.length,
    itemBuilder: (context, index) {
      final s = _filtreli[index];

      debugPrint("EKRANA BASILAN FİYAT = ${s['fiyat']}");
      debugPrint("ALIS_FIYATI = ${s['alis_fiyati']}");
      debugPrint("💰 TUTAR ANALİZİ - Ürün: ${s['urun']}");
      debugPrint("- SQLite'dan Gelen Ham Fiyat: ${s['fiyat']} (Tipi: ${s['fiyat'].runtimeType})");
      debugPrint("- Satırın Tamamı: $s");

      debugPrint("🔍 EKRAN KONTROL - Ürün: ${s['urun']} | Gelen Firma: ${s['firma_unvani']} | SQLite Ad: ${s['ad']}");
      debugPrint("DEBUG: Stok ID: ${s['id']} - Gelen Durum: '${s['durum']}'");
      String hamDurum = (s['durum'] ?? "SIFIR").toString().toUpperCase().trim();

      bool isSifir = hamDurum == "SIFIR" || hamDurum == "";

      Color durumRengi = isSifir ? Colors.teal[700]! : Colors.orange[800]!;
      Color durumArkaPlan = isSifir ? Colors.teal[50]! : Colors.orange[50]!;

      final String fotoYolu = (s['foto'] ?? s['fotoğraf'] ?? s['foto_yolu'] ?? "").toString();

      return Card(
        elevation: 3,
        margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: durumRengi.withOpacity(0.3), width: 1),
        ),
        child: Container(
          decoration: BoxDecoration(
            color: durumArkaPlan,
            borderRadius: BorderRadius.circular(12),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => _stokGuncelle(s),
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: Row(
                children: [
                  // --- SOL: FOTOĞRAF ---
                  _modernFotoWidget(fotoYolu, s),

                  const SizedBox(width: 12),

                  // --- ORTA: DETAYLI İÇERİK ---
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "${s['marka'] ?? ''} ${s['model'] ?? ''} ${s['alt_model'] ?? ''}".toUpperCase().trim(),
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 5),

                        Text(
                          "FİRMA: ${s['firma_unvani'] ?? 'GENEL'}",
                          style: TextStyle(
                            color: Colors.blueGrey[900],
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),

                        const SizedBox(height: 8),

                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: [
                            _bilgiRozeti(Icons.store, s['sube'] ?? '-', Colors.blueGrey),
                            _bilgiRozeti(Icons.inventory_2, "${s['adet']} Adet", Colors.blue[900]!),
                            _bilgiRozeti(
                                isSifir ? Icons.verified : Icons.handshake,
                                isSifir ? "SIFIR" : "2. EL",
                                durumRengi
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),

                        // 🎯 İSTEDİĞİN GİBİ TERTEMİZ, SADECE 'fiyat' OKUYAN YER:
                        Text(
                          "${PdfHelper.formatPara(s['fiyat'] ?? 0)} TL",
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                            color: anaRenk,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // --- SAĞ: AKSİYONLAR ---
                  Column(
                    children: [
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.swap_horiz, color: Colors.blue),
                        onPressed: () => _subeTransfer(s),
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                        onPressed: () => _stokSil(s['id']),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );

// 1. ROZET TASARIMI (Şube, Adet ve Durum için)
  Widget _bilgiRozeti(IconData icon, String metin, Color renk) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: renk.withOpacity(0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: renk),
          const SizedBox(width: 4),
          Text(
            metin,
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: renk),
          ),
        ],
      ),
    );
  }

  // 2. MODERN FOTOĞRAF TASARIMI
  Widget _modernFotoWidget(String yol, dynamic s) {
    return Stack(
      children: [
        GestureDetector(
          onTap: () => _fotoGuncelle(s),
          child: Container(
            width: 75,
            height: 75,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.grey[300]!),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4)],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: _fotoGetir(yol), // Senin mevcut fotoğraf getirme fonksiyonun
            ),
          ),
        ),
        if (yol.isNotEmpty)
          Positioned(
            bottom: 0, right: 0,
            child: GestureDetector(
              onTap: () => _resmiBuyut(yol, "${s['marka']} ${s['model']}", s),
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.only(topLeft: Radius.circular(8)),
                ),
                child: const Icon(Icons.fullscreen, color: Colors.blue, size: 18),
              ),
            ),
          ),
      ],
    );
  }

  // 3. PARA FORMATLAYICI (PdfHelper hatasını çözer)
  String _formatPara(dynamic tutar) {
    double m = double.tryParse(tutar.toString()) ?? 0.0;
    return NumberFormat.currency(locale: 'tr_TR', symbol: '', decimalDigits: 2).format(m);
  }

// Resim yükleme mantığını ayrı bir fonksiyona alarak kodu temizledik
  Widget _fotoGetir(String yol) {
    if (yol.isEmpty) return const Icon(Icons.camera_alt, color: Colors.grey);

    if (yol.contains('base64')) {
      try {
        String temiz = yol.contains(',') ? yol.split(',').last : yol;
        return Image.memory(base64Decode(temiz), fit: BoxFit.cover, errorBuilder: (c, e, s) => const Icon(Icons.broken_image));
      } catch (e) { return const Icon(Icons.broken_image); }
    }

    if (yol.startsWith('http')) {
      return Image.network(yol, fit: BoxFit.cover, errorBuilder: (c, e, s) => const Icon(Icons.broken_image));
    }

    if (!kIsWeb) {
      final f = File(yol);
      if (f.existsSync()) return Image.file(f, fit: BoxFit.cover);
    }

    return const Icon(Icons.camera_alt, color: Colors.grey);
  }




  Future<void> _fotoCekVeSadeceSQLEKaydet(Map<String, dynamic> urun) async {
    final ImagePicker picker = ImagePicker();
    // Fotoğrafı çekiyoruz
    final XFile? image = await picker.pickImage(source: ImageSource.camera, imageQuality: 50);

    if (image != null) {
      try {
        // 1. Uygulamanın kendi klasörünü buluyoruz (Kalıcı olması için)
        final directory = await getApplicationDocumentsDirectory();
        final String fileName = "stok_${urun['id']}_${DateTime.now().millisecondsSinceEpoch}.jpg";
        final File localImage = File(path.join(directory.path, fileName));

        // 2. Çekilen fotoğrafı bu kalıcı klasöre kopyalıyoruz
        await File(image.path).copy(localImage.path);

        // 3. Sadece Yerel SQL Veritabanını güncelliyoruz
        // 'foto_yolu' sütununa artık internet linki değil, telefonun içindeki adresi yazıyoruz
        await DatabaseHelper.instance.stokFotoGuncelle(urun['id'], localImage.path);

        print("✅ Fotoğraf telefona kaydedildi ve SQL güncellendi: ${localImage.path}");

        // Arayüzü tazelemek için setState kullanmayı unutma
      } catch (e) {
        print("❌ SQL Kayıt Hatası: $e");
      }
    }
  }

  Future<void> _fotoGuncelle(Map<String, dynamic> urun) async {
    debugPrint("🚀 [DEBUG] _fotoGuncelle tetiklendi. Ürün ID: ${urun['id']}, Firebase ID: ${urun['firebase_id']}");

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(15),
              child: Text("FOTOĞRAF İŞLEMLERİ", style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt, color: Colors.blue),
              title: const Text("Yeni Fotoğraf Çek"),
              onTap: () {
                debugPrint("📸 [DEBUG] Yeni Fotoğraf Çek tıklandı.");
                Navigator.pop(context);
                _fotoCekVeKaydet(urun);
              },
            ),
            if ((urun['foto'] ?? urun['foto_yolu'] ?? "").toString().isNotEmpty)
              ListTile(
                leading: const Icon(Icons.delete_forever, color: Colors.red),
                title: const Text("Fotoğrafı Sil", style: TextStyle(color: Colors.red)),
                onTap: () {
                  debugPrint("🗑️ [DEBUG] Fotoğrafı Sil tıklandı.");
                  Navigator.pop(context);
                  _fotoSil(urun);
                },
              ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  Future<void> _fotoCekVeKaydet(Map<String, dynamic> urun) async {
    final ImagePicker picker = ImagePicker();
    debugPrint("📷 [DEBUG] Kamera açılıyor...");

    // Fotoğrafı çekiyoruz (Kaliteyi %50 yaparak hem hız hem yer kazanıyoruz)
    final XFile? image = await picker.pickImage(source: ImageSource.camera, imageQuality: 50);

    if (image != null) {
      debugPrint("✅ [DEBUG] Fotoğraf çekildi. Geçici yol: ${image.path}");

      // Yükleme ekranı gösterelim (User Experience için önemli abi)
      showDialog(context: context, barrierDismissible: false, builder: (c) => const Center(child: CircularProgressIndicator()));

      try {
        // --- 1. FIREBASE STORAGE'A YÜKLE ---
        // Kategori olarak Stokları seçiyoruz
        String? bulutUrl = await FirebaseFotoService().fotoYukle(
            FotoKategori.stoklar,
            File(image.path)
        );

        if (bulutUrl != null) {
          debugPrint("🌐 [DEBUG] Bulut URL Alındı: $bulutUrl");

          // --- 2. VERİTABANLARINI GÜNCELLE (SQL & Firestore) ---
          // Servis içinde hem yerel SQL'e hem de Firebase'e bu linki yazıyoruz
          int result = await DatabaseHelper.instance.stokFotoGuncelle(
              urun['id'],
              bulutUrl, // Artık dosya yolu değil, internet linki gidiyor
              firebaseId: urun['firebase_id']?.toString()
          );

          debugPrint("🏁 [DEBUG] Veritabanı güncellendi. Sonuç: $result");

          if (mounted) Navigator.pop(context); // Yükleme ekranını kapat
          await _verileriYukle(); // Listeyi tazele

          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Ürün fotoğrafı buluta yüklendi! ✅")));
        } else {
          throw "Fotoğraf buluta yüklenemedi!";
        }

      } catch (e) {
        if (mounted) Navigator.pop(context); // Hata varsa yüklemeyi kapat
        debugPrint("❌ [HATA] Fotoğraf kayıt aşamasında hata: $e");
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Hata: $e"), backgroundColor: Colors.red));
      }
    }
  }

  void _tumFotolariGoster() async {
    // 1. Verileri Çek
    List<Map<String, dynamic>> guncelStoklar;
    if (kIsWeb) {
      final snapshot = await FirebaseFirestore.instance.collection('stoklar').get();
      guncelStoklar = snapshot.docs.map((doc) => {...doc.data(), 'firebase_id': doc.id}).toList();
    } else {
      guncelStoklar = await DatabaseHelper.instance.stokListesiGetir();
    }

    // 2. Sadece Fotoğrafı Olanları Ayıkla
    final fotoluUrunler = guncelStoklar.where((s) {
      final yol = (s['foto'] ?? s['foto_yolu'] ?? s['fotoğraf'] ?? "").toString();
      return yol.isNotEmpty;
    }).toList();

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) => Column(
          children: [
            const SizedBox(height: 10),
            Container(width: 40, height: 5, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(10))),
            const Padding(
              padding: EdgeInsets.all(15),
              child: Text("STOK FOTOĞRAF ARŞİVİ", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            ),
            Expanded(
              child: fotoluUrunler.isEmpty
                  ? const Center(child: Text("Henüz fotoğraf eklenmemiş."))
                  : GridView.builder(
                controller: scrollController,
                padding: const EdgeInsets.all(10),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3, crossAxisSpacing: 8, mainAxisSpacing: 8),
                itemCount: fotoluUrunler.length,
                itemBuilder: (c, i) {
                  final urun = fotoluUrunler[i];
                  final String yol = (urun['foto'] ?? urun['foto_yolu'] ?? urun['fotoğraf'] ?? "").toString();

                  return Stack(
                    children: [
                      GestureDetector(
                        // BURASI DEĞİŞTİ: urun değişkenini 3. parametre olarak ekledik
                        onTap: () => _resmiBuyut(yol, "${urun['marka']} ${urun['model']}", urun),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: SizedBox.expand(
                            child: _resimGosterici(yol),
                          ),
                        ),
                      ),
                      // SİLME BUTONU
                      Positioned(
                        top: 2,
                        right: 2,
                        child: GestureDetector(
                          onTap: () => _fotoSil(urun),
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                            child: const Icon(Icons.close, color: Colors.white, size: 16),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

// --- YARDIMCI: WEB/MOBİL VE BASE64 UYUMLU RESİM MOTORU ---
  Widget _resimGosterici(String yol) {
    if (yol.contains('base64')) {
      String temizBase64 = yol.contains(',') ? yol.split(',').last : yol;
      return Image.memory(base64Decode(temizBase64), fit: BoxFit.cover, errorBuilder: (c, e, s) => const Icon(Icons.broken_image));
    } else if (yol.startsWith('http')) {
      return Image.network(yol, fit: BoxFit.cover, errorBuilder: (c, e, s) => const Icon(Icons.broken_image));
    } else {
      if (kIsWeb) return const Icon(Icons.cloud_off); // Web'de yerel dosya gösterilemez
      return Image.file(File(yol), fit: BoxFit.cover, errorBuilder: (c, e, s) => const Icon(Icons.broken_image));
    }
  }

// Parametre sayısını 3'e çıkardık: yol, baslik ve urunData
  void _resmiBuyut(String yol, String baslik, Map<String, dynamic> urunData) {
    showDialog(
      context: context,
      builder: (c) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Başlık kısmında ürünün markasını ve modelini gösteriyoruz
            AppBar(
              title: Text(baslik),
              backgroundColor: Colors.black,
              foregroundColor: Colors.white,
              shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(15))),
            ),
            // Resim alanı
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.6, // Ekranın %60'ını geçmesin
              ),
              child: InteractiveViewer(
                child: _resimGosterici(yol), // Daha önce yazdığımız resim motorunu kullanıyor
              ),
            ),
            // Alt kısma ürünün detayını ekleyebilirsin (İstersen)
            Padding(
              padding: const EdgeInsets.all(10),
              child: Text(
                "Şube: ${urunData['sube']} | Adet: ${urunData['adet']}",
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }

// --- EKSİK OLAN FOTO SİLME FONKSİYONU ---
  void _fotoSil(Map<String, dynamic> urun) async {
    bool? onay = await showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text("Fotoğraf Silinsin mi?"),
        content: const Text("Bu ürünün fotoğrafı kaldırılacaktır. Emin misiniz?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text("İPTAL")),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text("SİL", style: TextStyle(color: Colors.red))),
        ],
      ),
    );

    if (onay == true) {
      // Fotoğraf alanını hem SQL'de hem Firebase'de temizle
      if (!kIsWeb) {
        await DatabaseHelper.instance.database.then((db) => db.update('stoklar', {'foto': null, 'foto_yolu': null}, where: 'id = ?', whereArgs: [urun['id']]));
      }
      if (urun['firebase_id'] != null) {
        await FirebaseFirestore.instance.collection('stoklar').doc(urun['firebase_id']).update({'foto': null, 'foto_yolu': null});
      }
      _verileriYukle();
      Navigator.pop(context); // Modal'ı kapatıp tazele
    }
  }






  Widget _ozetKutu(String baslik, String deger, Color renk) {
    return Column(children: [
      Text(baslik, style: TextStyle(fontSize: 10, color: Colors.grey[600], fontWeight: FontWeight.bold)),
      Text(deger, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: renk)),
    ]);
  }

  Widget _ustButon(String metin, IconData ikon, Color renk, VoidCallback onTab) {
    return Expanded(child: GestureDetector(onTap: onTab, child: Container(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(color: renk, borderRadius: BorderRadius.circular(8)),
      child: Column(children: [
        Icon(ikon, color: Colors.white, size: 20),
        const SizedBox(height: 4),
        Text(metin, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
      ]),
    )));
  }

  Widget _fChip(String etiket, int index) {
    return ChoiceChip(
      label: Text(etiket),
      selected: _aktifFiltreSube == index,
      onSelected: (val) { setState(() { _aktifFiltreSube = index; _listeyiYenile(); }); },
    );
  }
}
