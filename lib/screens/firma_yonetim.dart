
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// Veri İşleme ve Formatlama
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// PDF ve Yazdırma İşlemleri
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

// Dosya Yönetimi, Paylaşım ve Kamera
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
// Yerel Veritabanı
import '../db/database_helper.dart';
import 'dart:convert'; // Resim dönüştürme için şart
import 'firmahareketler.dart';
import 'package:flutter/foundation.dart' show kIsWeb; //
import 'dart:io' as io; // File hatasını engellemek için 'as io' dedik[cite: 1]
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'dart:io' show File;

class FirmaTanimSayfasi extends StatefulWidget {
  const FirmaTanimSayfasi({super.key});

  @override
  State<FirmaTanimSayfasi> createState() => _FirmaTanimSayfasiState();
}

class _FirmaTanimSayfasiState extends State<FirmaTanimSayfasi> {
  List<Map<String, dynamic>> _firmalar = [];
  List<Map<String, dynamic>> _filtreliFirmalar = [];
  final TextEditingController _aramaC = TextEditingController();

  double toplamBorc = 0;
  double toplamAlacak = 0;

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














  Widget buildImage(String path) {
    if (kIsWeb) {
      return Image.network(path); // web
    } else {
      return Image.file(File(path)); // mobil
    }
  }

  Future<void> _verileriYukle() async {
    // 1. Veritabanından gelen listeyi alıyoruz
    final veriler = await DatabaseHelper.instance.tarimFirmaListesiGetir();

    double b = 0; // Toplam Borcumuz (Kırmızı Kutu)
    double a = 0; // Toplam Alacak (Yeşil Kutu)

    // 2. Tekilleştirme mantığı
    final Map<String, Map<String, dynamic>> filtreliMap = {};

    if (veriler.isNotEmpty) {
      for (var f in veriler) {
        String idKey = f['id'].toString();

        if (!filtreliMap.containsKey(idKey)) {
          filtreliMap[idKey] = f;

          // SQL'den gelen bakiye değerini alıyoruz
          double bakiye = double.tryParse(f['bakiye']?.toString() ?? '0') ?? 0.0;

          // TOPLAM HESAPLAMA MANTIĞI:
          // Eğer bakiye 0'dan büyükse bu bizim firmaya olan toplam BORCUMUZDUR.
          if (bakiye > 0) {
            b += bakiye;
          }
          // Eğer bakiye 0'dan küçükse bu bizim firmadan olan ALACAĞIMIZDIR.
          else if (bakiye < 0) {
            a += bakiye.abs(); // Eksi değeri artıya çevirip alacağa ekliyoruz
          }
        }
      }
    }

    setState(() {
      // 3. Ekrana verileri basıyoruz
      _firmalar = filtreliMap.values.toList();
      _filtreliFirmalar = _firmalar;
      toplamBorc = b;    // Üstteki kırmızı kutuyu doldurur
      toplamAlacak = a;  // Üstteki yeşil kutuyu doldurur
    });
  }

  // Hata aldığın fonksiyon BURADA başlamalı:
  void _filtrele(String kelime) {
    setState(() {
      _filtreliFirmalar = _firmalar
          .where((f) => f['ad'].toString().toLowerCase().contains(kelime.toLowerCase()))
          .toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    // BURADAKİ HATALI _hareketler DÖNGÜSÜNÜ SİLDİK.
    // Çünkü bu ana sayfa, tüm firmaların toplamını gösterir.

    return Scaffold(
      backgroundColor: Colors.grey[200],
      appBar: AppBar(
        title: const Text("FİRMA İŞLEMLERİ"),
        backgroundColor: Colors.indigo[900],
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          _ozetPanel(), // Bu zaten aşağıda tanımlı, toplamBorc ve toplamAlacak'ı kullanıyor
          _aksiyonBar(),
          _aramaCubugu(),
          Expanded(
            child: _filtreliFirmalar.isEmpty
                ? const Center(child: Text("Firma bulunamadı."))
                : ListView.builder(
              itemCount: _filtreliFirmalar.length,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              itemBuilder: (context, index) => _firmaKart(_filtreliFirmalar[index]),
            ),
          ),
        ],
      ),
    );
  }

  // --- ÜST ÖZET PANEL ---
  Widget _ozetPanel() => Container(
    padding: const EdgeInsets.all(15),
    color: Colors.indigo[900],
    child: Row(
      children: [
        _ozetKutu("TOPLAM BORCUMUZ", toplamBorc, Colors.red[300]!),
        const SizedBox(width: 10),
        _ozetKutu("TOPLAM ALACAK", toplamAlacak, Colors.green[300]!),
      ],
    ),
  );

  Widget _ozetKutu(String t, double m, Color c) => Expanded(
    child: Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
      child: Column(children: [
        Text(t, style: TextStyle(color: c, fontSize: 11, fontWeight: FontWeight.bold)),
        const SizedBox(height: 5),
        // BURAYI DEĞİŞTİRDİK: locale: 'tr_TR' ekledik
        Text("${NumberFormat.currency(locale: 'tr_TR', symbol: '', decimalDigits: 2).format(m)} ₺",
            style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
      ]),
    ),
  );

  Widget _aksiyonBar() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 5),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Colors.grey.shade300, width: 1)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _ustButon(Icons.add_business, "Firma Ekle", Colors.blue[900]!, () => _firmaFormDialog(null)),
          _ustButon(Icons.account_balance_wallet, "Ödeme Yap", Colors.red[800]!, () => _hizliSecimDialog("ÖDEME")),
          _ustButon(Icons.assignment, "Ekstreler", Colors.orange[900]!, () => _hizliSecimDialog("EKSTRE")),
          _ustButon(Icons.add_a_photo, "Fatura Foto", Colors.purple[800]!, () => _faturaFotoEkle()),
        ],
      ),
    );
  }

  Widget _ustButon(IconData ikon, String etiket, Color renk, VoidCallback gorev) {
    return InkWell(
      onTap: gorev,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: renk.withOpacity(0.1), shape: BoxShape.circle),
            child: Icon(ikon, color: renk, size: 28),
          ),
          const SizedBox(height: 6),
          Text(etiket, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey[800])),
        ],
      ),
    );
  }

  Widget _aramaCubugu() => Padding(
    padding: const EdgeInsets.all(10),
    child: TextField(
      controller: _aramaC,
      onChanged: _filtrele,
      decoration: InputDecoration(
        hintText: "Firma ara...",
        prefixIcon: const Icon(Icons.search),
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
      ),
    ),
  );

  Widget _firmaKart(Map<String, dynamic> f) {
    // 1. Verileri çekiyoruz
    // ÖNEMLİ: f['bakiye'] döküm sayfasındaki (Mal Alımı - Ödeme) sonucunu temsil etmeli
    double bakiye = double.tryParse(f['bakiye']?.toString() ?? '0') ?? 0.0;
    return Card(
      elevation: 2,
      margin: const EdgeInsets.symmetric(vertical: 5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ExpansionTile(
        leading: CircleAvatar(
          backgroundColor: Colors.indigo[900],
          child: Text(f['ad'] != null && f['ad'].isNotEmpty ? f['ad'][0] : "?",
              style: const TextStyle(color: Colors.white)),
        ),
        title: Text(f['ad'] ?? "İsimsiz Firma", style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text("Yetkili: ${f['yetkili'] ?? '-'}"),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.collections, color: Colors.orange, size: 28),
              onPressed: () => _faturaGalerisiniAc(f),
            ),
            const SizedBox(width: 8),
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  // Tutarı her zaman mutlak değer (abs) olarak pozitif gösteriyoruz
                  NumberFormat.currency(locale: 'tr_TR', symbol: '₺', decimalDigits: 2).format(bakiye.abs()),
                  style: TextStyle(
                    // ARTI bakiye borçtur (Kırmızı), EKSİ bakiye alacaktır (Yeşil)
                      color: bakiye > 0 ? Colors.red[900] : (bakiye < 0 ? Colors.green[800] : Colors.black),
                      fontWeight: FontWeight.bold,
                      fontSize: 16
                  ),
                ),
                Text(
                  // Yazıyı da tam tersine çevirdik:
                  bakiye > 0 ? "FİRMAYA BORÇLUYUM" : (bakiye < 0 ? "FİRMADAN ALACAKLIYIM" : "BAKİYE SIFIR"),
                  style: TextStyle(
                      color: bakiye > 0 ? Colors.red[900] : (bakiye < 0 ? Colors.green[800] : Colors.grey),
                      fontSize: 9,
                      fontWeight: FontWeight.bold
                  ),
                ),
              ],
            ),
          ],
        ),
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("📍 Adres: ${f['adres'] ?? 'Girilmemiş'}"),
                Text("🚜 Araç: ${f['marka'] ?? ''} ${f['model'] ?? ''}"),
                const Divider(),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _kucukAksiyonButon(Icons.list_alt, "Ekstre", Colors.teal, () => _ekstreyeGit(f)),
                    _kucukAksiyonButon(Icons.camera_alt, "Foto", Colors.purple, () => _direktFotoCek(f)),
                    _kucukAksiyonButon(Icons.collections, "Galeri", Colors.orange, () => _faturaGalerisiniAc(f)),
                    _kucukAksiyonButon(Icons.edit, "Düzenle", Colors.blue, () => _firmaFormDialog(f)),
                    _kucukAksiyonButon(Icons.delete, "Sil", Colors.red, () => _firmaSilOnay(f['id'])),
                  ],
                )
              ],
            ),
          )
        ],
      ),
    );
  }

  // Kart içi buton tasarımı
  Widget _kucukAksiyonButon(IconData ikon, String etiket, Color renk, VoidCallback tap) {
    return InkWell(
      onTap: tap,
      child: Column(
        children: [
          Icon(ikon, color: renk, size: 22),
          const SizedBox(height: 4),
          Text(etiket, style: TextStyle(fontSize: 10, color: Colors.grey[700])),
        ],
      ),
    );
  }
  Future<void> _direktFotoCek(Map<String, dynamic> firma) async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.camera, imageQuality: 70);

    if (image != null) {
      _faturayiKaydet(image.path, firma['id']);
    }
  }
  void _firmaSilOnay(int id) async {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        title: const Text("Firmayı Sil"),
        content: const Text("Bu firmaya ait TÜM borç, alacak ve kayıtlar hem telefondan hem buluttan silinecektir. Emin misiniz?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("VAZGEÇ")),
          ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () async {
                // 1. Silme motorunu çalıştır
                await DatabaseHelper.instance.firmaSil(id);

                // 2. Pencereyi kapat
                if (context.mounted) Navigator.pop(context);

                // 3. Listeyi yenile ve mesaj ver
                _verileriYukle();
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("Firma ve tüm bulut kayıtları temizlendi ✅"))
                );
              },
              child: const Text("SİL", style: TextStyle(color: Colors.white))
          ),
        ],
      ),
    );
  }

  void _firmaFormDialog(Map<String, dynamic>? f) {
    final adC = TextEditingController(text: f?['ad']);
    final yetkiliC = TextEditingController(text: f?['yetkili']);
    final telC = TextEditingController(text: f?['tel']);
    final adresC = TextEditingController(text: f?['adres']);
    final kategoriC = TextEditingController(text: f?['kategori']);
    final markaC = TextEditingController(text: f?['marka']);
    final modelC = TextEditingController(text: f?['model']);
    final altModelC = TextEditingController(text: f?['altModel'] ?? f?['alt_model']);

    // Durum seçimi için değişken (Varsayılan SIFIR)
    String durum = f?['durum'] ?? "SIFIR";

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder( // Dropdown'ın anlık değişmesi için gerekli
        builder: (context, setS) => AlertDialog(
          title: Text(f == null ? "YENİ KAYIT" : "KAYIT GÜNCELLE"),
          content: SizedBox(
            width: MediaQuery.of(context).size.width * 0.8,
            child: SingleChildScrollView(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // SOL TARAF: FİRMA BİLGİLERİ
                  Expanded(
                    child: Column(
                      children: [
                        const Text("FİRMA BİLGİLERİ", style: TextStyle(fontWeight: FontWeight.bold)),
                        const Divider(),
                        _input(adC, "Firma Ünvanı"),
                        _input(yetkiliC, "Yetkili Ad Soyad"),
                        _input(telC, "Telefon", keyboard: TextInputType.phone),
                        _input(adresC, "Adres", lines: 3),
                      ],
                    ),
                  ),
                  const VerticalDivider(width: 30),
                  // SAĞ TARAF: STOK / DURUM / KATAGORİ
                  Expanded(
                    child: Column(
                      children: [
                        const Text("STOK TANIMI VE DURUM", style: TextStyle(fontWeight: FontWeight.bold)),
                        const Divider(),
                        // DURUM SEÇİMİ (SIFIR / 2.EL)
                        DropdownButtonFormField<String>(
                          value: durum,
                          decoration: const InputDecoration(labelText: "Ürün Durumu", border: OutlineInputBorder()),
                          items: ["SIFIR", "2. EL"].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                          onChanged: (v) => setS(() => durum = v!),
                        ),
                        const SizedBox(height: 10),
                        _input(kategoriC, "Kategori (Örn: Traktör, Römork)"),
                        _input(markaC, "Marka"),
                        _input(modelC, "Model"),
                        _input(altModelC, "alt_model / Detay"),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text("VAZGEÇ")),
            ElevatedButton(
              onPressed: () async {
                // 1. Veriyi hazırla (İki ismi birden ekleyerek garantiye alıyoruz)
                String altDegeri = altModelC.text.toUpperCase().trim();

                // _firmaFormDialog içindeki ElevatedButton'un içini böyle yap:
                Map<String, dynamic> v = {
                  'ad': adC.text.toUpperCase().trim(),
                  'yetkili': yetkiliC.text.trim(),
                  'tel': telC.text.trim(),
                  'adres': adresC.text.trim(),
                  'kategori': kategoriC.text.toUpperCase().trim(),
                  'durum': durum,
                  'marka': markaC.text.toUpperCase().trim(),
                  'model': modelC.text.toUpperCase().trim(),
                  'alt_model': altModelC.text.toUpperCase().trim(), // Tek isim kullan: alt_model
                };

                if (f == null) {
                  // 2. Firmayı ekle
                  await DatabaseHelper.instance.tarimFirmaEkle({
                    ...v,
                    'borc': 0.0,
                    'alacak': 0.0
                  });

                  // 3. Stok kütüphanesine (tanımlara) ekle
                  if (markaC.text.isNotEmpty) {
                    await DatabaseHelper.instance.stokTanimEkle({
                      // 1. KATEGORİ (Tabloda 2. sırada, ID'den sonra)
                      'kategori': kategoriC.text.toUpperCase().trim(),
                      // 2. MARKA
                      'marka': markaC.text.toUpperCase().trim(),
                      // 3. MODEL
                      'model': modelC.text.toUpperCase().trim(),
                      // 4. ALT_MODEL (Ve o gereksiz çift sütun)
                      'alt_model': altDegeri,
                      'altmodel': altDegeri,
                      // 5. FİRMA (Sen en başa yazmıştın, hata buydu!)
                      'tarim_firmalari': adC.text.toUpperCase().trim(),
                      // 6. DURUM
                      'durum': durum,
                    });
                  }
                } else {
                  // 4. Güncelleme yap
                  await DatabaseHelper.instance.firmaGuncelle(f['id'], v);
                }

                Navigator.pop(context);
                _verileriYukle();
              },
              child: const Text("KAYDET"),
            ),
          ],
        ),
      ),
    );
  }

  // --- ÖDEME FORMU ---
  // Bu fonksiyonu kopyala, sayfanın içine (en alta olabilir) yapıştır.
  Future<void> _odemeDialog(Map<String, dynamic> f) async {
    final tutarC = TextEditingController();
    final tarihC = TextEditingController(text: DateFormat('dd.MM.yyyy').format(DateTime.now()));
    String kanal = "NAKİT";

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setS) => AlertDialog(
          title: Text("ÖDEME YAP: ${f['ad']}"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _input(tutarC, "Tutar (₺)", keyboard: TextInputType.number),
              _input(tarihC, "Tarih"),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                value: kanal,
                decoration: const InputDecoration(labelText: "Ödeme Kanalı", border: OutlineInputBorder()),
                items: ["NAKİT", "EFT/HAVALE", "ÇEK", "SENET", "AÇIK HESAP"]
                    .map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                onChanged: (v) => setS(() => kanal = v!),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text("İPTAL")),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red[900], foregroundColor: Colors.white),
              onPressed: () async {
                double m = double.tryParse(tutarC.text.replaceAll(',', '.')) ?? 0;
                if (m > 0) {
                  // 1. Hareket kaydı ekle
                  await DatabaseHelper.instance.firmaHareketiEkle({
                    'firma_id': f['id'],
                    'tip': "ÖDEME",
                    'urun_adi': "$kanal ÖDEMESİ",
                    'tutar': m,
                    'tarih': tarihC.text,
                  });

                  // 2. Bakiyeyi güncelle (Ödeme olduğu için borçtan düşer)
                  await DatabaseHelper.instance.firmaBakiyeGuncelle(f['id'], -m);

                  Navigator.pop(context);
                  _verileriYukle(); // Ana listeyi tazele
                }
              },
              child: const Text("KAYDET"),
            ),
          ],
        ),
      ),
    );
  }

  // --- YARDIMCI METODLAR ---
  Widget _input(TextEditingController c, String l, {TextInputType keyboard = TextInputType.text, int lines = 1}) =>
      Padding(padding: const EdgeInsets.only(bottom: 8), child: TextField(controller: c, keyboardType: keyboard, maxLines: lines, decoration: InputDecoration(labelText: l, border: const OutlineInputBorder())));

  // --- FİRMA SEÇİCİ (SADECE PDF AÇACAK) ---
  void _hizliIslemSecici(String tip) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => ListView.builder(
        itemCount: _firmalar.length,
        itemBuilder: (context, i) {
          final Map<String, dynamic> secilenFirma = _firmalar[i];
          return ListTile(
            leading: const Icon(Icons.business, color: Colors.indigo),
            title: Text(secilenFirma['ad'] ?? "İsimsiz Firma"),
            onTap: () {
              Navigator.pop(context); // Listeyi kapat

              // TİP EKSTRE İSE DİREKT PDF OLUŞTURMAYA GİDER
              if (tip == "EKSTRE") {
                _firmaEkstrePdfOlustur(secilenFirma);
              }
            },
          );
        },
      ),
    );
  }

  // --- PDF FORMAT (Bu fonksiyon PDF içinde geçiyor ama kodunda yoktu) ---
  String pdfFormat(dynamic deger) {
    try {
      double rakam = double.tryParse(deger.toString()) ?? 0;
      // tr_TR sayesinde 200000 -> 200.000,00 olur
      return NumberFormat.currency(locale: 'tr_TR', symbol: '', decimalDigits: 2).format(rakam);
    } catch (e) {
      return "0,00";
    }
  }
  void _hizliSecimDialog(String tip) {
    _hizliIslemSecici(tip); // Direkt diğerini çağıralım, kod kalabalığı bitsin.
  }

  Future<void> _firmaEkstrePdfOlustur(Map<String, dynamic> firma) async {
    try {
      final pdf = pw.Document();
      final font = await PdfGoogleFonts.robotoRegular();
      final boldFont = await PdfGoogleFonts.robotoBold();

      String f(dynamic d) => NumberFormat.currency(
          locale: 'tr_TR', symbol: '', decimalDigits: 2)
          .format(double.tryParse(d.toString()) ?? 0)
          .trim();

      final hareketler = await DatabaseHelper.instance.firmaEkstresiGetir(firma['id']);
      double yuruyenBakiye = 0.0;

      Uint8List? byteList;
      try {
        final ByteData bytes = await rootBundle.load('assets/images/logo.png');
        byteList = bytes.buffer.asUint8List();
      } catch (e) {
        debugPrint("Logo yüklenemedi, logosuz devam ediliyor.");
      }

      final List<List<String>> tabloSatirlari = [];
      for (var h in hareketler) {
        // --- BU SATIRI EKLE ---
        if (h['tip'] == 'AKTARIM' || h['tip'] == 'TRANSFER') continue;
        double adet = double.tryParse(h['adet']?.toString() ?? "1") ?? 1.0;
        double tutar = double.tryParse(h['tutar']?.toString() ?? "0") ?? 0.0;
        double birimFiyat = adet > 0 ? tutar / adet : 0;

        bool isOdeme = h['tip'] == "ÖDEME" || h['tip'] == "ODEME" || h['tip'] == "AVANS";

        if (isOdeme) {
          yuruyenBakiye -= tutar;
        } else {
          yuruyenBakiye += tutar;
        }

        String anaBaslik = (h['urun_adi'] ?? "İŞLEM").toString().toUpperCase();
        String detay = "${h['marka'] ?? ''} ${h['model'] ?? ''}".trim().toUpperCase();
        String tamAciklama = detay.isNotEmpty && !anaBaslik.contains(detay)
            ? "$anaBaslik ($detay)"
            : anaBaslik;

        // TABLOYA SÜTUNLARI EKLİYORUZ
        tabloSatirlari.add([
          h['tarih'] ?? "-",
          tamAciklama,
          adet.toStringAsFixed(0), // Adet Sütunu
          f(birimFiyat),           // Birim Fiyat Sütunu
          !isOdeme ? f(tutar) : "0,00", // Borç
          isOdeme ? f(tutar) : "0,00",  // Alacak
          f(yuruyenBakiye),        // Bakiye
        ]);
      }

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.symmetric(horizontal: 25, vertical: 30),
          header: (context) => pw.Column(
            children: [
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Row(
                    children: [
                      if (byteList != null)
                        pw.Container(
                          width: 50,
                          height: 50,
                          child: pw.Image(pw.MemoryImage(byteList)),
                        ),
                      pw.SizedBox(width: 10),
                      pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text("EVREN TİCARET GRUBU",
                              style: pw.TextStyle(font: boldFont, fontSize: 16, color: PdfColors.blue900)),
                          pw.Text("Evren Özçoban | 0545 521 75 65",
                              style: pw.TextStyle(font: font, fontSize: 9)),
                          pw.Text("Tefenni / BURDUR",
                              style: pw.TextStyle(font: font, fontSize: 8)),
                        ],
                      ),
                    ],
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text("CARİ EKSTRE",
                          style: pw.TextStyle(font: boldFont, fontSize: 14)),
                      pw.SizedBox(height: 5),
                      pw.Text("TARİH: ${DateFormat('dd.MM.yyyy').format(DateTime.now())}",
                          style: pw.TextStyle(font: font, fontSize: 9)),
                    ],
                  ),
                ],
              ),
              pw.Divider(thickness: 1, height: 15, color: PdfColors.blue900),
            ],
          ),
          build: (pdfContext) => [
            pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.all(8),
              decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey400)),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text("FİRMA / MÜŞTERİ:", style: pw.TextStyle(font: boldFont, fontSize: 8)),
                  pw.Text("${firma['ad']}".toUpperCase(), style: pw.TextStyle(font: boldFont, fontSize: 12)),
                  if (firma['yetkili'] != null)
                    pw.Text("YETKİLİ: ${firma['yetkili']}", style: pw.TextStyle(font: font, fontSize: 9)),
                ],
              ),
            ),
            pw.SizedBox(height: 15),

            // TABLO BAŞLIKLARI VE GENİŞLİKLERİ GÜNCELLENDİ
            pw.TableHelper.fromTextArray(
              headers: ['TARİH', 'AÇIKLAMA', 'ADET', 'B.FİYAT', 'BORÇ', 'ALACAK', 'BAKİYE'],
              data: tabloSatirlari,
              headerStyle: pw.TextStyle(font: boldFont, color: PdfColors.white, fontSize: 8),
              headerDecoration: const pw.BoxDecoration(color: PdfColors.blue900),
              cellStyle: pw.TextStyle(font: font, fontSize: 7),
              columnWidths: {
                0: const pw.FixedColumnWidth(50), // Tarih
                1: const pw.FlexColumnWidth(3),   // Açıklama
                2: const pw.FixedColumnWidth(30), // Adet
                3: const pw.FixedColumnWidth(50), // B. Fiyat
                4: const pw.FixedColumnWidth(60), // Borç
                5: const pw.FixedColumnWidth(60), // Alacak
                6: const pw.FixedColumnWidth(65), // Bakiye
              },
              cellAlignments: {
                0: pw.Alignment.centerLeft,
                1: pw.Alignment.centerLeft,
                2: pw.Alignment.center,
                3: pw.Alignment.centerRight,
                4: pw.Alignment.centerRight,
                5: pw.Alignment.centerRight,
                6: pw.Alignment.centerRight,
              },
              headerHeight: 25,
              cellPadding: const pw.EdgeInsets.all(5),
            ),

            pw.SizedBox(height: 15),

            pw.Align(
              alignment: pw.Alignment.centerRight,
              child: pw.Container(
                width: 200,
                padding: const pw.EdgeInsets.all(8),
                decoration: const pw.BoxDecoration(color: PdfColors.grey100),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text("GÜNCEL BAKİYE", style: pw.TextStyle(font: boldFont, fontSize: 10)),
                    pw.Text("${f(yuruyenBakiye)} TL",
                        style: pw.TextStyle(
                            font: boldFont,
                            fontSize: 10,
                            color: yuruyenBakiye < 0 ? PdfColors.red : PdfColors.green700
                        )),
                  ],
                ),
              ),
            ),
          ],
        ),
      );

      final Uint8List pdfBytes = await pdf.save();
      if (!mounted) return;
      await Navigator.push(context, MaterialPageRoute(
        builder: (context) => Scaffold(
          appBar: AppBar(title: Text("${firma['ad']} Ekstre Önizleme"), backgroundColor: Colors.blueGrey[900]),
          body: PdfPreview(build: (format) => pdfBytes),
        ),
      ));

    } catch (e) {
      debugPrint("PDF Hatası: $e");
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Hata: $e")));
    }
  }

  void _ekstreyeGit(Map<String, dynamic> f) {
    Navigator.push(context, MaterialPageRoute(builder: (c) => FirmaEkstreSayfasi(firmaId: f['id'], firmaAd: f['ad'])));
  }

// Paketi en üste ekle: import 'package:image_picker/image_picker.dart';

  // 1. Firma Seçme Listesini Açan Fonksiyon (Üstteki "Fatura Foto" butonu için)
  void _faturaFotoEkle() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => ListView.builder(
        itemCount: _firmalar.length, // Sayfadaki firma listesini kullanır
        itemBuilder: (context, i) {
          final f = _firmalar[i];
          return ListTile(
            leading: const Icon(Icons.business, color: Colors.indigo),
            title: Text(f['ad'] ?? "İsimsiz Firma"),
            subtitle: Text("Yetkili: ${f['yetkili'] ?? '-'}"),
            onTap: () {
              Navigator.pop(context); // Listeyi kapat
              _fotoSecimMenusu(f);    // Firma bilgilerini menüye gönder
            },
          );
        },
      ),
    );
  }

  // 2. Firmaya Özel İşlem Seçeneklerini Açan Menü
  void _fotoSecimMenusu(Map<String, dynamic> f) {
    final ImagePicker picker = ImagePicker();
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.all(15),
            child: Text("${f['ad']} - İŞLEM SEÇİN", style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
          ListTile(
            leading: const Icon(Icons.camera_alt, color: Colors.purple),
            title: const Text("Kameradan Fatura Çek"),
            onTap: () async {
              final XFile? image = await picker.pickImage(source: ImageSource.camera, imageQuality: 70);
              if (image != null) _faturayiKaydet(image.path, f['id']); // Firmanın faturayı kaydeder
              Navigator.pop(context);
            },
          ),
          ListTile(
            leading: const Icon(Icons.image, color: Colors.blue),
            title: const Text("Galeriden Fatura Seç"),
            onTap: () async {
              final XFile? image = await picker.pickImage(source: ImageSource.gallery, imageQuality: 70);
              if (image != null) _faturayiKaydet(image.path, f['id']);
              Navigator.pop(context);
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.collections, color: Colors.orange),
            title: const Text("Firmanın Eski Faturalarını Gör"),
            onTap: () {
              Navigator.pop(context);
              _faturaGalerisiniAc(f); // Firmanın galerisini açar
            },
          ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }
  Future<void> _faturayiKaydet(String path, int firmaId) async {
    debugPrint("🚀 İşlem Başladı. Firma: $firmaId");

    try {
      // --- KONTROL ADIMI: AYNI DOSYA DAHA ÖNCE EKLENDİ Mİ? ---
      final db = await DatabaseHelper.instance.database;
      final mukerrerKontrol = await db.query(
        'faturalar',
        where: 'dosya_yolu = ? AND firma_id = ?',
        whereArgs: [path, firmaId],
      );

      if (mukerrerKontrol.isNotEmpty) {
        debugPrint("⚠️ DUR! Bu fotoğraf bu firmaya zaten eklenmiş. Sonsuz kaydı engelledim.");
        return; // Fonksiyonu burada bitir, aşağıya geçme.
      }
      // ------------------------------------------------------

      File resimDosyasi = File(path);
      if (!await resimDosyasi.exists()) return;

      Uint8List resimByte = await resimDosyasi.readAsBytes();
      String base64Resim = base64Encode(resimByte);

      // 2. Telefona Kaydet
      int localId = await DatabaseHelper.instance.faturaEkle({
        'firma_id': firmaId,
        'dosya_yolu': path,
        'tarih': DateFormat('dd.MM.yyyy HH:mm').format(DateTime.now()),
      });
      debugPrint("✅ SQLite Tamam (ID: $localId)");

      // 3. Firebase'e Gönder (Timeout ve Hata Kontrolüyle)
      try {
        await FirebaseFirestore.instance
            .collection('tarim_firmalari')
            .doc(firmaId.toString())
            .collection('faturalar')
            .add({
          'fatura_data': base64Resim,
          'yerel_yol': path, // Firebase tarafında da kontrol için yolu ekledik
          'tarih': FieldValue.serverTimestamp(),
        }).timeout(const Duration(seconds: 10)); // Bekleme süresini 10 sn yapalım, daemon ölmesin

        debugPrint("✅ Firebase Tamam");
      } catch (e) {
        debugPrint("⚠️ Firebase Yazılamadı (Ama telefona kaydedildi): $e");
      }

      _verileriYukle();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("✅ Fatura Başarıyla Mühürlendi")),
      );

    } catch (e) {
      debugPrint("🚨 Kritik Hata: $e");
    }
  }

  void _faturaGalerisiniAc(Map<String, dynamic> firma) {
    Navigator.push(context, MaterialPageRoute(builder: (c) => StatefulBuilder(
      builder: (context, setStateGaleri) => Scaffold(
        appBar: AppBar(
          title: Text("${firma['ad']} Faturaları"),
          backgroundColor: Colors.purple[900],
        ),
        body: FutureBuilder<List<Map<String, dynamic>>>(
          future: DatabaseHelper.instance.firmaFaturalariniGetir(firma['id']),
          builder: (context, snapshot) {
            if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
            final fotolar = snapshot.data!;

            if (fotolar.isEmpty) return const Center(child: Text("Henüz fatura fotoğrafı yok."));

            return GridView.builder(
              padding: const EdgeInsets.all(10),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8
              ),
              itemCount: fotolar.length,
              itemBuilder: (context, i) {
                return Stack(
                  children: [
                    InkWell(
                      onTap: () => _tamEkranGoster(fotolar[i]['dosya_yolu'], fotolar[i]['id'], () {
                        setStateGaleri(() {}); // Silinince galeriyi yenile
                      }),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.file(
                            File(fotolar[i]['dosya_yolu']),
                            fit: BoxFit.cover,
                            width: double.infinity,
                            height: double.infinity
                        ),
                      ),
                    ),
                    // Fotoğrafın sağ üstüne küçük bir silme ikonu (Hızlı silme için)
                    Positioned(
                      right: 2,
                      top: 2,
                      child: InkWell(
                        onTap: () => _faturaSilOnay(fotolar[i]['id'], () {
                          setStateGaleri(() {});
                        }),
                        child: Container(
                          decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                          child: const Icon(Icons.cancel, color: Colors.red, size: 20),
                        ),
                      ),
                    ),
                  ],
                );
              },
            );
          },
        ),
      ),
    )));
  }

  // --- TAM EKRAN GÖSTERİM VE SİLME ---
  void _tamEkranGoster(String yol, int faturaId, VoidCallback yenile) {
    showDialog(
      context: context,
      builder: (c) => Dialog(
        backgroundColor: Colors.black,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Image.file(File(yol), fit: BoxFit.contain),
            // Kapatma Butonu
            Positioned(
                top: 10,
                left: 10,
                child: IconButton(
                    icon: const Icon(Icons.close, color: Colors.white, size: 30),
                    onPressed: () => Navigator.pop(c)
                )
            ),
            // Silme Butonu
            Positioned(
                top: 10,
                right: 10,
                child: IconButton(
                    icon: const Icon(Icons.delete_forever, color: Colors.red, size: 35),
                    onPressed: () {
                      Navigator.pop(c); // Dialogu kapat
                      _faturaSilOnay(faturaId, yenile);
                    }
                )
            ),
          ],
        ),
      ),
    );
  }

  // --- SİLME ONAY DİALOGU ---
  void _faturaSilOnay(int faturaId, VoidCallback onDone) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Faturayı Sil"),
        content: const Text("Bu fatura fotoğrafı kalıcı olarak silinecek. Emin misiniz?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("VAZGEÇ")),
          ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () async {
                await DatabaseHelper.instance.faturaSil(faturaId);
                Navigator.pop(context);
                onDone(); // Galeriyi tazele
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("Fatura silindi."), backgroundColor: Colors.orange)
                );
              },
              child: const Text("SİL")
          ),
        ],
      ),
    );
  }
}

