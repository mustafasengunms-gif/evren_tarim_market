import 'package:flutter/foundation.dart' show kIsWeb;
// dart:io'yu sadece kütüphane bazında içeri alıyoruz ki Web patlamasın
import 'dart:io' as io;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:excel/excel.dart' as ex;
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../db/database_helper.dart';

class StokListesiSayfasi extends StatefulWidget {
  final List<Map<String, dynamic>> ilkVeriler;
  const StokListesiSayfasi({super.key, required this.ilkVeriler});

  @override
  State<StokListesiSayfasi> createState() => _StokListesiSayfasiState();
}

class _StokListesiSayfasiState extends State<StokListesiSayfasi> {
  final TextEditingController _aramaC = TextEditingController();

  String _seciliSube = "HEPSİ", _seciliKategori = "HEPSİ", _seciliMarka = "HEPSİ";
  String _seciliAltModel = "HEPSİ", _seciliDurum = "HEPSİ", _seciliSektor = "HEPSİ";

  List<Map<String, dynamic>> _tumStoklar = [];
  List<Map<String, dynamic>> _filtreliStok = [];
// --- TOPLAM TUTAR HESAPLAMA FONKSİYONU ---
  double _toplamTutarHesapla() {
    double toplam = 0;
    for (var s in _filtreliStok) {
      // Adet ve fiyatı güvenli bir şekilde double'a çeviriyoruz
      double adet = double.tryParse(s['adet']?.toString() ?? "0") ?? 0;
      double fiyat = double.tryParse(s['fiyat']?.toString() ?? "0") ?? 0;
      toplam += (adet * fiyat);
    }
    return toplam;
  }


  bool _fotoVarMi(String path) {
    // 1. Eğer web tarayıcısındaysak dosya sistemi yoktur, direkt false dön.
    if (kIsWeb) return false;

    // 2. Yol boşsa kontrol etmeye gerek yok.
    if (path.isEmpty) return false;

    // 3. Mobildeysek dart:io (io) üzerinden dosya var mı diye bak.
    return io.File(path).existsSync();
  }

  // --- 1. FOTOĞRAF BÜYÜTME (WEB VE MOBİL UYUMLU) ---
  void _fotoBuyut(String path, dynamic urunAdi) {
    if (kIsWeb) return; // Web'de dosya sistemi olmadığı için işlemi durdur

    String baslik = (urunAdi ?? "Ürün Detayı").toString();
    showDialog(
      context: context,
      builder: (context) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
            backgroundColor: Colors.transparent,
            foregroundColor: Colors.white,
            title: Text(baslik)
        ),
        body: Center(
          child: InteractiveViewer(
            minScale: 0.5,
            maxScale: 5.0,
            // BURAYA DİKKAT: File yerine io.File kullandık
            child: Image.file(io.File(path), fit: BoxFit.contain),
          ),
        ),
      ),
    );
  }

  // --- 2. 6'LI FİLTRELEME SİSTEMİ ---
  void _filtreUygula() {
    setState(() {
      String arama = _aramaC.text.toLowerCase();
      _filtreliStok = _tumStoklar.where((s) {
        bool bSube = _seciliSube == "HEPSİ" || (s['sube']?.toString().toUpperCase() ?? "") == _seciliSube;
        bool bKat = _seciliKategori == "HEPSİ" || (s['kategori']?.toString().toUpperCase() ?? "") == _seciliKategori;
        bool bMarka = _seciliMarka == "HEPSİ" || (s['marka']?.toString().toUpperCase() ?? "") == _seciliMarka;
        bool bAlt = _seciliAltModel == "HEPSİ" || (s['alt_model'] ?? s['altmodel'] ?? "").toString().toUpperCase() == _seciliAltModel;
        bool bDurum = _seciliDurum == "HEPSİ" || (s['durum']?.toString().toUpperCase() ?? "") == _seciliDurum;
        bool bSektor = _seciliSektor == "HEPSİ" || (s['sektor']?.toString().toUpperCase() ?? "") == _seciliSektor;

        bool bYazi = arama.isEmpty ||
            (s['urun']?.toString().toLowerCase() ?? "").contains(arama) ||
            (s['marka']?.toString().toLowerCase() ?? "").contains(arama) ||
            (s['model']?.toString().toLowerCase() ?? "").contains(arama); // Model'i de ekledik

        return bSube && bKat && bMarka && bAlt && bDurum && bSektor && bYazi;
      }).toList();
    });
  }

  List<String> _listeOlustur(String sutun) {
    List<String> liste = _tumStoklar
        .map((e) => (e[sutun] ?? "").toString().toUpperCase().trim())
        .where((e) => e.isNotEmpty && e != "NULL" && e != "FALSE")
        .toSet().toList();
    liste.sort();
    return ["HEPSİ", ...liste];
  }

  // --- 3. EXCEL OLUŞTURMA (WEB VE MOBİL UYUMLU) ---
  Future<void> _excelOlustur() async {
    var excel = ex.Excel.createExcel();
    ex.Sheet sheet = excel[''];
    excel.delete('Sheet1');

    sheet.appendRow([
      ex.TextCellValue('Marka'),
      ex.TextCellValue('Ürün'),
      ex.TextCellValue('Alt Model'),
      ex.TextCellValue('Adet'),
      ex.TextCellValue('Şube'),
      ex.TextCellValue('Durum')
    ]);

    for (var s in _filtreliStok) {
      sheet.appendRow([
        ex.TextCellValue(s['marka']?.toString() ?? ''),
        ex.TextCellValue(s['urun']?.toString() ?? ''),
        ex.TextCellValue((s['alt_model'] ?? s['altmodel'] ?? '').toString()),
        ex.DoubleCellValue(double.tryParse(s['adet']?.toString() ?? "0") ?? 0.0),
        ex.TextCellValue(s['sube']?.toString() ?? ''),
        ex.TextCellValue(s['durum']?.toString() ?? ''),
      ]);
    }

    final bytes = excel.save();
    if (bytes == null) return;

    if (kIsWeb) {
      // --- WEB İÇİN İNDİRME MANTIĞI ---
      await Printing.sharePdf(bytes: Uint8List.fromList(bytes), filename: "Stok_Listesi.xlsx");
    } else {
      // --- MOBİL İÇİN KAYDET VE PAYLAŞ ---
      final dir = await getTemporaryDirectory();
      // 'File' yerine 'io.File' kullanıyoruz!
      io.File f = io.File("${dir.path}/Stok_${DateFormat('dd_MM_HHmm').format(DateTime.now())}.xlsx");
      await f.writeAsBytes(bytes);
      await Share.shareXFiles([XFile(f.path)]);
    }
  }
// --- 4. PDF SİSTEMİ (ÖRNEK ALDIĞIN KURUMSAL TASARIM) ---
  void _pdfOnizlemeGoster() {
    Navigator.push(context, MaterialPageRoute(builder: (context) => Scaffold(
      appBar: AppBar(title: const Text("PDF ÖNİZLEME"), backgroundColor: Colors.blueGrey[900]),
      body: PdfPreview(
        build: (format) => _pdfDosyaOlustur(format),
        canDebug: false,
        pdfFileName: "Evren_Tarim_Stok_Listesi.pdf",
      ),
    )));
  }

  Future<Uint8List> _pdfDosyaOlustur(PdfPageFormat format) async {
    final pdf = pw.Document();

    // Fontlar ve Formatlayıcılar
    final font = await PdfGoogleFonts.robotoRegular();
    final boldFont = await PdfGoogleFonts.robotoBold();
    final formatTR = NumberFormat.currency(locale: "tr_TR", symbol: "₺");

    // Örnekteki gibi logo yükleme
    pw.MemoryImage? logoResmi;
    try {
      final ByteData logoData = await rootBundle.load('assets/images/logo.png');
      logoResmi = pw.MemoryImage(logoData.buffer.asUint8List());
    } catch (e) {
      logoResmi = null;
    }

    pdf.addPage(
      pw.MultiPage(
        pageFormat: format,
        theme: pw.ThemeData.withFont(base: font, bold: boldFont),
        margin: const pw.EdgeInsets.all(25),
        build: (pw.Context context) => [
          // --- LOGO VE BAŞLIK (ÖRNEKTEKİ ROW YAPISI) ---
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Row(
                children: [
                  if (logoResmi != null) pw.Container(width: 50, height: 50, child: pw.Image(logoResmi)),
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
                  pw.Text("STOK RAPORU",
                      style: pw.TextStyle(font: boldFont, fontSize: 12)),
                  pw.Text("Tarih: ${DateFormat('dd.MM.yyyy').format(DateTime.now())}",
                      style: pw.TextStyle(fontSize: 10)),
                ],
              ),
            ],
          ),
          pw.Divider(thickness: 2, color: PdfColors.blue900),
          pw.SizedBox(height: 15),

          // --- TABLO (ÖRNEKTEKİ SÜTUN GENİŞLİKLERİ VE TASARIM) ---
          pw.TableHelper.fromTextArray(
            headers: ['MARKA / MODEL', 'ADET', 'SUBE', 'BİRİM FİYAT', 'TOPLAM'],
            headerStyle: pw.TextStyle(font: boldFont, color: PdfColors.white, fontSize: 10),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.blue900),
            cellAlignment: pw.Alignment.centerLeft,
            cellStyle: const pw.TextStyle(fontSize: 9),
            columnWidths: {
              0: const pw.FlexColumnWidth(4), // Marka/Model alanı geniş
              1: const pw.FlexColumnWidth(1), // Adet dar
              2: const pw.FlexColumnWidth(2), // Şube
              3: const pw.FlexColumnWidth(2), // Birim Fiyat
              4: const pw.FlexColumnWidth(2), // Toplam
            },
            data: _filtreliStok.map((s) {
              double adet = double.tryParse(s['adet']?.toString() ?? "0") ?? 0;
              double fiyat = double.tryParse(s['fiyat']?.toString() ?? "0") ?? 0;

              // 1. ÜRÜN BİLGİSİ (Marka + Ürün/Model + Alt Model)
              String markaModelAlt = "${s['marka'] ?? ''} ${s['urun'] ?? ''} ${s['alt_model'] ?? s['altmodel'] ?? ''}".trim();

              // 2. FİRMA BİLGİSİ (Karmaşayı burada çözüyoruz)
              // SQLite'dan gelen 'firma_unvani' veya 'tarim_firmalari' alanına bakıyoruz
              String firmaUnvan = (s['firma_unvani'] ?? s['tarim_firmalari'] ?? s['firma'] ?? '-').toString().toUpperCase();

              // 3. TABLO SATIRI (Ürün isminin altına firmayı ekleyelim ki rapor kurumsal dursun)
              return [
                "$markaModelAlt\nFİRMA: $firmaUnvan", // İlk sütunda hem ürün hem firma yazacak
                s['adet']?.toString() ?? '0',
                (s['sube']?.toString() ?? '-').toUpperCase(),
                formatTR.format(fiyat),
                formatTR.format(adet * fiyat),
              ];
            }).toList(),
          ),

          pw.SizedBox(height: 20),

          // --- GENEL TOPLAM (ÖRNEKTEKİ SAĞA YASLI KUTU) ---
          pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Container(
              padding: const pw.EdgeInsets.all(8),
              decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.grey400),
                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4))
              ),
              child: pw.Text(
                "GENEL TOPLAM: ${formatTR.format(_toplamTutarHesapla())}",
                style: pw.TextStyle(font: boldFont, fontSize: 13, color: PdfColors.blue900),
              ),
            ),
          ),
        ],
        footer: (context) => pw.Container(
          alignment: pw.Alignment.centerRight,
          margin: const pw.EdgeInsets.only(top: 20),
          child: pw.Text("Sayfa ${context.pageNumber} / ${context.pagesCount}",
              style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey)),
        ),
      ),
    );

    return Uint8List.fromList(await pdf.save());
  }

  // --- 5. SİLME FONKSİYONU ---
  void _stokSil(int id) async {
    bool? onay = await showDialog(context: context, builder: (ctx) => AlertDialog(
      title: const Text("EVREN KAYIT SİLİNECEK"),
      content: const Text("Bu ürün tamamen silinsin mi?"),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("HAYIR")),
        TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("EVET, SİL", style: TextStyle(color: Colors.red))),
      ],
    ));
    if (onay == true) {
      await DatabaseHelper.instance.stokSil(id);
      final guncel = await DatabaseHelper.instance.stokListesiGetir();
      setState(() {
        _tumStoklar = guncel.where((s) => (double.tryParse(s['adet'].toString()) ?? 0) > 0).toList();
        _filtreUygula();
      });
    }
  }

  @override
  void initState() {
    super.initState();

    if (widget.ilkVeriler.isNotEmpty) {
      _tumStoklar = widget.ilkVeriler.map((s) {
        var m = Map<String, dynamic>.from(s);

        // --- 🎯 TUTAR KURTARMA MÜHÜRÜ ---
        // Fiyat bazen 'alis_fiyati' bazen 'fiyat' gelir, ikisini de kontrol et
        double hamFiyat = double.tryParse((m['fiyat'] ?? m['alis_fiyatı'] ?? m['alis_fiyati'] ?? '0').toString()) ?? 0.0;
        m['fiyat'] = hamFiyat;

        // --- 🎯 İSİM KURTARMA MÜHÜRÜ ---
        m['firma_ekran_adi'] = (m['firma_unvani'] ??
            m['ad'] ??
            m['tarim_firmalari'] ??
            m['cari_kod'] ??
            'BİLİNMEYEN').toString().toUpperCase();

        if (m['urun'] == null || m['urun'].toString().isEmpty) {
          m['urun'] = m['model'] ?? "";
        }
        return m;
      }).toList();
    } else {
      _tumStoklar = [];
    }
    _filtreliStok = List.from(_tumStoklar);
  }

  Future<void> stokListesiniAc(BuildContext context) async {
    List<Map<String, dynamic>> veriler = [];

    try {
      if (kIsWeb) {
        // Web tarafında alis_fiyatı alanını kontrol ederek çekiyoruz
        final snapshot = await FirebaseFirestore.instance.collection('stoklar').get();
        veriler = snapshot.docs.map((doc) {
          var data = doc.data();
          return {
            ...data,
            'id': doc.id.hashCode,
            'firebase_id': doc.id,
            'fiyat': double.tryParse((data['alis_fiyatı'] ?? data['alis_fiyati'] ?? data['fiyat'] ?? '0').toString()) ?? 0.0,
            'urun': (data['urun'] ?? data['model'] ?? '').toString().toUpperCase(),
          };
        }).toList();
      } else {
        // --- MOBİL İÇİN ASIL MÜHÜR BURASI ---
        final db = await DatabaseHelper.instance.database;
        veriler = await db.rawQuery('''
        SELECT 
          s.*, 
          f.ad as firma_unvani,
          s.fiyat as fiyat -- SQLite'daki fiyat kolonunu net alalım
        FROM stoklar s
        LEFT JOIN tarim_firmalari f ON s.cari_kod = f.cari_kod
        WHERE s.silindi = 0
      ''');
      }

      if (context.mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (c) => StokListesiSayfasi(ilkVeriler: veriler),
          ),
        );
      }
    } catch (e) {
      debugPrint("Hata oluştu: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[200],
      appBar: AppBar(
        title: const Text("GÜNCEL STOK LİSTESİ"),
        backgroundColor: Colors.blueGrey[900],
        actions: [
          IconButton(icon: const Icon(Icons.picture_as_pdf, color: Colors.redAccent), onPressed: _pdfOnizlemeGoster),
          IconButton(icon: const Icon(Icons.table_chart, color: Colors.greenAccent), onPressed: _excelOlustur),
        ],
      ),
      body: Column(
        children: [
          _filtrePaneli(),
          Expanded(
            child: _filtreliStok.isEmpty
                ? const Center(child: Text("Kriterlere uygun ürün bulunamadı."))
                : ListView.builder(
              itemCount: _filtreliStok.length,
              itemBuilder: (context, i) {
                final s = _filtreliStok[i];

                // --- DEBUG KALSIN DEMİŞTİN ---
                print("---------- STOK VERİSİ (İndex: $i) ----------");
                print("🔍 TÜM SATIR VERİSİ: $s");
                print("---------------------------------------------");

                // 1. DURUM & FOTO
                bool is2El = (s['durum']?.toString().toUpperCase().replaceAll(' ', '') ?? "") == "2.EL";
                String foto = s['foto']?.toString() ?? "";

                // 2. FİRMA ÜNVANI (BURASI KRİTİK)
                // Logda 'ad' null geldiği için 'firma_ekran_adi' veya 'cari_kod'u zorluyoruz.
                String firma = (s['ad'] ??
                    s['firma_unvani'] ??
                    s['firma_ekran_adi'] ?? // Logda dolu olan bu!
                    s['cari_kod'] ??
                    'BİLİNMEYEN').toString().toUpperCase();

                // 3. DİĞER DETAYLAR
                String altModel = (s['alt_model'] ?? s['altmodel'] ?? '-').toString().toUpperCase();
                String sube = (s['sube']?.toString() ?? 'TEFENNİ').toUpperCase();

                return Card(
                  color: is2El ? Colors.orange[50] : Colors.white,
                  margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                      side: BorderSide(color: is2El ? Colors.orange : Colors.transparent)
                  ),
                  child: ListTile(
                    onLongPress: () => _stokSil(s['id']),
                    leading: GestureDetector(
                      // Tıklama kontrolünü bir fonksiyon üzerinden yapıyoruz (Web'de patlamasın diye)
                      onTap: () => _fotoVarMi(foto) ? _fotoBuyut(foto, s['urun']) : null,
                      child: Container(
                        width: 50, height: 50,
                        decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(8)),
                        child: _fotoVarMi(foto)
                            ? ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            // File yerine io.File kullandık
                            child: Image.file(io.File(foto), fit: BoxFit.cover)
                        )
                            : Icon(is2El ? Icons.handshake : Icons.fiber_new, color: is2El ? Colors.orange : Colors.blue),
                      ),
                    ),
                    title: RichText(text: TextSpan(children: [
                      TextSpan(text: "${s['marka']?.toString().toUpperCase() ?? ''} ", style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 16)),
                      TextSpan(text: "${s['urun'] ?? ''}", style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 16)),
                    ])),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.location_on, size: 14, color: Colors.blueGrey[700]),
                            const SizedBox(width: 2),
                            Text(sube, style: TextStyle(color: Colors.blueGrey[900], fontWeight: FontWeight.bold, fontSize: 13)),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text("Alt: $altModel | Firma: $firma", style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: is2El ? Colors.orange : Colors.green,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            is2El ? "2. EL" : "SIFIR",
                            style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text("${s['adet']} Adet", style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 16)),
                        Text("${s['fiyat']} TL", style: const TextStyle(color: Colors.grey, fontSize: 11)),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _filtrePaneli() {
    return Container(
      padding: const EdgeInsets.all(8), color: Colors.white,
      child: Column(children: [
        TextField(controller: _aramaC, onChanged: (v) => _filtreUygula(), decoration: const InputDecoration(hintText: "Ürün veya Marka ara...", prefixIcon: Icon(Icons.search), isDense: true, border: OutlineInputBorder())),
        const SizedBox(height: 8),
        Row(children: [
          _combo("ŞUBE", _seciliSube, ["HEPSİ", "TEFENNİ", "AKSU"], (v) { _seciliSube = v!; _filtreUygula(); }),
          const SizedBox(width: 4),
          _combo("KATEGORİ", _seciliKategori, _listeOlustur('kategori'), (v) { _seciliKategori = v!; _filtreUygula(); }),
          const SizedBox(width: 4),
          _combo("MARKA", _seciliMarka, _listeOlustur('marka'), (v) { _seciliMarka = v!; _filtreUygula(); }),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          _combo("ALT MODEL", _seciliAltModel, _listeOlustur('alt_model'), (v) { _seciliAltModel = v!; _filtreUygula(); }),
          const SizedBox(width: 4),
          _combo("DURUM", _seciliDurum, ["HEPSİ", "SIFIR", "2. EL"], (v) { _seciliDurum = v!; _filtreUygula(); }),
          const SizedBox(width: 4),
          _combo("SEKTÖR", _seciliSektor, _listeOlustur('sektor'), (v) { _seciliSektor = v!; _filtreUygula(); }),
        ]),
      ]),
    );
  }
  Widget _combo(String t, String v, List<String> l, Function(String?) c) {
    return Expanded(
      child: DropdownButtonFormField<String>(
        isExpanded: true, // İÇERİĞİ KUTUYA SIĞMAYA ZORLAR
        value: l.contains(v) ? v : "HEPSİ",
        items: l.map((e) => DropdownMenuItem(
            value: e,
            child: Text(
              e,
              style: const TextStyle(fontSize: 9), // YAZIYI 1 PUAN KÜÇÜLTTÜK
              overflow: TextOverflow.ellipsis,
            )
        )).toList(),
        onChanged: c,
        decoration: InputDecoration(
          labelText: t,
          labelStyle: const TextStyle(fontSize: 9), // ETİKETİ DE KÜÇÜLTTÜK
          isDense: true,
          border: const OutlineInputBorder(),
          contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        ),
      ),
    );
  }
}