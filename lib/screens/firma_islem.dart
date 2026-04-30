import 'package:flutter/material.dart';
import '../db/database_helper.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'dart:io' show File;


// --- 1. ANA SAYFA: FİRMA LİSTESİ VE BAKİYELER ---
class FirmaTanimSayfasi extends StatefulWidget {
  const FirmaTanimSayfasi({super.key});

  @override
  State<FirmaTanimSayfasi> createState() => _FirmaTanimSayfasiState();
}

class _FirmaTanimSayfasiState extends State<FirmaTanimSayfasi> {
  // Örnek Veriler (Burası SQL'den dolacak)
  // Eski listeyi sil, bunu yaz:
  List<Map<String, dynamic>> _firmalar = [];
  @override
  void initState() {
    super.initState();
    _firmalariGetir(); // Sayfa açılır açılmaz veriyi çek
  }

  Future<void> _firmalariGetir() async {
    // Eski: firmaListesiGetir()
    // Yeni: Sadece dükkan carilerini getiren fonksiyon
    final veriler = await DatabaseHelper.instance.tarimFirmaListesiGetir();
    setState(() {
      _firmalar = veriler;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("FİRMA TANIM / CARİ"),
        backgroundColor: Colors.teal[800],
        foregroundColor: Colors.white,
        actions: [
          IconButton(icon: const Icon(Icons.add_business), onPressed: () => _firmaFormu()),
        ],
      ),
      body: Column(
        children: [
          _ustBilgiPaneli(),
          const Padding(
            padding: EdgeInsets.all(8.0),
            child: Text("FİRMALAR VE GÜNCEL DURUMLAR", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: _firmalar.length,
              itemBuilder: (context, i) {
                final f = _firmalar[i];
                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  child: ListTile(
                    leading: CircleAvatar(backgroundColor: Colors.teal, child: Text(f['ad'][0], style: const TextStyle(color: Colors.white))),
                    title: Text(f['ad'], style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text(f['tel']),
                    trailing: (() {
                      // 1. ADIM: Gerçek Bakiyeyi Hesapla (Alacak - Borç)
                      double alacak = double.tryParse(f['alacak']?.toString() ?? "0") ?? 0.0;
                      double borc = double.tryParse(f['borc']?.toString() ?? "0") ?? 0.0;
                      double netBakiye = alacak - borc;

                      return Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            "${netBakiye.toStringAsFixed(2)} ₺",
                            style: TextStyle(
                              // Eksi ise KIRMIZI (Borçluyuz), Artı ise YEŞİL (Alacaklıyız)
                              color: netBakiye < 0 ? Colors.red : Colors.green[700],
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                          Text(
                            netBakiye < 0 ? "BORÇLUYUZ" : "ALACAKLIYIZ",
                            style: TextStyle(
                                color: netBakiye < 0 ? Colors.red : Colors.green,
                                fontSize: 9,
                                fontWeight: FontWeight.bold
                            ),
                          ),
                        ],
                      );
                    })(),
                    onLongPress: () => _firmaSil(f['id']), // Uzun basınca sil
                    // FirmaTanimSayfasi içindeki onTap:
                    onTap: () async {
                      await Navigator.push(context, MaterialPageRoute(builder: (c) => FirmaEkstreSayfasi(firmaAd: f['ad'])));
                      _firmalariGetir(); // Sayfadan geri gelince listeyi tazelemek için bu şart!
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _ustBilgiPaneli() {
    double toplamGercekAlacak = 0; // Bizim alacaklı olduklarımız
    double toplamGercekBorc = 0;   // Bizim borçlu olduklarımız

    for (var f in _firmalar) {
      // Senin sisteminde her şey 'borc' sütununda tutuluyor
      double bakiye = double.tryParse(f['borc']?.toString() ?? "0") ?? 0.0;

      if (bakiye > 0) {
        // Borç sütunu ARTI ise: Biz firmaya borçluyuz
        toplamGercekBorc += bakiye;
      } else if (bakiye < 0) {
        // Borç sütunu EKSİ ise: Bizim firmadan alacağımız var demektir
        toplamGercekAlacak += bakiye.abs(); // Eksiyi artıya çevirip alacağa ekle
      }
    }

    return Container(
      padding: const EdgeInsets.all(15),
      color: Colors.white,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          // Burası artık eksi rakam göstermez, tertemiz yazar
          _kutu("TOPLAM ALACAK", "${toplamGercekAlacak.toStringAsFixed(2)} ₺", Colors.green[700]!),
          _kutu("TOPLAM BORÇ", "${toplamGercekBorc.toStringAsFixed(2)} ₺", Colors.red[700]!),
        ],
      ),
    );
  }

  Widget _kutu(String b, String d, Color r) => Column(children: [
    Text(b, style: const TextStyle(fontSize: 10, color: Colors.grey)),
    Text(d, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: r)),
  ]);

  // --- FİRMA EKLEME FORMU (HATASIZ TAM KOD) ---
  void _firmaFormu() {
    // 1. HATA: Controllerlar eksikti, eklendi.
    final TextEditingController adC = TextEditingController();
    final TextEditingController yetkiliC = TextEditingController();
    final TextEditingController telC = TextEditingController();
    final TextEditingController adresC = TextEditingController();

    showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        builder: (c) => Padding(
          padding: EdgeInsets.only(
              bottom: MediaQuery.of(c).viewInsets.bottom,
              left: 20, right: 20, top: 20
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text("YENİ FİRMA KAYDI", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              const SizedBox(height: 15),

              // 2. HATA: Parametre sayısı (3 tane olmalıydı) düzeltildi.
              _input("Firma Ünvanı", Icons.business, adC),
              _input("Yetkili Ad Soyad", Icons.person, yetkiliC),
              _input("Telefon Numarası", Icons.phone, telC),
              _input("Firma Adresi", Icons.map, adresC),

              const SizedBox(height: 20),

              SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.teal[800],
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: () async {
                        // 3. HATA: Boş kayıt engellendi.
                        if (adC.text.trim().isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text("Firma adını yaz abi!"))
                          );
                          return;
                        }

                        // 4. HATA: Veritabanına veri gitmiyordu, artık gidiyor.
                        Map<String, dynamic> yeniFirma = {
                          'ad': adC.text.toUpperCase().trim(), // BURASI DOĞRU, 'ad' KALSIN
                          'yetkili': yetkiliC.text.trim(),
                          'tel': telC.text.trim(),
                          'adres': adresC.text.trim(),
                          'borc': 0.0,
                          'alacak': 0.0,
                        };

                        await DatabaseHelper.instance.tarimFirmaEkle(yeniFirma);

                        // 5. HATA: Liste yenilenmiyordu, _firmalariGetir() eklendi.
                        if (context.mounted) {
                          Navigator.pop(c);
                          _firmalariGetir();
                          ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text("Firma başarıyla kaydedildi!"))
                          );
                        }
                      },
                      child: const Text("FİRMAYI KAYDET", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold))
                  )
              ),
              const SizedBox(height: 25),
            ],
          ),
        )
    );
  }

  // --- BU FONKSİYONU DA GÜNCELLE (PARAMETRELER TUTMALI) ---
  Widget _input(String l, IconData i, TextEditingController c) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: c,
        decoration: InputDecoration(
          labelText: l,
          prefixIcon: Icon(i, color: Colors.teal[800]),
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }

  void _firmaSil(int id) {
    // Buraya SQL silme kodu gelecek abi
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Firma ve tüm kayıtları silindi.")));
  }
}


// --- 2. DETAY SAYFASI: SADECE ÖDEME VE TAHSİLAT (CARİ HAREKETLER) ---
class FirmaEkstreSayfasi extends StatefulWidget {
  final String firmaAd;
  const FirmaEkstreSayfasi({super.key, required this.firmaAd});

  @override
  State<FirmaEkstreSayfasi> createState() => _FirmaEkstreSayfasiState();
}

class _FirmaEkstreSayfasiState extends State<FirmaEkstreSayfasi> {
  List<Map<String, dynamic>> _hareketler = [];






  Widget buildImage(String path) {
    if (kIsWeb) {
      return Image.network(path); // web
    } else {
      return Image.file(File(path)); // mobil
    }
  }

  @override
  void initState() {
    super.initState();
    _hareketleriGetir();
  }

  Future<void> _hareketleriGetir() async {
    // DatabaseHelper'dan bu firmaya özel hareketleri istiyoruz
    final veriler = await DatabaseHelper.instance.firmaHareketleriniGetir(widget.firmaAd);

    if (mounted) {
      setState(() {
        _hareketler = veriler; // Gelen veriyi ekrana basıyoruz
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("${widget.firmaAd} EKSTRESİ"),
        backgroundColor: Colors.teal[700],
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          _ozetKarti(),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text("HESAP HAREKETLERİ", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
          ),
          Expanded(
            child: _hareketler.isEmpty
                ? const Center(child: Text("Henüz bir ödeme veya tahsilat kaydı yok."))
                : ListView.builder(
              itemCount: _hareketler.length,
              itemBuilder: (context, i) {
                final h = _hareketler[i];
                bool isOdeme = h['tip'] == 'ÖDEME';
                return ListTile(
                  leading: Icon(isOdeme ? Icons.arrow_upward : Icons.arrow_downward,
                      color: isOdeme ? Colors.red : Colors.green),
                  // ListView içindeki ListTile'da:
                  title: Text(h['aciklama'] ?? "İşlem Kaydı"), // Eğer açıklama yoksa null yazmasın
                  subtitle: Text(h['tarih']?.split('T')[0] ?? ""), // Tarihi daha düzgün gösterir
                  trailing: Text("${h['tutar']} TL",
                      style: TextStyle(fontWeight: FontWeight.bold,
                          color: isOdeme ? Colors.red : Colors.green)),
                );
              },
            ),
          ),
          _altAksiyonlar(context),
        ],
      ),
    );
  }

  Widget _ozetKarti() {
    // Hareketler listesinden anlık hesapla
    double toplam = 0;
    for (var h in _hareketler) {
      double tutar = double.tryParse(h['tutar'].toString()) ?? 0.0;
      if (h['tip'] == 'TAHSİLAT') {
        toplam += tutar;
      } else {
        toplam -= tutar;
      }
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      margin: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: toplam < 0 ? Colors.red[50] : Colors.teal[50],
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: toplam < 0 ? Colors.red.shade200 : Colors.teal.shade200),
      ),
      child: Column(
        children: [
          Text("GÜNCEL BAKİYE", style: TextStyle(fontSize: 12, color: toplam < 0 ? Colors.red : Colors.teal)),
          const SizedBox(height: 5),
          Text(
              "${toplam.toStringAsFixed(2)} ₺",
              style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: toplam < 0 ? Colors.red : Colors.teal
              )
          ),
        ],
      ),
    );
  }

  Widget _altAksiyonlar(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: const BoxDecoration(
      color: Colors.white,
      boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10, offset: Offset(0, -2))],
    ),
    child: Row(
      children: [
        _islemButon("ÖDEME YAP", Colors.red, Icons.upload_outlined, () => _islemPenceresi("ÖDEME")),
        const SizedBox(width: 12),
        _islemButon("TAHSİLAT AL", Colors.green, Icons.download_outlined, () => _islemPenceresi("TAHSİLAT")),
      ],
    ),
  );

  Widget _islemButon(String t, Color c, IconData i, VoidCallback o) => Expanded(
    child: ElevatedButton.icon(
      onPressed: o,
      icon: Icon(i, size: 20),
      label: Text(t, style: const TextStyle(fontWeight: FontWeight.bold)),
      style: ElevatedButton.styleFrom(
        backgroundColor: c,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    ),
  );

  void _islemPenceresi(String baslik) {
    TextEditingController tutarC = TextEditingController();
    TextEditingController aciklamaC = TextEditingController();

    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: Text("$baslik GİRİŞİ", style: TextStyle(color: baslik == "ÖDEME" ? Colors.red : Colors.green)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: tutarC,
              decoration: const InputDecoration(labelText: "Tutar", suffixText: "TL", border: OutlineInputBorder()),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 10),
            TextField(
              controller: aciklamaC,
              decoration: const InputDecoration(labelText: "Açıklama / Not", border: OutlineInputBorder()),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text("İPTAL")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: baslik == "ÖDEME" ? Colors.red : Colors.green),
            onPressed: () async {
              double? tutar = double.tryParse(tutarC.text.replaceAll(',', '.'));
              String aciklama = aciklamaC.text.trim();

              if (tutar != null && tutar > 0) {
                // 1. CARİ HAREKETİ KAYDET (Bu zaten döküm için şart)
                await DatabaseHelper.instance.cariHareketEkle({
                  'ad': widget.firmaAd, // 'firma_ad' yerine 'ad' yapıyoruz!
                  'tip': baslik,
                  'tutar': tutar,
                  'aciklama': aciklama.isEmpty ? baslik : aciklama,
                  'tarih': DateTime.now().toIso8601String(),
                });

                await DatabaseHelper.instance.firmaBakiyesiGuncelle(widget.firmaAd, tutar, baslik);

                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text("$baslik Kaydedildi!"), backgroundColor: Colors.green)
                  );
                  Navigator.pop(context);

                  // Hem bu sayfadaki listeyi hem de bir önceki sayfadaki bakiyeleri tazelemek için:
                  _hareketleriGetir();
                }
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("Lütfen geçerli bir tutar gir abi!"))
                );
              }
            },
            child: const Text("KAYDET", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}