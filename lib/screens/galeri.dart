import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../db/database_helper.dart';
import 'EksperDetay.dart';
import 'bakim_paneli.dart'; // Sol tarafta küçük harfle görünüyor, öyle yaz
import 'SatisPaneli.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter/services.dart'; // rootBundle için
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:typed_data';
import 'package:intl/intl.dart'; // Tarih formatlama için
import 'package:printing/printing.dart'; // PdfPreview ve GoogleFonts için
import 'package:flutter/foundation.dart' show kIsWeb; //
import 'dart:io' as io; // File hatasını engellemek için 'as io' dedik[cite: 1]
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'dart:io' show File;


class GaleriPaneli extends StatefulWidget {
  const GaleriPaneli({super.key});

  @override
  State<GaleriPaneli> createState() => _GaleriPaneliState();
}

class _GaleriPaneliState extends State<GaleriPaneli> {
  List<Map<String, dynamic>> _araclar = [];
  final Color anaMavi = const Color(0xFF0288D1);
  final Color zeminBeyaz = const Color(0xFFF8FAFC);
  String _aktifMod = "TANIM";
  final ImagePicker _picker = ImagePicker();

  // --- DÜKKAN ÖZETİ İÇİN DEĞİŞKENLER ---
  int _toplamArac = 0;
  int _satilanArac = 0;





  Widget buildImage(String path) {
    if (kIsWeb) {
      return Image.network(path); // web
    } else {
      return Image.file(File(path)); // mobil
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
    _araclariGetir();
  }



  // BU FONKSİYON SINIFIN İÇİNDE AMA DİĞER METOTLARIN DIŞINDA OLMALI
  Future<void> _bulutaSenkronizeEt(int id, Map<String, dynamic> veri) async {
    try {
      await FirebaseFirestore.instance
          .collection('araclar')
          .doc(id.toString())
          .set(veri);

      // Başarılıysa yerelde 'senkronize edildi' olarak işaretle
      await DatabaseHelper.instance.aracGuncelle(id, {'is_synced': 1});
      debugPrint("✅ Bulut senkronize edildi ID: $id");
    } catch (e) {
      // İnternet yoksa buraya düşer, hata vermez, is_synced 0 kalır.
      debugPrint("⚠️ İnternet yok, veri kuyrukta bekliyor.");
    }
  }

  Future<void> _araclariGetir() async {
    final veriler = await DatabaseHelper.instance.aracListesi();
    int satilan = 0;
    for (var a in veriler) {
      if (a['durum'] == 'SATILDI') satilan++;
    }
    setState(() {
      _araclar = veriler;
      _toplamArac = veriler.length;
      _satilanArac = satilan;
    });
  }

  // Kamera mı Galeri mi Seçimi
  Future<void> _fotoSec(StateSetter setDialogState, Function(String) onSecildi) async {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(leading: const Icon(Icons.photo_library), title: const Text('Galeriden Seç'), onTap: () async {
              final XFile? pick = await _picker.pickImage(source: ImageSource.gallery);
              if (pick != null) { onSecildi(pick.path); Navigator.pop(context); }
            }),
            ListTile(leading: const Icon(Icons.camera_alt), title: const Text('Kamerayla Çek'), onTap: () async {
              final XFile? pick = await _picker.pickImage(source: ImageSource.camera);
              if (pick != null) { onSecildi(pick.path); Navigator.pop(context); }
            }),
          ],
        ),
      ),
    );
  }

  // --- KURUMSAL TEK ARAÇ RAPORU (KOPYALA-YAPIŞTIR) ---
  Future<void> _tekAracKurumsalRapor(Map arac) async {
    try {
      final pdf = pw.Document();
      final fontData = await rootBundle.load("assets/fonts/arial.ttf");
      final ttf = pw.Font.ttf(fontData);

      // Logo Yükleme
      final logoImage = pw.MemoryImage(
        (await rootBundle.load("assets/images/logo.png")).buffer.asUint8List(),
      );

      final masraflar = await DatabaseHelper.instance.bakimlariGetir(arac['id']);
      final satis = await DatabaseHelper.instance.satisGetir(arac['id']);

      double toplamMasraf = 0;
      for (var m in masraflar) {
        toplamMasraf += double.tryParse(m['tutar'].toString()) ?? 0.0;
      }

      pdf.addPage(
        pw.Page(
          theme: pw.ThemeData.withFont(base: ttf),
          build: (context) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text("ÖZÇOBAN TİCARET GRUBU", style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold, color: PdfColors.blue800)),
                      pw.Text("OTO GALERİ ARAÇ HAREKET FORMU", style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
                    ],
                  ),
                  pw.Container(width: 70, height: 70, child: pw.Image(logoImage)),
                ],
              ),
              pw.Divider(thickness: 1.5),
              pw.SizedBox(height: 15),
              pw.Container(
                padding: const pw.EdgeInsets.all(8),
                decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                child: pw.Row(children: [
                  pw.Text("PLAKA: ${arac['plaka']}", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 14)),
                  pw.Spacer(),
                  pw.Text("DURUM: ${arac['durum']}", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: arac['durum'] == 'SATILDI' ? PdfColors.green : PdfColors.orange)),
                ]),
              ),
              pw.SizedBox(height: 10),
              _pdfOzetSatir("Marka / Model:", "${arac['marka']} ${arac['model']}"),
              _pdfOzetSatir("Motor / Paket:", "${arac['motor_tipi']} / ${arac['paket']}"),
              _pdfOzetSatir("Kilometre:", "${arac['km']} KM"),
              _pdfOzetSatir("Alış Tarihi / Fiyatı:", "${arac['alis_tarihi']} / ${arac['alis_fiyati']} TL"),
              pw.SizedBox(height: 20),
              pw.Text("BAKIM VE EKSPERTİZ MASRAFLARI", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.red900)),
              pw.Divider(),
              ...masraflar.map((m) => _pdfOzetSatir("- ${m['islem_detay']}", "${m['tutar']} TL", PdfColors.red)),
              pw.Divider(),
              _pdfOzetSatir("TOPLAM MASRAF:", "$toplamMasraf TL", PdfColors.red800),
              _pdfOzetSatir("ARAÇ MALİYETİ (ALIŞ+MASRAF):", "${(arac['alis_fiyati'] + toplamMasraf).toStringAsFixed(2)} TL", PdfColors.blue800),
              if (arac['durum'] == 'SATILDI' && satis.isNotEmpty) ...[
                pw.SizedBox(height: 20),
                pw.Text("SATIŞ BİLGİLERİ", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.green900)),
                pw.Divider(),
                _pdfOzetSatir("Müşteri Adı:", "${satis[0]['musteri_ad']}"),
                _pdfOzetSatir("Satış Fiyatı:", "${satis[0]['satis_fiyati']} TL", PdfColors.green),
                _pdfOzetSatir("Kalan Bakiye:", "${satis[0]['kalan_tutar']} TL", PdfColors.red),
              ],
              pw.Spacer(),
              pw.Center(child: pw.Text("Evren Özçoban Yazılımı - Kurumsal Rapor Sistemi", style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey))),
            ],
          ),
        ),
      );

      final dir = await getTemporaryDirectory();
      final file = File("${dir.path}/${arac['plaka']}_Rapor.pdf");
      await file.writeAsBytes(await pdf.save());
      await Share.shareXFiles([XFile(file.path)], text: '${arac['plaka']} Raporu');
    } catch (e) {
      debugPrint("PDF Hatası: $e");
    }
  }


  Future<void> _galeriPdfRaporu() async {
    // --- PARA FORMATLAYICI (TL) ---
    final tlFormat = NumberFormat.currency(locale: 'tr_TR', symbol: '₺', decimalDigits: 2);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator(color: Colors.blue)),
    );

    try {
      final pdf = pw.Document();
      final font = await PdfGoogleFonts.robotoRegular();
      final boldFont = await PdfGoogleFonts.robotoBold();

      pw.MemoryImage? logoResmi;
      try {
        final ByteData logoData = await rootBundle.load('assets/images/logo.png');
        logoResmi = pw.MemoryImage(logoData.buffer.asUint8List());
      } catch (e) { debugPrint("Logo hatası: $e"); }

      double dukkanToplamAlis = 0;
      double dukkanToplamMasraf = 0;
      double dukkanToplamSatis = 0;

      List<List<dynamic>> tabloVerisi = [];

      for (var a in _araclar) {
        final int guvenliId = int.tryParse(a['id'].toString()) ?? 0;

        final bakimlar = await DatabaseHelper.instance.bakimlariGetir(guvenliId);
        double aracMasraf = 0;
        for (var b in bakimlar) {
          aracMasraf += double.tryParse(b['tutar']?.toString() ?? "0") ?? 0;
        }

        final satislar = await DatabaseHelper.instance.satisGetir(guvenliId);
        double aracSatis = (a['durum'] == 'SATILDI' && satislar.isNotEmpty)
            ? (double.tryParse(satislar[0]['satis_fiyati']?.toString() ?? "0") ?? 0)
            : 0;

        double alis = double.tryParse(a['alis_fiyati']?.toString() ?? "0") ?? 0;

        dukkanToplamAlis += alis;
        dukkanToplamMasraf += aracMasraf;
        dukkanToplamSatis += aracSatis;

        // --- TABLO İÇİ FORMATLAMA ---
        tabloVerisi.add([
          "${a['plaka']}\n${a['marka']} ${a['model']}".toUpperCase(),
          a['durum'].toString().toUpperCase(),
          tlFormat.format(alis),
          tlFormat.format(aracMasraf),
          tlFormat.format(aracSatis),
        ]);
      }

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          theme: pw.ThemeData.withFont(base: font, bold: boldFont),
          build: (pw.Context context) => [
            // BAŞLIK KISMI
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Row(children: [
                  if (logoResmi != null) pw.Container(width: 50, height: 50, child: pw.Image(logoResmi)),
                  pw.SizedBox(width: 10),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text("ÖZÇOBAN TİCARET", style: pw.TextStyle(font: boldFont, fontSize: 18, color: PdfColors.blue900)),
                      pw.Text("Evren Özçoban | BURDUR", style: const pw.TextStyle(fontSize: 10)),
                    ],
                  ),
                ]),
                pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
                  pw.Text("GÜNCEL STOK VE MALİYET RAPORU", style: pw.TextStyle(font: boldFont, fontSize: 11)),
                  pw.Text(DateFormat('dd.MM.yyyy HH:mm').format(DateTime.now()), style: const pw.TextStyle(fontSize: 9)),
                ]),
              ],
            ),
            pw.Divider(thickness: 1, color: PdfColors.blue900),
            pw.SizedBox(height: 15),

            // --- ÜST ÖZET KUTULARI (TL FORMATLI) ---
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                _pdfKutu("TOPLAM ALIŞ", tlFormat.format(dukkanToplamAlis), PdfColors.black, boldFont),
                _pdfKutu("TOPLAM MASRAF", tlFormat.format(dukkanToplamMasraf), PdfColors.red900, boldFont),
                _pdfKutu("TOPLAM SATIŞ", tlFormat.format(dukkanToplamSatis), PdfColors.green900, boldFont),
                _pdfKutu("NET KÂR", tlFormat.format(dukkanToplamSatis - (dukkanToplamAlis + dukkanToplamMasraf)), PdfColors.blue900, boldFont),
              ],
            ),
            pw.SizedBox(height: 20),

            // --- ANA TABLO ---
            pw.TableHelper.fromTextArray(
              headers: ['ARAÇ / PLAKA', 'DURUM', 'ALIŞ MİY.', 'MASRAF', 'SATIŞ BED.'],
              data: tabloVerisi,
              headerStyle: pw.TextStyle(font: boldFont, color: PdfColors.white, fontSize: 9),
              headerDecoration: const pw.BoxDecoration(color: PdfColors.blue900),
              cellAlignment: pw.Alignment.centerLeft,
              cellStyle: const pw.TextStyle(fontSize: 8),
              columnWidths: {
                0: const pw.FlexColumnWidth(3),
                1: const pw.FlexColumnWidth(1.5),
                2: const pw.FlexColumnWidth(2),
                3: const pw.FlexColumnWidth(2),
                4: const pw.FlexColumnWidth(2),
              },
            ),
          ],
        ),
      );

      if (mounted) Navigator.pop(context);

      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => Scaffold(
            appBar: AppBar(title: const Text("Rapor Önizleme"), backgroundColor: Colors.black),
            body: PdfPreview(build: (format) => pdf.save(), canDebug: false),
          ),
        ),
      );

    } catch (e) {
      if (mounted) Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Hata: $e")));
    }
  }

// Yardımcı Kutu Widget (PDF İçin)
  pw.Widget _pdfKutu(String baslik, String deger, PdfColor renk, pw.Font font) {
    return pw.Container(
      width: 110,
      padding: const pw.EdgeInsets.all(6),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey300),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
      ),
      child: pw.Column(
        children: [
          pw.Text(baslik, style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
          pw.SizedBox(height: 2),
          pw.Text(deger, style: pw.TextStyle(font: font, fontSize: 11, color: renk)),
        ],
      ),
    );
  }
// Parametrelerin yanına '?' ve '[]' ekledik, böylece boş bırakılabilir oldular.
  pw.Widget _pdfOzetSatir(String etiket, String deger, [PdfColor? renk, pw.Font? font]) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          // Font varsa kullan, yoksa varsayılan kalsın
          pw.Text(etiket, style: pw.TextStyle(font: font, fontSize: 10)),
          pw.Text(
              deger,
              style: pw.TextStyle(
                font: font,
                fontSize: 10,
                fontWeight: pw.FontWeight.bold,
                color: renk ?? PdfColors.black, // Renk verilmezse siyah yapar
              )
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: zeminBeyaz,
      // Scaffold içindeki AppBar kısmını şöyle güncelle:
      appBar: AppBar(
        title: Text("ÖZÇOBAN OTO GALERİ - $_aktifMod", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        backgroundColor: anaMavi,
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.picture_as_pdf, color: Colors.white),
            onPressed: _galeriPdfRaporu, // Yukarıda yazdığımız metodu çağırıyoruz
            tooltip: "PDF Rapor Al",
          )
        ],
      ),
      body: Column(
        children: [
          _ustMenu(),
          _skorTabelasi(), // PAŞA BURASI YENİ: Dükkanın tabelası
          Expanded(
            child: _araclar.isEmpty
                ? const Center(child: Text("Henüz araç eklenmemiş."))
                : ListView.builder(
              itemCount: _araclar.length,
              padding: const EdgeInsets.all(16),
              itemBuilder: (context, i) => _aracKarti(_araclar[i]),
            ),
          ),
        ],
      ),
      floatingActionButton: _aktifMod == "TANIM" ? FloatingActionButton(
        backgroundColor: anaMavi, onPressed: () => _aracEkleDialog(), child: const Icon(Icons.add, color: Colors.white),
      ) : null,
    );
  }

  // --- YENİ: ÜST SKOR TABELASI ---
  Widget _skorTabelasi() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    child: Row(
      children: [
        _skorKarti("STOK", "$_toplamArac", Colors.blue),
        _skorKarti("SATILAN", "$_satilanArac", Colors.green),
        _skorKarti("KALAN", "${_toplamArac - _satilanArac}", Colors.orange),
      ],
    ),
  );

  Widget _skorKarti(String b, String d, Color r) => Expanded(
    child: InkWell(
      onTap: () {
        if (b == "SATILAN") _satilanAraclarListesi(); // Sadece satılana basınca döküm açılır
      },
      child: Card(
        elevation: 2,
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Column(children: [
            Text(b, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: r)),
            Text(d, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ]),
        ),
      ),
    ),
  );

  // GaleriPaneli.dart içindeki _satilanAraclarListesi fonksiyonunu bul ve şununla değiştir:

  void _satilanAraclarListesi() async {
    // Sadece araçları değil, satış detaylarını da içeren listeyi çekmemiz lazım
    // Eğer SQLite kullanıyorsan DatabaseHelper'a yeni bir sorgu yazmalısın.
    // Ama şu anki hızlı çözümün için:

    final satilanlar = _araclar.where((a) => a['durum'] == 'SATILDI').toList();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.7,
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const Text("EVREN, İŞTE SATTIĞIN ARAÇLAR",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.green)),
            const Divider(),
            Expanded(
              child: satilanlar.isEmpty
                  ? const Center(child: Text("Henüz satış kaydı yok."))
                  : ListView.builder(
                itemCount: satilanlar.length,
                itemBuilder: (context, i) {
                  var arac = satilanlar[i];
                  return ListTile(
                    leading: const CircleAvatar(backgroundColor: Colors.green, child: Icon(Icons.attach_money, color: Colors.white)),
                    title: Text("${arac['marka']} ${arac['model']} (${arac['plaka']})"),
                    subtitle: Text("BU ARAÇ SATILDI - DETAY İÇİN TIKLA"), // Detay panelini aşağıda bağlayacağız
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () async {
                      Navigator.pop(context);
                      // Satış detaylarını getiren yeni bir fonksiyon çağıralım:
                      _satisDetayiniGoster(arac['id']);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
  void _satisDetayiniGoster(dynamic aracId) async {
    // Veritabanından veya Firebase'den o aracın SATIŞ KAYDINI bul
    final satisVerisi = await FirebaseFirestore.instance
        .collection('satislar')
        .where('arac_id', isEqualTo: int.tryParse(aracId.toString()))
        .get();

    if (satisVerisi.docs.isNotEmpty) {
      var satis = satisVerisi.docs.first.data();

      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text("SATIŞ DETAYI", style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("👤 MÜŞTERİ: ${satis['musteri_ad']}"),
              Text("💰 FİYAT: ${satis['satis_fiyati']} ₺"),
              Text("📅 TARİH: ${satis['satis_tarihi']}"),
              Text("💳 ÖDEME: ${satis['odeme_tipi']}"),
              Text("📍 KM: ${satis['satis_km']}"),
              const Divider(),
              Text("💵 KAPORA: ${satis['kapora']} ₺"),
              Text("🛑 KALAN: ${satis['kalan_tutar']} ₺", style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
            ],
          ),
          actions: [
            // --- BURASI YENİ: İPTAL BUTONU ---
            TextButton(
              onPressed: () {
                Navigator.pop(context); // Detay penceresini kapat
                _satisIptalEt(aracId, "ARAÇ"); // İptal fonksiyonunu çağır
              },
              child: const Text("SATIŞI İPTAL ET (İADE)", style: TextStyle(color: Colors.red)),
            ),
            // --------------------------------
            TextButton(onPressed: () => Navigator.pop(context), child: const Text("KAPAT")),
          ],
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Bu araca ait satış kaydı bulunamadı!")));
    }
  }

  void _satisIptalEt(dynamic aracId, String plaka) async {
    bool onay = await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("SATIŞI İPTAL ET"),
        content: Text("$plaka plakalı aracın satışı iptal edilip stoğa geri alınacak. Emin misin EVREN?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("VAZGEÇ")),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text("SATIŞI İPTAL ET", style: TextStyle(color: Colors.red))
          ),
        ],
      ),
    ) ?? false;

    if (!onay) return;

    try {
      // 1. Aracı STOKTA durumuna geri çek (Yerel ve Bulut)
      await DatabaseHelper.instance.aracGuncelle(int.parse(aracId.toString()), {'durum': 'STOKTA'});
      await FirebaseFirestore.instance.collection('araclar').doc(aracId.toString()).update({'durum': 'STOKTA'});

      // 2. Satış kaydını Firebase'den bul ve IPTAL olarak işaretle (İz bedeli kalsın diye)
      final satisSorgu = await FirebaseFirestore.instance
          .collection('satislar')
          .where('arac_id', isEqualTo: int.tryParse(aracId.toString()))
          .get();

      for (var doc in satisSorgu.docs) {
        await doc.reference.update({
          'durum': 'IPTAL EDILDI',
          'iptal_tarihi': DateTime.now().toString(),
        });
      }

      // 3. Ekranı tazele
      _araclariGetir();
      if (mounted) Navigator.pop(context); // Detay penceresini kapat

      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Satış iptal edildi, araç dükkana geri döndü!"), backgroundColor: Colors.orange)
      );
    } catch (e) {
      debugPrint("İptal hatası: $e");
    }
  }

  void _satilanAracDetay(Map arac) async {
    // Satış bilgilerini çekiyoruz
    final satislar = await DatabaseHelper.instance.satisGetir(arac['id']);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("${arac['plaka']} - SATIŞ ÖZETİ"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (satislar.isNotEmpty) ...[
              _ozetSatir("Müşteri", satislar[0]['musteri_ad']),
              _ozetSatir("Satış Fiyatı", "${satislar[0]['satis_fiyati']} TL"),
              _ozetSatir("Tarih", satislar[0]['satis_tarihi']),
            ] else const Text("Satış bilgisi bulunamadı."),
          ],
        ),
        actions: [
          // SİLME BUTONU
          TextButton(
            onPressed: () async {
              await DatabaseHelper.instance.aracSil(arac['id']);
              Navigator.pop(context);
              _araclariGetir(); // Ana listeyi tazele
            },
            child: const Text("KAYDI SİL", style: TextStyle(color: Colors.red)),
          ),
          // GÜNCELLEME BUTONU
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _aracEkleDialog(eskiArac: arac); // Senin mevcut güncelleme ekranını açar
            },
            child: const Text("GÜNCELLE"),
          ),
        ],
      ),
    );
  }

  // --- ARAÇ EKLEME DİALOGU (TABLOYA TAM UYUMLU) ---
  void _aracEkleDialog({Map? eskiArac}) {
    final plakaC = TextEditingController(text: eskiArac?['plaka']);
    final markaC = TextEditingController(text: eskiArac?['marka']);
    final modelC = TextEditingController(text: eskiArac?['model']);
    final altModelC = TextEditingController(text: eskiArac?['alt_model']);
    final paketC = TextEditingController(text: eskiArac?['paket']);
    final motorC = TextEditingController(text: eskiArac?['motor_tipi']);
    final kasaC = TextEditingController(text: eskiArac?['kasa_tipi']);
    final kmC = TextEditingController(text: eskiArac?['km']?.toString());
    final alisFiyatC = TextEditingController(text: eskiArac?['alis_fiyati']?.toString());
    final tahminiSatisC = TextEditingController(text: eskiArac?['tahmini_satis']?.toString());
    final alisTarihiC = TextEditingController(text: eskiArac?['alis_tarihi']);
    final kimdenC = TextEditingController(text: eskiArac?['kimden_alindi']);
    final muayeneC = TextEditingController(text: eskiArac?['muayene_tarihi']);
    String? secilenFotoYolu = eskiArac?['renk'];

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(eskiArac == null ? "YENİ ARAÇ KAYDI" : "KAYIT GÜNCELLE"),
          content: SingleChildScrollView(
            child: Column(
              children: [
                GestureDetector(
                  onTap: () => _fotoSec(setDialogState, (yol) => setDialogState(() => secilenFotoYolu = yol)),
                  child: Container(
                    height: 120, width: double.infinity,
                    decoration: BoxDecoration(color: Colors.grey[200], borderRadius: BorderRadius.circular(15), border: Border.all(color: anaMavi)),
                    child: secilenFotoYolu == null
                        ? const Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.add_a_photo, size: 40), Text("FOTO EKLE")])
                        : ClipRRect(borderRadius: BorderRadius.circular(15), child: Image.file(File(secilenFotoYolu!), fit: BoxFit.cover)),
                  ),
                ),
                const SizedBox(height: 15),
                _input(plakaC, "PLAKA", Icons.confirmation_number),
                _input(markaC, "MARKA", Icons.branding_watermark),
                _input(modelC, "MODEL", Icons.directions_car),
                _input(altModelC, "ALT MODEL", Icons.subdirectory_arrow_right),
                _input(paketC, "PAKET", Icons.inventory_2),
                _input(motorC, "MOTOR TİPİ", Icons.settings_input_component),
                _input(kasaC, "KASA TİPİ", Icons.garage),
                _input(kmC, "KM", Icons.speed, tip: TextInputType.number),
                _input(alisFiyatC, "ALIŞ FİYATI", Icons.download, tip: TextInputType.number),
                _input(tahminiSatisC, "TAHMİNİ SATIŞ", Icons.upload, tip: TextInputType.number),
                _input(alisTarihiC, "ALIŞ TARİHİ", Icons.calendar_month),
                _input(kimdenC, "KİMDEN ALINDI", Icons.person),
                _input(muayeneC, "MUAYENE TARİHİ", Icons.event_available),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text("İPTAL")),
            ElevatedButton(
              onPressed: () async {
                final veri = {
                  'plaka': plakaC.text.toUpperCase(),
                  'marka': markaC.text.toUpperCase(),
                  'model': modelC.text.toUpperCase(),
                  'alt_model': altModelC.text.toUpperCase(),
                  'paket': paketC.text.toUpperCase(),
                  'motor_tipi': motorC.text.toUpperCase(),
                  'kasa_tipi': kasaC.text.toUpperCase(),
                  'km': int.tryParse(kmC.text) ?? 0,
                  'alis_fiyati': double.tryParse(alisFiyatC.text) ?? 0.0,
                  'tahmini_satis': double.tryParse(tahminiSatisC.text) ?? 0.0,
                  'alis_tarihi': alisTarihiC.text.toUpperCase(),
                  'kimden_alindi': kimdenC.text.toUpperCase(),
                  'muayene_tarihi': muayeneC.text.toUpperCase(),
                  'renk': secilenFotoYolu,
                  'durum': eskiArac == null ? 'STOKTA' : eskiArac['durum'],
                  'is_synced': 0 // İlk başta 0 olarak işaretle
                };
                int localId;
                if (eskiArac == null) {
                  localId = await DatabaseHelper.instance.aracEkle(veri);
                } else {
                  localId = eskiArac['id'];
                  await DatabaseHelper.instance.aracGuncelle(localId, veri);
                }

                // BU SATIR HATA VERİYORSA FONKSİYON AŞAĞIDA TANIMLI DEĞİLDİR
                _bulutaSenkronizeEt(localId, veri);

                Navigator.pop(context);
                _araclariGetir();
              },
              child: const Text("KAYDET"),
            ),
          ],
        ),
      ),
    );
  }

  // --- DİĞER WIDGET VE YARDIMCILAR ---
  Widget _ustMenu() => Container(
    padding: const EdgeInsets.symmetric(vertical: 20),
    decoration: BoxDecoration(color: anaMavi, borderRadius: const BorderRadius.only(bottomLeft: Radius.circular(30), bottomRight: Radius.circular(30))),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: [
        _islemButonu("TANIM", Icons.directions_car_filled, "TANIM"),
        _islemButonu("EKSPER", Icons.fact_check, "EKSPER"),
        _islemButonu("SATIŞ", Icons.monetization_on, "SATIS"),
        _islemButonu("BAKIM", Icons.build_circle, "BAKIM"),
        _islemButonu("RAPOR", Icons.description, "RAPOR"),
      ],
    ),
  );

  Widget _aracKarti(Map arac) {
    bool isSatildi = arac['durum'] == 'SATILDI';
    return Card(
      color: isSatildi ? Colors.grey[100] : Colors.white,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(15),
        side: isSatildi ? const BorderSide(color: Colors.green, width: 1) : BorderSide.none,
      ),
      child: ListTile(
        leading: (arac['renk'] != null)
            ? ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.file(File(arac['renk']), width: 50, height: 50, fit: BoxFit.cover))
            : Icon(Icons.directions_car, color: isSatildi ? Colors.grey : anaMavi),
        title: Text("${arac['marka']} ${arac['model']}".toUpperCase(),
            style: TextStyle(fontWeight: FontWeight.bold, decoration: isSatildi ? TextDecoration.lineThrough : null, color: isSatildi ? Colors.grey : Colors.black)),
        subtitle: Text(isSatildi ? "PASA BU ARAC SATILDI!" : "PLAKA: ${arac['plaka']} | KM: ${arac['km']}"),
        trailing: isSatildi ? const Icon(Icons.check_circle, color: Colors.green) : const Icon(Icons.arrow_forward_ios, size: 16),
        onTap: () => _detayAc(arac),
      ),
    );
  }

  void _detayAc(Map arac) {
    if (_aktifMod == "EKSPER") {
      Navigator.push(context, MaterialPageRoute(builder: (context) => EksperDetay(arac: arac)));
    }
    else if (_aktifMod == "BAKIM") {
      Navigator.push(context, MaterialPageRoute(builder: (context) => BakimPaneli(arac: arac))).then((_) => _araclariGetir());
    }
    else if (_aktifMod == "SATIS") {
      Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => SatisPaneli(arac: arac))
      ).then((_) {
        // BURASI DÜKKANA DÖNÜNCE LİSTEYİ TEKRAR SAYDIRIR
        _araclariGetir();
      });
    }
    else {
      _aracOzetGoster(arac);
    }
  }


  // --- GÜNCELLENMİŞ PATRON RAPORU EKRANI (KESİN ÇÖZÜM) ---
  void _aracOzetGoster(Map arac) async {
    // 1. HATA KAYNAĞI ÇÖZÜMÜ: ID'yi her zaman güvenli bir int'e çeviriyoruz
    final dynamic hamId = arac['id'];
    final int guvenliId = int.tryParse(hamId.toString()) ?? 0;

    if (guvenliId == 0) {
      print("HATA: Geçersiz Araç ID'si!");
      return;
    }

    // Veritabanından masrafları ve satış bilgilerini çek (Güvenli ID ile)
    final masraflar = await DatabaseHelper.instance.bakimlariGetir(guvenliId);
    final satis = await DatabaseHelper.instance.satisGetir(guvenliId);

    double toplamMasraf = 0;
    for (var m in masraflar) {
      // 2. HATA KAYNAĞI ÇÖZÜMÜ: Tutar ne gelirse gelsin double'a zorla
      toplamMasraf += double.tryParse(m['tutar'].toString()) ?? 0.0;
    }

    if (!mounted) return;

    // ... masraf döngüsünden sonra gelen butonlar ...
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // RAPOR BUTONU (En Üstte ve Tek Başına)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.picture_as_pdf, color: Colors.white),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red[900]),
                onPressed: () => _tekAracKurumsalRapor(arac),
                label: const Text("KURUMSAL PDF RAPOR AL", style: TextStyle(color: Colors.white)),
              ),
            ),
            const SizedBox(height: 10),
            // GÜNCELLE VE SİL YAN YANA
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: () { Navigator.pop(context); _aracEkleDialog(eskiArac: arac); },
                    child: const Text("GÜNCELLE"),
                  ),
                ),
                const SizedBox(width: 10),
                // ... GÜNCELLE VE SİL YAN YANA olan kısımdaki SİL butonu:
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                    onPressed: () async {
                      // 1. Emniyet kilidini soruyoruz
                      bool? onay = await _silmeOnayiAl();
                      if (onay == true) {
                        // 2. Önce veritabanından sil
                        await DatabaseHelper.instance.aracSil(guvenliId);
                        // 3. Varsa Firebase'den de sil (Opsiyonel)
                        await FirebaseFirestore.instance.collection('araclar').doc(guvenliId.toString()).delete();

                        if (context.mounted) Navigator.pop(context); // BottomSheet'i kapat
                        _araclariGetir(); // Ana listeyi tazele

                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text("Araç kaydı silindi."), backgroundColor: Colors.red),
                        );
                      }
                    },
                    child: const Text("SİL", style: TextStyle(color: Colors.white)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

// Silme işlemi için küçük bir emniyet kilidi
  Future<bool?> _silmeOnayiAl() {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("DİKKAT!"),
        content: const Text("Bu araç kaydını tamamen silmek istediğine emin misin EVREN?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("VAZGEÇ")),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text("SİL", style: TextStyle(color: Colors.red))),
        ],
      ),
    );
  }

  Widget _ozetSatir(String b, String? d) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(b, style: const TextStyle(fontWeight: FontWeight.w500)),
        Text(d ?? "-", style: const TextStyle(fontWeight: FontWeight.bold))
      ])
  );

  Widget _islemButonu(String metin, IconData ikon, String modKod) {
    bool secili = _aktifMod == modKod;

    // Modlara göre ikon renklerini belirliyoruz
    Color butonRengi;
    switch (modKod) {
      case "TANIM": butonRengi = Colors.amber; break;    // Sarı/Turuncu (Kayıt)
      case "EKSPER": butonRengi = Colors.purple; break;  // Mor (Kontrol)
      case "SATIS": butonRengi = Colors.green; break;    // Yeşil (Para)
      case "BAKIM": butonRengi = Colors.orange; break;   // Turuncu (Tamir)
      case "RAPOR": butonRengi = Colors.red; break;      // Kırmızı (Döküm)
      default: butonRengi = Colors.white;
    }

    return InkWell(
      onTap: () {
        if (modKod == "RAPOR") {
          _galeriPdfRaporu();
        } else {
          setState(() => _aktifMod = modKod);
        }
      },
      child: Column(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              // Seçiliyse kendi rengini alıyor, değilse sönük beyaz kalıyor
              color: secili ? butonRengi : Colors.white24,
              shape: BoxShape.circle,
              boxShadow: secili ? [BoxShadow(color: butonRengi.withOpacity(0.5), blurRadius: 10, spreadRadius: 2)] : [],
            ),
            child: Icon(ikon, color: secili ? Colors.white : Colors.white70, size: 28),
          ),
          const SizedBox(height: 6),
          Text(
            metin,
            style: TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: secili ? FontWeight.bold : FontWeight.normal,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _input(TextEditingController c, String h, IconData i, {TextInputType tip = TextInputType.text}) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: TextField(
      controller: c, keyboardType: tip,
      onChanged: (v) => c.value = c.value.copyWith(text: v.toUpperCase(), selection: TextSelection.collapsed(offset: v.length)),
      decoration: InputDecoration(labelText: h, prefixIcon: Icon(i, color: anaMavi), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
    ),
  );
}