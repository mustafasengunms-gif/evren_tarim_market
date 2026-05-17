import 'package:evren_tarim_market/models/CekModel.dart';
import 'stok_giris_sayfasi.dart';
import 'dart:io';
import 'alis_islem_sayfasi.dart';
import 'firma_yonetim.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../db/database_helper.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'stok_yonetim_merkezi.dart';
import '../utils/pdf_helper.dart'; // Dosya yolun hangisiyse ona göre ayarla
import 'package:flutter/foundation.dart'; // debugPrint için bu şart!
import '../widgets/hizli_secim_dialog.dart';
import 'stok_listesi_sayfasi.dart';
import 'musteri_giris_sayfasi.dart';
import 'cek_senet_sayfasi.dart';
import 'proforma_screen.dart';
import 'raporlar_sayfasi.dart';
import 'package:evren_tarim_market/screens/musteri_satis_paneli.dart';
import 'package:evren_tarim_market/db/database_helper.dart';
import 'package:sqflite/sqflite.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart'; // En üstte kIsWeb kontrolü için bu import olmalı


class EvrenTarimPaneli extends StatefulWidget {
  const EvrenTarimPaneli({super.key});

  @override
  State<EvrenTarimPaneli> createState() => _EvrenTarimPaneliState();
}

class _EvrenTarimPaneliState extends State<EvrenTarimPaneli> {
  // --- DEĞİŞKENLER (TEKİL VE TEMİZ) ---
  List<Map<String, dynamic>> _musteriler = [];
  List<Map<String, dynamic>> _stoklar = [];
  List<Map<String, dynamic>> _filtreli = [];
  int _seciliSube = 0; // 0: TEFENNİ, 1: AKSU
  int _aktifFiltreSube = 2;
  String _secilenSatisTipi = "AÇIK HESAP";
  bool _yukleniyor = false;
  Map<String, dynamic> _guncelRaporMap = {}; // Ü harfini u yaptık, hata bitti

  double toplamCiro = 0.0;
  int toplamIslem = 0;

  final TextEditingController adController = TextEditingController();
  final TextEditingController fiyatController = TextEditingController();
  final TextEditingController stokController = TextEditingController();


  @override
  void initState() {
    super.initState();
    _tumVerileriYukle();
    _verileriSqlDenGetir();
  }

  @override
  void dispose() {
    adController.dispose();
    fiyatController.dispose();
    stokController.dispose();
    super.dispose();
  }


// Firebase Firestore kullanıyorsan onun importu da olmalı:
// import 'package:cloud_firestore/cloud_firestore.dart';

  Future<void> _verileriSqlDenGetir() async {
    // 🌐 1. WEB KONTROLÜ: Eğer uygulama Web'de çalışıyorsa local SQLite'a hiç dokunma!
    if (kIsWeb) {
      debugPrint("🌐 Web platformu algılandı, özet veriler Firebase Firestore'dan getiriliyor...");
      await _verileriFirebaseDenGetir();
      return; // Fonksiyonu burada bitir, aşağıdaki SQLite kodlarına geçme.
    }

    // 📱 2. MOBİL (Android/iOS) KODLARI: Local SQLite işlemleri aynen devam ediyor.
    try {
      final db = await DatabaseHelper.instance.database;

      var satisRes = await db.rawQuery("SELECT SUM(tutar) as toplam, COUNT(*) as adet FROM musteri_hareketleri WHERE islem = 'SATIS'");
      var stokRes = await db.rawQuery("SELECT COUNT(*) as adet FROM stoklar");
      var musteriRes = await db.rawQuery("SELECT COUNT(*) as adet FROM musteriler");
      var firmaRes = await db.rawQuery("SELECT COUNT(*) as adet FROM tarim_firmalari");
      var cekRes = await db.rawQuery("SELECT SUM(tutar) as toplam FROM cekler WHERE tip = 'cek' AND durum = 'beklemede'");
      var senetRes = await db.rawQuery("SELECT SUM(tutar) as toplam FROM cekler WHERE tip = 'senet' AND durum = 'beklemede'");

      double toplamCiroLocal = double.tryParse(satisRes.first['toplam'].toString()) ?? 0.0;
      int toplamIslemLocal = int.tryParse(satisRes.first['adet'].toString()) ?? 0;
      int stokSayisi = int.tryParse(stokRes.first['adet'].toString()) ?? 0;
      int musteriSayisi = int.tryParse(musteriRes.first['adet'].toString()) ?? 0;
      int firmaSayisi = int.tryParse(firmaRes.first['adet'].toString()) ?? 0;
      double cekToplam = double.tryParse(cekRes.first['toplam'].toString()) ?? 0.0;
      double senetToplam = double.tryParse(senetRes.first['toplam'].toString()) ?? 0.0;

      double fBorcu = 0.0;
      try {
        var borcSorgu = await db.rawQuery('''
        SELECT 
          SUM(CASE WHEN tip LIKE '%ÖDEME%' OR tip LIKE '%ODEME%' OR tip LIKE '%TAHSİLAT%' THEN -tutar ELSE tutar END) as net_borc 
        FROM tarim_firma_hareketleri 
        WHERE silindi = 0
      ''');
        fBorcu = double.tryParse(borcSorgu.first['net_borc'].toString()) ?? 0.0;
      } catch (e) {
        debugPrint("Firma borcu hesaplama hatası: $e");
        fBorcu = 0.0;
      }

      if (!mounted) return;

      setState(() {
        toplamCiro = toplamCiroLocal;
        toplamIslem = toplamIslemLocal;

        _guncelRaporMap = {
          'toplam_satis': toplamCiroLocal,
          'islem_sayisi': toplamIslemLocal,
          'stok_sayisi': stokSayisi,
          'musteri_sayisi': musteriSayisi,
          'firma_sayisi': firmaSayisi,
          'firma_borcu': fBorcu,
          'cek_toplam': cekToplam,
          'senet_toplam': senetToplam,
        };
      });

    } catch (e) {
      debugPrint("❌ GENEL SQL HATASI: $e");
    }
  }



  String normalizeAd(String ad) => ad.toUpperCase().trim().replaceAll(RegExp(r'\s+'), ' ');

  Future<void> firebaseCekleriIndir() async {
    final querySnapshot = await FirebaseFirestore.instance.collection('cekler').get();
    final db = await DatabaseHelper.instance.database;

    // 🔥 BURASI KRİTİK: Önce SQL'deki eski çekleri temizle ki üst üste binmesin!
    await db.delete('cekler');

    for (var doc in querySnapshot.docs) {
      await db.insert(
        'cekler',
        {
          ...doc.data(),
          'id': doc.id,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    debugPrint("✅ Çekler sıfırlanıp yeniden çekildi.");
  }


  Future<void> _verileriFirebaseDenGetir() async {
    try {
      final firestore = FirebaseFirestore.instance;

      // ==========================================
      // 1. DÖKÜMAN SAYILARI (COUNT SORGULARI)
      // ==========================================
      final musteriSnap = await firestore.collection('musteriler').count().get();
      final stokSnap = await firestore.collection('stoklar').count().get();
      final stokListesiSnap = await firestore.collection('stoklistesi').count().get();
      final stokTanimlariSnap = await firestore.collection('stok_tanimlari').count().get();
      final firmalarSnap = await firestore.collection('firmalar').count().get();
      final tarimFirmalariSnap = await firestore.collection('tarim_firmalari').count().get();
      final faturalarSnap = await firestore.collection('faturalar').count().get();
      final musteriFaturalariSnap = await firestore.collection('musteri_faturalari').count().get();
      final proformalarSnap = await firestore.collection('proformalar').count().get();
      final tarlalarSnap = await firestore.collection('tarlalar').count().get();
      final araclarSnap = await firestore.collection('araclar').count().get();
      final isletmelerSnap = await firestore.collection('isletmeler').count().get();
      final personelSnap = await firestore.collection('personel').count().get();

      // Biçerdöver Grubu Sayıları
      final bicerlerSnap = await firestore.collection('bicerler').count().get();
      final bicerMusterileriSnap = await firestore.collection('bicer_musterileri').count().get();

      // ==========================================
      // 2. TOPLAM CİRO & İŞLEM ADEDİ (SATISLAR)
      // ==========================================
      // Not: Satışları isterseniz 'satislar' koleksiyonundan, isterseniz 'musteri_hareketleri'nden süzebilirsiniz.
      final satislarSnap = await firestore.collection('satislar').get();
      double toplamCiroLocal = 0.0;
      int toplamIslemLocal = satislarSnap.docs.length;

      for (var doc in satislarSnap.docs) {
        var data = doc.data();
        double tutar = double.tryParse(data['tutar'].toString()) ?? 0.0;
        toplamCiroLocal += tutar;
      }

      // Alışlar Toplamı
      final alislarSnap = await firestore.collection('alislar').get();
      double toplamAlisLocal = 0.0;
      for (var doc in alislarSnap.docs) {
        double tutar = double.tryParse(doc.data()['tutar'].toString()) ?? 0.0;
        toplamAlisLocal += tutar;
      }

      // ==========================================
      // 3. ÇEK & SENET HESAPLAMALARI
      // ==========================================
      final ceklerSnap = await firestore.collection('cekler').where('durum', isEqualTo: 'beklemede').get();
      double cekToplam = 0.0;
      double senetToplam = 0.0;

      for (var doc in ceklerSnap.docs) {
        var data = doc.data();
        String tip = data['tip']?.toString().toLowerCase() ?? '';
        double tutar = double.tryParse(data['tutar'].toString()) ?? 0.0;

        if (tip == 'cek' || tip == 'çek') {
          cekToplam += tutar;
        } else if (tip == 'senet') {
          senetToplam += tutar;
        }
      }

      // ==========================================
      // 4. TARIM FİRMALARI BORÇ/ALACAK HESABI
      // ==========================================
      // Listenizdeki firma hareket tablolarını kontrol ediyoruz (tarim_firma_hareketleri)
      final firmaHareketlerSnap = await firestore
          .collection('tarim_firma_hareketleri')
          .where('silindi', isEqualTo: 0)
          .get();

      double fBorcu = 0.0;
      for (var doc in firmaHareketlerSnap.docs) {
        var data = doc.data();
        String tip = data['tip']?.toString().toUpperCase() ?? '';
        double tutar = double.tryParse(data['tutar'].toString()) ?? 0.0;

        if (tip.contains('ÖDEME') || tip.contains('ODEME') || tip.contains('TAHSİLAT')) {
          fBorcu -= tutar;
        } else {
          fBorcu += tutar;
        }
      }

      // ==========================================
      // 5. BİÇERDÖVER (HASAT & MAZOT) HESAPLARI
      // ==========================================
      final bicerIsleriSnap = await firestore.collection('bicer_isleri').get();
      double bicerToplamGelir = 0.0;
      for (var doc in bicerIsleriSnap.docs) {
        double tutar = double.tryParse(doc.data()['toplam_tutar'].toString()) ?? 0.0;
        bicerToplamGelir += tutar;
      }

      final bicerMazotSnap = await firestore.collection('bicer_mazotlar').get();
      double bicerTotalMazotLitre = 0.0;
      for (var doc in bicerMazotSnap.docs) {
        double litre = double.tryParse(doc.data()['litre'].toString()) ?? 0.0;
        bicerTotalMazotLitre += litre;
      }

      // Kasa bakiye hesabı
      final kasaSnap = await firestore.collection('kasa_hareketleri').get();
      double kasaBakiye = 0.0;
      for (var doc in kasaSnap.docs) {
        var data = doc.data();
        double tutar = double.tryParse(data['tutar'].toString()) ?? 0.0;
        if (data['tip'] == 'GİRİŞ' || data['tip'] == 'GIRIS') {
          kasaBakiye += tutar;
        } else {
          kasaBakiye -= tutar;
        }
      }

      if (!mounted) return;

      // ==========================================
      // 6. MAP UPDATE (TÜM DEĞERLERİ STATE'E GÖMÜYORUZ)
      // ==========================================
      setState(() {
        toplamCiro = toplamCiroLocal;
        toplamIslem = toplamIslemLocal;

        _guncelRaporMap = {
          'toplam_satis': toplamCiroLocal,
          'toplam_alis': toplamAlisLocal,
          'islem_sayisi': toplamIslemLocal,
          'stok_sayisi': stokSnap.count ?? 0,
          'stok_listesi_sayisi': stokListesiSnap.count ?? 0,
          'stok_tanimlari_sayisi': stokTanimlariSnap.count ?? 0,
          'musteri_sayisi': musteriSnap.count ?? 0,
          'firma_sayisi': tarimFirmalariSnap.count ?? 0,
          'normal_firma_sayisi': firmalarSnap.count ?? 0,
          'fatura_sayisi': faturalarSnap.count ?? 0,
          'musteri_fatura_sayisi': musteriFaturalariSnap.count ?? 0,
          'proforma_sayisi': proformalarSnap.count ?? 0,
          'tarla_sayisi': tarlalarSnap.count ?? 0,
          'arac_sayisi': araclarSnap.count ?? 0,
          'isletme_sayisi': isletmelerSnap.count ?? 0,
          'personel_sayisi': personelSnap.count ?? 0,
          'firma_borcu': fBorcu,
          'cek_toplam': cekToplam,
          'senet_toplam': senetToplam,
          'kasa_bakiye': kasaBakiye,

          // Biçerdöver Grubu
          'bicer_sayisi': bicerlerSnap.count ?? 0,
          'bicer_musteri_sayisi': bicerMusterileriSnap.count ?? 0,
          'bicer_toplam_gelir': bicerToplamGelir,
          'bicer_toplam_mazot_litre': bicerTotalMazotLitre,
        };
      });

      debugPrint("✅ 🌐 Web Modu: Tüm tabloların Firebase verileri başarıyla panele yüklendi!");

    } catch (e) {
      debugPrint("❌ FIREBASE TÜM TABLOLAR ÖZET VERİ ÇEKME HATASI: $e");
    }
  }

  Future<void> _tumVerileriYukle() async {
    try {
      if (mounted) setState(() => _yukleniyor = true);

      final db = await DatabaseHelper.instance.database;

      // 🔥 ADIM 1: Mükerrer kaydı önlemek için senkronizasyon öncesi tabloları temizle
      // Eğer tüm veriyi Firebase'den güncel alıyorsan bu en sağlam yoldur:
      // await db.delete('musteriler');
      // await db.delete('stoklar'); // Stoklarda da aynı sorun varsa bunu ekle

      // 🔥 ADIM 2: Firebase'den müşterileri çek
      final snapshot = await FirebaseFirestore.instance.collection('musteriler').get();
      for (var doc in snapshot.docs) {
        final data = doc.data();
        final adNorm = normalizeAd((data['ad'] ?? "").toString());

        await DatabaseHelper.instance.musteriUpsert({
          'id': data['id'] ?? doc.id,
          'ad': adNorm,
          'tel': data['tel'] ?? "",
          'bakiye': data['bakiye'] ?? 0,
          'adres': data['adres'] ?? "",
        });
      }

      // Çekleri indirirken tabloyu temizlemek için fonksiyonun içine müdahale edelim:
      await firebaseCekleriIndir();

      await _verileriSqlDenGetir();

    } catch (e) {
      print("SYNC HATA: $e");
    } finally {
      if (mounted) setState(() => _yukleniyor = false);
    }
  }


  // --- ANA EKRAN ---
  @override
  Widget build(BuildContext context) {
    final Color anaRenk = _seciliSube == 0 ? Colors.green[800]! : Colors.blue[900]!;

    return Scaffold(
      backgroundColor: Colors.grey[200],
      appBar: AppBar(
        title: Text("EVREN TARIM - ${_seciliSube == 0 ? 'TEFENNİ' : 'AKSU'}", style: const TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: anaRenk,
        centerTitle: true,
      ),
      body: Column(
        children: [
          // Şube Seçimi
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: Row(children: [
              _subeButon("TEFENNİ", 0, Colors.green),
              const SizedBox(width: 10),
              _subeButon("AKSU", 1, Colors.blue),
            ]),
          ),

          // Izgara Menü (Tüm 10 Buton Burada)
          Expanded(
            child: GridView.count(
              padding: const EdgeInsets.all(15),
              crossAxisCount: 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 1.5,
              children: [
                _anaButon("STOK GİRİŞ", Icons.inventory, Colors.orange, () async {
                  if (mounted) {
                    // 1. Sayfaya gidiş (Stok Yönetim Merkezi'ne uçuyoruz)
                    await Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (c) => StokYonetimMerkezi(
                              // ÖNEMLİ: Senin panelinde _seciliSube int (0 veya 1).
                              // Eğer StokYonetimMerkezi int bekliyorsa böyle kalsın.
                              // Eğer String bekliyorsa: _seciliSube == 0 ? "TEFENNİ" : "AKSU" yap.
                              seciliSube: _seciliSube,
                            )
                        )
                    );

                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text("stok listesi güncellendi."),
                            backgroundColor: Colors.green,
                            duration: Duration(seconds: 2),
                          )
                      );
                    }
                  }
                }),
                _anaEkranIslemKarti(
                  "STOK LİSTESİ",
                  Icons.inventory_2,
                  Colors.brown,
                  null,
                  ozelOnTap: () async {
                    List<Map<String, dynamic>> s; // Değişkeni yukarı aldık

                    if (kIsWeb) {
                      // --- WEB İÇİN BURASI ÇALIŞACAK ---
                      final snapshot = await FirebaseFirestore.instance.collection('stoklar').get();
                      s = snapshot.docs.map((doc) {
                        var data = doc.data();
                        return {
                          ...data,
                          'id': doc.id.hashCode, // Sayfadaki id beklentisi için
                          'firebase_id': doc.id,
                          // image_198307.png'deki gibi model ismini ürün ismine eşitle
                          'urun': (data['urun'] ?? data['model'] ?? '').toString().toUpperCase(),
                          'sube': (data['sube'] ?? 'TEFENNİ').toString().toUpperCase(),
                        };
                      }).toList();
                    } else {
                      // --- MOBİL İÇİN ESKİ SİSTEM DEVAM ---
                      s = await DatabaseHelper.instance.stokListesiGetir();
                    }

                    // Sonra sayfaya gönderiyoruz
                    if (context.mounted) {
                      Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => StokListesiSayfasi(ilkVeriler: s))
                      );
                    }
                  },
                ),
                _anaEkranIslemKarti("MÜŞTERİ GİRİŞ", Icons.person_add, Colors.blue, const MusteriGirisSayfasi()),
                _anaEkranIslemKarti(
                  "MÜŞTERİYE SATIŞ İŞLEMİ",
                  Icons.sell,
                  Colors.red,
                  null,
                  ozelOnTap: () {
                    hizliSecimDialog(
                      context: context,
                      tip: "SATIŞ",
                      musteriler: _musteriler,
                      onSecim: (secilenMusteri, odemeTipi) async {
                        // 🔥 AYNI DOSYADA OLDUĞU İÇİN BURADAN DİREKT GÖRÜR
                        int subeNo = (secilenMusteri['sube']?.toString().toUpperCase() == "AKSU") ? 1 : 0;
                        final stoklar = await DatabaseHelper.instance.stokListesiGetir();

                        if (!mounted) return;

                        Navigator.push(context, MaterialPageRoute(
                          builder: (context) => MusteriSatisPaneli(
                            secilenMusteri: secilenMusteri,
                            mevcutStoklar: stoklar,
                            seciliSube: subeNo, // Hata veren yer burasıydı, çözüldü!
                            ilkOdemeTipi: odemeTipi,
                          ),
                        ));
                      },
                    );
                  },
                ),
                _anaEkranIslemKarti("FİRMA EKLEME", Icons.business, Colors.teal, const FirmaTanimSayfasi()),
                _anaEkranIslemKarti("FİRMADAN MAL ALIŞ İŞLEMİ", Icons.shopping_cart, Colors.indigo, null, ozelOnTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => DetayliStokGirisSayfasi(seciliSube: _seciliSube)))),


                _anaEkranIslemKarti("ÇEK / SENET", Icons.payments, Colors.deepPurple, null, ozelOnTap: () async {
                  final f = await DatabaseHelper.instance.tarimFirmaListesiGetir();
                  Navigator.push(context, MaterialPageRoute(builder: (context) => CekSenetSayfasi(veriler: f)));
                }),
                _anaEkranIslemKarti("HIZLI STOK GİRİŞ", Icons.add_box, Colors.green[700]!, null, ozelOnTap: () async {
                  await Navigator.push(context, MaterialPageRoute(builder: (context) => DetayliStokGirisSayfasi(seciliSube: _seciliSube)));
                  _verileriSqlDenGetir();
                }),
                _anaEkranIslemKarti("PROFORMA", Icons.description, Colors.blueGrey, null, ozelOnTap: () async {
                  // Veriyi alırken tipini belirleyelim (List<Map<String, dynamic>>)
                  final List<Map<String, dynamic>> m = await DatabaseHelper.instance.musteriListesiGetir();

                  if (context.mounted) { // Navigator öncesi context kontrolü iyidir
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => ProformaSayfasi(
                          secilenMusteri: null,
                          musteriler: m, // m listesini buraya gönderiyoruz
                        ),
                      ),
                    );
                  }
                }),
                _anaEkranIslemKarti(
                  "RAPORLAR",
                  Icons.analytics,
                  Colors.black,
                  null,
                  ozelOnTap: () async {
                    // 1. Verileri SQL'den çek ve _guncelRaporMap'i doldur
                    await _verileriSqlDenGetir();

                    // 2. Veri çekme bittikten sonra ve widget hala ekrandaysa sayfayı aç
                    if (context.mounted) {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => RaporlarSayfasi(
                            // Fonksiyon içinde set ettiğiniz Map'i doğrudan gönderiyoruz
                            raporVerisi: _guncelRaporMap,
                          ),
                        ),
                      );
                    }
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _anaButon(String baslik, IconData ikon, Color renk, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Card(
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(ikon, size: 40, color: renk),
            const SizedBox(height: 10),
            Text(baslik, style: const TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  Widget _subeButon(String ad, int i, Color renk) => Expanded(
    child: ElevatedButton(
      style: ElevatedButton.styleFrom(backgroundColor: _seciliSube == i ? renk : Colors.white, foregroundColor: _seciliSube == i ? Colors.white : renk),
      onPressed: () => setState(() => _seciliSube = i),
      child: Text(ad),
    ),
  );

  Widget _anaEkranIslemKarti(String b, IconData i, Color r, Widget? s, {VoidCallback? ozelOnTap}) {
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: ozelOnTap ?? () { if (s != null) Navigator.push(context, MaterialPageRoute(builder: (context) => s)); },
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(i, color: r, size: 30), const SizedBox(height: 5), Text(b, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold))]),
      ),
    );
  }
}




class MusteriEkstreSayfasi extends StatefulWidget {
  final String musteriId;
  final String musteriAd;

  const MusteriEkstreSayfasi({
    super.key,
    required this.musteriId,
    required this.musteriAd
  });

  @override
  State<MusteriEkstreSayfasi> createState() => _MusteriEkstreSayfasiState();
}

class _MusteriEkstreSayfasiState extends State<MusteriEkstreSayfasi> {
  late Future<List<Map<String, dynamic>>> _ekstreFuture;

  // 🔥 PARAYI ADAM GİBİ GÖSTEREN FORMATTER
  final tlFormat = NumberFormat.currency(locale: 'tr_TR', symbol: '₺', decimalDigits: 2);

  @override
  void initState() {
    super.initState();
    _verileriYukle();
  }

  void _verileriYukle() {
    setState(() {
      // 🚀 ESKİSİ: musteriproformaekstresi (Sadece yerel)
      // 🚀 YENİSİ: musteriEkstresiGetir (Hibrit - Önce yerel, yoksa bulut)
      _ekstreFuture = DatabaseHelper.instance.musteriEkstresiGetir(widget.musteriId);
    });
  }

  // --- SİLME ONAY DİYALOĞU ---
  void _silmeOnayDialog(BuildContext context, Map<String, dynamic> h) {
    double tutar = double.tryParse((h['toplam_tutar'] ?? h['tutar'] ?? '0').toString()) ?? 0.0;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("İŞLEMİ SİL"),
        content: Text(
            "${tlFormat.format(tutar)} tutarındaki bu işlem silinecek. Emin misin abi?"
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("VAZGEÇ")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              await DatabaseHelper.instance.musteriHareketSil(
                  h['id'].toString(),
                  widget.musteriId,
                  tutar,
                  h['islem'] ?? "SATIS"
              );

              if (!mounted) return;
              Navigator.pop(ctx);
              _verileriYukle();

              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("Kayıt silindi, bakiye güncellendi.")),
              );
            },
            child: const Text("EVET, SİL"),
          ),
        ],
      ),
    );
  }

  void _tutarGuncelleDialog(Map<String, dynamic> h) {
    // mId'yi senin gönderdiğin widget'tan veya map'ten garantileyelim
    String mId = widget.musteriId;
    String hId = h['id'].toString();

    final TextEditingController _tutarController = TextEditingController(
        text: (h['tutar'] ?? h['toplam_tutar'] ?? '0').toString()
    );

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("TUTARI GÜNCELLE"),
        content: TextField(
          controller: _tutarController,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: "Yeni Tutar", suffixText: "₺"),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("İPTAL")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blue[900]),
            onPressed: () async {
              double yeniTutar = double.tryParse(_tutarController.text) ?? 0.0;
              double eskiTutar = double.tryParse((h['tutar'] ?? h['toplam_tutar'] ?? '0').toString()) ?? 0.0;

              // 🔥 DATABASEHELPER'A GİDİYORUZ
              await DatabaseHelper.instance.musteriHareketGuncelle(
                  hId,
                  mId,
                  yeniTutar,
                  eskiTutar
              );

              if (!mounted) return;
              Navigator.pop(ctx);
              _verileriYukle(); // Listeyi anında tazele ki yeni tutar görünsün

              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("Tutar ve müşteri bakiyesi güncellendi.")),
              );
            },
            child: const Text("KAYDET", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("${widget.musteriAd} Ekstresi"),
        backgroundColor: Colors.blue[900],
        actions: [IconButton(onPressed: _verileriYukle, icon: const Icon(Icons.refresh))],
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _ekstreFuture,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());

          final hareketler = snap.data ?? [];
          if (hareketler.isEmpty) return const Center(child: Text("Kayıt bulunamadı."));

          return ListView.builder(
            itemCount: hareketler.length,
            itemBuilder: (context, i) {
              final h = hareketler[i];
              double tutar = double.tryParse((h['toplam_tutar'] ?? h['tutar'] ?? '0').toString()) ?? 0.0;

              // 🔥 RENK MANTIĞI BURADA
              // Veritabanından gelen 'islem' değerini kontrol ediyoruz
              String islemTipi = (h['islem'] ?? "SATIS").toString().toUpperCase();

              // Satış kırmızı (borç), Tahsilat yeşil (ödeme)
              Color tutarRengi = islemTipi == "SATIS" ? Colors.red : Colors.green[700]!;
              IconData islemIkonu = islemTipi == "SATIS" ? Icons.arrow_upward : Icons.arrow_downward;

              return Card(
                elevation: 3,
                margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                child: ListTile(
                  leading: IconButton(
                    icon: const Icon(Icons.edit_note, color: Colors.orange, size: 30),
                    onPressed: () => _tutarGuncelleDialog(h),
                  ),
                  title: Row(
                    children: [
                      Icon(islemIkonu, color: tutarRengi, size: 16), // Satış/Tahsilat yönü
                      const SizedBox(width: 5),
                      Expanded(child: Text(h['aciklama'] ?? widget.musteriAd)),
                    ],
                  ),
                  subtitle: Text("${h['tarih'] ?? ''} - ${islemTipi == 'SATIS' ? 'BORÇ' : 'TAHSİLAT'}"),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        tlFormat.format(tutar),
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: tutarRengi // 🔥 İŞTE RENK BURADA BASILIYOR
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.delete_forever, color: Colors.red),
                        onPressed: () => _silmeOnayDialog(context, h),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

