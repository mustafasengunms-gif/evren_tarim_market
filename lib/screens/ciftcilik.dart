import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../db/database_helper.dart';
import 'package:printing/printing.dart';
import 'package:cloud_firestore/cloud_firestore.dart'; // <--- BURASI DÜZELDİ
import 'gider_detay_sayfasi.dart';
import 'package:evren_tarim_market/db/database_helper.dart';
import 'package:intl/intl.dart';
import 'package:flutter/foundation.dart' show kIsWeb; //
import 'dart:io' as io; // File hatasını engellemek için 'as io' dedik[cite: 1]
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'dart:io' show File;

class CiftcilikPaneli extends StatefulWidget {
  const CiftcilikPaneli({super.key});

  @override
  State<CiftcilikPaneli> createState() => _CiftcilikPaneliState();
}

class _CiftcilikPaneliState extends State<CiftcilikPaneli> {
  // --- ANA HESAPLAMA DEĞİŞKENLERİ (STANDARTLAŞTIRILDI) ---
  double _toplamGider = 0;   // Ekranda "Toplam Harcama" labeline bağla
  double _toplamGelir = 0;   // Ekranda "Toplam Gelir" labeline bağla
  double _toplamAlan = 0;    // Ekranda "Toplam Alan" labeline bağla
  int _islemSayisi = 0;      // Kaç adet işlem yapıldı bilgisi
  double _toplamMasraf = 0;
  // --- LİSTELER VE AYARLAR ---
  List<Map<String, dynamic>> _tarlalar = [];
  List<String> _sezonlar = ["2026", "2027", "2028", "2029","2030","2031","2032","2033","2034","2035","2036","2037","YETİVERSİN"];
  List<String> _urunler = ["BUĞDAY", "ARPA", "PANCAR", "MISIR", "YONCA", "AYÇİÇEĞİ", "BOŞ"];
  String _seciliSezon = "2026";

  final Color toprakRengi = Colors.brown[800]!;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // --- YARDIMCI ARAÇLAR ---

  // Metinleri temizler (Boşlukları siler, null kontrolü yapar)
  String normalize(dynamic v) => (v ?? "").toString().trim();

  // Veriyi her türlü sayıya (double) güvenli çevirir, patlamayı önler
  double toDoubleSafe(dynamic v) {
    if (v == null) return 0.0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString().replaceAll(',', '.')) ?? 0.0;
  }

  // Firebase'den gelen veriyi ID'si ile birlikte listeye çevirir
  List<Map<String, dynamic>> fbToList(QuerySnapshot snap) {
    return snap.docs.map((d) {
      final data = d.data() as Map<String, dynamic>;
      return {
        "id": d.id, // Kaydı silerken veya güncellerken lazım olan doküman ID
        "tarlaId": normalize(data['tarlaId']),
        "sezon": normalize(data['sezon']),
        // Firebase'de hangi isimle kayıtlıysa hepsini kontrol eder
        "toplam": toDoubleSafe(data['toplam'] ?? data['tutar'] ?? data['birimFiyat'] ?? 0),
        "miktar": toDoubleSafe(data['miktar']),
        "islem": normalize(data['islem'] ?? data['aciklama'] ?? "GİDER"),
        "tarih": normalize(data['tarih']),
      };
    }).toList();
  }










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
    _verileriYukle();
  }

  Future<void> _verileriYukle() async {
    try {
      debugPrint("🔄 Veriler yükleniyor...");

      final tarlalar = await DatabaseHelper.instance.tarlaListesiGetir();
      final yerelHareketler =
      await DatabaseHelper.instance.tumTarlaHareketleriniGetir();
      final db = await DatabaseHelper.instance.database;

      final yerelHasatlar =
      await DatabaseHelper.instance.tumHasatlariGetir();

      final fbHasatSnap = await FirebaseFirestore.instance
          .collection('tarla_hasatlari')
          .get();

      // ✅ SADECE firebase_id üzerinden kontrol
      Set<String> yerelFirebaseIds = yerelHasatlar
          .map((h) => h['firebase_id']?.toString() ?? "")
          .where((e) => e.isNotEmpty)
          .toSet();

      for (var doc in fbHasatSnap.docs) {
        String fId = doc.id;

        // ❗ Eğer zaten varsa ASLA ekleme
        if (yerelFirebaseIds.contains(fId)) continue;

        Map<String, dynamic> veri = doc.data();

        veri['firebase_id'] = fId;
        veri['is_synced'] = 1;

        // SQLite id çakışmasın
        veri.remove('id');

        await db.insert('tarla_hasatlari', veri);

        debugPrint("📥 Yeni kayıt eklendi: $fId");
      }

      final guncelHasatListesi =
      await DatabaseHelper.instance.tumHasatlariGetir();

      double hesaplananGider = 0;
      double hesaplananGelir = 0;
      double hesaplananAlan = 0;
      int gercekIslemSayisi = 0;

      final seciliSezonNorm = _seciliSezon.toString().trim();

      final sezonlukTarlalar = tarlalar.where((t) {
        return t['sezon'].toString().trim() == seciliSezonNorm;
      }).toList();

      for (var t in sezonlukTarlalar) {
        final tId = t['id'].toString().trim();

        hesaplananAlan += toDoubleSafe(t['dekar']);

        if (t['is_icar'] == 1) {
          hesaplananGider += toDoubleSafe(t['kira_tutari']);
        }

        final tGiderleri = yerelHareketler.where((m) =>
        m['tarla_id'].toString() == tId &&
            m['sezon'].toString() == seciliSezonNorm);

        for (var m in tGiderleri) {
          hesaplananGider += toDoubleSafe(m['tutar']);
          gercekIslemSayisi++;
        }

        final tHasatlari = guncelHasatListesi.where((h) =>
        h['tarla_id'].toString().trim() == tId &&
            h['sezon'].toString().trim() == seciliSezonNorm);

        for (var h in tHasatlari) {
          hesaplananGelir += toDoubleSafe(h['toplam_gelir']);
        }
      }

      if (mounted) {
        setState(() {
          _tarlalar = sezonlukTarlalar;
          _toplamAlan = hesaplananAlan;
          _toplamGider = hesaplananGider;
          _toplamMasraf = hesaplananGider;
          _toplamGelir = hesaplananGelir;
          _islemSayisi = gercekIslemSayisi;
        });
      }
    } catch (e) {
      debugPrint("❌ HATA: $e");
    }
  }


  Future<void> _pdfRaporOlusturVePaylas() async {
    try {
      final pdf = pw.Document();

      // 1. FONT YÜKLEME (Arial her zaman en sağlamıdır)
      final fontData = await rootBundle.load("assets/fonts/arial.ttf");
      final ttf = pw.Font.ttf(fontData);

      // 2. RENKLER
      const toprakRengi = PdfColor.fromInt(0xFF5D4037);
      const bereketYesili = PdfColor.fromInt(0xFF2E7D32);

      // 3. VERİLERİ TOPLA (BURASI KRİTİK!)
      final yerelHareketler = await DatabaseHelper.instance.tumTarlaHareketleriniGetir();
      final hasatlar = await DatabaseHelper.instance.tumHasatlariGetir();

      // Firebase verilerini de çekiyoruz
      final fbSnap = await FirebaseFirestore.instance
          .collection('tarla_hareketleri')
          .where('sezon', isEqualTo: _seciliSezon.trim())
          .get();

      List<List<String>> giderTabloVerisi = [];

      // SQL Giderleri ekle
      for (var h in yerelHareketler) {
        if (h['sezon'].toString().trim() == _seciliSezon.trim()) {
          giderTabloVerisi.add([
            h['tarih']?.toString().split('T')[0] ?? "-",
            (h['islem_adi'] ?? h['islem_tipi'] ?? "GIDER").toString().toUpperCase(),
            _tarlaAdiniBul(h['tarla_id']),
            "${pdfFormat(h['tutar'])} TL"
          ]);
        }
      }

      // Firebase Giderleri ekle (Artık bunlar da PDF'de!)
      for (var doc in fbSnap.docs) {
        var d = doc.data();
        giderTabloVerisi.add([
          d['tarih']?.toString().split('T')[0] ?? "-",
          (d['islem'] ?? d['aciklama'] ?? "BULUT GIDERI").toString().toUpperCase(),
          _tarlaAdiniBul(d['tarlaId']),
          "${pdfFormat(d['toplam'] ?? d['tutar'] ?? 0)} TL"
        ]);
      }

      // Hasat verilerini hazırla
      final sHasatlar = hasatlar.where((h) => h['sezon'].toString() == _seciliSezon).toList();

      pdf.addPage(pw.MultiPage(
        theme: pw.ThemeData.withFont(base: ttf, bold: ttf),
        build: (context) => [
          // BAŞLIK
          pw.Header(
            level: 0,
            child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text("EVREN TARIM $_seciliSezon RAPORU",
                      style: pw.TextStyle(color: toprakRengi, fontWeight: pw.FontWeight.bold, fontSize: 18)),
                  pw.Text(DateFormat('dd.MM.yyyy').format(DateTime.now())),
                ]
            ),
          ),

          pw.SizedBox(height: 15),

          // ÖZET KUTUSU
          pw.Container(
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: toprakRengi, width: 2),
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(10)),
              color: PdfColors.grey50,
            ),
            child: pw.Column(children: [
              pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
                pw.Text("TOPLAM GIDER:"),
                pw.Text("${pdfFormat(_toplamMasraf)} TL", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: PdfColors.red)),
              ]),
              pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
                pw.Text("TOPLAM GELIR:"),
                pw.Text("${pdfFormat(_toplamGelir)} TL", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: bereketYesili)),
              ]),
              pw.Divider(color: PdfColors.grey400),
              pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
                pw.Text("NET DURUM:", style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                pw.Text("${pdfFormat(_toplamGelir - _toplamMasraf)} TL",
                    style: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: (_toplamGelir - _toplamMasraf) >= 0 ? PdfColors.blue : PdfColors.red)),
              ]),
            ]),
          ),

          pw.SizedBox(height: 25),

          // GİDER TABLOSU
          pw.Text("1. GIDER DETAYLARI", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: toprakRengi)),
          pw.SizedBox(height: 8),
          pw.TableHelper.fromTextArray(
            headers: ['Tarih', 'Islem', 'Tarla', 'Tutar'],
            headerDecoration: const pw.BoxDecoration(color: toprakRengi),
            headerStyle: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold),
            data: giderTabloVerisi,
          ),

          pw.SizedBox(height: 25),

          // HASAT TABLOSU
          pw.Text("2. GELIR (HASAT) DETAYLARI", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: bereketYesili)),
          pw.SizedBox(height: 8),
          pw.TableHelper.fromTextArray(
            headers: ['Urun', 'Musteri', 'Miktar', 'Gelir'],
            headerDecoration: const pw.BoxDecoration(color: bereketYesili),
            headerStyle: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold),
            data: sHasatlar.map((h) => [
              h['ekilen_urun']?.toString().toUpperCase() ?? "",
              h['satilan_kisi']?.toString().toUpperCase() ?? "",
              "${h['toplam_kg']} KG",
              "${pdfFormat(h['toplam_gelir'])} TL"
            ]).toList(),
          ),
        ],
      ));

      // KAYDET VE PAYLAŞ
      final dir = await getTemporaryDirectory();
      final file = File("${dir.path}/Evren_Tarim_Rapor_${_seciliSezon}.pdf");
      await file.writeAsBytes(await pdf.save());
      await Share.shareXFiles([XFile(file.path)], text: 'Evren Tarım Raporu');

    } catch (e) {
      debugPrint("PDF Hatası: $e");
    }
  }
  // Bunu _CiftcilikPaneliState sınıfının içinde, herhangi bir fonksiyonun dışına koy:
  String pdfFormat(dynamic deger) {
    try {
      double rakam = double.tryParse(deger.toString()) ?? 0;
      String sonuc = rakam.toStringAsFixed(2).replaceAll('.', ',');
      RegExp reg = RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))');
      return sonuc.replaceAllMapped(reg, (Match m) => '${m[1]}.');
    } catch (e) {
      return "0,00";
    }
  }

  Widget _islemKarti(String baslik, IconData ikon, Color renk) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: () {
          if (baslik == "HASAT GİRİŞ") {
            // Önce listeyi gör ki ne girdiğini bilesin,
            // listenin içindeki "+" butonuna basınca form açılacak.
            _hasatListesiModal();
          }
          else if (baslik.contains("GÜBRE") || baslik.contains("MAZOT") ||
              baslik.contains("İLAÇ") || baslik.contains("SULAMA")) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => GiderDetaySayfasi(islemTipi: baslik),
              ),
            ).then((_) => _verileriYukle());
          }
          else if (baslik == "ANALİZ") {
            _analizGoster();
          }
          else if (baslik == "GİDERLER") {
            _tumGiderleriGoster();
          }
        },
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(ikon, size: 32, color: renk),
            const SizedBox(height: 8),
            Text(baslik,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }



  void _ekimYonetimiDiyalog() async {
    int? seciliTarlaId;
    final tarihC = TextEditingController(text: DateTime.now().toString().split(' ')[0]);
    final islemAdiC = TextEditingController();
    final miktarC = TextEditingController(text: "1");
    final birimFiyatC = TextEditingController(text: "0");
    final toplamC = TextEditingController(text: "0");
    String seciliIslemTipi = "SÜRÜM";

    List<Map<String, dynamic>> tarlaGecmisi = [];

    // Birim fiyat veya miktar değiştiğinde toplamı otomatik hesapla
    void hesapla(StateSetter setDialogState) {
      double m = double.tryParse(miktarC.text.replaceAll(',', '.')) ?? 0;
      double b = double.tryParse(birimFiyatC.text.replaceAll(',', '.')) ?? 0;
      setDialogState(() {
        toplamC.text = (m * b).toStringAsFixed(2);
      });
    }

    showDialog(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.orange[800], // Turuncu Panel
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: const Text(
              "TARLA HAREKETİ VE GİDER EKLE",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ),
          titlePadding: EdgeInsets.zero,
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 15),
                  // 1. TARLA SEÇİMİ
                // _ekimYonetimiDiyalog içindeki Dropdown'u böyle güncelle:
                DropdownButtonFormField<int>(
                  // EĞER seciliTarlaId o anki listede yoksa null yap ki uygulama çökmesin
                  value: _tarlalar.any((t) => t['id'] == seciliTarlaId) ? seciliTarlaId : null,
                  isExpanded: true,
                  decoration: const InputDecoration(
                      labelText: "İŞLEM YAPILACAK TARLA",
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.map, color: Colors.orange)
                  ),
                  items: _tarlalar.map((t) => DropdownMenuItem<int>(
                      value: t['id'],
                      child: Text("${t['mevki']} (${t['ekilen_urun']})", style: const TextStyle(fontSize: 12))
                  )).toList(),
                  onChanged: (v) async {
                      final hareketler = await DatabaseHelper.instance.tumTarlaHareketleriniGetir();
                      setDialogState(() {
                        seciliTarlaId = v;
                        tarlaGecmisi = hareketler.where((h) => h['tarla_id'] == v && h['sezon'].toString() == _seciliSezon).toList();
                      });
                    },
                  ),
                  const SizedBox(height: 12),

                  // 2. İŞLEM TİPİ (Resimdeki 'islem' kolonu)
                  DropdownButtonFormField<String>(
                    value: seciliIslemTipi,
                    decoration: const InputDecoration(labelText: "İŞLEM TİPİ", border: OutlineInputBorder(), prefixIcon: Icon(Icons.settings, color: Colors.orange)),
                    items: const [
                      DropdownMenuItem(value: "SÜRÜM", child: Text("TARLA SÜRÜMÜ")),
                      DropdownMenuItem(value: "EKİM", child: Text("MİZER / EKİM")),
                      DropdownMenuItem(value: "İLAÇLAMA", child: Text("İLAÇ ATMA")),
                      DropdownMenuItem(value: "GÜBRELEME", child: Text("GÜBRE ATMA")),
                      DropdownMenuItem(value: "SULAMA", child: Text("SULAMA")),
                      DropdownMenuItem(value: "DİĞER", child: Text("DİĞER")),
                    ],
                    onChanged: (v) => setDialogState(() => seciliIslemTipi = v!),
                  ),
                  const SizedBox(height: 12),

                  // 3. MİKTAR VE BİRİM FİYAT (Yan Yana)
                  Row(
                    children: [
                      Expanded(
                        child: _input(
                          miktarC,
                          "MİKTAR",
                          Icons.production_quantity_limits,
                          tip: TextInputType.number,
                          onChanged: (_) => hesapla(setDialogState), // İsim onChanged olmalı
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _input(
                          birimFiyatC, // Burası miktar değil, birimFiyatC olacak!
                          "B.FİYAT",
                          Icons.sell,
                          tip: TextInputType.number,
                          onChanged: (_) => hesapla(setDialogState), // İsim onChanged olmalı
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // 4. TOPLAM TUTAR VE TARİH
                  _input(toplamC, "TOPLAM TUTAR (TL)", Icons.payments, tip: TextInputType.number, color: Colors.red[900]),
                  _input(tarihC, "İŞLEM TARİHİ", Icons.calendar_today),
                  _input(islemAdiC, "AÇIKLAMA (Özel Not)", Icons.edit),

                  const Divider(thickness: 2, color: Colors.orange),
                  const Text("TARLA GEÇMİŞİ", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.orange)),

                  ...tarlaGecmisi.take(3).map((h) => ListTile(
                    dense: true,
                    title: Text("${h['islem_tipi']}"),
                    subtitle: Text("${h['tarih']}"),
                    trailing: Text("${formatPara(h['tutar'])} TL", style: const TextStyle(fontWeight: FontWeight.bold)),
                  )),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: const Text("İPTAL", style: TextStyle(color: Colors.grey))),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.orange[800], foregroundColor: Colors.white),
              onPressed: () async {
                if (seciliTarlaId != null) {
                  // RESİMDEKİ SÜTUN ADLARIYLA BİREBİR EŞLEŞTİRME
                  Map<String, dynamic> veri = {
                    'tarla_id': seciliTarlaId,
                    'tarlaId': seciliTarlaId.toString(), // Bazı yerlerde String beklediği için
                    'islem_tipi': seciliIslemTipi,
                    'islem': seciliIslemTipi, // Resimdeki kolon
                    'miktar': double.tryParse(miktarC.text) ?? 0,
                    'birimFiyat': double.tryParse(birimFiyatC.text) ?? 0,
                    'toplam': double.tryParse(toplamC.text) ?? 0,
                    'tutar': double.tryParse(toplamC.text) ?? 0, // SQL tablon tutar diyorsa diye
                    'aciklama': islemAdiC.text.toUpperCase(),
                    'tarih': tarihC.text,
                    'sezon': _seciliSezon,
                    'is_synced': 0,
                  };

                  try {
                    await DatabaseHelper.instance.tarlaHareketiEkle(veri);
                    if (mounted) {
                      Navigator.pop(c);
                      _verileriYukle();
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Kayıt Başarılı"), backgroundColor: Colors.orange));
                    }
                  } catch (e) {
                    debugPrint("Hata: $e");
                  }
                }
              },
              child: const Text("KAYDET"),
            ),
          ],
        ),
      ),
    );
  }

  Widget _input(TextEditingController c, String l, IconData i,
      {TextInputType tip = TextInputType.text, Color? color, Function(String)? onChanged}) { // <--- Burayı onChanged yaptık
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: TextField(
        controller: c,
        keyboardType: tip,
        onChanged: onChanged, // <--- Burası da onChanged oldu
        style: TextStyle(
            color: color ?? Colors.black,
            fontWeight: color != null ? FontWeight.bold : FontWeight.normal
        ),
        decoration: InputDecoration(
          labelText: l,
          prefixIcon: Icon(i, size: 20, color: Colors.orange),
          border: const OutlineInputBorder(),
          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        ),
      ),
    );
  }

  void _analizGoster() async {
    // 1. Önce her yerden verileri toplayan listeyi hazırlayalım (tam liste oluşturma mantığı)
    final hareketler = await DatabaseHelper.instance.tumTarlaHareketleriniGetir();
    final tarlaVerileri = await DatabaseHelper.instance.tarlaListesiGetir();
    final hasatlar = await DatabaseHelper.instance.tumHasatlariGetir();

    final fbSnapshot = await FirebaseFirestore.instance
        .collection('tarla_hareketleri')
        .where('sezon', isEqualTo: _seciliSezon.trim())
        .get();

    List<Map<String, dynamic>> analizListesi = [];

    // SQL Giderleri ekle
    for (var h in hareketler) {
      if (h['sezon'].toString().trim() == _seciliSezon.trim()) {
        analizListesi.add({'tip': h['islem_tipi'], 'tutar': (h['tutar'] ?? 0).toDouble(), 'ad': h['islem_adi']});
      }
    }

    // Firebase Giderleri ekle
    // Firebase Giderleri ekle
    for (var doc in fbSnapshot.docs) {
      var d = doc.data();

      // Değişken ismini 'gercekTip' olarak düzelttik, Türkçe karakterden arındırdık.
      String gercekTip = (d['islem'] ?? d['islem_tipi'] ?? "DIGER").toString().toUpperCase();

      analizListesi.add({
        'tip': gercekTip,
        'tutar': toDoubleSafe(d['toplam'] ?? d['tutar'] ?? d['birimFiyat']),
        'ad': d['aciklama'] ?? d['islem'] ?? "Bulut Kaydi"
      });
    }

    // İcarıları ekle
    for (var t in tarlaVerileri) {
      if (t['sezon'].toString().trim() == _seciliSezon.trim() && (t['kira_tutari'] ?? 0) > 0) {
        analizListesi.add({'tip': "İCAR", 'tutar': (t['kira_tutari'] ?? 0).toDouble(), 'ad': "${t['mevki']} Kirası"});
      }
    }

    // --- ŞİMDİ HESAPLA ---
    Map<String, double> tipBazliGider = {};
    double enYuksekGider = 0;
    String enMasrafliIslem = "-";

    for (var kalem in analizListesi) {
      String tip = kalem['tip'] ?? "DİĞER";
      double tutar = kalem['tutar'];

      tipBazliGider[tip] = (tipBazliGider[tip] ?? 0) + tutar;

      // 🔥 İŞTE BURASI: En yüksek masrafı burada buluyoruz
      if (tutar > enYuksekGider) {
        enYuksekGider = tutar;
        enMasrafliIslem = "${kalem['ad']} ($tip)";
      }
    }

    // Gelir Hesaplama (Hasat)
    Map<String, double> urunBazliGelir = {};
    final sezonlukHasatlar = hasatlar.where((h) => h['sezon'] == _seciliSezon).toList();
    for (var h in sezonlukHasatlar) {
      String urun = h['ekilen_urun'] ?? "BELİRSİZ";
      urunBazliGelir[urun] = (urunBazliGelir[urun] ?? 0) + (h['toplam_gelir'] ?? 0);
    }

    // MODAL GÖSTERİMİ (Senin mevcut modal kodun buraya gelecek)
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
      builder: (c) => Container(
        padding: const EdgeInsets.all(20),
        height: MediaQuery.of(context).size.height * 0.85,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(child: Container(width: 50, height: 5, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(10)))),
            const SizedBox(height: 15),
            const Text("📊 SEZONLUK ANALİZ RAPORU", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const Divider(),
            Row(
              children: [
                _ozetKutu("TOPLAM GİDER", formatPara(_toplamMasraf), Colors.red),
                _ozetKutu("TOPLAM GELİR", formatPara(_toplamGelir), Colors.green),
              ],
            ),
            const SizedBox(height: 10),
            // ✅ BURASI ARTIK DOLU GELECEK
            _genisOzetKutu("EN BÜYÜK TEKİL MASRAF", "$enMasrafliIslem: ${formatPara(enYuksekGider)} TL", Colors.orange),
            const SizedBox(height: 20),
            Expanded(
              child: ListView(
                children: [
                  ...tipBazliGider.entries.map((e) {
                    double oran = _toplamMasraf > 0 ? (e.value / _toplamMasraf) * 100 : 0;
                    return _analizSatiri(e.key, e.value, oran, _renkGetir(e.key), _ikonGetir(e.key));
                  }),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _analizSatiri(String baslik, double tutar, double oran, Color renk, IconData ikon) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: 4),
      shape: RoundedRectangleBorder(side: BorderSide(color: Colors.grey[200]!), borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            CircleAvatar(backgroundColor: renk.withOpacity(0.1), child: Icon(ikon, color: renk, size: 20)),
            const SizedBox(width: 15),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(baslik, style: const TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  LinearProgressIndicator(value: oran / 100, backgroundColor: Colors.grey[200], color: renk, minHeight: 6),
                ],
              ),
            ),
            const SizedBox(width: 15),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text("${formatPara(tutar)} TL", style: const TextStyle(fontWeight: FontWeight.bold)),
                Text("%${oran.toStringAsFixed(1)}", style: const TextStyle(fontSize: 10, color: Colors.grey)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _ozetKutu(String b, String d, Color r) => Expanded(
    child: Container(
      margin: const EdgeInsets.all(4),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(color: r.withOpacity(0.05), borderRadius: BorderRadius.circular(15), border: Border.all(color: r.withOpacity(0.2))),
      child: Column(children: [Text(b, style: TextStyle(fontSize: 10, color: r, fontWeight: FontWeight.bold)), const SizedBox(height: 5), Text(d, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13))]),
    ),
  );

  Widget _genisOzetKutu(String b, String d, Color r) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(15),
    decoration: BoxDecoration(color: r.withAlpha(20), borderRadius: BorderRadius.circular(15)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(b, style: TextStyle(fontSize: 10, color: r, fontWeight: FontWeight.bold)), const SizedBox(height: 5), Text(d, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12))]),
  );


  void _tumGiderleriGoster() async {
    try { // Hata olursa yakalamak için try-catch şart
      final hareketler = await DatabaseHelper.instance.tumTarlaHareketleriniGetir();
      final tarlaVerileri = await DatabaseHelper.instance.tarlaListesiGetir();

      final fbSnapshot = await FirebaseFirestore.instance
          .collection('tarla_hareketleri')
          .where('sezon', isEqualTo: _seciliSezon.trim())
          .get();

      List<Map<String, dynamic>> tamListe = [];

      // 1. SQL GİDERLERİ
      for (var h in hareketler) {
        if (h['sezon'].toString().trim() == _seciliSezon.trim()) {
          tamListe.add({
            'baslik': h['islem_adi'] ?? h['islem_tipi'] ?? "GİDER",
            'alt_baslik': "${h['islem_tipi']} | ${_tarlaAdiniBul(h['tarla_id'])}",
            'tarih': h['tarih'] ?? "-",
            'tutar': (h['tutar'] ?? 0).toDouble(),
            'tip': h['islem_tipi'],
            'kaynak': 'SQL',
            'f_id': h['firebase_id']
          });
        }
      }

      // 2. FIREBASE GİDERLERİ
      for (var doc in fbSnapshot.docs) {
        var d = doc.data();
        bool zatenVar = tamListe.any((element) => element['f_id'] == doc.id);
        if (zatenVar) continue;

        String baslik = (d['islem'] ?? d['İslam'] ?? d['islim'] ?? d['aciklama'] ?? "BULUT GİDERİ").toString().toUpperCase();

        tamListe.add({
          'baslik': baslik,
          'alt_baslik': "BULUT | ${_tarlaAdiniBul(d['tarlaId'])}",
          'tarih': d['tarih']?.toString().split('T')[0] ?? "-",
          'tutar': toDoubleSafe(d['toplam'] ?? d['tutar'] ?? d['birimFiyat']),
          'tip': "BULUT",
          'kaynak': 'FB',
          'f_id': doc.id
        });
      }

      // 3. İCARLAR (KİRALAR)
      for (var t in tarlaVerileri) {
        if (t['sezon'].toString().trim() == _seciliSezon.trim() && (t['kira_tutari'] ?? 0) > 0) {
          tamListe.add({
            'baslik': "TARLA İCARI (KİRA)",
            'alt_baslik': "${t['mevki']} - ${t['ekilen_urun']}",
            'tarih': "${_seciliSezon}-01-01",
            'tutar': (t['kira_tutari'] ?? 0).toDouble(),
            'tip': "İCAR",
            'kaynak': 'SQL',
            'f_id': null
          });
        }
      }

      // Tarihe göre sırala
      tamListe.sort((a, b) => b['tarih'].compareTo(a['tarih']));

      // MODALI AÇ
      _giderListesiModal(tamListe);

    } catch (e) {
      print("❌ GİDER LİSTESİ HATASI: $e");
      // Ekranda hatayı gör ki neden açılmadığını anlayalım
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Hata: $e")));
    }
  }

// ⚠️ BU FONKSİYONU DA GÜNCELLE (PATLAMAMASI İÇİN)
  String _tarlaAdiniBul(dynamic id) {
    if (id == null || id == "0" || id == "") return "GENEL GİDER";
    try {
      return _tarlalar.firstWhere(
              (t) => t['id'].toString() == id.toString(),
          orElse: () => {'mevki': "BİLİNMEYEN TARLA"} // <-- BURASI HAYAT KURTARIR
      )['mevki'] ?? "İSİMSİZ TARLA";
    } catch (e) {
      return "GENEL GİDER";
    }
  }

  void _giderListesiModal(List<Map<String, dynamic>> tamListe) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
      builder: (c) => Container(
        padding: const EdgeInsets.all(16),
        height: MediaQuery.of(context).size.height * 0.9,
        child: Column(
          children: [
            Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(10))),
            const SizedBox(height: 15),
            Text("📉 $_seciliSezon TÜM GİDERLER", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            Text("Toplam ${tamListe.length} Harcama Kalemi", style: const TextStyle(color: Colors.grey, fontSize: 12)),
            const Divider(),
            // TOPLAM PANELİ
            Container(
              padding: const EdgeInsets.all(15),
              decoration: BoxDecoration(color: Colors.red[50], borderRadius: BorderRadius.circular(15)),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text("TOPLAM HARCAMA:", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
                  Text(
                    "${pdfFormat(_toplamMasraf)} TL", // formatTL yerine senin pdfFormat'ı kullandım
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.red),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: ListView.builder(
                itemCount: tamListe.length,
                itemBuilder: (context, index) {
                  final item = tamListe[index];

                  return Card(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: item['kaynak'] == 'SQL' ? Colors.red[50] : Colors.orange[50],
                        child: Icon(
                          item['kaynak'] == 'SQL' ? Icons.phone_android : Icons.cloud_queue,
                          color: item['kaynak'] == 'SQL' ? Colors.red : Colors.orange,
                          size: 20,
                        ),
                      ),
                      title: Text(item['baslik'], style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text("${item['alt_baslik']}\n${item['tarih']}"),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text("-${pdfFormat(item['tutar'])} TL",
                              style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                          const SizedBox(width: 8),
                          // İŞTE GERİ GELEN SİL BUTONU
                          IconButton(
                            icon: const Icon(Icons.delete_outline, color: Colors.red),
                            onPressed: () => _giderSilOnay(item),
                          ),
                        ],
                      ),
                      isThreeLine: true,
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

// BU DA ONAYLI SİLME FONKSİYONU (KAZAYI ÖNLER)
  void _giderSilOnay(Map<String, dynamic> item) {
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text("KAYIT SİLİNECEK"),
        content: Text("${item['baslik']} harcamasını silmek istediğine emin misin?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text("İPTAL")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              try {
                if (item['kaynak'] == 'SQL') {
                  // SQL ID'sini 'id' anahtarıyla aldığından emin ol
                  await (await DatabaseHelper.instance.database).delete(
                      'tarla_hareketleri',
                      where: 'id = ?',
                      whereArgs: [item['id']]
                  );
                } else if (item['kaynak'] == 'FB' && item['f_id'] != null) {
                  await FirebaseFirestore.instance
                      .collection('tarla_hareketleri')
                      .doc(item['f_id'])
                      .delete();
                }

                Navigator.pop(c); // Diyaloğu kapat
                Navigator.pop(context); // Modalı kapat ki liste yenilensin
                _verileriYukle(); // Rakamları ve ana ekranı tazele

                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text("${item['baslik']} başarıyla silindi"), backgroundColor: Colors.green),
                );
              } catch (e) {
                debugPrint("Silme Hatası: $e");
              }
            },
            child: const Text("SİL", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }


  Future<void> _kayitSil(String id, String kaynak) async {
    try {
      if (id.isEmpty) return;

      // 1. Firebase'den sil
      if (kaynak == 'FB' || kaynak == 'SENKRON') {
        await FirebaseFirestore.instance.collection('tarla_hareketleri').doc(id).delete();
      }
      // 2. SQL'den sil
      await DatabaseHelper.instance.tarlaHareketiSil(id);

      _verileriYukle(); // Ana sayfadaki rakamları tazele
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Kayıt silindi.")));
    } catch (e) {
      print("Silme Hatası: $e");
    }
  }
  String formatTL(dynamic deger) {
    try {
      double rakam = double.tryParse(deger.toString()) ?? 0;
      // Önce 2 basamaklı kuruş ve virgül ayarı
      String sonuc = rakam.toStringAsFixed(2).replaceAll('.', ',');
      // Sonra binlik ayraç (nokta) ekleme
      RegExp reg = RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))');
      return sonuc.replaceAllMapped(reg, (Match m) => '${m[1]}.');
    } catch (e) {
      return "0,00";
    }
  }


  // 1. LİSTE MODALI (Durum göstergeli hali)
  void _hasatListesiModal() async {
    final hasatlar = await DatabaseHelper.instance.tumHasatlariGetir();
    final sezonlukHasatlar = hasatlar.where((h) => h['sezon'].toString().trim() == _seciliSezon.trim()).toList();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
      builder: (c) => Container(
        padding: const EdgeInsets.all(16),
        height: MediaQuery.of(context).size.height * 0.8,
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text("🌾 $_seciliSezon HASATLARI", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                IconButton(
                  icon: const Icon(Icons.add_circle, color: Colors.amber, size: 35),
                  onPressed: () { Navigator.pop(c); _hasatYonetimiDiyalog(); },
                ),
              ],
            ),
            const Divider(),
            Expanded(
              child: ListView.builder(
                itemCount: sezonlukHasatlar.length,
                itemBuilder: (context, index) {
                  final h = sezonlukHasatlar[index];
                  double kalan = toDoubleSafe(h['kalan_alacak']);
                  String durum = h['odeme_durumu'] ?? "BEKLEMEDE";

                  return Card(
                    child: ListTile(
                      leading: Icon(
                        durum == "ÖDENDİ" ? Icons.check_circle : Icons.pending_actions,
                        color: durum == "ÖDENDİ" ? Colors.green : Colors.orange,
                      ),
                      title: Text("${h['satilan_kisi']} (${h['ekilen_urun']})"),
                      subtitle: Text("Kalan: ${pdfFormat(kalan)} TL"),
                      trailing: const Icon(Icons.edit, size: 20),
                      onTap: () {
                        Navigator.pop(c);
                        _hasatYonetimiDiyalog(mevcutHasat: h);
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

  void _hasatYonetimiDiyalog({Map<String, dynamic>? mevcutHasat}) async {
    final kgC = TextEditingController(text: mevcutHasat?['toplam_kg']?.toString() ?? "");
    final fiyatC = TextEditingController(text: mevcutHasat?['birim_fiyat']?.toString() ?? "");
    final kisiC = TextEditingController(text: mevcutHasat?['satilan_kisi'] ?? "");
    final pesinC = TextEditingController(text: mevcutHasat?['pesin_alinan']?.toString() ?? "0");
    final vadeC = TextEditingController(text: mevcutHasat?['vade_tarihi'] ?? "");
    String seciliDurum = mevcutHasat?['odeme_durumu'] ?? "BEKLEMEDE";
    int? seciliTarlaId = mevcutHasat?['tarla_id'];

    showDialog(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (context, setDialogState) {
          double kg = toDoubleSafe(kgC.text);
          double fiyat = toDoubleSafe(fiyatC.text);
          double toplamTutar = kg * fiyat;
          double pesin = toDoubleSafe(pesinC.text);
          double kalan = toplamTutar - pesin;

          if (kalan <= 0 && seciliDurum == "BEKLEMEDE") seciliDurum = "ÖDENDİ";

          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
            title: Text(mevcutHasat == null ? "YENİ HASAT GİRİŞİ" : "HASAT DÜZENLE"),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<int>(
                    value: _tarlalar.any((t) => t['id'] == seciliTarlaId) ? seciliTarlaId : null,
                    decoration: const InputDecoration(labelText: "TARLA SEÇİN", border: OutlineInputBorder()),
                    items: _tarlalar.where((t) => normalize(t['sezon']) == _seciliSezon).map((t) =>
                        DropdownMenuItem<int>(value: t['id'], child: Text("${t['mevki']} (${t['ekilen_urun']})"))).toList(),
                    onChanged: (v) => setDialogState(() => seciliTarlaId = v),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(child: _input(kgC, "KG", Icons.scale, tip: TextInputType.number, onChanged: (_) => setDialogState(() {}))),
                      const SizedBox(width: 5),
                      Expanded(child: _input(fiyatC, "FİYAT", Icons.paid, tip: TextInputType.number, onChanged: (_) => setDialogState(() {}))),
                    ],
                  ),
                  _input(kisiC, "MÜŞTERİ", Icons.person),

                  // ✅ GERİ GELEN TOPLAM TUTAR KUTUSU
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: Colors.green[50], borderRadius: BorderRadius.circular(10)),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text("TOPLAM TUTAR:", style: TextStyle(fontWeight: FontWeight.bold)),
                        Text("${formatPara(toplamTutar)} TL",
                            style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green, fontSize: 16)),
                      ],
                    ),
                  ),

                  const Divider(height: 25),

                  DropdownButtonFormField<String>(
                    value: seciliDurum,
                    decoration: const InputDecoration(labelText: "ÖDEME DURUMU", border: OutlineInputBorder()),
                    items: ["BEKLEMEDE", "ÖDENDİ", "İPTAL"].map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                    onChanged: (v) => setDialogState(() => seciliDurum = v!),
                  ),
                  const SizedBox(height: 10),
                  _input(pesinC, "PEŞİN ALINAN", Icons.money, tip: TextInputType.number, onChanged: (_) => setDialogState(() {})),

                  // ✅ GERİ GELEN KALAN BORÇ KUTUSU
                  if (kalan > 0) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: Colors.red[50], borderRadius: BorderRadius.circular(10)),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text("KALAN ALACAK:", style: TextStyle(fontWeight: FontWeight.bold)),
                          Text("${formatPara(kalan)} TL",
                              style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.red, fontSize: 16)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    _input(vadeC, "VADE TARİHİ", Icons.calendar_month),
                  ],
                ],
              ),
            ),
            actions: [
              if (mevcutHasat != null)
                TextButton(
                  onPressed: () async {
                    try {
                      String? fId = mevcutHasat['firebase_id'];
                      if (fId != null && fId.isNotEmpty) {
                        await FirebaseFirestore.instance.collection('tarla_hasatlari').doc(fId).delete();
                      }
                      await (await DatabaseHelper.instance.database).delete(
                          'tarla_hasatlari',
                          where: 'id = ?',
                          whereArgs: [mevcutHasat['id']]
                      );
                      Navigator.pop(c);
                      _verileriYukle();
                    } catch (e) {
                      debugPrint("❌ Silme hatası: $e");
                    }
                  },
                  child: const Text("SİL", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                ),
              TextButton(onPressed: () => Navigator.pop(c), child: const Text("İPTAL")),
              ElevatedButton(
                onPressed: () async {
                  if (seciliTarlaId != null && kg > 0) {
                    var tarlaData = _tarlalar.firstWhere((t) => t['id'] == seciliTarlaId);
                    Map<String, dynamic> veri = {
                      'tarla_id': seciliTarlaId,
                      'sezon': _seciliSezon,
                      'ekilen_urun': tarlaData['ekilen_urun'] ?? "BELİRSİZ",
                      'toplam_kg': kg,
                      'birim_fiyat': fiyat,
                      'toplam_gelir': toplamTutar,
                      'satilan_kisi': kisiC.text.trim().toUpperCase(),
                      'pesin_alinan': pesin,
                      'kalan_alacak': kalan,
                      'vade_tarihi': vadeC.text,
                      'odeme_durumu': seciliDurum,
                      'tarih': mevcutHasat?['tarih'] ?? DateTime.now().toString().split(' ')[0],
                    };

                    if (mevcutHasat == null) {
                      var docRef = await FirebaseFirestore.instance.collection('tarla_hasatlari').add(veri);
                      veri['firebase_id'] = docRef.id;
                      await DatabaseHelper.instance.hasatEkle(veri);
                    } else {
                      String? fId = mevcutHasat['firebase_id'];
                      if (fId != null) {
                        await FirebaseFirestore.instance.collection('tarla_hasatlari').doc(fId).update(veri);
                      }
                      await DatabaseHelper.instance.hasatGuncelle(mevcutHasat['id'], veri);
                    }
                    Navigator.pop(c);
                    _verileriYukle();
                  }
                },
                child: const Text("KAYDET"),
              ),
            ],
          );
        },
      ),
    );
  }

  void _islemListesiGoster(String baslik, IconData ikon, Color renk) async {
    final hareketler = await DatabaseHelper.instance.tumTarlaHareketleriniGetir();

    final liste = hareketler.where((h) =>
    h['sezon'] == _seciliSezon &&
        (baslik.contains(h['islem_tipi'] ?? "") || h['islem_adi'].toString().contains(baslik))
    ).toList();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (c) => Container(
        padding: const EdgeInsets.all(16),
        height: MediaQuery.of(context).size.height * 0.7,
        child: Column(
          children: [
            // Başlık Çubuğu
            Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(10))),
            const SizedBox(height: 10),
            Text("$baslik KAYITLARI", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: renk)),
            const Divider(),

            Expanded(
              child: liste.isEmpty
                  ? const Center(child: Text("Bu kategoriye ait işlem bulunamadı."))
                  : ListView.builder(
                itemCount: liste.length,
                itemBuilder: (context, i) {
                  final item = liste[i];

                  // İŞTE SOLA KAYDIR SİL ÖZELLİĞİ (DISMISSIBLE)
                  return Dismissible(
                    key: Key("gider_${item['id']}"), // Her satır için benzersiz anahtar
                    direction: DismissDirection.endToStart, // Sadece sola kaydırınca çalışır
                    background: Container(
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.only(right: 20),
                      color: Colors.red,
                      child: const Icon(Icons.delete, color: Colors.white),
                    ),
                    onDismissed: (direction) async {
                      // 1. Veritabanından sil
                      await (await DatabaseHelper.instance.database).delete(
                          'tarla_hareketleri',
                          where: 'id = ?',
                          whereArgs: [item['id']]
                      );

                      // 2. Ana ekran rakamlarını tazele
                      _verileriYukle();

                      // 3. Kullanıcıya bilgi ver
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text("${item['islem_adi']} silindi"), backgroundColor: Colors.red),
                      );
                    },
                    child: Card(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      child: ListTile(
                        onTap: () => _islemEkleDialog(baslik, ikon, renk, mevcutHareket: item), // Tıklayınca güncelleme açılsın
                        leading: Icon(ikon, color: renk),
                        title: Text(item['islem_adi'] ?? "İsimsiz İşlem"),
                        subtitle: Text(item['tarih'] ?? ""),
                        trailing: Text("${formatPara(item['tutar'])} TL",
                            style: const TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ); // Dismissible Kapanışı
                },
              ),
            ),
          ],
        ),
      ),
    );
  }


  // --- KAYIT EKLEME VE GÜNCELLEME (OTOMATİK ÜRÜN ATAMALI) ---
  void _islemEkleDialog(String baslik, IconData ikon, Color renk, {Map<String, dynamic>? mevcutHareket}) {
    final adC = TextEditingController(text: mevcutHareket?['islem_adi']);
    final miktarC = TextEditingController(text: mevcutHareket?['miktar']?.toString());
    final tutarC = TextEditingController(text: mevcutHareket?['tutar']?.toString());
    int? seciliTarlaId = mevcutHareket?['tarla_id'];

    showDialog(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(mevcutHareket == null ? "$baslik KAYDI" : "$baslik GÜNCELLE"),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<int>(
                  value: seciliTarlaId,
                  decoration: const InputDecoration(labelText: "TARLA SEÇİN"),
                  items: _tarlalar.where((t) => (t['sezon'] ?? "2026") == _seciliSezon).map((t) => DropdownMenuItem<int>(value: t['id'], child: Text("${t['mevki']} (${t['ekilen_urun']})"))).toList(),
                  onChanged: (v) => setDialogState(() => seciliTarlaId = v),
                ),
                _input(adC, baslik == "MAZOT" ? "FİŞ NO / AÇIKLAMA" : "ÜRÜN ADI / MARKA", ikon),
                _input(miktarC, baslik == "MAZOT" ? "LİTRE" : "MİKTAR (KG/LT)", Icons.numbers, tip: TextInputType.number),
                _input(tutarC, "TOPLAM TUTAR (TL)", Icons.payments, tip: TextInputType.number),
              ],
            ),
          ),
          actions: [
            if (mevcutHareket != null)
              TextButton(onPressed: () async {
                await (await DatabaseHelper.instance.database).delete('tarla_hareketleri', where: 'id = ?', whereArgs: [mevcutHareket['id']]);
                Navigator.pop(c); _verileriYukle();
              }, child: const Text("SİL", style: TextStyle(color: Colors.red))),
            TextButton(onPressed: () => Navigator.pop(c), child: const Text("İPTAL")),
            ElevatedButton(
              onPressed: () async {
                if (seciliTarlaId != null && tutarC.text.isNotEmpty) {
                  // Seçilen tarlanın o anki ürününü buluyoruz
                  var tarlaData = _tarlalar.firstWhere((t) => t['id'] == seciliTarlaId);

                  Map<String, dynamic> veri = {
                    'tarla_id': seciliTarlaId,
                    'sezon': _seciliSezon,
                    'islem_tipi': baslik,
                    'islem_adi': adC.text.toUpperCase(),
                    'ekilen_urun': tarlaData['ekilen_urun'], // VERİTABANINA ÜRÜNÜ DE GÖNDERİYORUZ
                    'miktar': double.tryParse(miktarC.text) ?? 0,
                    'tutar': double.tryParse(tutarC.text) ?? 0,
                    'tarih': mevcutHareket?['tarih'] ?? DateTime.now().toString().split(' ')[0],
                  };

                  if (mevcutHareket == null) {
                    await DatabaseHelper.instance.tarlaHareketiEkle(veri);
                  } else {
                    await (await DatabaseHelper.instance.database).update('tarla_hareketleri', veri, where: 'id = ?', whereArgs: [mevcutHareket['id']]);
                  }
                  Navigator.pop(c);
                  _verileriYukle();
                }
              },
              child: const Text("KAYDET"),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text("ÇİFTÇİLİK TAKİP",
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
        backgroundColor: toprakRengi,
        actions: [
          // --- 1. WHATSAPP PAYLAŞ BUTONU (YENİ EKLENDİ) ---
          IconButton(
            icon: const Icon(Icons.share, color: Colors.white),
            tooltip: "Raporu Paylaş",
            onPressed: () {
              _pdfRaporOlusturVePaylas(); // Bu fonksiyonu tetikler
            },
          ),
          // --- 2. SEZON SEÇİMİ ---
          DropdownButton<String>(
            value: _seciliSezon,
            dropdownColor: toprakRengi,
            underline: const SizedBox(), // Alttaki çizgiyi kaldırdık, temiz durur
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            items: _sezonlar.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
            onChanged: (v) {
              setState(() => _seciliSezon = v!);
              _verileriYukle();
            },
          ),
          const SizedBox(width: 10),
        ],
      ),
      body: Column( // Ana yapın aynen kalıyor
        children: [
          _ustRaporKartlari(),
          _hizliMenu(),
          const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text("TARLA İŞLEMLERİ", style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.2))
          ),
          // Expanded senin GridView'ını ekranın geri kalanına yayıyor, burası kalsın
          Expanded(
              child: GridView.count(
                // Klavye açıldığında bu GridView'ın yukarı kayabilmesi için:
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  crossAxisCount: 3,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                  children: [
                    _islemKarti("GÜBRE GİDER", Icons.science, Colors.blue),
                    _islemKarti("İLAÇ GİDER", Icons.pest_control, Colors.orange),
                    _islemKarti("MAZOT GİDER", Icons.local_gas_station, Colors.red),
                    _islemKarti("HASAT GİRİŞ", Icons.agriculture, Colors.amber[900]!),
                    _islemKarti("SULAMA GİDER", Icons.water_drop, Colors.blueAccent),
                    _islemKarti("ANALİZ", Icons.query_stats, Colors.deepPurple),
                    _islemKarti("GİDERLER", Icons.summarize, Colors.black),
                  ]
              )
          )
        ],
      ),
    );
  }

  Widget _ustRaporKartlari() => Container(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Row(children: [
            // GİDER'E TIKLAYINCA: Gider Detaylarını Aç (false parametresiyle)
            _raporLabel("TOPLAM GİDER", "${formatPara(_toplamMasraf)} TL", Colors.red,
                onTap: () => _genelRaporDetayGoster(false)),

            // GELİR'E TIKLAYINCA: Hasat/Gelir Detaylarını Aç (true parametresiyle)
            _raporLabel("TOPLAM GELİR", "${formatPara(_toplamGelir)} TL", Colors.green,
                onTap: () => _genelRaporDetayGoster(true)),
          ]),
          const SizedBox(height: 5),
          Row(children: [
            // NET KÂR'A TIKLAYINCA: Şimdilik bir şey açmasın veya özet göstersin
            _raporLabel("NET KÂR", "${formatPara(_toplamGelir - _toplamMasraf)} TL", Colors.blue),

            _raporLabel("$_seciliSezon İŞLEM", "$_islemSayisi ADET", Colors.black54),
          ]),
        ],
      )
  );

  Widget _raporLabel(String b, String d, Color r, {VoidCallback? onTap}) {
    return Expanded(
      child: InkWell( // Tıklama özelliği ekledik
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.all(2),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: r.withAlpha(128)),
            borderRadius: BorderRadius.circular(8),
            boxShadow: [ // Hafif bir gölge atalım, tıklandığı belli olsun
              BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4, offset: const Offset(0, 2))
            ],
          ),
          child: Column(
            children: [
              Text(b, style: TextStyle(fontSize: 10, color: r, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(d, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _hizliMenu() => Container(padding: const EdgeInsets.symmetric(vertical: 10), color: Colors.white, child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [_hizliButon("TARLALAR", Icons.map, Colors.green), _hizliButon("RAPOR", Icons.bar_chart, Colors.black)]));

  Widget _hizliButon(String t, IconData i, Color r) => InkWell(
      onTap: () {
        if(t == "TARLALAR") _tarlaListesiGoster();
        if(t == "RAPOR") _pdfOnizlemeGoster(context);
      },
      child: Column(children: [
        Icon(i, color: r),
        const SizedBox(height: 4), // İkonla yazı birbirine girmesin diye azıcık boşluk
        Text(t, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold))
      ])
  );
// Önizleme Penceresini Açan Fonksiyon
  void _pdfOnizlemeGoster(BuildContext context) async {
    // Önce PDF verisini oluşturup alalım
    final pdfData = await _pdfVerisiOlustur();

    // Ekranda Full-Screen (Tam Ekran) önizleme açar
    Navigator.push(context, MaterialPageRoute(builder: (context) => Scaffold(
      appBar: AppBar(
        title: const Text("RAPOR ÖNİZLEME"),
        backgroundColor: Colors.brown[800],
      ),
      body: PdfPreview(
        build: (format) => pdfData, // PDF içeriği buraya geliyor
        allowPrinting: true, // Yazıcıdan çıkartma izni
        allowSharing: true,  // WhatsApp/Mail paylaşım izni
        canChangePageFormat: false,
        initialPageFormat: PdfPageFormat.a4,
        pdfFileName: "Evren_Tarim_${_seciliSezon}_Raporu.pdf",
      ),
    )));
  }
  Future<Uint8List> _pdfVerisiOlustur() async {
    final pdf = pw.Document();

    // 1. Font ve Tema (Karakter hatası almamak için şart)
    final fontData = await rootBundle.load("assets/fonts/arial.ttf");
    final ttf = pw.Font.ttf(fontData);
    final anaTema = pw.ThemeData.withFont(base: ttf, bold: ttf);

    // 2. Verileri Topla (SENİN SAYFADAKİ HAVUZ MANTIĞI)
    final yerelHareketler = await DatabaseHelper.instance.tumTarlaHareketleriniGetir();
    final hasatlar = await DatabaseHelper.instance.tumHasatlariGetir();

    // Firebase'den bu sezona ait tüm giderleri çekiyoruz
    final fbSnapshot = await FirebaseFirestore.instance
        .collection('tarla_hareketleri')
        .where('sezon', isEqualTo: _seciliSezon.trim())
        .get();

    Map<String, Map<String, dynamic>> havuz = {};

    // 🔥 Önce Firebase verilerini havuza at
    for (var doc in fbSnapshot.docs) {
      var d = doc.data();
      havuz[doc.id] = {
        'tarih': d['tarih']?.toString().split('T')[0] ?? "-",
        'islem': (d['islem'] ?? d['aciklama'] ?? "Gider").toString().toUpperCase(),
        'tarla': _tarlaAdiniBul(d['tarlaId']),
        'tutar': (d['toplam'] ?? d['tutar'] ?? 0).toDouble(),
      };
    }

    // 🔥 Sonra SQL verilerini havuza at (Çakışanları Firebase ID ile engelle)
    for (var h in yerelHareketler) {
      if (h['sezon'].toString().trim() == _seciliSezon.trim()) {
        String? fId = h['firebase_id']?.toString();
        String key = (fId != null && fId.isNotEmpty) ? fId : "sql_${h['id']}";

        // Havuzda yoksa ekle (Mükerrer kaydı önler)
        havuz.putIfAbsent(key, () => {
          'tarih': h['tarih']?.toString().split('T')[0] ?? "-",
          'islem': (h['islem_adi'] ?? h['islem_tipi'] ?? "Gider").toString().toUpperCase(),
          'tarla': _tarlaAdiniBul(h['tarla_id']),
          'tutar': (h['tutar'] ?? 0).toDouble(),
        });
      }
    }

    final giderListesi = havuz.values.toList();

    // 3. PDF Tasarımı
    pdf.addPage(pw.MultiPage(
      theme: anaTema,
      pageFormat: PdfPageFormat.a4,
      build: (context) => [
        pw.Header(level: 0, child: pw.Text("EVREN TARIM $_seciliSezon RAPORU",
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 20))),

        pw.SizedBox(height: 20),

        // GİDER TABLOSU (Havuzdan gelen verilerle)
        pw.Text("1. GIDER DETAYLARI", style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 10),
        pw.TableHelper.fromTextArray(
          headers: ['Tarih', 'Islem', 'Tarla', 'Tutar'],
          headerDecoration: const pw.BoxDecoration(color: PdfColors.teal),
          headerStyle: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold),
          data: giderListesi.map((g) => [
            g['tarih'],
            g['islem'],
            g['tarla'],
            "${pdfFormat(g['tutar'])} TL"
          ]).toList(),
        ),

        pw.SizedBox(height: 30),

        // HASAT TABLOSU
        pw.Text("2. GELIR (HASAT) DETAYLARI", style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 10),
        pw.TableHelper.fromTextArray(
          headers: ['Urun', 'Musteri', 'Miktar', 'Gelir'],
          headerDecoration: const pw.BoxDecoration(color: PdfColors.green),
          headerStyle: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold),
          data: hasatlar.where((h) => h['sezon'].toString() == _seciliSezon).map((h) => [
            h['ekilen_urun']?.toString().toUpperCase() ?? "-",
            h['satilan_kisi']?.toString().toUpperCase() ?? "-",
            "${h['toplam_kg']} KG",
            "${pdfFormat(h['toplam_gelir'])} TL"
          ]).toList(),
        ),
      ],
    ));

    return pdf.save();
  }


  void _tarlaListesiGoster() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (c) => StatefulBuilder(
        builder: (context, setModalState) => DraggableScrollableSheet(
          initialChildSize: 0.9,
          expand: false,
          builder: (_, controller) {
            final filtreliListe = _tarlalar; // Filtre yok, ne varsa göster.

            return Container(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  const Text(
                    "TARLALAR VE İCARLAR",
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const Divider(),

                  // YENİ KAYIT BUTONU
                  // YENİ KAYIT BUTONU KISMINI BÖYLE DÜZENLE
                  ElevatedButton.icon(
                    onPressed: () async {
                      print("🛠️ MANUEL TETİKLEME: Veriler yükleniyor..."); // DOĞRU (Küçük p)
                      await _verileriYukle(); // Manuel olarak çağırıyoruz
                      await _tarlaEkleDialog();

                      // 2. KRİTİK NOKTA: Veritabanından güncel listeyi ana değişkene (_tarlalar) tekrar çek
                      await _verileriYukle();

                      // 3. Modal'ın içini tazele (filtreliListe şimdi güncel _tarlalar'dan beslenecek)
                      setModalState(() {});
                    },
                    icon: const Icon(Icons.add),
                    label: const Text("YENİ TARLA KAYDI"),
                  ),

                  const SizedBox(height: 10),

                  Expanded(
                    child: ListView.builder(
                      controller: controller,
                      itemCount: filtreliListe.length,
                      itemBuilder: (context, i) {
                        final t = filtreliListe[i];
                        return Card(
                          child: ListTile(
                            leading: Icon(
                              Icons.landscape,
                              color: t['is_icar'] == 1 ? Colors.orange : Colors.green,
                            ),
                            title: Text(t['mevki'] ?? "Bilinmiyor"),
                            subtitle: Text("${t['ekilen_urun'] ?? "BOŞ"} | ${t['dekar']} Da"),
                            trailing: Wrap(
                              children: [
                                // EKSTRE
                                IconButton(
                                  icon: const Icon(Icons.receipt_long, color: Colors.blue),
                                  onPressed: () => _tarlaEkstreGoster(t),
                                ),
                                // DÜZENLE (GÜNCELLEME)
                                IconButton(
                                  icon: const Icon(Icons.edit, color: Colors.orange),
                                  onPressed: () async {
                                    // Veriyi gönderiyoruz, işlem bitince setModalState ile modalı tazeletiyoruz
                                    await _tarlaEkleDialog(mevcutTarla: t);
                                    await _verileriYukle();
                                    setModalState(() {});
                                  },
                                ),
                                // SİL
                                IconButton(
                                  icon: const Icon(Icons.delete, color: Colors.red),
                                  onPressed: () async {
                                    await _silOnay(t['id']);
                                    await _verileriYukle();
                                    setModalState(() {});
                                  },
                                ),
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
          },
        ),
      ),
    );
  }

  Future<void> _silOnay(int id) async {
    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("KAYIT SİLİNSİN Mİ?"),
        content: const Text("Bu tarlayı ve tarlaya ait tüm verileri silmek istediğinize emin misiniz?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("İPTAL"),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              try {
                final db = await DatabaseHelper.instance.database;

                // 1. Yerel Veritabanından Sil
                await db.delete('tarlalar', where: 'id = ?', whereArgs: [id]);

                // 2. Firebase'den Sil
                await FirebaseFirestore.instance
                    .collection('tarlalar')
                    .doc("TRL_$id")
                    .delete();

                if (mounted) {
                  Navigator.pop(context); // Diyaloğu kapat
                  _verileriYukle(); // Ana listeyi tazele
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("Tarla başarıyla silindi"), backgroundColor: Colors.red),
                  );
                }
              } catch (e) {
                debugPrint("SİLME HATASI: $e");
              }
            },
            child: const Text("EVET, SİL", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _tarlaEkstreGoster(Map<String, dynamic> t) async {
    final hareketler = await DatabaseHelper.instance.tumTarlaHareketleriniGetir();
    final hasatlar = await DatabaseHelper.instance.tumHasatlariGetir();

    // Bu tarlaya ait TÜM işlemler (Giderler + Hasatlar)
    List<Map<String, dynamic>> tumGecmis = [];

    // Masrafları ekle (Ekim, Sürüm, İlaç vs.)
    tumGecmis.addAll(hareketler.where((h) => h['tarla_id'] == t['id'] && h['sezon'] == _seciliSezon));

    // Hasatları ekle
    var buTarlaHasat = hasatlar.where((h) => h['tarla_id'] == t['id'] && h['sezon'] == _seciliSezon);
    for (var h in buTarlaHasat) {
      tumGecmis.add({
        'islem_tipi': 'HASAT',
        'islem_adi': 'ÜRÜN BİÇİMİ / SATIŞ',
        'tarih': h['hasat_tarihi'],
        'tutar': h['toplam_gelir'],
        'detay': "${h['toplam_kg']} KG - ${h['satilan_kisi']}",
        'gelir_mi': true
      });
    }

    // TARİHE GÖRE SIRALA (En eski işlemden en yeniye)
    tumGecmis.sort((a, b) => a['tarih'].compareTo(b['tarih']));

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (c) => Container(
        padding: const EdgeInsets.all(16),
        height: MediaQuery.of(context).size.height * 0.85,
        child: Column(children: [
          // BAŞLIK BİLGİSİ
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text("${t['mevki']}", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              Text("Ürün: ${t['ekilen_urun']} | Sezon: $_seciliSezon", style: const TextStyle(color: Colors.grey)),
            ]),
            const Icon(Icons.history, color: Colors.brown, size: 30),
          ]),
          const Divider(thickness: 2),

          Expanded(
            child: tumGecmis.isEmpty
                ? const Center(child: Text("Bu tarla için henüz bir işlem kaydı yok."))
                : ListView.builder(
              itemCount: tumGecmis.length,
              itemBuilder: (context, i) {
                final h = tumGecmis[i];
                bool isGelir = h['gelir_mi'] == true;

                return Row(
                  children: [
                    // SOL TARAF: TARİH ÇİZGİSİ (Zaman Çizelgesi Efekti)
                    Column(children: [
                      Container(width: 2, height: 20, color: Colors.grey[300]),
                      Icon(_ikonGetir(h['islem_tipi']), color: _renkGetir(h['islem_tipi']), size: 24),
                      Container(width: 2, height: 20, color: Colors.grey[300]),
                    ]),
                    const SizedBox(width: 15),

                    // SAĞ TARAF: İŞLEM DETAYI
                    Expanded(
                      child: Card(
                        elevation: 0,
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        shape: RoundedRectangleBorder(
                            side: BorderSide(color: Colors.grey[200]!),
                            borderRadius: BorderRadius.circular(10)
                        ),
                        child: ListTile(
                          title: Text("${h['islem_tipi']} - ${h['islem_adi']}",
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                          subtitle: Text("Tarih: ${h['tarih']}${h['detay'] != null ? '\n${h['detay']}' : ''}"),
                          trailing: Text(
                            "${isGelir ? '+' : '-'}${formatPara(h['tutar'])} TL",
                            style: TextStyle(
                                color: isGelir ? Colors.green : Colors.red,
                                fontWeight: FontWeight.bold
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ]),
      ),
    );
  }
  void _genelRaporDetayGoster(bool gelirMi) async {
    final hareketler = await DatabaseHelper.instance.tumTarlaHareketleriniGetir();
    final hasatlar = await DatabaseHelper.instance.tumHasatlariGetir();

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (c) => Container(
        padding: const EdgeInsets.all(16),
        height: MediaQuery.of(context).size.height * 0.8,
        child: Column(children: [
          // Sürükleme çubuğu (Görsel olarak iyi durur)
          Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(10))),
          const SizedBox(height: 15),
          Text(gelirMi ? "$_seciliSezon HASAT VE SATIŞLAR" : "$_seciliSezon TÜM GİDERLER",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: gelirMi ? Colors.green : Colors.red)),
          const Divider(),
          Expanded(
            child: gelirMi
                ? ListView.builder(
                itemCount: hasatlar.where((h) => h['sezon'] == _seciliSezon).length,
                itemBuilder: (context, i) {
                  final h = hasatlar.where((h) => h['sezon'] == _seciliSezon).toList()[i];
                  String tarlaAdi = _tarlalar.firstWhere((t) => t['id'] == h['tarla_id'], orElse: () => {'mevki': 'Bilinmeyen'})['mevki'];
                  bool odendi = h['odeme_durumu'] == "ALINDI";

                  return Card(
                    color: odendi ? Colors.white : Colors.amber[50],
                    child: ListTile(
                      onTap: () {
                        Navigator.pop(c);
                        _hasatYonetimiDiyalog(mevcutHasat: h);
                      },
                      title: Text("$tarlaAdi - ${h['satilan_kisi']}"),
                      subtitle: Text("${h['toplam_kg']} KG | ${h['birim_fiyat']} TL\nDurum: ${h['odeme_durumu']}"),
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text("${formatPara(h['toplam_gelir'])} TL", style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
                          // HATALI SATIR:
// Icon(odendi ? Icons.check_circle : Icons.orange, color: odendi ? Colors.green : Colors.orange, size: 16),

// DOĞRUSU:
                          Icon(
                            odendi ? Icons.check_circle : Icons.pending, // İkon olarak pending veya warning kullan
                            color: odendi ? Colors.green : Colors.orange, // Renk olarak orange burada kullanılır
                            size: 16,
                          ),
                        ],
                      ),
                    ),
                  );
                })
                : ListView.builder(
                itemCount: hareketler.where((h) => h['sezon'] == _seciliSezon).length,
                itemBuilder: (context, i) {
                  final h = hareketler.where((h) => h['sezon'] == _seciliSezon).toList()[i];
                  return Card( // Daha iyi görünmesi için Card içine aldım
                    elevation: 0,
                    shape: RoundedRectangleBorder(side: BorderSide(color: Colors.grey[100]!), borderRadius: BorderRadius.circular(10)),
                    child: ListTile(
                      // --- KRİTİK EKLEME: Gider detayına uçurur ---
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => GiderDetaySayfasi(
                              islemTipi: h['islem_tipi'].toString().toUpperCase(),
                            ),
                          ),
                        ).then((_) => _verileriYukle()); // Geri dönünce verileri tazele
                      },
                      leading: Icon(_ikonGetir(h['islem_tipi']), color: _renkGetir(h['islem_tipi'])),
                      title: Text("${h['islem_tipi']} - ${h['islem_adi']}"),
                      subtitle: Text(h['tarih']),
                      trailing: Text("${formatPara(h['tutar'])} TL", style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                    ),
                  );
                }),
          )
        ]),
      ),
    );
  }

  Future<void> _tarlaEkleDialog({Map<String, dynamic>? mevcutTarla}) async {
    final mevkiC = TextEditingController(text: mevcutTarla?['mevki']);
    final dekarC = TextEditingController(text: mevcutTarla?['dekar']?.toString());
    final adaParselC = TextEditingController(text: mevcutTarla?['ada_parsel']);
    final sahibiC = TextEditingController(text: mevcutTarla?['tarla_sahibi']);
    final kiraC = TextEditingController(text: mevcutTarla?['kira_tutari']?.toString());
    final baslangicC = TextEditingController(text: mevcutTarla?['kira_baslangic'] ?? "2026-01-01");
    final bitisC = TextEditingController(text: mevcutTarla?['kira_bitis'] ?? "2026-12-31");

    bool isSulu = (mevcutTarla?['is_sulu'] ?? 0) == 1;
    bool isIcar = (mevcutTarla?['is_icar'] ?? 0) == 1;
    String seciliUrun = mevcutTarla?['ekilen_urun'] ?? "BOŞ";
    bool isSaving = false; // Kilit burada

    showDialog(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: Text(mevcutTarla == null ? "YENİ TARLA KAYDI" : "TARLA GÜNCELLE"),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    decoration: const InputDecoration(labelText: "EKİLEN ÜRÜN", border: OutlineInputBorder()),
                    value: seciliUrun,
                    items: _urunler.map((u) => DropdownMenuItem(value: u, child: Text(u))).toList(),
                    onChanged: (v) => setDialogState(() => seciliUrun = v!),
                  ),
                  const SizedBox(height: 10),
                  _input(mevkiC, "MEVKİ / TARLA ADI", Icons.map),
                  _input(dekarC, "DEKAR (DÖNÜM)", Icons.straighten, tip: TextInputType.number),
                  _input(adaParselC, "ADA / PARSEL", Icons.grid_3x3),
                  const Divider(),
                  SwitchListTile(
                    title: Text(isSulu ? "SULU TARLA" : "SUSUZ TARLA"),
                    secondary: Icon(Icons.water_drop, color: isSulu ? Colors.blue : Colors.grey),
                    value: isSulu,
                    onChanged: (v) => setDialogState(() => isSulu = v),
                  ),
                  SwitchListTile(
                    title: Text(isIcar ? "İCAR (KİRALIK)" : "KENDİ MÜLKÜM"),
                    secondary: Icon(Icons.history_edu, color: isIcar ? Colors.orange : Colors.green),
                    value: isIcar,
                    onChanged: (v) => setDialogState(() => isIcar = v),
                  ),
                  if (isIcar) ...[
                    _input(sahibiC, "TARLA SAHİBİ", Icons.person),
                    _input(kiraC, "YILLIK KİRA TUTARI (TL)", Icons.money, tip: TextInputType.number),
                    Row(
                      children: [
                        Expanded(child: _input(baslangicC, "BAŞLANGIÇ", Icons.date_range)),
                        const SizedBox(width: 5),
                        Expanded(child: _input(bitisC, "BİTİŞ", Icons.event_available)),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(c), child: const Text("İPTAL")),
              ElevatedButton(
                onPressed: isSaving ? null : () async {
                  setDialogState(() => isSaving = true);
                  try {
                    Map<String, dynamic> veri = {
                      'mevki': mevkiC.text.toUpperCase(),
                      'dekar': double.tryParse(dekarC.text) ?? 0,
                      'ada_parsel': adaParselC.text,
                      'is_sulu': isSulu ? 1 : 0,
                      'is_icar': isIcar ? 1 : 0,
                      'tarla_sahibi': isIcar ? sahibiC.text : "",
                      'kira_tutari': isIcar ? (double.tryParse(kiraC.text) ?? 0) : 0,
                      'kira_baslangic': isIcar ? baslangicC.text : "",
                      'kira_bitis': isIcar ? bitisC.text : "",
                      'sezon': _seciliSezon,
                      'ekilen_urun': seciliUrun,
                      'is_synced': 1,
                    };

                    final db = await DatabaseHelper.instance.database;

                    if (mevcutTarla == null) {
                      int yeniId = await db.insert('tarlalar', veri);
                      // Firebase tarafına yazarken ID'yi elle veriyoruz
                      await FirebaseFirestore.instance
                          .collection('tarlalar')
                          .doc("TRL_$yeniId")
                          .set({...veri, 'id': yeniId}, SetOptions(merge: true));
                    } else {
                      int targetId = mevcutTarla['id'];
                      await db.update('tarlalar', veri, where: 'id = ?', whereArgs: [targetId]);
                      await FirebaseFirestore.instance
                          .collection('tarlalar')
                          .doc("TRL_$targetId")
                          .set({...veri, 'id': targetId}, SetOptions(merge: true));
                    }

                    if (mounted) {
                      Navigator.pop(c);
                      _verileriYukle();
                    }
                  } catch (e) {
                    debugPrint("HATA: $e");
                  } finally {
                    if (mounted) setDialogState(() => isSaving = false);
                  }
                },
                child: isSaving
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text("KAYDET"),
              ),
            ],
          );
        },
      ),
    );
  }

  IconData _ikonGetir(String tip) {
    switch (tip) {
      case "EKİM": return Icons.grass;
      case "GÜBRELEME": return Icons.science;
      case "İLAÇLAMA": return Icons.pest_control;
      case "MAZOT": return Icons.local_gas_station;
      case "SÜRÜM": return Icons.agriculture;
      case "HASAT": return Icons.shopping_basket;
      case "SULAMA": case "SU": return Icons.water_drop;
      case "ELEKTRİK": return Icons.bolt;
      case "İŞÇİLİK": return Icons.groups;
      case "TOHUM": return Icons.grain;
      case "İCAR": return Icons.history_edu;
      default: return Icons.receipt_long;
    }
  }

  Color _renkGetir(String tip) {
    switch (tip) {
      case "EKİM": return Colors.teal;
      case "HASAT": return Colors.amber[900]!;
      case "İLAÇLAMA": return Colors.orange;
      case "SÜRÜM": return Colors.brown;
      case "MAZOT": return Colors.red;
      case "SU": case "SULAMA": return Colors.blue;
      case "ELEKTRİK": return Colors.yellow[800]!;
      case "İŞÇİLİK": return Colors.purple;
      case "İCAR": return Colors.deepOrange;
      default: return Colors.blueGrey;
    }
  }


  String formatPara(dynamic deger) {
    double rakam = (deger ?? 0).toDouble();
    return rakam.toStringAsFixed(0).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]}.');
  }
}