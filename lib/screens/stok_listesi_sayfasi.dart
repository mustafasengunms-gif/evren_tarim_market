
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
import 'package:flutter/foundation.dart' show kIsWeb; //
import 'dart:io' as io; // File hatasını engellemek için 'as io' dedik[cite: 1]
import '../db/database_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'dart:io' show File;

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

// 👇 İŞTE TAM BURAYA YAPIŞTIR (Herhangi bir metodun dışında kalsın)
  Widget _resimGoster(String path) {
    if (kIsWeb) {
      return const Icon(Icons.image, size: 50, color: Colors.grey);
    } else {
      // io.File olarak çağırmayı unutma, en üstte 'import dart:io as io' olmalı
      return Image.file(io.File(path));
    }
  }

  // --- 1. FOTOĞRAF BÜYÜTME (HATA VERMEYEN VERSİYON) ---
  void _fotoBuyut(String path, dynamic urunAdi) {
    // urunAdi null ise boş string basıyoruz ki uygulama patlamasın
    String baslik = (urunAdi ?? "Ürün Detayı").toString();
    showDialog(
      context: context,
      builder: (context) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(backgroundColor: Colors.transparent, foregroundColor: Colors.white, title: Text(baslik)),
        body: Center(
          child: InteractiveViewer(
            minScale: 0.5,
            maxScale: 5.0,
            child: Image.file(File(path), fit: BoxFit.contain),
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

        bool bYazi = (s['urun']?.toString().toLowerCase() ?? "").contains(arama) ||
            (s['marka']?.toString().toLowerCase() ?? "").contains(arama);

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

  // --- 3. EXCEL OLUŞTURMA (HIZLI VE TAM) ---
  Future<void> _excelOlustur() async {
    var excel = ex.Excel.createExcel();
    ex.Sheet sheet = excel[''];
    excel.delete('Sheet1');
    sheet.appendRow([ex.TextCellValue('Marka'), ex.TextCellValue('Ürün'), ex.TextCellValue('Alt Model'), ex.TextCellValue('Adet'), ex.TextCellValue('Şube'), ex.TextCellValue('Durum')]);
    for (var s in _filtreliStok) {
      sheet.appendRow([
        ex.TextCellValue(s['marka']?.toString() ?? ''),
        ex.TextCellValue(s['urun']?.toString() ?? ''),
        ex.TextCellValue((s['alt_model'] ?? s['altmodel'] ?? '').toString()),
        ex.DoubleCellValue(double.tryParse(s['adet'].toString()) ?? 0.0),
        ex.TextCellValue(s['sube']?.toString() ?? ''),
        ex.TextCellValue(s['durum']?.toString() ?? ''),
      ]);
    }
    final bytes = excel.save();
    final dir = await getTemporaryDirectory();
    File f = File("${dir.path}/Stok_${DateFormat('dd_MM_HHmm').format(DateTime.now())}.xlsx");
    await f.writeAsBytes(bytes!);
    await Share.shareXFiles([XFile(f.path)]);
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

              // Marka Model ve Alt Modeli tek satırda birleştiriyoruz
              String markaModelAlt = "${s['marka'] ?? ''} ${s['urun'] ?? ''} ${s['alt_model'] ?? s['altmodel'] ?? ''}".trim();

              return [
                markaModelAlt.toUpperCase(),
                s['adet']?.toString() ?? '0',
                s['sube']?.toString() ?? '-',
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

// --- LİSTE TASARIMI VE SIFIR STOK FİLTRESİ GÜNCEL HALİ ---

  @override
  void initState() {
    super.initState();
    // SIFIR STOKLARI EN BAŞTA ELİYORUZ
    _tumStoklar = widget.ilkVeriler.where((s) {
      double adet = double.tryParse(s['adet']?.toString() ?? "0") ?? 0.0;
      return adet > 0; // Sadece 0'dan büyük olanlar
    }).map((s) {
      var m = Map<String, dynamic>.from(s);
      m['durum'] = (m['durum']?.toString().toUpperCase().trim() ?? "SIFIR");
      return m;
    }).toList();
    _filtreliStok = List.from(_tumStoklar);
  }

// ... (Diğer fonksiyonlar aynı kalıyor)

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
                bool is2El = (s['durum']?.toString().toUpperCase() ?? "") == "2. EL";
                String foto = s['foto']?.toString() ?? "";
                String firma = (s['tarim_firmalari'] ?? s['firma'] ?? 'BİLİNMEYEN').toString().toUpperCase();
                String altModel = (s['alt_model'] ?? s['altmodel'] ?? '-').toString().toUpperCase();
                String sube = (s['sube']?.toString() ?? 'BİLİNMEYEN').toUpperCase();

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
                      onTap: () => (foto.isNotEmpty && File(foto).existsSync()) ? _fotoBuyut(foto, s['urun']) : null,
                      child: Container(
                        width: 50, height: 50,
                        decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(8)),
                        child: (foto.isNotEmpty && File(foto).existsSync())
                            ? ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.file(File(foto), fit: BoxFit.cover))
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
                        // ŞUBE BİLGİSİ BURAYA EKLENDİ
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
    return Expanded(child: DropdownButtonFormField(
      value: l.contains(v) ? v : "HEPSİ",
      items: l.map((e) => DropdownMenuItem(value: e, child: Text(e, style: const TextStyle(fontSize: 10), overflow: TextOverflow.ellipsis))).toList(),
      onChanged: c,
      decoration: InputDecoration(labelText: t, isDense: true, border: const OutlineInputBorder(), contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8)),
    ));
  }
}