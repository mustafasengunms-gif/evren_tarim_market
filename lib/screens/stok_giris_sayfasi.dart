import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../db/database_helper.dart';
import 'package:cloud_firestore/cloud_firestore.dart';


class DetayliStokGirisSayfasi extends StatefulWidget {
  final int seciliSube;

  const DetayliStokGirisSayfasi({super.key, required this.seciliSube});
  @override
  State<DetayliStokGirisSayfasi> createState() => _DetayliStokGirisSayfasiState();
}

class _DetayliStokGirisSayfasiState extends State<DetayliStokGirisSayfasi> {
  DateTime _tarih = DateTime.now();
  String? _seciliFirma;
  String? _seciliMarka;
  String? _seciliModel;
  String? _seciliAltModel;
  String _seciliDurum = "SIFIR"; // Hata veren yer buydu
  late String _kayitSubesi;
  String _durum = "SIFIR";
  List<Map<String, dynamic>> _firmaListesi = [];
  List<Map<String, dynamic>> _stokTanimListesi = [];
  // Diğer değişkenlerin olduğu yerin hemen altına ekle:
  List<String> _kategoriler = ["RÖMORK", "MİBZER", "PULLUK", "BALYA MAKİNESİ", "TRAKTÖR", "YEM KARMA","CEVİZ SOYMA","HAMUR KARMA","PANCAR KAZMA","DİĞER","EVREN YOKSA + BAS EKLE"];
  String? _seciliKategori; // Hata veren isim buydu, şimdi sisteme tanıttık.
  bool _islemDevamEdiyor = false; // Bunu ekle
  double toplamCiro = 0.0;
  int toplamIslem = 0;


  final TextEditingController _kategoriController = TextEditingController();
  final TextEditingController _markaController = TextEditingController();
  final TextEditingController _altModelController = TextEditingController();
  final TextEditingController _adetController = TextEditingController();
  final TextEditingController _fiyatController = TextEditingController();
  final TextEditingController _faturaNoController = TextEditingController();


  @override
  void initState() {
    super.initState();
    _kayitSubesi = widget.seciliSube == 0 ? "TEFENNİ" : "AKSU";
    _verileriYukle();
  }

  // --- YARDIMCI DROPDOWN METODU (SİGORTA) ---
  List<DropdownMenuItem<String>> _dropdownItemsHazirla(List<String> liste, String? seciliDeger) {
    List<String> temizListe = liste
        .map((e) => e.toString().trim().toUpperCase())
        .where((e) => e.isNotEmpty)
        .toSet()
        .toList();
    if (seciliDeger != null && seciliDeger.isNotEmpty && !temizListe.contains(seciliDeger.toUpperCase())) {
      temizListe.add(seciliDeger.toUpperCase());
    }
    return temizListe.map((e) => DropdownMenuItem<String>(
      value: e,
      child: Text(e, style: const TextStyle(fontSize: 13), overflow: TextOverflow.ellipsis),
    )).toList();
  }

  Future<void> _verileriYukle() async {
    try {
      final snapshot = await FirebaseFirestore.instance.collection('stoklar').get();

      // 🔥 PERFORMANS: Her döküman için tek tek await yerine toplu işlem yapmaya çalış.
      // Şimdilik hata vermemesi için mevcut mantığına şu kontrolü ekleyelim:
      for (var doc in snapshot.docs) {
        final d = doc.data();
        // Burada DatabaseHelper içinde 'INSERT OR IGNORE' kullandığından emin ol
        await DatabaseHelper.instance.stokTanimEkle({
          'id': doc.id,
          'kategori': d['kategori'] ?? "DİĞER",
          'marka': (d['marka'] ?? "").toString().toUpperCase(),
          'model': (d['model'] ?? "").toString().toUpperCase(),
          'alt_model': (d['alt_model'] ?? d['alt'] ?? "").toString().toUpperCase(),
          'firma': d['firma'] ?? d['tarim_firmalari'] ?? "BİLİNMEYEN",
        });
      }

      final gelenFirmalar = await DatabaseHelper.instance.tarimFirmaListesiGetir();
      final gelenTanimlar = await DatabaseHelper.instance.stokTanimlariniGetir();
      final tazeKategoriler = await DatabaseHelper.instance.kategorileriGetirGaranti();

      setState(() {
        _firmaListesi = gelenFirmalar;
        _stokTanimListesi = gelenTanimlar;
        _kategoriler = tazeKategoriler;

        // 🔥 KRİTİK: Eğer kategori listesi geldiyse ve seçili kategori boşsa ilkini seç
        if (_seciliKategori == null && _kategoriler.isNotEmpty) {
          _seciliKategori = _kategoriler.first;
        }
      });
    } catch (e) {
      print("‼️ Hata: $e");
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

                // --- MÜKERRER KONTROLÜ BAŞLANGIÇ ---
                if (!guncellemeMi) {
                  // Mevcut listede aynı firma ve aynı isimde tanım var mı bakıyoruz
                  bool zatenVarMi = _stokTanimListesi.any((e) {
                    bool ayniFirma = e['tarim_firmalari'].toString().toUpperCase() == _seciliFirma?.toUpperCase();
                    bool ayniDeger = false;

                    if (tip == "KATEGORİ") ayniDeger = e['kategori'].toString().toUpperCase() == yeniDeger;
                    else if (tip == "MARKA") ayniDeger = e['marka'].toString().toUpperCase() == yeniDeger;
                    else if (tip == "MODEL") ayniDeger = e['model'].toString().toUpperCase() == yeniDeger;
                    else if (tip == "ALTMODEL") ayniDeger = (e['alt_model'] ?? e['altmodel']).toString().toUpperCase() == yeniDeger;

                    return ayniFirma && ayniDeger;
                  });

                  if (zatenVarMi) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text("BU $tip ZATEN KAYITLI!"), backgroundColor: Colors.red),
                    );
                    return; // Zaten varsa aşağıya geçme, burada durdur.
                  }
                }
                // --- MÜKERRER KONTROLÜ BİTİŞ ---

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
                  // --- "BİLİNMEYEN" SORUNUNU ÇÖZEN GÜVENLİ KAYIT ---
                  await DatabaseHelper.instance.stokTanimEkle({
                    'kategori': tip == "KATEGORİ" ? yeniDeger : (_seciliKategori ?? "DİĞER"),
                    'marka': tip == "MARKA" ? yeniDeger : (_seciliMarka ?? ""),
                    'model': tip == "MODEL" ? yeniDeger : (_seciliModel ?? ""),
                    'alt_model': tip == "ALTMODEL" ? yeniDeger : (_seciliAltModel ?? ""),
                    'altmodel': tip == "ALTMODEL" ? yeniDeger : (_seciliAltModel ?? ""),
                    'tarim_firmalari': _seciliFirma!.toUpperCase().trim(), // ?? "BİLİNMEYEN" kaldırıldı, ünlem eklendi
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
                    _seciliAltModel = null;
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: AppBar(title: const Text("YENİ STOK KAYDI")),
      body: ListView(
        padding: const EdgeInsets.all(15),
        children: [
          // --- ŞUBE SEÇİMİ ---
          Container(
            margin: const EdgeInsets.only(bottom: 15),
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue.shade200)
            ),
            child: Row(children: [
              const Icon(Icons.store, color: Colors.blue),
              const SizedBox(width: 10),
              const Text("KAYIT ŞUBESİ:", style: TextStyle(fontWeight: FontWeight.bold)),
              const Spacer(),
              DropdownButton<String>(
                value: _kayitSubesi,
                underline: Container(),
                items: ["TEFENNİ", "AKSU"].map((s) => DropdownMenuItem(value: s, child: Text(s, style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold)))).toList(),
                onChanged: (v) => setState(() => _kayitSubesi = v!),
              ),
            ]),
          ),

          // --- DURUM SEÇİMİ ---
          Padding(
            padding: const EdgeInsets.only(bottom: 15),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Text("ÜRÜN DURUMU:", style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(width: 15),
              ChoiceChip(label: const Text("SIFIR"), selected: _durum == "SIFIR", onSelected: (val) => setState(() => _durum = "SIFIR")),
              const SizedBox(width: 10),
              ChoiceChip(label: const Text("2. EL"), selected: _durum == "2. EL", onSelected: (val) => setState(() => _durum = "2. EL")),
            ]),
          ),

          // --- 1. BASAMAK: FİRMA SEÇİMİ ---
          Row(children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                isExpanded: true,
                value: _seciliFirma,
                decoration: const InputDecoration(labelText: "1. FİRMA SEÇİN", border: OutlineInputBorder()),
                items: _firmaListesi.map((f) => DropdownMenuItem(value: f['ad'].toString(), child: Text(f['ad'].toString(), overflow: TextOverflow.ellipsis))).toList(),
                onChanged: (v) => setState(() {
                  _seciliFirma = v;
                  _seciliKategori = null; _seciliMarka = null; _seciliModel = null; _seciliAltModel = null;
                }),
              ),
            ),
            IconButton(icon: const Icon(Icons.account_balance_wallet, color: Colors.red), onPressed: () => _seciliFirma != null ? _odemeDialog(_firmaListesi.firstWhere((e) => e['ad'] == _seciliFirma)) : null),
          ]),
          const SizedBox(height: 10),

          // --- 2. BASAMAK: KATEGORİ SEÇİMİ (Soyağacı Başlangıcı) ---
          Row(children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                isExpanded: true,
                value: _seciliKategori,
                decoration: const InputDecoration(labelText: "2. KATEGORİ SEÇİN", border: OutlineInputBorder(), prefixIcon: Icon(Icons.category)),
                items: _kategoriler.map((k) => DropdownMenuItem(value: k, child: Text(k))).toList(),
                onChanged: (v) => setState(() {
                  _seciliKategori = v;
                  _seciliMarka = null; _seciliModel = null; _seciliAltModel = null;
                }),
              ),
            ),
            IconButton(icon: const Icon(Icons.add_circle, color: Colors.green), onPressed: () => _tanimIslemDialog("KATEGORİ")),
          ]),
          const SizedBox(height: 10),

          // --- 3. BASAMAK: MARKA SEÇİMİ (Kategoriye Göre Süzülür) ---
          Row(children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                isExpanded: true,
                value: _seciliMarka,
                decoration: const InputDecoration(labelText: "3. MARKA SEÇİN", border: OutlineInputBorder()),
                items: _dropdownItemsHazirla(
                    _stokTanimListesi
                        .where((e) => e['kategori']?.toString().toUpperCase() == _seciliKategori?.toUpperCase())
                        .map((e) => e['marka'].toString()).toList(),
                    _seciliMarka
                ),
                onChanged: (v) => setState(() {
                  _seciliMarka = v;
                  _seciliModel = null; _seciliAltModel = null;
                }),
              ),
            ),
            IconButton(icon: const Icon(Icons.add_circle, color: Colors.green), onPressed: () => _tanimIslemDialog("MARKA")),
          ]),
          const SizedBox(height: 10),

          // --- 4. BASAMAK: MODEL SEÇİMİ (Kategori ve Markaya Göre Süzülür) ---
          Row(children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                isExpanded: true,
                value: _seciliModel,
                decoration: const InputDecoration(labelText: "4. MODEL SEÇİN", border: OutlineInputBorder()),
                items: _dropdownItemsHazirla(
                    _stokTanimListesi
                        .where((e) =>
                    e['kategori']?.toString().toUpperCase() == _seciliKategori?.toUpperCase() &&
                        e['marka']?.toString().toUpperCase() == _seciliMarka?.toUpperCase()
                    )
                        .map((e) => e['model'].toString()).toList(),
                    _seciliModel
                ),
                onChanged: (v) => setState(() {
                  _seciliModel = v;
                  _seciliAltModel = null;
                }),
              ),
            ),
            IconButton(icon: const Icon(Icons.add_circle, color: Colors.blue), onPressed: () => _tanimIslemDialog("MODEL")),
          ]),
          const SizedBox(height: 10),

          // --- 5. BASAMAK: ALT MODEL SEÇİMİ ---
          Row(children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                isExpanded: true,
                value: _seciliAltModel,
                decoration: const InputDecoration(labelText: "5. ALT MODEL SEÇİN", border: OutlineInputBorder()),
                items: _dropdownItemsHazirla(
                    _stokTanimListesi
                        .where((e) =>
                    e['kategori']?.toString().toUpperCase() == _seciliKategori?.toUpperCase() &&
                        e['marka']?.toString().toUpperCase() == _seciliMarka?.toUpperCase() &&
                        e['model']?.toString().toUpperCase() == _seciliModel?.toUpperCase()
                    )
                        .map((e) => (e['alt_model'] ?? e['altModel'] ?? "").toString())
                        .where((s) => s.isNotEmpty).toSet().toList(),
                    _seciliAltModel
                ),
                onChanged: (v) => setState(() => _seciliAltModel = v),
              ),
            ),
            IconButton(icon: const Icon(Icons.add_circle, color: Colors.blue), onPressed: () => _tanimIslemDialog("ALTMODEL")),
          ]),
          const SizedBox(height: 10),

          // --- MİKTAR VE FİYAT ---
          Row(children: [
            Expanded(child: _input("ADET", tip: TextInputType.number, controller: _adetController)),
            const SizedBox(width: 10),
            Expanded(child: _input("ALIŞ FİYATI", tip: TextInputType.number, controller: _fiyatController)),
          ]),
          const SizedBox(height: 10),

          _input("IRSALİYE / FATURA NO", controller: _faturaNoController),
          ListTile(
            tileColor: Colors.grey[200],
            title: Text("ALIŞ TARİHİ: ${DateFormat('dd.MM.yyyy').format(_tarih)}"),
            trailing: const Icon(Icons.calendar_month),
            onTap: () async {
              DateTime? d = await showDatePicker(context: context, initialDate: _tarih, firstDate: DateTime(2020), lastDate: DateTime(2030));
              if (d != null) setState(() => _tarih = d);
            },
          ),
          const SizedBox(height: 30),

          // --- KAYDET BUTONU ---
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.all(20),
            ),
            onPressed: _islemDevamEdiyor ? null : () async {
              if (_seciliMarka == null || _seciliFirma == null || _adetController.text.isEmpty || _seciliKategori == null) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Lütfen soyağacını tamamlayın!")));
                return;
              }

              setState(() => _islemDevamEdiyor = true);
              showDialog(context: context, barrierDismissible: false, builder: (c) => const Center(child: CircularProgressIndicator()));

              try {
                double fiyat = double.tryParse(_fiyatController.text.replaceAll(',', '.')) ?? 0.0;
                double adet = double.tryParse(_adetController.text.replaceAll(',', '.')) ?? 0.0;
                String altModelV = (_seciliAltModel ?? "").trim().toUpperCase();
                String urunAdi = "$_seciliMarka $_seciliModel $altModelV".trim().toUpperCase();

                Map<String, dynamic> yeniStok = {
                  'marka': _seciliMarka,
                  'model': _seciliModel,
                  'alt_model': altModelV,
                  'urun': urunAdi,
                  'fiyat': fiyat,
                  'adet': adet,
                  'kategori': _seciliKategori,
                  'sube': _kayitSubesi,
                  'durum': _durum,
                  'tarih': DateFormat('dd.MM.yyyy').format(_tarih),
                  'tarim_firmalari': _seciliFirma,
                  'fatura_no': _faturaNoController.text.trim().toUpperCase(),
                  'is_synced': 1,
                };

                // 1. SQL Kaydı
                int localId = await DatabaseHelper.instance.stokEkle(yeniStok);

                // 2. Firebase Kaydı (Tek Tanım Mantığı)
                await FirebaseFirestore.instance
                    .collection('stoklar')
                    .doc(localId.toString())
                    .set({
                  ...yeniStok,
                  'ana_stok_id': localId,
                  'firebase_id': localId.toString(),
                }, SetOptions(merge: true));

                // 3. Firma Ekstresi
                final firma = _firmaListesi.firstWhere((e) => e['ad'] == _seciliFirma);
                await DatabaseHelper.instance.firmaBakiyeGuncelle(firma['id'], (fiyat * adet));
                await DatabaseHelper.instance.firmaHareketiEkle({
                  'firma_id': firma['id'],
                  'tip': "BORC",
                  'urun_adi': "STOK GİRİŞ: $urunAdi",
                  'tutar': fiyat * adet,
                  'adet': adet,
                  'tarih': DateFormat('dd.MM.yyyy').format(_tarih),
                });

                if (mounted) {
                  Navigator.pop(context); // Loading kapat
                  Navigator.pop(context, true); // Sayfayı kapat
                }
              } catch (e) {
                setState(() => _islemDevamEdiyor = false);
                if (mounted) Navigator.pop(context);
                print("❌ HATA: $e");
              }
            },
            child: Text(_islemDevamEdiyor ? "KAYDEDİLİYOR..." : "EVREN SİSTEME KAYDET"),
          )
        ],
      ),
    );
  }

  // --- BURADAN AŞAĞISI SINIFIN İÇİNDE KALMALI ---
  Widget _input(String l, {TextInputType tip = TextInputType.text, required TextEditingController controller}) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: TextField(
      controller: controller,
      keyboardType: tip,
      onChanged: (v) => setState(() {}),
      decoration: InputDecoration(labelText: l, border: const OutlineInputBorder()),
    ),
  );

  void _odemeDialog(Map<String, dynamic> f) {
    final tutarC = TextEditingController();
    final tarihC = TextEditingController(text: DateFormat('dd.MM.yyyy').format(DateTime.now()));
    String kanal = "NAKİT";
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setS) => AlertDialog(
          title: Text("ÖDEME YAP: ${f['ad']}"),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            _input("Tutar (₺)", tip: TextInputType.number, controller: tutarC),
            _input("Tarih", controller: tarihC),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              value: kanal,
              decoration: const InputDecoration(labelText: "Ödeme Kanalı", border: OutlineInputBorder()),
              items: ["NAKİT", "EFT/HAVALE", "ÇEK", "SENET", "AÇIK HESAP"].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
              onChanged: (v) => setS(() => kanal = v!),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text("İPTAL")),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red[900], foregroundColor: Colors.white),
              onPressed: () async {
                double m = double.tryParse(tutarC.text.replaceAll(',', '.')) ?? 0;
                if (m > 0) {
                  await DatabaseHelper.instance.firmaHareketiEkle({'tarim_firmalari': f['id'], 'tip': "ÖDEME", 'urun_adi': "$kanal ÖDEMESİ", 'tutar': m, 'tarih': tarihC.text});
                  await DatabaseHelper.instance.firmaBakiyeGuncelle(f['id'], -m);
                  Navigator.pop(context); _verileriYukle();
                }
              },
              child: const Text("KAYDET"),
            ),
          ],
        ),
      ),
    );
  }

  void _firmaGuncelleDialog(Map<String, dynamic> f) {
    final adC = TextEditingController(text: f['ad']);
    final yetkiliC = TextEditingController(text: f['yetkili']);
    final telC = TextEditingController(text: f['tel']);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("FİRMA BİLGİSİNİ DÜZENLE"),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          _input("Firma Ünvanı", controller: adC),
          _input("Yetkili Kişi", controller: yetkiliC),
          _input("Telefon", controller: telC, tip: TextInputType.phone),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("VAZGEÇ")),
          ElevatedButton(
            onPressed: () async {
              Map<String, dynamic> v = {'ad': adC.text.toUpperCase(), 'yetkili': yetkiliC.text, 'tel': telC.text};
              await DatabaseHelper.instance.firmaGuncelle(f['id'], v);
              Navigator.pop(context); _verileriYukle(); setState(() => _seciliFirma = v['ad']);
            },
            child: const Text("GÜNCELLE"),
          ),
        ],
      ),
    );
  }
} // SINIF BURADA BİTTİ