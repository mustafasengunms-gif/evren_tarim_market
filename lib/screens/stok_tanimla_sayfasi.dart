import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../db/database_helper.dart';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;


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
    // 1. Veritabanındaki TÜM ham verileri al
    final hamVeriler = await DatabaseHelper.instance.stokTanimlariniGetir();
    final tazeKategoriler = await DatabaseHelper.instance.kategorileriGetirGaranti();

    // 2. SİLİNENLERİ FİLTRELE: Sadece 'silindi' değeri 0 olanları veya null olanları al
    final aktifVeriler = hamVeriler.where((s) {
      return s['silindi'] == 0 || s['silindi'] == null;
    }).toList();

    if (mounted) {
      setState(() {
        // Artık listelerimizde sadece "hayatta olan" stoklar var
        _sqlTanimliStoklar = aktifVeriler;
        _filtreliListe = aktifVeriler;
        _kategoriler = tazeKategoriler.map((e) => e.toString().toUpperCase()).toList();
      });
    }
  }

// 1. MARKA LİSTESİ: Filtreyi biraz gevşetiyoruz ki veri gelsin
  List<String> get _markaListesi {
    // Eğer hiçbir kategori seçilmemişse, TÜM markaları göster (Kilitlenmeyi önler)
    Iterable<Map<String, dynamic>> kaynak = _sqlTanimliStoklar;

    if (seciliKategori != null) {
      kaynak = kaynak.where((s) =>
      s['kategori'].toString().trim().toUpperCase() == seciliKategori!.trim().toUpperCase()
      );
    }

    List<String> liste = kaynak
        .map((s) => s['marka'].toString().trim().toUpperCase())
        .where((m) => m.isNotEmpty)
        .toList();

    liste.addAll(_ekstraMarkalar);
    return liste.toSet().toList();
  }

// 2. MODEL LİSTESİ: Markaya göre getir
  List<String> get _modelListesi {
    if (seciliMarka == null) return [];

    List<String> liste = _sqlTanimliStoklar
        .where((s) {
      // Marka eşleşmesi ana şartımız olsun
      bool markaMatch = s['marka'].toString().trim().toUpperCase() == seciliMarka!.trim().toUpperCase();

      // Kategori seçiliyse onu da kontrol et, değilse sadece markaya bak
      bool katMatch = true;
      if (seciliKategori != null) {
        katMatch = s['kategori'].toString().trim().toUpperCase() == seciliKategori!.trim().toUpperCase();
      }
      return markaMatch && katMatch;
    })
        .map((s) => s['model'].toString().trim().toUpperCase())
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

    String firmaAd = seciliFirma!.trim().toUpperCase();
    String altDeger = altModelC.text.toUpperCase().trim();
    String kat = seciliKategori!.trim().toUpperCase();
    String mrk = seciliMarka!.trim().toUpperCase();
    String mdl = seciliModel!.trim().toUpperCase();

    Map<String, dynamic> veri = {
      "tarim_firmalari": firmaAd,
      "firma": firmaAd,
      "marka": mrk,
      "model": mdl,
      "kategori": kat,
      "durum": seciliDurum,
      "alt_model": altDeger,
      "altmodel": altDeger,
      "is_synced": 0,
    };

    try {
      // --- MÜHÜRLEME VE ÖĞRENME ADIMI ---
      // Eğer yeni yazdığın Kategori, Marka veya Model listede yoksa,
      // SQL bunları bir sonraki girişte hatırlasın diye mühürlüyoruz.
      if (!_kategoriler.contains(kat)) {
        await DatabaseHelper.instance.kategoriEkleGaranti(kat); // SQL'e "Uçak"ı öğret
      }

      if (guncellenecekId != null) {
        await DatabaseHelper.instance.stokTanimGuncelleById(guncellenecekId!, veri);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Güncellendi ✅")));
      } else {
        await DatabaseHelper.instance.stokTanimEkle(veri);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Kütüphaneye Eklendi ✅")));
      }

      // --- KRİTİK NOKTA ---
      // Önce verileri tazeleyelim ki yeni eklenen "Uçak" veritabanından listeye girsin
      await _verileriSqlDenYukle();

      // Sonra formu temizle
      _formuTemizle();

    } catch (e) {
      print("❌ Kayıt Hatası: $e");
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Hata: $e")));
    }
  }

// 2. FORMA DOLDURMA METODU: Listeden seçince yukarıdaki kutuları doldurur
  void _formaDoldur(Map<String, dynamic> urun) {
    setState(() {
      guncellenecekId = urun['id'];

      // Firebase ve SQL'den gelen farklı isimleri kontrol et
      String? hamFirma = (urun['tarim_firmalari'] ?? urun['firma'] ?? urun['ad'])?.toString().toUpperCase();

      // Mevcut firmalar listesinde bu isim var mı bak, yoksa bile seçtir
      if (hamFirma != null) {
        seciliFirma = hamFirma;
      }

      seciliKategori = urun['kategori']?.toString().toUpperCase();
      seciliDurum = (urun['durum'] == "2. EL") ? "2. EL" : "SIFIR";
      altModelC.text = (urun['alt_model'] ?? urun['altmodel'] ?? '').toString().toUpperCase();

      String marka = urun['marka']?.toString().toUpperCase() ?? "";
      String model = urun['model']?.toString().toUpperCase() ?? "";

      if (marka.isNotEmpty && !_ekstraMarkalar.contains(marka)) _ekstraMarkalar.add(marka);
      if (model.isNotEmpty && !_ekstraModeller.contains(model)) _ekstraModeller.add(model);

      seciliMarka = marka;
      seciliModel = model;
    });
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
                  // _yeniEkleDialog çağrılan yerdeki kodu şu şekilde mühürle:
                  onAdd: () => _yeniEkleDialog("YENİ KATEGORİ", (y) async {
                    String yeniKat = y.trim().toUpperCase();
                    if (!_kategoriler.contains(yeniKat)) {
                      // Sadece ekrana değil, SQL'e de fısılda
                      await DatabaseHelper.instance.kategoriEkle(yeniKat);
                      setState(() {
                        _kategoriler.add(yeniKat);
                        seciliKategori = yeniKat;
                      });
                    }
                  }),
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
                  try {
                    // 1. Önce silme işlemini dene
                    await DatabaseHelper.instance.stokTaniminiIdIleSil(urun['id']);

                    // 2. Başarılıysa listeyi tazele
                    await _verileriSqlDenYukle();

                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text("Kayıt Arşivlendi ✅"), backgroundColor: Colors.green)
                      );
                    }
                  } catch (e) {
                    // 3. Hata varsa (Sütun yoksa vs.) buraya düşer
                    print("❌ Silme Hatası: $e");
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text("Sistem Hatası: Sütun eksik olabilir. Lütfen uygulamayı güncelleyin."),
                            backgroundColor: Colors.red,
                            action: SnackBarAction(label: "TAMAM", textColor: Colors.white, onPressed: () {}),
                          )
                      );
                    }
                  }
                },
              ),
            ),
          );
        },
      ),
    );
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
