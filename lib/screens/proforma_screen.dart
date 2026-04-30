
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart' as syncPdf;
import '../db/database_helper.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:io' as io;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'dart:io' show File;



// --- 1. PROFORMA ANA MERKEZ (LİSTELEME EKRANI) ---
class ProformaSayfasi extends StatefulWidget {
  final Map<String, dynamic>? secilenMusteri;
  final List<Map<String, dynamic>> musteriler; // <-- Bunu ekledik

  const ProformaSayfasi({
    super.key,
    this.secilenMusteri,
    required this.musteriler
  });

  @override
  State<ProformaSayfasi> createState() => _ProformaSayfasiState();
}

class _ProformaSayfasiState extends State<ProformaSayfasi> {
  List<Map<String, dynamic>> _kayitliProformalar = [];
  List<File> yuklenenBelgeler = [];
  final formatAraci = NumberFormat.currency(locale: 'tr_TR', symbol: '₺', decimalDigits: 2);

  // Müşteri Listesi (VT Simülasyonu)
  final List<Map<String, dynamic>> _musteriListesi = [
    {"ad": "Ahmet Yılmaz", "tc": "12345678901", "adres": "Tefenni / Burdur"},
    {"ad": "Mehmet Demir", "tc": "98765432109", "adres": "Merkez / Isparta"},
  ];




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
    _verileriGetir();
  }

  Future<void> _verileriGetir() async {
    try {
      var snapshot = await FirebaseFirestore.instance
          .collection('proformalar') // Aynı klasöre bakıyoruz
          .orderBy('kayit_tarihi', descending: true) // Kayıt tarihlerine göre sırala
          .get();

      // _verileriGetir içindeki map kısmı böyle olmalı:
      setState(() {
        _kayitliProformalar = snapshot.docs.map((doc) {
          final d = doc.data() as Map<String, dynamic>;
          d['id'] = doc.id;

          // 🔥 İŞTE ÇÖZÜM BURASI:
          // Sırasıyla ad_norm'a bak, yoksa musteri_adi'na bak, o da yoksa reklam'a bak...
          d['musteri'] = d['ad_norm'] ?? d['musteri_adi'] ?? d['ad'] ?? d['reklam'] ?? 'İsimsiz Kayıt';

          return d;
        }).toList();
      });
      print("✅ ${_kayitliProformalar.length} tane veri çekildi.");
    } catch (e) {
      print("❌ Veri çekme hatası: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    double toplamTutar = _kayitliProformalar.fold(0.0, (sum, item) => sum + (double.tryParse(item['toplam'].toString()) ?? 0.0));

    return Scaffold(
      backgroundColor: Colors.grey[200],
      appBar: AppBar(
        title: const Text("PROFORMA MERKEZİ"),
        backgroundColor: Colors.blueGrey[900],
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.person_search),
            onPressed: _musteriSecmeEkrani,
            tooltip: "Müşteri Seç",
          ),
        ],
      ),
      body: Column(
        children: [
          _ustPano(toplamTutar),
          _yeniButon(),
          Expanded(child: _liste()),
        ],
      ),
    );
  }
  Future<void> belgeEkle() async {
    final picker = ImagePicker();

    final XFile? image = await picker.pickImage(
      source: ImageSource.gallery, // istersek camera da yaparız
      imageQuality: 80,
    );

    if (image != null) {
      setState(() {
        yuklenenBelgeler.add(File(image.path));
      });
    }
  }
  // --- PAYLAŞIM VE İŞLEM MENÜSÜ ---
  void _paylasimMenusu(Map<String, dynamic> proforma) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text("${proforma['musteri'].toString().toUpperCase()} - İŞLEMLER",
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.message, color: Colors.green),
                title: const Text("WhatsApp ile Özet Gönder"),
                onTap: () {
                  Navigator.pop(context);
                  _whatsappGonder(proforma);
                },
              ),
              ListTile(
                leading: const Icon(Icons.picture_as_pdf, color: Colors.red),
                title: const Text("PDF / TSE / Yerli Malı İşlemleri"),
                onTap: () {
                  Navigator.pop(context);
                  _ekEvrakSecimi(proforma);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  // --- WHATSAPP METİN OLUŞTURUCU ---
  void _whatsappGonder(Map<String, dynamic> p) {
    String mesaj = """
*PROFORMA TEKLİF ÖZETİ*
----------------------------
👤 *Müşteri:* ${p['musteri']}
🗓 *Tarih:* ${p['tarih']}
💰 *Toplam:* ${p['toplam']} TL
----------------------------
Detaylı PDF ve ek belgeler (TSE, Yerli Malı) ekte sunulacaktır.
Hayırlı işler dileriz.
""";
    // url_launcher paketi yüklüyse buraya launchUrl eklenecek
    print("WhatsApp'a giden mesaj:\n$mesaj");
  }

  void _ekEvrakSecimi(Map<String, dynamic> p) async {
    List<String> secilenler = [];

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text("Belge ve Ekleri Seçin"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CheckboxListTile(
                title: const Text("TSE Belgesi Ekle"),
                value: secilenler.contains("TSE"),
                onChanged: (v) => setDialogState(() => v! ? secilenler.add("TSE") : secilenler.remove("TSE")),
              ),
              CheckboxListTile(
                title: const Text("Yerli Malı Belgesi Ekle"),
                value: secilenler.contains("YERLI"),
                onChanged: (v) => setDialogState(() => v! ? secilenler.add("YERLI") : secilenler.remove("YERLI")),
              ),
              const Divider(), // Araya bir çizgi çekelim düzgün dursun
              ElevatedButton.icon(
                onPressed: () async {
                  try {
                    // NE 'platform' NE 'instance'... Doğrudan sınıf üzerinden çağırıyoruz:
                    FilePickerResult? result = await FilePicker.pickFiles(
                      type: FileType.custom,
                      allowedExtensions: ['pdf'],
                    );

                    if (result != null && result.files.single.path != null) {
                      String dosyaYolu = result.files.single.path!;
                      setDialogState(() {
                        secilenler.add(dosyaYolu);
                      });
                      debugPrint("Dosya seçildi: $dosyaYolu");
                    }
                  } catch (e) {
                    debugPrint("Dosya seçme hatası: $e");
                    // Hata olursa kullanıcıya göster
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text("Dosya seçilemedi: $e")),
                    );
                  }
                },
                icon: const Icon(Icons.attach_file),
                label: const Text("PDF Dosyası Seç"),
              ),
              const SizedBox(height: 10),
              // Seçilenleri daha derli toplu gösterelim
              Text(
                  "Seçilen Belge Sayısı: ${secilenler.length}",
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text("İptal")),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
              onPressed: () async {
                var urunlerListesi = p['urunler'] ?? [];

                if (urunlerListesi.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("Hata: Ürün listesi boş!")),
                  );
                  return;
                }

                final messenger = ScaffoldMessenger.of(context);

                // PDF Üretimini başlat
                _pdfUretVeOnizle(p, urunlerListesi, secilenler);

                if (mounted) Navigator.pop(context);

                messenger.showSnackBar(
                  const SnackBar(
                    content: Text("PDF hazırlanıyor..."),
                    backgroundColor: Colors.green,
                  ),
                );
              },
              child: const Text("PDF ÜRET VE KAYDET"),
            )
          ],
        ),
      ),
    );
  }

  void _satisiFirebaseKaydet(Map<String, dynamic> p, List<dynamic> urunler) async {
    print("🚀 [SATIS DEBUG 1] Kayıt başladı...");
    try {
      List<Map<String, dynamic>> temizUrunler = urunler.map((u) {
        return {
          'marka': u['marka'] ?? '',
          'model': u['model'] ?? '',
          'alt_model': u['alt_model'] ?? '',
          'ad': u['ad'] ?? '',
          'adet': u['adet'] ?? 1,
          'fiyat': u['fiyat'] ?? 0,
        };
      }).toList();

      // Müşteri ismini sağlama alalım
      String mAdi = p['musteri_adi'] ?? p['ad'] ?? p['musteri'] ?? 'İsimsiz Müşteri';
      print("📦 [SATIS DEBUG 2] Müşteri: $mAdi, Ürün Sayısı: ${temizUrunler.length}");

      await FirebaseFirestore.instance.collection('formal').add({
        'musteri_adi': mAdi,
        'tc_no': p['tc'] ?? '',
        'toplam_tutar': p['toplam'] ?? 0,
        'urunler': temizUrunler,
        'tarih': FieldValue.serverTimestamp(),
        'islem_tipi': 'PROFORMA_SATIS',
        'sube': p['sube'] ?? 'Merkez',
      });

      print("✅ [SATIS DEBUG 3] 'formal' koleksiyonuna başarıyla yazıldı!");
    } catch (e) {
      print("❌ [SATIS HATA]: $e");
    }
  }

  Future<void> _pdfUretVeOnizle(
      Map<String, dynamic> p,
      List<dynamic> urunler,
      List<String> secilenler,
      ) async {
    final pdf = pw.Document();
    final font = await PdfGoogleFonts.robotoRegular();
    final boldFont = await PdfGoogleFonts.robotoBold();

    String f(dynamic d) => NumberFormat.currency(
        locale: 'tr_TR', symbol: '', decimalDigits: 2)
        .format(double.tryParse(d.toString()) ?? 0)
        .trim();

    // --- 1. VERİ HESAPLAMA (DÖNGÜYÜ SAĞLAMA ALDIK) ---
    // --- 1. VERİ HESAPLAMA ---
    double araToplam = 0;
    final List<List<String>> tabloSatirlari = [];

    for (var urun in urunler) {
      // 1. Verileri çekiyoruz
      String anaAd = (urun['ad'] ?? "").toString().trim();
      String marka = (urun['marka'] ?? "").toString().trim();
      String model = (urun['model'] ?? "").toString().trim();
      String altModel = (urun['alt_model'] ?? "").toString().trim();
      String tamIsim = anaAd.toUpperCase();
      if (altModel.isNotEmpty && !tamIsim.contains(altModel.toUpperCase())) {
        tamIsim = "$tamIsim $altModel".trim().toUpperCase();
      }
      if (tamIsim.isEmpty) {
        tamIsim = "$marka $model $altModel".trim().toUpperCase();
      }

      if (tamIsim.isEmpty) tamIsim = "BİLİNMEYEN ÜRÜN";

      // 3. Hesaplamalar (Buralar aynı kalıyor)
      double adet = double.tryParse(urun['adet']?.toString() ?? '1') ?? 1;
      double fiyat = double.tryParse(urun['fiyat']?.toString() ?? '0') ?? 0;
      double toplam = adet * fiyat;
      araToplam += toplam;

      tabloSatirlari.add([
        tamIsim,
        adet.toStringAsFixed(0),
        f(fiyat),
        f(toplam),
      ]);
    }

    // 1. İskonto hesaplama zaten doğru
    double iskontoOran = double.tryParse(p['iskontoOran']?.toString() ?? '0') ?? 0;
    double iskontoTutar = araToplam * (iskontoOran / 100);
    double kdvOncesi = araToplam - iskontoTutar;

// 2. KDV oranını formdan çekiyoruz (Eğer boşsa 20 varsayıyoruz)
// BURAYI DEĞİŞTİR:
    double kdvOran = double.tryParse(p['kdvOran']?.toString() ?? '10') ?? 10;
    double kdvTutar = kdvOncesi * (kdvOran / 100); // Artık 0.20 değil, kdvOran kullanılıyor

// 3. Genel toplam
    double genelToplam = kdvOncesi + kdvTutar;
    final ByteData bytes = await rootBundle.load('assets/images/logo.png');
    final Uint8List byteList = bytes.buffer.asUint8List();
    final logoResmi = pw.MemoryImage(byteList);
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.symmetric(horizontal: 25, vertical: 30),
        // Header her sayfada başlığı tekrar eder (İstemiyorsanız build içine alabilirsiniz)
        header: (context) => pw.Align(
          alignment: pw.Alignment.centerLeft,
          child: pw.SizedBox(
            width: 480, // Tabloyla tam hizada durması için
            child: pw.Column(
              children: [
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    // SOL TARAF: Logo ve Firma Bilgileri
                    pw.Row(
                      children: [
                        // LOGO (Burada logoResmi değişkenini image: MemoryImage ile tanımlamış olmalısın)
                        pw.Container(
                          width: 50,
                          height: 50,
                          child: pw.Image(logoResmi),
                        ),
                        pw.SizedBox(width: 10),
                        pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Text("EVREN TARIM",
                                style: pw.TextStyle(font: boldFont, fontSize: 18, color: PdfColors.blue900)),
                            pw.Text("Evren Özçoban | 0545 521 75 65",
                                style: pw.TextStyle(font: font, fontSize: 9)),
                            pw.Text("Pazar Mh. Tarım Kredi Koop. Yanı Tefenni / BURDUR",
                                style: pw.TextStyle(font: font, fontSize: 8)), // Takvimdeki adres
                          ],
                        ),
                      ],
                    ),

                    // SAĞ TARAF: Başlık ve Tarih
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.end,
                      children: [
                        pw.Text("PROFORMA FATURA",
                            style: pw.TextStyle(font: boldFont, fontSize: 12)),
                        pw.SizedBox(height: 5),
                        pw.Text("TARİH: ${DateTime.now().day}.${DateTime.now().month}.${DateTime.now().year}",
                            style: pw.TextStyle(font: font, fontSize: 9)),
                      ],
                    ),
                  ],
                ),
                pw.Divider(thickness: 1, height: 15),
              ],
            ),
          ),
        ),
        build: (pdfContext) => [
          // 1. MÜŞTERİ BİLGİLERİ (Genişliği Tabloyla Eşitledik)
          pw.Align(
            alignment: pw.Alignment.centerLeft,
            child: pw.SizedBox(
              width: 480, // Tablo genişliğiyle aynı yaptık
              child: pw.Container(
                padding: const pw.EdgeInsets.all(8),
                decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey400)),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text("SAYIN (ALICI):", style: pw.TextStyle(font: boldFont, fontSize: 8)),
                    pw.Text("${p['musteri'] ?? ''}".toUpperCase(), style: pw.TextStyle(font: boldFont, fontSize: 12)),
                    pw.Text("TC / VKN: ${p['tc'] ?? '-'}", style: pw.TextStyle(font: font, fontSize: 9)),
                    pw.Text("ADRES: ${p['adres'] ?? '-'}", style: pw.TextStyle(font: font, fontSize: 8)),
                  ],
                ),
              ),
            ),
          ),
          pw.SizedBox(height: 15),

          // 2. ÜRÜN TABLOSU (Hizalı ve Sabit)
          pw.Align(
            alignment: pw.Alignment.centerLeft,
            child: pw.SizedBox(
              width: 480,
              child: pw.TableHelper.fromTextArray(
                headers: ['ÜRÜN AÇIKLAMASI', 'ADET', 'BİRİM FİYAT', 'TOPLAM'],
                data: tabloSatirlari,
                headerStyle: pw.TextStyle(font: boldFont, color: PdfColors.white, fontSize: 9),
                headerDecoration: const pw.BoxDecoration(color: PdfColors.blue900),
                cellStyle: pw.TextStyle(font: font, fontSize: 8),
                columnWidths: {
                  0: const pw.FlexColumnWidth(3),
                  1: const pw.FixedColumnWidth(40),
                  2: const pw.FixedColumnWidth(70),
                  3: const pw.FixedColumnWidth(80),
                },
                cellAlignments: {
                  0: pw.Alignment.centerLeft,
                  1: pw.Alignment.centerRight,
                  2: pw.Alignment.centerRight,
                  3: pw.Alignment.centerRight,
                },
                headerHeight: 25,
                cellPadding: const pw.EdgeInsets.all(5),
              ),
            ),
          ),

          pw.SizedBox(height: 10),

          // 3. ALT TOPLAMLAR VE IBAN (Sağdan Taşma Engellendi)
          pw.Align(
            alignment: pw.Alignment.centerLeft,
            child: pw.SizedBox(
              width: 480, // Burayı da kısıtladık ki toplam rakamı sayfadan fırlamasın
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  // Sol: IBAN ve Banka
                  pw.Expanded(
                    flex: 2,
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text("IBAN:", style: pw.TextStyle(font: boldFont, fontSize: 9)),
                        pw.Text("TR60 0001 0000 5958 7838 9350 07", style: pw.TextStyle(font: font, fontSize: 8)),
                        pw.SizedBox(height: 20), // Tablo ile metin arasında boşluk

                        // --- TEKLİF SÜRESİ VE NOT ---
                        pw.Align(
                          alignment: pw.Alignment.centerLeft,
                          child: pw.Column(
                            crossAxisAlignment: pw.CrossAxisAlignment.start,
                            children: [
                              pw.Text(
                                "NOT: Teklif geçerlilik süresi, teklif tarihinden itibaren 7 (yedi) gündür.",
                                style: pw.TextStyle(
                                  font: font,
                                  fontSize: 9,
                                  fontStyle: pw.FontStyle.italic,
                                  color: PdfColors.grey700,
                                ),
                              ),
                              pw.SizedBox(height: 5),
                              pw.Text(
                                "Ödeme yapılmadan sipariş kesinleşmiş sayılmaz.",
                                style: pw.TextStyle(
                                  font: font,
                                  fontSize: 8,
                                  color: PdfColors.grey600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Sağ: Hesaplamalar
                  pw.Expanded(
                    flex: 2,
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.end,
                      children: [
                        _pdfAltSatir("Ara Toplam", f(araToplam), font),
                        if (iskontoTutar > 0) _pdfAltSatir("İskonto", "-${f(iskontoTutar)}", font),
                        _pdfAltSatir("KDV (%${kdvOran.toStringAsFixed(0)})", f(kdvTutar), font),
                        pw.Divider(thickness: 1, color: PdfColors.black),
                        pw.Row(
                          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                          children: [
                            pw.Text("GENEL TOPLAM", style: pw.TextStyle(font: boldFont, fontSize: 10)),
                            pw.Text("${f(genelToplam)} TL", style: pw.TextStyle(font: boldFont, fontSize: 10)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );

    // --- PDF BİRLEŞTİRME KODUN (Aynen Devam) ---
    final Uint8List anaPdfBytes = await pdf.save();
    final syncPdf.PdfDocument finalDoc = syncPdf.PdfDocument();
    final syncPdf.PdfDocument tempAna = syncPdf.PdfDocument(inputBytes: anaPdfBytes);
    for (int i = 0; i < tempAna.pages.count; i++) {
      finalDoc.pages.add().graphics.drawPdfTemplate(tempAna.pages[i].createTemplate(), Offset.zero);
    }
    tempAna.dispose();

    for (var yol in secilenler) {
      final File fl = File(yol);
      if (await fl.exists()) {
        final syncPdf.PdfDocument ekDoc = syncPdf.PdfDocument(inputBytes: await fl.readAsBytes());
        for (int i = 0; i < ekDoc.pages.count; i++) {
          finalDoc.pages.add().graphics.drawPdfTemplate(ekDoc.pages[i].createTemplate(), Offset.zero);
        }
        ekDoc.dispose();
      }
    }

    final List<int> birlesmisBytes = await finalDoc.save();
    finalDoc.dispose();

    if (context.mounted) {
      await Navigator.push(context, MaterialPageRoute(
        builder: (context) => Scaffold(
          appBar: AppBar(title: const Text("PROFORMA ÖNİZLEME"), backgroundColor: Colors.blueGrey[900]),
          body: PdfPreview(build: (format) => Uint8List.fromList(birlesmisBytes)),
        ),
      ));
    }
  }

  pw.Widget _pdfAltSatir(String label, String value, pw.Font font) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(label, style: pw.TextStyle(font: font, fontSize: 9)),
          pw.Text(value, style: pw.TextStyle(font: font, fontSize: 9)),
        ],
      ),
    );
  }

  // 2. ADIM: Müşteri Seçme Ekranını Gerçek Veriye Bağla
  void _musteriSecmeEkrani() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => ListView.builder(
        // widget.musteriler: Ana sayfadan gönderdiğin gerçek liste
        itemCount: widget.musteriler.length,
        itemBuilder: (context, i) {
          final m = widget.musteriler[i];
          return ListTile(
            leading: const Icon(Icons.person, color: Colors.blue),
            title: Text(m['ad'] ?? "İsimsiz"),
            subtitle: Text("Şube: ${m['sube'] ?? '-'}"),
            onTap: () {
              Navigator.pop(context);
              // Seçilen gerçek müşteriyi (ID'si dahil) forma gönderiyoruz
              _formaGit(secilen: m);
            },
          );
        },
      ),
    );
  }

  void _formaGit({Map<String, dynamic>? secilen}) async {
    final yeni = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => ProformaHazirlamaFormu(gelenMusteri: secilen)),
    );

    if (yeni != null) {
      try {
        // 1. Firebase'e tek seferde kayıt ve ID'yi al
        var docRef = await FirebaseFirestore.instance.collection('proformalar').add({
          ...yeni,
          'kayit_tarihi': FieldValue.serverTimestamp(), // Sıralama için şart
        });

        // 2. SQLite'a Firebase ID'siyle beraber yaz
        await DatabaseHelper.instance.insert('proformalar', {
          'firebase_id': docRef.id, // İşte o köprü bu ID!
          'musteri_adi': yeni['ad_norm'],
          'toplam': yeni['toplam'],
          'tarih': yeni['tarih'],
          'sube': 'AKSU',
          'is_synced': 1
        });

        _verileriGetir(); // Listeyi tazele
        print("✅ Kayıt Tek Seferde Tamamlandı ID: ${docRef.id}");
      } catch (e) {
        print("❌ Kayıt hatası: $e");
      }
    }
  }

  Widget _ustPano(double t) {
    // Binlik noktası ve kuruş virgülü ayarı (Örn: 1.250.000,00)
    RegExp reg = RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))');
    String mathFunc(Match match) => '${match[1]}.';
    String sabit = t.toStringAsFixed(2);
    List<String> parcalar = sabit.split('.');
    parcalar[0] = parcalar[0].replaceAllMapped(reg, mathFunc);
    String formatli = parcalar.join(',');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      margin: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.blueGrey[900],
        borderRadius: BorderRadius.circular(15),
      ),
      child: Column(
        children: [
          const Text("TOPLAM PROFORMA TUTARI", style: TextStyle(color: Colors.white70, fontSize: 12)),
          const SizedBox(height: 5),
          Text("$formatli TL", style: const TextStyle(color: Colors.greenAccent, fontSize: 28, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }


  Widget _label(String b, String d, Color r) => Column(children: [Text(b), Text(d, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: r))]);

  Widget _yeniButon() => Padding(
    padding: const EdgeInsets.all(15),
    child: ElevatedButton.icon(
      style: ElevatedButton.styleFrom(
          backgroundColor: Colors.orange[900],
          foregroundColor: Colors.white,
          minimumSize: const Size(double.infinity, 55)
      ),
      onPressed: () {
        print("🚀 DEBUG: Yeni Proforma butonuna basıldı, forma gidiliyor...");
        _formaGit();
      },
      icon: const Icon(Icons.add),
      label: const Text("YENİ PROFORMA OLUŞTUR"),
    ),
  );

  Widget _liste() => ListView.builder(
    itemCount: _kayitliProformalar.length,
    itemBuilder: (context, i) {
      final p = _kayitliProformalar[i];
      final String docId = p['id'] ?? "";

      // 🔥 TL FORMATI İÇİN HESAPLAMA:
      double tutar = double.tryParse(p['toplam']?.toString() ?? '0') ?? 0.0;

      // Binlik ayıracı (nokta) ve kuruş ayıracı (virgül) ayarı
      // Örn: 425000 -> 425.000,00 TL
      String formatliTutar = tutar.toStringAsFixed(2)
          .replaceAll('.', '|')   // Geçici işaret
          .replaceAll(',', '.')   // Noktaları virgül yap
          .replaceAll('|', ',');  // Virgülleri nokta yap

      return Dismissible(
        key: Key(docId),
        direction: DismissDirection.endToStart,
        background: Container(
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 20),
          color: Colors.red,
          child: const Icon(Icons.delete, color: Colors.white),
        ),
        onDismissed: (direction) async {
          setState(() => _kayitliProformalar.removeAt(i));
          if (docId.isNotEmpty) {
            try {
              // Firebase'den de kazıyoruz
              await FirebaseFirestore.instance.collection('proformalar').doc(docId).delete();
              print("✅ Buluttan silindi: $docId");
            } catch (e) {
              print("❌ Silme hatası: $e");
            }
          }
        },
        child: Card(
          margin: const EdgeInsets.symmetric(horizontal: 15, vertical: 5),
          elevation: 2,
          child: ListTile(
            leading: const CircleAvatar(
              backgroundColor: Colors.teal,
              child: Icon(Icons.person, color: Colors.white),
            ),
            // MÜŞTERİ ADI
            title: Text(
                p['musteri'] ?? p['ad_norm'] ?? "İsimsiz",
                style: const TextStyle(fontWeight: FontWeight.bold)
            ),
            // TARİH
            subtitle: Text(p['tarih'] ?? ""),
            // 🔥 TUTAR (ARADIĞIN TL BURASI!)
            trailing: Text(
              "$formatliTutar TL",
              style: const TextStyle(
                  color: Colors.greenAccent,
                  fontWeight: FontWeight.bold,
                  fontSize: 18
              ),
            ),
            onTap: () => _paylasimMenusu(p),
          ),
        ),
      );
    },
  );
}

// --- PROFORMA HAZIRLAMA (STOK SEÇİMİ DAHİL) ---
class ProformaHazirlamaFormu extends StatefulWidget {
  final Map<String, dynamic>? gelenMusteri;
  const ProformaHazirlamaFormu({super.key, this.gelenMusteri});


  @override
  State<ProformaHazirlamaFormu> createState() => _ProformaHazirlamaFormuState();
}

class _ProformaHazirlamaFormuState extends State<ProformaHazirlamaFormu> {
  final TextEditingController _adC = TextEditingController();
  final TextEditingController _tcC = TextEditingController();
  final TextEditingController _adresC = TextEditingController();

  double _iskontoOrani = 0.0;
  double _kdvOrani = 20.0;

  // --- GERÇEK VERİLER İÇİN DEĞİŞKENLER ---
  List<Map<String, dynamic>> _stoklar = [];
  bool _yukleniyor = true;
  late TextEditingController _telC; // Değişkeni tanımla
  // Kalemler listesi (Fiyat controller'ı ile birlikte)
  List<Map<String, dynamic>> _kalemler = [
    {"ad": "", "adet": 1, "fiyat": 0.0, "controller": TextEditingController()}
  ];

  Widget buildImage(String path) {
    if (path.isEmpty) {
      return Image.asset("assets/images/logo.png");
    }
    return Image.file(File(path));
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
    _stoklariGetir(); // Sayfa açılırken veritabanından malları çekiyoruz

    if (widget.gelenMusteri != null) {
      _adC.text = widget.gelenMusteri!['ad'] ?? "";
      _tcC.text = widget.gelenMusteri!['tc'] ?? "";
      _adresC.text = widget.gelenMusteri!['adres'] ?? "";
    }
  }

  Future<void> _stoklariGetir() async {
    setState(() => _yukleniyor = true);
    try {
      final yerelStoklar = await DatabaseHelper.instance.stokListesiGetir();

      setState(() {
        _stoklar = yerelStoklar.map((s) {
          String marka = s['marka'] ?? "";
          String model = s['model'] ?? "";
          String altModel = s['alt_model'] ?? s['altmodel'] ?? "";

          // 🔥 ÜRÜN ADI BURADA OLUŞUYOR
          String tamAd = "$marka $model $altModel".trim();

          return {
            'id': s['id'],
            'ad': tamAd.isEmpty ? "İSİMSİZ ÜRÜN" : tamAd,
            'fiyat': double.tryParse(s['fiyat']?.toString() ?? '0') ?? 0.0,
            'marka': marka,
            'model': model,
            'alt_model': altModel,
            'miktar': double.tryParse(s['adet']?.toString() ?? '0') ?? 0.0, // 🔥 BURASI KRİTİK
          };
        }).toList();

        _yukleniyor = false;
      });

      print("✅ Stoklar yüklendi: ${_stoklar.length}");
    } catch (e) {
      print("❌ HATA: $e");
      setState(() => _yukleniyor = false);
    }
  }

  void _stoktanSec(int index) {
    if (_stoklar.isEmpty) {
      _stoklariGetir();
      return;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.7,
        padding: const EdgeInsets.all(15),
        child: Column(
          children: [
            const Text("DÜKKAN STOĞUNDAN ÜRÜN SEÇ",
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            const Divider(),
            Expanded(
              child: ListView.builder(
                itemCount: _stoklar.length,
                itemBuilder: (context, i) {
                  final urun = _stoklar[i];

                  String marka = urun['marka'] ?? "";
                  String model = urun['model'] ?? "";
                  String urunAdi = urun['ad'] ?? "İsimsiz Ürün";

                  String tamIsim = urun['ad'];

                  double gelenFiyat = urun['fiyat'] ?? 0.0;

                  return ListTile(
                    leading: const Icon(Icons.inventory_2, color: Colors.orange),
                    title: Text(tamIsim),
                    subtitle: Text(
                      "Fiyat: $gelenFiyat TL | Stok: ${urun['miktar']}",
                    ),
                    onTap: () {
                      setState(() {
                        _kalemler[index]['ad'] = tamIsim;
                        _kalemler[index]['fiyat'] = gelenFiyat;
                        _kalemler[index]['adet'] = 1;
                        _kalemler[index]['controller'].text =
                            gelenFiyat.toStringAsFixed(2);
                      });
                      Navigator.pop(context);
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

  Map<String, double> _hesapla() {
    double ara = _kalemler.fold(0.0, (sum, k) {
      double adet = double.tryParse(k['adet'].toString()) ?? 1.0;
      double fiyat = double.tryParse(k['fiyat'].toString()) ?? 0.0;
      return sum + (adet * fiyat);
    });
    double isk = ara * (_iskontoOrani / 100);
    double mat = ara - isk;
    double kdv = mat * (_kdvOrani / 100);
    return {"ara": ara, "isk": isk, "mat": mat, "kdv": kdv, "toplam": mat + kdv};
  }

  @override
  Widget build(BuildContext context) {
    var h = _hesapla();
    return Scaffold(
      appBar: AppBar(title: const Text("PROFORMA / STOKLU GİRİŞ"), backgroundColor: Colors.blueGrey[900], foregroundColor: Colors.white),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(15),
              children: [
                _input(_adC, "Müşteri Adı"),
                _input(_tcC, "TC / Vergi No"),
                _input(_adresC, "Adres", maxLines: 2),
                const Divider(height: 30),
                ..._kalemler.asMap().entries.map((e) => _urunSatiri(e.key)),
                const SizedBox(height: 10),
                ElevatedButton.icon(
                  onPressed: () => setState(() => _kalemler.add({"ad": "", "adet": 1, "fiyat": 0.0, "controller": TextEditingController()})),
                  icon: const Icon(Icons.add), label: const Text("Yeni Kalem Ekle"),
                ),
              ],
            ),
          ),
          _hesapPano(h),
        ],
      ),
    );
  }

  Widget _urunSatiri(int i) {
    return Card(
      elevation: 3,
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          children: [
            TextField(
              controller: TextEditingController(
                text: _kalemler[i]['ad'] ?? "",
              ),
              decoration: InputDecoration(
                hintText: "Ürün / Marka / Model",
                suffixIcon: IconButton(
                  icon: const Icon(Icons.inventory, color: Colors.orange),
                  onPressed: () => _stoktanSec(i),
                ),
              ),
              onChanged: (v) {
                _kalemler[i]['ad'] = v;
              },
            ),

            Row(
              children: [
                Expanded(
                  child: TextField(
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: "Adet"),
                    onChanged: (v) {
                      setState(() {
                        _kalemler[i]['adet'] =
                            double.tryParse(v) ?? 1.0;
                      });
                    },
                  ),
                ),

                const SizedBox(width: 10),

                Expanded(
                  child: TextField(
                    controller: _kalemler[i]['controller'],
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: "Fiyat"),
                    onChanged: (v) {
                      setState(() {
                        // ❌ ARTIK AD'A DOKUNMUYORUZ
                        _kalemler[i]['fiyat'] =
                            double.tryParse(v) ?? 0.0;
                      });
                    },
                  ),
                ),

                IconButton(
                  icon: const Icon(Icons.delete, color: Colors.red),
                  onPressed: () => setState(() => _kalemler.removeAt(i)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _hesapPano(Map<String, double> h) {
    String suAnkiTarih = DateFormat('dd.MM.yyyy').format(DateTime.now());
    String tamTarihSaat = DateFormat('dd.MM.yyyy HH:mm').format(DateTime.now());

    // 🔥 TÜRKÇE PARA FORMATI FONKSİYONU
    String format(double? m) {
      if (m == null) return "0,00";
      return m.toStringAsFixed(2)
          .replaceAll('.', '|') // Noktayı geçici koru
          .replaceAll(',', '.') // Virgülü nokta yap
          .replaceAll('|', ','); // Korunan noktayı virgül yap
      // Not: Binlik ayıracı için daha detaylı Regex gerekebilir ama bu kuruşu düzeltir.
    }

    // Daha profesyonel binlik ayırıcılı format:
    String trFormat(double? m) {
      if (m == null) return "0,00";
      // Bu kısım 1000000.50 -> 1.000.000,50 yapar
      RegExp reg = RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))');
      String mathFunc(Match match) => '${match[1]}.';

      String sabit = m.toStringAsFixed(2);
      List<String> parcalar = sabit.split('.');
      parcalar[0] = parcalar[0].replaceAllMapped(reg, mathFunc);
      return parcalar.join(',');
    }

    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
          color: Colors.blueGrey[900],
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20))
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(child: _oranInput("İskonto %", (v) => setState(() => _iskontoOrani = double.tryParse(v) ?? 0))),
              const SizedBox(width: 15),
              Expanded(child: _oranInput("KDV %", (v) => setState(() => _kdvOrani = double.tryParse(v) ?? 20))),
            ],
          ),
          const Divider(color: Colors.white24, height: 20),

          // 🔥 BURADA FORMATLI FONKSİYONU ÇAĞIRIYORUZ
          _ozetSatir("Ara Toplam:", "${trFormat(h['ara'])} TL"),
          _ozetSatir("İskonto Tutarı:", "- ${trFormat(h['isk'])} TL", renk: Colors.orangeAccent),
          _ozetSatir("KDV Matrahı:", "${trFormat(h['mat'])} TL"),
          _ozetSatir("KDV Tutarı:", "+ ${trFormat(h['kdv'])} TL", renk: Colors.blueAccent),

          const Divider(color: Colors.white, height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text("İŞLEM TARİHİ", style: TextStyle(color: Colors.white54, fontSize: 10)),
                Text(suAnkiTarih, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
              ]),
              // 🔥 TOPLAM RAKAMI BURADA DÜZELTİLDİ
              _ozetSatir("TOPLAM:", "${trFormat(h['toplam'])} TL", renk: Colors.greenAccent, bold: true, fontBoyut: 22),
            ],
          ),
          const SizedBox(height: 15),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green[700],
                minimumSize: const Size(double.infinity, 55),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))
            ),
            onPressed: () {
              List<Map<String, dynamic>> kalemListesi = _kalemler.map((k) {
                return {
                  "ad": k['ad']?.toString() ?? "",
                  "marka": k['marka'] ?? "",
                  "model": k['model'] ?? "",
                  "alt_model": k['alt_model'] ?? "",
                  "adet": double.tryParse(k['adet']?.toString() ?? '1') ?? 1.0,
                  "fiyat": double.tryParse(k['fiyat']?.toString() ?? '0') ?? 0.0,
                  "toplam": (double.tryParse(k['fiyat']?.toString() ?? '0') ?? 0.0) * (double.tryParse(k['adet']?.toString() ?? '1') ?? 1.0),
                };
              }).toList();

              Map<String, dynamic> proformaData = {
                "ad_norm": _adC.text.trim().isEmpty ? "İsimsiz Müşteri" : _adC.text.trim(),
                "tc": _tcC.text.trim(),
                "adres": _adresC.text.trim(),
                "ara_toplam": h['ara'],
                "iskonto_tutari": h['isk'],
                "kdv_tutari": h['kdv'],
                "toplam": h['toplam'],
                "kdv_orani": _kdvOrani,
                "iskonto_orani": _iskontoOrani,
                "tarih": tamTarihSaat,
                "urunler": kalemListesi,
                "sube": "AKSU",
              };

              Navigator.pop(context, proformaData);
            },
            child: const Text("KAYDI TAMAMLA",
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
          )
        ],
      ),
    );
  }

  Widget _ozetSatir(String s, String d, {Color renk = Colors.white, bool bold = false, double fontBoyut = 14}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text(s, style: const TextStyle(color: Colors.white70, fontSize: 13)),
      Text(d, style: TextStyle(color: renk, fontWeight: bold ? FontWeight.bold : FontWeight.normal, fontSize: fontBoyut)),
    ]),
  );

  Widget _oranInput(String l, Function(String) n) => TextField(
    style: const TextStyle(color: Colors.white, fontSize: 13),
    decoration: InputDecoration(labelText: l, labelStyle: const TextStyle(color: Colors.white60, fontSize: 12), enabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)), focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Colors.orange))),
    keyboardType: TextInputType.number,
    onChanged: n,
  );

  Widget _input(TextEditingController c, String l, {int maxLines = 1}) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: TextField(controller: c, maxLines: maxLines, decoration: InputDecoration(labelText: l, border: const OutlineInputBorder(), contentPadding: const EdgeInsets.all(10))),
  );
}
