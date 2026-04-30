
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../db/database_helper.dart';
import '../utils/pdf_helper.dart';
import 'package:evren_tarim_market/db/database_helper.dart';


class AlisIslemSayfasi extends StatefulWidget {
  final int seciliSube; // 0: TEFENNİ, 1: AKSU
  const AlisIslemSayfasi({super.key, required this.seciliSube});

  @override
  State<AlisIslemSayfasi> createState() => _AlisIslemSayfasiState();
}

class _AlisIslemSayfasiState extends State<AlisIslemSayfasi> {
  DateTime _tarih = DateTime.now();
  String? _seciliFirma;
  String? _seciliMarka;
  String? _seciliModel;
  String? _seciliAltModel;
  String? _seciliKategori;

  List<Map<String, dynamic>> _firmaListesi = [];
  List<Map<String, dynamic>> _stokTanimListesi = [];
  List<String> _kategoriler = [];

  final TextEditingController _faturaNoController = TextEditingController();
  final TextEditingController _adetController = TextEditingController();
  final TextEditingController _fiyatController = TextEditingController();
  final TextEditingController _kategoriController = TextEditingController();
  final TextEditingController _markaController = TextEditingController();
  final TextEditingController _modelController = TextEditingController();
  final TextEditingController _altModelController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _verileriYukle();
  }

  Future<void> _verileriYukle() async {
    try {
      final gelenFirmalar = await DatabaseHelper.instance.tarimFirmaListesiGetir();
      final gelenStoklar = await DatabaseHelper.instance.stokTanimlariniGetir();
      setState(() {
        _firmaListesi = gelenFirmalar;
        _stokTanimListesi = gelenStoklar;
        _kategoriler = gelenStoklar
            .map((e) => e['kategori'].toString())
            .toSet()
            .where((s) => s.isNotEmpty && s != "null")
            .toList();
      });
    } catch (e) {
      debugPrint("❌ VERİ YÜKLEME HATASI: $e");
    }
  }

  Future<void> _tanimIslemDialog(String tip, {bool guncellemeMi = false}) async {
    if (_seciliFirma == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("ÖNCE FİRMA SEÇİN!")));
      return;
    }

    String eskiDeger = "";
    if (guncellemeMi) {
      if (tip == "KATEGORİ") eskiDeger = _seciliKategori ?? "";
      else if (tip == "MARKA") eskiDeger = _seciliMarka ?? "";
      else if (tip == "MODEL") eskiDeger = _seciliModel ?? "";
      else if (tip == "ALTMODEL") eskiDeger = _seciliAltModel ?? "";
    }

    TextEditingController _islemController = TextEditingController(text: eskiDeger);

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(guncellemeMi ? "$tip GÜNCELLE" : "YENİ $tip EKLE"),
        content: TextField(
          controller: _islemController,
          decoration: InputDecoration(hintText: "$tip adını girin"),
          textCapitalization: TextCapitalization.characters,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("İPTAL")),
          ElevatedButton(
            onPressed: () async {
              if (_islemController.text.isNotEmpty) {
                String yeniDeger = _islemController.text.toUpperCase().trim();
                if (guncellemeMi) {
                  await DatabaseHelper.instance.stokTanimGuncelle(
                      _seciliFirma!,
                      tip == "MARKA" ? eskiDeger : (_seciliMarka ?? ""),
                      tip == "MODEL" ? eskiDeger : (_seciliModel ?? ""),
                      eskiDeger,
                      yeniDeger,
                      tip
                  );
                } else {
                  // --- EVREN ABİ, SIRALAMA ŞİMDİ JİLET GİBİ OLDU ---
                  await DatabaseHelper.instance.stokTanimEkle({
                    'kategori': tip == "KATEGORİ" ? yeniDeger : (_seciliKategori ?? "DİĞER"), // 1. Kolon
                    'marka': tip == "MARKA" ? yeniDeger : (_seciliMarka ?? ""),             // 2. Kolon
                    'model': tip == "MODEL" ? yeniDeger : (_seciliModel ?? ""),             // 3. Kolon
                    'alt_model': tip == "ALTMODEL" ? yeniDeger : (_seciliAltModel ?? ""),    // 4. Kolon
                    'altmodel': tip == "ALTMODEL" ? yeniDeger : (_seciliAltModel ?? ""),     // 5. Kolon (Yedek)
                    'tarim_firmalari': _seciliFirma ?? "BİLİNMEYEN",                                  // 6. Kolon
                    'durum': 'AKTİF',
                    'is_synced': 0,
                  });
                }

                await _verileriYukle();

                setState(() {
                  if (tip == "KATEGORİ") {
                    _seciliKategori = yeniDeger;
                  } else if (tip == "MARKA") {
                    _seciliMarka = yeniDeger;
                  } else if (tip == "MODEL") {
                    _seciliModel = yeniDeger;
                    _seciliAltModel = null; // Model değişince alt modeli sıfırla
                  } else {
                    _seciliAltModel = yeniDeger;
                  }
                });
                Navigator.pop(context);
              }
            },
            child: Text(guncellemeMi ? "GÜNCELLE" : "KAYDET"),
          ),
        ],
      ),
    );
  }

  Future<void> _alisSistemeKaydet() async {
    if (_seciliFirma == null || _seciliKategori == null || _seciliMarka == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Eksik bilgi var!"), backgroundColor: Colors.red)
      );
      return;
    }

    showDialog(
        context: context,
        barrierDismissible: false,
        builder: (c) => const Center(child: CircularProgressIndicator())
    );

    try {
      double fiyat = double.tryParse(_fiyatController.text.replaceAll(',', '.')) ?? 0.0;
      double adet = double.tryParse(_adetController.text.replaceAll(',', '.')) ?? 1.0;
      double toplamTutar = fiyat * adet;

      String tamUrunAdi = "$_seciliMarka ${_seciliModel ?? ""} ${_seciliAltModel ?? ""}".trim().toUpperCase();
      String subeAdi = widget.seciliSube == 0 ? "TEFENNİ" : "AKSU";

      // 1. ADIM: Stok Verisini Hazırla (ana_stok_id ilk başta boş gider, stokEkle içinde atanır)
      Map<String, dynamic> yeniStok = {
        'kategori': _seciliKategori,
        'marka': _seciliMarka,
        'model': _seciliModel ?? "",
        'alt_model': _seciliAltModel ?? "",
        'adet': adet,
        'fiyat': fiyat,
        'sube': subeAdi,
        'tarih': DateFormat('dd.MM.yyyy').format(_tarih),
        'tarim_firmalari': _seciliFirma,
        'fatura_no': _faturaNoController.text,
        'sektor': "TARIM", // Varsayılan sektör
        'is_synced': 0,
      };

      // 2. ADIM: Yerel Veritabanına Stok Ekle ve Gerçek ID'yi Al
      // stokEkle fonksiyonun artık ana_stok_id atamasını içeride otomatik yapıyor.
      int sqlId = await DatabaseHelper.instance.stokEkle(yeniStok);

      // 3. ADIM: Firma Cari Hareketlerini İşle (PDF ve Ekstre Buradan Besleniyor)
      final firma = _firmaListesi.firstWhere((f) => f['ad'] == _seciliFirma);

      await DatabaseHelper.instance.firmaHareketiEkle({
        'firma_id': firma['id'],
        'stok_id': sqlId,       // Bu malın yereldeki benzersiz ID'si
        'ana_stok_id': sqlId,   // İlk alış olduğu için ana ID de bu
        'tip': "ALIM",
        'urun_adi': tamUrunAdi,
        'tutar': toplamTutar,
        'adet': adet,
        'tarih': DateFormat('dd.MM.yyyy').format(_tarih)
      });

      // 4. ADIM: Bakiyeyi Güncelle
      await DatabaseHelper.instance.firmaBakiyeGuncelle(firma['id'], toplamTutar);

      // 5. ADIM: Firebase Sync (Buluta da ana_stok_id ile gönder)
      try {
        await FirebaseFirestore.instance
            .collection('stoklar')
            .doc(sqlId.toString())
            .set({
          ...yeniStok,
          'id': sqlId,
          'ana_stok_id': sqlId,
          'firebase_id': sqlId.toString(),
          'lastUpdated': FieldValue.serverTimestamp()
        });
        // Firebase senkronize bilgisini yerelde güncelle
        await DatabaseHelper.instance.database.then((db) => db.update(
            'stoklar',
            {'is_synced': 1, 'firebase_id': sqlId.toString()},
            where: 'id = ?',
            whereArgs: [sqlId]
        ));
      } catch (e) {
        debugPrint("⚠️ Bulut senkronizasyon hatası: $e");
      }

      if (mounted) {
        Navigator.pop(context); // Yükleniyor dialogunu kapat
        Navigator.pop(context, true); // Sayfadan çık ve listeyi yenile
      }
    } catch (e) {
      if (mounted) Navigator.pop(context);
      debugPrint("❌ ALIŞ KAYIT HATASI: $e");
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Hata oluştu: $e"), backgroundColor: Colors.red)
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // KRİTİK: Firma listesinde seçili firma var mı kontrolü (Hata önleyici)
    final bool firmaVarMi = _firmaListesi.any((f) => f['ad'].toString() == _seciliFirma);
    final String? guvenliFirma = firmaVarMi ? _seciliFirma : null;

    return Scaffold(
      backgroundColor: Colors.grey[100],
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
          title: const Text("FİRMADAN MAL ALIŞI"),
          backgroundColor: Colors.green[900],
          foregroundColor: Colors.white
      ),
      body: Column(
        children: [
          _ustBanner(),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(15),
              child: Column(
                children: [
                  // FİRMA SEÇİMİ (Güvenli Hale Getirildi)
                  DropdownButtonFormField<String>(
                    value: guvenliFirma, // 🔥 Değişti: _seciliFirma yerine guvenliFirma
                    decoration: const InputDecoration(
                        labelText: "FİRMA SEÇİN",
                        border: OutlineInputBorder(),
                        filled: true,
                        fillColor: Colors.white
                    ),
                    items: _firmaListesi
                        .map((f) => f['ad'].toString())
                        .toSet() // Çift kayıtları engeller
                        .map((ad) => DropdownMenuItem(value: ad, child: Text(ad)))
                        .toList(),
                    onChanged: (v) => setState(() {
                      _seciliFirma = v;
                      _seciliKategori = null;
                      _seciliMarka = null;
                      _seciliModel = null;
                    }),
                  ),
                  const SizedBox(height: 10),

                  // KATEGORİ, MARKA, MODEL, ALTMODEL (Hepsi _tanimSatiri içindeki güvenli mantığı kullanmalı)
                  _tanimSatiri("KATEGORİ", _seciliKategori, (v) => setState(() { _seciliKategori = v; _seciliMarka = null; }), items: _kategoriler),

                  _tanimSatiri("MARKA", _seciliMarka, (v) => setState(() { _seciliMarka = v; _seciliModel = null; }),
                      items: _stokTanimListesi.where((e) => e['kategori'] == _seciliKategori).map((e) => e['marka'].toString()).toSet()),

                  _tanimSatiri("MODEL", _seciliModel, (v) => setState(() { _seciliModel = v; _seciliAltModel = null; }),
                      items: _stokTanimListesi
                          .where((e) => e['kategori'] == _seciliKategori && e['marka'] == _seciliMarka)
                          .map((e) => e['model'].toString())
                          .toSet()),

                  _tanimSatiri(
                    "ALTMODEL",
                    _seciliAltModel,
                        (v) => setState(() { _seciliAltModel = v; }),
                    items: _stokTanimListesi
                        .where((e) =>
                    e['kategori'].toString() == _seciliKategori.toString() &&
                        e['marka'].toString() == _seciliMarka.toString() &&
                        e['model'].toString() == _seciliModel.toString())
                        .map((e) => e['alt_model']?.toString() ?? "")
                        .where((s) => s.isNotEmpty && s != "null")
                        .toSet(),
                  ),

                  const SizedBox(height: 10),
                  Row(children: [
                    Expanded(child: _input("ADET", tip: TextInputType.number, controller: _adetController)),
                    const SizedBox(width: 10),
                    Expanded(child: _input("BİRİM FİYAT", tip: TextInputType.number, controller: _fiyatController)),
                  ]),
                  _input("FATURA / İRSALİYE NO", controller: _faturaNoController),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: _alisSistemeKaydet,
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.green[900], minimumSize: const Size(double.infinity, 55)),
                    child: const Text("EVREN KAYIT EDEBİLİRSİN", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(height: 300),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _ustBanner() => Container(
    padding: const EdgeInsets.all(15),
    color: Colors.green[900],
    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: const [
        Text("EVREN ÖZÇOBAN", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
        Text("0545 521 75 65", style: TextStyle(color: Colors.white70, fontSize: 12)),
      ]),
      const Icon(Icons.agriculture, color: Colors.white, size: 40),
    ]),
  );

  Widget _tanimSatiri(String tip, String? value, Function(String?) onChanged, {required Iterable<String> items}) {
    // Önce listeyi temizleyelim (boş ve null olanları atalım)
    final temizListe = items.where((m) => m.isNotEmpty && m != "null").toList();

    // KRİTİK KONTROL: Seçili değer listede var mı? Yoksa uygulama patlar!
    // Eğer listede yoksa value'yu null yapıyoruz, böylece "Seçin" yazısı çıkar.
    final String? guvenliDeger = temizListe.contains(value) ? value : null;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          // 1. Esnek Alan: Dropdown
          Expanded(
            child: DropdownButtonFormField<String>(
              isExpanded: true,
              value: guvenliDeger, // 🔥 Artık burası güvenli, uygulama çökmez.
              decoration: InputDecoration(
                labelText: "$tip SEÇİN",
                labelStyle: const TextStyle(fontSize: 13),
                border: const OutlineInputBorder(),
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              ),
              items: temizListe
                  .map((m) => DropdownMenuItem(
                value: m,
                child: Text(
                  m,
                  style: const TextStyle(fontSize: 14),
                  overflow: TextOverflow.ellipsis, // Uzun yazıları keser
                ),
              ))
                  .toList(),
              onChanged: onChanged,
            ),
          ),

          // 2. Butonlar (Düzenli ve Sabit)
          const SizedBox(width: 4),
          IconButton(
            constraints: const BoxConstraints(),
            padding: const EdgeInsets.all(4),
            icon: const Icon(Icons.edit, color: Colors.orange, size: 26),
            onPressed: () => _tanimIslemDialog(tip, guncellemeMi: true),
          ),
          IconButton(
            constraints: const BoxConstraints(),
            padding: const EdgeInsets.all(4),
            icon: const Icon(Icons.add_circle, color: Colors.green, size: 26),
            onPressed: () => _tanimIslemDialog(tip),
          ),
        ],
      ),
    );
  }

  Widget _input(String l, {TextInputType tip = TextInputType.text, required TextEditingController controller}) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextField(
      controller: controller,
      keyboardType: tip,
      decoration: InputDecoration(
        labelText: l,
        labelStyle: const TextStyle(fontSize: 13),
        border: const OutlineInputBorder(),
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12), // Textfield içini ferahlattık
      ),
    ),
  );
}