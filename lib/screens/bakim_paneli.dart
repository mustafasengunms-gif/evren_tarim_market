import 'package:flutter/material.dart';
// Tek bir import biçimi kullanmak daha güvenlidir
import '../db/database_helper.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:io' as io; // 'File' yerine 'io.File' kullanacağız
import 'package:flutter/foundation.dart';
import 'dart:io' show File;

class BakimPaneli extends StatefulWidget {
  final Map arac;
  const BakimPaneli({super.key, required this.arac});

  @override
  State<BakimPaneli> createState() => _BakimPaneliState();
}

class _BakimPaneliState extends State<BakimPaneli> {
  List<Map<String, dynamic>> _bakimlar = [];
  double _toplamEkstraMasraf = 0;

  final List<String> _ustalar = [
    "MOTOR USTASI", "KAPORTACI", "BOYACI",
    "ELEKTRİKÇİ", "DÖŞEMECİ", "LASTİKÇİ", "YEDEK PARÇACI"
  ];


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
      return Image.network(path);
    } else {
      return Image.file(File(path));
    }
  }

  Future<void> _verileriYukle() async {
    // widget.arac['id'] değerinin int olduğundan emin olalım
    // Eğer String geliyorsa int'e çevirir, zaten int ise aynen bırakır.
    final dynamic hamId = widget.arac['id'];
    final int guvenliId = hamId is int ? hamId : int.parse(hamId.toString());

    try {
      // 2. Çağırırken de 'u' kullanmalısın
      final veriler = await DatabaseHelper.instance.bakimlariGetir(guvenliId);

    double toplam = 0;
    for (var kalem in veriler) {
    toplam += double.tryParse(kalem['tutar'].toString()) ?? 0;
    }

    setState(() {
    _bakimlar = veriler;
    _toplamEkstraMasraf = toplam;
    });
    } catch (e) {
    print("Yükleme hatası: $e");
    }
  }

  void _bakimKaydetFormu() {
    String secilenUsta = _ustalar[0];
    TextEditingController islemC = TextEditingController();
    TextEditingController tutarC = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text("BAKIM / ONARIM GİRİŞİ",
              style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButton<String>(
                  isExpanded: true,
                  value: secilenUsta,
                  items: _ustalar.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                  onChanged: (v) => setDialogState(() => secilenUsta = v!),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: islemC,
                  decoration: const InputDecoration(labelText: "YAPILAN İŞLEM", border: OutlineInputBorder()),
                  // Büyük harfe zorlama
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: tutarC,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: "ÖDENEN TUTAR", suffixText: "₺", border: OutlineInputBorder()),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text("İPTAL")),
            // bakim_paneli.dart dosyasının içinde aşağılara doğru in
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
              onPressed: () async {
                // 1. Önce boşluk kontrolü yapıyoruz
                if (tutarC.text.isNotEmpty && islemC.text.isNotEmpty) {

                  // 2. İŞTE BURAYA EKLEYECEKSİN (DatabaseHelper'ı çağırdığın yer)
                  await DatabaseHelper.instance.bakimEkle({
                    'arac_id': widget.arac['id'],
                    'usta_tipi': secilenUsta,
                    'islem_detay': islemC.text.toUpperCase(),
                    'tutar': double.tryParse(tutarC.text) ?? 0,
                    'tarih': DateTime.now().toString().substring(0, 10),
                    'firebase_id': widget.arac['id'].toString(), // Firestore'daki döküman ID'si
                  });

                  // 3. Kayıttan sonra sayfayı kapat ve listeyi yenile
                  if (mounted) Navigator.pop(context);
                  _verileriYukle();
                }
              },
              child: const Text("FİŞİ KES", style: TextStyle(color: Colors.white)),
            )
          ],
        ),
      ),
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