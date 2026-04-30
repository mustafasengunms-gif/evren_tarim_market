import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:printing/printing.dart';
import '../db/database_helper.dart';
import '../utils/pdf_helper.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:evren_tarim_market/db/database_helper.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb; //
import 'dart:io' as io; // File hatasını engellemek için 'as io' dedik[cite: 1]
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'dart:io' show File;


class BicerPaneli extends StatefulWidget {
  const BicerPaneli({super.key});

  @override
  State<BicerPaneli> createState() => _BicerPaneliState();
}

class _BicerPaneliState extends State<BicerPaneli> {
  List<Map<String, dynamic>> _isler = [];
  List<Map<String, dynamic>> _makineler = [];
  List<Map<String, dynamic>> _mazotlar = [];

  double bugdayFiyat = 250;
  double arpaFiyat = 230;
  double danelikMisirFiyat = 400;
  double soslukMisirFiyat = 450;
  double _toplamHasilat = 0;
  double _toplamAlacak = 0;
  double _toplamMazotBorcu = 0;
  final TextEditingController _aramaC = TextEditingController();
  String secilenSezon = "2026";
  // Eski hali: List<String> sezonListesi = ["2024", "2025", "2026", "2027"];
// Yeni (Otomatik) Hali:
  List<String> get sezonListesi {
    int suankiYil = DateTime.now().year; // 2026'daysak 2026'yı alır
    // 2024'ten başlasın, şu anki yılın 5 yıl sonrasına kadar gitsin
    return List.generate(10, (index) => (2024 + index).toString());
  }
  double _toplamBakimMasrafi = 0;


  final Color anaTuruncu = Colors.orange[900]!;








  Widget buildImage(String path) {
    if (kIsWeb) {
      return Image.network(path); // web
    } else {
      return Image.file(File(path)); // mobil
    }
  }


// Parametreyi 'Map' olarak bırakalım ki her türlü Map'i kabul etsin
  Future<void> _arkaPlandaBulutaGonder(Map isVerisi, double miktar) async {
    try {
      // Verileri kullanırken .toString() ve double.tryParse gibi yöntemlerle zorlayalım
      // Böylece tip ne olursa olsun uygulama patlamaz.

      await FirebaseFirestore.instance.collection('bicer_tahsilatlari').add({
        'ciftci_ad': isVerisi['ciftci_ad']?.toString() ?? "Bilinmeyen Çiftçi",
        'miktar': miktar,
        'tarih': DateTime.now().toString().substring(0, 10),
        'sezon': secilenSezon,
        'timestamp': FieldValue.serverTimestamp(),
      });

      if (isVerisi['firebase_id'] != null) {
        await FirebaseFirestore.instance
            .collection('bicer_isleri')
            .doc(isVerisi['firebase_id'].toString())
            .update({
          'odenen_miktar': FieldValue.increment(miktar),
        });
      }
      debugPrint("✅ Bulut senkronize edildi.");
    } catch (e) {
      debugPrint("⚠️ Arka plan hatası (Önemli değil): $e");
    }
  }

  // 👇 İŞTE TAM BURAYA YAPIŞTIR (Herhangi bir metodun dışında kalsın)
  Widget _resimGoster(String path) {
    if (kIsWeb) {
      return const Icon(Icons.image, size: 50, color: Colors.grey);
    } else {
      // io.File olarak çağırmayı unutma, en üstte 'import dart:io as io' olmalı
      return Image.file(io.File(path));
    }
  }

  @override
  void initState() {
    super.initState();
    // Uygulama ilk açıldığında o anki yılı seçili sezon yap
    secilenSezon = DateTime.now().year.toString();
    _verileriYukle();
  }

  Future<void> _verileriYukle() async {
    try {
      final islerRaw = await DatabaseHelper.instance.bicerIsleriGetir(secilenSezon);
      final allBicerler = await DatabaseHelper.instance.bicerListesi();
      final bicerlerRaw = allBicerler.where((m) => m['yil'] == secilenSezon).toList();
      final mazotlarRaw = await DatabaseHelper.instance.mazotListesiGetir(secilenSezon);

      double hasilat = 0;
      double alacak = 0;
      double mBorc = 0;
      double bakimMasraf = 0;

      // --- GRUPLANDIRMA İŞLEMİ ---
      Map<String, Map<String, dynamic>> gruplanmisMusteriler = {};
      for (var i in islerRaw) {
        String isim = i['ciftci_ad']?.toString() ?? "Bilinmeyen";
        double t = double.tryParse(i['toplam_tutar']?.toString() ?? '0') ?? 0;
        double o = double.tryParse(i['odenen_miktar']?.toString() ?? '0') ?? 0;
        double d = double.tryParse(i['dekar']?.toString() ?? '0') ?? 0; // Dekarı çek

        hasilat += t;
        alacak += (t - o);

        if (gruplanmisMusteriler.containsKey(isim)) {
          gruplanmisMusteriler[isim]!['toplam_tutar'] += t;
          gruplanmisMusteriler[isim]!['odenen_miktar'] += o;
          gruplanmisMusteriler[isim]!['dekar'] += d;
          gruplanmisMusteriler[isim]!['is_sayisi'] = (gruplanmisMusteriler[isim]!['is_sayisi'] ?? 1) + 1;
        } else {
          gruplanmisMusteriler[isim] = {
            'id': i['id'],
            'ciftci_ad': isim,
            'toplam_tutar': t,
            'odenen_miktar': o,
            'dekar': d,
            'urun_tipi': i['urun_tipi'],
            'sezon': i['sezon'],
            'is_sayisi': 1,
            // --- TAM BURAYA EKLE ---
            'tc': i['firebase_id'] ?? '', // SQLite'dan gelen firebase_id'yi (TC) buraya koyduk
          };
        }
      }

      for (var m in mazotlarRaw) {
        mBorc += (double.tryParse(m['tutar']?.toString() ?? '0') ?? 0) -
            (double.tryParse(m['odenen']?.toString() ?? '0') ?? 0);
      }

      // --- MAKİNELERİ HAZIRLAMA ---
      List<Map<String, dynamic>> guncelMakineler = [];
      for (var m in bicerlerRaw) {
        Map<String, dynamic> makine = Map.from(m);
        final yerelBakimlar = await DatabaseHelper.instance.bicerBakimlariGetir(makine['id']);
        double makineToplamMasraf = 0;
        for (var b in yerelBakimlar) {
          makineToplamMasraf += double.tryParse(b['tutar']?.toString() ?? '0') ?? 0;
        }
        bakimMasraf += makineToplamMasraf;
        makine['toplam_masraf'] = makineToplamMasraf;
        guncelMakineler.add(makine);
      }

      if (mounted) {
        setState(() {
          // İşleri Gruplanmış Listeye Atıyoruz
          _isler = gruplanmisMusteriler.values.toList();

          // --- KRİTİK EKSİK BURASIYDI, EKLENDİ ---
          _makineler = guncelMakineler;

          // Üst kartlardaki toplamlar
          _toplamHasilat = hasilat;
          _toplamAlacak = alacak;
          _toplamMazotBorcu = mBorc;
          _toplamBakimMasrafi = bakimMasraf; // Bakım kutusunu da günceller
        });
      }

      _arkaPlandaFirebaseGuncelle();

    } catch (e) {
      debugPrint("Kritik Yükleme Hatası: $e");
    }
  }

// Bu da Firebase'i bekletmeden güncelleyen yardımcı fonksiyon
  Future<void> _arkaPlandaFirebaseGuncelle() async {
    try {
      final cloudMakineler = await FirebaseFirestore.instance.collection('bicerler').get();
      for (var doc in cloudMakineler.docs) {
        var data = doc.data();
        await DatabaseHelper.instance.bicerEkle({
          'id': int.tryParse(doc.id) ?? doc.id.hashCode,
          'marka': data['marka'] ?? "Bilinmiyor",
          'model': data['model'] ?? "",
          'plaka': data['plaka'] ?? "",
          'yil': data['yil'] ?? "",
          'durum': data['durum'] ?? 'AKTİF',
          'firebase_id': doc.id,
        });
      }
    } catch (e) {
      debugPrint("Firebase Güncelleme Hatası: $e");
    }
  }

  Widget _giderKarti(Map g, bool isMazot) {
    return Card(
      color: isMazot ? Colors.orange[50] : Colors.red[50],
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: ListTile(
        leading: Icon(isMazot ? Icons.gas_meter : Icons.settings, color: isMazot ? Colors.orange : Colors.red),
        title: Text(isMazot ? "${g['petrol_adi']} - Mazot" : "${g['parca_adi']} - Bakım"),
        subtitle: Text("${g['tarih']} | ${isMazot ? g['litre'].toString() + ' Lt' : ''}"),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text("${formatPara(g['tutar'])} TL", style: const TextStyle(fontWeight: FontWeight.bold)),
            IconButton(
              icon: const Icon(Icons.delete_sweep, color: Colors.red),
              onPressed: () => _giderSilOnay(g['id'], isMazot),
            ),
          ],
        ),
      ),
    );
  }


  void _giderSilOnay(int id, bool isMazot, {String? fId}) { // fId eklendi
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text("KAYIT SİLİNECEK"),
        content: Text("Bu ${isMazot ? 'mazot' : 'bakım'} kaydı tamamen silinecek. Emin misiniz?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text("İPTAL")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              if (isMazot) {
                // BURAYA DİKKAT: Artık _mazotlar[index] demiyoruz!
                // Doğrudan dışarıdan gelen id ve fId'yi kullanıyoruz.
                await DatabaseHelper.instance.mazotSil(id, firebaseId: fId);
              } else {
                await DatabaseHelper.instance.bicerBakimSil(id);
              }
              Navigator.pop(c);
              _verileriYukle();
            },
            child: const Text("SİL", style: TextStyle(color: Colors.white)),
          )
        ],
      ),
    );
  }


  void _pdfOnizlemeGoster(BuildContext context, {String? ciftciAdi}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => Scaffold(
        appBar: AppBar(
          title: Text(ciftciAdi == null ? "Sezon Raporu" : "$ciftciAdi Ekstresi"),
          backgroundColor: anaTuruncu,
          actions: [
            IconButton(
              icon: const Icon(Icons.share),
              onPressed: () => _pdfOlusturVePaylas(ciftciAdi: ciftciAdi),
            )
          ],
        ),
        body: PdfPreview(
          build: (format) => _pdfGenelRaporBuild(ciftciAdi: ciftciAdi),
          allowPrinting: true,
          allowSharing: true,
        ),
      ),
    );
  }

  Future<Uint8List> _pdfGenelRaporBuild({String? ciftciAdi}) async {
    final pdf = pw.Document();
    final fontData = await rootBundle.load("assets/fonts/arial.ttf").catchError((e) => rootBundle.load("assets/fonts/Roboto-Regular.ttf"));
    final ttf = pw.Font.ttf(fontData);

    // 1. VERİLERİ FİLTRELEYEREK ÇEK
    final tumIsler = await DatabaseHelper.instance.bicerIsleriGetir(secilenSezon);

    // Eğer çiftçi adı varsa sadece onun işlerini filtrele
    final raporlukIsler = ciftciAdi == null
        ? tumIsler
        : tumIsler.where((i) => i['ciftci_ad'] == ciftciAdi).toList();

    double toplamGelir = 0;
    double toplamTahsilat = 0;

    // 2. GELİR TABLOSU VERİSİ (Çiftçiye göre veya Genel)
    final gelirTablosu = raporlukIsler.map((i) {
      toplamGelir += (i['toplam_tutar'] ?? 0).toDouble();
      toplamTahsilat += (i['odenen_miktar'] ?? 0).toDouble();
      return [i['tarih'], i['ciftci_ad'], "${i['dekar']} Da", "${formatPara(i['toplam_tutar'])} TL"];
    }).toList();

    // --- HATAYI ÇÖZEN KISIM BURASI (Tanımlamaları dışarı alıyoruz) ---
    List<List<String>> mazotTablosu = [];
    List<List<String>> bakimTablosu = [];
    double toplamMazotGideri = 0;
    double toplamBakimGideri = 0;

    if (ciftciAdi == null) {
      final tumMazotlar = await DatabaseHelper.instance.mazotListesiGetir(secilenSezon);

      // map işlemini listeye çevirirken tipini sağlama alıyoruz
      mazotTablosu = tumMazotlar.map((m) {
        toplamMazotGideri += (m['tutar'] ?? 0).toDouble();
        return [
          m['tarih']?.toString() ?? "",
          m['petrol_adi']?.toString() ?? "",
          "${m['litre']} Lt",
          "${formatPara(m['tutar'])} TL"
        ];
      }).toList();

      // Makine bakımlarını da buraya ekliyoruz...
      for (var m in _makineler) {
        final bakimlar = await DatabaseHelper.instance.bicerBakimlariGetir(m['id']);
        for (var b in bakimlar) {
          toplamBakimGideri += (b['tutar'] ?? 0).toDouble();
          bakimTablosu.add([
            "${m['marka']} ${m['model']}",
            b['tarih']?.toString() ?? "",
            b['parca_adi']?.toString() ?? "",
            "${formatPara(b['tutar'])} TL"
          ]);
        }
      }
    }

    pdf.addPage(
      pw.MultiPage(
        theme: pw.ThemeData.withFont(base: ttf, bold: ttf),
        pageFormat: PdfPageFormat.a4,
        build: (context) => [
          pw.Header(level: 0, child: pw.Text(ciftciAdi == null
              ? "EVREN TARIM - 2026 GENEL SEZON RAPORU"
              : "EVREN TARIM - MÜŞTERİ EKSTRESİ")),
          if (ciftciAdi != null) pw.Text("Müşteri: $ciftciAdi", style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
          pw.Divider(thickness: 2, color: PdfColors.orange900),

          // --- BÖLÜM 1: HASAT GELİRLERİ (Her iki raporda da var) ---
          pw.SizedBox(height: 10),
          pw.Text(ciftciAdi == null ? "1. TÜM HASAT GELİRLERİ" : "YAPILAN İŞLEMLER",
              style: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.blue900)),
          pw.TableHelper.fromTextArray(
            headers: ['Tarih', 'Ciftci', 'Alan', 'Tutar'],
            data: gelirTablosu,
            headerStyle: pw.TextStyle(color: PdfColors.white),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.blue900),
          ),

          // --- SADECE GENEL RAPORDA GÖRÜNECEK KISIMLAR ---
          if (ciftciAdi == null) ...[
            pw.SizedBox(height: 20),
            pw.Text("2. MAZOT GİDER DETAYLARI", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.orange900)),
            pw.TableHelper.fromTextArray(
              headers: ['Tarih', 'Istasyon', 'Miktar', 'Tutar'],
              data: mazotTablosu,
              headerStyle: pw.TextStyle(color: PdfColors.white),
              headerDecoration: const pw.BoxDecoration(color: PdfColors.orange900),
            ),
            pw.SizedBox(height: 20),
            pw.Text("3. MAKİNE BAKIM GİDERLERİ", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.red900)),
            pw.TableHelper.fromTextArray(
              headers: ['Makine', 'Tarih', 'Islem', 'Tutar'],
              data: bakimTablosu,
              headerStyle: pw.TextStyle(color: PdfColors.white),
              headerDecoration: const pw.BoxDecoration(color: PdfColors.red900),
            ),
          ],

          pw.Divider(thickness: 2),

          // --- ÖZET PANELİ (Rapora göre değişir) ---
          pw.SizedBox(height: 20),
          pw.Container(
            padding: const pw.EdgeInsets.all(10),
            decoration: pw.BoxDecoration(border: pw.Border.all(width: 2), color: PdfColors.grey100),
            child: pw.Column(
              children: ciftciAdi == null
                  ? [ // GENEL ÖZET
                _pdfSatir("TOPLAM HASILAT:", "${formatPara(toplamGelir)} TL", PdfColors.blue900, buyuk: true),
                _pdfSatir("TOPLAM MAZOT GİDERİ:", "-${formatPara(toplamMazotGideri)} TL", PdfColors.orange900),
                _pdfSatir("TOPLAM MAKİNE MASRAFI:", "-${formatPara(toplamBakimGideri)} TL", PdfColors.red900),
                pw.Divider(),
                _pdfSatir("NET SEZON KARI:", "${formatPara(toplamGelir - (toplamMazotGideri + toplamBakimGideri))} TL", PdfColors.green900, buyuk: true),
              ]
                  : [ // MÜŞTERİ ÖZETİ
                _pdfSatir("TOPLAM İŞ TUTARI:", "${formatPara(toplamGelir)} TL", PdfColors.black, buyuk: true),
                _pdfSatir("TOPLAM YAPILAN ÖDEME:", "${formatPara(toplamTahsilat)} TL", PdfColors.green900),
                pw.Divider(),
                _pdfSatir("KALAN BORÇ DURUMU:", "${formatPara(toplamGelir - toplamTahsilat)} TL", PdfColors.red900, buyuk: true),
              ],
            ),
          ),
        ],
      ),
    );
    return pdf.save();
  }
  void _tahsilatYapDialog(Map isVerisi) {
    final tutarC = TextEditingController();
    final tarihC = TextEditingController(text: DateTime.now().toString().substring(0, 10));

    showDialog(
      context: context,
      barrierDismissible: false, // İşlem bitmeden dışarı tıklayıp kapatamasın
      builder: (c) => AlertDialog(
        title: Text("${isVerisi['ciftci_ad']} - ÖDEME AL"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Kalan borcu anlık gösterelim
            Text(
              "Mevcut Borç: ${formatPara((isVerisi['toplam_tutar'] ?? 0) - (isVerisi['odenen_miktar'] ?? 0))} TL",
              style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            _input(tutarC, "Alınan Nakit", Icons.money, tip: TextInputType.number),
            _input(tarihC, "Ödeme Tarihi", Icons.calendar_today),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text("İPTAL")),
          // ... diyaloğun diğer kısımları (TextEditingController vs)
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            onPressed: () async {
              // BURADAN BAŞLIYOR:

              double yeniGelenPara = double.tryParse(tutarC.text) ?? 0;
              if (yeniGelenPara <= 0) return;

              // Pencereyi anında kapat ki kullanıcı "dondu mu bu" demesin
              Navigator.of(c).pop();

              try {
                print("📄 [DEBUG 5] Gelen veri: $isVerisi");

                // Logda 'id_firebase' gördüğümüz için onu da ekledik:
                var hamId = isVerisi['id'] ?? isVerisi['id_firebase'] ?? isVerisi['İD'];
                print("🆔 [DEBUG 6] Tespit edilen ID: $hamId");

                if (hamId == null) {
                  print("❌ [DEBUG 7] ID BULUNAMADI! Anahtarlar: ${isVerisi.keys.toList()}");
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("Hata: İş ID bulunamadı!"), backgroundColor: Colors.red),
                  );
                  return;
                }

                int isId = int.parse(hamId.toString());

                // 1. SQLite'a tahsilatı ekle
                await DatabaseHelper.instance.tahsilatEkle({
                  'is_id': isId,
                  'ciftci_ad': isVerisi['ciftci_ad']?.toString() ?? "Bilinmeyen",
                  'miktar': yeniGelenPara,
                  'tarih': tarihC.text,
                  'sezon': isVerisi['sezon'] ?? "2026",
                  'odeme_tipi': "NAKİT",
                });

                // 2. Biçer işini güncelle (odenen_miktar'ı artır)
                await DatabaseHelper.instance.bicerIsGuncelle(isId, {
                  'odenen_miktar': (isVerisi['odenen_miktar'] ?? 0) + yeniGelenPara,
                });

                // 3. Arayüzü tazele
                _verileriYukle();

                // 4. Buluta gönder (varsa fonksiyonun)
                _arkaPlandaBulutaGonder(isVerisi, yeniGelenPara);

                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Ödeme başarıyla kaydedildi."), backgroundColor: Colors.green),
                );

              } catch (e) {
                print("🔥 HATA: $e");
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text("İşlem başarısız: $e"), backgroundColor: Colors.red),
                );
              }
            },
            child: const Text("ÖDEMEYİ KAYDET", style: TextStyle(color: Colors.white)),
          )
        ],
      ),
    );
  }

  // PDF İçin Satır Yardımcısı
  pw.Widget _pdfSatir(String etiket, String deger, PdfColor renk, {bool buyuk = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(etiket, style: pw.TextStyle(fontSize: buyuk ? 12 : 10, fontWeight: buyuk ? pw.FontWeight.bold : null)),
          pw.Text(deger, style: pw.TextStyle(fontSize: buyuk ? 12 : 10, color: renk, fontWeight: pw.FontWeight.bold)),
        ],
      ),
    );
  }

  Future<void> _pdfOlusturVePaylas({String? ciftciAdi}) async {
    final bytes = await _pdfGenelRaporBuild(ciftciAdi: ciftciAdi);
    final dir = await getTemporaryDirectory();
    final file = File("${dir.path}/rapor.pdf");
    await file.writeAsBytes(bytes);
    await Share.shareXFiles([XFile(file.path)], text: "Hasat Raporu");
  }

  // --- UI BİLEŞENLERİ ---

  Widget _ustRaporKartlari() {
    return Container(
      padding: const EdgeInsets.all(8),
      child: Row(
        children: [
          _raporKutu("HASILAT", _toplamHasilat, Colors.blue),
          _raporKutu("ALACAK", _toplamAlacak, Colors.red),
          _raporKutu("MAZOT", _toplamMazotBorcu, Colors.black),
          _raporKutu("BAKIM", _toplamBakimMasrafi, Colors.orange[900]!), // Yeni kutu burası
        ],
      ),
    );
  }

  Widget _raporKutu(String baslik, double deger, Color renk) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.all(1),
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: renk, width: 1.5),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Column(
          children: [
            Text(baslik, style: TextStyle(fontSize: 9, color: renk, fontWeight: FontWeight.bold)),
            const SizedBox(height: 2),
            FittedBox( // Tutar uzun gelirse kutudan taşmasın diye
              fit: BoxFit.scaleDown,
              child: Text("${formatPara(deger)} TL", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _hizliMenu() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _hizliButon("MAKİNELER", Icons.agriculture, Colors.blue, () => _makinelerDialog()),
          _hizliButon("ÇİFTÇİLER", Icons.people, Colors.green, () => _ciftciListesiDialog()),
          _hizliButon("MAZOT", Icons.gas_meter, Colors.orange, () => _mazotTakibiGoster()),
          _hizliButon("RAPOR", Icons.picture_as_pdf, Colors.red, () => _pdfOnizlemeGoster(context)),
          _hizliButon("AYARLAR", Icons.settings, Colors.black, () => _ayarlarDialog()),
          _hizliButon("ARIZA", Icons.warning_amber_rounded, Colors.red[900]!, () => _arizaKodlari()),
        ],
      ),
    );
  }

  // --- SENİN İSTEDİĞİN O KÜÇÜK GÖRSEL LİSTE BURASI ---
  Widget _makineListesiPaneli() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 5),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("AKTİF MAKİNELER",
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.blueGrey)),
              // Hızlı ekleme butonu
              InkWell(
                onTap: () => _makineEkleDialog(),
                child: const Row(
                  children: [
                    Icon(Icons.add_circle, color: Colors.green, size: 18),
                    SizedBox(width: 4),
                    Text("YENİ", style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 12)),
                  ],
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 100,
          child: _makineler.isEmpty
              ? const Center(child: Text("Kayıtlı makine yok.", style: TextStyle(fontSize: 12, color: Colors.grey)))
              : ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.only(left: 15),
            itemCount: _makineler.length,
            itemBuilder: (context, index) {
              final m = _makineler[index];
              double masraf = (m['toplam_masraf'] as num? ?? 0).toDouble();
              return Container(
                width: 150,
                margin: const EdgeInsets.only(right: 12, bottom: 10, top: 5),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.blue.withOpacity(0.2)),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4)],
                ),
                child: ListTile(
                  onTap: () => _makinelerDialog(), // Tıklayınca detaylı listeyi açar
                  contentPadding: const EdgeInsets.symmetric(horizontal: 10),
                  title: Text("${m['marka']}",
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      overflow: TextOverflow.ellipsis),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("${m['plaka']}", style: const TextStyle(fontSize: 10)),
                      const SizedBox(height: 4),
                      Text("${formatPara(masraf)} TL",
                          style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 11)),
                      // Kartın içine Plaka'nın hemen altına ekleyebilirsin:
                      Text("Saat: ${m['calisma_saati'] ?? '0'} H",
                          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        const Divider(indent: 15, endIndent: 15),
      ],
    );
  }

  Future<void> _makineKaydet(Map<String, dynamic> makineVerisi) async {
    try {
      // 1. Yerel SQLite Kaydı (Sütun: calisma_saati)
      int yeniId = await DatabaseHelper.instance.bicerEkle({
        'marka': makineVerisi['marka'],
        'model': makineVerisi['model'],
        'plaka': makineVerisi['plaka'],
        'yil': makineVerisi['yil'],
        'durum': makineVerisi['durum'],
        'calisma_saati': makineVerisi['calisma_saati'], // RESİMDEKİ SÜTUN
      });

      // 2. Bulut Senkronizasyonu
      await FirebaseFirestore.instance.collection('bicerler').doc(yeniId.toString()).set({
        'id': yeniId,
        'marka': makineVerisi['marka'],
        'model': makineVerisi['model'],
        'plaka': makineVerisi['plaka'],
        'yil': makineVerisi['yil'],
        'durum': makineVerisi['durum'],
        'calisma_saati': makineVerisi['calisma_saati'],
        'guncelleme': FieldValue.serverTimestamp(),
      });

      _verileriYukle(); // Listeyi yenile
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Makine ve Çalışma Saati Kaydedildi")));
    } catch (e) {
      debugPrint("SQL/Firebase Hatası: $e");
    }
  }

  void _makineEkleDialog() {
    final markaC = TextEditingController();
    final modelC = TextEditingController();
    final plakaC = TextEditingController();
    final saatC = TextEditingController(); // ÇALIŞMA SAATİ İÇİN

    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text("YENİ MAKİNE VE SAAT TANIMLA"),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _input(markaC, "Marka", Icons.agriculture),
              _input(modelC, "Model", Icons.settings),
              _input(plakaC, "Plaka", Icons.branding_watermark),
              _input(saatC, "Çalışma Saati (H)", Icons.timer, tip: TextInputType.number), // SAAT GİRİŞİ
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text("İPTAL")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            onPressed: () {
              _makineKaydet({
                'marka': markaC.text.toUpperCase(),
                'model': modelC.text.toUpperCase(),
                'plaka': plakaC.text.toUpperCase(),
                'calisma_saati': double.tryParse(saatC.text) ?? 0.0, // SAATİ BURADAN ALIYORUZ
                'yil': secilenSezon,
                'durum': 'AKTİF'
              });
              Navigator.pop(c);
            },
            child: const Text("MAKİNEYİ KAYDET", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }


  Widget _hizliButon(String t, IconData i, Color r, VoidCallback g) {
    return InkWell(
      onTap: g,
      child: Column(
        children: [
          Icon(i, color: r, size: 28),
          const SizedBox(height: 4),
          Text(t, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _isKarti(Map i) {
    double toplam = (i['toplam_tutar'] ?? 0).toDouble();
    double odenen = (i['odenen_miktar'] ?? 0).toDouble();
    double borc = toplam - odenen;
    int adet = i['kayit_sayisi'] ?? 1;

    return Card(
      elevation: 3,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: Column(
        children: [
          ListTile(
            leading: CircleAvatar(
              backgroundColor: borc > 0 ? Colors.red[100] : Colors.green[100],
              child: Icon(
                borc > 0 ? Icons.priority_high : Icons.check,
                color: borc > 0 ? Colors.red : Colors.green,
              ),
            ),
            title: Text(
              "${i['ciftci_ad']}",
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            subtitle: Text(
              adet > 1 ? "$adet Farklı İş Kaydı" : "${i['urun_tipi']} | ${i['dekar']} Da",
            ),
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text("${formatPara(toplam)} TL",
                    style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
                Text(borc > 0 ? "Kalan: ${formatPara(borc)} TL" : "ÖDENDİ",
                    style: TextStyle(color: borc > 0 ? Colors.red : Colors.green, fontSize: 11)),
              ],
            ),
          ),
          const Divider(height: 1, indent: 15, endIndent: 15),

          // --- YENİ EKLENEN ALT BUTONLAR ---
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                // EKSTRE BUTONU
                _altButon(
                  ikon: Icons.description_outlined,
                  renk: Colors.orange[800]!,
                  etiket: "Ekstre",
                  onTap: () => bicerMusteriEkstreGoster(i['ciftci_ad']),
                ),
                _altButon(
                  ikon: Icons.camera_alt_outlined,
                  renk: Colors.blueGrey,
                  etiket: "Foto",
                  onTap: () => _fotoSecimMenusu(i, context), // Yanına context'i de ekledik
                ),
                // GÜNCELLE BUTONU
                _altButon(
                  ikon: Icons.edit_outlined,
                  renk: Colors.blue,
                  etiket: "Düzenle",
                  onTap: () => _isEkleDialog(eskiVeri: i),
                ),
                // SİL BUTONU
                // _isKarti içindeki SİL BUTONU kısmına bunu yaz:
                _altButon(
                  ikon: Icons.delete_outline,
                  renk: Colors.red,
                  etiket: "Sil",
                  onTap: () => _isSilOnay(i['id'], i['ciftci_ad']), // Müşteriyi komple silen fonksiyona gider
                ),
                // ÖDEME AL BUTONU (Hızlı Erişim)
                if (borc > 0)
                  _altButon(
                    ikon: Icons.add_circle_outline,
                    renk: Colors.green,
                    etiket: "Ödeme",
                    onTap: () => _tahsilatYapDialog(i),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _fotoSecimMenusu(Map isVerisi, BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (c) => SafeArea(
        child: Wrap(
          children: [
            const ListTile(title: Text("FOTOĞRAF KAYNAĞI SEÇİN", style: TextStyle(fontWeight: FontWeight.bold))),
            ListTile(
              leading: const Icon(Icons.camera_alt, color: Colors.blue),
              title: const Text('Kamerayı Aç'),
              onTap: () {
                Navigator.pop(c);
                _fotoIsle(isVerisi, ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library, color: Colors.green),
              title: const Text('Galeriden Seç'),
              onTap: () {
                Navigator.pop(c);
                _fotoIsle(isVerisi, ImageSource.gallery);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _fotoIsle(Map isVerisi, ImageSource kaynak) async {
    final ImagePicker picker = ImagePicker();

    try {
      // 1. Fotoğrafı çek/seç
      final XFile? image = await picker.pickImage(source: kaynak, imageQuality: 50);

      if (image != null) {
        // 2. Müşteriyi yakalamak için TC veya Firebase ID'yi kontrol et
        // Senin gruplanmisMusteriler Map'inden gelen 'tc' anahtarı burada kritik
        var tcNo = isVerisi['tc'] ?? isVerisi['firebase_id'] ?? isVerisi['TC'];

        if (tcNo == null || tcNo.toString().isEmpty || tcNo.toString() == "null") {
          print("❌ HATA: Müşteri TC/ID bulunamadı. Veri: $isVerisi");
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text("Müşteri bilgisi eksik, fotoğraf rehbere kaydedilemedi!"),
                backgroundColor: Colors.red
            ),
          );
          return;
        }

        // 3. DatabaseHelper'daki o çift taraflı (Hem Müşteri hem İşler) fonksiyonu çağır
        await DatabaseHelper.instance.bicerFaturaGorseliEkleTC(tcNo.toString(), File(image.path));

        if (mounted) {
          // Müşterinin adını da ekleyelim ki kime kaydedildiğini kullanıcı görsün
          String ciftci = isVerisi['ciftci_ad'] ?? "Müşteri";

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("$ciftci profili ve fatura kayıtları güncellendi."),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 2),
            ),
          );

          // 4. Arayüzü tazele (Listede fatura ikonları veya resimler gözüksün)
          _verileriYukle();
        }
      }
    } catch (e) {
      debugPrint("📸 Foto İşlem Hatası: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Fotoğraf kaydedilirken hata oluştu: $e")),
        );
      }
    }
  }


  Widget _kucukMakineListesi() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(left: 15, top: 10, bottom: 5),
          child: Text("MAKİNE DURUMU", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.blueGrey)),
        ),
        SizedBox(
          height: 100,
          child: _makineler.isEmpty
              ? const Center(child: Text("Kayıtlı Makine Yok"))
              : ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            itemCount: _makineler.length,
            itemBuilder: (context, i) {
              final m = _makineler[i];
              double masraf = (m['toplam_masraf'] as num? ?? 0).toDouble();
              return Container(
                width: 150,
                margin: const EdgeInsets.only(right: 10, bottom: 5),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.blue.shade100),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4)],
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("${m['marka']} ${m['model']}", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12), maxLines: 1),
                    Text(m['plaka'] ?? "-", style: const TextStyle(fontSize: 10, color: Colors.grey)),
                    const Spacer(),
                    Text("${formatPara(masraf)} TL", style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 11)),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

// Alt butonlar için yardımcı küçük widget
  Widget _altButon({required IconData ikon, required Color renk, required String etiket, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          children: [
            Icon(ikon, color: renk, size: 22),
            const SizedBox(height: 2),
            Text(etiket, style: TextStyle(color: renk, fontSize: 10, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  void _isSilOnay(int id, String isim) {
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text("TÜM KAYITLAR SİLİNSİN Mİ?"),
        content: Text("$isim adına kayıtlı bu iş ve bağlı tüm ödemeler silinecek!"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text("VAZGEÇ")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              await DatabaseHelper.instance.musteriyiKompleSil(id);
              Navigator.pop(c);
              _verileriYukle();
            },
            child: const Text("KOMPLE SİL"),
          )
        ],
      ),
    );
  }

  void _ekstredekiSatiriSil(Map h) {
    bool isHasat = h.containsKey('urun_tipi');

    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text("BU HAREKET SİLİNSİN Mİ?"),
        content: const Text("Sadece bu satır silinecek. Borç durumu yeniden hesaplanacak."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text("İPTAL")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              await DatabaseHelper.instance.ekstreSatirSil(
                id: h['id'],
                isHasat: isHasat,
                bagliIsId: h['is_id'],
                miktar: double.tryParse(h['miktar']?.toString() ?? '0'),
              );
              Navigator.pop(c); // Onay kutusunu kapat
              Navigator.pop(context); // Ekstreyi kapat
              _verileriYukle(); // Ana sayfayı tazele
            },
            child: const Text("SATIRI SİL"),
          )
        ],
      ),
    );
  }

  // --- BİÇER MÜŞTERİ EKSTRE FONKSİYONU ---
  Future<void> bicerMusteriEkstreGoster(String isim) async {
    try {
      final isler = await DatabaseHelper.instance.musteriHareketleriGetir(isim);
      final odemeler = await DatabaseHelper.instance.tahsilatListesiGetir(isim);

      List<Map<String, dynamic>> tumHareketler = [];
      if (isler != null) tumHareketler.addAll(isler);
      if (odemeler != null) tumHareketler.addAll(odemeler);

      tumHareketler.sort((a, b) {
        String tarihA = a['tarih']?.toString() ?? "";
        String tarihB = b['tarih']?.toString() ?? "";
        return tarihB.compareTo(tarihA);
      });

      if (!mounted) return;

      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (context) => DraggableScrollableSheet(
          initialChildSize: 0.9,
          maxChildSize: 0.95,
          minChildSize: 0.5,
          expand: false,
          builder: (_, controller) => Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Container(width: 40, height: 5, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(10))),
                const SizedBox(height: 10),
                Text("$isim - BİÇER MÜŞTERİ EKSTRESİ", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.orange)),
                const Divider(),
                Expanded(
                  child: tumHareketler.isEmpty
                      ? const Center(child: Text("Kayıt bulunamadı."))
                      : ListView.builder(
                    controller: controller,
                    itemCount: tumHareketler.length,
                    itemBuilder: (context, index) {
                      final h = tumHareketler[index];
                      bool isHasat = h.containsKey('urun_tipi');

                      return Card(
                        elevation: 0,
                        color: isHasat ? Colors.white : Colors.green[50],
                        shape: RoundedRectangleBorder(
                            side: BorderSide(color: Colors.grey[200]!),
                            borderRadius: BorderRadius.circular(10)),
                        child: Column(
                          children: [
                            ListTile(
                              leading: Icon(
                                  isHasat ? Icons.agriculture : Icons.payments,
                                  color: isHasat ? Colors.orange : Colors.green),
                              title: Text(isHasat ? "${h['urun_tipi']} HASADI" : "NAKİT TAHSİLAT"),
                              subtitle: Text("${h['tarih']} ${isHasat ? '| ' + h['dekar'].toString() + ' Da' : ''}"),
                              trailing: Text(
                                "${isHasat ? '+' : '-'}${formatPara(isHasat ? h['toplam_tutar'] : h['miktar'])} TL",
                                style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: isHasat ? Colors.red : Colors.green[800]),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8.0, right: 8.0),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  TextButton.icon(
                                    icon: const Icon(Icons.edit, size: 16, color: Colors.blue),
                                    label: const Text("Düzenle", style: TextStyle(fontSize: 12, color: Colors.blue)),
                                    onPressed: () {
                                      Navigator.pop(context);
                                      if (isHasat) {
                                        _isEkleDialog(eskiVeri: h);
                                      }
                                    },
                                  ),
                                  const SizedBox(width: 8),
                                  TextButton.icon(
                                    icon: const Icon(Icons.delete_outline, size: 16, color: Colors.red),
                                    label: const Text("Sil", style: TextStyle(fontSize: 12, color: Colors.red)),
                                    onPressed: () => _hareketSilOnay(h, isHasat), // Aşağıdaki tetikleyiciye gidiyor
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
                // Özet Panelini de buraya ekledik
                _ekstreOzetPaneli(isler, odemeler),
              ],
            ),
          ),
        ),
      );
    } catch (e) {
      debugPrint("Ekstre Hatası: $e");
    }
  }

// EKSTRE İÇİNDEKİ SİLME ONAYI
  void _hareketSilOnay(Map h, bool isHasat) {
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text("KAYIT SİLİNECEK"),
        content: const Text("Bu hareketi silmek istediğinize emin misiniz?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text("VAZGEÇ")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              // CIMBIZ SİLME: DatabaseHelper'daki yeni fonksiyona gider
              await DatabaseHelper.instance.ekstreSatirSil(
                id: h['id'],
                isHasat: isHasat,
                bagliIsId: h['is_id'], // Tahsilat ise bağlı olduğu işin ID'si
                miktar: double.tryParse((h['miktar'] ?? 0).toString()),
              );
              Navigator.pop(c); // Diyaloğu kapat
              Navigator.pop(context); // Ekstreyi kapat
              _verileriYukle(); // Ana sayfayı yenile
            },
            child: const Text("SİL"),
          )
        ],
      ),
    );
  }

  // EKSTRE ALTINDAKİ TOPLAM TABLOSU
  Widget _ekstreOzetPaneli(List<Map<String, dynamic>>? isler, List<Map<String, dynamic>>? odemeler) {
    double toplamIs = 0;
    double toplamOdeme = 0;
    if (isler != null) {
      for (var i in isler) { toplamIs += double.tryParse(i['toplam_tutar']?.toString() ?? '0') ?? 0; }
    }
    if (odemeler != null) {
      for (var o in odemeler) { toplamOdeme += double.tryParse(o['miktar']?.toString() ?? '0') ?? 0; }
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(10)),
      child: Column(
        children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text("Toplam İş Tutarı:"), Text("${formatPara(toplamIs)} TL", style: const TextStyle(fontWeight: FontWeight.bold))]),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text("Alınan Ödeme:"), Text("${formatPara(toplamOdeme)} TL", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green))]),
          const Divider(),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text("Kalan Borç:", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)), Text("${formatPara(toplamIs - toplamOdeme)} TL", style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.red))]),
        ],
      ),
    );
  }

  void _kompleMusteriSil(String isim) {
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text("TÜM KAYITLAR SİLİNSİN Mİ?"),
        content: Text("$isim adına kayıtlı TÜM hasat ve ödeme geçmişi silinecek. Emin misiniz?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text("VAZGEÇ")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              await DatabaseHelper.instance.tumMusteriKayitlariniTemizle(isim);
              Navigator.pop(c);
              _verileriYukle();
            },
            child: const Text("EVET, KOMPLE SİL"),
          )
        ],
      ),
    );
  }

  void _ekstreSatirSil(Map h) {
    bool isHasat = h.containsKey('urun_tipi');

    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text("BU KAYIT SİLİNSİN Mİ?"),
        content: const Text("Sadece bu işlem silinecek ve borç yeniden hesaplanacak."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text("İPTAL")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              await DatabaseHelper.instance.tekilHareketSil(
                id: h['id'],
                isHasat: isHasat,
                bagliIsId: h['is_id'],
                miktar: double.tryParse(h['miktar']?.toString() ?? '0'),
              );
              Navigator.pop(c); // Onay kutusunu kapat
              Navigator.pop(context); // Ekstreyi kapat
              _verileriYukle(); // Listeyi güncelle
            },
            child: const Text("SİL"),
          )
        ],
      ),
    );
  }



  void _ciftciListesiDialog() async {
    final ciftciler = await DatabaseHelper.instance.ciftciListesiGetir();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true, // Klavye açılırsa diye tam ekran desteği
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (c) => Container(
        padding: const EdgeInsets.all(16),
        height: MediaQuery.of(context).size.height * 0.8, // Listeyi daha geniş gör
        child: Column(
          children: [
            // --- ÜST BAŞLIK VE EKLE BUTONU ---
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text("ÇİFTÇİ REHBERİ", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(c);
                    _ciftciEkleDialog(); // Çiftçi ekleme diyaloğunu çağırır
                  },
                  icon: const Icon(Icons.person_add),
                  label: const Text("Yeni Ekle"),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                )
              ],
            ),
            const Text("İsme tıkla: Ekstre | Sola kaydır: Sil", style: TextStyle(fontSize: 10, color: Colors.grey)),
            const Divider(),

            Expanded(
              child: ListView.builder(
                itemCount: ciftciler.length,
                itemBuilder: (context, index) {
                  final cf = ciftciler[index];
                  return Dismissible(
                    key: Key(cf['id'].toString()),
                    direction: DismissDirection.endToStart, // Sadece sola kaydırınca siler
                    background: Container(
                      color: Colors.red,
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.only(right: 20),
                      child: const Icon(Icons.delete, color: Colors.white),
                    ),
                    confirmDismiss: (dir) async {
                      // Sola kaydırınca direkt silmek yerine onay sorar
                      _ciftciSilOnay(cf['id'], cf['ad_soyad']);
                      return false;
                    },
                    child: ListTile(
                      leading: const CircleAvatar(child: Icon(Icons.person)),
                      title: Text(cf['ad_soyad']),
                      subtitle: Text(cf['telefon'] ?? "Telefon Yok"),
                      trailing: IconButton(
                        icon: const Icon(Icons.picture_as_pdf, color: Colors.red),
                        onPressed: () {
                          Navigator.pop(context);
                          _pdfOnizlemeGoster(context, ciftciAdi: cf['ad_soyad']);
                        },
                      ),
                      onTap: () {
                        Navigator.pop(context);
                        _musteriEkstreGoster(cf['ad_soyad']);
                      },
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
  void _ciftciEkleDialog() {
    final tcC = TextEditingController(); // Yeni TC kontrolcüsü
    final adC = TextEditingController();
    final telC = TextEditingController();
    final adresC = TextEditingController();
    final notC = TextEditingController();

    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text("YENİ ÇİFTÇİ KAYDI"),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // TC numarasını en üste ekledik
              _input(tcC, "TC Kimlik No", Icons.badge, tip: TextInputType.number),
              _input(adC, "Ad Soyad", Icons.person),
              _input(telC, "Telefon", Icons.phone, tip: TextInputType.phone),
              _input(adresC, "Adres", Icons.location_on),
              _input(notC, "Özel Not (Tarla tarifi vb.)", Icons.note_alt),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text("İPTAL")),
          ElevatedButton(
            onPressed: () async {
              if (adC.text.isNotEmpty && tcC.text.length == 11) {
                String tcNo = tcC.text.trim();

                // 1. ADIM: Diyaloğu hemen kapat (Kullanıcı işlemin başladığını anlasın)
                // Veya bir yükleniyor simgesi göster. En hızlısı kapatmaktır.
                Navigator.pop(c);

                Map<String, dynamic> ciftciVerisi = {
                  'tc': tcNo,
                  'ad_soyad': adC.text,
                  'telefon': telC.text,
                  'adres': adresC.text,
                  'notlar': notC.text,
                  'firebase_id': tcNo,
                  'sube': "TEFENNİ",
                };

                try {
                  // 2. ADIM: Arka planda işlemleri yap
                  await FirebaseFirestore.instance
                      .collection('bicer_musterileri')
                      .doc(tcNo)
                      .set(ciftciVerisi);

                  await DatabaseHelper.instance.ciftciEkle({
                    ...ciftciVerisi,
                    'id': int.tryParse(tcNo.substring(tcNo.length - 9)) ?? 0,
                    'is_synced': 1,
                  });

                  // 3. ADIM: Arayüzü tazele
                  _verileriYukle();

                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text("✅ Çiftçi başarıyla kaydedildi.")),
                    );
                  }
                } catch (e) {
                  debugPrint("Kayıt hatası: $e");
                  // Hata olsa bile en azından yerel veri tabanına yazmayı deneyebilirsin
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text("⚠️ Buluta yüklenemedi ama yerel kaydedildi: $e")),
                    );
                  }
                }
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Ad ve 11 haneli TC girmek zorunludur!")),
                );
              }
            },
            child: const Text("KAYDET"),
          )
        ],
      ),
    );
  }

  void _musteriEkstreGoster(String isim) async {
    try {
      final isler = await DatabaseHelper.instance.musteriHareketleriGetir(isim);
      final odemeler = await DatabaseHelper.instance.tahsilatListesiGetir(isim);

      List<Map<String, dynamic>> tumHareketler = [];
      if (isler != null) tumHareketler.addAll(isler);
      if (odemeler != null) tumHareketler.addAll(odemeler);

      tumHareketler.sort((a, b) {
        String tarihA = a['tarih']?.toString() ?? "";
        String tarihB = b['tarih']?.toString() ?? "";
        return tarihB.compareTo(tarihA);
      });

      if (!mounted) return;

      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (context) => DraggableScrollableSheet(
          initialChildSize: 0.9,
          maxChildSize: 0.95,
          minChildSize: 0.5,
          expand: false,
          builder: (_, controller) => Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Container(width: 40, height: 5, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(10))),
                const SizedBox(height: 10),
                Text("$isim - CARİ EKSTRE", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const Divider(),
                Expanded(
                  child: tumHareketler.isEmpty
                      ? const Center(child: Text("Bu müşteriye ait kayıt bulunamadı."))
                      : ListView.builder(
                    controller: controller,
                    itemCount: tumHareketler.length,
                    itemBuilder: (context, index) {
                      final h = tumHareketler[index];
                      bool isHasat = h.containsKey('urun_tipi');

                      // --- SİLME VE GÜNCELLEME DESTEKLİ LİSTE ---
                      return Dismissible(
                        // Her kayıt için benzersiz bir anahtar
                        key: Key("${isHasat ? 'hasat' : 'tahsilat'}_${h['id']}"),
                        direction: DismissDirection.endToStart,
                        background: Container(
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(10)),
                          child: const Icon(Icons.delete, color: Colors.white),
                        ),
                        // Sola kaydırınca onay al ve sil
                        confirmDismiss: (direction) async {
                          return await _kayitSilOnay(h);
                        },
                        child: Card(
                          elevation: 0,
                          color: isHasat ? Colors.white : Colors.green[50],
                          shape: RoundedRectangleBorder(
                              side: BorderSide(color: Colors.grey[200]!),
                              borderRadius: BorderRadius.circular(10)
                          ),
                          child: ListTile(
                            onTap: () {
                              if (isHasat) {
                                Navigator.pop(context); // Ekstreyi kapat
                                _isEkleDialog(eskiVeri: h); // Var olan hasat düzenleme metodun
                              } else {
                                _tahsilatGuncelleDialog(h); // Yeni yazacağımız tahsilat düzenleme
                              }
                            },
                            leading: Icon(isHasat ? Icons.agriculture : Icons.payments,
                                color: isHasat ? Colors.blue : Colors.green),
                            title: Text(isHasat ? "${h['urun_tipi']} HASADI" : "NAKİT TAHSİLAT"),
                            subtitle: Text("${h['tarih']} ${isHasat ? '| ' + h['dekar'].toString() + ' Da' : ''}"),
                            trailing: Text(
                              "${isHasat ? '+' : '-'}${formatPara(isHasat ? h['toplam_tutar'] : h['miktar'])} TL",
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: isHasat ? Colors.red : Colors.green
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                _ekstreOzetPaneli(isler, odemeler)
              ],
            ),
          ),
        ),
      );
    } catch (e) {
      print("Ekstre Hatası: $e");
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Hata: $e")));
    }
  }


  Future<bool> _kayitSilOnay(Map h) async {
    bool isHasat = h.containsKey('urun_tipi');
    bool silindi = false;

    await showDialog(
      context: context,
      barrierDismissible: false, // İşlem bitmeden dışarı basıp kapatmasın
      builder: (c) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.red[900]),
            const SizedBox(width: 10),
            const Text("KAYIT SİLİNSİN Mİ?"),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Tarih: ${h['tarih']}"),
            Text("Tür: ${isHasat ? 'Hasat İşlemi' : 'Nakit Tahsilat'}"),
            Text("Tutar: ${formatPara(isHasat ? h['toplam_tutar'] : h['miktar'])} TL"),
            const Divider(),
            const Text(
              "Bu işlem geri alınamaz ve borç/alacak yeniden hesaplanır.",
              style: TextStyle(fontSize: 12, color: Colors.red, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text("İPTAL")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red[900]),
            onPressed: () async {
              try {
                if (h['id'] == null) throw "Kayıt ID'si bulunamadı!";

                // AZ ÖNCE YAZDIĞIMIZ 'ekstreSatirSil' FONKSİYONUNU ÇAĞIRIYORUZ
                // Eğer DatabaseHelper'da adı 'tahsilatSil' ise onu kullanabilirsin
                await DatabaseHelper.instance.ekstreSatirSil(
                  id: h['id'],
                  isHasat: isHasat,
                  bagliIsId: h['is_id'], // Tahsilat ise hangi hasat işine bağlı olduğu
                  miktar: double.tryParse((h['miktar'] ?? 0).toString()), // Silinen ödeme miktarı
                );

                silindi = true;

                // Arayüzü temizle
                if (Navigator.of(c).canPop()) Navigator.pop(c); // Diyaloğu kapat
                Navigator.pop(context); // Ekstreyi kapat (Veriler tazelensin diye)

                _verileriYukle(); // Ana sayfadaki listeyi ve rakamları güncelle

                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("Kayıt silindi, bakiye güncellendi."), backgroundColor: Colors.green)
                );

              } catch (e) {
                debugPrint("SİLME HATASI: $e");
                ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text("Hata: $e"), backgroundColor: Colors.red)
                );
              }
            },
            child: const Text("EVET, SİL", style: TextStyle(color: Colors.white)),
          )
        ],
      ),
    );

    return silindi;
  }


  void _tahsilatGuncelleDialog(Map h) {
    final tutarC = TextEditingController(text: h['miktar'].toString());
    final tarihC = TextEditingController(text: h['tarih']);

    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text("ÖDEME DÜZENLE"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _input(tutarC, "Miktar", Icons.money, tip: TextInputType.number),
            _input(tarihC, "Tarih", Icons.calendar_today),
          ],
        ),
        actions: [
          // SOLA SİL BUTONU EKLEDİK
          IconButton(
            icon: const Icon(Icons.delete_forever, color: Colors.red),
            onPressed: () {
              Navigator.pop(c); // Önce bu diyaloğu kapat
              _kayitSilOnay(h); // Silme onay diyaloğunu aç
            },
          ),
          const Spacer(), // Butonları sağa yaslamak için boşluk
          TextButton(onPressed: () => Navigator.pop(c), child: const Text("İPTAL")),
          ElevatedButton(
            onPressed: () async {
              double yeniMiktar = double.tryParse(tutarC.text) ?? 0;
              await DatabaseHelper.instance.tahsilatGuncelle(
                  h['id'],
                  h['is_id'] ?? 0,
                  (h['miktar'] ?? 0).toDouble(),
                  yeniMiktar,
                  {'miktar': yeniMiktar, 'tarih': tarihC.text}
              );
              Navigator.pop(c);
              Navigator.pop(context); // Ekstre panelini kapat (tazeleme için)
              _verileriYukle();
            },
            child: const Text("GÜNCELLE"),
          )
        ],
      ),
    );
  }
  // --- REHBERDEKİ ÇİFTÇİYİ SİLME ---
  void _ciftciSilOnay(int id, String ad) {
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text("ÇİFTÇİYİ SİL"),
        content: Text("$ad isimli çiftçi rehberden silinecektir. Devam edilsin mi?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text("İPTAL")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              await DatabaseHelper.instance.ciftciSil(id);
              Navigator.pop(c);
              Navigator.pop(context); // Bottom sheet'i kapat
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Çiftçi rehberden silindi.")));
            },
            child: const Text("SİL", style: TextStyle(color: Colors.white)),
          )
        ],
      ),
    );
  }

  void _hareketSil(Map h) async {
    bool isHasat = h.containsKey('urun_tipi');

    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text("KAYIT SİLİNSİN Mİ?"),
        content: Text(
            "${h['tarih']} tarihli ${isHasat ? 'hasat' : 'ödeme'} kaydı silinecektir. Bu işlem bakiye durumunu günceller."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text("İPTAL")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              try {
                if (isHasat) {
                  // Hasat kaydını kökten sil
                  await DatabaseHelper.instance.bicerIsSil(h['id']);
                } else {
                  // Tahsilatı sil ve bağlı işin borcunu geri yükle
                  // h['miktar'] verisini garantiye almak için double.tryParse ekledik
                  double miktar = double.tryParse(h['miktar'].toString()) ?? 0;
                  int bagliIsId = h['is_id'] ?? 0;

                  await DatabaseHelper.instance.tahsilatSil(
                      h['id'],
                      bagliIsId,
                      miktar
                  );
                }

                // Arayüzü temizle
                if (mounted) {
                  Navigator.pop(c); // Diyaloğu kapat
                  Navigator.pop(context); // Ekstre panelini kapat
                  _verileriYukle(); // Ana listeyi tazele
                }

                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Kayıt silindi, bakiye güncellendi.")),
                );
              } catch (e) {
                debugPrint("Silme hatası: $e");
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text("Hata oluştu: $e"), backgroundColor: Colors.red),
                );
              }
            },
            child: const Text("SİL", style: TextStyle(color: Colors.white)),
          )
        ],
      ),
    );
  }

  Widget _ekstreSatir(String baslik, String deger, {Color renk = Colors.black, bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(baslik, style: TextStyle(fontSize: 13, fontWeight: bold ? FontWeight.bold : FontWeight.w500)),
          Text("$deger TL", style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: renk)),
        ],
      ),
    );
  }
  String formatPara(dynamic deger) {
    double rakam = (deger ?? 0).toDouble();
    return rakam.toStringAsFixed(0).replaceAllMapped(
        RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]}.');
  }

  Widget _input(
      TextEditingController controller,
      String label,
      IconData icon, {
        TextInputType tip = TextInputType.text,
        ValueChanged<String>? onChanged, // Bu satırı ekle
      }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: controller,
        keyboardType: tip,
        onChanged: onChanged, // Bu satırı ekle
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon),
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text("BİÇER İŞLERİ",
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
        backgroundColor: anaTuruncu,
        centerTitle: false, // Dropdown sağa gelsin diye false yaptık
        actions: [
          // --- SEZON SEÇİCİ DROPDOWN ---
          Container(
            margin: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: secilenSezon,
                dropdownColor: anaTuruncu,
                icon: const Icon(Icons.calendar_month, color: Colors.white),
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                items: sezonListesi.map((String yil) {
                  return DropdownMenuItem<String>(
                    value: yil,
                    child: Text(yil),
                  );
                }).toList(),
                onChanged: (String? yeniYil) {
                  if (yeniYil != null) {
                    setState(() {
                      secilenSezon = yeniYil;
                    });
                    _verileriYukle(); // SEZON DEĞİŞİNCE HER ŞEYİ YENİDEN YÜKLE
                  }
                },
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          _ustRaporKartlari(),   // Seçilen sezona göre otomatik güncellenir
          _hizliMenu(),          // Menü butonları
          _makineListesiPaneli(), // Seçilen sezona ait makineleri gösterir

          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text("$secilenSezon GÜNCEL HASAT LİSTESİ",
                style: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.2)),
          ),

          Expanded(
            child: _isler.isEmpty
                ? const Center(child: Text("BU SEZONA AİT KAYIT YOK."))
                : ListView.builder(
              itemCount: _isler.length,
              itemBuilder: (context, i) => _isKarti(_isler[i]),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: anaTuruncu,
        onPressed: () => _isEkleDialog(),
        label: Text("$secilenSezon HASAT EKLE", style: const TextStyle(color: Colors.white)),
        icon: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }



  void _isEkleDialog({Map? eskiVeri}) async {
    final tumCiftciler = await DatabaseHelper.instance.ciftciListesiGetir();

    final ciftciC = TextEditingController(text: eskiVeri?['ciftci_ad']);
    final dekarC = TextEditingController(text: eskiVeri?['dekar']?.toString());
    final fiyatC = TextEditingController(text: eskiVeri?['birim_fiyat']?.toString());
    final alinanC = TextEditingController(text: eskiVeri?['odenen_miktar']?.toString() ?? "0");

    int? secilenBicerId = eskiVeri?['bicer_id'];
    String? secilenCiftciAdi = eskiVeri?['ciftci_ad'];
    String secilenUrun = eskiVeri?['urun_tipi'] ?? "BUĞDAY";

    if (eskiVeri == null && fiyatC.text.isEmpty) {
      fiyatC.text = bugdayFiyat.toString();
    }

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          // --- ANLIK HESAPLAMA MANTIĞI ---
          double d = double.tryParse(dekarC.text) ?? 0;
          double f = double.tryParse(fiyatC.text) ?? 0;
          double alinan = double.tryParse(alinanC.text) ?? 0;

          double anlikToplam = d * f;
          double anlikKalan = anlikToplam - alinan; // Borç hesabı

          // Ekranı tazelemek için yardımcı fonksiyon
          void hesapla() => setDialogState(() {});

          return AlertDialog(
            title: Text(eskiVeri == null ? "YENİ HASAT" : "HASAT GÜNCELLE"),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<int>(
                    value: secilenBicerId,
                    hint: const Text("MAKİNE SEÇ"),
                    items: _makineler.map((m) => DropdownMenuItem(value: m['id'] as int, child: Text("${m['marka']} ${m['model']}"))).toList(),
                    onChanged: (v) => setDialogState(() => secilenBicerId = v),
                    decoration: const InputDecoration(border: OutlineInputBorder(), labelText: "Biçer Seç"),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    value: secilenUrun,
                    items: ["BUĞDAY", "ARPA", "DANELİK MISIR", "SOSLUK MISIR"].map((u) => DropdownMenuItem(value: u, child: Text(u))).toList(),
                    onChanged: (v) {
                      setDialogState(() {
                        secilenUrun = v!;
                        if (v == "BUĞDAY") fiyatC.text = bugdayFiyat.toString();
                        if (v == "ARPA") fiyatC.text = arpaFiyat.toString();
                        if (v == "DANELİK MISIR") fiyatC.text = danelikMisirFiyat.toString();
                        if (v == "SOSLUK MISIR") fiyatC.text = soslukMisirFiyat.toString();
                      });
                    },
                    decoration: const InputDecoration(border: OutlineInputBorder(), labelText: "Ürün Tipi"),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    value: tumCiftciler.any((c) => c['ad_soyad'] == secilenCiftciAdi) ? secilenCiftciAdi : null,
                    hint: const Text("KAYITLI ÇİFTÇİ SEÇ"),
                    items: tumCiftciler.map((c) => DropdownMenuItem(value: c['ad_soyad'].toString(), child: Text(c['ad_soyad'].toString()))).toList(),
                    onChanged: (v) {
                      setDialogState(() {
                        secilenCiftciAdi = v;
                        ciftciC.text = v ?? "";
                      });
                    },
                    decoration: const InputDecoration(border: OutlineInputBorder(), labelText: "Rehberden Çiftçi"),
                  ),
                  const SizedBox(height: 10),
                  _input(ciftciC, "VEYA ELLE ÇİFTÇİ ADI YAZ", Icons.person),

                  _input(dekarC, "DEKAR", Icons.straighten, tip: TextInputType.number, onChanged: (v) => hesapla()),
                  _input(fiyatC, "BİRİM FİYAT", Icons.payments, tip: TextInputType.number, onChanged: (v) => hesapla()),
                  // ALINAN NAKİT kısmına onChanged eklendi, böylece yazdığın an alttaki borç düşer
                  _input(alinanC, "ALINAN NAKİT (PEŞİNAT)", Icons.money, tip: TextInputType.number, onChanged: (v) => hesapla()),

                  const SizedBox(height: 15),

                  // --- GÜNCELLENEN GÖSTERGE ALANI ---
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.orange.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.orange.shade200),
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text("TOPLAM TUTAR:", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                            Text("${formatPara(anlikToplam)} TL", style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                          ],
                        ),
                        const Divider(),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text("KALAN BORÇ:", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.red)),
                            Text("${formatPara(anlikKalan)} TL",
                                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.red)),
                          ],
                        ),
                        if (alinan > 0)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text("${formatPara(alinan)} TL Peşinat Düştü",
                                style: const TextStyle(fontSize: 10, color: Colors.green, fontWeight: FontWeight.bold)),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              if (eskiVeri != null)
                IconButton(
                    icon: const Icon(Icons.delete_forever, color: Colors.red, size: 28),
                    onPressed: () {
                      Navigator.pop(context);
                      _kayitSilOnay(eskiVeri);
                    }
                ),
              const SizedBox(width: 20),
              TextButton(onPressed: () => Navigator.pop(context), child: const Text("İPTAL")),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: anaTuruncu),
                onPressed: () async {
                  // 1. MAKİNE SEÇİM KONTROLÜ (Boşsa uyarı ver ve dur)
                  if (secilenBicerId == null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text("LÜTFEN MAKİNE SEÇİN!"), backgroundColor: Colors.red),
                    );
                    return;
                  }

                  double d = double.tryParse(dekarC.text) ?? 0;
                  double f = double.tryParse(fiyatC.text) ?? 0;
                  double alinan = double.tryParse(alinanC.text) ?? 0;
                  double toplam = d * f;
                  double kalan = toplam - alinan;

                  Map<String, dynamic> veri = {
                    'ciftci_ad': ciftciC.text.trim().toUpperCase(),
                    'dekar': d,
                    'fiyat': f, // EĞER SQL'DE HATA ALIRSAN BURAYI 'birim_fiyat' OLARAK DEĞİŞTİR
                    'toplam_tutar': toplam,
                    'odenen_miktar': alinan,
                    'kalan_borc': kalan,
                    'urun_tipi': secilenUrun,
                    'sezon': secilenSezon,
                    'tarih': eskiVeri?['tarih'] ?? DateTime.now().toString().substring(0, 10),
                    'is_synced': 0,
                    'bicer_id': secilenBicerId,
                  };

                  try {
                    if (eskiVeri == null) {
                      int yeniId = await DatabaseHelper.instance.bicerIsEkle(veri);
                      if (alinan > 0) {
                        await DatabaseHelper.instance.tahsilatEkle({
                          'is_id': yeniId,
                          'ciftci_ad': ciftciC.text.trim().toUpperCase(),
                          'miktar': alinan,
                          'tarih': veri['tarih'],
                          'sezon': secilenSezon,
                          'odeme_tipi': "NAKİT",
                          'aciklama': "${secilenUrun} Hasatı Peşinatı"
                        });
                      }
                    } else {
                      await DatabaseHelper.instance.bicerIsGuncelle(eskiVeri['id'], veri);
                    }

                    Navigator.pop(context);
                    _verileriYukle(); // Listeyi yeniler

                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text("Hasat Başarıyla Kaydedildi"), backgroundColor: Colors.green),
                    );
                  } catch (e) {
                    // Bir hata olursa burada yakalarız
                    print("KAYIT HATASI: $e");
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text("Hata: $e"), backgroundColor: Colors.red),
                    );
                  }
                },
                child: const Text("KAYDET", style: TextStyle(color: Colors.white)),
              )
            ],
          );
        },
      ),
    );
  }

  void _makinelerDialog() async {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (c) => StatefulBuilder( // Sezon seçimi anlık değişsin diye
        builder: (context, setModalState) => Container(
          padding: const EdgeInsets.all(16),
          height: MediaQuery.of(context).size.height * 0.8,
          child: Column(
            children: [
              // ÜST BAŞLIK VE SEZON SEÇİCİ
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text("MAKİNE LİSTESİ",
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      // SEZON SEÇİCİ DROPDOWN
                      DropdownButton<String>(
                        value: secilenSezon, // Sınıf düzeyinde tanımladığın değişken
                        underline: Container(),
                        style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold),
                        items: ["2024", "2025", "2026"].map((s) => DropdownMenuItem(
                            value: s,
                            child: Text("$s SEZONU")
                        )).toList(),
                        onChanged: (v) {
                          setModalState(() => secilenSezon = v!);
                          setState(() => secilenSezon = v!);
                          _verileriYukle(); // Seçilen sezona göre listeyi tazele
                        },
                      ),
                    ],
                  ),
                  ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(c);
                      _makineEkleDialog();
                    },
                    icon: const Icon(Icons.add),
                    label: const Text("Yeni Makine"),
                  )
                ],
              ),
              const Divider(),
              Expanded(
                child: _makineler.isEmpty
                    ? const Center(child: Text("Kayıtlı makine yok."))
                    : ListView.builder(
                  itemCount: _makineler.length,
                  itemBuilder: (context, i) {
                    final m = _makineler[i];
                    // Sadece seçilen sezona ait olanları göster (veya SQL'de filtrele)
                    if (m['yil'] != secilenSezon) return const SizedBox();

                    double masraf = (m['toplam_masraf'] as num? ?? 0).toDouble();

                    return Card(
                      elevation: 3,
                      margin: const EdgeInsets.symmetric(vertical: 5),
                      child: ListTile(
                        leading: const Icon(Icons.agriculture,
                            color: Colors.blue, size: 35),
                        title: Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 10,
                          children: [
                            Text("${m['marka']} ${m['model']}",
                                style: const TextStyle(fontWeight: FontWeight.bold)),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.red[100],
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                "${formatPara(masraf)} TL",
                                style: const TextStyle(color: Colors.red, fontSize: 12, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ),
                        subtitle: Text("Plaka: ${m['plaka']}\nSezon: ${m['yil']}",
                            style: const TextStyle(color: Colors.grey, fontSize: 12)),
                        trailing: PopupMenuButton<String>(
                          onSelected: (value) {
                            if (value == 'duzenle') {
                              _makineDuzenleDialog(m);
                            } else if (value == 'sil') {
                              _makineSil(m['id']);
                            } else if (value == 'masraf') {
                              _bakimEkleDialog(m['id'], m['marka']);
                            } else if (value == 'gecmis') {
                              _makineMasrafListesiGoster(m['id'], m['marka']);
                            }
                          },
                          itemBuilder: (context) => [
                            const PopupMenuItem(value: 'masraf', child: ListTile(leading: Icon(Icons.build, color: Colors.orange, size: 20), title: Text("Masraf Ekle"))),
                            const PopupMenuItem(value: 'gecmis', child: ListTile(leading: Icon(Icons.list_alt, size: 20), title: Text("Geçmiş"))),
                            const PopupMenuItem(value: 'duzenle', child: ListTile(leading: Icon(Icons.edit, color: Colors.blue, size: 20), title: Text("Düzenle"))),
                            const PopupMenuItem(value: 'sil', child: ListTile(leading: Icon(Icons.delete, color: Colors.red, size: 20), title: Text("Sil"))),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _makineSil(int? id) async {
    if (id == null) return;

    bool? onay = await showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text("MAKİNEYİ SİL"),
        content: const Text("Bu makineyi ve ilgili tüm kayıtları silmek istediğinize emin misiniz?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text("VAZGEÇ")),
          ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.pop(c, true),
              child: const Text("SİL", style: TextStyle(color: Colors.white))
          ),
        ],
      ),
    );

    if (onay == true) {
      // DatabaseHelper'da yeni yazdığımız fonksiyonu çağırıyoruz
      await DatabaseHelper.instance.bicerSil(id);

      _verileriYukle(); // Ekranı tazele
      if (mounted) Navigator.pop(context); // Listeyi kapat

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Makine ve bağlı kayıtlar temizlendi.")),
      );
    }
  }

// DÜZENLEME DİALOGU
  void _makineDuzenleDialog(Map<String, dynamic> m) {
    final markaC = TextEditingController(text: m['marka']);
    final modelC = TextEditingController(text: m['model']);
    final plakaC = TextEditingController(text: m['plaka']);
    final calismaC = TextEditingController(text: m['calisma_saati'].toString());

    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text("MAKİNE DÜZENLE"),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _input(markaC, "MARKA", Icons.agriculture),
              _input(modelC, "MODEL", Icons.settings),
              _input(plakaC, "PLAKA", Icons.numbers),
              _input(calismaC, "ÇALIŞMA SAATİ", Icons.timer, tip: TextInputType.number),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text("İPTAL")),
          ElevatedButton(
            onPressed: () async {
              await DatabaseHelper.instance.customUpdate(
                  "UPDATE bicerler SET marka=?, model=?, plaka=?, calisma_saati=? WHERE id=?",
                  [markaC.text, modelC.text, plakaC.text, int.tryParse(calismaC.text) ?? 0, m['id']]
              );
              Navigator.pop(c);
              _verileriYukle();
            },
            child: const Text("GÜNCELLE"),
          )
        ],
      ),
    );
  }


  void _mazotTakibiGoster() async {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (c) => Container(
        padding: const EdgeInsets.all(16),
        height: MediaQuery.of(context).size.height * 0.8,
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text("MAZOT FİŞLERİ", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.picture_as_pdf, color: Colors.red),
                      onPressed: () {
                        Navigator.pop(c);
                        _mazotPdfOnizlemeGoster();
                      },
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      onPressed: () { Navigator.pop(c); _mazotFisEkleDialog(); },
                      icon: const Icon(Icons.add),
                      label: const Text("Fiş Ekle"),
                    ),
                  ],
                )
              ],
            ),
            const Divider(),
            Expanded(
              child: _mazotlar.isEmpty
                  ? const Center(child: Text("Mazot fişi bulunamadı."))
                  : ListView.builder(
                itemCount: _mazotlar.length,
                itemBuilder: (context, i) { // <--- Değişken adımız 'i'
                  final m = _mazotlar[i];
                  double tutar = (m['tutar'] as num? ?? 0).toDouble();
                  double odenen = (m['odenen'] as num? ?? 0).toDouble();
                  double borc = tutar - odenen;

                  return ListTile(
                    leading: const Icon(Icons.gas_meter, color: Colors.orange),
                    title: Text(m['petrol_adi'] ?? "Bilinmiyor"),
                    subtitle: Text("${m['litre']} Lt | ${m['tarih']}${borc > 0 ? '\nBorç: ${formatPara(borc)} TL' : ''}"),
                    isThreeLine: borc > 0,
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text("${formatPara(tutar)} TL", style: const TextStyle(fontWeight: FontWeight.bold)),
                        IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          onPressed: () async {
                            // DÜZELTİLEN KISIM:
                            // 1. 'index' yerine 'i' kullandık.
                            // 2. 'firebaseId:' ismini belirterek gönderdik.
                            await DatabaseHelper.instance.mazotSil(
                                m['id'],
                                firebaseId: m['firebase_id']
                            );

                            _verileriYukle();
                            Navigator.pop(c); // Sildikten sonra listeyi tazelemek için kapatıyoruz
                          },
                        ),
                      ],
                    ),
                    onTap: () => _mazotGuncelleDialog(m),
                  );
                },
              ),
            )
          ],
        ),
      ),
    );
  }


  void _mazotPdfOnizlemeGoster() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => Scaffold(
        appBar: AppBar(
          title: const Text("Mazot Ekstresi / Raporu"),
          backgroundColor: Colors.orange[900],
        ),
        body: PdfPreview(
          // Bir önceki mesajda verdiğim _pdfMazotEkstresiBuild fonksiyonunu çağırır
          build: (format) => _pdfMazotEkstresiBuild(),
          allowPrinting: true,
          allowSharing: true,
        ),
      ),
    );
  }

  Widget _arizaSatir(String kod, String baslik, String cozum) {
    return ListTile(
      leading: const Icon(Icons.warning, color: Colors.red),
      title: Text("$kod - $baslik"),
      subtitle: Text("Çözüm: $cozum"),
    );
  }



  // Eksik olan bakım metodlarını da ekliyorum:
  void _bakimEkleDialog(int bicerId, String ad) {
    final parcaC = TextEditingController();
    final tutarC = TextEditingController();
    showDialog(context: context, builder: (c) => AlertDialog(
      title: Text("$ad - MASRAF EKLE"),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        _input(parcaC, "Yapılan İşlem", Icons.settings),
        _input(tutarC, "Tutar", Icons.money, tip: TextInputType.number),
      ]),
      actions: [
        ElevatedButton(onPressed: () async {
          await DatabaseHelper.instance.bicerBakimEkle({
            'bicer_id': bicerId, 'parca_adi': parcaC.text, 'tutar': double.tryParse(tutarC.text) ?? 0,
            'tarih': DateTime.now().toString().substring(0, 10)
          });
          Navigator.pop(c); _verileriYukle();
        }, child: const Text("KAYDET"))
      ],
    ));
  }

  void _makineMasrafListesiGoster(int bicerId, String ad) async {
    // 1. Veritabanından o makinenin masraflarını çekiyoruz
    final b = await DatabaseHelper.instance.bicerBakimlariGetir(bicerId);

    showDialog(context: context, builder: (c) => AlertDialog(
      title: Text("$ad Masrafları"),
      content: SizedBox(
        width: double.maxFinite,
        child: b.isEmpty
            ? const Text("Bu makineye ait masraf kaydı bulunamadı.")
            : ListView.builder(
          shrinkWrap: true,
          itemCount: b.length,
          itemBuilder: (context, i) => ListTile(
            title: Text(b[i]['parca_adi']),
            // BURAYA TARİH VE TUTAR EKLEDİK
            subtitle: Text(b[i]['tarih'] ?? ""),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text("${b[i]['tutar']} TL", style: const TextStyle(fontWeight: FontWeight.bold)),
                // --- İŞTE SİLME BUTONU ---
                IconButton(
                  icon: const Icon(Icons.delete, color: Colors.red),
                  onPressed: () async {
                    await DatabaseHelper.instance.bicerBakimSil(b[i]['id']);
                    Navigator.pop(c); // Pencereyi kapat
                    _verileriYukle(); // Ana sayfayı yenile
                    _makineMasrafListesiGoster(bicerId, ad); // Listeyi güncel haliyle geri aç
                  },
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text("KAPAT"))
      ],
    ));
  }

  void _ayarlarDialog() {
    final bC = TextEditingController(text: bugdayFiyat.toString());
    final aC = TextEditingController(text: arpaFiyat.toString());
    final dMC = TextEditingController(text: danelikMisirFiyat.toString());
    final sMC = TextEditingController(text: soslukMisirFiyat.toString());

    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text("SEZONLUK DEKAR FİYATLARI"),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _input(bC, "BUĞDAY (TL)", Icons.eco, tip: TextInputType.number),
              _input(aC, "ARPA (TL)", Icons.eco, tip: TextInputType.number),
              _input(dMC, "DANELİK MISIR (TL)", Icons.grain, tip: TextInputType.number),
              _input(sMC, "SOSLUK MISIR (TL)", Icons.local_dining, tip: TextInputType.number),
              const SizedBox(height: 10),
              const Text("Not: Burada girilen fiyatlar yeni kayıtlarda varsayılan olarak gelir.",
                  style: TextStyle(fontSize: 10, color: Colors.grey)),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text("İPTAL")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: anaTuruncu),
            onPressed: () {
              setState(() {
                bugdayFiyat = double.tryParse(bC.text) ?? bugdayFiyat;
                arpaFiyat = double.tryParse(aC.text) ?? arpaFiyat;
                danelikMisirFiyat = double.tryParse(dMC.text) ?? danelikMisirFiyat;
                soslukMisirFiyat = double.tryParse(sMC.text) ?? soslukMisirFiyat;
              });
              Navigator.pop(c);
              ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Fiyatlar güncellendi."))
              );
            },
            child: const Text("KAYDET", style: TextStyle(color: Colors.white)),
          )
        ],
      ),
    );
  }



  void _mazotFisEkleDialog() {
    final petrolC = TextEditingController();
    final litreC = TextEditingController();
    final fiyatC = TextEditingController(); // Birim fiyat için yeni
    final tutarC = TextEditingController(); // Otomatik hesaplanacak toplam
    final odenenC = TextEditingController();
    final tarihC = TextEditingController(text: DateTime.now().toString().substring(0, 10));

    // --- HESAPLAMA MANTIĞI ---
    void hesapla() {
      double litre = double.tryParse(litreC.text) ?? 0;
      double fiyat = double.tryParse(fiyatC.text) ?? 0;
      if (litre > 0 && fiyat > 0) {
        tutarC.text = (litre * fiyat).toStringAsFixed(2);
      }
    }

    // Kullanıcı yazdıkça hesapla fonksiyonunu çalıştır
    litreC.addListener(hesapla);
    fiyatC.addListener(hesapla);

    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text("YENİ MAZOT FİŞİ"),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _input(petrolC, "Petrol İstasyonu", Icons.local_gas_station),
              _input(litreC, "Litre Miktarı", Icons.opacity, tip: TextInputType.number),
              _input(fiyatC, "Litre Fiyatı (TL)", Icons.toll, tip: TextInputType.number),

              // Toplam Tutar Kutusu (Arka planı hafif gri yaparak otomatik olduğunu belli edelim)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8.0),
                child: TextField(
                  controller: tutarC,
                  readOnly: true, // Kullanıcı elle müdahale etmesin, otomatik gelsin
                  decoration: InputDecoration(
                    labelText: "Toplam Tutar (Otomatik)",
                    prefixIcon: const Icon(Icons.calculate, color: Colors.blue),
                    filled: true,
                    fillColor: Colors.blue.withOpacity(0.05),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),

              _input(odenenC, "Şimdi Ödenen (Nakit)", Icons.money_off, tip: TextInputType.number),
              _input(tarihC, "Fiş Tarihi", Icons.calendar_today),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text("İPTAL")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))
            ),
            onPressed: () async {
              if (petrolC.text.isNotEmpty && tutarC.text.isNotEmpty) {
                String mazotId = "MAZOT_${DateTime.now().millisecondsSinceEpoch}";
                double m_litre = double.tryParse(litreC.text) ?? 0;
                double m_tutar = double.tryParse(tutarC.text) ?? 0;
                double m_odenen = double.tryParse(odenenC.text) ?? 0;

                Map<String, dynamic> mazotVerisi = {
                  'petrol_adi': petrolC.text.toUpperCase(),
                  'litre': m_litre,
                  'tutar': m_tutar,
                  'odenen': m_odenen,
                  'tarih': tarihC.text,
                  'sezon': secilenSezon,
                  'firebase_id': mazotId,
                };

                try {
                  // 1. FIREBASE KAYIT (Burada sorun yok, başarıyla kaydediyor)
                  await FirebaseFirestore.instance
                      .collection('bicer_mazotlar')
                      .doc(mazotId)
                      .set({
                    ...mazotVerisi,
                    'kayit_tarihi': FieldValue.serverTimestamp(),
                  });
                  print("✅ Firebase: Mazot kaydı başarılı.");

                  // 2. SQL KAYIT (Hata veren 'is_synced' satırını sildik)
                  final db = await DatabaseHelper.instance.database;
                  await db.insert('mazot_takibi', mazotVerisi); // Sadece tablodaki mevcut alanları gönderiyoruz

                  print("✅ SQL: Mazot kaydı başarılı.");

                  if (mounted) {
                    Navigator.pop(c);
                    _verileriYukle();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text("Mazot fişi başarıyla kaydedildi.")),
                    );
                  }
                } catch (e) {
                  print("❌ KAYIT HATASI: $e");

                  // Hata durumunda (internet yoksa vb.) yine is_synced olmadan yerel kayıt dene
                  try {
                    final db = await DatabaseHelper.instance.database;
                    await db.insert('mazot_takibi', mazotVerisi);
                    Navigator.pop(c);
                    _verileriYukle();
                  } catch (sqlHata) {
                    print("❌ Yerel SQL Hatası: $sqlHata");
                  }
                }
              }
            },
            child: const Text("KAYDET", style: TextStyle(color: Colors.white)),
          )
        ],
      ),
    );
  }

  void _mazotGuncelleDialog(Map m) {
    // Mevcut Kontroller
    final petrolC = TextEditingController(text: m['petrol_adi']);
    final litreC = TextEditingController(text: m['litre'].toString());
    final odenenC = TextEditingController(text: (m['odenen'] ?? 0).toString());

    // Eksik olan Kontroller
    final tutarC = TextEditingController(text: (m['tutar'] ?? 0).toString());
    final tarihC = TextEditingController(text: (m['tarih'] ?? ""));

    // Birim fiyatı hesapla (sadece görsel amaçlı)
    double ilkTutar = (m['tutar'] as num? ?? 0).toDouble();
    double ilkLitre = (m['litre'] as num? ?? 1).toDouble();
    double hesaplananBirimFiyat = ilkTutar / (ilkLitre == 0 ? 1 : ilkLitre);
    final fiyatC = TextEditingController(text: hesaplananBirimFiyat.toStringAsFixed(2));

    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text("MAZOT FİŞİ DÜZENLE"),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _input(petrolC, "PETROL ADI", Icons.business),
              _input(litreC, "LİTRE", Icons.local_gas_station, tip: TextInputType.number),
              _input(fiyatC, "BİRİM FİYAT", Icons.sell, tip: TextInputType.number),
              _input(odenenC, "ÖDENEN", Icons.payments, tip: TextInputType.number),
            ],
          ),
        ),
        actionsPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        actions: [
          Row(
            children: [
      IconButton(
      icon: const Icon(Icons.delete_forever, color: Colors.red, size: 28),
      onPressed: () async {
        bool? onay = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text("KAYDI SİL"),
            content: const Text("Bu mazot fişi silinecek. Emin misiniz?"),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("İPTAL")),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                onPressed: () => Navigator.pop(context, true),
                child: const Text("SİL"),
              ),
            ],
          ),
        );

        if (onay == true) {
          // ÇÖZÜM BURADA: '_mazotlar[index]' yerine doğrudan 'm' kullanıyoruz
          await DatabaseHelper.instance.mazotSil(
              m['id'],                // SQLite ID'si
              firebaseId: m['firebase_id'] // Firebase ID'si (isimlendirilmiş parametre)
          );

          if (!mounted) return;
          Navigator.pop(c); // Ana diyaloğu kapat
          await _verileriYukle(); // Listeyi yenile
        }
      },
    ),
              const Spacer(),
              TextButton(onPressed: () => Navigator.pop(c), child: const Text("İPTAL")),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.orange[900]),
                onPressed: () async {
                  // Tutar kontrolü
                  double lt = double.tryParse(litreC.text) ?? 0;
                  double fr = double.tryParse(fiyatC.text) ?? 0;
                  double yeniTutar = lt * fr;

                  if (petrolC.text.isEmpty) return;

                  try {
                    Map<String, dynamic> guncelVeri = {
                      'petrol_adi': petrolC.text.toUpperCase(),
                      'litre': lt,
                      'tutar': yeniTutar,
                      'odenen': double.tryParse(odenenC.text) ?? 0,
                      'tarih': tarihC.text,
                      'sezon': m['sezon'], // Mevcut sezonu koru
                      'firebase_id': m['firebase_id'], // Mevcut ID'yi koru
                    };

                    // 1. Yerel Veritabanını Güncelle (Tablo: mazot_takibi)
                    await DatabaseHelper.instance.mazotGuncelle(m['id'], guncelVeri);

                    // 2. Firebase Güncelle (Opsiyonel: firebase_id varsa)
                    if (m['firebase_id'] != null) {
                      await FirebaseFirestore.instance
                          .collection('bicer_mazotlar')
                          .doc(m['firebase_id'].toString())
                          .update(guncelVeri);
                    }

                    if (mounted) Navigator.pop(c);
                    await _verileriYukle();

                  } catch (e) {
                    print("❌ GÜNCELLEME HATASI: $e");
                  }
                },
                child: const Text("GÜNCELLE", style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<Uint8List> _pdfMazotEkstresiBuild() async {
    final pdf = pw.Document();
    final fontData = await rootBundle.load("assets/fonts/arial.ttf").catchError((e) => rootBundle.load("assets/fonts/Roboto-Regular.ttf"));
    final ttf = pw.Font.ttf(fontData);

    // Sadece bu sezonun mazotlarını çek
    final tumMazotlar = await DatabaseHelper.instance.mazotListesiGetir(secilenSezon);

    double mToplamGider = 0;
    double mToplamOdenen = 0;

    final mazotTabloVerisi = tumMazotlar.map((m) {
      double tutar = (m['tutar'] ?? 0).toDouble();
      double odenen = (m['odenen'] ?? 0).toDouble();
      mToplamGider += tutar;
      mToplamOdenen += odenen;

      return [
        m['tarih']?.toString() ?? "",
        m['petrol_adi']?.toString() ?? "",
        "${m['litre']} Lt",
        "${formatPara(odenen)} TL", // O an ödenen
        "${formatPara(tutar)} TL"   // Toplam tutar
      ];
    }).toList();

    pdf.addPage(
      pw.MultiPage(
        theme: pw.ThemeData.withFont(base: ttf, bold: ttf),
        pageFormat: PdfPageFormat.a4,
        build: (context) => [
          pw.Header(level: 0, child: pw.Text("EVREN TARIM - MAZOT HARCAMA EKSTRESİ ($secilenSezon)")),
          pw.Divider(thickness: 2, color: PdfColors.orange900),

          pw.SizedBox(height: 10),
          pw.TableHelper.fromTextArray(
            headers: ['Tarih', 'İstasyon', 'Litre', 'Ödenen', 'Toplam Tutar'],
            data: mazotTabloVerisi,
            headerStyle: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.orange900),
            cellAlignment: pw.Alignment.centerLeft,
          ),

          pw.SizedBox(height: 20),
          // --- MAZOT ÖZET PANELİ ---
          pw.Container(
            padding: const pw.EdgeInsets.all(10),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.black, width: 2),
              color: PdfColors.grey100,
            ),
            child: pw.Column(
              children: [
                _pdfSatir("TOPLAM MAZOT MALİYETİ:", "${formatPara(mToplamGider)} TL", PdfColors.black, buyuk: true),
                _pdfSatir("TOPLAM YAPILAN ÖDEME:", "${formatPara(mToplamOdenen)} TL", PdfColors.green900),
                pw.Divider(),
                _pdfSatir("GÜNCEL PETROL BORCU:", "${formatPara(mToplamGider - mToplamOdenen)} TL", PdfColors.red900, buyuk: true),
              ],
            ),
          ),
        ],
      ),
    );

    return pdf.save();
  }
  void _arizaKodlari() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (c) => DraggableScrollableSheet(
        initialChildSize: 0.9,
        expand: false,
        builder: (_, controller) => Container(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              const Text("CLAAS TUCANO ARIZA REHBERİ",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.red)),
              const Divider(),
              Expanded(
                child: ListView(
                  controller: controller,
                  children: [
                    _arizaBaslik("MOTOR & GENEL (CAB)"),
                    _arizaSatir("E-01 / E-02", "Yağ Basıncı Düşük", "Yağ seviyesini ve müşürü kontrol et."),
                    _arizaSatir("E-04 / E-51", "Hararet / Su Seviyesi", "Radyatörü temizle, su ekle."),
                    _arizaSatir("E-98", "Hava Filtresi Tıkalı", "Filtreyi temizle veya değiştir."),
                    _arizaSatir("E-101", "Düşük Voltaj", "Aküyü ve alternatörü kontrol et."),
                    _arizaBaslik("YÜRÜYÜŞ & HİDROLİK (EFA)"),
                    _arizaSatir("E-05", "Şanzıman Yağ Sıcaklığı", "Yağ soğutucusunu kontrol et."),
                    _arizaSatir("E-11", "Hidrolik Seviye Düşük", "Depoyu ve kaçakları kontrol et."),
                    _arizaSatir("E-40", "Hidrostatik Arızası", "Pompa selenoid valfini kontrol et."),
                    _arizaBaslik("HASAT & BATÖR (ESR)"),
                    _arizaSatir("E-13 / E-14", "Metal Dedektörü", "Kablo ve sensör bağlantısına bak."),
                    _arizaSatir("E-48", "Metal Tespit Edildi!", "Besleme boğazındaki yabancı maddeyi çıkar."),
                    _arizaSatir("E-49", "Kayış Kaydırıyor", "Besleme kayışı gerginliğini kontrol et."),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _arizaBaslik(String baslik) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: Text(baslik, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.orange)),
  );
}