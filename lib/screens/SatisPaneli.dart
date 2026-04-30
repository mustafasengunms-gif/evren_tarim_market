import 'package:flutter/material.dart';
import '../db/database_helper.dart';
import 'package:cloud_firestore/cloud_firestore.dart';


class SatisPaneli extends StatefulWidget {
  final Map arac;
  const SatisPaneli({super.key, required this.arac});

  @override
  State<SatisPaneli> createState() => _SatisPaneliState();
}

class _SatisPaneliState extends State<SatisPaneli> {
  final _musteriC = TextEditingController();
  final _fiyatC = TextEditingController();
  final _kmC = TextEditingController();
  final _kaporaC = TextEditingController(text: "0");
  final _vadeC = TextEditingController();
  final _satisTarihiC = TextEditingController(
    text:
    "${DateTime.now().day.toString().padLeft(2, '0')}.${DateTime.now().month.toString().padLeft(2, '0')}.${DateTime.now().year}",
  );

  String _odemeTipi = "PEŞİN";
  String _durum = "ÖDENDİ";
  double _kalan = 0;

  final List<String> _tipler = ["PEŞİN", "VADELİ", "ÇEK", "SENET", "AÇIK HESAP"];
  final List<String> _durumlar = [
    "ÖDENDİ",
    "BEKLİYOR",
    "PARÇALI ÖDEME",
    "PATLADI / ÖDENMEZ"
        "BU ALACAK BATTI"
  ];

  void _hesaplaKalan() {
    double satis = double.tryParse(_fiyatC.text) ?? 0;
    double kapora = double.tryParse(_kaporaC.text) ?? 0;
    setState(() => _kalan = satis - kapora);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("${widget.arac['plaka']} SATIŞ İŞLEMİ"),
        backgroundColor: Colors.green,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _kart("MÜŞTERİ BİLGİSİ", [
              _input(_musteriC, "MÜŞTERİ ADI SOYADI", Icons.person),
              _input(_satisTarihiC, "SATIŞ TARİHİ (GG.AA.YYYY)",
                  Icons.calendar_today),
              _input(_kmC, "SATIŞ KM", Icons.speed,
                  tip: TextInputType.number),
            ]),

            _kart("SATIŞ VE ÖDEME", [
              _input(_fiyatC, "SATIŞ FİYATI", Icons.monetization_on,
                  tip: TextInputType.number,
                  onChange: (v) => _hesaplaKalan()),
              _input(_kaporaC, "ALINAN KAPORA / PEŞİNAT", Icons.savings,
                  tip: TextInputType.number,
                  onChange: (v) => _hesaplaKalan()),
              const Divider(),
              Text(
                "KALAN ALACAK: $_kalan ₺",
                style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.red),
              ),
            ]),

            _kart("VADE VE TİP", [
              DropdownButtonFormField<String>(
                value: _odemeTipi,
                decoration:
                const InputDecoration(labelText: "ÖDEME ŞEKLİ"),
                items: _tipler
                    .map((e) =>
                    DropdownMenuItem(value: e, child: Text(e)))
                    .toList(),
                onChanged: (v) =>
                    setState(() => _odemeTipi = v!),
              ),
              if (_odemeTipi != "PEŞİN")
                _input(_vadeC, "VADE TARİHİ", Icons.date_range),
              DropdownButtonFormField<String>(
                value: _durum,
                decoration:
                const InputDecoration(labelText: "TAHSİLAT DURUMU"),
                items: _durumlar
                    .map((e) =>
                    DropdownMenuItem(value: e, child: Text(e)))
                    .toList(),
                onChanged: (v) =>
                    setState(() => _durum = v!),
              ),
            ]),

            const SizedBox(height: 20),

            // ✅ BUTON
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                padding:
                const EdgeInsets.symmetric(vertical: 15),
              ),
              onPressed: () async {
                try {
                  int aracId = int.tryParse(
                      widget.arac['id'].toString()) ??
                      0;
                  int aracKm = int.tryParse(
                      widget.arac['km'].toString()) ??
                      0;

                  double satisFiyati =
                      double.tryParse(_fiyatC.text) ?? 0.0;
                  double kapora =
                      double.tryParse(_kaporaC.text) ?? 0.0;

                  int satisKm =
                      int.tryParse(_kmC.text) ?? aracKm;

                  final veri = {
                    'arac_id': aracId,
                    'musteri_ad':
                    _musteriC.text.trim().toUpperCase(),
                    'satis_fiyati': satisFiyati,
                    'satis_km': satisKm,
                    'satis_tarihi':
                    _satisTarihiC.text.trim(),
                    'odeme_tipi': _odemeTipi,
                    'kapora': kapora,
                    'kalan_tutar': _kalan,
                    'vade_tarihi': _vadeC.text.trim(),
                    'durum': 'SATILDI'
                  };

                  await DatabaseHelper.instance
                      .galeriSatisYap(veri: veri);

                  // SatisPaneli.dart içindeki onay butonunun (onPressed) içi:

// 1. Önce yereli güncelle (zaten yapıyorsun)
                  await DatabaseHelper.instance.aracGuncelle(aracId, {'durum': 'SATILDI'});

// 2. ŞİMDİ BULUTU DA GÜNCELLE (Resimdeki yeri değiştirecek olan bu!)
                  await FirebaseFirestore.instance
                      .collection('araclar')
                      .doc(aracId.toString())
                      .update({'durum': 'SATILDI'});

// 3. Sonra dükkana geri dön
                  if (mounted) Navigator.pop(context);
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context)
                        .showSnackBar(
                      SnackBar(
                        content: Text("Hata: $e"),
                      ),
                    );
                  }
                }
              },
              child: const Center(
                child: Text(
                  "SATIŞI ONAYLA",
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _kart(String baslik, List<Widget> cocuklar) => Card(
    elevation: 4,
    margin: const EdgeInsets.only(bottom: 15),
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(baslik,
              style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.blueGrey)),
          const Divider(),
          ...cocuklar
        ],
      ),
    ),
  );

  Widget _input(TextEditingController c, String h, IconData i,
      {TextInputType tip = TextInputType.text,
        Function(String)? onChange}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: TextField(
          controller: c,
          keyboardType: tip,
          onChanged: (v) {
            c.value = c.value.copyWith(text: v.toUpperCase());
            if (onChange != null) onChange(v);
          },
          decoration: InputDecoration(
            labelText: h,
            prefixIcon: Icon(i),
            border: const OutlineInputBorder(),
          ),
        ),
      );
}