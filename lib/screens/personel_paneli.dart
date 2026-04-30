
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import 'package:image_picker/image_picker.dart';
import '../db/database_helper.dart';
import 'package:printing/printing.dart';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show kIsWeb; //
import 'dart:io' as io; // File hatasını engellemek için 'as io' dedik[cite: 1]
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'dart:io' show File;



class PersonelPaneli extends StatefulWidget {
  const PersonelPaneli({super.key});


  @override
  State<PersonelPaneli> createState() => _PersonelPaneliState();
}

class _PersonelPaneliState extends State<PersonelPaneli> {
  List<Map<String, dynamic>> _personeller = [];
  bool _yukleniyor = true;
  final trFormat = NumberFormat.currency(locale: 'tr_TR', symbol: '₺', decimalDigits: 0);
  double safeDouble(dynamic v) {
    if (v == null) return 0;
    if (v is int) return v.toDouble();
    if (v is double) return v;
    return double.tryParse(v.toString()) ?? 0;
  }

  String formatPara(dynamic v) {
    double val = safeDouble(v);
    return trFormat.format(val);
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
    _verileriYukle();
  }

  Future<void> _verileriYukle() async {
    if (!mounted) return; // Widget ekranda değilse işlem yapma

    setState(() => _yukleniyor = true);

    try {
      final veriler = await DatabaseHelper.instance.personelListesiGetir();

      if (mounted) {
        setState(() {
          // Gelen listeyi güvenli bir şekilde map'leyerek sayısal değerleri garantiye alıyoruz
          _personeller = veriler.map((p) {
            return {
              ...p,
              'bakiye': double.tryParse(p['bakiye'].toString()) ?? 0.0,
              'maas': double.tryParse(p['maas'].toString()) ?? 0.0,
            };
          }).toList();
          _yukleniyor = false;
        });
      }
    } catch (e) {
      print("Veri yükleme hatası: $e");
      if (mounted) setState(() => _yukleniyor = false);
    }
  }

  // Hesaplamalarda toDouble() zorlaması ile "0" görünme hatası çözüldü
  double get _aylikMaasYuku => _personeller.fold(0.0, (sum, p) => sum + (double.tryParse(p['maas'].toString()) ?? 0.0));

  // Ödenecek: Sadece personelin alacaklı (pozitif bakiye) olduğu durumların toplamı
  double get _toplamOdenecek => _personeller.fold(0.0, (sum, p) {
    double b = double.tryParse(p['bakiye'].toString()) ?? 0.0;
    return b > 0 ? sum + b : sum;
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text("PERSONEL VE FİNANS", style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.blue.shade900,
        foregroundColor: Colors.white,
        centerTitle: true,
      ),
      body: Column(
        children: [
          _ustBilgiPaneli(),
          _aksiyonButonlari(),
          Expanded(
            child: _yukleniyor
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              itemCount: _personeller.length,
              itemBuilder: (context, index) => _personelKarti(_personeller[index]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _ustBilgiPaneli() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
          color: Colors.blue.shade900,
          borderRadius: const BorderRadius.only(bottomLeft: Radius.circular(30), bottomRight: Radius.circular(30))
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _ozetMetin("PERSONEL", "${_personeller.length}"),
          _ozetMetin("AYLIK YÜK", trFormat.format(_aylikMaasYuku)),
          _ozetMetin("ÖDENECEK", trFormat.format(_toplamOdenecek)),
        ],
      ),
    );
  }

  Widget _ozetMetin(String b, String d) => Column(children: [
    Text(b, style: const TextStyle(color: Colors.white60, fontSize: 10)),
    Text(d, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
  ]);

  Widget _aksiyonButonlari() {
    return Padding(
      padding: const EdgeInsets.all(15.0),
      child: Row(
        children: [
          Expanded(child: _ustButon("YENİ EKLE", Icons.person_add, Colors.green.shade700, () => _personelFormu())),
          const SizedBox(width: 10),
          Expanded(child: _ustButon("RAPOR AL", Icons.picture_as_pdf, Colors.red.shade700, () => _pdfRaporYap())),
        ],
      ),
    );
  }

  Widget _ustButon(String l, IconData i, Color c, VoidCallback t) => ElevatedButton.icon(
    onPressed: t, icon: Icon(i, size: 18), label: Text(l),
    style: ElevatedButton.styleFrom(backgroundColor: c, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 12)),
  );

  Widget _personelKarti(Map<String, dynamic> p) {
    double bakiye = double.tryParse(p['bakiye'].toString()) ?? 0.0;
    Color durumRengi = bakiye > 0 ? Colors.green.shade700 : (bakiye < 0 ? Colors.red.shade700 : Colors.grey);
    String durumMetni = bakiye > 0 ? "Pers. Alacaklı" : (bakiye < 0 ? "Pers. Borçlu" : "Bakiye Sıfır");

    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: ExpansionTile(
        leading: CircleAvatar(
          backgroundColor: durumRengi.withOpacity(0.1),
          backgroundImage: p['foto_yolu'] != null ? FileImage(File(p['foto_yolu'])) : null,
          child: p['foto_yolu'] == null ? Text(p['ad'][0], style: TextStyle(color: durumRengi, fontWeight: FontWeight.bold)) : null,
        ),
        title: Text(p['ad'], style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Row(
          children: [
            Text(trFormat.format(bakiye.abs()), style: TextStyle(color: durumRengi, fontWeight: FontWeight.bold)),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(color: durumRengi.withOpacity(0.1), borderRadius: BorderRadius.circular(5)),
              child: Text(durumMetni, style: TextStyle(fontSize: 10, color: durumRengi, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            color: Colors.grey.shade50,
            child: Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                _kucukButon("ÖDEME YAP", Icons.outbound, Colors.red, () => _hareketDialog(p, "ÖDEME/AVANS")),
                _kucukButon("MAAŞ İŞLE", Icons.assignment_turned_in, Colors.green, () => _hareketDialog(p, "MAAŞ TAHAKKUK")),
                _kucukButon("EKSTRE", Icons.description, Colors.blue, () => _ekstreGoster(p)),
                _kucukButon("FOTO", Icons.camera_alt, Colors.purple, () => _fotoEkle(p)),
                _kucukButon("DÜZENLE", Icons.edit, Colors.blueGrey, () => _personelFormu(personel: p)),
                _kucukButon("SİL", Icons.delete, Colors.red, () => _silOnay(p)),
              ],
            ),
          )
        ],
      ),
    );
  }

  void _hareketDialog(Map<String, dynamic> p, String tur) {
    final tC = TextEditingController(
      text: tur == "MAAŞ TAHAKKUK" ? (p['maas']?.toString() ?? "") : "",
    );

    final aC = TextEditingController();

    final List<String> aylar = [
      "OCAK","ŞUBAT","MART","NİSAN","MAYIS","HAZİRAN",
      "TEMMUZ","AĞUSTOS","EYLÜL","EKİM","KASIM","ARALIK"
    ];

    int secilenAyIndex = DateTime.now().month - 1;

    showDialog(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Text(
            tur == "MAAŞ TAHAKKUK" ? "MAAŞ İŞLE" : "ÖDEME YAP",
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [

              /// 🟢 AY SEÇİMİ
              if (tur == "MAAŞ TAHAKKUK") ...[
                const Text(
                  "Hangi Ayın Maaşı?",
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),

                DropdownButton<int>(
                  isExpanded: true,
                  value: secilenAyIndex,
                  items: List.generate(
                    aylar.length,
                        (i) => DropdownMenuItem(
                      value: i,
                      child: Text(aylar[i]),
                    ),
                  ),
                  onChanged: (v) {
                    if (v == null) return;
                    setDialogState(() => secilenAyIndex = v);
                  },
                ),

                const SizedBox(height: 10),
              ],

              /// 💰 TUTAR
              TextField(
                controller: tC,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: "Tutar",
                  hintText: "0,00 ₺",
                  border: const OutlineInputBorder(),
                ),
              ),

              const SizedBox(height: 10),

              /// 📝 AÇIKLAMA
              TextField(
                controller: aC,
                decoration: InputDecoration(
                  labelText: "Açıklama",
                  hintText: tur == "MAAŞ TAHAKKUK"
                      ? "${aylar[secilenAyIndex]} MAAŞI"
                      : "Banka, Elden...",
                  border: const OutlineInputBorder(),
                ),
              ),
            ],
          ),

          actions: [

            /// ❌ İPTAL
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text("İPTAL"),
            ),

            /// ✅ KAYDET
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor:
                tur == "MAAŞ TAHAKKUK" ? Colors.green : Colors.red,
              ),
              onPressed: () async {
                double tutar = double.tryParse(tC.text) ?? 0;
                if (tutar <= 0) return;

                double netDegisim =
                (tur == "MAAŞ TAHAKKUK") ? tutar : -tutar;

                await DatabaseHelper.instance.personelHareketEkle({
                  'id': const Uuid().v4(),
                  'personel_id': p['id'].toString(),
                  'tarih': DateTime.now().toIso8601String(),
                  'tur': tur,
                  'tutar': netDegisim,
                  'not_aciklama': aC.text.isEmpty
                      ? (tur == "MAAŞ TAHAKKUK"
                      ? "${aylar[secilenAyIndex]} MAAŞI"
                      : "ÖDEME")
                      : aC.text.toUpperCase(),
                  'is_synced': 0,
                });

                Navigator.pop(c);
                await _verileriYukle();
              },
              child: const Text(
                "KAYDET",
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _kucukButon(String l, IconData i, Color c, VoidCallback t) => InkWell(
    onTap: t,
    child: Container(
      width: 75,
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(color: c.withOpacity(0.1), borderRadius: BorderRadius.circular(10), border: Border.all(color: c.withOpacity(0.3))),
      child: Column(children: [Icon(i, size: 18, color: c), const SizedBox(height: 4), Text(l, style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: c))]),
    ),
  );

  void _personelFormu({Map<String, dynamic>? personel}) {
    final adC = TextEditingController(text: personel?['ad']);
    final maasC = TextEditingController(text: personel?['maas']?.toString() ?? "");

    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(personel == null ? "YENİ PERSONEL" : "BİLGİLERİ DÜZENLE"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: adC, decoration: const InputDecoration(labelText: "Ad Soyad", border: OutlineInputBorder())),
            const SizedBox(height: 10),
            TextField(controller: maasC, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: "Net Maaş", border: OutlineInputBorder())),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text("İPTAL")),
          ElevatedButton(
            onPressed: () async {
              final v = {
                'ad': adC.text.toUpperCase(),
                'maas': double.tryParse(maasC.text) ?? 0,
                'is_synced': 0
              };
              if (personel == null) {
                v['id'] = const Uuid().v4();
                v['bakiye'] = 0.0;
                await DatabaseHelper.instance.personelEkle(v);
              } else {
                await DatabaseHelper.instance.personelGuncelle(personel['id'], v);
              }
              Navigator.pop(c);
              await _verileriYukle();
            },
            child: const Text("KAYDET"),
          )
        ],
      ),
    );
  }

  void _silOnay(Map<String, dynamic> p) {
    showDialog(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text("SİLME ONAYI"),
          content: Text("${p['ad']} personeli tamamen silinecek. Emin misiniz?"),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: const Text("HAYIR")),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () async {
                // p['id']'nin String olduğundan emin oluyoruz
                final String personelId = p['id'].toString();

                await DatabaseHelper.instance.personelSil(personelId);

                if (mounted) {
                  Navigator.pop(context); // 'c' yerine context kullanmak daha güvenlidir
                  _verileriYukle();
                }
              },
              child: const Text("SİL", style: TextStyle(color: Colors.white)),
            ),
          ],
        )
    );
  }

  void _fotoEkle(Map<String, dynamic> p) async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.camera);
    if (image != null) {
      await DatabaseHelper.instance.personelGuncelle(p['id'], {'foto_yolu': image.path});
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Fotoğraf güncellendi")));
      await _verileriYukle();
    }
  }

  void _ekstreGoster(Map<String, dynamic> p) async {
    try {
      final hareketler = await DatabaseHelper.instance.personelHareketleriGetir(
        p['id'].toString(),
      );

      double toplamMaas = 0;
      double toplamOdeme = 0;

      for (var h in hareketler) {
        double tutar = safeDouble(h['tutar']);
        String tur = (h['tur'] ?? "").toString().toUpperCase();
        if (tur.contains("MAAŞ")) {
          toplamMaas += tutar.abs();
        } else {
          toplamOdeme += tutar.abs();
        }
      }

      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (context) => Container(
          height: MediaQuery.of(context).size.height * 0.85,
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
          ),
          child: Column(
            children: [
              // Üst Tutamaç Çizgisi
              Container(
                margin: const EdgeInsets.only(top: 10, bottom: 20),
                width: 40, height: 5,
                decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(10)),
              ),

              // Başlık Alanı
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(p['ad'].toString().toUpperCase(), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                          const Text("Personel Hesap Özeti", style: TextStyle(color: Colors.grey, fontSize: 13)),
                        ],
                      ),
                    ),
                    IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close, color: Colors.red)),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // Özet Kartları (Maaş ve Ödeme)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 15),
                child: Row(
                  children: [
                    _ozetKart("TOPLAM MAAŞ", toplamMaas, Colors.blue.shade900),
                    const SizedBox(width: 10),
                    _ozetKart("TOPLAM ÖDEME", toplamOdeme, Colors.orange.shade800),
                  ],
                ),
              ),

              const Padding(
                padding: EdgeInsets.all(15.0),
                child: Divider(thickness: 1),
              ),

              // Hareket Listesi
              Expanded(
                child: hareketler.isEmpty
                    ? const Center(child: Text("Henüz hareket kaydı bulunamadı."))
                    : ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 15),
                  itemCount: hareketler.length,
                  separatorBuilder: (context, i) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final h = hareketler[i];
                    double tutar = safeDouble(h['tutar']);
                    bool isMaas = h['tur'].toString().toUpperCase().contains("MAAŞ");

                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      leading: CircleAvatar(
                        backgroundColor: isMaas ? Colors.green.withOpacity(0.1) : Colors.red.withOpacity(0.1),
                        child: Icon(isMaas ? Icons.arrow_upward : Icons.arrow_downward,
                            color: isMaas ? Colors.green : Colors.red, size: 20),
                      ),
                      title: Text(h['tur'].toString(), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(h['not_aciklama'] ?? "Açıklama yok", style: const TextStyle(fontSize: 12)),
                          Text(h['tarih']?.toString().substring(0, 10) ?? "", style: const TextStyle(fontSize: 10, color: Colors.grey)),
                        ],
                      ),
                      trailing: Text(
                        formatPara(tutar),
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: tutar >= 0 ? Colors.green.shade700 : Colors.red.shade700,
                        ),
                      ),
                    );
                  },
                ),
              ),

              // Alt Bilgi (Bakiye)
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    border: Border(top: BorderSide(color: Colors.grey.shade300))
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text("GÜNCEL BAKİYE:", style: TextStyle(fontWeight: FontWeight.bold)),
                    Text(formatPara(safeDouble(p['bakiye'])),
                        style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: safeDouble(p['bakiye']) >= 0 ? Colors.green.shade800 : Colors.red.shade800
                        )
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    } catch (e) {
      debugPrint("EKSTRE HATA: $e");
    }
  }

// Yardımcı Özet Kartı Widget'ı
  Widget _ozetKart(String baslik, double deger, Color renk) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: renk.withOpacity(0.05),
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: renk.withOpacity(0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(baslik, style: TextStyle(color: renk, fontSize: 10, fontWeight: FontWeight.bold)),
            const SizedBox(height: 5),
            FittedBox(
              child: Text(formatPara(deger),
                  style: TextStyle(color: renk, fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pdfRaporYap() async {
    try {
      final pdf = pw.Document();
      final personeller = await DatabaseHelper.instance.personelListesiGetir();
      final font = await PdfGoogleFonts.robotoRegular();
      final boldFont = await PdfGoogleFonts.robotoBold();

      String f(dynamic d) => NumberFormat.currency(
        locale: 'tr_TR', symbol: '₺', decimalDigits: 2,
      ).format(double.tryParse(d.toString()) ?? 0);

      final ByteData bytes = await rootBundle.load('assets/images/logo.png');
      final logo = pw.MemoryImage(bytes.buffer.asUint8List());

      // 🔥 TÜM VERİYİ ÖNCEDEN HAZIRLA (PDF içinde await kullanamayacağımız için)
      // Her personelin ID'sine karşılık hareket listesini tutacak bir yapı
      Map<String, List<List<String>>> tumEkstreler = {};

      for (var p in personeller) {
        final hareketler = await DatabaseHelper.instance.personelHareketleriGetir(
          p['id'].toString(),
        );

        List<List<String>> personelTabloData = [];
        // Tablo başlıkları
        personelTabloData.add(["TARİH", "İŞLEM", "AÇIKLAMA", "TUTAR"]);

        if (hareketler.isEmpty) {
          personelTabloData.add(["-", "-", "HAREKET YOK", "0.00"]);
        } else {
          for (var h in hareketler) {
            double tutar = double.tryParse(h['tutar'].toString()) ?? 0;
            String tarih = h['tarih'] != null ? h['tarih'].toString().substring(0, 10) : "-";

            personelTabloData.add([
              tarih,
              h['tur'].toString().toUpperCase(),
              h['not_aciklama']?.toString() ?? "",
              f(tutar),
            ]);
          }
        }
        tumEkstreler[p['id'].toString()] = personelTabloData;
      }

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(25),
          header: (context) => pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Row(children: [
                pw.Container(width: 40, height: 40, child: pw.Image(logo)),
                pw.SizedBox(width: 10),
                pw.Text("EVREN TARIM - DETAYLI PERSONEL EKSTRESİ",
                    style: pw.TextStyle(font: boldFont, fontSize: 14)),
              ]),
              pw.Text(DateFormat('dd.MM.yyyy').format(DateTime.now()),
                  style: pw.TextStyle(font: font, fontSize: 10)),
            ],
          ),
          build: (context) {
            List<pw.Widget> widgets = [];

            for (var p in personeller) {
              String pId = p['id'].toString();

              widgets.add(pw.SizedBox(height: 15));

              // Personel Bilgi Şeridi
              widgets.add(
                pw.Container(
                  padding: const pw.EdgeInsets.all(6),
                  decoration: const pw.BoxDecoration(
                      color: PdfColors.grey200,
                      border: pw.Border(left: pw.BorderSide(color: PdfColors.blue900, width: 3))
                  ),
                  child: pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text("PERSONEL: ${p['ad'].toString().toUpperCase()}",
                          style: pw.TextStyle(font: boldFont, fontSize: 10)),
                      pw.Text("GÜNCEL BAKİYE: ${f(p['bakiye'])}",
                          style: pw.TextStyle(font: boldFont, fontSize: 10)),
                    ],
                  ),
                ),
              );

              // Hazırladığımız Tabloyu Basıyoruz
              widgets.add(
                pw.TableHelper.fromTextArray(
                  data: tumEkstreler[pId]!,
                  cellStyle: pw.TextStyle(font: font, fontSize: 8),
                  headerStyle: pw.TextStyle(font: boldFont, fontSize: 8, color: PdfColors.white),
                  headerDecoration: const pw.BoxDecoration(color: PdfColors.blueGrey800),
                  columnWidths: {
                    0: const pw.FixedColumnWidth(60),
                    1: const pw.FixedColumnWidth(80),
                    2: const pw.FlexColumnWidth(),
                    3: const pw.FixedColumnWidth(70),
                  },
                  cellAlignments: {
                    3: pw.Alignment.centerRight,
                  },
                ),
              );
            }
            return widgets;
          },
        ),
      );

      // PDF Önizleme
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => Scaffold(
            appBar: AppBar(title: const Text("PERSONEL EKSTRE RAPORU")),
            body: PdfPreview(build: (format) => pdf.save()),
          ),
        ),
      );
    } catch (e) {
      debugPrint("PDF HATA: $e");
    }
  }
}