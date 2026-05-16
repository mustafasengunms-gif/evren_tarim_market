import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

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

  // ✅ BİÇER MÜŞTERİ EKSTRESİ (HASAT + TAHSİLAT) - BAŞLIKLAR KORUNDU VE VERİLER BAĞLANDI
  static Future<void> bicerMusteriEkstresiGoster(
      BuildContext context,
      String musteriAd,
      List<Map<String, dynamic>> hareketler
      ) async {
    final pdf = pw.Document();
    final font = await PdfGoogleFonts.robotoRegular();
    final boldFont = await PdfGoogleFonts.robotoBold();

    // Logo yükleme
    pw.ImageProvider? imageProvider;
    try {
      imageProvider = await flutterImageProvider(const AssetImage('assets/images/logo.png'));
    } catch (e) {
      print("Logo yüklenemedi: $e");
    }

    DateTime simdi = DateTime.now();
    String tarihFormati = "${simdi.day.toString().padLeft(2, '0')}.${simdi.month.toString().padLeft(2, '0')}.${simdi.year}";

    double toplamBorc = 0;
    double toplamAlacak = 0;

    // 1. HESAPLAMA MANTIĞI (Görseldeki miktar ve tip sütunlarına göre)
    for (var h in hareketler) {
      double miktar = double.tryParse(h['miktar']?.toString() ?? '0') ?? 0.0;
      String tip = (h['tip'] ?? '').toString().toUpperCase();

      if (tip == 'HASAT') {
        toplamBorc += miktar;
      } else if (tip == 'TAHSİLAT' || tip == 'TAHSILAT' || tip == 'NAKİT') {
        toplamAlacak += miktar;
      }
    }

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        theme: pw.ThemeData.withFont(base: font, bold: boldFont),
        build: (context) => [
          // SENİN BAŞLIK METODUN - TARİH VE LOGO İLE
          if (imageProvider != null) _pdfBicerBaslik(imageProvider, boldFont, font, tarihFormati),

          pw.SizedBox(height: 10),
          pw.Text("Müşteri: ${musteriAd.toUpperCase()}", style: pw.TextStyle(fontSize: 14, font: boldFont)),
          pw.SizedBox(height: 15),

          // 2. TABLO VERİLERİ (Sütunlar image_76da35.png ile tam uyumlu)[cite: 1]
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey300),
            columnWidths: {
              0: const pw.FlexColumnWidth(2.5),
              1: const pw.FlexColumnWidth(4.5),
              2: const pw.FlexColumnWidth(2.5),
              3: const pw.FlexColumnWidth(3),
            },
            children: [
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: PdfColors.orange900),
                children: [
                  _pdfHucre("TARİH", boldFont, PdfColors.white, true),
                  _pdfHucre("AÇIKLAMA", boldFont, PdfColors.white, true),
                  _pdfHucre("İŞLEM TİPİ", boldFont, PdfColors.white, true),
                  _pdfHucre("TUTAR", boldFont, PdfColors.white, true),
                ],
              ),
              ...hareketler.map((h) {
                String tip = (h['tip'] ?? '').toString().toUpperCase();
                bool isHasat = tip == 'HASAT';
                double tutar = double.tryParse(h['miktar']?.toString() ?? '0') ?? 0.0;

                return pw.TableRow(
                  children: [
                    _pdfHucre(h['tarih'] ?? "", font, PdfColors.black, false),
                    _pdfHucre(h['aciklama'] ?? "-", font, PdfColors.black, false), // Veritabanındaki açıklama[cite: 1]
                    _pdfHucre(tip, font, PdfColors.black, false),
                    _pdfHucre(
                        "${formatPara(tutar)} TL",
                        boldFont,
                        isHasat ? PdfColors.red900 : PdfColors.green900,
                        false
                    ),
                  ],
                );
              }).toList(),
            ],
          ),

          pw.SizedBox(height: 20),

          // 3. SENİN ÖZET PANELİN - RENKLER VE HESAPLAR DOĞRU
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.end,
            children: [
              pw.Container(
                width: 220,
                padding: const pw.EdgeInsets.all(10),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.orange900, width: 1),
                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
                ),
                child: pw.Column(
                  children: [
                    _ozetSatiri("Toplam İş Bedeli:", formatPara(toplamBorc), PdfColors.red900, boldFont),
                    pw.SizedBox(height: 4),
                    _ozetSatiri("Toplam Tahsilat:", formatPara(toplamAlacak), PdfColors.green900, boldFont),
                    pw.Divider(color: PdfColors.orange900),
                    _ozetSatiri(
                        "KALAN BAKİYE:",
                        "${formatPara(toplamBorc - toplamAlacak)} TL",
                        (toplamBorc - toplamAlacak) > 0 ? PdfColors.red900 : PdfColors.green900,
                        boldFont,
                        fontSize: 12
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );

    // 4. ÖNİZLEME EKRANI (NAVIGATOR İLE)
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => Scaffold(
          appBar: AppBar(title: Text("$musteriAd - Biçer Ekstresi"), backgroundColor: Colors.orange[900]),
          body: PdfPreview(build: (format) => pdf.save(), canDebug: false),
        ),
      ),
    );
  }

  // YARDIMCI METODLAR (Bunlar static olarak PdfHelper içinde kalmalı)

  static pw.Widget _pdfBicerBaslik(pw.ImageProvider image, pw.Font boldFont, pw.Font font, String tarih) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Row(
          children: [
            pw.Container(width: 45, height: 45, child: pw.Image(image)),
            pw.SizedBox(width: 10),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text("EVREN TARIM MARKET", style: pw.TextStyle(fontSize: 18, font: boldFont, color: PdfColors.orange900)),
                pw.Text("BİÇERDÖVER HASAT HİZMETLERİ", style: pw.TextStyle(fontSize: 10, font: font)),
                pw.Text("Tefenni / BURDUR", style: pw.TextStyle(fontSize: 9)),
              ],
            ),
          ],
        ),
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Text("BİÇER MÜŞTERİ EKSTRE", style: pw.TextStyle(fontSize: 14, font: boldFont, color: PdfColors.orange900)),
            pw.Text("Sezon: 2026", style: pw.TextStyle(fontSize: 10)),
            pw.Text("Tarih: $tarih", style: pw.TextStyle(fontSize: 10)),
          ],
        ),
      ],
    );
  }

  // Özet satırı için yardımcı widget
  static pw.Widget _ozetSatiri(String baslik, String deger, PdfColor renk, pw.Font font, {double fontSize = 10}) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(baslik, style: pw.TextStyle(fontSize: fontSize, font: font)),
        pw.Text(deger, style: pw.TextStyle(fontSize: fontSize, font: font, color: renk)),
      ],
    );
  }
  // ✅ TARIM FİRMA EKSTRESİ (MÜHÜRLÜ VE CARİ KODLU)
  static Future<void> tarimFirmaEkstresiGoster(
      BuildContext context,
      String firmaAdi, // Parametre ismimiz bu
      List<Map<String, dynamic>> hareketler,
      [double bakiye = 0.0]
      ) async {
    final pdf = pw.Document();
    final font = await PdfGoogleFonts.robotoRegular();
    final boldFont = await PdfGoogleFonts.robotoBold();

    // Cari kodu ilk hareketten veya güvenli bir şekilde alalım
    String cariKod = hareketler.isNotEmpty ? (hareketler.first['cari_kod'] ?? "-") : "-";

    final imageProvider = await flutterImageProvider(const AssetImage('assets/images/logo.png'));
    String tarih = DateFormat('dd.MM.yyyy').format(DateTime.now());

    double toplamAlim = 0;
    double toplamOdeme = 0;
    double yuruyenBakiye = 0;

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        theme: pw.ThemeData.withFont(base: font, bold: boldFont),
        build: (context) => [
          // Başlık ve Logo
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
                    ],
                  ),
                ],
              ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text("FİRMA CARİ EKSTRESİ", style: pw.TextStyle(fontSize: 14, font: boldFont)),
                  pw.Text("Tarih: $tarih"),
                ],
              ),
            ],
          ),
          pw.SizedBox(height: 10),
          pw.Divider(thickness: 2, color: PdfColors.blue900),
          pw.SizedBox(height: 10),

          // FİRMA VE CARİ KOD BİLGİSİ
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text("Firma: ${firmaAdi.toUpperCase()}", style: pw.TextStyle(fontSize: 14, font: boldFont)), // firmaAd değil firmaAdi yaptık
              pw.Text("Cari Kod: $cariKod", style: pw.TextStyle(fontSize: 12, font: boldFont, color: PdfColors.grey700)),
            ],
          ),
          pw.SizedBox(height: 15),

          // Tablo Yapısı
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey300),
            columnWidths: {
              0: const pw.FlexColumnWidth(2),
              1: const pw.FlexColumnWidth(4),
              2: const pw.FlexColumnWidth(2),
              3: const pw.FlexColumnWidth(2),
              4: const pw.FlexColumnWidth(2.5),
            },
            children: [
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: PdfColors.blue900),
                children: [
                  _pdfHucre("TARİH", boldFont, PdfColors.white, true),
                  _pdfHucre("AÇIKLAMA", boldFont, PdfColors.white, true),
                  _pdfHucre("BORÇ", boldFont, PdfColors.white, true),
                  _pdfHucre("ALACAK", boldFont, PdfColors.white, true),
                  _pdfHucre("BAKİYE", boldFont, PdfColors.white, true),
                ],
              ),
              // PDF içindeki map döngüsünü bu mantıkla güncelle:
              ...hareketler.map((h) {
                double tutar = double.tryParse((h['tutar'] ?? '0').toString()) ?? 0;

                // Tipi temizle: Boşlukları at, büyük harfe çevir
                String tip = (h['tip'] ?? "").toString().trim().toUpperCase();

                // ÖDEME tespiti: İçinde ÖDEME, ODEME veya TAHSİLAT geçiyorsa ödemedir
                bool isOdeme = tip.contains("ÖDEME") || tip.contains("ODEME") || tip.contains("TAHSİLAT");

                if (isOdeme) {
                  toplamOdeme += tutar;
                  yuruyenBakiye -= tutar;
                } else {
                  // İçinde ödeme geçmeyen her şey (ALIM, GÜBRE, TOHUM vb.) borçtur
                  toplamAlim += tutar;
                  yuruyenBakiye += tutar;
                }

                return pw.TableRow(
                  children: [
                    _pdfHucre(h['tarih'] ?? "", font, PdfColors.black, false),
                    _pdfHucre((h['urun_adi'] ?? h['tip'] ?? "-").toString().toUpperCase(), font, PdfColors.black, false),
                    _pdfHucre(!isOdeme ? formatPara(tutar) : "0,00", font, !isOdeme ? PdfColors.red900 : PdfColors.black, false),
                    _pdfHucre(isOdeme ? formatPara(tutar) : "0,00", font, isOdeme ? PdfColors.green900 : PdfColors.black, false),
                    _pdfHucre(formatPara(yuruyenBakiye), boldFont, yuruyenBakiye > 0 ? PdfColors.red900 : PdfColors.green900, false),
                  ],
                );
              }).toList(),
            ],
          ),

          pw.SizedBox(height: 20),

          // Alt Özet
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.end,
            children: [
              pw.Container(
                width: 200,
                padding: const pw.EdgeInsets.all(10),
                decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey), borderRadius: const pw.BorderRadius.all(pw.Radius.circular(5))),
                child: pw.Column(
                  children: [
                    _ozetSatiri("Toplam Alım:", formatPara(toplamAlim), PdfColors.red900, boldFont),
                    _ozetSatiri("Toplam Ödeme:", formatPara(toplamOdeme), PdfColors.green900, boldFont),
                    pw.Divider(),
                    _ozetSatiri("GÜNCEL BORÇ:", "${formatPara(yuruyenBakiye)} TL", yuruyenBakiye > 0 ? PdfColors.red900 : PdfColors.green900, boldFont, fontSize: 12),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );

    // Önizleme
    await Navigator.push(context, MaterialPageRoute(builder: (context) => Scaffold(
      appBar: AppBar(title: Text("$firmaAdi - Ekstre"), backgroundColor: Colors.blue[900]), // firmaAd düzeltildi
      body: PdfPreview(build: (format) => pdf.save()),
    )));
  }
}