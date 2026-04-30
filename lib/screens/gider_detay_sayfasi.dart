import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../db/database_helper.dart';

class GiderDetaySayfasi extends StatefulWidget {
  final String islemTipi;

  const GiderDetaySayfasi({super.key, required this.islemTipi});

  @override
  State<GiderDetaySayfasi> createState() => _GiderDetaySayfasiState();
}

class _GiderDetaySayfasiState extends State<GiderDetaySayfasi> {
  List<Map<String, dynamic>> _yerelHareketler = [];
  List<Map<String, dynamic>> _tarlalar = []; // Tarla listesi buraya gelecek

  String formatTL(dynamic deger) {
    try {
      double rakam = double.tryParse(deger.toString()) ?? 0;
      String sonuc = rakam.toStringAsFixed(2).replaceAll('.', ',');
      RegExp reg = RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))');
      return sonuc.replaceAllMapped(reg, (Match m) => '${m[1]}.');
    } catch (e) {
      return "0,00";
    }
  }

  @override
  void initState() {
    super.initState();
    _verileriYukle();
  }

  Future<void> _verileriYukle() async {
    final tarlalar = await DatabaseHelper.instance.tarlaListesiGetir();
    final hareketler = await DatabaseHelper.instance.tumTarlaHareketleriniGetir();
    if (mounted) {
      setState(() {
        _tarlalar = tarlalar;
        _yerelHareketler = hareketler.where((h) =>
        h['islem_tipi'].toString().toUpperCase() ==
            widget.islemTipi.toUpperCase()).toList();
      });
    }
  }

  // Tarla ID'sine göre isim bulma
  String _tarlaAdiniGetir(dynamic id) {
    if (id == null || id == "0" || id == "") return "GENEL GİDER";
    try {
      return _tarlalar.firstWhere(
              (t) => t['id'].toString() == id.toString(),
          orElse: () => {'mevki': "BİLİNMEYEN"}
      )['mevki'];
    } catch (e) {
      return "GENEL";
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("${widget.islemTipi} DETAYLARI"),
        backgroundColor: Colors.orange[800], // Turuncu Tema
        foregroundColor: Colors.white,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('tarla_hareketleri')
            .where('islem', isEqualTo: widget.islemTipi)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) return const Center(child: Text("Hata!"));
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

          final fbDocs = snapshot.data!.docs;
          Map<String, Map<String, dynamic>> havuz = {};

          for (var doc in fbDocs) {
            var d = doc.data() as Map<String, dynamic>;
            havuz[doc.id] = {
              'id': doc.id,
              'miktar': (d['miktar'] ?? 0),
              'birimFiyat': (d['birimFiyat'] ?? 0),
              'toplam': (d['toplam'] ?? d['tutar'] ?? 0),
              'aciklama': d['aciklama'] ?? "Bulut Kaydı",
              'sezon': d['sezon'] ?? "2026",
              'tarlaId': d['tarlaId'] ?? "0",
              'kaynak': 'FB'
            };
          }

          for (var h in _yerelHareketler) {
            String? fId = h['firebase_id']?.toString();
            String key = (fId != null && fId.isNotEmpty) ? fId : "sql_${h['id']}";
            havuz[key] = {
              'id': key,
              'miktar': (h['miktar'] ?? 0),
              'birimFiyat': (h['birimFiyat'] ?? 0),
              'toplam': (h['tutar'] ?? 0),
              'aciklama': h['islem_adi'] ?? "Yerel Kayıt",
              'sezon': h['sezon'] ?? "2026",
              'tarlaId': h['tarla_id']?.toString() ?? "0",
              'kaynak': (fId != null && fId.isNotEmpty) ? 'SENKRON' : 'SQL'
            };
          }

          final tamListe = havuz.values.toList();
          tamListe.sort((a, b) => b['id'].compareTo(a['id']));

          return Column(
            children: [
              // ÖZET PANELİ
              Container(
                color: Colors.orange[50],
                padding: const EdgeInsets.all(15),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _istatistik("TOPLAM KAYIT", "${tamListe.length}"),
                    _istatistik("TOPLAM TUTAR", "${formatTL(tamListe.fold(0.0, (sum, item) => sum + (double.tryParse(item['toplam'].toString()) ?? 0)))} TL", renk: Colors.red[900]!),
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: tamListe.length,
                  itemBuilder: (context, index) => _listeElemani(tamListe[index]),
                ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: Colors.orange[800],
        onPressed: () => _giderKayitDiyalog(widget.islemTipi),
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  Widget _listeElemani(Map<String, dynamic> veri) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      child: ListTile(
        onTap: () => _giderKayitDiyalog(widget.islemTipi, mevcutVeri: veri),
        leading: Icon(Icons.agriculture, color: Colors.orange[800]),
        title: Text("${_tarlaAdiniGetir(veri['tarlaId'])}", style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text("${veri['miktar']} Birim - ${veri['aciklama']}"),
        trailing: Text("${formatTL(veri['toplam'])} TL", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
      ),
    );
  }

  void _giderKayitDiyalog(String islemTipi, {Map<String, dynamic>? mevcutVeri}) {
    int? seciliTarlaId = int.tryParse(mevcutVeri?['tarlaId']?.toString() ?? "");
    final miktarC = TextEditingController(text: mevcutVeri?['miktar']?.toString() ?? "1");
    final birimFiyatC = TextEditingController(text: mevcutVeri?['birimFiyat']?.toString() ?? "0");
    final aciklamaC = TextEditingController(text: mevcutVeri?['aciklama']?.toString() ?? "");
    final toplamC = TextEditingController(text: mevcutVeri?['toplam']?.toString() ?? "0");

    showDialog(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: Colors.orange[800], borderRadius: BorderRadius.circular(10)),
              child: Text(mevcutVeri == null ? "$islemTipi EKLE" : "DÜZELT", style: const TextStyle(color: Colors.white, fontSize: 16)),
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // TARLA SEÇİMİ (Artık Var!)
                  // Dropdown kısmını bu şekilde güncelle:
                  DropdownButtonFormField<int>(
                    // EĞER seciliTarlaId listede yoksa (yani yeni kayıt açıyorsan), value null olsun.
                    // Bu satır hatayı kökten çözer:
                    value: _tarlalar.any((t) => t['id'] == seciliTarlaId) ? seciliTarlaId : null,

                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: "TARLA SEÇİN",
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.map, color: Colors.orange),
                    ),

                    // Listeyi oluştururken her ihtimale karşı null kontrolü ekliyoruz
                    items: _tarlalar.map((t) {
                      return DropdownMenuItem<int>(
                        value: t['id'], // Buradaki ID ile yukarıdaki 'value' eşleşmeli
                        child: Text("${t['mevki']} (${t['ekilen_urun']})", style: const TextStyle(fontSize: 13)),
                      );
                    }).toList(),

                    onChanged: (v) {
                      setDialogState(() {
                        seciliTarlaId = v;
                      });
                    },
                  ),
                  const SizedBox(height: 10),
                  _input(miktarC, "MİKTAR", Icons.add_box, tip: TextInputType.number, onChanged: (_) {
                    double m = double.tryParse(miktarC.text) ?? 0;
                    double b = double.tryParse(birimFiyatC.text) ?? 0;
                    toplamC.text = (m * b).toStringAsFixed(2);
                    setDialogState(() {});
                  }),
                  _input(birimFiyatC, "BİRİM FİYAT", Icons.money, tip: TextInputType.number, onChanged: (_) {
                    double m = double.tryParse(miktarC.text) ?? 0;
                    double b = double.tryParse(birimFiyatC.text) ?? 0;
                    toplamC.text = (m * b).toStringAsFixed(2);
                    setDialogState(() {});
                  }),
                  _input(toplamC, "TOPLAM", Icons.functions, color: Colors.red),
                  _input(aciklamaC, "NOT", Icons.edit),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(c), child: const Text("İPTAL")),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.orange[800]),
                onPressed: () async {
                  double m = double.tryParse(miktarC.text) ?? 0;
                  double b = double.tryParse(birimFiyatC.text) ?? 0;
                  double t = m * b;
                  final data = {
                    'islem': islemTipi, // Firebase için
                    'islem_tipi': islemTipi.toUpperCase(), // SQLite için
                    'miktar': m,
                    'birim_fiyat': b, // SQLite tablonla uyumlu hale getirildi
                    'toplam': t,
                    'tutar': t, // SQLite 'tutar' kolonunu doldurur
                    'aciklama': aciklamaC.text.toUpperCase(), // Firebase için
                    'islem_adi': aciklamaC.text.toUpperCase(), // SQLite 'islem_adi' kolonu için
                    'tarih': DateTime.now().toString().split(' ')[0],
                    'sezon': "2026",
                    'tarla_id': seciliTarlaId, // SQLite bağlantısı için KRİTİK
                    'tarlaId': seciliTarlaId.toString(), // Firebase aramaları için
                  };

                  if (mevcutVeri == null) {
                    DocumentReference docRef = await FirebaseFirestore.instance.collection('tarla_hareketleri').add(data);
                    await DatabaseHelper.instance.tarlaHareketiEkle({...data, 'firebase_id': docRef.id});
                  } else {
                    if (mevcutVeri['kaynak'] != 'SQL') {
                      await FirebaseFirestore.instance.collection('tarla_hareketleri').doc(mevcutVeri['id']).update(data);
                    }
                    await DatabaseHelper.instance.tarlaHareketiGuncelle(mevcutVeri['id'], data);
                  }
                  Navigator.pop(c);
                  _verileriYukle();
                },
                child: const Text("KAYDET", style: TextStyle(color: Colors.white)),
              )
            ],
          );
        },
      ),
    );
  }

  Widget _istatistik(String b, String d, {Color renk = Colors.black}) => Column(children: [Text(b, style: const TextStyle(fontSize: 10, color: Colors.grey)), Text(d, style: TextStyle(fontWeight: FontWeight.bold, color: renk))]);

  Widget _input(TextEditingController c, String l, IconData i, {TextInputType tip = TextInputType.text, Color? color, Function(String)? onChanged}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: TextFormField(
        controller: c,
        keyboardType: tip,
        onChanged: onChanged,
        style: TextStyle(color: color, fontWeight: color != null ? FontWeight.bold : FontWeight.normal),
        decoration: InputDecoration(labelText: l, prefixIcon: Icon(i, color: Colors.orange[800]), border: const OutlineInputBorder()),
      ),
    );
  }
}