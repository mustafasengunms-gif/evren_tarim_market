import 'package:flutter/material.dart';
import 'dart:io';
import 'package:intl/intl.dart';
import '../db/database_helper.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

class BakimPaneli extends StatefulWidget {
  final Map arac;
  const BakimPaneli({super.key, required this.arac});

  @override
  State<BakimPaneli> createState() => _BakimPaneliState();
}

class _BakimPaneliState extends State<BakimPaneli> {
  List<Map<String, dynamic>> _bakimlar = [];
  double _toplamEkstraMasraf = 0;

  // 🔥 EKSİK OLAN DEĞİŞKENLER BURAYA EKLENDİ:
  final TextEditingController _tutarC = TextEditingController();
  final TextEditingController _aciklamaC = TextEditingController();
  String _seciliUsta = "MOTOR USTASI"; // Varsayılan seçim

  final List<String> _ustalar = [
    "MOTOR USTASI", "KAPORTACI", "BOYACI",
    "ELEKTRİKÇİ", "DÖŞEMECİ", "LASTİKÇİ", "YEDEK PARÇACI"
  ];

  @override
  void initState() {
    super.initState();
    _verileriYukle();
  }

  Widget buildImage(String? path) {
    if (path == null || path.isEmpty) {
      return Image.asset("assets/images/logo.png");
    }
    if (kIsWeb) {
      return Image.network(path); // Web'de resimler genelde URL veya network üzerinden gelir
    }
    return Image.file(File(path));
  }

  void _verileriYukle() async {
    // Hem Web (Firebase ID) hem Mobil (SQLite ID) uyumluluğu için tüm ID alternatiflerini kontrol ediyoruz
    String bicerId = (widget.arac['id'] ?? widget.arac['id_firebase'] ?? widget.arac['firebase_id'] ?? '').toString();

    // Eğer ID hâlâ boş veya "-1" ise ve web üzerindeysek döküman adını korumak için sağlama alıyoruz
    if (bicerId.isEmpty || bicerId == "-1") {
      print("⚠️ Uyarı: Geçersiz araç ID'si saptandı! (${widget.arac})");
    }

    try {
      // DatabaseHelper katmanındaki web uyumlu sorguyu çağırıyoruz
      List<Map<String, dynamic>> bakimListesi =
      await DatabaseHelper.instance.bicerBakimlariniGetir(bicerId);

      double toplamMasraf = 0;
      for (var bakim in bakimListesi) {
        toplamMasraf += double.tryParse(bakim['tutar'].toString()) ?? 0;
      }

      setState(() {
        _bakimlar = bakimListesi;
        _toplamEkstraMasraf = toplamMasraf;
      });
    } catch (e) {
      debugPrint("‼️ Bakım verileri arayüze yüklenirken hata: $e");
    }
  }

  void _bakimEkle() async {
    if (_tutarC.text.isEmpty || _aciklamaC.text.isEmpty) return;

    double tutar = double.tryParse(_tutarC.text.replaceAll(',', '.')) ?? 0.0;
    String usta = _seciliUsta;
    String aciklama = _aciklamaC.text.trim().toUpperCase();
    String tarihStr = DateFormat('dd.MM.yyyy').format(DateTime.now());

    String bicerId = (widget.arac['id'] ?? widget.arac['id_firebase'] ?? widget.arac['firebase_id'] ?? '').toString();

    Map<String, dynamic> yeniBakim = {
      'bicer_id': bicerId, // Hem web koleksiyon eşleşmesi hem SQLite ilişkisi için ortak alan
      'usta': usta,
      'aciklama': aciklama,
      'tutar': tutar,
      'tarih': tarihStr,
      'is_synced': 0,
    };

    try {
      // Web ise doğrudan Firebase'e, mobil ise yerel + arka plan senkronuna kaydeder
      await DatabaseHelper.instance.bicerBakimEkle(yeniBakim);

      _tutarC.clear();
      _aciklamaC.clear();
      Navigator.pop(context); // Pop-up dialog penceresini kapat

      _verileriYukle(); // Ekrandaki listeyi ve maliyet grafiğini anlık tazele

      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text("Bakım Masrafı Başarıyla İşlendi ✅"),
        backgroundColor: Colors.green,
      ));
    } catch (e) {
      debugPrint("‼️ Masraf Kaydedilirken Hata: $e");
    }
  }

  void _bakimKaydetFormu() {
    String secilenUsta = _ustalar[0];
    TextEditingController islemC = TextEditingController();
    TextEditingController tutarC = TextEditingController();

    showDialog(
      context: context,
      builder: (context) {
        // Dialog açıldığında usta seçimi için bir geçici değişken (Eğer sayfa genelinde tanımlı değilse)
        String secilenUstaLocal = "MOTOR USTASI";

        return StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: const Text("BAKIM / ONARIM GİRİŞİ",
                style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButton<String>(
                    isExpanded: true,
                    value: _ustalar.contains(secilenUstaLocal) ? secilenUstaLocal : _ustalar.first,
                    items: _ustalar.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                    onChanged: (v) => setDialogState(() => secilenUstaLocal = v!),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _aciklamaC, // _aciklamaC olarak güncellendi
                    decoration: const InputDecoration(labelText: "YAPILAN İŞLEM (AÇIKLAMA)", border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _tutarC, // _tutarC olarak güncellendi
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: "ÖDENEN TUTAR", suffixText: "₺", border: OutlineInputBorder()),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text("İPTAL")),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
                onPressed: () async {
                  final islem = _aciklamaC.text.trim().toUpperCase();
                  final tutarHam = _tutarC.text.trim();

                  if (islem.isNotEmpty && tutarHam.isNotEmpty) {
                    try {
                      // Hem mobil hem web uyumluluğu için ID'yi string alıyoruz
                      final String bicerId = (widget.arac['id'] ?? widget.arac['id_firebase'] ?? '').toString();
                      final double tutar = double.tryParse(tutarHam.replaceAll(',', '.')) ?? 0.0;
                      final String tarihStr = DateFormat('dd.MM.yyyy').format(DateTime.now());

                      if (bicerId.isEmpty) {
                        print("❌ Hata: Makine ID bulunamadı!");
                        return;
                      }

                      // 💾 DATABASE_HELPER VE SİSTEM ŞEMASI İLE TAM UYUMLU PAKET:
                      Map<String, dynamic> bakimVerisi = {
                        'bicer_id': bicerId,         // Veritabanının beklediği ilişki sütunu
                        'usta': secilenUstaLocal,    // DatabaseHelper'daki 'usta' sütunu
                        'aciklama': islem,           // DatabaseHelper'daki 'aciklama' sütunu
                        'tutar': tutar,              // Sütun adı: tutar
                        'tarih': tarihStr,           // Biçim: dd.MM.yyyy
                        'is_synced': 0,
                      };

                      print("💾 Kaydediliyor: $bakimVerisi");

                      // Yeni yazdığımız ve hem Web/Firebase hem Mobil destekleyen fonksiyonu tetikliyoruz
                      await DatabaseHelper.instance.bicerBakimEkle(bakimVerisi);

                      if (mounted) {
                        _aciklamaC.clear(); // Giriş kutularını temizle
                        _tutarC.clear();

                        Navigator.pop(context); // Diyaloğu kapat
                        _verileriYukle();      // Listeyi ve Güncel Maliyeti yenile

                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text("Bakım kaydı başarıyla eklendi. ✅"), backgroundColor: Colors.green),
                        );
                      }
                    } catch (e) {
                      print("❌ Kayıt Hatası: $e");
                    }
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text("⚠️ İşlem açıklaması veya tutar boş olamaz!"), backgroundColor: Colors.orange),
                    );
                  }
                },
                child: const Text("FİŞİ KES", style: TextStyle(color: Colors.white)),
              )
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    // Verilerin null olma ihtimaline karşı kontrol
    double alisFiyati = double.tryParse(widget.arac['alis_fiyati']?.toString() ?? '0') ?? 0;
    double genelToplam = alisFiyati + _toplamEkstraMasraf;

    return Scaffold(
      appBar: AppBar(
        title: Text("${widget.arac['plaka'] ?? 'Araç'} - BAKIM"),
        backgroundColor: Colors.blueGrey,
      ),
      body: Column(
        children: [
          _maliyetOzeti(alisFiyati, genelToplam),
          const Padding(
            padding: EdgeInsets.all(8.0),
            child: Text("YAPILAN İŞLEMLER GEÇMİŞİ",
                style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey)),
          ),
          Expanded(
            child: _bakimlar.isEmpty
                ? const Center(child: Text("Henüz bir işlem kaydı yok."))
                : ListView.builder(
              itemCount: _bakimlar.length,
              itemBuilder: (context, i) {
                final b = _bakimlar[i];
                return Card(
                  elevation: 2,
                  margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  child: ListTile(
                    leading: Icon(_getIcon(b['usta_tipi'] ?? ""), color: Colors.blue),
                    title: Text(b['islem_detay'] ?? "Detay yok",
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.black87)),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("${b['usta_tipi']}",
                            style: const TextStyle(fontSize: 12, color: Colors.blueGrey, fontWeight: FontWeight.w500)),
                        Text(
                          // Tarihi 2026-04-24 formatından 24.04.2026 formatına çevirir
                          b['tarih'].toString().split('-').reversed.join('.'),
                          style: const TextStyle(fontSize: 11, color: Colors.grey),
                        ),
                      ],
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_tlFormat(b['tutar']), // Burada fonksiyonu çağırdık
                            style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 14)),
                        IconButton(
                          icon: const Icon(Icons.delete_outline, color: Colors.red),
                          onPressed: () async {
                            await DatabaseHelper.instance.bakimSil(b['id']);
                            _verileriYukle();
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
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _bakimKaydetFormu,
        label: const Text("BAKIM / MASRAF EKLE"),
        icon: const Icon(Icons.build_circle),
        backgroundColor: Colors.blue,
      ),
    );
  }

  // Alt metodlar (Widgetları böldüğün yerler)
  Widget _maliyetOzeti(double alis, double genel) {
    return Container(
      // ... mevcut dekorasyon kodların ...
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _maliyetSutun("ALIŞ", _tlFormat(alis), Colors.black),
              const Icon(Icons.add, size: 15),
              _maliyetSutun("MASRAF", _tlFormat(_toplamEkstraMasraf), Colors.red),
            ],
          ),
          const Divider(),
          Text("GÜNCEL MALİYET: ${_tlFormat(genel)}",
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.green)),
        ],
      ),
    );
  }
  String _tlFormat(dynamic deger) {
    double miktar = double.tryParse(deger.toString()) ?? 0;
    // Binlik ayraçları eklemek için (Örn: 15000 -> 15.000)
    RegExp reg = RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))');
    String sonuc = miktar.toStringAsFixed(0).replaceAllMapped(reg, (Match m) => '${m[1]}.');
    return "$sonuc ₺";
  }


  Widget _maliyetSutun(String baslik, String deger, Color renk) {
    return Column(
      children: [
        Text(baslik, style: const TextStyle(fontSize: 10, color: Colors.grey)),
        Text(deger, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: renk)),
      ],
    );
  }

  IconData _getIcon(String usta) {
    if (usta.contains("BOYA")) return Icons.format_paint;
    if (usta.contains("MOTOR")) return Icons.settings_input_component;
    if (usta.contains("LASTİK")) return Icons.adjust;
    if (usta.contains("PARÇA")) return Icons.shopping_bag;
    return Icons.handyman;
  }
}