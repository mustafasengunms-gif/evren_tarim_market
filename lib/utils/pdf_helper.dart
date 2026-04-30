import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:flutter/material.dart';

class PdfHelper {
  // ✅ Para formatlama fonksiyonu (1.500,00 formatı)
  static String formatPara(dynamic deger) {
    try {
      if (deger == null) return "0,00";
      double rakam = double.tryParse(deger.toString().replaceAll(',', '.')) ?? 0;
      String sonuc = rakam.toStringAsFixed(2).replaceAll('.', ',');
      RegExp reg = RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))');
      return sonuc.replaceAllMapped(reg, (Match m) => '${m[1]}.');
    } catch (e) {
      return "0,00";
    }
  }

  static Future<void> musteriEkstresiGoster(
      BuildContext context,
      String musteriAd,
      List<Map<String, dynamic>> hareketler
      ) async {
    final pdf = pw.Document();
    final font = await PdfGoogleFonts.robotoRegular();
    final boldFont = await PdfGoogleFonts.robotoBold();

    final imageProvider = await flutterImageProvider(const AssetImage('assets/images/logo.png'));

    DateTime simdi = DateTime.now();
    String tarih = "${simdi.day.toString().padLeft(2, '0')}.${simdi.month.toString().padLeft(2, '0')}.${simdi.year}";

    double toplamBorc = 0;
    double toplamAlacak = 0;

    for (var h in hareketler) {
      double tutar = double.tryParse((h['tutar'] ?? h['toplam_tutar'] ?? '0').toString()) ?? 0;
      String islem = (h['islem'] ?? "SATIS").toString().toUpperCase();
      if (islem == "SATIS" || islem == "BORC") {
        toplamBorc += tutar;
      } else if (islem == "TAHSILAT" || islem == "ALACAK") {
        toplamAlacak += tutar;
      }
    }

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        theme: pw.ThemeData.withFont(base: font, bold: boldFont),
        build: (context) => [
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Row(
                children: [
                  pw.Container(width: 50, height: 50, child: pw.Image(imageProvider)),
                  pw.SizedBox(width: 10),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text("EVREN TARIM MARKET", style: pw.TextStyle(fontSize: 20, font: boldFont, color: PdfColors.blue900)),
                      pw.Text("Tefenni / BURDUR", style: pw.TextStyle(fontSize: 10)),
                      pw.Text("Güvenilir Tarım Ticareti", style: pw.TextStyle(fontSize: 9, font: font)),
                    ],
                  ),
                ],
              ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text("MÜŞTERİ EKSTRESİ", style: pw.TextStyle(fontSize: 14, font: boldFont)),
                  pw.Text("Tarih: $tarih"),
                ],
              ),
            ],
          ),
          pw.SizedBox(height: 10),
          pw.Divider(thickness: 2, color: PdfColors.blue900),
          pw.SizedBox(height: 10),

          pw.Text("Müşteri: ${musteriAd.toUpperCase()}", style: pw.TextStyle(fontSize: 15, font: boldFont)),
          pw.SizedBox(height: 15),

          // 📊 RENKLİ EKSTRE TABLOSU
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey300),
            columnWidths: {
              0: const pw.FlexColumnWidth(2), // Tarih
              1: const pw.FlexColumnWidth(4), // Açıklama
              2: const pw.FlexColumnWidth(2), // İşlem
              3: const pw.FlexColumnWidth(3), // Tutar
            },
            children: [
              // Başlık Satırı
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: PdfColors.blue900),
                children: [
                  _pdfHucre("TARİH", boldFont, PdfColors.white, true),
                  _pdfHucre("AÇIKLAMA", boldFont, PdfColors.white, true),
                  _pdfHucre("İŞLEM", boldFont, PdfColors.white, true),
                  _pdfHucre("TUTAR", boldFont, PdfColors.white, true),
                ],
              ),
              // Veri Satırları
              ...hareketler.map((h) {
                double t = double.tryParse((h['tutar'] ?? h['toplam_tutar'] ?? '0').toString()) ?? 0;
                String i = (h['islem'] ?? "SATIS").toString().toUpperCase();

                // Renk ve Yazı Kararı
                bool isSatis = (i == "SATIS" || i == "BORC");
                PdfColor renk = isSatis ? PdfColors.red900 : PdfColors.green900;
                String islemMetni = isSatis ? "SATIŞ" : "TAHSİLAT";

                return pw.TableRow(
                  children: [
                    _pdfHucre(h['tarih'] ?? "", font, PdfColors.black, false),
                    _pdfHucre((h['aciklama'] ?? "-").toString().toUpperCase(), font, PdfColors.black, false),
                    _pdfHucre(islemMetni, boldFont, renk, false),
                    _pdfHucre("${formatPara(t)} TL", boldFont, renk, false),
                  ],
                );
              }).toList(),
            ],
          ),

          pw.SizedBox(height: 20),

          // 💰 HESAP ÖZETİ (BURAYI DEĞİŞTİR)
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.end,
            children: [
              pw.Container(
                width: 200,
                padding: const pw.EdgeInsets.all(10),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.grey),
                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(5)),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text(
                      "Toplam Satış: ${formatPara(toplamBorc)} TL",
                      style: pw.TextStyle(font: boldFont, color: PdfColors.red900), // 🔥 KIRMIZI
                    ),
                    pw.SizedBox(height: 2),
                    pw.Text(
                      "Toplam Tahsilat: ${formatPara(toplamAlacak)} TL",
                      style: pw.TextStyle(font: boldFont, color: PdfColors.green900), // 🔥 YEŞİL
                    ),
                    pw.Divider(),
                    pw.Text(
                      "KALAN BAKİYE: ${formatPara(toplamBorc - toplamAlacak)} TL",
                      style: pw.TextStyle(
                          fontSize: 14,
                          font: boldFont,
                          color: (toplamBorc - toplamAlacak) > 0 ? PdfColors.red900 : PdfColors.green900
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 50),
          pw.Center(child: pw.Text("Bu ekstre sistem tarafından otomatik oluşturulmuştur.", style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey))),
        ],
      ),
    );

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => Scaffold(
          appBar: AppBar(title: Text("$musteriAd - Ekstre Önizleme"), backgroundColor: Colors.blue[900]),
          body: PdfPreview(build: (format) => pdf.save()),
        ),
      ),
    );
  }

  // ✅ Tablo Hücresi Yardımcı Fonksiyonu (Kod kalabalığını önler)
  static pw.Widget _pdfHucre(String metin, pw.Font font, PdfColor renk, bool isHeader) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(5),
      child: pw.Text(
        metin,
        style: pw.TextStyle(font: font, color: renk, fontSize: isHeader ? 10 : 9),
        textAlign: pw.TextAlign.left,
      ),
    );
  }
  // ✅ Stok Raporu Fonksiyonu
  static Future<void> stokRaporuGoster(
      BuildContext context,
      List<Map<String, dynamic>> filtreliListe,
      int aktifSube
      ) async {
    final pdf = pw.Document();
    final font = await PdfGoogleFonts.robotoRegular();
    final boldFont = await PdfGoogleFonts.robotoBold();

    DateTime simdi = DateTime.now();
    String formatliTarih = "${simdi.day.toString().padLeft(2, '0')}.${simdi.month.toString().padLeft(2, '0')}.${simdi.year}";
    String subeBaslik = aktifSube == 0 ? "TEFENNİ" : (aktifSube == 1 ? "AKSU" : "TÜM ŞUBELER");

    int toplamAdet = 0;
    double genelToplamTutar = 0;

    for (var item in filtreliListe) {
      int adet = int.tryParse(item['adet'].toString()) ?? 0;
      double fiyat = double.tryParse(item['fiyat'].toString()) ?? 0;
      toplamAdet += adet;
      genelToplamTutar += (adet * fiyat);
    }

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        theme: pw.ThemeData.withFont(base: font, bold: boldFont),
        build: (context) => [
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text("EVREN TARIM STOK RAPORU", style: pw.TextStyle(fontSize: 16, font: boldFont)),
              pw.Text(formatliTarih),
            ],
          ),
          pw.Divider(),
          pw.TableHelper.fromTextArray(
            headers: ['MARKA', 'MODEL', 'ADET', 'SUBE', 'B.FIYAT', 'TOPLAM'],
            data: [
              ...filtreliListe.map((s) {
                int adet = int.tryParse(s['adet']?.toString() ?? "0") ?? 0;
                double fiyat = double.tryParse(s['fiyat']?.toString() ?? "0") ?? 0;
                return [
                  s['marka']?.toString().toUpperCase() ?? "",
                  (s['urun'] ?? s['model'] ?? "").toString().toUpperCase(),
                  adet.toString(),
                  s['sube']?.toString() ?? "",
                  formatPara(fiyat),
                  formatPara(adet * fiyat),
                ];
              }).toList(),
              ["GENEL TOPLAM", "", toplamAdet.toString(), "", "", "${formatPara(genelToplamTutar)} TL"],
            ],
          ),
        ],
      ),
    );

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => Scaffold(
          appBar: AppBar(title: Text("$subeBaslik - Rapor Önizleme"), backgroundColor: Colors.teal[800]),
          body: PdfPreview(build: (format) => pdf.save()),
        ),
      ),
    );
  }
}