import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../db/database_helper.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'stok_tanimla_sayfasi.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

class DetayliStokGirisSayfasi extends StatefulWidget {
  final int seciliSube;

  const DetayliStokGirisSayfasi({super.key, required this.seciliSube});
  @override
  State<DetayliStokGirisSayfasi> createState() => _DetayliStokGirisSayfasiState();
}

class _DetayliStokGirisSayfasiState extends State<DetayliStokGirisSayfasi> {
  DateTime _tarih = DateTime.now();
  String? _seciliFirma; // Senin istediğin gibi sadece isim tutuyor
  String? _seciliMarka;
  String? _seciliModel;
  String? _seciliAltModel;
  late String _kayitSubesi;
  String _durum = "SIFIR";
  List<Map<String, dynamic>> _firmaListesi = [];
  List<Map<String, dynamic>> _stokTanimListesi = [];
  List<String> _kategoriler = ["RÖMORK", "MİBZER", "PULLUK", "BALYA MAKİNESİ", "TRAKTÖR", "YEM KARMA","CEVİZ SOYMA","HAMUR KARMA","PANCAR KAZMA","DİĞER","EVREN YOKSA + BAS EKLE"];
  String? _seciliKategori;
  bool _islemDevamEdiyor = false;

  final TextEditingController _adetController = TextEditingController();
  final TextEditingController _fiyatController = TextEditingController();
  final TextEditingController _faturaNoController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _kayitSubesi = widget.seciliSube == 0 ? "TEFENNİ" : "AKSU";
    _verileriYukle();
  }

  // --- YARDIMCI DROPDOWN METODU (HAYALET SAVAR) ---
  List<DropdownMenuItem<String>> _dropdownItemsHazirla(List<String> liste, String? seciliDeger) {
    List<String> temizListe = liste
        .map((e) => e.toString().trim().toUpperCase()) // Hepsini büyük harf yap ve boşlukları at
        .where((e) {
      // --- KRİTİK FİLTRELEME BURASI ---
      // 1. Tamamen boş değilse
      // 2. "NULL" kelimesine eşit değilse
      // 3. Sadece mühür ayracı olan "|" karakterinden ibaret değilse
      // 4. Uzunluğu en az 1 karakter ise (garanti olsun)
      return e.isNotEmpty &&
          e != "NULL" &&
          e != "|" &&
          e != "||" &&
          e.length > 0;
    })
        .toSet() // Aynı isimli verileri teke düşür (Mükerrer mühürü engeller)
        .toList();

    // Eğer seçili bir değer varsa ama listede yoksa (yeni eklendiyse), onu da listeye dahil et
    if (seciliDeger != null &&
        seciliDeger.isNotEmpty &&
        !temizListe.contains(seciliDeger.toUpperCase())) {
      temizListe.add(seciliDeger.toUpperCase());
    }

    // Alfabetik sırala ki kullanıcı aradığını bulabilsin
    temizListe.sort();

    return temizListe.map((e) => DropdownMenuItem<String>(
      value: e,
      child: Text(
          e,
          style: const TextStyle(fontSize: 13),
          overflow: TextOverflow.ellipsis
      ),
    )).toList();
  }

  Future<void> _verileriYukle() async {
    if (_islemDevamEdiyor) return;
    setState(() => _islemDevamEdiyor = true);

    try {
      final dbHelper = DatabaseHelper.instance;
      List<Map<String, dynamic>> gelenFirmalar = [];
      List<Map<String, dynamic>> gelenTanimlar = [];
      List<String> tazeKategoriler = _kategoriler;

      if (kIsWeb) {
        // 🌐 WEB: Direkt Firebase'den taze çek
        final snapStok = await FirebaseFirestore.instance.collection('stok_tanimlari').get();
        final snapFirma = await FirebaseFirestore.instance.collection('tarim_firmalari').get();

        gelenFirmalar = snapFirma.docs.map((doc) => {
          ...doc.data(),
          'id': doc.id,
          'cari_kod': (doc.data()['cari_kod'] ?? doc.id).toString().toUpperCase(),
          'ad': (doc.data()['ad'] ?? "BİLİNMEYEN").toString().toUpperCase(),
        }).toList();

        gelenTanimlar = snapStok.docs.map((doc) => {
          ...doc.data(),
          'id': doc.id,
          'marka': (doc.data()['marka'] ?? "").toString().toUpperCase(),
          'model': (doc.data()['model'] ?? "").toString().toUpperCase(),
        }).toList();
      } else {
        // 📱 MOBİL: Önce yerelde ne varsa onu çek (Kullanıcıyı bekletme)
        gelenFirmalar = await dbHelper.tarimFirmaListesiGetir();
        gelenTanimlar = await dbHelper.stokTanimlariniGetir();
        tazeKategoriler = await dbHelper.kategorileriGetirGaranti();

        // Yerel veriyi hemen göster
        if (mounted) {
          setState(() {
            _firmaListesi = gelenFirmalar;
            _stokTanimListesi = gelenTanimlar;
            _kategoriler = tazeKategoriler;
          });
        }

        // ARKA PLANDA: Firebase'den taze çek ve SQLite'ı sessizce güncelle
        // snapshot'ı 'stoklar' yerine 'stok_tanimlari' olarak kontrol et (Koleksiyon ismin hangisiyse)
        final snapshot = await FirebaseFirestore.instance.collection('stok_tanimlari').get();

        // Batch mantığıyla yazıyoruz ki 'hayalet' oluşmasın
        for (var doc in snapshot.docs) {
          final d = doc.data();
          await dbHelper.stokTanimEkle({
            'firebase_id': doc.id, // Mühür: Eğer bu ID varsa üstüne yazar (Replace)
            'kategori': (d['kategori'] ?? "DİĞER").toString().toUpperCase(),
            'marka': (d['marka'] ?? "").toString().toUpperCase(),
            'model': (d['model'] ?? "").toString().toUpperCase(),
            'alt_model': (d['alt_model'] ?? d['alt'] ?? "").toString().toUpperCase(),
            'tarim_firmalari': (d['tarim_firmalari'] ?? d['firma'] ?? "").toString().toUpperCase(),
            'is_synced': 1, // Buluttan geldiği için onaylıdır
          });
        }

        // Güncel listeyi tekrar çek
        gelenFirmalar = await dbHelper.tarimFirmaListesiGetir();
        gelenTanimlar = await dbHelper.stokTanimlariniGetir();
      }

      // 2. Arayüzü Son Kez Güncelle
      if (mounted) {
        setState(() {
          _firmaListesi = gelenFirmalar;
          _stokTanimListesi = gelenTanimlar;
          if (tazeKategoriler.isNotEmpty) _kategoriler = tazeKategoriler;
          if (_seciliKategori == null && _kategoriler.isNotEmpty) {
            _seciliKategori = _kategoriler.contains("TRAKTÖR") ? "TRAKTÖR" : _kategoriler.first;
          }
        });
      }
    } catch (e) {
      debugPrint("‼️ Kritik Hata: $e");
    } finally {
      if (mounted) setState(() => _islemDevamEdiyor = false);
    }
  }

  Future<void> _tanimIslemDialog(String tip, {bool guncellemeMi = false}) async {
    if (_seciliFirma == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("ÖNCE FİRMA SEÇİN!")));
      return;
    }

    // onPressed içindeki veri hazırlığı kısmını şöyle düzelt:
    final seciliFirmaVerisi = _firmaListesi.firstWhere(
          (e) => e['ad'].toString() == _seciliFirma,
      orElse: () => {},
    );
    String cKod = seciliFirmaVerisi['cari_kod']?.toString() ?? _seciliFirma!;


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
              // 1. ADIM: Boş kontrolü
              if (_islemController.text.isEmpty) return;

              // 2. ADIM: Değişkenleri ve Mühürleri Hazırla
              String yeniDeger = _islemController.text.toUpperCase().trim();

              // --- FİRMA MÜHÜRÜ (Cari Kod) ---
              final seciliFirmaVerisi = _firmaListesi.firstWhere(
                    (e) => e['ad'].toString().toUpperCase() == _seciliFirma?.toUpperCase(),
                orElse: () => {},
              );
              String fMuhur = (seciliFirmaVerisi['cari_kod'] ?? _seciliFirma ?? "BELIRSIZ").toString();

              // --- MEVCUT SEÇİMLERİ KORU ---
              // Tipine göre yeni değeri yerleştir, diğerlerini mevcut seçimlerden al
              String kat = tip == "KATEGORİ" ? yeniDeger : (_seciliKategori ?? "DİĞER");
              String mar = tip == "MARKA" ? yeniDeger : (_seciliMarka ?? "");
              String mod = tip == "MODEL" ? yeniDeger : (_seciliModel ?? "");
              String alt = tip == "ALTMODEL" ? yeniDeger : (_seciliAltModel ?? "");

              // 3. ADIM: Mükerrer Kontrolü (Daha Sağlam)
              if (!guncellemeMi) {
                bool zatenVarMi = _stokTanimListesi.any((e) {
                  bool ayniFirma = e['tarim_firmalari'].toString().toUpperCase() == fMuhur.toUpperCase();
                  bool ayniKategori = e['kategori'].toString().toUpperCase() == kat.toUpperCase();
                  bool ayniMarka = e['marka'].toString().toUpperCase() == mar.toUpperCase();
                  bool ayniModel = e['model'].toString().toUpperCase() == mod.toUpperCase();
                  bool ayniAlt = (e['alt_model'] ?? e['altmodel'] ?? "").toString().toUpperCase() == alt.toUpperCase();

                  return ayniFirma && ayniKategori && ayniMarka && ayniModel && ayniAlt;
                });

                if (zatenVarMi) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text("BU $tip KOMBİNASYONU ZATEN KAYITLI!"), backgroundColor: Colors.red),
                  );
                  return;
                }
              }

              // 4. ADIM: Veritabanı Kayıt/Güncelleme
              try {
                if (guncellemeMi) {
                  // Eski değer mühürleme için lazım
                  String eskiDeger = "";
                  if (tip == "KATEGORİ") eskiDeger = _seciliKategori ?? "";
                  else if (tip == "MARKA") eskiDeger = _seciliMarka ?? "";
                  else if (tip == "MODEL") eskiDeger = _seciliModel ?? "";
                  else if (tip == "ALTMODEL") eskiDeger = _seciliAltModel ?? "";

                  await DatabaseHelper.instance.stokTanimGuncelle(
                      fMuhur,
                      tip == "MARKA" ? eskiDeger : (_seciliMarka ?? ""),
                      tip == "MODEL" ? eskiDeger : (_seciliModel ?? ""),
                      eskiDeger,
                      yeniDeger,
                      tip
                  );
                } else {
                  // YENİ EKLEME: Mühürü tam çakıyoruz
                  // Boşlukları alt tire yapalım ki Firebase linklerde patlamasın
                  String fullMuhur = "SK-${fMuhur}|${kat}|${mar}|${mod}|${alt}".toUpperCase().replaceAll(' ', '_');

                  await DatabaseHelper.instance.stokTanimEkle({
                    'firebase_id': fullMuhur,
                    'stok_kodu': fullMuhur,
                    'kategori': kat,
                    'marka': mar,
                    'model': mod,
                    'alt_model': alt,
                    'tarim_firmalari': fMuhur, // FIRMA BURADA (Cari Kod)
                    'durum': _durum,           // "AKTİF" YAZAN YERİ DEĞİŞKEN YAPTIK (SIFIR/2.EL)
                    'sube': _kayitSubesi,      // EKSİK OLAN ŞUBE BURADA (TEFENNİ/AKSU)
                    'is_synced': 0,
                    'son_guncelleme': DateTime.now().toIso8601String(),
                  });
                }

                // 5. ADIM: Arayüzü tazele ve seçimi otomatize et
                await _verileriYukle();

                setState(() {
                  if (tip == "KATEGORİ") _seciliKategori = yeniDeger;
                  else if (tip == "MARKA") { _seciliMarka = yeniDeger; _seciliModel = null; _seciliAltModel = null; }
                  else if (tip == "MODEL") { _seciliModel = yeniDeger; _seciliAltModel = null; }
                  else if (tip == "ALTMODEL") _seciliAltModel = yeniDeger;
                });

                Navigator.pop(context);
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text("Veritabanı Hatası: $e"), backgroundColor: Colors.red),
                );
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
      appBar: AppBar(title: const Text("YENİ STOK KAYDI")),
      body: ListView(
        padding: const EdgeInsets.all(15),
        children: [
          _subeVeDurumSecimi(),
          const SizedBox(height: 10),

          // --- 1. BASAMAK: FİRMA SEÇİMİ (İSİM GELİYOR) ---
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

          _kategoriMarkaModelInputlari(),

          Row(children: [
            Expanded(child: _input("ADET", tip: TextInputType.number, controller: _adetController)),
            const SizedBox(width: 10),
            Expanded(child: _input("ALIŞ FİYATI", tip: TextInputType.number, controller: _fiyatController)),
          ]),
          const SizedBox(height: 10),
          _input("IRSALİYE / FATURA NO", controller: _faturaNoController),

          _tarihSecimi(),
          const SizedBox(height: 30),

          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.all(20),
            ),
            onPressed: _islemDevamEdiyor ? null : () async {
              if (_seciliFirma == null || _seciliMarka == null || _adetController.text.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("EKSİK BİLGİ!")));
                return;
              }

              // 1. FİRMA VE ZAMAN BİLGİSİNİ AL
              final seciliFirmaVerisi = _firmaListesi.firstWhere(
                    (e) => e['ad'].toString().toUpperCase() == _seciliFirma?.toUpperCase(),
                orElse: () => {},
              );
              String cKod = (seciliFirmaVerisi['cari_kod'] ?? _seciliFirma!).toString();

              // 🚩 HER KAYIT İÇİN EŞSİZ BİR KİMLİK (MÜHÜR) OLUŞTUR
              // Milisaniye kullanarak her basışta farklı bir ID garanti edilir.
              String benzersizId = "STK-${DateTime.now().millisecondsSinceEpoch}";

              setState(() => _islemDevamEdiyor = true);

              try {
                // Sayısal verileri hazırla
                double adet = double.tryParse(_adetController.text.replaceAll(',', '.')) ?? 0.0;
                double fiyat = double.tryParse(_fiyatController.text.replaceAll(',', '.')) ?? 0.0;

                // 2. VERİTABANINA PAKETİ GÖNDER
                await DatabaseHelper.instance.stokHareketiIsle(
                  firma: {
                    'cari_kod': cKod,
                    'ad': _seciliFirma,
                  },
                  stok: {
                    'stok_kodu': benzersizId, // 🚩 ARTIK BURASI HEP YENİ
                    'urun': "$_seciliMarka $_seciliModel ${_seciliAltModel ?? ""}".toUpperCase().trim(),
                    'marka': _seciliMarka,
                    'model': _seciliModel,
                    'alt_model': _seciliAltModel,
                    'kategori': _seciliKategori,
                    'sube': _kayitSubesi,
                    'durum': _durum,
                    'fatura_no': _faturaNoController.text.toUpperCase(),
                    'fiyat': fiyat, // SQL tablandaki 'fiyat' sütunu için
                    'firebase_id': benzersizId,
                    'tarih': DateFormat('dd.MM.yyyy').format(DateTime.now()),
                  },
                  adet: adet,
                  birimFiyat: fiyat,
                  islemTipi: 'ALIM',
                );

                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("YENİ STOK GİRİŞİ YAPILDI ✅")));
                  Navigator.pop(context, true);
                }
              } catch (e) {
                debugPrint("‼️ Kayıt Hatası: $e");
              } finally {
                if (mounted) setState(() => _islemDevamEdiyor = false);
              }
            },
            child: Text(_islemDevamEdiyor ? "İŞLENİYOR..." : "EVREN SİSTEME KAYDET"),
          )
        ],
      ),
    );
  }

  // --- YARDIMCI WIDGETLAR ---
  Widget _subeVeDurumSecimi() => Column(children: [
    Container(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(color: Colors.blue[50], borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.blue.shade200)),
      child: Row(children: [
        const Icon(Icons.store, color: Colors.blue),
        const SizedBox(width: 10),
        const Text("ŞUBE:", style: TextStyle(fontWeight: FontWeight.bold)),
        const Spacer(),
        DropdownButton<String>(value: _kayitSubesi, underline: Container(), items: ["TEFENNİ", "AKSU"].map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(), onChanged: (v) => setState(() => _kayitSubesi = v!)),
      ]),
    ),
    const SizedBox(height: 10),
    Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      ChoiceChip(label: const Text("SIFIR"), selected: _durum == "SIFIR", onSelected: (val) => setState(() => _durum = "SIFIR")),
      const SizedBox(width: 10),
      ChoiceChip(label: const Text("2. EL"), selected: _durum == "2. EL", onSelected: (val) => setState(() => _durum = "2. EL")),
    ]),
  ]);

  Widget _kategoriMarkaModelInputlari() => Column(children: [
    Row(children: [
      Expanded(child: DropdownButtonFormField<String>(isExpanded: true, value: _seciliKategori, decoration: const InputDecoration(labelText: "2. KATEGORİ"), items: _kategoriler.map((k) => DropdownMenuItem(value: k, child: Text(k))).toList(), onChanged: (v) => setState(() { _seciliKategori = v; _seciliMarka = null; }))),
      IconButton(icon: const Icon(Icons.add_circle, color: Colors.green), onPressed: () => _tanimIslemDialog("KATEGORİ")),
    ]),
    const SizedBox(height: 10),
    Row(children: [
      Expanded(child: DropdownButtonFormField<String>(isExpanded: true, value: _seciliMarka, decoration: const InputDecoration(labelText: "3. MARKA"), items: _dropdownItemsHazirla(_stokTanimListesi.where((e) => e['kategori']?.toString().toUpperCase() == _seciliKategori?.toUpperCase()).map((e) => e['marka'].toString()).toList(), _seciliMarka), onChanged: (v) => setState(() { _seciliMarka = v; _seciliModel = null; }))),
      IconButton(icon: const Icon(Icons.add_circle, color: Colors.green), onPressed: () => _tanimIslemDialog("MARKA")),
    ]),
    const SizedBox(height: 10),
    Row(children: [
      Expanded(child: DropdownButtonFormField<String>(isExpanded: true, value: _seciliModel, decoration: const InputDecoration(labelText: "4. MODEL"), items: _dropdownItemsHazirla(_stokTanimListesi.where((e) => e['kategori']?.toString().toUpperCase() == _seciliKategori?.toUpperCase() && e['marka']?.toString().toUpperCase() == _seciliMarka?.toUpperCase()).map((e) => e['model'].toString()).toList(), _seciliModel), onChanged: (v) => setState(() { _seciliModel = v; _seciliAltModel = null; }))),
      IconButton(icon: const Icon(Icons.add_circle, color: Colors.blue), onPressed: () => _tanimIslemDialog("MODEL")),
    ]),
    const SizedBox(height: 10),
    // _kategoriMarkaModelInputlari içindeki Column'un en altına (Model Row'undan sonra) ekleyin:

    // _kategoriMarkaModelInputlari içindeki Alt Model kısmı:
    Row(children: [
      Expanded(
          child: DropdownButtonFormField<String>(
            isExpanded: true,
            value: _seciliAltModel,
            decoration: const InputDecoration(labelText: "5. ALT MODEL (OPSİYONEL)"),
            items: _dropdownItemsHazirla(
                _stokTanimListesi
                    .where((e) =>
                e['kategori']?.toString().toUpperCase() == _seciliKategori?.toUpperCase() &&
                    e['marka']?.toString().toUpperCase() == _seciliMarka?.toUpperCase() &&
                    e['model']?.toString().toUpperCase() == _seciliModel?.toUpperCase())
                    .map((e) {
                  // Mühür karmaşasını burada çöz: alt_model yoksa altmodel'e bak
                  var val = e['alt_model'] ?? e['altmodel'] ?? "";
                  return val.toString().trim().toUpperCase();
                })
                // Sadece içi dolu olan gerçek modelleri listeye al (Hayaletleri engeller)
                    .where((val) => val.isNotEmpty && val != "NULL")
                    .toList(),
                _seciliAltModel
            ),
            onChanged: (v) => setState(() => _seciliAltModel = v),
          )
      ),
      IconButton(
          icon: const Icon(Icons.add_circle, color: Colors.orange),
          onPressed: () => _tanimIslemDialog("ALTMODEL")
      ),
    ]),
  ]);

  Widget _input(String l, {TextInputType tip = TextInputType.text, required TextEditingController controller}) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: TextField(controller: controller, keyboardType: tip, decoration: InputDecoration(labelText: l, border: const OutlineInputBorder()), onChanged: (v) => setState(() {})),
  );

  Widget _tarihSecimi() => ListTile(
    tileColor: Colors.grey[200],
    title: Text("TARİH: ${DateFormat('dd.MM.yyyy').format(_tarih)}"),
    trailing: const Icon(Icons.calendar_month),
    onTap: () async {
      DateTime? d = await showDatePicker(context: context, initialDate: _tarih, firstDate: DateTime(2020), lastDate: DateTime(2030));
      if (d != null) setState(() => _tarih = d);
    },
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
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red[900],
                  foregroundColor: Colors.white
              ),
              onPressed: () async {
                // 1. Tutari Hazirla
                double m = double.tryParse(tutarC.text.replaceAll(',', '.')) ?? 0;

                if (m > 0) {
                  // 2. MUHURLEME: Sayisal ID yerine Cari Kod aliyoruz
                  // f['cari_kod'] yoksa sistemin cokmemesi icin bosluk kontrolu
                  String muhur = f['cari_kod']?.toString() ?? "";

                  if (muhur.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text("Hata: Firmanin Cari Kodu (Muhuru) bulunamadi!"))
                    );
                    return;
                  }

                  // 3. HAREKET EKLE (Cari kod ile)
                  // 'tarim_firmalari' anahtarini 'cari_kod' olarak guncelledik
                  await DatabaseHelper.instance.tarimfirmaHareketiEkle({
                    'cari_kod': muhur,
                    'tip': "ODEME", // 'Ö' harfini sildik, hata vermez
                    'urun_adi': "${kanal.toUpperCase()} ODEMESI", // Karakter hatasi temizlendi
                    'tutar': m,
                    'tarih': tarihC.text
                  });

                  // 4. BAKIYE GUNCELLE (Cari kod ile)
                  // Tip olarak "ODEME" gonderiyoruz ki sistem miktari eksiye cevirsin
                  await DatabaseHelper.instance.tarimfirmaBakiyeGuncelle(muhur, m, tip: "ODEME");

                  if (mounted) {
                    Navigator.pop(context);
                    _verileriYukle();
                    ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text("Odeme basariyla muhurlendi ve kaydedildi ✅"))
                    );
                  }
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
              // 1. Veriyi hazırla
              Map<String, dynamic> v = {
                'ad': adC.text.toUpperCase().trim(),
                'yetkili': yetkiliC.text.trim(),
                'tel': telC.text.trim()
              };

              // 2. Güncelleme işlemini yap (ID ve Cari Kod beraber gitse daha iyi)
              // f['cari_kod'] verisini de gönderiyoruz ki Firebase'de nokta atışı yapsın
              await DatabaseHelper.instance.firmaGuncelle(f['id'], v, cariKod: f['cari_kod']);

              // 3. Arayüzü tazele
              if (mounted) {
                Navigator.pop(context);
                _verileriYukle();
                setState(() => _seciliFirma = v['ad']);
              }
            },
            child: const Text("GÜNCELLE"),
          ),
        ],
      ),
    );
  }
} // SINIF BURADA BİTTİ