import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class RaporlarSayfasi extends StatelessWidget {
  final Map<String, dynamic> raporVerisi;
  const RaporlarSayfasi({super.key, required this.raporVerisi});

  String formatTL(dynamic deger) {
    final format = NumberFormat.currency(locale: 'tr_TR', symbol: '₺');
    return format.format(double.tryParse(deger.toString()) ?? 0.0);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("EVREN TİCARET GENEL RAPOR"),
        backgroundColor: Colors.green[900],
        foregroundColor: Colors.white,
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(12.0),
        child: GridView.count(
          crossAxisCount: 2,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          childAspectRatio: 1.4,
          children: [
            _raporKarti("TOPLAM CİRO", formatTL(raporVerisi['toplam_satis']), Icons.trending_up, Colors.green),
            _raporKarti("STOKTAKİ ÜRÜN", "${raporVerisi['stok_sayisi']} Kalem", Icons.inventory_2, Colors.orange),

            _raporKarti("FİRMA SAYISI", "${raporVerisi['firma_sayisi']} Kayıtlı", Icons.business, Colors.blueGrey),
            _raporKarti("FİRMA BORÇLARI", formatTL(raporVerisi['firma_borcu']), Icons.account_balance, Colors.red[900]!),

            _raporKarti("MÜŞTERİLER", "${raporVerisi['musteri_sayisi']} Kişi", Icons.groups, Colors.indigo),
            _raporKarti("TOPLAM SATIŞ", "${raporVerisi['islem_sayisi']} Adet", Icons.shopping_bag, Colors.blue),

            // 🔥 BURADAKİ İKONLARI DÜZELTTİK:
            _raporKarti("BEKLEYEN ÇEK", formatTL(raporVerisi['cek_toplam']), Icons.confirmation_number, Colors.red),
            _raporKarti("BEKLEYEN SENET", formatTL(raporVerisi['senet_toplam']), Icons.history_edu, Colors.purple),
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
            Icon(ikon, color: renk, size: 28),
            const SizedBox(height: 6),
            Text(baslik, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.black54)),
            const SizedBox(height: 2),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(deger, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: renk)),
            ),
          ],
        ),
      ),
    );
  }
}