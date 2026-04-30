
import 'package:flutter/foundation.dart' show kIsWeb; // Web olup olmadığını anlamak için
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


void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      print("✅ Firebase Jilet Gibi Başlatıldı");
    }
  } catch (e) {
    debugPrint("⚠️ Firebase zaten açık veya bir hata oluştu: $e");
  }

  // ✅ SADECE MOBİLDE çalışacak işlemler
  if (!kIsWeb) {
    try {
      await DatabaseHelper.instance.database;
      _arkaPlanServisleriniBaslat(); // ✅ TEK NOKTA
    } catch (e) {
      debugPrint("❌ Yerel DB başlatma hatası: $e");
    }
  }

  // --- KAPIDAKİ KONTROL ---
  User? user = FirebaseAuth.instance.currentUser;

  Widget ilkSayfa =
  (user == null) ? const GirisEkrani() : const GirisKapisi();

  runApp(
    MaterialApp(
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
        colorSchemeSeed: Colors.green,
        scaffoldBackgroundColor: const Color(0xFFF8F9FA),
      ),
      home: ilkSayfa,
    ),
  );

  // ❌ BURAYI SİLDİK (EN KRİTİK HATA BUYDU)
  // _arkaPlanServisleriniBaslat();
}
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Container(),
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

// --- SENİN MEVCUT KODLARIN (DOKUNULMADI) ---

void _arkaPlanServisleriniBaslat() {
  Future.delayed(const Duration(seconds: 8), () async {
    print("🚀 [SYNC] Akıllı Senkronizasyon Başlatıldı...");
    try {
      await DatabaseHelper.instance.herSeyiBuluttanIndir();
      await DatabaseHelper.instance.herSeyiBulutaBas();
      print("🏁 [İŞLEM TAMAM] Evren Sistem Güncel.");
    } catch (err) {
      debugPrint("❌ Senkronizasyon Hatası: $err");
    }
  });
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

                    _islemButon(context, "PERSONEL İŞLERİ", Icons.people, Colors.indigo, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PersonelPaneli()))),
                    _islemButon(context, "ÇEK UYARI", Icons.notification_important, Colors.redAccent, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CekUyariPaneli()))),
                  ],
                ),
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