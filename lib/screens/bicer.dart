import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:io';
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
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';

class BicerPaneli extends StatefulWidget {
  const BicerPaneli({super.key});

  @override
  State<BicerPaneli> createState() => _BicerPaneliState();
}

class _BicerPaneliState extends State<BicerPaneli> {
  List<Map<String, dynamic>> _isler = [];
  List<Map<String, dynamic>> _makineler = [];
  List<Map<String, dynamic>> _mazotlar = [];
  List<Map<String, dynamic>> _tumMusteriler = []; //


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
  bool _yukleniyor = false;

  final Color anaTuruncu = Colors.orange[900]!;

  Widget buildImage(String path) {
    if (path.isEmpty) {
      return Image.asset("assets/images/logo.png");
    }
    return Image.file(File(path));
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



  @override
  void initState() {
    super.initState();
    // Uygulama ilk açıldığında o anki yılı seçili sezon yap
    secilenSezon = DateTime.now().year.toString();
    _verileriYukle();
  }



  Future<void> _verileriYukle() async {
    if (_yukleniyor) return;
    if (mounted) setState(() => _yukleniyor = true);

    try {
      // 1. TÜM VERİLERİ PARALEL ÇEK (Performans için)
      final results = await Future.wait([
        DatabaseHelper.instance.bicerIsleriGetir(secilenSezon),
        DatabaseHelper.instance.bicerListesi(),
        DatabaseHelper.instance.mazotListesiGetir(secilenSezon),
        DatabaseHelper.instance.tumCiftcileriGetir(), // Ana sayfada görünecek liste
      ]);

      final List<Map<String, dynamic>> islerRaw = results[0] as List<Map<String, dynamic>>;
      final List<Map<String, dynamic>> allBicerler = results[1] as List<Map<String, dynamic>>;
      final List<Map<String, dynamic>> mazotlarRaw = results[2] as List<Map<String, dynamic>>;
      final List<Map<String, dynamic>> safMusteriListesi = results[3] as List<Map<String, dynamic>>;

      // 2. HESAPLAMA DEĞİŞKENLERİ
      double hasilat = 0;
      double alacak = 0;
      double mBorc = 0;
      double bakimMasraf = 0;
      Map<String, Map<String, dynamic>> gruplanmisMusteriler = {};

      // 3. HASAT İŞLERİNİ İŞLE VE GRUPLA
      for (var i in islerRaw) {
        String isim = (i['ciftci_ad'] ?? i['CIFTCI_AD'] ?? "Bilinmeyen").toString().trim();
        String tcKimlik = (i['tc'] ?? i['TC'] ?? i['firebase_id'] ?? '').toString().trim();

        // 1. DEĞİŞKENLERİ TANIMLA (Burada 'd' eksik olduğu için hata alıyorsun)
        double t = double.tryParse(i['toplam_tutar']?.toString() ?? '0') ?? 0;
        double o = double.tryParse(i['odenen_miktar']?.toString() ?? '0') ?? 0;
        double d = double.tryParse(i['dekar']?.toString() ?? '0') ?? 0; // <--- EKSİK OLAN SATIR BU

        hasilat += t;
        alacak += (t - o);

        if (gruplanmisMusteriler.containsKey(isim)) {
          gruplanmisMusteriler[isim]!['toplam_tutar'] += t;
          gruplanmisMusteriler[isim]!['odenen_miktar'] += o;
          gruplanmisMusteriler[isim]!['dekar'] += d; // Artık 'd' tanımlı olduğu için hata vermez
          gruplanmisMusteriler[isim]!['is_sayisi'] += 1;
        } else {
          gruplanmisMusteriler[isim] = {
            'id': i['id'] ?? (DateTime.now().millisecondsSinceEpoch % 100000),
            'ciftci_ad': isim,
            'toplam_tutar': t,
            'odenen_miktar': o,
            'dekar': d, // Burada da 'd' kullanılıyor
            'is_sayisi': 1,
            'tc': tcKimlik,
          };
        }
      }

      // 4. MAZOT HESAPLAMA
      for (var m in mazotlarRaw) {
        double tutar = double.tryParse(m['tutar']?.toString() ?? '0') ?? 0;
        double odenen = double.tryParse(m['odenen']?.toString() ?? '0') ?? 0;
        mBorc += (tutar - odenen);
      }

      // 5. MAKİNE BAKIM HESAPLAMA
      final bicerlerRaw = allBicerler.where((m) => m['yil'] == secilenSezon).toList();
      List<Map<String, dynamic>> guncelMakineler = [];

      // 1. BİÇERLER DÖNGÜSÜ (Masraf Hesaplama Kısmı)
      for (var b in bicerlerRaw) {
        Map<String, dynamic> makine = Map.from(b);

        // 🔥 TAMİRAT: .toString() ile ID ne gelirse gelsin güvenli bir şekilde String'e çeviriyoruz
        String guvenliBicerId = (makine['id'] ?? '').toString();

    final bakimlar = await DatabaseHelper.instance.bicerBakimlariniGetir(guvenliBicerId);
    double mMasraf = 0;
    for (var bakim in bakimlar) {
    mMasraf += double.tryParse(bakim['tutar']?.toString() ?? '0') ?? 0;
    }
    makine['toplam_masraf'] = mMasraf;
    bakimMasraf += mMasraf;
    guncelMakineler.add(makine);
    }

      // 6. TEK SEFERDE STATE GÜNCELLEME
      if (mounted) {
        setState(() {
          _tumMusteriler = safMusteriListesi; // Ana sayfadaki liste için
          _isler = gruplanmisMusteriler.values.toList(); // Hasat özeti için
          _makineler = guncelMakineler;
          _mazotlar = mazotlarRaw;
          _toplamHasilat = hasilat;
          _toplamAlacak = alacak;
          _toplamMazotBorcu = mBorc;
          _toplamBakimMasrafi = bakimMasraf;
        });
      }

    } catch (e) {
      debugPrint("❌ Kritik Yükleme Hatası: $e");
    } finally {
      if (mounted) setState(() => _yukleniyor = false);
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

      // 2. MAKİNELER DÖNGÜSÜ (Tabloya/PDF'e Yazma Kısmı)
// Makine bakımlarını da buraya ekliyoruz...
      for (var m in _makineler) {
        // 🔥 TAMİRAT: Makine ID'sini String'e zorluyoruz
        String guvenliMusteriId = (m['id'] ?? '').toString();

    final bakimlar = await DatabaseHelper.instance.bicerBakimlariniGetir(guvenliMusteriId);
    for (var b in bakimlar) {
    // Tutar dönüşümünü sağlama alıyoruz
    double tMiktar = double.tryParse(b['tutar']?.toString() ?? '0') ?? 0.0;
    toplamBakimGideri += tMiktar;

    bakimTablosu.add([
    "${m['marka']} ${m['model']}",
    b['tarih']?.toString() ?? "",
    // 🔥 TAMİRAT: Tablo şemamızda sütun adı 'parca_adi' değil 'aciklama' idi.
    // Null gelme ihtimaline karşı yedekli yazıyoruz:
    b['aciklama']?.toString() ?? b['parca_adi']?.toString() ?? "",
    "${formatPara(tMiktar)} TL"
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
    final tutarC = TextEditingController(
        text: (isVerisi['gelen_miktar'] ?? isVerisi['miktar'] ?? isVerisi['eski_miktar'] ?? "").toString()
    );

    final tarihC = TextEditingController(
        text: (isVerisi['gelen_tarih'] ?? isVerisi['tarih'] ?? DateTime.now().toString().substring(0, 10)).toString()
    );

    // AÇIKLAMA İÇİN YENİ CONTROLLER (Varsayılan olarak NAKİT TAHSİLAT)
    final aciklamaC = TextEditingController(text: "NAKİT TAHSİLAT");

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (c) => AlertDialog(
        title: Text("${isVerisi['ciftci_ad'] ?? 'Müşteri'} - ÖDEME AL"),
        content: SingleChildScrollView( // Klavye açılınca taşma yapmasın diye
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                "Kalan Borç: ${formatPara((isVerisi['toplam_tutar'] ?? 0) - (isVerisi['odenen_miktar'] ?? 0))} TL",
                style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              _input(tutarC, "Alınan Miktar", Icons.money, tip: TextInputType.number),
              _input(tarihC, "Ödeme Tarihi", Icons.calendar_today),
              // AÇIKLAMA SÜTUNU EKLEDİK
              _input(aciklamaC, "Ödeme Açıklaması", Icons.description),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text("İPTAL")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            onPressed: () async {
              double yeniGelenPara = double.tryParse(tutarC.text) ?? 0;
              if (yeniGelenPara <= 0) return;

              Navigator.of(c).pop();

              try {
                var hamId = isVerisi['id'] ?? isVerisi['id_firebase'] ?? isVerisi['is_id'] ?? isVerisi['İD'];
                if (hamId == null) return;

                int isId = int.parse(hamId.toString());

                await DatabaseHelper.instance.bicerHareketEkle({
                  'is_id': isId,
                  'ciftci_ad': isVerisi['ciftci_ad'],
                  'miktar': yeniGelenPara,
                  'tarih': tarihC.text,
                  'sezon': isVerisi['sezon'] ?? "2026",
                  'odeme_tipi': "NAKİT",
                  'tip': 'TAHSİLAT', // PDF bu kelimeye bakarak borçtan düşecek
                  'aciklama': aciklamaC.text.toUpperCase(),
                  'is_synced': 0,
                });

                // 2. ANA İŞ GÜNCELLEME (Mevcut ödenen miktarı artır)[cite: 1]
                await DatabaseHelper.instance.bicerIsGuncelle(isId, {
                  'odenen_miktar': (isVerisi['odenen_miktar'] ?? 0) + yeniGelenPara,
                });

                _verileriYukle();

                // Firebase tarafına da açıklamayı gönderelim
                _arkaPlandaBulutaGonder(isVerisi, yeniGelenPara);

                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("✅ Ödeme ve açıklama kaydedildi."), backgroundColor: Colors.green),
                );

              } catch (e) {
                debugPrint("🔥 HATA: $e");
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
                  onTap: () => _fotoSecimMenusu(i, context),
                ),
                _altButon(
                  ikon: Icons.edit_outlined,
                  renk: Colors.blue,
                  etiket: "Düzenle",
                  onTap: () => _isEkleDialog(eskiVeri: i),
                ),
                _altButon(
                  ikon: Icons.delete_outline,
                  renk: Colors.red,
                  etiket: "Sil",
                  onTap: () {
                    final dynamic silId = i['id'];
                    final String silAd = i['ciftci_ad'].toString();
                    final dynamic silFid = i['firebase_id'];

                    print("🗑️ Silme tetiklendi: ID=$silId, Ciftci=$silAd");
                    _isSilOnay(silId, silAd, silFid);
                  },
                ),
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


  // --- EVRAK/DOSYA SEÇİM MENÜSÜ ---
  void _evrakSecimMenusu(Map isVerisi, BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (c) => SafeArea(
        child: Wrap(
          children: [
            const ListTile(
              title: Text("EVRAK KAYNAĞI SEÇİN", style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt, color: Colors.blue),
              title: const Text('Belgeyi Tara (Kamera)'),
              onTap: () {
                Navigator.pop(c);
                _evrakIsle(isVerisi, ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.picture_as_pdf, color: Colors.red),
              title: const Text('Galeriden Belge Seç'),
              onTap: () {
                Navigator.pop(c);
                _evrakIsle(isVerisi, ImageSource.gallery);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _evrakIsle(Map gelenVeri, ImageSource kaynak) async {
    final ImagePicker picker = ImagePicker();

    // 1. Önce doğrudan gelen veride TC var mı diye bak
    String? tcNo = gelenVeri['tc']?.toString().trim();

    // 2. Eğer boşsa (ki senin terminalde boş görünüyor), isimden bulalım
    if (tcNo == null || tcNo.isEmpty || tcNo == "null") {
      String ciftciAdi = gelenVeri['ciftci_ad']?.toString() ?? "";

      if (ciftciAdi.isNotEmpty) {
        // DatabaseHelper'a soruyoruz
        tcNo = await DatabaseHelper.instance.tcBulIsimden(ciftciAdi);
      }
    }

    print("DEBUG - Final TC: $tcNo"); // Terminalde bunu görüyorsan işlem tamamdır[cite: 1]

    if (tcNo == null || tcNo.isEmpty) {
      _hataMesaji("HATA: '$gelenVeri['ciftci_ad']' isimli çiftçinin TC'si veritabanında bulunamadı!");
      return;
    }

    try {
      final XFile? image = await picker.pickImage(source: kaynak, imageQuality: 70);
      if (image == null) return;

      _yukleniyorGoster();

      // Artık elimizde kesin TC var, kaydı yapıyoruz[cite: 1]
      await DatabaseHelper.instance.bicerFaturaGorseliEkleTC(tcNo, File(image.path));

      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        _verileriYukle();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("✅ Evrak başarıyla kaydedildi."), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        _hataMesaji("Yükleme hatası: $e");
      }
    }
  }

// --- BU YARDIMCI WIDGET'I DA EKLE (Alt Buton Tasarımı) ---
  Widget _altButon({required IconData ikon, required Color renk, required String etiket, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.all(6.0),
        child: Column(
          children: [
            Icon(ikon, color: renk, size: 22),
            const SizedBox(height: 2),
            Text(etiket, style: TextStyle(color: renk, fontSize: 10, fontWeight: FontWeight.bold)),
          ],
        ),
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

    // 1. Kimlik Belirleme (Null-Safety ve Trim)
    // Daha önce şemada yaptığın değişikliklere göre burayı genişletiyoruz
    String tcNo = (isVerisi['tc'] ??
        isVerisi['TC'] ??
        isVerisi['tc_no'] ??
        isVerisi['id'] ??
        isVerisi['ID'] ?? '').toString().trim();

    if (tcNo.isEmpty || tcNo == "null") {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Geçerli bir kimlik bilgisi bulunamadı!")),
      );
      return;
    }

    try {
      final XFile? image = await picker.pickImage(
        source: kaynak,
        imageQuality: 50,
        maxWidth: 1080,
      );

      if (image == null || !mounted) return; // Kullanıcı vazgeçtiyse veya sayfadan çıktıysa dur

      _yukleniyorGoster();

      // DatabaseHelper'daki fonksiyonunun tcNo (String) beklediğinden emin ol
      // Çünkü firma_id'yi METİN (String) olarak güncellemiştin
      await DatabaseHelper.instance.bicerFaturaGorseliEkleTC(
          tcNo,
          File(image.path)
      );

      if (mounted) {
        // Yükleniyor diyaloğunu güvenli kapat
        Navigator.of(context, rootNavigator: true).pop();

        _verileriYukle();

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("${isVerisi['ciftci_ad'] ?? 'İşlem'} tamamlandı."),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      // Hata anında yükleniyor ekranı açıksa kapat
      if (mounted) {
        try { Navigator.of(context, rootNavigator: true).pop(); } catch (_) {}
        _hataMesaji("Hata: $e");
      }
    }
  }

// Küçük yardımcı metodlar kodun temiz kalmasını sağlar
  void _hataMesaji(String mesaj) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(mesaj), backgroundColor: Colors.red),
    );
  }

  void _yukleniyorGoster() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (c) => const Center(child: CircularProgressIndicator(color: Colors.orange)),
    );
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


  void _isSilOnay(dynamic id, String ad, dynamic fId) {
    if (id == null) {
      print("❌ HATA: ID null geldi!");
      return;
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("KAYIT SİLİNSİN Mİ?"),
        content: Text("$ad adına olan bu kayıt silinecek."),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text("VAZGEÇ")
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              try {
                // A. SQLite - Ana İşi Sil
                await DatabaseHelper.instance.bicerIsSil(id);

                // B. SQLite - O İşe Bağlı Tüm Hareketleri (Tahsilat/Borç) Sil
                // Bu satır eksik olduğu için müşteride hareketler duruyor
                await DatabaseHelper.instance.bicerHareketleriniSil(id);

                // C. Firebase - Ana İşi Sil
                if (fId != null) {
                  await FirebaseFirestore.instance.collection('bicer_isleri').doc(fId.toString()).delete();
                  print("✅ Firebase: Hasat işi silindi.");
                }

                // D. Firebase - Hareketleri Sil (DÖNGÜ İLE)
                // Firebase'de is_id'si bu olan tüm belgeleri bulup silmemiz gerekir
                var hareketler = await FirebaseFirestore.instance
                    .collection('bicermusteri_hareketleri')
                    .where('is_id', isEqualTo: id)
                    .get();

                for (var doc in hareketler.docs) {
                  await doc.reference.delete();
                }
                print("✅ Firebase: Bağlı hareketler temizlendi.");

                Navigator.pop(ctx);
                _verileriYukle(); // Ekranı tazele
              } catch (e) {
                print("❌ SİLME HATASI: $e");
              }
            },
            child: const Text("EVET, SİL"),
          ),
        ],
      ),
    );
  }

// --- PARA FORMATLAMA (Eksikti, eklendi) ---
  String formatPara(dynamic miktar) {
    double tutar = double.tryParse(miktar?.toString() ?? '0') ?? 0;
    return tutar.toStringAsFixed(0).replaceAllMapped(
        RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]}.');
  }


  void _ekstredekiSatiriSil(Map<String, dynamic> h, bool isTahsilat) {
    // Önce ID'yi sağlama alalım, patlamayı burada önleyelim
    final dynamic hamId = h['id'];
    final int? temizId = int.tryParse(hamId.toString());

    if (temizId == null) {
      debugPrint("HATA: ID bulunamadı veya geçersiz! Gelen: $hamId");
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Hata: Kayıt kimliği (ID) alınamadı!")),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text("KAYIT SİLİNECEK"),
        content: Text("Bu ${isTahsilat ? 'tahsilat' : 'hasat'} kaydı tamamen silinecek. Emin misiniz?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text("İPTAL")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              try {
                if (isTahsilat) {
                  // Temizlediğimiz int ID'yi gönderiyoruz
                  await DatabaseHelper.instance.bicerHareketSil(temizId);
                } else {
                  await DatabaseHelper.instance.bicerIsSil(temizId);
                }

                if (!mounted) return;
                Navigator.pop(c); // Onay kutusunu kapat

                // Alttaki panel açıksa onu da kapat ki liste tazelensin
                if (Navigator.canPop(context)) Navigator.pop(context);

                _verileriYukle(); // Ana ekranı tazele

                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Kayıt başarıyla silindi.")),
                );
              } catch (e) {
                debugPrint("Silme işlemi sırasında hata çıktı: $e");
              }
            },
            child: const Text("EVET, SİL", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Future<void> bicerMusteriEkstreGoster(String isim) async {
    try {
      // 1. Veriyi çek
      final List<Map<String, dynamic>> hamHareketler =
      await DatabaseHelper.instance.bicerMusteriHareketleriGetir(isim, secilenSezon);

      // 2. Çift yazma sorununu burada çözüyoruz (Filtreleme)
      final List<Map<String, dynamic>> tumHareketler = [];
      final Set<String> eklenenIsler = {};

      for (var h in hamHareketler) {
        // Hem iş ID'sini hem de tutarı birleştirerek eşsiz bir anahtar yapıyoruz
        String uniqueKey = "${h['id']}_${h['tutar'] ?? h['toplam_tutar']}_${h['islem']}";

        if (!eklenenIsler.contains(uniqueKey)) {
          tumHareketler.add(h);
          eklenenIsler.add(uniqueKey);
        }
      }

      if (!mounted) return;

      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (context) => DraggableScrollableSheet(
          initialChildSize: 0.9,
          maxChildSize: 0.95,
          minChildSize: 0.6,
          expand: false,
          builder: (_, controller) => Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Column(
              children: [
                // --- ÜST BAŞLIK ---
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
                  child: Column(
                    children: [
                      Container(width: 40, height: 5, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(10))),
                      const SizedBox(height: 10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text("$isim - EKSTRE",
                                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.orange)),
                          ),
                          IconButton(
                            icon: const Icon(Icons.picture_as_pdf, color: Colors.blue, size: 28),
                            onPressed: () => _pdfOlustur(tumHareketler, isim),
                            tooltip: "PDF Kaydet",
                          ),
                        ],
                      ),
                      const Divider(),
                    ],
                  ),
                ),

                // --- LİSTE ---
                Expanded(
                  child: tumHareketler.isEmpty
                      ? const Center(child: Text("Bu sezona ait kayıt bulunamadı."))
                      : ListView.builder(
                    controller: controller,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: tumHareketler.length,
                    itemBuilder: (context, index) {
                      final h = tumHareketler[index];
                      bool isHasat = h['hareket_tipi'] == 'BORC' || h['tip'] == 'HASAT';

                      return Card(
                        elevation: 0,
                        margin: const EdgeInsets.only(bottom: 10),
                        color: isHasat ? Colors.white : Colors.green[50],
                        shape: RoundedRectangleBorder(
                            side: BorderSide(color: Colors.grey[200]!),
                            borderRadius: BorderRadius.circular(12)),
                        child: ListTile(
                          leading: Icon(
                              isHasat ? Icons.agriculture : Icons.payments,
                              color: isHasat ? Colors.orange : Colors.green),
                          title: Text(h['islem'] ?? "", style: const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Text(h['tarih'] ?? ""),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                "${isHasat ? '+' : '-'}${formatPara(h['tutar'] ?? h['toplam_tutar'])} TL",
                                style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: isHasat ? Colors.red : Colors.green[800]),
                              ),
                              const SizedBox(width: 4),
                              PopupMenuButton<String>(
                                icon: const Icon(Icons.more_vert, size: 20),
                                onSelected: (value) async {
                                  if (value == 'duzenle') {
                                    Navigator.pop(context);
                                    if (isHasat) {
                                      final db = await DatabaseHelper.instance.database;
                                      final detayliVeriList = await db.query(
                                        'bicer_isleri',
                                        where: 'id = ?',
                                        whereArgs: [h['id']],
                                      );
                                      if (detayliVeriList.isNotEmpty) {
                                        Map<String, dynamic> tamVeri = Map.from(detayliVeriList.first);
                                        tamVeri['ciftci_ad'] = tamVeri['ciftci_ad'] ?? isim;
                                        _isEkleDialog(eskiVeri: tamVeri);
                                      }
                                    } else {
                                      final db = await DatabaseHelper.instance.database;
                                      final asilIsList = await db.query('bicer_isleri', where: 'id = ?', whereArgs: [h['is_id'] ?? h['id']]);
                                      Map<String, dynamic> dVeri = asilIsList.isNotEmpty ? Map.from(asilIsList.first) : Map.from(h);
                                      dVeri['id'] = h['is_id'] ?? h['id'];
                                      _tahsilatYapDialog(dVeri);
                                    }
                                  } else if (value == 'sil') {
                                    _hareketSilOnay(h, isHasat);
                                  }
                                },
                                itemBuilder: (context) => [
                                  const PopupMenuItem(value: 'duzenle', child: ListTile(dense: true, leading: Icon(Icons.edit, color: Colors.blue), title: Text("Düzenle"))),
                                  const PopupMenuItem(value: 'sil', child: ListTile(dense: true, leading: Icon(Icons.delete, color: Colors.red), title: Text("Sil"))),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),

                // --- ALT ÖZET PANELİ ---
                _ekstreAltPanel(tumHareketler),
              ],
            ),
          ),
        ),
      );
    } catch (e) {
      debugPrint("Ekstre Hatası: $e");
    }
  }

  Widget _ekstreAltPanel(List<Map<String, dynamic>> hareketler) {
    double tBorc = 0;
    double tOdeme = 0;

    for (var h in hareketler) {
      double tutar = double.tryParse((h['tutar'] ?? h['toplam_tutar'] ?? '0').toString()) ?? 0.0;

      // Veritabanındaki 'tip' veya 'hareket_tipi' alanına göre kontrol et
      String tip = (h['hareket_tipi'] ?? h['tip'] ?? '').toString().toUpperCase();

      if (tip == 'HASAT' || tip == 'BORC') {
        tBorc += tutar;
      } else if (tip == 'TAHSİLAT' || tip == 'ODEME') {
        tOdeme += tutar;
      }
    }
    // ... geri kalan kod aynı

    double kBorc = tBorc - tOdeme;

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 15, 20, 35),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10, offset: const Offset(0, -5))],
        borderRadius: const BorderRadius.vertical(top: Radius.circular(25)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("Toplam İş Tutarı:", style: TextStyle(color: Colors.grey, fontSize: 14)),
              Text("${formatPara(tBorc)} TL", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("Alınan Ödeme:", style: TextStyle(color: Colors.green, fontSize: 14)),
              Text("${formatPara(tOdeme)} TL", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green, fontSize: 14)),
            ],
          ),
          const Padding(padding: EdgeInsets.symmetric(vertical: 10), child: Divider()),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("KALAN BORÇ", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
                decoration: BoxDecoration(
                  color: kBorc > 0 ? Colors.red[50] : Colors.green[50],
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: kBorc > 0 ? Colors.red.shade200 : Colors.green.shade200),
                ),
                child: Text(
                  "${formatPara(kBorc)} TL",
                  style: TextStyle(
                      fontWeight: FontWeight.w900,
                      color: kBorc > 0 ? Colors.red[900] : Colors.green[900],
                      fontSize: 22),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _pdfOlustur(List<Map<String, dynamic>> hareketler, String musteriAdi) async {
    try {
      await PdfHelper.bicerMusteriEkstresiGoster(context, musteriAdi, hareketler);
    } catch (e) {
      debugPrint("PDF Hatası: $e");
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
              await DatabaseHelper.instance.bicerEkstreSatirSil(
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
    // Veritabanından listeyi çekiyoruz
    final ciftciler = await DatabaseHelper.instance.ciftciListesiGetir();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (c) => Container(
        padding: const EdgeInsets.all(16),
        height: MediaQuery.of(context).size.height * 0.8,
        child: Column(
          children: [
            // --- ÜST BAŞLIK VE EKLE BUTONU ---
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                    "ÇİFTÇİ REHBERİ",
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)
                ),
                ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(c);
                    _ciftciEkleDialog();
                  },
                  icon: const Icon(Icons.person_add),
                  label: const Text("Yeni Ekle"),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white
                  ),
                )
              ],
            ),
            const Text(
                "İsme tıkla: Ekstre | Sola kaydır: Sil",
                style: TextStyle(fontSize: 10, color: Colors.grey)
            ),
            const Divider(),

            Expanded(
              child: ListView.builder(
                itemCount: ciftciler.length,
                itemBuilder: (context, index) {
                  final cf = ciftciler[index];

                  // HATA ÖNLEME: ID ve İsim değerlerini sağlama alıyoruz
                  final String safeId = cf['id']?.toString() ?? "0";
                  final String safeAd = cf['ad_soyad']?.toString() ?? "Bilinmeyen Çiftçi";

                  return Dismissible(
                    // Key null olamaz, o yüzden safeId kullanıyoruz
                    key: Key("ciftci_$safeId"),
                    direction: DismissDirection.endToStart,
                    background: Container(
                      color: Colors.red,
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.only(right: 20),
                      child: const Icon(Icons.delete, color: Colors.white),
                    ),
                    confirmDismiss: (dir) async {
                      // Silme onayına gönderirken tekrar int'e çeviriyoruz
                      _ciftciSilOnay(int.tryParse(safeId) ?? 0, safeAd);
                      return false; // Dismissible'ın kendi silmesini engelle, biz manuel siliyoruz
                    },
                    child: ListTile(
                      leading: const CircleAvatar(child: Icon(Icons.person)),
                      title: Text(safeAd),
                      subtitle: Text(cf['telefon'] ?? "Telefon Yok"),
                      trailing: IconButton(
                        icon: const Icon(Icons.picture_as_pdf, color: Colors.red),
                        onPressed: () {
                          Navigator.pop(context);
                          _pdfOnizlemeGoster(context, ciftciAdi: safeAd);
                        },
                      ),
                      onTap: () {
                        Navigator.pop(context);
                        // Eğer bu fonksiyon tanımlı değilse _pdfOnizlemeGoster de kullanabilirsin
                        bicerMusteriEkstresiGoster(safeAd);
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
    final tcC = TextEditingController();
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
              // TC Kimlik No Alanı - Kısıtlamalar Eklendi
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: TextField(
                  controller: tcC,
                  keyboardType: TextInputType.number,
                  // Sadece 11 hane ve sadece rakam izni verir
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(11),
                  ],
                  decoration: const InputDecoration(
                    labelText: "TC Kimlik No",
                    prefixIcon: Icon(Icons.badge),
                    border: OutlineInputBorder(),
                    helperText: "Tam 11 hane olmalıdır",
                  ),
                ),
              ),
              _input(adC, "Ad Soyad", Icons.person),
              _input(telC, "Telefon", Icons.phone, tip: TextInputType.phone),
              _input(adresC, "Adres", Icons.location_on),
              _input(notC, "Özel Not", Icons.note_alt),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text("İPTAL")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            onPressed: () async {
              // TC Hanelerini ve İsim Boşluğunu Kontrol Et
              if (adC.text.trim().isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Lütfen Ad Soyad giriniz!"), backgroundColor: Colors.red),
                );
                return;
              }

              if (tcC.text.length != 11) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("TC Kimlik No 11 haneli olmalıdır!"), backgroundColor: Colors.red),
                );
                return;
              }

              // Eğer kontrollerden geçtiyse kayıt başlar
              String tcNo = tcC.text.trim();
              Navigator.pop(c); // Pencereyi kapat

              Map<String, dynamic> ciftciVerisi = {
                'tc': tcNo,
                'ad_soyad': adC.text.toUpperCase(),
                'telefon': telC.text,
                'adres': adresC.text,
                'notlar': notC.text,
                'firebase_id': tcNo,
                'sube': "TEFENNİ",
              };

              try {
                // Firebase ve Yerel Veritabanı Kaydı
                await FirebaseFirestore.instance
                    .collection('bicer_musterileri')
                    .doc(tcNo)
                    .set(ciftciVerisi);

                await DatabaseHelper.instance.ciftciEkle({
                  ...ciftciVerisi,
                  'id': int.tryParse(tcNo.substring(tcNo.length - 9)) ?? 0,
                  'is_synced': 1,
                });

                _verileriYukle();

                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("✅ Çiftçi başarıyla kaydedildi."), backgroundColor: Colors.green),
                  );
                }
              } catch (e) {
                debugPrint("Kayıt hatası: $e");
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text("⚠️ Hata oluştu: $e"), backgroundColor: Colors.orange),
                  );
                }
              }
            },
            child: const Text("KAYDET", style: TextStyle(color: Colors.white)),
          )
        ],
      ),
    );
  }

  void bicerMusteriEkstresiGoster(String isim) async {
    try {
      final List<Map<String, dynamic>> tumHareketler =
      await DatabaseHelper.instance.bicerMusteriHareketleriGetir(isim, secilenSezon);

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
                Container(
                    width: 40,
                    height: 5,
                    decoration: BoxDecoration(
                        color: Colors.grey[300],
                        borderRadius: BorderRadius.circular(10))),
                const SizedBox(height: 10),
                Text("$isim - CARİ EKSTRE",
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const Divider(),

                Expanded(
                  child: tumHareketler.isEmpty
                      ? const Center(child: Text("Bu müşteriye ait kayıt bulunamadı."))
                      : ListView.builder(
                    controller: controller,
                    itemCount: tumHareketler.length,
                    itemBuilder: (context, index) {
                      final h = tumHareketler[index];

                      // ✅ TEK NOKTADAN TİP OKUMA (PDF ile aynı mantık)
                      String tip = (h['tip'] ?? h['hareket_tipi'] ?? '')
                          .toString()
                          .toUpperCase()
                          .trim();

                      // 🔥 TÜM OLASILIKLARI YAKALA
                      bool isHasat = tip.contains('HASAT') ||
                          tip.contains('BORC') ||
                          tip.contains('BORÇ') ||
                          tip.contains('IS') ||
                          tip.contains('İS');

                      // ✅ TEK NOKTADAN TUTAR OKUMA (ARTIK HER YERDE AYNI)
                      double tutar = double.tryParse(
                          (h['miktar'] ?? h['tutar'] ?? h['toplam_tutar'] ?? 0)
                              .toString()) ??
                          0.0;

                      return Dismissible(
                        key: Key("${isHasat ? 'hasat' : 'tahsilat'}_${h['id']}"),
                        direction: DismissDirection.endToStart,
                        background: Container(
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          decoration: BoxDecoration(
                              color: Colors.red,
                              borderRadius: BorderRadius.circular(10)),
                          child: const Icon(Icons.delete, color: Colors.white),
                        ),
                        confirmDismiss: (direction) async => await _kayitSilOnay(h),
                        child: Card(
                          elevation: 0,
                          color: isHasat ? Colors.white : Colors.green[50],
                          shape: RoundedRectangleBorder(
                              side: BorderSide(color: Colors.grey[200]!),
                              borderRadius: BorderRadius.circular(10)),
                          child: ListTile(
                            onTap: () {
                              if (isHasat) {
                                Navigator.pop(context);
                                _isEkleDialog(eskiVeri: h);
                              } else {
                                _tahsilatGuncelleDialog(h);
                              }
                            },
                            leading: Icon(
                                isHasat ? Icons.agriculture : Icons.payments,
                                color: isHasat ? Colors.blue : Colors.green),
                            title: Text(h['islem'] ??
                                (isHasat ? "HASAT KAYDI" : "NAKİT TAHSİLAT")),
                            subtitle: Text("${h['tarih']}"),
                            trailing: Text(
                              "${isHasat ? '+' : '-'}${formatPara(tutar)} TL",
                              style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: isHasat ? Colors.red : Colors.green),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),

                // ✅ ALT PANEL AYNI MANTIKLA
                _ekstreOzetPaneliYeni(tumHareketler)
              ],
            ),
          ),
        ),
      );
    } catch (e) {
      debugPrint("Ekstre Hatası: $e");
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text("Hata: $e")));
    }
  }

//////////////////////////////////////////////////////////////
// ✅ ÖZET PANELİ (PDF İLE %100 AYNI MANTIK)
//////////////////////////////////////////////////////////////

  Widget _ekstreOzetPaneliYeni(List<Map<String, dynamic>> hareketler) {
    double toplamBorc = 0;
    double toplamTahsilat = 0;

    for (var h in hareketler) {
      double tutar = double.tryParse(
          (h['miktar'] ?? h['tutar'] ?? h['toplam_tutar'] ?? 0).toString()) ??
          0.0;

      String tip = (h['tip'] ?? h['hareket_tipi'] ?? '')
          .toString()
          .toUpperCase()
          .trim();

      // 🔥 AYNI AYRIM (PDF ile birebir)
      if (tip.contains('HASAT') ||
          tip.contains('BORC') ||
          tip.contains('BORÇ') ||
          tip.contains('IS') ||
          tip.contains('İS')) {
        toplamBorc += tutar;
      } else {
        toplamTahsilat += tutar;
      }
    }

    double kalan = toplamBorc - toplamTahsilat;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: Colors.grey[50],
          border: Border(top: BorderSide(color: Colors.grey[300]!))),
      child: Column(
        children: [
          _ozetSatir("Toplam İş (Borç):", formatPara(toplamBorc), Colors.red),
          _ozetSatir("Toplam Tahsilat:", formatPara(toplamTahsilat), Colors.green),
          const Divider(),
          _ozetSatir(
              "GÜNCEL BAKİYE:",
              formatPara(kalan),
              kalan > 0 ? Colors.red : Colors.blue,
              bold: true),
        ],
      ),
    );
  }

  Widget _ozetSatir(String baslik, String deger, Color renk,
      {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(baslik,
              style: TextStyle(
                  fontWeight: bold ? FontWeight.bold : FontWeight.normal,
                  fontSize: bold ? 16 : 14)),
          Text("$deger TL",
              style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: renk,
                  fontSize: bold ? 18 : 14)),
        ],
      ),
    );
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
                await DatabaseHelper.instance.bicerEkstreSatirSil(
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
  void _ciftciSilOnay(dynamic id, String isim) {
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text("KAYIT SİLİNECEK"),
        content: Text("$isim rehberden silinecek. Emin misiniz?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text("İPTAL")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              try {
                await DatabaseHelper.instance.database.then((db) async {
                  if (id != null && id != 0) {
                    await db.delete('bicer_musterileri', where: 'id = ?', whereArgs: [id]);
                  } else {
                    await db.delete('bicer_musterileri', where: 'ad_soyad = ?', whereArgs: [isim]);
                  }
                });

                // Firebase silme işlemi
                await FirebaseFirestore.instance
                    .collection('bicer_musterileri')
                    .where('ad_soyad', isEqualTo: isim)
                    .get()
                    .then((snapshot) {
                  for (var doc in snapshot.docs) {
                    doc.reference.delete();
                  }
                });

                // 1. Silme onay diyaloğunu kapat
                Navigator.pop(c);

                // 2. Açık olan Çiftçi Rehberi (BottomSheet) penceresini kapat
                Navigator.pop(context);

                // 3. Ana sayfadaki verileri arkada tazele
                await _verileriYukle();

                // 4. Rehberi GÜNCEL haliyle tekrar aç
                _ciftciListesiDialog();

                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text("$isim silindi."), backgroundColor: Colors.orange),
                );
              } catch (e) {
                debugPrint("Silme hatası: $e");
                // Hata olursa en azından onay kutusunu kapat
                Navigator.pop(c);
              }
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
    // 1. Veritabanından güncel çiftçi rehberini çekiyoruz
    final tumCiftciler = await DatabaseHelper.instance.ciftciListesiGetir();

    // 2. Kontrolcüleri (Controllers) hazırlıyoruz
    final ciftciC = TextEditingController(text: eskiVeri?['ciftci_ad']);
    final mevkiC = TextEditingController(text: (eskiVeri?['mevki'] ?? "").toString());
    final dekarC = TextEditingController(text: eskiVeri?['dekar']?.toString());
    final fiyatC = TextEditingController(
        text: (eskiVeri?['birim_fiyat'] ?? eskiVeri?['fiyat'] ?? "").toString()
    );
    final alinanC = TextEditingController(
        text: (eskiVeri?['odenen_miktar'] ?? "0").toString()
    );

    int? secilenBicerId = eskiVeri?['bicer_id'];
    String? secilenCiftciAdi = eskiVeri?['ciftci_ad'];
    String secilenUrun = eskiVeri?['urun_tipi'] ?? "BUĞDAY";

    // Yeni kayıtta varsayılan fiyatı ata
    if (eskiVeri == null && fiyatC.text.isEmpty) {
      fiyatC.text = bugdayFiyat.toString();
    }

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          // Anlık hesaplama değişkenleri
          double d = double.tryParse(dekarC.text) ?? 0;
          double f = double.tryParse(fiyatC.text) ?? 0;
          double alinan = double.tryParse(alinanC.text) ?? 0;
          double anlikToplam = d * f;
          double anlikKalan = anlikToplam - alinan;

          // TextField değiştikçe rakamları güncellemek için yardımcı
          void hesapla() => setDialogState(() {});

          return AlertDialog(
            title: Text(eskiVeri == null ? "🚜 YENİ HASAT KAYDI" : "📝 HASAT GÜNCELLE"),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // --- MAKİNE SEÇİMİ ---
                  DropdownButtonFormField<int>(
                    value: secilenBicerId,
                    hint: const Text("MAKİNE SEÇ"),
                    items: _makineler.map((m) => DropdownMenuItem(value: m['id'] as int, child: Text("${m['marka']} ${m['model']}"))).toList(),
                    onChanged: (v) => setDialogState(() => secilenBicerId = v),
                    decoration: const InputDecoration(border: OutlineInputBorder(), labelText: "Biçer Seç"),
                  ),
                  const SizedBox(height: 10),

                  // --- ÜRÜN TİPİ VE OTOMATİK FİYAT ---
                  DropdownButtonFormField<String>(
                    value: secilenUrun,
                    items: ["BUĞDAY", "ARPA", "DANELİK MISIR", "SOSLUK MISIR"].map((u) => DropdownMenuItem(value: u, child: Text(u))).toList(),
                    onChanged: (v) {
                      setDialogState(() {
                        secilenUrun = v!;
                        // Fiyatları otomatik güncelle
                        if (v == "BUĞDAY") fiyatC.text = bugdayFiyat.toString();
                        if (v == "ARPA") fiyatC.text = arpaFiyat.toString();
                        if (v == "DANELİK MISIR") fiyatC.text = danelikMisirFiyat.toString();
                        if (v == "SOSLUK MISIR") fiyatC.text = soslukMisirFiyat.toString();
                      });
                    },
                    decoration: const InputDecoration(border: OutlineInputBorder(), labelText: "Ürün Tipi"),
                  ),
                  const SizedBox(height: 10),

                  // --- REHBERDEN ÇİFTÇİ SEÇİMİ ---
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
                  _input(mevkiC, "TARLA ADI / MEVKİ (Örn: Köy Altı)", Icons.location_on),
                  _input(dekarC, "DEKAR", Icons.straighten, tip: TextInputType.number, onChanged: (v) => hesapla()),
                  _input(fiyatC, "BİRİM FİYAT", Icons.payments, tip: TextInputType.number, onChanged: (v) => hesapla()),
                  _input(alinanC, "ALINAN NAKİT (PEŞİNAT)", Icons.money, tip: TextInputType.number, onChanged: (v) => hesapla()),

                  const SizedBox(height: 15),

                  // --- ANLIK HESAPLAMA TABELASI ---
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
                      _isSilOnay(eskiVeri['id'], eskiVeri['ciftci_ad'], eskiVeri['firebase_id']);
                    }
                ),
              const SizedBox(width: 20),
              TextButton(onPressed: () => Navigator.pop(context), child: const Text("İPTAL")),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: anaTuruncu),
                onPressed: () async {
                  if (secilenBicerId == null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text("LÜTFEN MAKİNE SEÇİN!"), backgroundColor: Colors.red),
                    );
                    return;
                  }
                  if (ciftciC.text.isEmpty) return;

                  double d = double.tryParse(dekarC.text) ?? 0;
                  double f = double.tryParse(fiyatC.text) ?? 0;
                  double alinan = double.tryParse(alinanC.text) ?? 0;
                  double toplam = d * f;
                  String ciftciAdi = ciftciC.text.trim().toUpperCase();
                  String mevkiAdi = mevkiC.text.trim().toUpperCase();

                  Map<String, dynamic> veri = {
                    'ciftci_ad': ciftciAdi,
                    'mevki': mevkiAdi,
                    'dekar': d,
                    'fiyat': f,
                    'toplam_tutar': toplam,
                    'odenen_miktar': alinan,
                    'urun_tipi': secilenUrun,
                    'sezon': secilenSezon,
                    'tarih': eskiVeri?['tarih'] ?? DateTime.now().toString().substring(0, 10),
                    'is_synced': 0,
                    'bicer_id': secilenBicerId,
                  };

                  try {
                    if (eskiVeri == null) {
                      // 1. İş Kaydını Ekle
                      var yeniId = await DatabaseHelper.instance.bicerIsEkle(veri);

                      // 2. Müşteri Hareketine BORÇ Olarak Ekle
                      await DatabaseHelper.instance.bicerHareketEkle({
                        'is_id': yeniId,
                        'ciftci_ad': ciftciAdi,
                        'miktar': toplam,
                        'tip': 'HASAT',
                        'tarih': veri['tarih'],
                        'sezon': secilenSezon,
                        'aciklama': "$mevkiAdi - $secilenUrun HASATI"
                      });

                      // 3. Eğer Peşinat Varsa Tahsilat Olarak Ekle
                      if (alinan > 0) {
                        await DatabaseHelper.instance.bicerHareketEkle({
                          'is_id': yeniId,
                          'ciftci_ad': ciftciAdi,
                          'miktar': alinan,
                          'tip': 'TAHSİLAT',
                          'tarih': veri['tarih'],
                          'sezon': secilenSezon,
                          'aciklama': "HASAT PEŞİNATI"
                        });
                      }
                    } else {
                      // Güncelleme mantığı
                      await DatabaseHelper.instance.bicerIsGuncelle(eskiVeri['id'], veri);
                    }

                    if (mounted) {
                      Navigator.pop(context);
                      _verileriYukle();
                    }
                  } catch (e) {
                    debugPrint("❌ Kayıt Hatası: $e");
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
    await _verileriYukle(); // 🔥 EKLE
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
                          // Mazot takip listesi içindeki silme ve yükleme mantığı
                          onPressed: () async {
                            // Mazot kaydını hem yerelden hem Firebase'den siliyoruz
                            await DatabaseHelper.instance.mazotSil(
                                m['id'],
                                firebaseId: m['firebase_id']?.toString()
                            );

                            if (mounted) {
                              Navigator.pop(c); // Modalı kapatıp veriyi tazeleyelim
                              _verileriYukle();
                              ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text("Mazot fişi silindi."))
                              );
                            }
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



  // Makineye Bakım/Masraf Ekleme Diyaloğu
  void _bakimEkleDialog(int makineId, String marka) {
    final parcaC = TextEditingController();
    final tutarC = TextEditingController();
    final tarihC = TextEditingController(text: DateTime.now().toString().substring(0, 10));

    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: Text("$marka - MASRAF EKLE"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _input(parcaC, "Yapılan İşlem / Parça", Icons.settings),
            _input(tutarC, "Tutar", Icons.money, tip: TextInputType.number),
            _input(tarihC, "Tarih", Icons.calendar_today),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text("İPTAL")),
          ElevatedButton(
            onPressed: () async {
              await DatabaseHelper.instance.bicerBakimEkle({
                'bicer_id': makineId,
                'parca_adi': parcaC.text.toUpperCase(),
                'tutar': double.tryParse(tutarC.text) ?? 0,
                'tarih': tarihC.text,
                'sezon': secilenSezon,
              });
              Navigator.pop(c);
              _verileriYukle();
            },
            child: const Text("KAYDET"),
          )
        ],
      ),
    );
  }


  // 3. MASRAF LİSTESİ GÖSTERME FONKSİYONU
// 🔥 TAMİRAT: Parametreyi 'dynamic' veya 'String' yapıyoruz ki çağrılan yerde patlamasın
  void _makineMasrafListesiGoster(dynamic bicerId, String ad) async {
    final b = await DatabaseHelper.instance.bicerBakimlariniGetir(bicerId.toString());

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
                  // Tutar hesaplama
                  double lt = double.tryParse(litreC.text) ?? 0;
                  double fr = double.tryParse(fiyatC.text) ?? 0;
                  double yeniTutar = lt * fr;

                  if (petrolC.text.isEmpty) return;

                  try {
                    // 1. Veriyi Hazırla (Önemli: id'yi verinin içine dahil etme, sadece güncelleme için kullan)
                    Map<String, dynamic> guncelVeri = {
                      'petrol_adi': petrolC.text.toUpperCase(),
                      'litre': lt,
                      'tutar': yeniTutar,
                      'odenen': double.tryParse(odenenC.text) ?? 0,
                      'tarih': tarihC.text,
                      'sezon': m['sezon'],
                      'firebase_id': m['firebase_id'],
                    };

                    print("🛠️ Güncelleme Başlıyor: ID=${m['id']} - FirebaseID=${m['firebase_id']}");

                    // 2. Yerel Veritabanını Güncelle
                    // NOT: DatabaseHelper içindeki mazotGuncelle fonksiyonunun
                    // 'bicer_mazotlar' tablosuna baktığından emin ol abi.
                    await DatabaseHelper.instance.mazotGuncelle(m['id'], guncelVeri);

                    // 3. Firebase Güncelle (Eğer ID varsa)
                    if (m['firebase_id'] != null) {
                      await FirebaseFirestore.instance
                          .collection('bicer_mazotlar')
                          .doc(m['firebase_id'].toString())
                          .set(guncelVeri, SetOptions(merge: true)); // update yerine set(merge:true) daha güvenli

                      print("✅ Firebase mühürlendi.");
                    }

                    if (mounted) {
                      Navigator.pop(c);
                      // 🔥 Listeyi tazelemeyi unutma
                      await _verileriYukle();
                    }

                  } catch (e) {
                    print("❌ GÜNCELLEME HATASI: $e");
                    // Kullanıcıya hata olduğunu bildir (isteğe bağlı)
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text("Güncelleme başarısız: $e")),
                    );
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