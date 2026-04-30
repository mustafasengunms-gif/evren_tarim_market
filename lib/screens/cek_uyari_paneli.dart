import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../db/database_helper.dart';
import '../models/CekModel.dart';
import 'package:evren_tarim_market/db/database_helper.dart';

class CekUyariPaneli extends StatefulWidget {
  const CekUyariPaneli({super.key});

  @override
  State<CekUyariPaneli> createState() => _CekUyariPaneliState();
}

class _CekUyariPaneliState extends State<CekUyariPaneli> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<CekModel> tumBekleyenCekler = [];
  bool yukleniyor = true;
  final tlFormat = NumberFormat.currency(locale: 'tr_TR', symbol: '₺');

  @override
  void initState() {
    super.initState();
    // Sekme sayısını 4'e çıkardık
    _tabController = TabController(length: 4, vsync: this);
    _verileriGetir();
  }

  Future<void> _verileriGetir() async {
    setState(() => yukleniyor = true);
    final veriler = await DatabaseHelper.instance.getCekler();
    setState(() {
      // Sadece 'beklemede' olan çekleri (ödenmemiş) ana listeye alıyoruz
      tumBekleyenCekler = veriler.where((c) => c.durum == CekDurumu.beklemede).toList();
      yukleniyor = false;
    });
  }

  // Tarihe göre filtreleme fonksiyonu
  List<CekModel> _filtrele(int? gun) {
    var liste = <CekModel>[];

    if (gun == null) {
      // Eğer gün verilmemişse 'TÜMÜ' sekmesi içindir
      liste = List.from(tumBekleyenCekler);
    } else {
      final sinirTarihi = DateTime.now().add(Duration(days: gun));
      liste = tumBekleyenCekler.where((c) => c.vadeTarihi.isBefore(sinirTarihi)).toList();
    }

    // Her zaman vade tarihine göre sıralı göster (en yakın en üstte)
    liste.sort((a, b) => a.vadeTarihi.compareTo(b.vadeTarihi));
    return liste;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("ÖDEME TAKVİMİ"),
        backgroundColor: Colors.black,
        foregroundColor: const Color(0xFFFFD700),
        bottom: TabBar(
          controller: _tabController,
          labelColor: const Color(0xFFFFD700),
          unselectedLabelColor: Colors.white60,
          indicatorColor: const Color(0xFFFFD700),
          isScrollable: false, // 4 sekme ekrana sığar
          tabs: const [
            Tab(text: "7 GÜN"),
            Tab(text: "15 GÜN"),
            Tab(text: "30 GÜN"),
            Tab(text: "TÜMÜ"),
          ],
        ),
      ),
      body: yukleniyor
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
        controller: _tabController,
        children: [
          _listeOlustur(_filtrele(7), Colors.red, "Kritik Ödemeler"),
          _listeOlustur(_filtrele(15), Colors.orange, "Yakın Ödemeler"),
          _listeOlustur(_filtrele(30), Colors.blue, "Aylık Plan"),
          _listeOlustur(_filtrele(null), Colors.teal, "Tüm Portföy"),
        ],
      ),
    );
  }

  Widget _listeOlustur(List<CekModel> liste, Color temaRengi, String baslik) {
    if (liste.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle_outline, size: 50, color: temaRengi.withOpacity(0.5)),
            const SizedBox(height: 10),
            Text("$baslik bulunamadı.", style: const TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }

    double toplam = liste.fold(0.0, (sum, item) => sum + item.tutar);

    return Column(
      children: [
        _ozetBand(toplam, temaRengi, liste.length, baslik),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            itemCount: liste.length,
            itemBuilder: (context, index) => _uyariKarti(liste[index], temaRengi),
          ),
        ),
      ],
    );
  }

  Widget _ozetBand(double toplam, Color renk, int adet, String baslik) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: renk.withOpacity(0.08),
        border: Border(bottom: BorderSide(color: renk.withOpacity(0.2))),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(baslik.toUpperCase(), style: TextStyle(color: renk, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1)),
              const SizedBox(height: 2),
              Text(tlFormat.format(toplam), style: TextStyle(color: renk, fontSize: 20, fontWeight: FontWeight.bold)),
            ],
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(color: renk, borderRadius: BorderRadius.circular(20)),
            child: Text("$adet ADET", style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
          )
        ],
      ),
    );
  }

  Widget _uyariKarti(CekModel cek, Color renk) {
    int kalanGun = cek.vadeTarihi.difference(DateTime.now()).inDays;
    bool vadesiGecti = cek.vadeTarihi.isBefore(DateTime.now());

    return Card(
      elevation: 2,
      margin: const EdgeInsets.symmetric(vertical: 5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: ListTile(
          leading: Icon(
            vadesiGecti ? Icons.warning_rounded : Icons.calendar_today_rounded,
            color: vadesiGecti ? Colors.red[900] : renk,
            size: 28,
          ),
          title: Text(cek.firmaAd.toUpperCase(), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          subtitle: Text(
            "Vade: ${DateFormat('dd.MM.yyyy').format(cek.vadeTarihi)}\n${vadesiGecti ? 'GECİKMİŞ!' : '$kalanGun gün kaldı'}",
            style: TextStyle(
                color: vadesiGecti ? Colors.red[900] : Colors.black54,
                fontSize: 12
            ),
          ),
          // --- SAĞ TARAF: TUTAR VE İŞLEM BUTONU YAN YANA ---
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                  tlFormat.format(cek.tutar),
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.black87)
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: Icon(Icons.edit_note, color: renk),
                onPressed: () {
                  _durumDegistirPanel(cek);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _durumDegistirPanel(CekModel cek) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        title: Column(
          children: [
            Text(cek.firmaAd.toUpperCase(),
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 5),
            const Text("İşlem Seçiniz",
                style: TextStyle(fontSize: 13, color: Colors.grey, fontWeight: FontWeight.normal)),
            const Divider(),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min, // Ekranın ortasında küçük ve şık durur
          children: [
            // ÖDENDİ BUTONU
            _islemButon(
                icon: Icons.check_circle_outline,
                renk: Colors.green,
                metin: "ÖDENDİ",
                onTap: () async {
                  await DatabaseHelper.instance.cekDurumGuncelle(cek.id, "odendi");
                  _verileriGetir();
                  if (context.mounted) Navigator.pop(context);
                }
            ),
            const SizedBox(height: 12),

            // İADE EDİLDİ BUTONU
            _islemButon(
                icon: Icons.assignment_return_outlined,
                renk: Colors.orange,
                metin: "İADE EDİLDİ",
                onTap: () async {
                  await DatabaseHelper.instance.cekDurumGuncelle(cek.id, "iade");
                  _verileriGetir();
                  if (context.mounted) Navigator.pop(context);
                }
            ),
            const SizedBox(height: 12),

            // İPTAL BUTONU
            _islemButon(
                icon: Icons.highlight_off,
                renk: Colors.red,
                metin: "İPTAL ET",
                onTap: () async {
                  await DatabaseHelper.instance.cekDurumGuncelle(cek.id, "iptal");
                  _verileriGetir();
                  if (context.mounted) Navigator.pop(context);
                }
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("VAZGEÇ", style: TextStyle(color: Colors.blueGrey)),
          )
        ],
      ),
    );
  }

// Yardımcı Tasarım Butonu
  Widget _islemButon({required IconData icon, required Color renk, required String metin, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 15),
        decoration: BoxDecoration(
          color: renk.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: renk.withOpacity(0.3), width: 1.5),
        ),
        child: Row(
          children: [
            Icon(icon, color: renk, size: 24),
            const SizedBox(width: 15),
            Text(metin, style: TextStyle(color: renk, fontWeight: FontWeight.bold, fontSize: 14)),
            const Spacer(),
            Icon(Icons.chevron_right, color: renk, size: 18),
          ],
        ),
      ),
    );
  }
}