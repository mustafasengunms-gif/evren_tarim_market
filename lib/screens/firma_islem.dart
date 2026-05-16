import 'package:flutter/material.dart';
import '../db/database_helper.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:intl/intl.dart'; // DateFormat hatasını bu satır çözer


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
                      await Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (c) => FirmaEkstreSayfasi(
                                firmaAd: f['ad'].toString(),        // Firmanın adı (Başlık için)
                                cariKod: f['cari_kod'].toString(),  // ASIL MÜHÜR (Sorgu için)
                              )
                          )
                      );
                      // Sayfadan geri gelince (Ödeme/Alım yapılmış olabilir) listeyi tazeliyoruz
                      _firmalariGetir();
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

  void _firmaFormu() {
    final TextEditingController adC = TextEditingController();
    final TextEditingController yetkiliC = TextEditingController();
    final TextEditingController telC = TextEditingController();
    final TextEditingController adresC = TextEditingController();

    showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.white,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        builder: (c) => Container(
          color: Colors.white,
          padding: EdgeInsets.only(
              bottom: MediaQuery.of(c).viewInsets.bottom,
              left: 20, right: 20, top: 20
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text("YENI FIRMA KAYDI",
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.black)),
              const SizedBox(height: 15),

              _input("Firma Unvani", Icons.business, adC),
              _input("Yetkili Ad Soyad", Icons.person, yetkiliC),
              _input("Telefon Numarasi", Icons.phone, telC),
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
                        String temizAd = adC.text.trim().toUpperCase();

                        if (temizAd.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text("Firma adini yaz abi!"))
                          );
                          return;
                        }

                        // 🔥 MUHURLEME: Zamani saniyesine kadar mühürledik
                        String muhur = "F-${DateTime.now().millisecondsSinceEpoch}";

                        Map<String, dynamic> yeniFirma = {
                          'cari_kod': muhur, // Ana mühür
                          'id': muhur,       // Firebase döküman ID ile eşleşmesi için
                          'firebase_id': muhur,
                          'ad': temizAd,
                          'yetkili': yetkiliC.text.trim(),
                          'tel': telC.text.trim(),
                          'adres': adresC.text.trim(),
                          'borc': 0.0,
                          'alacak': 0.0,
                          'sube': 'TEFENNI',
                          'is_synced': 1, // Kayıt anında senkron sayıyoruz
                          'son_guncelleme': DateTime.now().toIso8601String(),
                        };

                        // Bekleme göstergesi (UI kitlenmesin)
                        showDialog(
                          context: context,
                          barrierDismissible: false,
                          builder: (context) => const Center(child: CircularProgressIndicator()),
                        );

                        try {
                          // Veritabanı motoru artık bu mühürü kullanmak ZORUNDA
                          await DatabaseHelper.instance.tarimFirmaEkle(yeniFirma);

                          if (mounted) {
                            Navigator.pop(context); // Loading kapat
                            Navigator.pop(c);       // Formu kapat
                            _firmalariGetir();      // Listeyi tazele
                            ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text("Firma Muhurlendi ✅"))
                            );
                          }
                        } catch (e) {
                          if (mounted) Navigator.pop(context);
                          debugPrint("Kayıt Hatası: $e");
                        }
                      },
                      child: const Text("FIRMAYI KAYDET",
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold))
                  )
              ),
              const SizedBox(height: 25),
            ],
          ),
        )
    );
  }

  // --- INPUT YARDIMCISI (RENKLER SABİTLENDİ) ---
  Widget _input(String l, IconData i, TextEditingController c) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: c,
        style: const TextStyle(color: Colors.black), // Yazı rengini siyah yapalım
        decoration: InputDecoration(
          labelText: l,
          labelStyle: const TextStyle(color: Colors.grey),
          prefixIcon: Icon(i, color: Colors.teal[800]),
          filled: true,
          fillColor: Colors.white, // İçini beyaz doldur ki gri kalmasın
          border: const OutlineInputBorder(),
          enabledBorder: const OutlineInputBorder(borderSide: BorderSide(color: Colors.grey)),
        ),
      ),
    );
  }

  // --- FIRMA SILME MOTORU (MUHURLU) ---
  void _firmaSil(String cariKod) { // Artik String cariKod aliyor
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("EMIN MISIN ABI?"),
        content: Text("$cariKod muhurlu firma ve TUM HAREKETLERI silinecek. Bu isin donusu yok!"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("VAZGEC", style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              Navigator.pop(context); // Diyalogu kapat

              // Bekleme ekrani
              showDialog(
                context: context,
                barrierDismissible: false,
                builder: (c) => const Center(child: CircularProgressIndicator()),
              );

              try {
                // 1. DatabaseHelper icindeki o zirhli silme fonksiyonunu cagiriyoruz
                await DatabaseHelper.instance.tarimfirmaSil(cariKod);

                if (mounted) {
                  Navigator.pop(context); // Loading'i kapat
                  _firmalariGetir(); // Ana listeyi tazele
                  ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text("Firma ve tum kayitlar her yerden kazindi ✅"))
                  );
                }
              } catch (e) {
                if (mounted) Navigator.pop(context);
                debugPrint("Silme Hatasi: $e");
              }
            },
            child: const Text("SIL GITSIN"),
          ),
        ],
      ),
    );
  }
}



class FirmaEkstreSayfasi extends StatefulWidget {
  final String firmaAd;
  final String cariKod; // firmaId yerine cariKod ve tipi String yaptık

  const FirmaEkstreSayfasi({
    super.key,
    required this.firmaAd,
    required this.cariKod // Artık zorunlu ve mühürlü
  });

  @override
  State<FirmaEkstreSayfasi> createState() => _FirmaEkstreSayfasiState();
}

class _FirmaEkstreSayfasiState extends State<FirmaEkstreSayfasi> {
  List<Map<String, dynamic>> _hareketler = [];
  bool _yukleniyor = true;

  @override
  void initState() {
    super.initState();
    _hareketleriGetir();
  }

  // --- MÜHÜRLÜ VERİ ÇEKME MOTORU ---
  Future<void> _hareketleriGetir() async {
    if (!mounted) return;
    setState(() => _yukleniyor = true);

    // DatabaseHelper içindeki o "Demir Gibi" fonksiyonu çağırıyor
    final veriler = await DatabaseHelper.instance.tarimfirmaEkstresiGetir(widget.cariKod ?? widget.firmaAd);

    if (mounted) {
      setState(() {
        _hareketler = veriler;
        _yukleniyor = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: Text("${widget.firmaAd} EKSTRESİ"),
        backgroundColor: Colors.teal[700],
        foregroundColor: Colors.white,
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _hareketleriGetir)
        ],
      ),
      body: _yukleniyor
          ? const Center(child: CircularProgressIndicator())
          : Column(
        children: [
          _ozetKarti(),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text("HESAP HAREKETLERİ", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
          ),
          Expanded(
            child: _hareketler.isEmpty
                ? const Center(child: Text("Henüz bir hareket kaydı bulunamadı."))
                : ListView.builder(
              itemCount: _hareketler.length,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              itemBuilder: (context, i) {
                final h = _hareketler[i];

                // Web/Mobil ve Uç/Tip karmaşasını çözen mantık:
                String tip = (h['tip'] ?? h['uç'] ?? "İŞLEM").toString().toUpperCase();
                bool isNegatif = (tip == 'ÖDEME' || tip == 'AVANS' || tip == 'TAHSİLAT');

                return Card(
                  elevation: 1,
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: isNegatif ? Colors.red[50] : Colors.green[50],
                      child: Icon(isNegatif ? Icons.arrow_upward : Icons.arrow_downward,
                          color: isNegatif ? Colors.red : Colors.green),
                    ),
                    title: Text(h['urun_adi'] ?? h['aciklama'] ?? "İşlem Kaydı"),
                    subtitle: Text(h['tarih'] ?? ""),
                    trailing: Text("${h['tutar']} TL",
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: isNegatif ? Colors.red : Colors.green)),
                  ),
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
    double toplam = 0;
    for (var h in _hareketler) {
      double tutar = double.tryParse(h['tutar'].toString()) ?? 0.0;
      String tip = (h['tip'] ?? h['uç'] ?? "").toString().toUpperCase();

      // Borç/Alacak Hesaplama
      if (tip == 'ALIM') {
        toplam += tutar;
      } else if (tip == 'ÖDEME' || tip == 'AVANS' || tip == 'TAHSİLAT') {
        toplam -= tutar;
      }
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      margin: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)],
        border: Border.all(color: toplam > 0 ? Colors.red.shade200 : Colors.teal.shade200),
      ),
      child: Column(
        children: [
          Text(toplam > 0 ? "FİRMAYA BORCUMUZ" : "FİRMADAN ALACAK",
              style: TextStyle(fontSize: 12, color: toplam > 0 ? Colors.red : Colors.teal)),
          const SizedBox(height: 5),
          Text(
              "${toplam.abs().toStringAsFixed(2)} ₺",
              style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: toplam > 0 ? Colors.red[900] : Colors.teal[900]
              )
          ),
        ],
      ),
    );
  }

  Widget _altAksiyonlar(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    color: Colors.white,
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
      label: Text(t),
      style: ElevatedButton.styleFrom(
        backgroundColor: c, foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 12),
      ),
    ),
  );

  void _islemPenceresi(String baslik) {
    TextEditingController tutarC = TextEditingController();
    TextEditingController aciklamaC = TextEditingController();

    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: Text("$baslik GİRİŞİ"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: tutarC, decoration: const InputDecoration(labelText: "Tutar"), keyboardType: TextInputType.number),
            TextField(controller: aciklamaC, decoration: const InputDecoration(labelText: "Açıklama")),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text("İPTAL")),
          ElevatedButton(
            onPressed: () async {
              double m = double.tryParse(tutarC.text) ?? 0;
              if (m > 0) {
                // Burada DatabaseHelper içindeki mühürlü kayıt fonksiyonunu kullanıyoruz
                await DatabaseHelper.instance.tarimfirmaHareketiEkle({
                  'firma_id': widget.cariKod ?? widget.firmaAd,
                  'tip': baslik,
                  'urun_adi': aciklamaC.text.isEmpty ? baslik : aciklamaC.text,
                  'tutar': m,
                  'tarih': DateFormat('dd.MM.yyyy').format(DateTime.now()),
                });
                Navigator.pop(context);
                _hareketleriGetir();
              }
            },
            child: const Text("KAYDET"),
          ),
        ],
      ),
    );
  }
}