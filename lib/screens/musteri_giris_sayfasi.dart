import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import '../db/database_helper.dart';
import 'evren_tarim.dart';
import 'package:evren_tarim_market/widgets/hizli_secim_dialog.dart'; // Widgets içinde dediğin için yol bu
import 'musteri_satis_paneli.dart';
import 'package:evren_tarim_market/utils/pdf_helper.dart';
import 'package:flutter/foundation.dart'; // <--- BU SATIRI EKLE
import 'package:evren_tarim_market/services/firebase_foto_service.dart';
import 'package:sqflite/sqflite.dart'; // <--- Çakışma algoritmaları için bu şart


class MusteriGirisSayfasi extends StatefulWidget {
  const MusteriGirisSayfasi({super.key});


  @override
  State<MusteriGirisSayfasi> createState() => _MusteriGirisSayfasiState();
}

class _MusteriGirisSayfasiState extends State<MusteriGirisSayfasi> {
  final TextEditingController _aramaC = TextEditingController();
  List<Map<String, dynamic>> _musteriler = [];
  List<Map<String, dynamic>> _filtreliMusteriler = [];


  double toplamAlacak = 0; // Müşterilerden alacağımız para
  int tefenniSayisi = 0;
  int aksuSayisi = 0;

  final formatAraci = NumberFormat.currency(locale: 'tr_TR', symbol: '₺', decimalDigits: 2);
  bool _yukleniyor = false;

  @override
  void initState() {
    super.initState();
    _verileriYukle();
  }


  Future<void> _verileriYukle() async {
    if (_yukleniyor) return;

    setState(() {
      _yukleniyor = true;
    });

    try {
      // 1. Önce yereli oku ve ekrana anında bas
      final yerel = await DatabaseHelper.instance.musteriListesiGetir();
      _verileriYukleDinamik(yerel);

      // 2. Bulut verilerini çek
      final snapshot = await FirebaseFirestore.instance.collection('musteriler').get();

      // 🔥 Burası senin DatabaseHelper'ındaki ana db nesnesini alır (Genelde database'dir)
      final db = await DatabaseHelper.instance.database;

      // 3. SQLite Transaction Kullanarak Toplu Yazma Çakışmasını Engelle
      await db.transaction((txn) async {
        for (var doc in snapshot.docs) {
          Map<String, dynamic> data = doc.data();

          data.forEach((key, value) {
            if (value is Timestamp) {
              data[key] = value.toDate().toIso8601String();
            }
          });

          // Döngü sırasında çakışmaları REPLACE (üzerine yaz) mantığıyla çözüyoruz
          await txn.insert(
            'musteriler',
            {
              'id': doc.id,
              'ad': (data['ad'] ?? "İSİMSİZ").toString().toUpperCase().trim(),
              'tel': data['tel'] ?? "",
              'tc': data['tc'] ?? "",
              'bakiye': double.tryParse(data['bakiye']?.toString() ?? '0.0') ?? 0.0,
              'sube': (data['sube'] ?? "TEFENNİ").toString().toUpperCase(),
              'adres': data['adres'] ?? "",
              'is_synced': 1,
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
      });

      // 4. Her şey bittikten sonra temiz veriyi son kez çek
      final sonListe = await DatabaseHelper.instance.musteriListesiGetir();
      _verileriYukleDinamik(sonListe);

    } catch (e) {
      debugPrint("Senkronizasyon hatası: $e");
    } finally {
      if (mounted) {
        setState(() {
          _yukleniyor = false;
        });
      }
    }
  }

  void _verileriYukleDinamik(List<Map<String, dynamic>> liste) {
    if (!mounted) return;

    double tAlacak = 0;
    int tSayisi = 0;
    int aSayisi = 0;

    for (var m in liste) {
      double b = double.tryParse(m['bakiye_hesaplanan']?.toString() ?? '') ??
          double.tryParse(m['bakiye']?.toString() ?? '0.0') ?? 0.0;

      if (b > 0) tAlacak += b;

      String s = (m['sube_guncel'] ?? m['sube'] ?? "").toString().toUpperCase();
      if (s == "TEFENNİ") tSayisi++; else if (s == "AKSU") aSayisi++;
    }

    setState(() {
      _musteriler = liste;
      _filtreliMusteriler = liste;
      toplamAlacak = tAlacak;
      tefenniSayisi = tSayisi;
      aksuSayisi = aSayisi;
    });
  }

  void _filtrele(String kelime) {
    String aranan = kelime.toLowerCase().trim();
    setState(() {
      _filtreliMusteriler = _musteriler.where((m) {
        String musteriAdi = (m['ad'] ?? "").toString().toLowerCase();
        String musteriTc = (m['tc'] ?? "").toString();
        return musteriAdi.contains(aranan) || musteriTc.contains(aranan);
      }).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[200],
      appBar: AppBar(
        title: const Text("MÜŞTERİ MERKEZİ"),
        backgroundColor: Colors.blue[900],
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          _ozetPanel(),
          _aksiyonBar(),
          _aramaCubugu(),
          Expanded(
            child: ListView.builder(
              itemCount: _filtreliMusteriler.length,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              itemBuilder: (context, index) => _musteriKart(_filtreliMusteriler[index]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _ozetPanel() => Container(
    padding: const EdgeInsets.all(15),
    color: Colors.blue[900],
    child: Row(
      children: [
        _ozetKutu("TOPLAM ALACAK", toplamAlacak, Colors.green[300]!),
        const SizedBox(width: 10),
        _ozetKutu("TEFENNİ/AKSU", "$tefenniSayisi / $aksuSayisi Kişi", Colors.white70),
      ],
    ),
  );

  Widget _ozetKutu(String t, dynamic m, Color c) => Expanded(
    child: Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
      child: Column(children: [
        Text(t, style: TextStyle(color: c, fontSize: 11, fontWeight: FontWeight.bold)),
        const SizedBox(height: 5),
        if (m is double)
          Text("${NumberFormat.currency(locale: 'tr_TR', symbol: '', decimalDigits: 2).format(m)} ₺",
              style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold))
        else
          Text(m.toString(), style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
      ]),
    ),
  );

  Widget _aksiyonBar() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _ustButon(Icons.person_add_alt_1, "Müşteri Ekle", Colors.blue[900]!, () => _musteriFormDialog(null)),
          _ustButon(Icons.shopping_cart, "Yeni Satış", Colors.red[800]!, () {
            hizliSecimDialog(
              context: context,
              tip: "SATIŞ",
              musteriler: _musteriler,
              onSecim: (m, tip) => _satisaGit(m, satisTipi: tip),
            );
          }),
          _ustButon(Icons.assignment, "Ekstreler", Colors.orange[900]!, () {
            hizliSecimDialog(
              context: context,
              tip: "EKSTRE",
              musteriler: _musteriler,
              onSecim: (m, _) async {
                // 🚀 BURASI DİREKT PDF MOTORU
                String mId = (m['id'] ?? m['tc'] ?? "").toString();
                String mAd = (m['ad'] ?? "Müşteri").toString().toUpperCase();

                List<Map<String, dynamic>> hareketler = await DatabaseHelper.instance.musteriEkstresiGetir(mId);

                if (context.mounted) {
                  if (hareketler.isNotEmpty) {
                    await PdfHelper.musteriEkstresiGoster(context, mAd, hareketler);
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Hareket yok!")));
                  }
                }
              },
            );
          }),
          _ustButon(Icons.camera_alt, "Evrak Foto", Colors.purple[800]!, () => _evrakFotoEkle()),
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
        hintText: "Müşteri adı veya TC ara...",
        prefixIcon: const Icon(Icons.search),
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
      ),
    ),
  );

  Widget _musteriKart(Map<String, dynamic>? m) {
    if (m == null) return const SizedBox.shrink();

    double bakiye = 0.0;
    try {
      bakiye = double.parse(m['bakiye']?.toString() ?? '0.0');
    } catch (e) {
      bakiye = 0.0;
    }

    String musteriAdi = (m['ad']?.toString() ?? "İSİMSİZ MÜŞTERİ").trim().toUpperCase();
    String ilkHarf = musteriAdi.isNotEmpty ? musteriAdi[0] : "?";

    return Card(
      elevation: 2,
      margin: const EdgeInsets.symmetric(vertical: 5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ExpansionTile(
        leading: CircleAvatar(
          backgroundColor: (m['sube']?.toString() == "TEFENNİ") ? Colors.green[700] : Colors.blue[800],
          child: Text(ilkHarf, style: const TextStyle(color: Colors.white)),
        ),
        title: Text(musteriAdi, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text("TC: ${m['tc'] ?? '-'} | Şube: ${m['sube'] ?? '-'}"),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.collections, color: Colors.orange, size: 26),
              onPressed: () => _faturaGalerisiniAc(m),
            ),
            const SizedBox(width: 5),
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  formatAraci.format(bakiye),
                  style: TextStyle(
                      color: bakiye > 0 ? Colors.red : Colors.green[700],
                      fontWeight: FontWeight.bold,
                      fontSize: 16
                  ),
                ),
                Text(
                  bakiye > 0 ? "BİZE BORÇLU" : "HESAP TEMİZ",
                  style: TextStyle(color: bakiye > 0 ? Colors.red : Colors.green, fontSize: 9, fontWeight: FontWeight.bold),
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
                Text("📞 Telefon: ${m['tel'] ?? m['telefon'] ?? 'Girilmemiş'}"),
                Text("📍 Adres: ${m['adres'] ?? 'Girilmemiş'}"),
                const Divider(),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _kucukAksiyonButon(Icons.shopping_cart, "Satış Yap", Colors.red, () {
                      hizliSecimDialog(
                        context: context,
                        tip: "SATIŞ",
                        musteriler: [m], // Sadece bu müşteriyi listeye gönderiyoruz
                        onSecim: (secilenMusteri, satisTipi) => _satisaGit(secilenMusteri, satisTipi: satisTipi),
                      );
                    }),
                    _kucukAksiyonButon(Icons.monetization_on, "Tahsilat", Colors.green, () => _tahsilatDialog(m)),
                    _kucukAksiyonButon(Icons.list_alt, "Ekstre", Colors.teal, () async {

                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => MusteriEkstreSayfasi(
                            musteriId: (m['id'] ?? m['tc'] ?? "").toString(),
                            musteriAd: (m['ad'] ?? "Müşteri").toString().toUpperCase(),
                          ),
                        ),
                      );
                      _verileriYukle();
                    }),
                    _kucukAksiyonButon(Icons.camera_alt, "Evrak Ekle", Colors.orange, () => _direktEvrakFotoCek(m)),
                    _kucukAksiyonButon(Icons.edit, "Düzenle", Colors.blue, () => _musteriFormDialog(m)),
                    _kucukAksiyonButon(Icons.delete, "Sil", Colors.grey, () {
                      final hamId = m['id']?.toString() ?? "";
                      if (hamId.isNotEmpty) _musteriSilOnay(hamId);
                    }),
                  ],
                )
              ],
            ),
          )
        ],
      ),
    );
  }

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

  void _musteriFormDialog(Map<String, dynamic>? m) {
    final adC = TextEditingController(text: m?['ad']);
    final tcC = TextEditingController(text: m?['tc']);
    final telC = TextEditingController(text: m?['tel']);
    final adresC = TextEditingController(text: m?['adres']);
    String seciliSube = m?['sube'] ?? "TEFENNİ";

    showDialog(
      context: context,
      barrierDismissible: false, // İşlem bitmeden dışarı tıklayıp kapatmasın
      builder: (c) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          titlePadding: EdgeInsets.zero,
          title: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.blue[900],
              borderRadius: const BorderRadius.only(topLeft: Radius.circular(20), topRight: Radius.circular(20)),
            ),
            child: Row(
              children: [
                Icon(m == null ? Icons.person_add : Icons.edit, color: Colors.white),
                const SizedBox(width: 10),
                Text(m == null ? "YENİ MÜŞTERİ KAYDI" : "MÜŞTERİ DÜZENLE",
                    style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 10),
                _modernInput(adC, "Ad Soyad", Icons.person, textCapitalization: TextCapitalization.characters),

                // 🔥 TC NO: 11 hane sınırı ve rakam klavyesi eklendi
                _modernInput(
                  tcC,
                  "TC Kimlik No",
                  Icons.badge,
                  keyboard: TextInputType.number,
                  maxLength: 11, // En fazla 11 hane
                ),

                _modernInput(telC, "Telefon Numarası", Icons.phone, keyboard: TextInputType.phone),
                _modernInput(adresC, "Yerleşim Adresi", Icons.location_on, lines: 2),

                const SizedBox(height: 10),
                // Şube Seçimi Modern Görünüm
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade400),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButtonFormField<String>(
                      value: ["TEFENNİ", "AKSU"].contains(seciliSube) ? seciliSube : "TEFENNİ",
                      decoration: const InputDecoration(border: InputBorder.none, labelText: "Çalıştığı Şube"),
                      items: ["TEFENNİ", "AKSU"].map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                      onChanged: (v) => setDialogState(() => seciliSube = v!),
                    ),
                  ),
                ),
              ],
            ),
          ),
          actionsPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: Text("VAZGEÇ", style: TextStyle(color: Colors.grey[600], fontWeight: FontWeight.bold)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue[900],
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                padding: const EdgeInsets.symmetric(horizontal: 25, vertical: 12),
              ),
              // ... senin kodundaki ElevatedButton başlagıcı
              onPressed: _yukleniyor ? null : () async {
                // ⌨️ 1. ADIM: Önce klavyeyi kapat ki sistem nefes alsın
                FocusScope.of(context).unfocus();

                // 🛑 2. ADIM: Boş isim kontrolü (zaten vardı)
                if (adC.text.trim().isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Lütfen Ad Soyad girin!")));
                  return;
                }

                // ⏳ 3. ADIM: Yükleme durumuna geç
                setState(() => _yukleniyor = true);
                setDialogState(() {});

                try {
                  // 🆔 4. ADIM: TC'yi ID yapma mantığı (Nisan 2026 projesi kapsamında)
                  String mId;
                  if (m == null) {
                    mId = tcC.text.trim().isNotEmpty
                        ? tcC.text.trim()
                        : (telC.text.trim().isNotEmpty ? telC.text.trim() : DateTime.now().millisecondsSinceEpoch.toString());
                  } else {
                    mId = m['id'].toString();
                  }

                  Map<String, dynamic> veri = {
                    'id': mId,
                    'ad': adC.text.toUpperCase().trim(),
                    'tc': tcC.text.trim(),
                    'tel': telC.text.trim(),
                    'adres': adresC.text.trim(),
                    'sube': seciliSube,
                    'bakiye': m?['bakiye'] ?? 0.0,
                    'is_synced': 1,
                  };

                  // ☁️ 5. ADIM: Firestore Kaydı
                  await FirebaseFirestore.instance
                      .collection('musteriler')
                      .doc(mId)
                      .set(veri, SetOptions(merge: true));

                  // 💾 6. ADIM: Yerel SQLite Kaydı
                  if (m == null) {
                    await DatabaseHelper.instance.musteriEkle(veri);
                  } else {
                    await DatabaseHelper.instance.musteriGuncelle(mId, veri);
                  }

                  // ✅ 7. ADIM: Kapatma
                  if (!mounted) return;
                  setState(() => _yukleniyor = false);

                  // MIUI hatasını önlemek için rootNavigator: true kullanabilirsin
                  Navigator.of(context, rootNavigator: true).pop();
                  _verileriYukle();

                } catch (e) {
                  if (mounted) setState(() => _yukleniyor = false);
                  setDialogState(() {});
                  print("Hata: $e");
                }
              },
              child: _yukleniyor
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text("KAYDET", style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

// Modern Input Yardımcı Widget'ı
  Widget _modernInput(TextEditingController c, String label, IconData icon,
      {TextInputType keyboard = TextInputType.text, int lines = 1, int? maxLength, TextCapitalization textCapitalization = TextCapitalization.none}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 15),
      child: TextField(
        controller: c,
        keyboardType: keyboard,
        maxLines: lines,
        maxLength: maxLength,
        textCapitalization: textCapitalization,
        // maxLength eklendiğinde altta çıkan karakter sayacını gizlemek için:
        buildCounter: (context, {required currentLength, required isFocused, maxLength}) => null,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon, color: Colors.blue[900]),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.blue.shade900, width: 2),
          ),
          contentPadding: const EdgeInsets.symmetric(vertical: 15, horizontal: 10),
        ),
      ),
    );
  }


  void _tahsilatDialog(Map<String, dynamic> m) {
    final TextEditingController miktarC = TextEditingController();
    final TextEditingController aciklamaC = TextEditingController();

    String secilenOdeme = "NAKİT";
    bool isProcessing = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
            title: Text("${m['ad']?.toString().toUpperCase()} - Tahsilat Al"),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: miktarC,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: "Miktar",
                    suffixText: "₺",
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: aciklamaC,
                  decoration: const InputDecoration(
                    labelText: "Aciklama / Not",
                  ),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: secilenOdeme, // value yerine initialValue yapildi
                  items: const ["NAKİT", "KREDİ KARTI", "HAVALE"]
                      .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                      .toList(),
                  onChanged: (v) => secilenOdeme = v!,
                  decoration: const InputDecoration(labelText: "Odeme Yolu"),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: isProcessing ? null : () => Navigator.pop(context),
                child: const Text("İPTAL"),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                onPressed: isProcessing
                    ? null
                    : () async {
                  if (isProcessing) return;

                  double miktar = double.tryParse(
                      miktarC.text.replaceAll(',', '.')) ??
                      0.0;

                  if (miktar <= 0) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text("Lutfen gecerli bir miktar girin!")),
                    );
                    return;
                  }

                  setStateDialog(() => isProcessing = true);
                  setState(() => _yukleniyor = true);

                  final String mId = m['id'].toString();
                  final String aciklama = aciklamaC.text.trim().isEmpty
                      ? "$secilenOdeme tahsilat"
                      : aciklamaC.text.trim();

                  // Degisken ismi muhurluIslemId olarak guncellendi (Turkce karakter icermez)
                  final String muhurluIslemId = "HL_${mId}_${DateTime.now().millisecondsSinceEpoch}";
                  final docRef = FirebaseFirestore.instance.collection('musteri_hareketleri').doc(muhurluIslemId);

                  try {
                    await docRef.set({
                      'id': muhurluIslemId,
                      'musteri_id': mId,
                      'musteri_ad': m['ad'],
                      'islem': 'TAHSILAT',
                      'tutar': miktar,
                      'aciklama': aciklama,
                      'tarih': DateFormat('dd.MM.yyyy').format(DateTime.now()),
                      'server_tarih': FieldValue.serverTimestamp(),
                      'sqlite_id': muhurluIslemId,
                      'is_synced': 1,
                    });

                    final mDataOncesi = await DatabaseHelper.instance.getMusteri(mId);
                    final double eskiBakiye = double.tryParse(mDataOncesi['bakiye'].toString()) ?? 0.0;
                    final double yeniBakiye = eskiBakiye - miktar;

                    await FirebaseFirestore.instance
                        .collection('musteriler')
                        .doc(mId)
                        .set({
                      'bakiye': yeniBakiye,
                      'son_islem': 'TAHSILAT',
                      'guncelleme': FieldValue.serverTimestamp(),
                    }, SetOptions(merge: true));

                    await DatabaseHelper.instance.musteriBakiyeGuncelle(mId, -miktar, secilenOdeme);

                    await DatabaseHelper.instance.musteriHareketEkle({
                      'id': muhurluIslemId,
                      'musteri_id': mId,
                      'musteri_ad': m['ad'],
                      'islem': 'TAHSILAT',
                      'tutar': miktar,
                      'aciklama': aciklama,
                      'tarih': DateFormat('dd.MM.yyyy').format(DateTime.now()),
                      'is_synced': 1,
                    });

                    if (context.mounted) {
                      Navigator.pop(context);
                    }
                    _verileriYukle();

                  } catch (e) {
                    print("Hata: $e");

                    try {
                      await DatabaseHelper.instance.musteriBakiyeGuncelle(mId, -miktar, secilenOdeme);
                      await DatabaseHelper.instance.musteriHareketEkle({
                        'id': muhurluIslemId,
                        'musteri_id': mId,
                        'musteri_ad': m['ad'],
                        'islem': 'TAHSILAT',
                        'tutar': miktar,
                        'aciklama': aciklama,
                        'tarih': DateFormat('dd.MM.yyyy').format(DateTime.now()),
                        'is_synced': 0,
                      });
                    } catch (sqliteE) {
                      print("SQLite Hata: $sqliteE");
                    }

                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text("Islem yerel hafizaya muhurlendi. ($e)"),
                          backgroundColor: Colors.orange,
                        ),
                      );
                      Navigator.pop(context);
                    }
                    _verileriYukle();
                  } finally {
                    if (context.mounted) setStateDialog(() => isProcessing = false);
                    if (mounted) setState(() => _yukleniyor = false);
                  }
                },
                child: isProcessing
                    ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                )
                    : const Text("KAYDET"),
              ),
            ],
          );
        },
      ),
    );
  }

  void _satisaGit(Map<String, dynamic> m, {String satisTipi = "AÇIK HESAP"}) async {
    // 🔥 ad_norm KALDIRILDI, SADECE ad VE tc ÜZERİNDEN GİDİYORUZ
    String id = (m['id'] ?? m['tc'] ?? "").toString().trim();
    String tc = (m['tc'] ?? m['id'] ?? "").toString().trim();
    String ad = (m['ad'] ?? "İSİMSİZ").toString().trim(); // Sadece ad kalsın

    print("🛠️ NAV: id=$id tc=$tc ad=$ad");

    try {
      final stoklar = await DatabaseHelper.instance.stokListesiGetir();

      if (!mounted) return;

      // 🔥 TEMİZ MÜŞTERİ VERİSİ
      final musteri = {
        'id': id,
        'tc': tc,
        'ad': ad,
      };

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => MusteriSatisPaneli(
            secilenMusteri: musteri,
            mevcutStoklar: stoklar,
            ilkOdemeTipi: satisTipi,
            // Şube kontrolünü de garantiye alalım
            seciliSube: (m['sube']?.toString().toUpperCase() == "AKSU") ? 1 : 0,
          ),
        ),
      );

    } catch (e) {
      print("🚨 SATIŞ NAV HATA: $e");
    }
  }

  void _ekstreyeGit(Map<String, dynamic> m) {
    // 🆔 1. Kimlik tespiti
    String mId = (m['id'] ?? m['musteriId'] ?? m['tc'] ?? "").toString().trim();
    String mAd = (m['ad'] ?? "İSİMSİZ").toString().toUpperCase();

    if (mId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text("Hata: Müşteriye ait geçerli bir ID/TC bulunamadı!"),
            backgroundColor: Colors.red
        ),
      );
      return;
    }

    // 🕵️‍♂️ DEBUG
    print("📄 EKSTRE KÖPRÜSÜ ÇALIŞTI -> İsim: $mAd | Gönderilen ID: $mId");

    // 🚀 2. Sayfaya Gönderiyoruz
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => MusteriEkstreSayfasi(
          musteriId: mId, // Bu ID ile ekstre sayfasında işlemler yapılacak
          musteriAd: mAd,
        ),
      ),
    );
  }


  void _musteriSilOnay(String id) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("DİKKAT: Tam Temizlik"),
        content: const Text("Bu müşteriyi sildiğinizde ona ait TÜM satış ve tahsilat geçmişi de silinecektir. Emin misiniz?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("VAZGEÇ")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              try {
                // ==========================================
                // 1. CLOUD FIREBASE TEMİZLİĞİ
                // ==========================================

                // A. Müşteri Kartını Sil
                await FirebaseFirestore.instance.collection('musteriler').doc(id).delete();

                // B. musteri_hareketleri Koleksiyonundan Sil
                var hareketler = await FirebaseFirestore.instance
                    .collection('musteri_hareketleri')
                    .where('musteri_id', isEqualTo: id)
                    .get();

                for (var doc in hareketler.docs) {
                  await doc.reference.delete();
                }

                // 🔥 C. YENİ: satislar Koleksiyonundan Sil (Ekran görüntüsündeki kaçak alan)
                var satislar = await FirebaseFirestore.instance
                    .collection('satislar')
                    .where('musteri_id', isEqualTo: id)
                    .get();

                for (var doc in satislar.docs) {
                  await doc.reference.delete();
                }


                // ==========================================
                // 2. YEREL SQLITE TEMİZLİĞİ
                // ==========================================

                // A. Müşteri Kartını Sil
                await DatabaseHelper.instance.musteriSil(id);

                // B. Müşterinin Tüm Hareketlerini Sil
                await DatabaseHelper.instance.musteriTumHareketleriniSil(id);

                // 🔥 C. YENİ: SQLite satislar Tablosundan Sil
                // (DatabaseHelper'da bu metodun olup olmadığını kontrol et, yoksa aşağıya ekledim)
                try {
                  await DatabaseHelper.instance.musteriSatislariniSil(id);
                } catch (sqliteErr) {
                  print("Lokal satış silme esnasında hata (Metot eksik olabilir): $sqliteErr");
                }


                print("✅ Müşteri, hareketleri ve tüm satış kayıtları buluttan ve yerelden kazındı.");

                if (!mounted) return;
                Navigator.of(context, rootNavigator: true).pop();
                _verileriYukle();

              } catch (e) {
                print("🚨 Silme hatası: $e");
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text("Silme başarısız: $e"), backgroundColor: Colors.red),
                  );
                }
              }
            },
            child: const Text("HER ŞEYİ SİL"),
          ),
        ],
      ),
    );
  }

  Future<void> _direktEvrakFotoCek(Map<String, dynamic> m) async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.camera, imageQuality: 70);
    if (image != null) _evrakKaydet(image.path, m['id']);
  }

  void _evrakFotoEkle() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => ListView.builder(
        itemCount: _musteriler.length,
        itemBuilder: (context, i) => ListTile(
          leading: const Icon(Icons.person, color: Colors.purple),
          title: Text(_musteriler[i]['ad']),
          onTap: () {
            Navigator.pop(context);
            _fotoSecimMenusu(_musteriler[i]);
          },
        ),
      ),
    );
  }

  void _fotoSecimMenusu(Map<String, dynamic> m) {
    final ImagePicker picker = ImagePicker();
    showModalBottomSheet(
      context: context,
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.camera_alt),
            title: const Text("Kameradan Çek"),
            onTap: () async {
              final XFile? image = await picker.pickImage(source: ImageSource.camera, imageQuality: 70);
              if (image != null) _evrakKaydet(image.path, m['id']);
              Navigator.pop(context);
            },
          ),
          ListTile(
            leading: const Icon(Icons.image),
            title: const Text("Galeriden Seç"),
            onTap: () async {
              final XFile? image = await picker.pickImage(source: ImageSource.gallery, imageQuality: 70);
              if (image != null) _evrakKaydet(image.path, m['id']);
              Navigator.pop(context);
            },
          ),
          ListTile(
            leading: const Icon(Icons.collections, color: Colors.orange),
            title: const Text("Eski Evrakları Gör"),
            onTap: () {
              Navigator.pop(context);
              _faturaGalerisiniAc(m);
            },
          ),
        ],
      ),
    );
  }
  void _evrakKaydet(String tempPath, dynamic musteriId) async {
    setState(() => _yukleniyor = true); // Varsa loading başlat

    try {
      // --- 1. DOSYAYI HAZIRLA ---
      File dosya = File(tempPath);

      // --- 2. FIREBASE STORAGE'A YÜKLE (Buluuta Atıyoruz) ---
      // Yazdığımız servisi çağırıyoruz. Kategori: musteri_faturalari
      String? bulutUrl = await FirebaseFotoService().fotoYukle(
          FotoKategori.musteri_faturalari,
          dosya
      );

      if (bulutUrl != null) {
        // --- 3. FIREBASE FIRESTORE KAYDI (Ortak Linki Yazıyoruz) ---
        await FirebaseFirestore.instance.collection('musteri_faturalari').add({
          'musteri_id': musteriId.toString(),
          'dosya_yolu': bulutUrl, // Artık kalıcı internet linkini yazıyoruz abi
          'tarih': DateTime.now().toIso8601String(),
          'server_tarih': FieldValue.serverTimestamp(),
        });

        // --- 4. YEREL DB KAYDI (SQLite) ---
        // SQLite'a da bulut linkini kaydediyoruz ki internet varken oradan çeksin
        await DatabaseHelper.instance.faturaGorseliEkle(
            musteriId.toString(),
            bulutUrl
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text("Evrak Buluta Yüklendi ve Kaydedildi! ✅"))
          );
        }
      } else {
        throw "Fotoğraf buluta yüklenemedi, internetinizi kontrol edin.";
      }

    } catch (e) {
      debugPrint("❌ Evrak Kayıt Hatası: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Hata oluştu: $e"), backgroundColor: Colors.red)
        );
      }
    } finally {
      if (mounted) setState(() => _yukleniyor = false);
    }
  }

  void _faturaGalerisiniAc(Map<String, dynamic> m) {
    Navigator.push(context, MaterialPageRoute(builder: (c) => StatefulBuilder(
      builder: (context, setStateGaleri) => Scaffold(
        appBar: AppBar(title: Text("${m['ad']} Evrakları"), backgroundColor: Colors.orange[900]),
        body: FutureBuilder<QuerySnapshot>(
          future: FirebaseFirestore.instance.collection('musteri_faturalari').where('musteri_id', isEqualTo: m['id'].toString()).get(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
            final fotolar = snapshot.data?.docs ?? [];
            if (fotolar.isEmpty) return const Center(child: Text("Evrak bulunamadı."));
            return GridView.builder(
              padding: const EdgeInsets.all(10),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, crossAxisSpacing: 8, mainAxisSpacing: 8),
              itemCount: fotolar.length,
              itemBuilder: (context, i) {
                var data = fotolar[i].data() as Map<String, dynamic>;
                String yol = data['dosya_yolu'] ?? "";

                return InkWell(
                  onTap: () => _tamEkranGoster(yol, fotolar[i].id, () => setStateGaleri(() {})),
                  // 🔥 DEĞİŞİKLİK: Image.file yerine Image.network kullanıyoruz
                  child: yol.startsWith('http')
                      ? Image.network(yol, fit: BoxFit.cover, errorBuilder: (c, e, s) => const Icon(Icons.broken_image))
                      : Image.file(File(yol), fit: BoxFit.cover, errorBuilder: (c, e, s) => const Icon(Icons.broken_image)),
                );
              },
            );
          },
        ),
      ),
    )));
  }

  void _tamEkranGoster(String yol, String docId, VoidCallback yenile) {
    showDialog(context: context, builder: (c) => Dialog(
      backgroundColor: Colors.black,
      child: Stack(
        children: [
          // 🔥 DEĞİŞİKLİK: Tam ekran gösterimde de bulut desteği
          Center(
            child: yol.startsWith('http')
                ? Image.network(yol, fit: BoxFit.contain)
                : Image.file(File(yol), fit: BoxFit.contain),
          ),
          Positioned(top: 10, right: 10, child: IconButton(icon: const Icon(Icons.delete, color: Colors.red, size: 30), onPressed: () {
            Navigator.pop(c);
            _evrakSilOnay(docId, yol, yenile); // 🔥 Yol bilgisini de gönderiyoruz
          })),
        ],
      ),
    ));
  }

  void _evrakSilOnay(String docId, String fotoUrl, VoidCallback yenile) {
    showDialog(context: context, builder: (context) => AlertDialog(
      title: const Text("Bu evrak kalıcı olarak silinsin mi?"),
      content: const Text("Bu işlem geri alınamaz ve fotoğraf buluttan da silinir."),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text("HAYIR")),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
          onPressed: () async {
            // 1. Önce Storage'dan (buluttan) gerçek dosyayı sil
            await FirebaseFotoService().fotoSil(fotoUrl);

            // 2. Sonra Firestore'daki kaydı sil
            await FirebaseFirestore.instance.collection('musteri_faturalari').doc(docId).delete();

            if (context.mounted) Navigator.pop(context);
            yenile(); // Galeriyi tazele
          },
          child: const Text("SİL"),
        ),
      ],
    ));
  }
}