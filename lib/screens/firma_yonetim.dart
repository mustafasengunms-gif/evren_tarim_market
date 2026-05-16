// Temel Flutter ve Dart Paketleri
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

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
import '../services/firebase_foto_service.dart'; // Bu satırı ekle
import '../utils/pdf_helper.dart';


class FirmaTanimSayfasi extends StatefulWidget {
  const FirmaTanimSayfasi({super.key});

  @override
  State<FirmaTanimSayfasi> createState() => _FirmaTanimSayfasiState();
}

class _FirmaTanimSayfasiState extends State<FirmaTanimSayfasi> {
  List<Map<String, dynamic>> _firmalar = [];
  List<Map<String, dynamic>> _filtreliFirmalar = [];
  final TextEditingController _aramaC = TextEditingController();
  Map<String, dynamic>? seciliFirma; // En üste, değişkenlerin yanına ekle

  double toplamBorc = 0;
  double toplamAlacak = 0;


  @override
  void initState() {
    super.initState();
    _verileriYukle();
  }

  Widget buildImage(String path) {
    if (path.isEmpty) return Image.asset("assets/images/logo.png");

    // Eğer yol http ile başlıyorsa internetten çek, başlamıyorsa yerel dosyadan
    return path.startsWith('http')
        ? Image.network(path, fit: BoxFit.cover)
        : Image.file(File(path), fit: BoxFit.cover);
  }

  Future<void> _verileriYukle() async {
    print("🔍 --- PDF MANTIĞI İLE BAKİYE DOĞRULAMA BAŞLADI ---");
    List<Map<String, dynamic>> hamVeriler = [];

    try {
      if (kIsWeb) {
        QuerySnapshot snapshot = await FirebaseFirestore.instance.collection('tarim_firmalari').get();
        hamVeriler = snapshot.docs.map((doc) => doc.data() as Map<String, dynamic>).toList();
      } else {
        hamVeriler = await DatabaseHelper.instance.tarimFirmaListesiGetir();
      }

      double borcToplam = 0;
      double alacakToplam = 0;
      List<Map<String, dynamic>> yeniListe = [];

      for (var f in hamVeriler) {
        Map<String, dynamic> mutableFirma = Map<String, dynamic>.from(f);
        String cKod = (mutableFirma['cari_kod'] ?? mutableFirma['id']).toString();

        // --- MÜHÜR BURASI: PDF'deki listeyi çekiyoruz ---
        final hareketler = await DatabaseHelper.instance.tarimfirmaEkstresiGetir(cKod);

        double firmaYuruyenBakiye = 0.0;

        // PDF'deki döngünün aynısı:
        for (var h in hareketler) {
          if (h['tip'] == 'AKTARIM' || h['tip'] == 'TRANSFER') continue;

          double tutar = double.tryParse(h['tutar']?.toString() ?? "0") ?? 0.0;

          // PDF süzgeci: ALIM borcu artırır, ÖDEME/ODEME borcu azaltır
          bool isAlim = h['tip'] == "ALIM";
          bool isOdeme = h['tip'] == "ÖDEME" || h['tip'] == "ODEME";

          if (isAlim) {
            firmaYuruyenBakiye += tutar;
          } else if (isOdeme) {
            firmaYuruyenBakiye -= tutar;
          }
        }

        // --- GENEL PANEL HESABI (Kırmızı/Yeşil Kutular İçin) ---
        if (firmaYuruyenBakiye > 0) {
          borcToplam += firmaYuruyenBakiye;
        } else if (firmaYuruyenBakiye < 0) {
          alacakToplam += firmaYuruyenBakiye.abs();
        }

        // Artık firma nesnesindeki bakiye PDF ile %100 aynı
        mutableFirma['bakiye'] = firmaYuruyenBakiye;
        yeniListe.add(mutableFirma);
      }

      if (mounted) {
        setState(() {
          _firmalar = yeniListe;
          _filtreliFirmalar = yeniListe;
          toplamBorc = borcToplam;
          toplamAlacak = alacakToplam;
        });
        print("✅ Evren Sistem Mühürlendi: PDF ve Liste Bakiyeleri Eşitlendi.");
      }
    } catch (e) {
      print("❌ Bakiye Yükleme Hatası: $e");
    }
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

  // --- ÜST ÖZET PANEL (MÜHÜRLENDİ) ---
  Widget _ozetPanel() => Container(
    padding: const EdgeInsets.all(15),
    color: Colors.indigo[900],
    child: Row(
      children: [
        // FİRMALARA OLAN BORCUN (Kırmızı - Borç)
        _ozetKutu("TOPLAM BORCUMUZ", toplamBorc, Colors.red[300]!),

        _ozetKutu("TOPLAM ALACAĞIMIZ", toplamAlacak, Colors.green[300]!),
      ],
    ),
  );

  Widget _ozetKutu(String t, double m, Color c) => Expanded(
    child: Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c.withOpacity(0.3), width: 1), // Hafif kenarlık ekledik
      ),
      child: Column(children: [
        Text(t, style: TextStyle(color: c, fontSize: 11, fontWeight: FontWeight.bold)),
        const SizedBox(height: 5),
        Text(
            "${NumberFormat.currency(locale: 'tr_TR', symbol: '', decimalDigits: 2).format(m)} ₺",
            style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)
        ),
      ]),
    ),
  );

  // --- AKSİYON BAR (DÜZELTİLDİ) ---
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

          _ustButon(Icons.account_balance_wallet, "Ödeme Yap", Colors.red[800]!, () {
            if (_firmalar.isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Kayıtlı firma bulunamadı!")));
            } else {
              _firmaSeciciDialog("ÖDEME"); // Önce listeyi açar
            }
          }),

          // EKSTRELER BUTONU (MÜHÜRLÜ): 'firma' yerine null gönderip içeride seçtiriyoruz
          // ya da bu butonu genel bir "Raporlar" butonu olarak kullanıyoruz.
          _ustButon(
            Icons.assignment,
            "Ekstreler",
            Colors.orange[900]!,
                () => _hizliIslemSecici("EKSTRE"), // Firma parametresini kaldırdık, hata bitti!
          ),

          _ustButon(Icons.add_a_photo, "Fatura Foto", Colors.purple[800]!, () => _faturaFotoEkle()),
        ],
      ),
    );
  }

  // Giriş fonksiyonu: Butondan gelen veriyi karşılar
  void _hizliSecimDialog(String baslik, Map<String, dynamic> gelenFirma) {
    _ekstreMenusuAc(baslik, gelenFirma);
  }

// Menü fonksiyonu: Alt paneli açar ve PDF'i tetikler
  void _ekstreMenusuAc(String baslik, Map<String, dynamic> seciliFirma) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                  "$baslik İŞLEMLERİ",
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.orange[900])
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.picture_as_pdf, color: Colors.red),
                title: const Text("Firma Ekstresi (PDF)"),
                subtitle: const Text("Alım ve ödemeleri profesyonel listeler"),
                onTap: () async {
                  Navigator.pop(context);

                  // f['cari_kod'] yerine seciliFirma['cari_kod'] kullanmalısın
                  // Çünkü listenin başındaki değişken adın 'seciliFirma'
                  final String cKod = (seciliFirma['cari_kod'] ?? "").toString();

                  if (cKod.isEmpty) {
                    debugPrint("HATA: Firmanın cari kodu boş!");
                    return;
                  }

                  final hareketler = await DatabaseHelper.instance.tarimfirmaEkstresiGetir(cKod);
                  print("EKSTRE CARİ KOD => $cKod");
                  print("HAREKET SAYISI => ${hareketler.length}");

                  if (mounted) {
                    await PdfHelper.tarimFirmaEkstresiGoster(
                        context,
                        seciliFirma['ad'] ?? "Bilinmeyen Firma",
                        hareketler
                    );
                  }
                },
              ),
            ],
          ),
        );
      },
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
    // Database'den gelen saf bakiye (Borç - Alacak)
    double bakiye = double.tryParse(f['bakiye']?.toString() ?? '0') ?? 0.0;

    return Card(
      elevation: 2,
      margin: const EdgeInsets.symmetric(vertical: 5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ExpansionTile(
        leading: CircleAvatar(
          backgroundColor: Colors.indigo[900],
          child: Text(
            f['ad'] != null && f['ad'].isNotEmpty ? f['ad'][0] : "?",
            style: const TextStyle(color: Colors.white),
          ),
        ),
        title: Text(f['ad'] ?? "İsimsiz Firma", style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text("Yetkili: ${f['yetkili'] ?? '-'}"),
        trailing: Row( // İŞTE BURASI: Tek bir Row, temiz parantez
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
                  NumberFormat.currency(locale: 'tr_TR', symbol: '₺', decimalDigits: 2).format(bakiye.abs()),
                  style: TextStyle(
                    // MANTIĞI ÇİVİLEDİK: Borç varsa KIRMIZI, Alacak varsa YEŞİL
                    color: bakiye > 0 ? Colors.red[900] : (bakiye < 0 ? Colors.green[800] : Colors.black),
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                Text(
                  // YAZIYI ÇİVİLEDİK
                  bakiye > 0 ? "FİRMAYA BORCUMUZ" : (bakiye < 0 ? "ALACAĞIMIZ VAR" : "BAKİYE SIFIR"),
                  style: TextStyle(
                    color: bakiye > 0 ? Colors.red[900] : (bakiye < 0 ? Colors.green[800] : Colors.grey),
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
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
                    _kucukAksiyonButon(Icons.delete, "Sil", Colors.red, () => _firmaSilOnay(f)),
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


// 2. İşlem Menüsü: Alt panel burada açılır
  void _ekstreSecimMenusu(String tip, Map<String, dynamic> seciliFirma) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                  "$tip İŞLEMLERİ",
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.orange[900])
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.picture_as_pdf, color: Colors.red),
                title: const Text("Firma Ekstresi (PDF)"),
                subtitle: const Text("Alım ve ödemeleri listeler"),
                  onTap: () async {

                    final anaContext = context;

                    Navigator.pop(context);

                    await Future.delayed(const Duration(milliseconds: 200));

                    final String cKod =
                    (seciliFirma['cari_kod'] ?? "").toString();

                    print("Sorgulanan Cari Kod: $cKod");

                    final hareketler =
                    await DatabaseHelper.instance.tarimfirmaEkstresiGetir(cKod);

                    print("EKSTRE CARİ KOD => $cKod");
                    print("HAREKET SAYISI => ${hareketler.length}");

                    if (!anaContext.mounted) return;

                    await PdfHelper.tarimFirmaEkstresiGoster(
                      anaContext,
                      seciliFirma['ad'] ?? "Bilinmeyen Firma",
                      hareketler,
                    );
                  }
              ),
            ],
          ),
        );
      },
    );
  }



  Future<void> _direktFotoCek(Map<String, dynamic> firma) async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 70,
    );

    if (image != null) {
      _faturayiKaydet(
        image.path,
        (firma['cari_kod'] ?? firma['id']).toString(),
      );
    }
  }
  void _firmaSilOnay(Map<String, dynamic> firma) async {
    // 1. Mühürü al (Resimdeki F-177... kodları)
    String muhur = firma['cari_kod']?.toString() ?? firma['id']?.toString() ?? "";

    if (muhur.isEmpty || muhur.contains("HATA")) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("HATA: GEÇERLİ MÜHÜR BULUNAMADI!"))
      );
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false, // Silme sırasında dışarı tıklanmasın
      builder: (diagContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        title: Text("${firma['ad']} TAMAMEN SİLİNSİN Mİ?"),
        content: const Text("Bu firmanın bakiyesi, hareketleri ve bulut kayıtları kalıcı olarak silinecektir. Geri dönüşü yoktur!"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(diagContext), child: const Text("VAZGEÇ")),
          ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () async {
                // 1. İşlem çarkını göster (Çark Penceresi)
                showDialog(context: context, builder: (c) => const Center(child: CircularProgressIndicator()));

                try {
                  // --- ADIM 1: FİREBASE SİLME ---
                  await FirebaseFirestore.instance
                      .collection('tarim_firmalari')
                      .doc(muhur)
                      .delete();

                  // --- ADIM 2: SQLITE SİLME ---
                  if (!kIsWeb) {
                    final db = await DatabaseHelper.instance.database;
                    await db.delete(
                      'tarim_firmalari',
                      where: 'id = ?',
                      whereArgs: [firma['id']],
                    );
                  }

                  // --- KRİTİK ADIM: PENCERELERİ KAPAT ---
                  if (mounted) {
                    Navigator.pop(context); // 1. Çarkı kapatır
                    Navigator.pop(context); // 2. "Silinsin mi?" uyarısını kapatır

                    // Listeyi yenile ve mesaj ver
                    _verileriYukle();
                    ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text("Firma ve tüm kayıtları kökten silindi."))
                    );
                  }

                } catch (e) {
                  if (mounted) Navigator.pop(context); // Hata olursa sadece çarkı kapat
                  debugPrint("❌ SİLME HATASI: $e");
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Hata: $e")));
                }
              },
              child: const Text("KÖKTEN SİL", style: TextStyle(color: Colors.white))
          ),
        ],
      ),
    );
  }

  void _firmaFormDialog(Map<String, dynamic>? f) {
    final adC = TextEditingController(text: f?['ad']?.toString() ?? "");
    final yetkiliC = TextEditingController(text: f?['yetkili']?.toString() ?? "");
    final telC = TextEditingController(text: f?['tel']?.toString() ?? "");
    final adresC = TextEditingController(text: f?['adres']?.toString() ?? "");
    final kategoriC = TextEditingController(text: f?['kategori']?.toString() ?? "");
    final markaC = TextEditingController(text: f?['marka']?.toString() ?? "");
    final modelC = TextEditingController(text: f?['model']?.toString() ?? "");

    // Sadece alt_model kullanıyoruz, eski verileri de buraya çekiyoruz
    final altModelC = TextEditingController(
        text: (f?['alt_model'] ?? f?['altmodel'])?.toString() ?? "");

    String durum = (f?['durum'] == "SIFIR" || f?['durum'] == "2. EL")
        ? f!['durum']
        : "SIFIR";

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setS) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          titlePadding: const EdgeInsets.all(0),
          title: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.indigo[900],
              borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(20), topRight: Radius.circular(20)),
            ),
            child: Row(
              children: [
                Icon(f == null ? Icons.add_business : Icons.edit_note, color: Colors.white),
                const SizedBox(width: 10),
                Text(
                  f == null ? "YENİ KAYIT" : "KAYIT GÜNCELLE",
                  style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
                ),
              ],
            ),
          ),
          content: SizedBox(
            width: MediaQuery.of(context).size.width * 0.9,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("FİRMA BİLGİLERİ",
                      style: TextStyle(fontWeight: FontWeight.bold, color: Colors.indigo)),
                  const Divider(),
                  _modernInput(adC, "Firma Ünvanı"),
                  _modernInput(yetkiliC, "Yetkili Ad Soyad"),
                  _modernInput(telC, "Telefon", keyboard: TextInputType.phone),
                  _modernInput(adresC, "Adres", lines: 2),

                  const SizedBox(height: 20),
                  const Text("STOK / TEKNİK BİLGİLER",
                      style: TextStyle(fontWeight: FontWeight.bold, color: Colors.indigo)),
                  const Divider(),

                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6.0),
                    child: DropdownButtonFormField<String>(
                      value: durum,
                      decoration: InputDecoration(
                        labelText: "Ürün Durumu",
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        filled: true,
                        fillColor: Colors.grey[50],
                      ),
                      items: const [
                        DropdownMenuItem(value: "SIFIR", child: Text("SIFIR")),
                        DropdownMenuItem(value: "2. EL", child: Text("2. EL")),
                      ],
                      onChanged: (v) => setS(() => durum = v!),
                    ),
                  ),
                  _modernInput(kategoriC, "Kategori (Örn: Traktör)"),
                  _modernInput(markaC, "Marka"),
                  _modernInput(modelC, "Model"),
                  _modernInput(altModelC, "Alt Model / Detay"),
                ],
              ),
            ),
          ),
          actionsPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 15),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("VAZGEÇ",
                  style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
            ),
            ElevatedButton.icon(
              icon: const Icon(Icons.save),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.indigo[900],
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 25, vertical: 15),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () async {
                // 1. BOŞ KONTROLLERİ
                if (adC.text.trim().isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text("Firma Ünvanı boş olamaz!")));
                  return;
                }

                if (kategoriC.text.trim().isEmpty ||
                    markaC.text.trim().isEmpty ||
                    modelC.text.trim().isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text("Kategori, Marka ve Model zorunludur!"),
                    backgroundColor: Colors.orange,
                  ));
                  return;
                }

                String firmaAd = adC.text.toUpperCase().trim();
                String altDegeri = altModelC.text.toUpperCase().trim();
                String zaman = DateTime.now().toIso8601String();

                // 2. ORTAK VERİ PAKETİ (alt_model tek tipleştirildi, durum netleştirildi)
                Map<String, dynamic> v = {
                  'ad': firmaAd,
                  'yetkili': yetkiliC.text.toUpperCase().trim(),
                  'tel': telC.text.trim(),
                  'adres': adresC.text.toUpperCase().trim(),
                  'kategori': kategoriC.text.toUpperCase().trim(),
                  'durum': durum, // Formdan gelen "SIFIR" veya "2. EL"
                  'marka': markaC.text.toUpperCase().trim(),
                  'model': modelC.text.toUpperCase().trim(),
                  'alt_model': altDegeri, // ARTIK SADECE BU VAR
                  'son_guncelleme': zaman,
                  'is_synced': 0,
                  'silindi': 0,
                };

                try {
                  if (f == null) {
                    // --- YENİ KAYIT MÜHÜRÜ ---
                    String cariKod = "F-${DateTime.now().millisecondsSinceEpoch}";

                    // Firma Ekle
                    await DatabaseHelper.instance.tarimFirmaEkle({
                      ...v,
                      'cari_kod': cariKod,
                      'borc': 0.0,
                      'alacak': 0.0,
                      'toplam_borc': 0.0,
                      'toplam_alacak': 0.0,
                    });

                    // Stok Tanımını Ekle
                    if (markaC.text.isNotEmpty) {
                      String yeniFirebaseId = "STOK-${DateTime.now().millisecondsSinceEpoch}";
                      String yeniStokKodu = "${markaC.text.substring(0, 1).toUpperCase()}-${modelC.text.toUpperCase()}-${DateTime.now().microsecond}";

                      await DatabaseHelper.instance.stokTanimEkle({
                        'firebase_id': yeniFirebaseId,
                        'stok_kodu': yeniStokKodu,
                        'kategori': v['kategori'],
                        'marka': v['marka'],
                        'model': v['model'],
                        'alt_model': v['alt_model'], // Tek tip
                        'tarim_firmalari': firmaAd,
                        'durum': durum,
                        'silindi': 0,
                        'is_synced': 0,
                      });
                    }
                  } else {
                    // --- GÜNCELLEME MÜHÜRÜ ---
                    // Önce cari kod kontrolü (f['cari_kod'] yoksa f['id'] kullan)
                    await DatabaseHelper.instance.firmaGuncelle(f['cari_kod'] ?? f['id'], v);

                    if (markaC.text.isNotEmpty) {
                      // Stok güncellemesinde de tek tip alt_model gönderiyoruz
                      await DatabaseHelper.instance.stokTanimGuncelle(
                        v['kategori'],
                        v['marka'],
                        v['model'],
                        v['alt_model'],
                        firmaAd,
                        durum,
                      );
                    }
                  }

                  if (mounted) {
                    Navigator.pop(context);
                    _verileriYukle(); // Listeyi tazele
                    ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text("Sistem Mühürlendi! ✅"), backgroundColor: Colors.green)
                    );
                  }
                } catch (e) {
                  debugPrint("HATA KAYDEDERKEN: $e");
                  ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text("Kritik Hata: $e"), backgroundColor: Colors.red)
                  );
                }
              },
              label: const Text("KAYDET VE MÜHÜRLE",
                  style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }


  Future<void> _odemeDialog(Map<String, dynamic> f) async {
    print("🛠️ DEBUG 1: Ödeme Penceresi Açıldı. Gelen Veri: $f");

    final tutarC = TextEditingController();
    final tarihC = TextEditingController(text: DateFormat('dd.MM.yyyy').format(DateTime.now()));
    final aciklamaC = TextEditingController();

    // Görseldeki F-177... kodunu yakalıyoruz
    String cKod = (f['cari_kod'] ?? f['id'] ?? "").toString();

    if (cKod.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("HATA: Firma kodu eksik!")));
      return;
    }

    showDialog(
      context: context,
      builder: (diagContext) => StatefulBuilder(
        builder: (diagContext, setS) => AlertDialog(
          title: Text("ÖDEME: ${f['ad']}"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _modernInput(tutarC, "Tutar (₺)", keyboard: TextInputType.number),
              _modernInput(aciklamaC, "Açıklama"),
              _modernInput(tarihC, "Tarih"),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(diagContext), child: const Text("İPTAL")),
            ElevatedButton(
              onPressed: () async {
                double m = double.tryParse(tutarC.text.replaceAll(',', '.')) ?? 0;
                if (m <= 0) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Geçerli bir tutar girin!")));
                  return;
                }

                // Sadece paketini hazırla
                Map<String, dynamic> hareketPaketi = {
                  'id': "H-${DateTime.now().millisecondsSinceEpoch}",
                  'cari_kod': cKod,
                  'tip': "ÖDEME",
                  'urun_adi': aciklamaC.text.isEmpty ? "NAKİT ÖDEME" : aciklamaC.text.toUpperCase(),
                  'tutar': m,
                  'tarih': tarihC.text,
                };

                // ADIM 1: Senin o dev fonksiyonu çağır, o her şeyi halletsin
                await DatabaseHelper.instance.tarimfirmaHareketiEkle(hareketPaketi);

                // ADIM 2: Ekranı tazele ve kapat
                if (mounted) {
                  Navigator.pop(diagContext);
                  _verileriYukle(); // SQLite'tan güncel bakiyeleri çekip ekrana basar
                  ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text("İşlem başarıyla mühürlendi! ✅"),
                        backgroundColor: Colors.green,
                      )
                  );
                }
              },
              child: const Text("KAYDET VE MÜHÜRLE"),
            ),
          ],
        ),
      ),
    );
  }



// 2. MODERN INPUT METODU (HER YERDEN ERİŞİLEBİLİR)
  Widget _modernInput(TextEditingController controller, String label, {TextInputType keyboard = TextInputType.text, int lines = 1}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: TextFormField(
        controller: controller,
        textCapitalization: TextCapitalization.characters,
        keyboardType: keyboard,
        maxLines: lines,
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: Colors.indigo, fontSize: 14),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          filled: true,
          fillColor: Colors.grey[50],
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
      ),
    );
  }
  void _hizliIslemSecici(String tip) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.8,
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Text(
                "PDF EKSTRE İÇİN FİRMA SEÇİN",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: Colors.blue[900],
                ),
              ),
              const Divider(),
              Expanded(
                child: _firmalar.isEmpty
                    ? const Center(child: Text("Seçilecek firma bulunamadı!"))
                    : ListView.builder(
                  itemCount: _firmalar.length,
                  itemBuilder: (context, index) {
                    final f = _firmalar[index];

                    // --- SENİN DEBUG SATIRLARIN ---
                    print("🖥️ UI Çiziliyor: ${f['ad']}");
                    print("📊 Ham Borç: ${f['borc']} | Ham Alacak: ${f['alacak']}");
                    print("📊 Toplam Borç: ${f['toplam_borc']} | Toplam Alacak: ${f['toplam_alacak']}");
                    print("⚖️ Hesaplanan Bakiye: ${f['bakiye']}");

                    return ListTile(
                      leading: CircleAvatar(
                        child: Text((f['ad'] != null && f['ad'].isNotEmpty) ? f['ad'][0] : "?"),
                      ),
                      title: Text(f['ad'] ?? "İsimsiz Firma"),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text("Kod: ${f['cari_kod'] ?? '-'}"),
                          Text(
                            "Bakiye: ${f['bakiye']?.toStringAsFixed(2) ?? '0.00'} TL",
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: (f['bakiye'] ?? 0) < 0 ? Colors.red : Colors.green,
                            ),
                          ),
                        ],
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () async {
                        print("🚀 Seçilen Firma: ${f['ad']} (${f['cari_kod']})");

                        // 1. Hareketleri çek
                        final hareketler = await DatabaseHelper.instance.tarimfirmaEkstresiGetir(f['cari_kod']);

                        if (hareketler.isNotEmpty) {
                          // 2. PDF'i göster
                          if (context.mounted) {
                            await PdfHelper.tarimFirmaEkstresiGoster(
                              context,
                              f['ad'] ?? "İsimsiz",
                              hareketler,
                            );
                          }
                        } else {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text("Bu firmaya ait hareket bulunamadı.")),
                            );
                          }
                        }

                        // 3. Kapat ve f'yi geri gönder
                        if (context.mounted) {
                          Navigator.pop(context, f);
                        }
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }


  // 1. PDF ve Liste için Tutar Formatlayıcı (Eksikti, eklendi)
  String pdfFormat(dynamic tutar) {
    double m = double.tryParse(tutar.toString()) ?? 0.0;
    return NumberFormat.currency(locale: 'tr_TR', symbol: '', decimalDigits: 2).format(m);
  }

  Future<void> _ekstreyeGit(Map<String, dynamic> f) async {
    // Cari kod tespiti (Firebase ID'si olan cari_kod'u öncelikli alıyoruz)
    final String cKod = (f['cari_kod'] ?? f['id']).toString();

    // Veritabanından hareketleri çekiyoruz
    List<Map<String, dynamic>> hareketler = await DatabaseHelper.instance.tarimfirmaEkstresiGetir(cKod);
    print("EKSTRE CARİ KOD => $cKod");
    print("HAREKET SAYISI => ${hareketler.length}");

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(25))),
      builder: (context) => StatefulBuilder(
        builder: (context, setS) => Container(
          height: MediaQuery.of(context).size.height * 0.85,
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Container(width: 50, height: 5, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(10))),
              const SizedBox(height: 15),
              Text("${f['ad'].toString().toUpperCase()} - HAREKETLER", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const Divider(),
              Expanded(
                child: hareketler.isEmpty
                    ? const Center(child: Text("Henüz hareket kaydı bulunmuyor."))
                    : ListView.builder(
                  itemCount: hareketler.length,
                  itemBuilder: (context, i) {
                    // ListView.builder içindeki ilgili kısım:
                    final h = hareketler[i];
                    String tip = (h['tip'] ?? "").toString().trim().toUpperCase();

// Ödeme mi? (Aynı mühür burada da olmalı)
                    bool isOdeme = tip.contains("ÖDEME") || tip.contains("ODEME") || tip.contains("TAHSİLAT");

// Eğer ödeme DEĞİLSE borçtur (Kırmızı), ödemeyse alacaktır (Yeşil)
                    final bool isBorc = !isOdeme;
                    final double tutar = double.tryParse(h['tutar'].toString()) ?? 0;

                    return Card(
                      color: isBorc ? Colors.red[50] : Colors.green[50], // Borçsa Kırmızımsı, Ödemeyse Yeşilimsi
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: isBorc ? Colors.red : Colors.green,
                          child: Icon(isBorc ? Icons.shopping_basket : Icons.account_balance_wallet, color: Colors.white, size: 20),
                        ),
                        title: Text((h['urun_adi'] ?? h['tip']).toString().toUpperCase(), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        // ... geri kalan trailing ve buton kodların aynı kalabilir
                        subtitle: Text("Tarih: ${h['tarih']}"),
                        // ... ListView.builder içindeki trailing Row kısmı:
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                                "${pdfFormat(tutar)} ₺",
                                style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: isBorc ? Colors.red[900] : Colors.green[900]
                                )
                            ),
                            const SizedBox(width: 4),
                            // ✏️ DÜZENLE BUTONU
                            IconButton(
                              icon: const Icon(Icons.edit_outlined, color: Colors.blue, size: 20),
                              onPressed: () => _hareketDuzenleDialog(h, f, () async {
                                var yeniListe = await DatabaseHelper.instance.tarimfirmaEkstresiGetir(cKod);
                                setS(() => hareketler = yeniListe);
                                _verileriYukle();
                              }),
                            ),
                            // 🗑️ SİL BUTONU
                            IconButton(
                              icon: const Icon(Icons.delete_outline, color: Colors.grey, size: 20),
                              onPressed: () => _hareketSilOnay(h, f, () async {
                                var yeniListe = await DatabaseHelper.instance.tarimfirmaEkstresiGetir(cKod);
                                setS(() => hareketler = yeniListe);
                                _verileriYukle();
                              }),
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
        ),
      ),
    );
  }
  void _firmaSeciciDialog(String mod) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(mod == "EKSTRE" ? "Ekstre İçin Firma Seçin" : "Ödeme İçin Firma Seçin"),
        content: SizedBox(
          width: double.maxFinite,
          height: 400,
          child: ListView.builder(
            itemCount: _filtreliFirmalar.length,
            itemBuilder: (context, index) {
              final f = _filtreliFirmalar[index];
              return ListTile(
                leading: CircleAvatar(backgroundColor: Colors.indigo, child: Text(f['ad'][0], style: const TextStyle(color: Colors.white))),
                title: Text(f['ad'] ?? ""),
                subtitle: Text("Cari Kod: ${f['cari_kod']}"),
                onTap: () {
                  Navigator.pop(context); // Listeyi kapat
                  if (mod == "EKSTRE") {
                    _ekstreSecimMenusu("EKSTRE", f); // Ekstre menüsünü aç
                  } else {
                    _odemeDialog(f); // Direkt ödeme ekranını aç
                  }
                },
              );
            },
          ),
        ),
      ),
    );
  }

  void _hareketSilOnay(Map<String, dynamic> h, Map<String, dynamic> f, Function yenile) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Hareketi Sil?"),
        content: Text("${h['tip']} işlemini silmek üzeresiniz. Emin misiniz?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("VAZGEÇ")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              // 1. Verileri hazırla
              String muhur = h['firebase_id']?.toString() ?? "";
              String firmaKodu = f['cari_kod']?.toString() ?? "";
              double miktar = double.tryParse(h['tutar']?.toString() ?? "0") ?? 0;
              String hamTip = h['tip']?.toString() ?? "";

              // Karakter temizliği
              String temizTip = hamTip.replaceAll('Ö', 'O').replaceAll('Ü', 'U').toUpperCase();

              // 2. Silme ve Bakiye Güncelleme işlemini başlat
              await DatabaseHelper.instance.tarimfirmaHareketiSil(
                  muhur,
                  firmaKodu,
                  miktar,
                  temizTip
              );

              if (mounted) {
                Navigator.pop(context); // Diyaloğu kapat
                yenile(); // Ekstre listesini güncelle (Bulunduğun sayfayı yeniler)

                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("İşlem Başarılı. Bakiye güncellendi.")),
                );
              }
            },
            child: const Text("SİL"),
          )
        ],
      ),
    );
  }



  Future<void> _firmaEkstrePdfOlustur(Map<String, dynamic> firma) async {
    try {
      final pdf = pw.Document();
      final font = await PdfGoogleFonts.robotoRegular();
      final boldFont = await PdfGoogleFonts.robotoBold();

      // HATA BURADAYDI: Fonksiyon ismini 'formatla' yaptık ki 'firma'nın 'f'si ile karışmasın
      String formatla(dynamic d) => PdfHelper.formatPara(d);

      // MÜHÜR: Firebase görselindeki gibi direkt cari_kod üzerinden çekiyoruz
      final String cKod = firma['cari_kod'].toString();
      final hareketler = await DatabaseHelper.instance.tarimfirmaEkstresiGetir(cKod);
      print("EKSTRE CARİ KOD => $cKod");
      print("HAREKET SAYISI => ${hareketler.length}");

      double yuruyenBakiye = 0.0;

      // Logo Yükleme (Hata almaması için kontrol mühürlü)
      pw.ImageProvider? imageProvider;
      try {
        imageProvider = await flutterImageProvider(const AssetImage('assets/images/logo.png'));
      } catch (e) {
        debugPrint("Logo yüklenemedi, devam ediliyor.");
      }

      final List<List<String>> tabloSatirlari = [];
      for (var h in hareketler) {
        if (h['tip'] == 'AKTARIM' || h['tip'] == 'TRANSFER') continue;

        double tutar = double.tryParse(h['tutar']?.toString() ?? "0") ?? 0.0;

        // GÖRSELDEKİ MANTIK:
        // tip == "ALIM" -> Mal aldık, borcumuz arttı (BORÇ sütunu)
        // tip == "ÖDEME" -> Para verdik, borcumuz azaldı (ALACAK sütunu)
        bool isAlim = h['tip'] == "ALIM";
        bool isOdeme = h['tip'] == "ÖDEME" || h['tip'] == "ODEME";

        if (isAlim) {
          yuruyenBakiye += tutar;
        } else if (isOdeme) {
          yuruyenBakiye -= tutar;
        }

        tabloSatirlari.add([
          h['tarih'] ?? "-",
          (h['urun_adi'] ?? h['tip']).toString().toUpperCase(),
          (h['adet'] ?? "1").toString(),
          formatla(tutar / (double.tryParse(h['adet']?.toString() ?? "1") ?? 1)), // B.Fiyat
          isAlim ? formatla(tutar) : "0,00",    // Borç (Aldığımız Mal)
          isOdeme ? formatla(tutar) : "0,00",   // Alacak (Ödememiz)
          formatla(yuruyenBakiye),              // Bakiye
        ]);
      }

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(25),
          header: (context) => pw.Column(
            children: [
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Row(
                    children: [
                      if (imageProvider != null)
                        pw.Container(width: 50, height: 50, child: pw.Image(imageProvider)),
                      pw.SizedBox(width: 10),
                      pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text("EVREN TARIM MARKET",
                              style: pw.TextStyle(font: boldFont, fontSize: 18, color: PdfColors.blue900)),
                          pw.Text("Güvenilir Tarım Ticareti",
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
                      pw.Text("FİRMA CARİ EKSTRE",
                          style: pw.TextStyle(font: boldFont, fontSize: 14)),
                      pw.Text("Tarih: ${DateFormat('dd.MM.yyyy').format(DateTime.now())}",
                          style: pw.TextStyle(font: font, fontSize: 9)),
                    ],
                  ),
                ],
              ),
              pw.Divider(thickness: 1, color: PdfColors.blue900, height: 20),
            ],
          ),
          build: (context) => [
            // Cari Bilgi Kartı
            pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.all(8),
              decoration: pw.BoxDecoration(
                color: PdfColors.grey100,
                border: pw.Border.all(color: PdfColors.grey400),
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text("CARİ ÜNVAN:", style: pw.TextStyle(font: boldFont, fontSize: 8, color: PdfColors.grey700)),
                  pw.Text("${firma['ad']}".toUpperCase(), style: pw.TextStyle(font: boldFont, fontSize: 13)),
                ],
              ),
            ),
            pw.SizedBox(height: 15),

            // EKSTRE TABLOSU
            pw.TableHelper.fromTextArray(
              headers: ['TARİH', 'AÇIKLAMA', 'ADET', 'B.FİYAT', 'BORÇ', 'ALACAK', 'BAKİYE'],
              data: tabloSatirlari,
              headerStyle: pw.TextStyle(font: boldFont, color: PdfColors.white, fontSize: 8),
              headerDecoration: const pw.BoxDecoration(color: PdfColors.blue900),
              cellStyle: pw.TextStyle(font: font, fontSize: 7.5),
              columnWidths: {
                0: const pw.FixedColumnWidth(55), // Tarih
                1: const pw.FlexColumnWidth(3),   // Açıklama
                2: const pw.FixedColumnWidth(30), // Adet
                3: const pw.FixedColumnWidth(45), // B. Fiyat
                4: const pw.FixedColumnWidth(55), // Borç
                5: const pw.FixedColumnWidth(55), // Alacak
                6: const pw.FixedColumnWidth(60), // Bakiye
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
              cellPadding: const pw.EdgeInsets.all(5),
            ),

            pw.SizedBox(height: 20),

            // GENEL TOPLAM PANELİ
            pw.Align(
              alignment: pw.Alignment.centerRight,
              child: pw.Container(
                width: 180,
                padding: const pw.EdgeInsets.all(10),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: PdfColors.blue900),
                  color: PdfColors.blue50,
                ),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text("NET BAKİYE:", style: pw.TextStyle(font: boldFont, fontSize: 10)),
                    // 'f' yerine 'formatla' kullanıyoruz
                    pw.Text("${formatla(yuruyenBakiye)} TL",
                        style: pw.TextStyle(
                            font: boldFont,
                            fontSize: 10,
                            // Bakiye artıdaysa (borç) kırmızı, eksideyse veya sıfırsa (alacak/kapalı) yeşil
                            color: yuruyenBakiye > 0 ? PdfColor.fromHex("#B71C1C") : PdfColor.fromHex("#1B5E20")
                        )),
                  ],
                ),
              ),
            ),
            pw.SizedBox(height: 50),
            pw.Center(child: pw.Text("Bu ekstre sistem tarafından otomatik oluşturulmuştur.", style: pw.TextStyle(fontSize: 7, color: PdfColors.grey500))),
          ],
        ),
      );

      // ÖNİZLEME EKRANINA GÖNDER
      if (!mounted) return;
      await Navigator.push(context, MaterialPageRoute(
        builder: (context) => Scaffold(
          appBar: AppBar(title: Text("${firma['ad']} Ekstre Önizleme"), backgroundColor: Colors.blue[900]),
          body: PdfPreview(build: (format) => pdf.save(), canDebug: false),
        ),
      ));

    } catch (e) {
      debugPrint("PDF Hatası: $e");
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Hata: $e")));
    }
  }



  void _hareketDuzenleDialog(Map<String, dynamic> h, Map<String, dynamic> f, VoidCallback basarili) {
    final tutarC = TextEditingController(text: h['tutar'].toString());
    final tarihC = TextEditingController(text: h['tarih']);
    final aciklamaC = TextEditingController(text: h['urun_adi'] ?? h['tip']);

    final double eskiTutar = double.tryParse(h['tutar'].toString()) ?? 0;
    final String tip = (h['tip'] ?? "ALIM").toString().toUpperCase();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("KAYDI DÜZENLE"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: aciklamaC, decoration: const InputDecoration(labelText: "Açıklama / Ürün")),
            TextField(controller: tutarC, decoration: const InputDecoration(labelText: "Tutar"), keyboardType: TextInputType.number),
            TextField(controller: tarihC, decoration: const InputDecoration(labelText: "Tarih (GG.AA.YYYY)")),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("İPTAL")),
          ElevatedButton(
            // ... (üst kısımlar aynı)
            onPressed: () async {
              double yeniTutar = double.tryParse(tutarC.text.replaceAll(',', '.')) ?? 0;

              double fark = yeniTutar - eskiTutar;
              double bakiyeDuzeltme = (tip == "ALIM") ? fark : -fark;

              // 2. HAREKETİ GÜNCELLE (GÜVENLİ PAKET)
              Map<String, dynamic> yeniVeri = {
                'urun_adi': aciklamaC.text.toUpperCase(),
                'tutar': yeniTutar,
                'tarih': tarihC.text,
                'is_synced': 0,
                // KRİTİK: NOT NULL hatasını önlemek için mevcut tip bilgilerini koruyoruz
                'tip': tip,
                'islem_tipi': tip,
              };

              // SQLite Güncelle
              await DatabaseHelper.instance.tarimHareketiGuncelle(h['id'].toString(), yeniVeri);

              // ... (bakiye ve firebase kısımları aynı)

              // Bakiye Güncelle (Fark kadar)
              final String cariId = (f['cari_kod'] ?? f['id']).toString();
              await DatabaseHelper.instance.tarimfirmaBakiyeGuncelle(cariId, bakiyeDuzeltme);

              // 3. FIREBASE GÜNCELLE
              try {
                await FirebaseFirestore.instance
                    .collection('tarim_firma_hareketleri')
                    .doc(h['firebase_id'] ?? h['id'].toString())
                    .update(yeniVeri);
              } catch (e) {
                print("Bulut güncelleme hatası: $e");
              }

              Navigator.pop(context);
              basarili();
            },
            child: const Text("GÜNCELLE"),
          ),
        ],
      ),
    );
  }



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
              if (image != null)_faturayiKaydet(image.path, f['cari_kod']);
              Navigator.pop(context);
            },
          ),
          ListTile(
            leading: const Icon(Icons.image, color: Colors.blue),
            title: const Text("Galeriden Fatura Seç"),
            onTap: () async {
              final XFile? image = await picker.pickImage(source: ImageSource.gallery, imageQuality: 70);
              if (image != null) _faturayiKaydet(image.path, f['cari_kod']);
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
  // 1. Parametreyi 'int firmaId' yerine 'String cariKod' yapıyoruz
  Future<void> _faturayiKaydet(String path, String cariKod) async {
    debugPrint("🚀 Fatura Yükleme Başladı. Mühür: $cariKod");

    try {
      // 2. Storage'a Yükle (Dosya adını Cari Kod ile mühürleyelim ki karışmasın)
      String? bulutUrl = await FirebaseFotoService().fotoYukle(
          FotoKategori.musteri_faturalari,
          File(path)
      );

      if (bulutUrl != null) {
        // 3. Yerel SQLite Kaydı (Mühürlü Cari Kod ile)
        await DatabaseHelper.instance.faturaEkle({
          'cari_kod': cariKod,    // 🔥 firma_id yerine cari_kod
          'dosya_yolu': bulutUrl,
          'tarih': DateFormat('dd.MM.yyyy HH:mm').format(DateTime.now()),
        });

        // 4. Firestore Kaydı (Nokta Atışı)
        // Doküman ID'sini Cari Kod yaptığımız ana koleksiyona gidiyoruz
        await FirebaseFirestore.instance
            .collection('tarim_firmalari')
            .doc(cariKod) // 🔥 Sayı ID değil, Mühürlü Cari Kod!
            .collection('faturalar')
            .add({
          'fatura_url': bulutUrl,
          'cari_kod': cariKod,
          'tarih': FieldValue.serverTimestamp(),
        });

        debugPrint("✅ Fatura buluta ve yerel veri tabanına işlendi.");
        if(mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text("✅ Fatura Buluta ve Cari Hesaba İşlendi"))
          );
        }
      }
    } catch (e) {
      debugPrint("🚨 Fatura Kayıt Hatası: $e");
    }
  }

  void _faturaGalerisiniAc(Map<String, dynamic> f) {
    String cKod = (f['cari_kod'] ?? f['id']).toString();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.black,
      builder: (context) => StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('fatura_fotograflari')
            .where('cari_kod', isEqualTo: cKod)
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          var docs = snapshot.data!.docs;
          return Column(
            children: [
              AppBar(title: Text("${f['ad']} - Galeri"), backgroundColor: Colors.transparent, foregroundColor: Colors.white),
              Expanded(
                child: docs.isEmpty
                    ? const Center(child: Text("Fatura yok.", style: TextStyle(color: Colors.white)))
                    : GridView.builder(
                  padding: const EdgeInsets.all(10),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, crossAxisSpacing: 10, mainAxisSpacing: 10),
                  itemCount: docs.length,
                  itemBuilder: (context, i) {
                    var data = docs[i].data() as Map<String, dynamic>;
                    return InkWell(
                      onTap: () => _tamEkranGoster(data['url']),
                      child: Image.network(data['url'], fit: BoxFit.cover),
                    );
                  },
                ),
              ),
            ],
          );
        },
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

  void _tamEkranGoster(String url) {
    showDialog(
      context: context,
      builder: (context) => Dialog.fullscreen(
        child: Stack(
          children: [
            InteractiveViewer(child: Center(child: Image.network(url))),
            Positioned(top: 40, right: 20, child: IconButton(
              icon: const Icon(Icons.close, color: Colors.white, size: 30),
              onPressed: () => Navigator.pop(context),
            )),
          ],
        ),
      ),
    );
  }
} // <--- STATE SINIFININ SONU






