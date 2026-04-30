import 'package:flutter/material.dart';
import '../db/database_helper.dart';


class StokTanimlaSayfasi extends StatefulWidget {
  final List<Map<String, dynamic>> mevcutFirmalar;
  final List<Map<String, dynamic>> tanimliStoklar;
  final Function(Map<String, dynamic>) onKaydet;

  const StokTanimlaSayfasi({
    super.key,
    required this.mevcutFirmalar,
    required this.tanimliStoklar,
    required this.onKaydet,
  });

  @override
  State<StokTanimlaSayfasi> createState() => _StokTanimlaSayfasiState();
}

class _StokTanimlaSayfasiState extends State<StokTanimlaSayfasi> {
  // --- FORM DEĞİŞKENLERİ ---
  int? guncellenecekId;
  String? seciliFirma, seciliMarka, seciliModel, seciliKategori;
  String seciliDurum = "SIFIR";
  final TextEditingController altModelC = TextEditingController();

  // --- LİSTE VE FİLTRE DEĞİŞKENLERİ ---
  final TextEditingController aramaC = TextEditingController();
  List<Map<String, dynamic>> _sqlTanimliStoklar = [];
  List<Map<String, dynamic>> _filtreliListe = [];

  List<String> _kategoriler = [];
  List<String> _ekstraMarkalar = [];
  List<String> _ekstraModeller = [];

  @override
  void initState() {
    super.initState();
    _verileriSqlDenYukle();
  }

  Future<void> _verileriSqlDenYukle() async {
    // Veritabanındaki tüm tanımları ve kategorileri alıyoruz
    final veriler = await DatabaseHelper.instance.stokTanimlariniGetir();
    final tazeKategoriler = await DatabaseHelper.instance.kategorileriGetirGaranti();

    if (mounted) {
      setState(() {
        _sqlTanimliStoklar = veriler;
        _filtreliListe = veriler;
        // Kategorileri de büyük harf yaparak standartlaştırıyoruz
        _kategoriler = tazeKategoriler.map((e) => e.toString().toUpperCase()).toList();
      });
    }
  }

// 1. MARKA LİSTESİ: Sadece seçili KATEGORİYE ait markaları getirir
  List<String> get _markaListesi {
    if (seciliKategori == null) return [];

    List<String> liste = _sqlTanimliStoklar
        .where((s) {
      // Kategori eşleşmesi kontrolü
      return s['kategori'].toString().toUpperCase() == seciliKategori!.toUpperCase();
    })
        .map((s) => s['marka'].toString().toUpperCase())
        .where((m) => m.isNotEmpty)
        .toList();

    liste.addAll(_ekstraMarkalar);
    return liste.toSet().toList(); // Mükerrerleri siler
  }

// 2. MODEL LİSTESİ: Seçili KATEGORİ VE MARKAYA ait modelleri getirir
  List<String> get _modelListesi {
    if (seciliKategori == null || seciliMarka == null) return [];

    List<String> liste = _sqlTanimliStoklar
        .where((s) {
      // Hem kategori hem marka eşleşmesi şart
      bool katMatch = s['kategori'].toString().toUpperCase() == seciliKategori!.toUpperCase();
      bool markaMatch = s['marka'].toString().toUpperCase() == seciliMarka!.toUpperCase();
      return katMatch && markaMatch;
    })
        .map((s) => s['model'].toString().toUpperCase())
        .where((m) => m.isNotEmpty)
        .toList();

    liste.addAll(_ekstraModeller);
    return liste.toSet().toList();
  }


  void _listeyiFiltrele(String s) {
    setState(() {
      _filtreliListe = _sqlTanimliStoklar.where((i) {
        final txt = s.toUpperCase();
        return i['marka'].toString().toUpperCase().contains(txt) ||
            i['model'].toString().toUpperCase().contains(txt) ||
            i['kategori'].toString().toUpperCase().contains(txt);
      }).toList();
    });
  }

  Future<void> _kaydetVeyaGuncelle() async {
    if (seciliFirma == null || seciliMarka == null || seciliModel == null || seciliKategori == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Lütfen tüm alanları doldurun!")));
      return;
    }

    // --- BURASI KRİTİK: İKİ ALANI DA DOLDURUYORUZ ---
    Map<String, dynamic> veri = {
      "firma": seciliFirma!.trim().toUpperCase(),
      "tarim_firmalari": seciliFirma!.trim().toUpperCase(), // Garantiye alıyoruz
      "marka": seciliMarka!.trim().toUpperCase(),
      "model": seciliModel!.trim().toUpperCase(),
      "kategori": seciliKategori!.trim().toUpperCase(),
      "durum": seciliDurum,
      "alt_model": altModelC.text.toUpperCase().trim(),
      "is_synced": 0, // Senkronizasyon için önemli
    };

    try {
      if (guncellenecekId != null) {
        await DatabaseHelper.instance.stokTanimGuncelleById(guncellenecekId!, veri);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Güncellendi ✅")));
      } else {
        await DatabaseHelper.instance.stokTanimEkle(veri);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Kütüphaneye Eklendi ✅")));
      }
      _formuTemizle();
      _verileriSqlDenYukle();
    } catch (e) {
      print("Hata: $e");
    }
  }

  void _formuTemizle() {
    setState(() {
      guncellenecekId = null;
      seciliFirma = null; seciliMarka = null; seciliModel = null; seciliKategori = null;
      seciliDurum = "SIFIR";
      altModelC.clear();
      _ekstraMarkalar.clear();
      _ekstraModeller.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[200],
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        title: const Text("STOK ÖZELLİKLERİNİ GİR EVREN"),
        backgroundColor: Colors.purple[800],
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          _buildFormCard(),
          _buildSearchField(),
          _buildResultList(),
        ],
      ),
    );
  }

  // --- UI BİLEŞENLERİ (Parçalanmış) ---

  Widget _buildFormCard() {
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        child: Container(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.55),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildDurumSecimi(),
                const Divider(),
                _buildFormRow(
                  icon: Icons.category,
                  hint: "Kategori Seç",
                  value: seciliKategori,
                  items: _kategoriler,
                  onChanged: (v) => setState(() => seciliKategori = v),
                  onAdd: () => _yeniEkleDialog("YENİ KATEGORİ", (y) => setState(() { if (!_kategoriler.contains(y)) _kategoriler.add(y); seciliKategori = y; })),
                ),
                _buildFormRow(
                  icon: Icons.business,
                  hint: "Firma Seç",
                  value: seciliFirma,
                  items: widget.mevcutFirmalar.map((f) => f['ad'].toString()).toSet().toList(),
                  onChanged: (v) => setState(() { seciliFirma = v; seciliMarka = null; seciliModel = null; }),
                ),
                Row(
                  children: [
                    Expanded(child: _buildFormRow(
                      icon: Icons.branding_watermark,
                      hint: "Marka",
                      value: seciliMarka,
                      items: _markaListesi,
                      onChanged: (v) => setState(() { seciliMarka = v; seciliModel = null; }),
                      onAdd: () => _yeniEkleDialog("YENİ MARKA", (y) { setState(() { _ekstraMarkalar.add(y); seciliMarka = y; seciliModel = null; }); }),
                    )),
                    Expanded(child: _buildFormRow(
                      icon: Icons.settings,
                      hint: "Model",
                      value: seciliModel,
                      items: _modelListesi,
                      onChanged: (v) => setState(() => seciliModel = v),
                      onAdd: () => _yeniEkleDialog("YENİ MODEL", (y) { setState(() { _ekstraModeller.add(y); seciliModel = y; }); }),
                    )),
                  ],
                ),
                TextField(
                  controller: altModelC,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(hintText: "Alt Model / Özellik", icon: Icon(Icons.account_tree, size: 20)),
                ),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: guncellenecekId != null ? Colors.blue : Colors.purple[800],
                      foregroundColor: Colors.white,
                      minimumSize: const Size(double.infinity, 45)
                  ),
                  onPressed: _kaydetVeyaGuncelle,
                  icon: Icon(guncellenecekId != null ? Icons.edit : Icons.save),
                  label: Text(guncellenecekId != null ? "KAYDI GÜNCELLE" : "KÜTÜPHANEYE KAYDET"),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDurumSecimi() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Text("DURUM: ", style: TextStyle(fontWeight: FontWeight.bold)),
        ChoiceChip(
          label: const Text("SIFIR"),
          selected: seciliDurum == "SIFIR",
          onSelected: (_) => setState(() => seciliDurum = "SIFIR"),
        ),
        const SizedBox(width: 10),
        ChoiceChip(
          label: const Text("2. EL"),
          selected: seciliDurum == "2. EL",
          onSelected: (_) => setState(() => seciliDurum = "2. EL"),
        ),
        if (guncellenecekId != null)
          IconButton(
            onPressed: _formuTemizle,
            icon: const Icon(Icons.close, color: Colors.red),
            tooltip: "Düzenlemeyi İptal Et",
          )
      ],
    );
  }

  Widget _buildSearchField() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      child: TextField(
        controller: aramaC,
        onChanged: _listeyiFiltrele,
        decoration: InputDecoration(
          hintText: "Kütüphanede Ara...",
          prefixIcon: const Icon(Icons.search),
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
        ),
      ),
    );
  }

  Widget _buildResultList() {
    return Expanded(
      child: ListView.builder(
        itemCount: _filtreliListe.length,
        padding: const EdgeInsets.all(8),
        itemBuilder: (context, index) {
          final urun = _filtreliListe[index];
          return Card(
            child: ListTile(
              onTap: () => _formaDoldur(urun),
              leading: CircleAvatar(
                  backgroundColor: Colors.purple[50],
                  child: Text(urun['kategori'] != null && urun['kategori'].isNotEmpty ? urun['kategori'][0] : "?")
              ),
              title: Text("${urun['marka']} ${urun['model']}", style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text("${urun['kategori']} | ${urun['tarim_firmalari']} | ${urun['durum']}"),
              trailing: IconButton(
                icon: const Icon(Icons.delete, color: Colors.red),
                onPressed: () async {
                  await DatabaseHelper.instance.stokTaniminiIdIleSil(urun['id']);
                  _verileriSqlDenYukle();
                },
              ),
            ),
          );
        },
      ),
    );
  }

  void _formaDoldur(Map<String, dynamic> urun) {
    setState(() {
      String marka = urun['marka']?.toString().toUpperCase() ?? "";
      String model = urun['model']?.toString().toUpperCase() ?? "";

      if (marka.isNotEmpty && !_ekstraMarkalar.contains(marka)) _ekstraMarkalar.add(marka);
      if (model.isNotEmpty && !_ekstraModeller.contains(model)) _ekstraModeller.add(model);

      guncellenecekId = urun['id'];

      // --- BİLİNMEYEN SORUNUNU ÇÖZEN SATIR ---
      // Önce tarim_firmalari, sonra firma, o da yoksa ad sütununa bakıyoruz
      seciliFirma = (urun['tarim_firmalari'] ?? urun['firma'] ?? urun['ad'])?.toString().toUpperCase();

      seciliKategori = urun['kategori']?.toString().toUpperCase();
      seciliDurum = urun['durum'] ?? "SIFIR";
      altModelC.text = (urun['alt_model'] ?? urun['altModel'] ?? '').toString().toUpperCase();
      seciliMarka = marka;
      seciliModel = model;
    });
  }

  Widget _buildFormRow({
    required IconData icon,
    required String hint,
    String? value,
    required List<String> items,
    required Function(String?) onChanged,
    VoidCallback? onAdd
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(icon, color: Colors.purple, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: DropdownButtonFormField<String>(
              value: (value != null && items.contains(value)) ? value : null,
              hint: Text(hint, style: const TextStyle(fontSize: 13)),
              isExpanded: true,
              decoration: const InputDecoration(
                contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                isDense: true,
                border: UnderlineInputBorder(),
              ),
              items: items.toSet().map((e) => DropdownMenuItem(
                  value: e,
                  child: Text(e, style: const TextStyle(fontSize: 13), overflow: TextOverflow.ellipsis)
              )).toList(),
              onChanged: onChanged,
            ),
          ),
          if (onAdd != null)
            IconButton(
                constraints: const BoxConstraints(),
                padding: const EdgeInsets.only(left: 8),
                onPressed: onAdd,
                icon: const Icon(Icons.add_circle, color: Colors.green, size: 22)
            ),
        ],
      ),
    );
  }

  void _yeniEkleDialog(String baslik, Function(String) onEkle) {
    TextEditingController c = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(baslik),
        content: TextField(
          controller: c,
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(hintText: "Yazın..."),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("İPTAL")),
          ElevatedButton(
              onPressed: () {
                if (c.text.trim().isNotEmpty) {
                  onEkle(c.text.trim().toUpperCase());
                  Navigator.pop(context);
                }
              },
              child: const Text("EKLE")
          ),
        ],
      ),
    );
  }
}