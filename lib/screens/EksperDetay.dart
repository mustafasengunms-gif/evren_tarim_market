import 'package:flutter/material.dart';
import '../db/database_helper.dart';


class EksperDetay extends StatefulWidget {
  final Map arac;
  const EksperDetay({super.key, required this.arac});

  @override
  State<EksperDetay> createState() => _EksperDetayState();
}

class _EksperDetayState extends State<EksperDetay> {
  List<Map<String, dynamic>> _kayitlar = [];
  Map<String, String> _seciliDurumlar = {};

  final List<String> _parcalar = [
    "KAPUT", "TAVAN", "BAGAJ", "SAĞ ÖN ÇAMURLUK", "SAĞ ÖN KAPI",
    "SAĞ ARKA KAPI", "SAĞ ARKA ÇAMURLUK", "SOL ÖN ÇAMURLUK",
    "SOL ÖN KAPI", "SOL ARKA KAPI", "SOL ARKA ÇAMURLUK"
  ];

  @override
  void initState() {
    super.initState();
    _verileriYukle();
    _durumlariSifirla();
  }

  void _durumlariSifirla() {
    for (var p in _parcalar) { _seciliDurumlar[p] = "ORİJİNAL"; }
  }

  Future<void> _verileriYukle() async {
    try {
      final int aracId = int.tryParse(widget.arac['id'].toString()) ?? 0;
      if (aracId != 0) {
        final veriler = await DatabaseHelper.instance.eksperKayitlariniGetir(aracId);
        setState(() {
          _kayitlar = veriler;
        });
      }
    } catch (e) {
      debugPrint("❌ Veri yükleme hatası: $e");
    }
  }

  Future<void> _eksperKaydet(String not) async {
    try {
      final int aracId = int.tryParse(widget.arac['id'].toString()) ?? 0;

      String hasarNotu = "";
      _seciliDurumlar.forEach((parca, durum) {
        if (durum != "ORİJİNAL") {
          hasarNotu += "$parca: $durum\n";
        }
      });

      if (not.isNotEmpty) hasarNotu += "NOT: ${not.toUpperCase()}";
      if (hasarNotu.isEmpty) hasarNotu = "TÜM PARÇALAR ORİJİNAL";

      final yeniKayit = {
        'arac_id': aracId,
        'hasar_notu': hasarNotu,
        'tarih': DateTime.now().toString().substring(0, 16),
      };

      // 1. ADIM: Eksper kaydını ekle (Bu artık başarılı)
      await DatabaseHelper.instance.eksperKaydiEkle(yeniKayit);

      // 2. ADIM: Aracın durumunu güncelle
      // DİKKAT: Burada 'galeri' tablosu yerine 'araclar' mı yazmalı?
      // DatabaseHelper.dart içindeki metodu kontrol et!
      await DatabaseHelper.instance.aracGuncelle(aracId, {'durum': 'EKSPERLİ'});

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("✅ Kaydedildi"), backgroundColor: Colors.green)
        );
      }
    } catch (e) {
      debugPrint("🔥 PATLADI: $e");
      if (mounted) {
        // Hatayı ekranda gör ki ne olduğunu anlayalım
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("❌ Hata: $e"), backgroundColor: Colors.red)
        );
      }
    }
  }

  void _eksperFormuAc({Map? eskiKayit}) {
    _durumlariSifirla();
    TextEditingController notC = TextEditingController();

    if (eskiKayit != null) {
      String rapor = eskiKayit['hasar_notu'] ?? "";
      for (var p in _parcalar) {
        if (rapor.contains("$p: BOYALI")) _seciliDurumlar[p] = "BOYALI";
        else if (rapor.contains("$p: LOKAL BOYALI")) _seciliDurumlar[p] = "LOKAL BOYALI";
        else if (rapor.contains("$p: DEĞİŞEN")) _seciliDurumlar[p] = "DEĞİŞEN";
      }
      if (rapor.contains("NOT: ")) notC.text = rapor.split("NOT: ").last;
    }

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text("YENİ EKSPER RAPORU"),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                children: [
                  Container(
                    height: 180,
                    width: double.infinity,
                    decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(10)),
                    child: CustomPaint(painter: AracSemasiPainter(durumlar: _seciliDurumlar)),
                  ),
                  const Divider(),
                  ..._parcalar.map((p) => Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(p, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold)),
                      DropdownButton<String>(
                        value: _seciliDurumlar[p],
                        items: ["ORİJİNAL", "BOYALI", "LOKAL BOYALI", "DEĞİŞEN"]
                            .map((e) => DropdownMenuItem(value: e, child: Text(e, style: const TextStyle(fontSize: 10)))).toList(),
                        onChanged: (v) {
                          setDialogState(() => _seciliDurumlar[p] = v!);
                          setState(() {});
                        },
                      )
                    ],
                  )),
                  const SizedBox(height: 10),
                  TextField(
                    controller: notC,
                    decoration: const InputDecoration(labelText: "ÖZEL NOT", border: OutlineInputBorder()),
                    onChanged: (v) => notC.value = notC.value.copyWith(text: v.toUpperCase()),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text("İPTAL")),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
              onPressed: () => _eksperKaydet(notC.text),
              child: const Text("RAPORU KAYDET", style: TextStyle(color: Colors.white)),
            )
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("${widget.arac['plaka']} - EKSPER"), backgroundColor: Colors.orange),
      body: Column(
        children: [
          _ustBilgi(),
          Expanded(
            child: _kayitlar.isEmpty
                ? const Center(child: Text("Henüz rapor eklenmemiş."))
                : ListView.builder(
              itemCount: _kayitlar.length,
              itemBuilder: (context, i) => _kayitKarti(_kayitlar[i]),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _eksperFormuAc(),
        backgroundColor: Colors.orange,
        icon: const Icon(Icons.add),
        label: const Text("YENİ RAPOR"),
      ),
    );
  }

  Widget _ustBilgi() => Container(
    padding: const EdgeInsets.all(15),
    color: Colors.orange.withOpacity(0.1),
    child: Row(children: [
      const Icon(Icons.directions_car, size: 40, color: Colors.orange),
      const SizedBox(width: 15),
      Text("${widget.arac['marka']} ${widget.arac['model']}\n${widget.arac['plaka']}",
          style: const TextStyle(fontWeight: FontWeight.bold)),
    ]),
  );

  Widget _kayitKarti(Map k) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      elevation: 3,
      child: ListTile(
        leading: const Icon(Icons.description, color: Colors.orange),
        title: Text(k['hasar_notu'], style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
        subtitle: Text(k['tarih'] ?? ""),
        trailing: IconButton(
          icon: const Icon(Icons.delete, color: Colors.red),
          onPressed: () async {
            bool? onay = await showDialog(
                context: context,
                builder: (c) => AlertDialog(
                  title: const Text("SİLME ONAYI"),
                  content: const Text("Bu raporu silmek istediğinize emin misiniz?"),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(c, false), child: const Text("HAYIR")),
                    TextButton(onPressed: () => Navigator.pop(c, true), child: const Text("EVET")),
                  ],
                )
            );
            if (onay == true) {
              await DatabaseHelper.instance.eksperKaydiSil(k['id']);
              _verileriYukle();
            }
          },
        ),
      ),
    );
  }
}

class AracSemasiPainter extends CustomPainter {
  final Map<String, String> durumlar;
  AracSemasiPainter({required this.durumlar});

  Color _renkGetir(String parca) {
    String d = durumlar[parca] ?? "ORİJİNAL";
    if (d == "BOYALI") return Colors.orange;
    if (d == "LOKAL BOYALI") return Colors.yellow[700]!;
    if (d == "DEĞİŞEN") return Colors.red;
    return Colors.green.withOpacity(0.4);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final borderPaint = Paint()..style = PaintingStyle.stroke..color = Colors.black..strokeWidth = 0.5;
    double w = size.width; double h = size.height; double cx = w / 2;

    void _ciz(Rect r, String parca) {
      canvas.drawRect(r, Paint()..color = _renkGetir(parca));
      canvas.drawRect(r, borderPaint);
    }

    // Orta Sütun
    _ciz(Rect.fromLTWH(cx - 15, h * 0.1, 30, 20), "KAPUT");
    _ciz(Rect.fromLTWH(cx - 15, h * 0.35, 30, 30), "TAVAN");
    _ciz(Rect.fromLTWH(cx - 15, h * 0.75, 30, 15), "BAGAJ");

    // Sol Taraf
    _ciz(Rect.fromLTWH(cx - 35, h * 0.1, 15, 20), "SOL ÖN ÇAMURLUK");
    _ciz(Rect.fromLTWH(cx - 35, h * 0.35, 15, 20), "SOL ÖN KAPI");
    _ciz(Rect.fromLTWH(cx - 35, h * 0.58, 15, 20), "SOL ARKA KAPI");
    _ciz(Rect.fromLTWH(cx - 35, h * 0.8, 15, 15), "SOL ARKA ÇAMURLUK");

    // Sağ Taraf
    _ciz(Rect.fromLTWH(cx + 20, h * 0.1, 15, 20), "SAĞ ÖN ÇAMURLUK");
    _ciz(Rect.fromLTWH(cx + 20, h * 0.35, 15, 20), "SAĞ ÖN KAPI");
    _ciz(Rect.fromLTWH(cx + 20, h * 0.58, 15, 20), "SAĞ ARKA KAPI");
    _ciz(Rect.fromLTWH(cx + 20, h * 0.8, 15, 15), "SAĞ ARKA ÇAMURLUK");
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}