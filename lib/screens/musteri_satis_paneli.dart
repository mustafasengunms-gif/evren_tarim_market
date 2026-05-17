import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../db/database_helper.dart';
import '../models/CekModel.dart';
import 'package:flutter/foundation.dart' show kIsWeb;


class MusteriSatisPaneli extends StatefulWidget {
  final Map<String, dynamic> secilenMusteri;
  final List<Map<String, dynamic>> mevcutStoklar;
  final int seciliSube;
  final String ilkOdemeTipi; // <--- DOĞRU YER BURASI (Yukarı aldık)


  const MusteriSatisPaneli({
    super.key,
    required this.secilenMusteri,
    required this.mevcutStoklar,
    required this.seciliSube,
    this.ilkOdemeTipi = "AÇIK HESAP", // <--- DIŞARIDAN GELENİ BURASI KARŞILAR
  });

  @override
  State<MusteriSatisPaneli> createState() => _MusteriSatisPaneliState();
}

class _MusteriSatisPaneliState extends State<MusteriSatisPaneli> {
  final formatTR = NumberFormat.currency(locale: 'tr_TR', symbol: 'TL', decimalDigits: 2);
  List<Map<String, dynamic>> _stoklar = [];
  List<Map<String, dynamic>> _sepet = [];
  String _odemeTipi = "AÇIK HESAP";
  DateTime _secilenTarih = DateTime.now();
  double _toplamTutar = 0;
  bool _islemYapiliyor = false;

  @override
  void initState() {
    super.initState();
    _odemeTipi = widget.ilkOdemeTipi;
    // Dışarıdan gelen stokları direkt içeri aktar
    _stoklar = List.from(widget.mevcutStoklar);

    // Eğer dışarıdan gelen boşsa o zaman veritabanına bak
    if (_stoklar.isEmpty) {
      _stoklariTazele();
    }
  }

  Future<void> _stoklariTazele() async {
    final veriler = await DatabaseHelper.instance.stokListesiGetir();
    if (mounted) setState(() => _stoklar = veriler);
  }

  void _sepeteEkle(Map<String, dynamic> urun, int adet, double fiyat) {
    setState(() {
      // String birleştirmelerimizi güvenli yapıyoruz
      String marka = (urun['marka'] ?? '').toString().trim();
      String model = (urun['model'] ?? urun['urun'] ?? '').toString().trim();
      String altModel = (urun['alt_model'] ?? urun['altmodel'] ?? '').toString().trim();

      // Listelerde ve sepet başlığında görünecek tam ad
      String ad = "$marka $model $altModel".replaceAll(RegExp(r'\s+'), ' ').trim();

      _sepet.add({
        "id": urun['id'].toString(),
        "ad": ad,
        "adet": adet,
        "fiyat": fiyat,
        "toplam": adet * fiyat, // Burada 1 x 75000 = 75000 doğru.
        // 🔥 İŞTE BURAYA YENİ ALANLARI EKLEDİK ABİ:
        "kategori": urun['kategori'] ?? urun['kategori_ad'] ?? '',
        "marka": marka,
        "model": model,
        "alt_model": altModel,
      });

      // 🔥 DEĞİŞİKLİK BURADA: Sıfırdan hesapla ki üzerine ekleme yapmasın
      double yeniToplam = 0;
      for (var item in _sepet) {
        yeniToplam += (item['toplam'] as double);
      }
      _toplamTutar = yeniToplam;
    });
  }

  Future<void> _satisiKaydet() async {

    // 🔥 ÇİFT TIK / MÜKERRER KAYIT KİLİDİ
    if (_islemYapiliyor) {
      print("⛔ BLOKE: İşlem zaten devam ediyor!");
      return;
    }

    // 🔒 LOCK
    _islemYapiliyor = true;

    if (mounted) {
      setState(() {});
    }

    print("\n🚀🚀🚀 [MÜHÜRLÜ SATIŞ BAŞLADI] 🚀🚀🚀");

    try {

      // 🛡️ [YENİ ADIM] STOK KONTROL BARİYERİ (Eksiye düşmeyi engeller)
      for (var item in _sepet) {
        final String urunId = item['id'].toString();
        final int satilanAdet =
        (double.tryParse(item['adet'].toString()) ?? 0.0).toInt();

        final urunBilgisi = _stoklar.firstWhere(
              (u) => u['id'].toString() == urunId,
          orElse: () => {},
        );

        if (urunBilgisi.isNotEmpty) {

          int mevcutStok = (double.tryParse(
              (urunBilgisi['adet'] ??
                  urunBilgisi['stok_adet'] ??
                  '0').toString()) ??
              0.0)
              .toInt();

          if (satilanAdet > mevcutStok) {

            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    "❌ Yetersiz Stok! ${item['ad']} ürününden elinde sadece $mevcutStok adet var, sen $satilanAdet adet satmaya çalışıyorsun!",
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  backgroundColor: Colors.red[900],
                  duration: const Duration(seconds: 4),
                ),
              );
            }

            return;
          }
        }
      }

      // 🆔 1. MÜŞTERİ ID ÇÖZÜMLEME
      String mId = (
          widget.secilenMusteri['musteriId'] ??
              widget.secilenMusteri['id'] ??
              widget.secilenMusteri['tc'] ??
              ""
      ).toString().trim();

      print("🆔 [ADIM 1] Kullanılacak Müşteri ID: '$mId'");

      if (mId.isEmpty) {
        print("❌ [HATA] Müşteri ID hiçbir alandan okunamadı!");
        return;
      }

      // 🔥 5 SANİYELİK MÜKERRER ENGELLEYİCİ
      String tekilIslemKey =
          "${mId}_${DateTime.now().millisecondsSinceEpoch ~/ 5000}";

      // ☁️ FIRESTORE'DA AYNI SATIŞ VAR MI?
      final mevcutSatis = await FirebaseFirestore.instance
          .collection('satislar')
          .where('islem_key', isEqualTo: tekilIslemKey)
          .limit(1)
          .get();

      if (mevcutSatis.docs.isNotEmpty) {
        print("⛔ MÜKERRER SATIŞ ENGELLENDİ!");

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Bu satış zaten kaydedilmiş!"),
              backgroundColor: Colors.orange,
            ),
          );
        }

        return;
      }

      // 🔑 KESİN ID MÜHÜRLEME
      String zamanMuhu =
      DateTime.now().millisecondsSinceEpoch.toString();

      String nihaiIslemId =
          "HL_${mId}_$zamanMuhu";

      // 📦 2. STOK DÜŞ
      print("📦 [ADIM 2] Stoklar düşülüyor...");

      // 🛡️ EK GÜVENLİ KONTROL
      for (var item in _sepet) {

        final String urunId =
        item['id'].toString().trim();

        final double satilanAdet =
            double.tryParse(item['adet'].toString()) ?? 0.0;

        final urunBilgisi = _stoklar.firstWhere(
              (u) => u['id'].toString().trim() == urunId,
          orElse: () => <String, dynamic>{},
        );

        if (urunBilgisi.isNotEmpty) {

          double mevcutStok = double.tryParse(
              (urunBilgisi['adet'] ??
                  urunBilgisi['stok_adet'] ??
                  '0').toString()) ??
              0.0;

          if (satilanAdet > mevcutStok) {

            if (mounted) {
              showDialog(
                context: context,
                barrierDismissible: false,
                builder: (BuildContext dialogContext) {

                  return AlertDialog(
                    title: Row(
                      children: const [
                        Icon(Icons.error, color: Colors.red),
                        SizedBox(width: 10),
                        Text("Stok Yetersiz!"),
                      ],
                    ),
                    content: Text(
                      "${item['ad']} ürününden elinde sadece ${mevcutStok.toStringAsFixed(0)} adet var.\n\nSen ${satilanAdet.toStringAsFixed(0)} adet satmaya çalışıyorsun!",
                      style: const TextStyle(fontSize: 16),
                    ),
                    actions: [
                      TextButton(
                        child: const Text(
                          "Anladım, Düzenle",
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        onPressed: () =>
                            Navigator.of(dialogContext).pop(),
                      ),
                    ],
                  );
                },
              );
            }

            return;
          }
        }
      }

      // 📦 GERÇEK STOK DÜŞÜMÜ
      for (var item in _sepet) {

        final String urunId =
        item['id'].toString().trim();

        final double satilanAdet =
            double.tryParse(item['adet'].toString()) ?? 0.0;

        await DatabaseHelper.instance
            .stokDus(urunId, satilanAdet);
      }

      print("💾 [ADIM 3] SQLite Hareket Kaydı...");

      // 🧾 ÜRÜN AÇIKLAMASI
      String urunDetaylariAcliklamasi =
      _sepet.map((item) =>
      "${item['ad']} (${item['adet']} Adet)")
          .join(", ");

      String kategoriler = _sepet
          .map((item) =>
      (item['kategori'] ??
          item['kategori_ad'] ??
          ''))
          .where((e) => e.isNotEmpty)
          .join(", ");

      String markalar = _sepet
          .map((item) => (item['marka'] ?? ''))
          .where((e) => e.isNotEmpty)
          .join(", ");

      String modeller = _sepet
          .map((item) =>
      (item['model'] ??
          item['urun'] ??
          ''))
          .where((e) => e.isNotEmpty)
          .join(", ");

      String altModeller = _sepet
          .map((item) =>
      (item['alt_model'] ??
          item['altmodel'] ??
          ''))
          .where((e) => e.isNotEmpty)
          .join(", ");

      // 🧾 HAREKET
      Map<String, dynamic> hareket = {

        'id': nihaiIslemId,
        'islem_key': tekilIslemKey,

        'musteri_id': mId,
        'musteri_ad': widget.secilenMusteri['ad'],
        'veri_musteri_id': mId,

        'islem': 'SATIS',

        'tutar': _toplamTutar,

        'aciklama': urunDetaylariAcliklamasi,

        'tarih': DateFormat('dd.MM.yyyy')
            .format(_secilenTarih),

        'is_synced': 1,

        'teslim_durumu': 'TESLİM EDİLMEDİ',

        'kategori': kategoriler,
        'marka': markalar,
        'model': modeller,
        'alt_model': altModeller,
      };

      // 💾 SQLITE
      print("💾 [ADIM 4] SQLite kayıt...");
      await DatabaseHelper.instance
          .musteriHareketEkle(hareket);

      // ☁️ FIRESTORE
      print("☁️ [ADIM 5] Firestore kayıt...");

      await FirebaseFirestore.instance
          .collection('satislar')
          .doc(nihaiIslemId)
          .set({

        ...hareket,

        'server_tarih':
        FieldValue.serverTimestamp(),

        'sube': widget.seciliSube,

        'sqlite_id': nihaiIslemId,

      });

      // 💰 BAKİYE SENKRON
      if (_odemeTipi == "AÇIK HESAP") {

        print("💰 [ADIM 6] Bakiye senkronize ediliyor");

        final mData =
        await DatabaseHelper.instance.getMusteri(mId);

        double guncelBakiye =
            double.tryParse(
                mData['bakiye'].toString()) ??
                0.0;

        await FirebaseFirestore.instance
            .collection('musteriler')
            .doc(mId)
            .set({

          'bakiye': guncelBakiye,

          'son_islem': 'SATIS',

          'guncelleme':
          FieldValue.serverTimestamp(),

        }, SetOptions(merge: true));

        print("✅ Bakiye senkronizasyonu tamam");
      }

      print("🏁 SATIŞ MÜHÜRLENDİ VE TAMAMLANDI");

      if (mounted) {
        Navigator.pop(context, true);
      }

    } catch (e) {

      print("🚨 HATA: $e");

      if (mounted) {

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                "Satış kaydedilirken hata oluştu: $e"),
            backgroundColor: Colors.red,
          ),
        );
      }

    } finally {

      // 🔓 LOCK KALDIR
      _islemYapiliyor = false;

      if (mounted) {
        setState(() {});
      }
    }
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.secilenMusteri['ad'] ?? "Müşteri"),
        backgroundColor: Colors.red[900],
        foregroundColor: Colors.white,
      ),

      body: SafeArea(
        child: Column(
          children: [

            /// SEPET LİSTESİ
            Expanded(
              child: _sepet.isEmpty
                  ? const Center(child: Text("Sepet boş. Ürün ekleyin."))
                  : ListView.builder(
                itemCount: _sepet.length,
                itemBuilder: (c, i) => ListTile(
                  title: Text(_sepet[i]['ad']),
                  subtitle: Text(
                    "${_sepet[i]['adet']} x ${formatTR.format(_sepet[i]['fiyat'])}",
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete, color: Colors.red),
                    onPressed: () {
                      setState(() {
                        _toplamTutar -= _sepet[i]['toplam'];
                        _sepet.removeAt(i);
                      });
                    },
                  ),
                ),
              ),
            ),

            /// ALT PANEL (HER ZAMAN GÖRÜNÜR)
            SafeArea(
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  boxShadow: [
                    BoxShadow(
                      blurRadius: 10,
                      color: Colors.black12,
                    )
                  ],
                  borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [

                    /// TOPLAM
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          "TOPLAM",
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        Text(
                          formatTR.format(_toplamTutar),
                          style: const TextStyle(
                            fontSize: 20,
                            color: Colors.red,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 10),

                    /// BUTON
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor:
                          _sepet.isEmpty ? Colors.grey : Colors.red[900],
                          foregroundColor: Colors.white,
                        ),
                        onPressed: _sepet.isEmpty
                            ? null
                            : () {
                          print("👉 SATIŞ BASILDI");
                          print("👉 SEPET: ${_sepet.length}");
                          print("👉 MÜŞTERİ: ${widget.secilenMusteri}");

                          _satisiKaydet();
                        },
                        child: _islemYapiliyor
                            ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                            : Text("SATIŞI TAMAMLA (${_sepet.length})"),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),

      floatingActionButton: FloatingActionButton(
        onPressed: _urunSec,
        backgroundColor: Colors.red[900],
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  Widget _altPanel() => Container(
    padding: const EdgeInsets.all(20),
    decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text("TOPLAM:", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            Text(
              formatTR.format(_toplamTutar),
              style: const TextStyle(fontSize: 22, color: Colors.red, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              // Sepet boşsa buton gri olsun ki anlayalım
                backgroundColor: _sepet.isEmpty ? Colors.grey : Colors.red[900],
                foregroundColor: Colors.white
            ),
            onPressed: () {
              // --- BURASI KRİTİK DEBUG ---
              print("---------------------------------------");
              print("👉 BUTONA BASILDI!");
              print("👉 SEPET ADET: ${_sepet.length}");
              print("👉 İŞLEM DURUMU: $_islemYapiliyor");
              print("---------------------------------------");

              if (_sepet.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("Evren abi sepet boş, ürün ekle!"))
                );
              } else {
                _satisiKaydet();
              }
            },
            child: _islemYapiliyor
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white))
                : Text("SATIŞI TAMAMLA (${_sepet.length} ÜRÜN)"),
          ),
        )
      ],
    ),
  );

  void _urunSec() {
    if (_stoklar.isEmpty) {
      _stoklariTazele().then((_) {
        if (_stoklar.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Stok bulunamadı!")));
          return;
        }
        _urunSec();
      });
      return;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (c) => Container(
        height: MediaQuery.of(context).size.height * 0.8, // Biraz daha genişlettik
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: Text("SATILACAK ÜRÜNÜ SEÇİN", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            ),
            const Divider(),
            Expanded(
              child: ListView.builder(
                  itemCount: _stoklar.length,
                  itemBuilder: (c, i) {
                    final urun = _stoklar[i];
                    // Maliyeti sayıya çeviriyoruz
                    double maliyetFiyati = double.tryParse(urun['fiyat']?.toString() ?? '0') ?? 0.0;

                    return ListTile(
                      leading: const Icon(Icons.shopping_bag, color: Colors.blue),
                      title: Text(
                        "${urun['marka'] ?? ''} ${urun['model'] ?? ''}".trim(),
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        "Mevcut Stok: ${urun['adet'] ?? 0} Adet\n" // Adet bilgisini belirginleştirdik
                            "Alış (Maliyet): ${formatTR.format(maliyetFiyati)}", // Formatlı maliyet
                        style: const TextStyle(fontSize: 13),
                      ),
                      isThreeLine: true, // İki satırlı subtitle için alan açar
                      trailing: const Icon(Icons.chevron_right), // Tıklanabilir olduğunu gösteren ikon
                      onTap: () {
                        Navigator.pop(context);
                        _fiyatVeAdetSor(urun);
                      },
                    );
                  }
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _fiyatVeAdetSor(Map<String, dynamic> urun) {
    double maliyet = double.tryParse(urun['fiyat']?.toString() ?? '0') ?? 0.0;

    // Kontrolcüler: Adet varsayılan 1, fiyat boş (ipucu olarak maliyet görünecek)
    TextEditingController adetController = TextEditingController(text: "1");
    TextEditingController fiyatController = TextEditingController();

    showDialog(
      context: context,
      barrierDismissible: false, // Yanlışlıkla dışarı tıklayıp kapatılmasın
      builder: (context) => AlertDialog(
        title: Text("${urun['marka'] ?? ''} ${urun['model'] ?? ''}"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              "Evren, Senin Alış Fiyatın: ${formatTR.format(maliyet)}",
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.red,
                fontWeight: FontWeight.bold,
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: adetController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: "Satış Adedi", border: OutlineInputBorder()),
            ),
            const SizedBox(height: 15),
            TextField(
              controller: fiyatController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              autofocus: true, // Klavye direkt açılsın
              decoration: InputDecoration(
                labelText: "Satış Birim Fiyatı",
                hintText: maliyet.toString(), // Gri yazı olarak maliyeti gösterir
                border: const OutlineInputBorder(),
                suffixText: "TL",
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("İPTAL")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            onPressed: () {
              // .trim() ekleyerek boşlukları temizleyelim, virgülü noktaya çevirelim
              String temizAdet = adetController.text.trim();
              String temizFiyat = fiyatController.text.trim().replaceAll(',', '.');

              int adet = int.tryParse(temizAdet) ?? 1;
              double satisFiyati = double.tryParse(temizFiyat) ?? maliyet;

              // 🔥 İŞTE BURADA LOG ATALIM Kİ HATAYI YAKALAYALIM
              print("🛒 DİALOGDAN ÇIKAN -> Adet: $adet, Fiyat: $satisFiyati, Toplam: ${adet * satisFiyati}");

              // Sepete sadece bu temizlenmiş verileri gönder
              _sepeteEkle(urun, adet, satisFiyati);

              Navigator.pop(context);
            },
            child: const Text("SEPETE EKLE", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}