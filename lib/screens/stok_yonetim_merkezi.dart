import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../db/database_helper.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'dart:typed_data'; // Uint8List için şart
import 'package:flutter/services.dart'; // rootBundle (Logo okuma) için şart
import 'package:pdf/pdf.dart'; // PdfColors ve PdfPageFormat için
import 'package:share_plus/share_plus.dart';
import 'stok_tanimla_sayfasi.dart';
import 'package:sqflite/sqflite.dart';
import 'alis_islem_sayfasi.dart'; // Eğer aynı klasördeyseler
import 'package:path_provider/path_provider.dart'; // En üste ekle
import 'package:flutter/foundation.dart' show kIsWeb; //
import 'dart:io' as io; // File hatasını engellemek için 'as io' dedik[cite: 1]
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'dart:io' show File;


class StokYonetimMerkezi extends StatefulWidget {
  final int seciliSube;
  const StokYonetimMerkezi({super.key, required this.seciliSube});

  @override
  State<StokYonetimMerkezi> createState() => _StokYonetimMerkeziState();
}

class _StokYonetimMerkeziState extends State<StokYonetimMerkezi> {
  final TextEditingController _araC = TextEditingController();

  int _aktifFiltreSube = 2;
  String seciliSube = "HEPSİ"; // Başlangıç ismini de düzelttik
  List<Map<String, dynamic>> _asilListe = [];
  List<Map<String, dynamic>> _filtreli = [];

  // KATEGORİLER BURADA DA OLSUN (Gerekirse diye)
  List<String> _kategoriler = [];
  bool _tutarGozuksun = false;

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
    // 2. widget.seciliSube yerine direkt 2 vererek "HEPSİ" ile açılmasını sağlıyoruz
    _aktifFiltreSube = 2;
    _verileriYukle();
    _firebaseSenkronizeEt();
  }

  void _subeTransfer(Map<String, dynamic> urun) {
    final TextEditingController miktarC = TextEditingController();
    double mevcutAdet = double.tryParse(urun['adet'].toString()) ?? 0;
    String suankiSube = urun['sube'].toString().toUpperCase();
    String hedefSube = (suankiSube == "TEFENNİ") ? "AKSU" : "TEFENNİ";

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        title: const Text("ŞUBELER ARASI SEVKİYAT", textAlign: TextAlign.center),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 15),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.blue[200]!),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  Column(children: [
                    const Text("ÇIKIŞ", style: TextStyle(fontSize: 10, color: Colors.red)),
                    Text(suankiSube, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  ]),
                  const Icon(Icons.double_arrow, color: Colors.blue),
                  Column(children: [
                    const Text("VARIŞ", style: TextStyle(fontSize: 10, color: Colors.green)),
                    Text(hedefSube, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  ]),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Text("${urun['marka']} ${urun['model']}",
                style: const TextStyle(fontWeight: FontWeight.bold), textAlign: TextAlign.center),
            Text("Mevcut Stok: $mevcutAdet Adet", style: const TextStyle(color: Colors.grey)),
            const SizedBox(height: 20),
            TextField(
              controller: miktarC,
              keyboardType: TextInputType.number,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: "Sevk Edilecek Adet",
                hintText: "Miktar girin",
                border: OutlineInputBorder(),
                suffixText: "Adet",
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("İPTAL", style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blue[900]),
            onPressed: () async {
              double sevkMiktari = double.tryParse(miktarC.text.replaceAll(',', '.')) ?? 0;

              if (sevkMiktari <= 0 || sevkMiktari > mevcutAdet) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Hatalı miktar!"), backgroundColor: Colors.red),
                );
                return;
              }

              try {
                final db = await DatabaseHelper.instance.database;
                String? urunFirebaseId = urun['firebase_id']?.toString();

                // 🔥 ANA STOK ID BELİRLEME: Mevcut üründe yoksa kendi ID'sini ana_stok_id yap
                int anaStokId = urun['ana_stok_id'] != null
                    ? int.parse(urun['ana_stok_id'].toString())
                    : urun['id'];

                // 1. ÇIKIŞ ŞUBESİ STOK DÜŞÜR
                await db.update(
                  'stoklar',
                  {'adet': mevcutAdet - sevkMiktari, 'is_synced': 0, 'ana_stok_id': anaStokId},
                  where: 'id = ?',
                  whereArgs: [urun['id']],
                );

                if (urunFirebaseId != null && urunFirebaseId != "hükümsüz") {
                  await FirebaseFirestore.instance
                      .collection('stoklar')
                      .doc(urunFirebaseId)
                      .update({'adet': mevcutAdet - sevkMiktari, 'ana_stok_id': anaStokId});
                }

                // 2. HEDEF ŞUBE KONTROL / EKLEME
                final List<Map<String, dynamic>> hedefKontrol = await db.query(
                  'stoklar',
                  where: 'marka = ? AND model = ? AND alt_model = ? AND sube = ?',
                  whereArgs: [urun['marka'], urun['model'], urun['alt_model'], hedefSube],
                );

                if (hedefKontrol.isNotEmpty) {
                  // Hedef şubede zaten bu mal varsa sadece miktar artır
                  double eskiAdet = double.tryParse(hedefKontrol.first['adet'].toString()) ?? 0;
                  String? hedefFirebaseId = hedefKontrol.first['firebase_id']?.toString();

                  await db.update(
                    'stoklar',
                    {'adet': eskiAdet + sevkMiktari, 'is_synced': 0, 'ana_stok_id': anaStokId},
                    where: 'id = ?',
                    whereArgs: [hedefKontrol.first['id']],
                  );

                  if (hedefFirebaseId != null && hedefFirebaseId != "hükümsüz") {
                    await FirebaseFirestore.instance
                        .collection('stoklar')
                        .doc(hedefFirebaseId)
                        .update({'adet': eskiAdet + sevkMiktari, 'ana_stok_id': anaStokId});
                  }
                } else {
                  // Hedef şubede yoksa YENİ KAYIT aç ama ANA ID'Yİ KORU
                  var yeniSubeKaydi = Map<String, dynamic>.from(urun);
                  yeniSubeKaydi.remove('id');
                  yeniSubeKaydi['firebase_id'] = null; // SQLite UNIQUE hatası vermesin diye

                  yeniSubeKaydi['ana_stok_id'] = anaStokId; // 🔥 KİMLİĞİ KORUDUK
                  yeniSubeKaydi['sube'] = hedefSube;
                  yeniSubeKaydi['adet'] = sevkMiktari;
                  yeniSubeKaydi['is_synced'] = 0;

                  int yeniId = await db.insert('stoklar', yeniSubeKaydi);

                  // Firebase Sync
                  DocumentReference docRef = await FirebaseFirestore.instance.collection('stoklar').add({
                    ...yeniSubeKaydi,
                    'ana_stok_id': anaStokId
                  });

                  await db.update('stoklar', {'firebase_id': docRef.id}, where: 'id = ?', whereArgs: [yeniId]);
                }

                await _verileriYukle();
                if (context.mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Transfer Başarılı ✅")));
                }
              } catch (e) {
                debugPrint("Transfer Hatası: $e");
              }
            },
            child: const Text("ONAYLA", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Future<void> _verileriYukle() async {
    // 1. ni çek
    final stoklar = await DatabaseHelper.instance.stokListesiGetir();

    // 2. 🔥 KATEGORİLERİ DE ÇEK (EKSİK OLAN BURASIYDI)
    // Diğer sayfadaki gibi kütüphaneyi burada da güncelliyoruz
    final tazeKategoriler = await DatabaseHelper.instance.kategorileriGetirGaranti();

    if (mounted) {
      setState(() {
        _asilListe = List.from(stoklar);
        _kategoriler = tazeKategoriler; // Kategoriler artık bu sayfada da güncel
        _listeyiYenile();
      });
    }
  }

  Future<void> _firebaseSenkronizeEt() async {
    try {
      final db = await DatabaseHelper.instance.database;

      final snapshot = await FirebaseFirestore.instance
          .collection('stoklar')
          .get();

      debugPrint("🔥 Firebase'den ${snapshot.docs.length} adet kayıt geldi.");

      for (var doc in snapshot.docs) {
        final data = doc.data();

        String firestoreId = doc.id;

        // 🔥 1. ÖNCE VAR MI KONTROL ET
        final existing = await db.query(
          'stoklar',
          where: 'firebase_id = ?',
          whereArgs: [firestoreId],
        );

        if (existing.isNotEmpty) {
          continue; // 🔥 zaten var → tekrar ekleme
        }

        // 🔥 2. VERİ HAZIRLA
        String marka = (data['marka'] ?? '').toString().toUpperCase();
        String model = (data['model'] ?? '').toString().toUpperCase();
        String urunAdi = (data['urun'] ?? "$marka $model").toString().toUpperCase();

        Map<String, dynamic> veri = {
          'firebase_id': firestoreId,
          'urun': urunAdi,
          'marka': marka,
          'model': model,
          'alt_model': (data['alt_model'] ?? '').toString(),
          'ana_stok_id': data['ana_stok_id'], // 🔥 İŞTE BURASI! Firebase'deki ana ID'yi de yerele alıyoruz.
          'kategori': (data['kategori'] ?? 'GENEL').toString().toUpperCase(),
          'adet': double.tryParse(data['adet']?.toString() ?? '1') ?? 1.0,
          'fiyat': double.tryParse(data['fiyat']?.toString() ?? '0') ?? 0.0,
          'sube': (data['sube'] ?? 'TEFENNİ').toString().toUpperCase(),
          'durum': (data['durum'] ?? 'SIFIR').toString().toUpperCase(),
        };

        // 🔥 3. INSERT
        await db.insert(
          'stoklar',
          veri,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }

      await _verileriYukle();

    } catch (e) {
      debugPrint("⚠️ Firebase Hatası: $e");
    }
  }

  void _listeyiYenile() {
    setState(() {
      String arama = _araC.text.trim().toUpperCase();
      _filtreli = _asilListe.where((s) {
        bool subeUyuyor = (_aktifFiltreSube == 2) ||
            (_aktifFiltreSube == 0 && s['sube'].toString().toUpperCase() == "TEFENNİ") ||
            (_aktifFiltreSube == 1 && s['sube'].toString().toUpperCase() == "AKSU");

        // Bütün alanları birleştirip öyle arama yapıyoruz
        String urunAdi = (s['urun'] ?? '').toString().toUpperCase();
        String marka = (s['marka'] ?? '').toString().toUpperCase();
        String model = (s['model'] ?? '').toString().toUpperCase();
        String alt = (s['alt_model'] ?? s['altmodel'] ?? '').toString().toUpperCase();

        bool aramaUyuyor = urunAdi.contains(arama) ||
            marka.contains(arama) ||
            model.contains(arama) ||
            alt.contains(arama);

        double adet = double.tryParse(s['adet']?.toString() ?? "0") ?? 0;

        // Sadece şube ve arama değil, adetin 0'dan büyük olması şartını ekle:
        return subeUyuyor && aramaUyuyor && adet > 0;
      }).toList();
    });
  }

  // Toplam Tutar Hesaplama (Filtreli Liste Üzerinden)
  double get _toplamStokDegeri {
    double toplam = 0;
    for (var s in _filtreli) {
      double adet = double.tryParse(s['adet']?.toString() ?? "0") ?? 0;
      double fiyat = double.tryParse(s['fiyat']?.toString() ?? "0") ?? 0;
      toplam += (adet * fiyat);
    }
    return toplam;
  }

  @override
  Widget build(BuildContext context) {
    final Color anaRenk = widget.seciliSube == 0 ? Colors.green[800]! : Colors.blue[900]!;

    return Scaffold(
      backgroundColor: Colors.grey[200],
      appBar: AppBar(
        title: const Text("STOK GİRİŞİ"),
        backgroundColor: anaRenk,
        foregroundColor: Colors.white,
        actions: [
          // 🔥 İSTEDİĞİN FOTOĞRAF KLASÖRÜ BURADA
          IconButton(
            icon: const Icon(Icons.folder_open, size: 28),
            onPressed: () => _tumFotolariGoster(),
          ),
          const SizedBox(width: 10),
        ],
      ),
      body: Column(
        children: [
          // 1. ÖZET PANELİ (GÜNCELLENDİ: GİZLİ TUTAR EKLENDİ)
          Container(
            padding: const EdgeInsets.all(15), color: Colors.white,
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
              _ozetKutu("ÇEŞİT", "${_filtreli.length}", Colors.blue),
              _ozetKutu(
                  "TOPLAM ADET",
                  _filtreli.fold<num>(0, (p, e) => p + (num.tryParse(e['adet'].toString()) ?? 0)).toString(),
                  Colors.orange
              ),
              // 🔥 GİZLİ TOPLAM TUTAR (DOKUNUNCA AÇILIR)
              GestureDetector(
                onTap: () => setState(() => _tutarGozuksun = !_tutarGozuksun),
                child: _ozetKutu(
                    "TOPLAM TUTAR (GİZLİ)",
                    _tutarGozuksun
                        ? NumberFormat.currency(locale: "tr_TR", symbol: "₺").format(_toplamStokDegeri)
                        : "****** ₺",
                    Colors.green[700]!
                ),
              ),
            ]),
          ),

          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              _ustButon("STOK GİRİŞ", Icons.add_box, Colors.orange[800]!, () {
                Navigator.push(
                    context,
                    MaterialPageRoute(builder: (c) => AlisIslemSayfasi(seciliSube: widget.seciliSube))
                ).then((_) => _verileriYukle()); // BURASI ÇOK ÖNEMLİ: Geri gelince listeyi tazelemeli!
              }),
              _ustButon("STOK TANIMLA EVREN", Icons.app_registration, Colors.purple[700]!, () async {
                // Önce gerekli verileri hazırlıyoruz
                final firmalar = await DatabaseHelper.instance.tarimFirmaListesiGetir();
                final tanimlar = await DatabaseHelper.instance.stokTanimlariniGetir();

                if (context.mounted) {
                  Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (c) => StokTanimlaSayfasi(
                              mevcutFirmalar: firmalar,
                              tanimliStoklar: tanimlar,
                              onKaydet: (yeni) {
                                _verileriYukle();
                              }
                          )
                      )
                  ).then((_) {
                    // Sayfadan geri çıkınca ana sayfayı tazele
                    _verileriYukle();
                  });
                }
              }),
              const SizedBox(width: 8),
              _ustButon("RAPOR", Icons.picture_as_pdf, Colors.teal[700]!, () => _pdfOnizlemeGoster(context)),
            ]),
          ),

          _subeSecimBar(),
          _aramaCubugu(),

          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 15, vertical: 8),
            child: Align(alignment: Alignment.centerLeft, child: Text("MEVCUT STOKLAR (SADECE VARDA OLANLAR)", style: TextStyle(fontWeight: FontWeight.bold))),
          ),

          Expanded(child: _stokListesi(anaRenk)),
        ],
      ),
    );
  }
  void _pdfOnizlemeGoster(BuildContext context) async {
    final pdf = pw.Document();

    // 1. Yazı Tipleri (Türkçe karakterler için)
    final font = await PdfGoogleFonts.robotoRegular();
    final boldFont = await PdfGoogleFonts.robotoBold();

    // 2. Logo Yükleme (assets içinde logo.png olduğunu varsayıyoruz)
    // Eğer logo dosya yolun farklıysa burayı düzelt abi
    final ByteData bytes = await rootBundle.load('assets/images/logo.png');
    final Uint8List byteList = bytes.buffer.asUint8List();
    final logoResmi = pw.MemoryImage(byteList);

    // 3. TL Formatlayıcı (Parayı 1.500,00 ₺ şeklinde yazar)
    final formatTR = NumberFormat.currency(locale: "tr_TR", symbol: "₺");

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        theme: pw.ThemeData.withFont(base: font, bold: boldFont),
        build: (pw.Context context) => [
          // --- LOGO VE BAŞLIK ---
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Row(
                children: [
                  pw.Container(width: 50, height: 50, child: pw.Image(logoResmi)),
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
                  pw.Text("GÜNCEL STOK RAPORU",
                      style: pw.TextStyle(font: boldFont, fontSize: 12)),
                  pw.Text("Tarih: ${DateFormat('dd.MM.yyyy').format(DateTime.now())}",
                      style: pw.TextStyle(fontSize: 10)),
                ],
              ),
            ],
          ),
          pw.Divider(thickness: 2, color: PdfColors.blue900),
          pw.SizedBox(height: 15),

          // --- TABLO ---
          pw.TableHelper.fromTextArray(
            headers: ['MARKA / MODEL', 'ADET', 'SUBE', 'BİRİM FİYAT'],
            headerStyle: pw.TextStyle(font: boldFont, color: PdfColors.white),
            headerDecoration: const pw.BoxDecoration(color: PdfColors.blue900),
            cellAlignment: pw.Alignment.centerLeft,
            // Sütun genişliklerini ayarla (Ürün ismi daha geniş olsun)
            columnWidths: {
              0: const pw.FlexColumnWidth(4),
              1: const pw.FlexColumnWidth(1),
              2: const pw.FlexColumnWidth(2),
              3: const pw.FlexColumnWidth(2),
            },
            data: _filtreli.map((s) {
              double fiyat = double.tryParse(s['fiyat']?.toString() ?? "0") ?? 0;
              return [
                "${s['marka'] ?? ''} ${s['model'] ?? ''} ${s['alt_model'] ?? ''}".trim(),
                s['adet']?.toString() ?? '0',
                s['sube'] ?? '-',
                formatTR.format(fiyat), // ₺ Formatı burada basılıyor
              ];
            }).toList(),
          ),

          pw.SizedBox(height: 20),

          // --- TOPLAM TUTAR BİLGİSİ ---
          pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Container(
              padding: const pw.EdgeInsets.all(8),
              decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.grey400),
                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4))
              ),
              child: pw.Text(
                "GENEL TOPLAM: ${formatTR.format(_toplamStokDegeri)}",
                style: pw.TextStyle(font: boldFont, fontSize: 13, color: PdfColors.blue900),
              ),
            ),
          ),
        ],
      ),
    );

    // Önizleme Ekranına Gönder
    if (mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => Scaffold(
            appBar: AppBar(
              title: const Text("PDF ÖNİZLEME"),
              backgroundColor: Colors.blueGrey[900],
            ),
            body: PdfPreview(
              build: (format) => pdf.save(),
              canDebug: false, // Kenardaki kırmızı debug çizgilerini kapatır
              pdfFileName: "Evren_Tarim_Stok_Listesi.pdf",
            ),
          ),
        ),
      );
    }
  }




  void _stokGuncelle(Map<String, dynamic> urun) {
    final TextEditingController adetC = TextEditingController(text: urun['adet'].toString());
    final TextEditingController fiyatC = TextEditingController(text: urun['fiyat'].toString());
    showDialog(context: context, builder: (context) => AlertDialog(
      title: Text("${urun['marka']} ${urun['model']} DÜZENLE"),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: adetC, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: "Yeni Adet")),
        const SizedBox(height: 10),
        TextField(controller: fiyatC, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: "Yeni Birim Fiyat (₺)")),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text("İPTAL")),
        // ElevatedButton içindeki onPressed kısmı:
        ElevatedButton(
            onPressed: () async {
              double yeniAdet = double.tryParse(adetC.text) ?? 0;
              double yeniFiyat = double.tryParse(fiyatC.text.replaceAll(',', '.')) ?? 0;

              // 1. SQL Güncelle
              await DatabaseHelper.instance.stokGuncelle(urun['id'], yeniAdet.toInt(), yeniFiyat, urun['tarim_firmalari'] ?? '');

              // 2. FIREBASE GÜNCELLE
              if (urun['firebase_id'] != null) {
                await FirebaseFirestore.instance
                    .collection('stoklar')
                    .doc(urun['firebase_id'])
                    .update({
                  'adet': yeniAdet,
                  'fiyat': yeniFiyat,
                });
              }

              await _verileriYukle();
              if (mounted) Navigator.pop(context);
            },
            child: const Text("GÜNCELLE")
        )
      ],
    ));
  }

  void _stokSil(int id) async {
    // Onay penceresi
    bool? onay = await showDialog(
        context: context,
        builder: (c) => AlertDialog(
            title: const Text("Kayıt Silinsin mi?"),
            content: const Text("Bu stok kaydı silindiğinde firmanın bakiyesi de güncellenecektir. Emin misiniz?"),
            actions: [
              TextButton(onPressed: () => Navigator.pop(c), child: const Text("İPTAL")),
              TextButton(
                  onPressed: () => Navigator.pop(c, true),
                  child: const Text("SİL", style: TextStyle(color: Colors.red))
              )
            ]
        )
    );

    if (onay == true) {
      // Senin yazdığın o meşhur fonksiyonu çağırıyoruz
      // Bu fonksiyon içeride hem SQL'i silecek, hem borcu düşecek, hem Firebase'i temizleyecek.
      await DatabaseHelper.instance.stokSil(id);

      // Listeyi yenile
      await _verileriYukle();

      if(mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Ürün ve ilgili bakiye güncellendi ✅"))
        );
      }
    }
  }

  Widget _subeSecimBar() => Row(mainAxisAlignment: MainAxisAlignment.center, children: [_fChip("TEFENNİ", 0), const SizedBox(width: 5), _fChip("AKSU", 1), const SizedBox(width: 5), _fChip("HEPSİ", 2)]);
  Widget _aramaCubugu() => Padding(padding: const EdgeInsets.all(12), child: TextField(controller: _araC, onChanged: (_) => _listeyiYenile(), decoration: InputDecoration(hintText: "Marka/Model Ara...", prefixIcon: const Icon(Icons.search), filled: true, fillColor: Colors.white, border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)))));
  Widget _stokListesi(Color anaRenk) => ListView.builder(
    itemCount: _filtreli.length,
    itemBuilder: (context, index) {
      final s = _filtreli[index];
      return Card(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Stack(
          children: [
            ListTile(
              onTap: () => _stokGuncelle(s),
              leading: GestureDetector(
                onTap: () => _fotoGuncelle(s), // 🔥 Index yerine s gönderdik, hata bitti.
                child: Container(
                  width: 55, height: 55,
                  decoration: BoxDecoration(
                    color: Colors.grey[200],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey[400]!),
                  ),
                  child: Builder(builder: (context) {
                    final String yol = (s['foto_yolu'] ?? s['foto'] ?? "").toString();
                    if (yol.isEmpty || !File(yol).existsSync()) {
                      return const Icon(Icons.camera_alt, color: Colors.grey);
                    }
                    return ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.file(File(yol), fit: BoxFit.cover),
                    );
                  }),
                ),
              ),
              title: Text("${s['marka'] ?? ''} ${s['model'] ?? ''}".trim(), style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 4),
                  Text("Şube: ${s['sube']} | Adet: ${s['adet']} | ${s['fiyat']} TL",
                      style: TextStyle(fontSize: 12, color: Colors.grey[700])),
                ],
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(icon: const Icon(Icons.swap_horiz, color: Colors.blue, size: 24), onPressed: () => _subeTransfer(s)),
                  IconButton(icon: const Icon(Icons.delete, color: Colors.red, size: 20), onPressed: () => _stokSil(s['id'])),
                ],
              ),
            ),

            // --- SAĞ ÜST KÖŞEDEKİ BÜYÜTME BUTONU ---
            if ((s['foto_yolu'] ?? s['foto'] ?? "").toString().isNotEmpty)
              Positioned(
                top: 0, right: 0,
                child: GestureDetector(
                  onTap: () {
                    final path = (s['foto_yolu'] ?? s['foto']).toString();
                    _resmiBuyut(path, "${s['marka']} ${s['model']}");
                  },
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.purple.withOpacity(0.1),
                      borderRadius: const BorderRadius.only(topRight: Radius.circular(10), bottomLeft: Radius.circular(10)),
                    ),
                    child: const Icon(Icons.fullscreen, color: Colors.purple, size: 22),
                  ),
                ),
              ),
          ],
        ),
      );
    },
  );


  Future<void> _fotoGuncelle(Map<String, dynamic> urun) async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.camera, imageQuality: 50);

    if (image != null) {
      try {
        // 1. Dosya Hazırlığı
        final directory = await getApplicationDocumentsDirectory();
        final String dosyaAdi = "stok_${urun['id']}_${DateTime.now().millisecondsSinceEpoch}.jpg";
        final String kaliciYol = "${directory.path}/$dosyaAdi";

        // 2. Fotoğrafı Kalıcı Klasöre Kopyala
        await File(image.path).copy(kaliciYol);

        // 3. SQL'E HEMEN YAZ (İnternet olmasa da burada kalsın)
        await DatabaseHelper.instance.stokFotoGuncelle(
            urun['id'],
            kaliciYol
        );

        // 4. FIREBASE'E ATMAYA ÇALIŞ (Hata alsa da SQL'deki silinmez)
        try {
          await FirebaseFirestore.instance
              .collection('stoklar')
              .doc(urun['firebase_id'])
              .update({'foto': kaliciYol});
        } catch (e) {
          debugPrint("Firebase bağlantı hatası (Önemli değil, SQL'e yazıldı): $e");
        }

        // 5. Arayüzü tazele
        await _verileriYukle();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text("Fotoğraf kaydedildi (Çevrimdışı mod aktif) ✅"))
          );
        }
      } catch (e) {
        debugPrint("Kritik Hata: $e");
      }
    }
  }

  void _tumFotolariGoster() async {
    // Önce veritabanından en güncel halini çekelim ki yeni çekilen hemen görünsün
    final guncelStoklar = await DatabaseHelper.instance.stokListesiGetir();

    final fotoluUrunler = guncelStoklar.where((s) {
      final yol = (s['foto'] ?? "").toString();
      return yol.isNotEmpty && File(yol).existsSync();
    }).toList();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) => Column(
          children: [
            const SizedBox(height: 10),
            Container(width: 40, height: 5, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(10))),
            const Padding(
              padding: EdgeInsets.all(15),
              child: Text("STOK FOTOĞRAF ARŞİVİ", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            ),
            Expanded(
              child: fotoluUrunler.isEmpty
                  ? const Center(child: Text("Henüz fotoğraf eklenmemiş."))
                  : GridView.builder(
                controller: scrollController,
                padding: const EdgeInsets.all(10),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3, crossAxisSpacing: 8, mainAxisSpacing: 8),
                itemCount: fotoluUrunler.length,
                itemBuilder: (c, i) {
                  final path = fotoluUrunler[i]['foto'].toString();
                  return GestureDetector(
                    onTap: () => _resmiBuyut(path, "${fotoluUrunler[i]['marka']} ${fotoluUrunler[i]['model']}"),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.file(File(path), fit: BoxFit.cover),
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

  void _resmiBuyut(String dosyaYolu, String baslik) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent, // Arka planı şeffaf yapalım
        insetPadding: const EdgeInsets.all(10), // Kenarlardan az boşluk kalsın
        child: Stack(
          alignment: Alignment.center,
          children: [
            // 1. Resmin Kendisi
            InteractiveViewer( // Kullanıcı parmağıyla resmi yakınlaştırabilir
              panEnabled: true,
              minScale: 0.5,
              maxScale: 4.0,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(15),
                child: Image.file(
                  File(dosyaYolu),
                  fit: BoxFit.contain,
                ),
              ),
            ),
            // 2. Kapatma Butonu (Sağ Üstte)
            Positioned(
              top: 10,
              right: 10,
              child: CircleAvatar(
                backgroundColor: Colors.black54,
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
            ),
            // 3. Alt Bilgi (Ürün Adı)
            Positioned(
              bottom: 20,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  baslik,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }


  Widget _ustButon(String l, IconData i, Color c, VoidCallback t) => Expanded(child: ElevatedButton.icon(style: ElevatedButton.styleFrom(backgroundColor: c, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 12)), onPressed: t, icon: Icon(i, size: 18), label: Text(l, style: const TextStyle(fontSize: 11))));
  Widget _fChip(String l, int i) => ChoiceChip(label: Text(l), selected: _aktifFiltreSube == i, onSelected: (v) { if(v) setState(() { _aktifFiltreSube = i; _listeyiYenile(); }); });
  Widget _ozetKutu(String b, String d, Color r) => Column(children: [Text(b, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)), Text(d, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: r))]);
}
