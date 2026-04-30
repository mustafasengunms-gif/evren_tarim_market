
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../db/database_helper.dart';
import 'evren_tarim.dart';
import 'package:evren_tarim_market/widgets/hizli_secim_dialog.dart'; // Widgets içinde dediğin için yol bu
import 'musteri_satis_paneli.dart';
import 'package:evren_tarim_market/utils/pdf_helper.dart';
import 'package:flutter/foundation.dart' show kIsWeb; //
import 'dart:io' as io; // File hatasını engellemek için 'as io' dedik[cite: 1]
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'dart:io' show File;


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
    final yerel = await DatabaseHelper.instance.musteriListesiGetir();
    if (!mounted) return;
    _verileriYukleDinamik(yerel);

    try {
      final snapshot = await FirebaseFirestore.instance.collection('musteriler').get();
      if (!mounted) return;

      for (var doc in snapshot.docs) {
        Map<String, dynamic> data = doc.data();

        // 🔥 İŞTE BURASI: Timestamp hatasını engelleyen emniyet kilidi
        data.forEach((key, value) {
          if (value is Timestamp) {
            data[key] = value.toDate().toIso8601String(); // Tarihi metne çevir ki SQLite korkmasın
          }
        });

        // 🔥 ARTIK ad_norm YOK, DİREKT ad ÜZERİNDEN GİDİYORUZ
        await DatabaseHelper.instance.musteriUpsert({
          'id': doc.id,
          'ad': (data['ad'] ?? "İSİMSİZ").toString().toUpperCase().trim(),
          'tel': data['tel'] ?? "",
          'tc': data['tc'] ?? "",
          'bakiye': double.tryParse(data['bakiye']?.toString() ?? '0.0') ?? 0.0,
          'sube': (data['sube'] ?? "TEFENNİ").toString().toUpperCase(),
          'adres': data['adres'] ?? "",
          'is_synced': 1,
        });
      }

      final sonListe = await DatabaseHelper.instance.musteriListesiGetir();
      if (mounted) _verileriYukleDinamik(sonListe);

    } catch (e) {
      debugPrint("Buluta erişilemedi: $e");
    }
  }

  void _verileriYukleDinamik(List<Map<String, dynamic>> liste) {
    if (!mounted) return;

    double tAlacak = 0;
    int tSayisi = 0;
    int aSayisi = 0;

    for (var m in liste) {
      // 💥 DÜZELTME: Sadece tek bir alanı baz al.
      // Eğer hareketlerden hesaplatıyorsan SADECE bakiye_hesaplanan'ı kullan.
      // Yoksa Firebase'den gelen bakiye ile toplanıp şişer.
      double b = double.tryParse(m['bakiye_hesaplanan']?.toString() ?? '0.0') ??
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
  bool _islemlerYukleniyor = false; // İsmi farklı olsun ki diğerleriyle karışmasın
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

                List<Map<String, dynamic>> hareketler = await DatabaseHelper.instance.musteriproformaekstresi(mId);

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
    final TextEditingController aciklamaC = TextEditingController(); // 🔥 Yeni: Açıklama kutusu için
    String secilenOdeme = "NAKİT";

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("${m['ad']} - Tahsilat Al"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
                controller: miktarC,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: "Miktar", suffixText: "₺")
            ),
            const SizedBox(height: 10),
            // 🔥 Yeni: Not yazabileceğin alan
            TextField(
                controller: aciklamaC,
                decoration: const InputDecoration(
                    labelText: "Açıklama / Not",
                    hintText: "Örn: Süt parası, mahsul ödemesi vb."
                )
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              value: secilenOdeme,
              items: ["NAKİT", "KREDİ KARTI", "HAVALE"].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
              onChanged: (v) => secilenOdeme = v!,
              decoration: const InputDecoration(labelText: "Ödeme Yolu"),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("İPTAL")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            onPressed: () async {
              double miktar = double.tryParse(miktarC.text.replaceAll(',', '.')) ?? 0.0;
              if (miktar > 0) {
                String mId = m['id'].toString();

                // 🔥 Eğer açıklama boşsa eski usul otomatik yaz, doluysa senin notunu yaz
                String nihaiAciklama = aciklamaC.text.trim().isEmpty
                    ? '$secilenOdeme yoluyla tahsilat'
                    : aciklamaC.text.trim();

                await DatabaseHelper.instance.musteriBakiyeGuncelle(mId, -miktar, secilenOdeme);

                await DatabaseHelper.instance.musteriHareketEkle({
                  'musteri_id': mId,
                  'musteri_ad': m['ad'],
                  'islem': 'TAHSILAT',
                  'tutar': miktar,
                  'aciklama': nihaiAciklama, // 🔥 Artık notun buraya gidiyor
                });

                if (!mounted) return;
                Navigator.pop(context);
                _verileriYukle(); // Listeyi tazele
              }
            },
            child: const Text("KAYDET"),
          ),
        ],
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
        title: const Text("Müşteri Silinecek"),
        content: const Text("Bu müşteriyi silmek istediğinize emin misiniz?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("VAZGEÇ")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
    onPressed: () async {
    await FirebaseFirestore.instance.collection('musteriler').doc(id).delete();
    await DatabaseHelper.instance.musteriSil(id);

    if (!mounted) return;

    Navigator.of(context, rootNavigator: true).pop(); // 🔥 DAHA GÜVENLİ
    _verileriYukle();
    },
            child: const Text("SİL"),
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
    try {
      final directory = await getApplicationDocumentsDirectory();
      final String fileName = "${DateTime.now().millisecondsSinceEpoch}${p.extension(tempPath)}";
      final String kaliciYol = p.join(directory.path, fileName);
      await File(tempPath).copy(kaliciYol);

      await FirebaseFirestore.instance.collection('musteri_faturalari').add({
        'musteri_id': musteriId.toString(),
        'dosya_yolu': kaliciYol,
        'tarih': DateTime.now().toIso8601String(),
      });

      await DatabaseHelper.instance.faturaGorseliEkle(musteriId.toString(), kaliciYol);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Evrak Kaydedildi!")));
    } catch (e) {
      debugPrint("Hata: $e");
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
                return InkWell(
                  onTap: () => _tamEkranGoster(data['dosya_yolu'], fotolar[i].id, () => setStateGaleri(() {})),
                  child: Image.file(File(data['dosya_yolu']), fit: BoxFit.cover, errorBuilder: (c, e, s) => const Icon(Icons.broken_image)),
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
          Center(child: Image.file(File(yol), fit: BoxFit.contain, errorBuilder: (c,e,s) => const Text("Dosya yok", style: TextStyle(color: Colors.white)))),
          Positioned(top: 10, right: 10, child: IconButton(icon: const Icon(Icons.delete, color: Colors.red, size: 30), onPressed: () {
            Navigator.pop(c);
            _evrakSilOnay(docId, yenile);
          })),
        ],
      ),
    ));
  }

  void _evrakSilOnay(String docId, VoidCallback yenile) {
    showDialog(context: context, builder: (context) => AlertDialog(
      title: const Text("Silinsin mi?"),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text("HAYIR")),
        ElevatedButton(onPressed: () async {
          await FirebaseFirestore.instance.collection('musteri_faturalari').doc(docId).delete();
          Navigator.pop(context);
          yenile();
        }, child: const Text("EVET")),
      ],
    ));
  }
}