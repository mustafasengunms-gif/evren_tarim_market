import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flutter/foundation.dart' show kIsWeb;


class RaporlarSayfasi extends StatelessWidget {
  final Map<String, dynamic>? raporVerisi; // ? koyarak null gelebilir dedik
  const RaporlarSayfasi({super.key, this.raporVerisi});

  String formatTL(dynamic deger) {
    if (deger == null) return "0,00 ₺";
    final format = NumberFormat.currency(locale: 'tr_TR', symbol: '₺');
    return format.format(double.tryParse(deger.toString()) ?? 0.0);
  }

  @override
  Widget build(BuildContext context) {
    // Web'de genişliğe göre kart sayısını ayarla
    double genislik = MediaQuery.of(context).size.width;
    int kartSayisi = genislik > 800 ? 4 : 2; // Web'de 4, Mobilde 2 sütun

    // Veri null gelirse boş harita ata ki hata vermesin
    final veri = raporVerisi ?? {};

    return Scaffold(
      appBar: AppBar(
        title: const Text("EVREN TİCARET GENEL RAPOR"),
        backgroundColor: Colors.green[900],
        foregroundColor: Colors.white,
        centerTitle: true,
      ),
      body: veri.isEmpty
          ? const Center(child: CircularProgressIndicator()) // Veri gelene kadar döner
          : Padding(
        padding: const EdgeInsets.all(12.0),
        child: GridView.count(
          crossAxisCount: kartSayisi,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          childAspectRatio: 1.4,
          children: [
            _raporKarti("TOPLAM CİRO", formatTL(veri['toplam_satis']), Icons.trending_up, Colors.green),
            _raporKarti("STOKTAKİ ÜRÜN", "${veri['stok_sayisi'] ?? 0} Kalem", Icons.inventory_2, Colors.orange),
            _raporKarti("FİRMA SAYISI", "${veri['firma_sayisi'] ?? 0} Kayıtlı", Icons.business, Colors.blueGrey),
            _raporKarti("FİRMA BORÇLARI", formatTL(veri['firma_borcu']), Icons.account_balance, Colors.red[900]!),
            _raporKarti("MÜŞTERİLER", "${veri['musteri_sayisi'] ?? 0} Kişi", Icons.groups, Colors.indigo),
            _raporKarti("TOPLAM SATIŞ", "${veri['islem_sayisi'] ?? 0} Adet", Icons.shopping_bag, Colors.blue),
            _raporKarti("BEKLEYEN ÇEK", formatTL(veri['cek_toplam']), Icons.confirmation_number, Colors.red),
            _raporKarti("BEKLEYEN SENET", formatTL(veri['senet_toplam']), Icons.history_edu, Colors.purple),
          ],
        ),
      ),
    );
  }

  Widget _raporKarti(String baslik, String deger, IconData ikon, Color renk) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: Container(
        padding: const EdgeInsets.all(8),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(ikon, color: renk, size: 32),
            const SizedBox(height: 8),
            Text(baslik, textAlign: TextAlign.center, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black54)),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(deger, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: renk)),
            ),
          ],
        ),
      ),
    );
  }
}