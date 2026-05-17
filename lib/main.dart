import 'dart:io' show File; // Sadece File gerekiyorsa ve mobil/masaüstü içinse
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:intl/intl.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:excel/excel.dart' as excel_lib;
import 'package:evren_tarim_market/db/database_helper.dart';
import 'package:evren_tarim_market/screens/evren_tarim.dart';
import 'package:evren_tarim_market/screens/bicer.dart';
import 'package:evren_tarim_market/screens/galeri.dart';
import 'package:evren_tarim_market/screens/ciftcilik.dart';
import 'package:evren_tarim_market/screens/personel_paneli.dart';
import 'package:evren_tarim_market/screens/cek_uyari_paneli.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'firebase_options.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/foundation.dart'; // kIsWeb kontrolü için şart
import 'screens/teslimat_takip_paneli.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart'; // Standart sqflite eklentisi
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart'; // 👈 Yüklediğimiz Web paketi

void main() async {
  // 1. Flutter motorunu başlat
  WidgetsFlutterBinding.ensureInitialized();

  // 2. Firebase'i TEK SEFERDE VE GÜVENLİ Başlat
  try {
    if (Firebase.apps.isEmpty) {
      if (kIsWeb) {
        await Firebase.initializeApp(
          options: const FirebaseOptions(
            apiKey: "AIzaSyDQb-auztfquDvxk9tkHCk-0GjpKLw2Keo",
            authDomain: "evrentarimmarket.firebaseapp.com",
            projectId: "evrentarimmarket",
            storageBucket: "evrentarimmarket.firebasestorage.app",
            messagingSenderId: "83830242468",
            appId: "1:83830242468:web:b3b818ec12f32d9105fa31",
          ),
        );
      } else {
        await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
      }
      print("✅ Firebase Başarıyla Hazırlandı");
    } else {
      print("ℹ️ Firebase zaten başlatılmıştı, mükerrer kurulum engellendi.");
    }
  } catch (e) {
    debugPrint("⚠️ Firebase Başlatma Hatası: $e");
  }

  // ⭐ WEB İÇİN KRİTİK AYAR: Tarayıcı açılırken sqflite hatası vermemesi için motoru mühürlüyoruz
  if (kIsWeb) {
    try {
      databaseFactory = databaseFactoryFfiWeb;
      print("🌐 Web: Veritabanı fabrikası (FFI Web) main.dart içinde başarıyla mühürlendi.");
    } catch (e) {
      print("⚠️ Web Veritabanı Fabrikası Ayarlanırken Hata: $e");
    }
  }

  // 3. Yerel Veritabanını Hazırla (Sadece Mobil Cihazlar İçin)
  if (!kIsWeb) {
    try {
      await DatabaseHelper.instance.database;
      print("✅ SQLite Tabloları Sorunsuz Hazır");

      // Arka plan servislerini tetikle
      _arkaPlanServisleriniBaslat();
    } catch (e) {
      if (e.toString().contains('duplicate-app')) {
        print("ℹ️ Firebase zaten ayaktaymış, mühür devam ediyor.");
      } else {
        debugPrint("⚠️ SQLite Başlatma Hatası: $e");
      }
    }
  }

  // 4. Uygulamayı Çalıştır
  runApp(const MyApp());
}

// --- ARKA PLAN SENKRONİZASYONUNU DOĞRU FONKSİYONA BAĞLAMA ---
void _arkaPlanServisleriniBaslat() {
  Future.delayed(const Duration(seconds: 4), () async {
    print("🚀 [SYNC] Akıllı Senkronizasyon Başlatıldı...");

    try {
      // 🎯 KRİTİK NOKTA: Burası DatabaseHelper içindeki senin düzelttiğin
      // fiyat yakalama mühürlü fonksiyonun adı olmalı (Örn: _firebaseSenkronizeEt veya herSeyiBuluttanIndir)
      // Eğer bu fonksiyon DatabaseHelper içinde public değilse, başına 'await DatabaseHelper.instance.' koyarak çağıracağın ismi yaz.

      await DatabaseHelper.instance.herSeyiBuluttanIndir();

      // Yerel kirli verileri buluta bas
      await DatabaseHelper.instance.herSeyiBulutaBas();

      print("🏁 [İŞLEM TAMAM] Evren Sistem Güncel.");
    } catch (err) {
      debugPrint("❌ Senkronizasyon Sırasında Hata: $err");
    }
  });
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Evren Tarım Market',
      locale: const Locale('tr', 'TR'),
      supportedLocales: const [Locale('tr', 'TR')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.green[900],
        scaffoldBackgroundColor: const Color(0xFFF8F9FA),
      ),
      // --- DİNAMİK GİRİŞ KONTROLÜ ---
      home: StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, snapshot) {
          // Firebase'den henüz cevap gelmediyse bekleme ekranı (Loading) göster
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator(color: Colors.green)),
            );
          }
          // Kullanıcı varsa ana kapıya, yoksa giriş ekranına gönder
          if (snapshot.hasData && snapshot.data != null) {
            return const GirisKapisi();
          }
          return const GirisEkrani();
        },
      ),
    );
  }
}

// --- YENİ: GİRİŞ EKRANI (KİLİTLİ KAPI) ---
class GirisEkrani extends StatefulWidget {
  const GirisEkrani({super.key});

  @override
  State<GirisEkrani> createState() => _GirisEkraniState();
}

class _GirisEkraniState extends State<GirisEkrani> {
  final _emailController = TextEditingController();
  final _sifreController = TextEditingController();
  bool _yukleniyor = false;

  Future<void> _girisYap() async {
    setState(() => _yukleniyor = true);
    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _sifreController.text.trim(),
      );
      if (mounted) {
        Navigator.pushReplacement(
            context, MaterialPageRoute(builder: (context) => const GirisKapisi())
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Hatalı giriş! Bilgileri kontrol et abi."), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _yukleniyor = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.agriculture, size: 100, color: Colors.green),
              const SizedBox(height: 20),
              const Text("EVREN TARIM MARKET", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              const Text("Yetkili Girişi", style: TextStyle(color: Colors.grey)),
              const SizedBox(height: 30),
              TextField(
                controller: _emailController,
                decoration: const InputDecoration(labelText: "E-posta", border: OutlineInputBorder()),
              ),
              const SizedBox(height: 15),
              TextField(
                controller: _sifreController,
                obscureText: true,
                decoration: const InputDecoration(labelText: "Şifre", border: OutlineInputBorder()),
              ),
              const SizedBox(height: 25),
              _yukleniyor
                  ? const CircularProgressIndicator()
                  : SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _girisYap,
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.green[900], foregroundColor: Colors.white),
                  child: const Text("DÜKKANA GİRİŞ YAP"),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}


class GirisKapisi extends StatelessWidget {
  const GirisKapisi({super.key});

  Future<void> _buluttanGeriYukle(BuildContext context) async {
    bool? onay = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Verileri Geri Yükle?"),
        content: const Text("Telefondaki yerel veriler silinecek ve Firebase'deki verileriniz indirilecek. Emin misiniz?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("İPTAL")),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text("EVET, YÜKLE")),
        ],
      ),
    );

    if (onay == true) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(child: CircularProgressIndicator()),
      );

      try {
        await DatabaseHelper.instance.herSeyiFirebaseGeriYukle();
        if (!context.mounted) return;
        Navigator.pop(context);
        _mesaj(context, "Tüm veriler Firebase'den geri yüklendi! ✅", Colors.green);
      } catch (e) {
        if (!context.mounted) return;
        Navigator.pop(context);
        _mesaj(context, "Hata: $e", Colors.red);
      }
    }
  }

  Future<void> _verileriSifirla(BuildContext context) async {
    try {
      await DatabaseHelper.instance.herSeyiSifirla();
      if (!context.mounted) return;
      _mesaj(context, "Sistem ve Bulut Tertemiz Edildi! 🗑️", Colors.red);
    } catch (e) {
      debugPrint("Sıfırlama Hatası: $e");
    }
  }

  Future<void> _excelYukle(BuildContext context, String tip) async {
    // 0. ŞUBE SEÇİMİ
    String? secilenSube = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Yüklenecek Şubeyi Seçin"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(leading: const Icon(Icons.location_on, color: Colors.red), title: const Text("TEFENNİ"), onTap: () => Navigator.pop(context, "TEFENNİ")),
            ListTile(leading: const Icon(Icons.location_on, color: Colors.blue), title: const Text("AKSU"), onTap: () => Navigator.pop(context, "AKSU")),
          ],
        ),
      ),
    );

    if (secilenSube == null) return;

    try {
      FilePickerResult? result = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: ['xlsx', 'xls'], withData: true);
      if (result == null || result.files.isEmpty) return;

      Uint8List? bytes = result.files.single.bytes;
      if (bytes == null && !kIsWeb) {
        final file = File(result.files.single.path!);
        bytes = file.readAsBytesSync();
      }
      if (bytes == null) return;

      var excel = excel_lib.Excel.decodeBytes(bytes);
      int sayac = 0;

      // --- YARDIMCI FONKSİYONLAR ---
      String readCell(dynamic cell) {
        if (cell == null || cell.value == null) return "";
        return cell.value.toString().trim().toUpperCase();
      }

      double parse(dynamic cell) {
        if (cell == null || cell.value == null) return 0.0;
        String text = cell.value.toString().replaceAll(RegExp(r'[^0-9.,]'), '').replaceAll(',', '.').trim();
        return double.tryParse(text) ?? 0.0;
      }

      for (var table in excel.tables.keys) {
        var rows = excel.tables[table]!.rows;
        Map<String, String> firmaCache = {}; // Cari Kodları tutmak için

        for (int i = 1; i < rows.length; i++) {
          var row = rows[i];
          if (row.isEmpty || row.length < 3 || readCell(row[2]) == "") continue;

          // 1. EXCEL'DEN VERİLERİ OKU
          String firmaAdi = readCell(row[0]).isEmpty ? "GENEL" : readCell(row[0]);
          String kategori = readCell(row[1]).isEmpty ? "DİĞER" : readCell(row[1]);
          String marka    = readCell(row[2]);
          String model    = row.length > 3 ? readCell(row[3]) : "";
          String altModel = row.length > 4 ? readCell(row[4]) : "";
          double adet     = row.length > 5 ? parse(row[5]) : 0.0;
          double fiyat    = row.length > 6 ? parse(row[6]) : 0.0;

          String tarihStr = DateFormat('dd.MM.yyyy').format(DateTime.now());
          String benzersizId = "STK-EXCEL-${DateTime.now().millisecondsSinceEpoch}-$i";

          // 2. FİRMA VE CARİ KOD YÖNETİMİ
          String cKod;
          if (firmaCache.containsKey(firmaAdi)) {
            cKod = firmaCache[firmaAdi]! ;
          } else {
            // Firma var mı kontrol et yoksa ekle (Senin mantığın)
            cKod = "F-EXCEL-${DateTime.now().millisecondsSinceEpoch}-$i";
            await DatabaseHelper.instance.tarimFirmaEkle({
              'cari_kod': cKod,
              'ad': firmaAdi,
              'yetkili': "EXCEL OTOMATİK",
              'is_synced': 0,
            });
            firmaCache[firmaAdi] = cKod;
          }
// 3. İLK KODUNDAKİ SÜTUNLARLA BİREBİR AYNI PAKETİ HAZIRLA
          await DatabaseHelper.instance.stokHareketiIsle(
            firma: {
              'cari_kod': cKod,
              'ad': firmaAdi,
            },
            stok: {
              'stok_kodu': benzersizId,
              'urun': "$marka $model $altModel".toUpperCase().trim(),
              'marka': marka,
              'model': model,
              'alt_model': altModel,
              'kategori': kategori,
              'sube': secilenSube,
              'durum': tip, // SIFIR veya 2. EL
              'fatura_no': "EXCEL_YUKLEME",

              // 🔀 Cari kodu buraya da bağlayalım
              'cari_kod': cKod,

              // 🔥 EKLEMELER BURADA:
              // Bulutun veya listeleme ekranının doğrudan okuyabilmesi için
              // firma ünvanını tüm olası anahtarlarla (keys) içeri gömüyoruz.
              'firma_unvani': firmaAdi,
              'firma_adi': firmaAdi,
              'firma': firmaAdi,

              // Fiyat ihtimalleri mühürleri
              'fiyat': fiyat,
              'alis_fiyatı': fiyat,
              'alis_fiyati': fiyat,

              'firebase_id': benzersizId,
              'tarih': tarihStr,
              'is_synced': 0,
            },
            adet: adet,
            birimFiyat: fiyat,
            islemTipi: 'ALIM',
          );

          sayac++;
        }
      }

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text("$sayac Ürün ($secilenSube) Sisteme Mühürlendi ✅"),
          backgroundColor: Colors.green,
        ));
      }
    } catch (e) {
      debugPrint("‼️ Excel Kritik Hata: $e");
    }
  }

  void _mesaj(BuildContext context, String metin, Color renk) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(metin), backgroundColor: renk));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("EVREN TARIM VE OTOMOTİV", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            Text("Ziraai Aletler Alım Satım", style: TextStyle(fontSize: 12, color: Colors.white70)),
          ],
        ),
        backgroundColor: Colors.green[900],
        foregroundColor: Colors.white,
        toolbarHeight: 70,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await FirebaseAuth.instance.signOut();
              if (context.mounted) {
                Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const GirisEkrani()));
              }
            },
          )
        ],
      ),
      body: Column(
        children: [
          _ustBanner(context),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _menuKart(context, "EVREN TARIM MARKET", Icons.agriculture, Colors.green, const EvrenTarimPaneli()),
                _menuKart(context, "BİÇER HİZMETLERİ", Icons.settings_suggest, Colors.orange, const BicerPaneli()),
                _menuKart(context, "OTO GALERİ", Icons.directions_car, Colors.blueGrey, const GaleriPaneli()),
                _menuKart(context, "ÇİFTÇİLİK İŞLERİ", Icons.grass, Colors.brown, const CiftcilikPaneli()),
                const SizedBox(height: 20),
                const Text("SİSTEM YÖNETİMİ", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey)),
                const Divider(),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _islemButon(context, "SIFIR EXCEL", Icons.upload_file, Colors.teal, () => _excelYukle(context, "SIFIR")),
                    _islemButon(context, "2.EL EXCEL", Icons.history, Colors.orange, () => _excelYukle(context, "2.EL")),

                    // 🔥 GÜNCELLENEN SEYYAR SAYAÇLI EMANET BUTONU (setState Hataları Temizlendi)
                    FutureBuilder<int>(
                      future: DatabaseHelper.instance.getTeslimEdilmeyenAdet(), // Veritabanından adeti okur
                      builder: (context, snapshot) {
                        int adet = snapshot.data ?? 0;

                        return InkWell(
                          onTap: () async {
                            // Sayfaya gider, işlem yapıp geri döndüğünde (await sayesinde) ana sayfayı yeniler
                            await Navigator.push(
                                context,
                                MaterialPageRoute(builder: (_) => const TeslimatTakipPaneli())
                            );

                            // 🔥 ÇÖZÜM: StatelessWidget içinde setState çalışmaz.
                            // Bunun yerine context'i Element'e cast edip sayfayı güvenle tetikliyoruz.
                            if (context is Element) {
                              (context as Element).markNeedsBuild();
                            }
                          },
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              Container(
                                width: (MediaQuery.of(context).size.width - 42) / 2,
                                padding: const EdgeInsets.all(15),
                                decoration: BoxDecoration(
                                    color: Colors.deepOrange.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(color: Colors.deepOrange.withOpacity(0.3), width: 1.5)
                                ),
                                child: const Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.local_shipping, color: Colors.deepOrange, size: 35),
                                    SizedBox(height: 8),
                                    Text(
                                      "ÜRÜN / EMANET",
                                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.black87),
                                      textAlign: TextAlign.center,
                                    ),
                                  ],
                                ),
                              ),
                              // 🚨 UYARI LABALI (BADGE) - Eğer teslim edilmeyen mal varsa sağ üstte kırmızı daire çıkar
                              if (adet > 0)
                                Positioned(
                                  top: 5,
                                  right: 10,
                                  child: Container(
                                    padding: const EdgeInsets.all(6),
                                    decoration: const BoxDecoration(
                                      color: Colors.red, // Dikkat çekici kırmızı uyarı rengi
                                      shape: BoxShape.circle,
                                    ),
                                    constraints: const BoxConstraints(
                                      minWidth: 24,
                                      minHeight: 24,
                                    ),
                                    child: Text(
                                      '$adet',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        );
                      },
                    ),
                    _islemButon(context, "PERSONEL İŞLERİ", Icons.people, Colors.indigo, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PersonelPaneli()))),
                    _islemButon(context, "ÇEK UYARI", Icons.notification_important, Colors.redAccent, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CekUyariPaneli()))),
                  ],
                )
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _ustBanner(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
    decoration: BoxDecoration(color: Colors.green[900], borderRadius: const BorderRadius.only(bottomLeft: Radius.circular(20), bottomRight: Radius.circular(20))),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("EVREN ÖZÇOBAN", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
            Text("0545 521 75 65", style: TextStyle(color: Colors.white, fontSize: 14)),
            Text("Tefenni/Burdur", style: TextStyle(color: Colors.white70, fontSize: 10)),
          ],
        ),
        Stack(
          alignment: Alignment.center,
          children: [
            Container(
              height: 60, width: 60,
              decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
              child: ClipOval(child: Image.asset('assets/images/logo.png', fit: BoxFit.cover, errorBuilder: (c, e, s) => const Icon(Icons.agriculture, color: Colors.green))),
            ),
            Positioned(
              right: -2, bottom: -2,
              child: GestureDetector(
                onTap: () => _buluttanGeriYukle(context),
                child: Container(
                  padding: const EdgeInsets.all(5),
                  decoration: const BoxDecoration(color: Colors.orange, shape: BoxShape.circle, boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 4)]),
                  child: const Icon(Icons.cloud_download, color: Colors.white, size: 20),
                ),
              ),
            ),
          ],
        ),
      ],
    ),
  );

  Widget _menuKart(BuildContext context, String ad, IconData ikon, Color renk, Widget sayfa) => Card(
    child: ListTile(
      leading: Icon(ikon, color: renk),
      title: Text(ad, style: const TextStyle(fontWeight: FontWeight.bold)),
      trailing: const Icon(Icons.arrow_forward_ios, size: 16),
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => sayfa)),
    ),
  );

  Widget _islemButon(BuildContext context, String baslik, IconData ikon, Color renk, VoidCallback tap) {
    return InkWell(
      onTap: tap,
      child: Container(
        width: (MediaQuery.of(context).size.width - 42) / 2,
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(color: renk.withOpacity(0.1), borderRadius: BorderRadius.circular(10), border: Border.all(color: renk.withOpacity(0.3))),
        child: Column(children: [Icon(ikon, color: renk), const SizedBox(height: 5), Text(baslik, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold))]),
      ),
    );
  }
}