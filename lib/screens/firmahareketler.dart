import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../db/database_helper.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

class FirmaEkstreSayfasi extends StatefulWidget {
  final String cariKod; // firmaId yerine cariKod (String)
  final String firmaAd;

  const FirmaEkstreSayfasi({super.key, required this.cariKod, required this.firmaAd});

  @override
  State<FirmaEkstreSayfasi> createState() => _FirmaEkstreSayfasiState();
}

class _FirmaEkstreSayfasiState extends State<FirmaEkstreSayfasi> {
  Key _refreshKey = UniqueKey();

  Widget _input(TextEditingController c, String l, {TextInputType keyboard = TextInputType.text, int lines = 1}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextField(
        controller: c,
        keyboardType: keyboard,
        maxLines: lines,
        decoration: InputDecoration(
          labelText: l,
          border: const OutlineInputBorder(),
          filled: true,
          fillColor: Colors.white,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: Text("${widget.firmaAd} Ekstresi"),
        backgroundColor: Colors.indigo[900],
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => setState(() => _refreshKey = UniqueKey()),
          )
        ],
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        key: _refreshKey,
        future: DatabaseHelper.instance.tarimfirmaEkstresiGetir(widget.cariKod),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snap.hasData || snap.data!.isEmpty) {
            return const Center(child: Text("Henüz bir hareket yok."));
          }

          final hareketler = snap.data!;

          // 1. TOPLAM BAKİYE HESAPLAMA (Mühürlü Mantık)
          double netBakiye = 0;
          for (var h in hareketler) {
            double tutar = double.tryParse(h['tutar']?.toString() ?? "0") ?? 0.0;
            String tip = (h['tip'] ?? "ALIM").toString().toUpperCase();

            // Borç/Alacak Ayrımı
            if (tip == "ÖDEME" || tip == "TAHSİLAT" || tip == "AVANS") {
              netBakiye -= tutar; // Ödeme yaptıkça borç azalır
            } else {
              netBakiye += tutar; // Mal aldıkça (ALIM) borç artar
            }
          }

          return Column(
            children: [
              _bakiyeKarti(netBakiye),
              Expanded(
                child: ListView.builder(
                  itemCount: hareketler.length,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  itemBuilder: (context, i) {
                    final h = hareketler[i];
                    String tip = (h['tip'] ?? "İŞLEM").toString().toUpperCase();
                    bool isOdeme = (tip == "ÖDEME" || tip == "TAHSİLAT" || tip == "AVANS");
                    double tutar = double.tryParse(h['tutar']?.toString() ?? "0") ?? 0.0;

                    return Card(
                      elevation: 2,
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: isOdeme ? Colors.green[50] : Colors.red[50],
                          child: Icon(isOdeme ? Icons.call_made : Icons.call_received,
                              color: isOdeme ? Colors.green : Colors.red),
                        ),
                        title: Text(
                            h['urun_adi'] ?? h['aciklama'] ?? 'İşlem',
                            style: const TextStyle(fontWeight: FontWeight.bold)
                        ),
                        subtitle: Text(h['tarih'] ?? ""),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              "${NumberFormat.currency(locale: 'tr_TR', symbol: '').format(tutar)} ₺",
                              style: TextStyle(
                                color: isOdeme ? Colors.green[700] : Colors.red[700],
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline, color: Colors.grey, size: 20),
                              onPressed: () => _hareketSilDialog(h),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _yeniOdemeDialog(context),
        label: const Text("ÖDEME / TAHSİLAT GİR"),
        icon: const Icon(Icons.add_card),
        backgroundColor: Colors.red[900],
      ),
    );
  }

  Widget _bakiyeKarti(double netBakiye) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: netBakiye >= 0 ? Colors.red[50] : Colors.green[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: netBakiye >= 0 ? Colors.red.shade200 : Colors.green.shade200),
      ),
      child: Column(
        children: [
          Text(
            netBakiye >= 0 ? "FİRMAYA TOPLAM BORCUNUZ" : "FİRMADAN TOPLAM ALACAĞINIZ",
            style: TextStyle(fontWeight: FontWeight.bold, color: netBakiye >= 0 ? Colors.red[900] : Colors.green[900]),
          ),
          const SizedBox(height: 8),
          Text(
            "${NumberFormat.currency(locale: 'tr_TR', symbol: '').format(netBakiye.abs())} ₺",
            style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: netBakiye >= 0 ? Colors.red[900] : Colors.green[900]),
          ),
        ],
      ),
    );
  }

  void _hareketSilDialog(Map<String, dynamic> h) {
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text("KAYDI SİL"),
        content: Text("${h['tutar']} ₺ tutarındaki bu işlem silinecek. Emin misin abi?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text("VAZGEÇ")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              // Navigator'ı hemen kapatıyoruz ki kullanıcı üst üste basmasın
              Navigator.pop(c);

              try {
                // DİKKAT: Parametre isimlerini mühürlü fonksiyonla birebir eşledik
                await DatabaseHelper.instance.firmaHareketiSil(
                  hareketId: h['id'].toString(), // 'id' yerine 'hareketId' olarak düzelttik
                  cariKod: widget.cariKod,
                  tutar: double.tryParse(h['tutar']?.toString() ?? "0") ?? 0.0,
                  tip: (h['tip'] ?? "ALIM").toString().toUpperCase(), // 'uç' riskini kaldırdık
                );

                // Sayfayı yenile
                setState(() => _refreshKey = UniqueKey());

                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Kayıt başarıyla silindi ve bakiye güncellendi.")),
                );
              } catch (e) {
                debugPrint("Silme hatası: $e");
              }
            },
            child: const Text("EVET, SİL", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Future<void> _yeniOdemeDialog(BuildContext context) async {
    final tutarC = TextEditingController();
    final aciklamaC = TextEditingController();
    final tarihC = TextEditingController(text: DateFormat('dd.MM.yyyy').format(DateTime.now()));
    String islemTipi = "ÖDEME"; // Varsayılan Ödeme (Senin borcun azalır)

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setS) => AlertDialog(
          title: Text("$islemTipi GİRİŞİ"),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  value: islemTipi,
                  decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: "İşlem Türü"
                  ),
                  items: const [
                    DropdownMenuItem(value: "ÖDEME", child: Text("ÖDEME YAPTIM (BORCUM DÜŞER)")),
                    DropdownMenuItem(value: "TAHSİLAT", child: Text("GERİ ÖDEME ALDIM")),
                    DropdownMenuItem(value: "ALIM", child: Text("MAL ALDIM (BORCUM ARTAR)")),
                  ],
                  onChanged: (v) => setS(() => islemTipi = v!),
                ),
                const SizedBox(height: 10),
                // _input fonksiyonun zaten tanımlı olduğunu varsayıyorum
                TextField(
                  controller: tutarC,
                  decoration: const InputDecoration(labelText: "Tutar (₺)", border: OutlineInputBorder()),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: tarihC,
                  decoration: const InputDecoration(labelText: "Tarih", border: OutlineInputBorder()),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: aciklamaC,
                  decoration: const InputDecoration(labelText: "Açıklama (Opsiyonel)", border: OutlineInputBorder()),
                  maxLines: 2,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text("İPTAL")),
            ElevatedButton(
              onPressed: () async {
                double m = double.tryParse(tutarC.text.replaceAll(',', '.')) ?? 0;
                if (m > 0) {
                  // --- KRİTİK DÜZELTME BURADA ---
                  await DatabaseHelper.instance.tarimfirmaHareketiEkle({
                    'cari_kod': widget.cariKod,
                    'islem_tipi': islemTipi, // 'tip' değil, 'islem_tipi' olarak mühürledik!
                    'urun_adi': aciklamaC.text.trim().isEmpty
                        ? "$islemTipi İŞLEMİ"
                        : aciklamaC.text.trim(),
                    'tutar': m,
                    'tarih': tarihC.text,
                    'is_synced': 0, // Senkronizasyon için şart
                    'firebase_id': "O-${DateTime.now().millisecondsSinceEpoch}", // Çift kaydı önleyen mühür
                  });

                  if (!mounted) return;
                  Navigator.pop(context);
                  setState(() => _refreshKey = UniqueKey());
                }
              },
              child: const Text("KAYDET"),
            ),
          ],
        ),
      ),
    );
  }
}
