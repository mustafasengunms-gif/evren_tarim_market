import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../db/database_helper.dart'; // Yolunu kontrol et abi

class FirmaEkstreSayfasi extends StatefulWidget {
  final int firmaId;
  final String firmaAd;

  const FirmaEkstreSayfasi({super.key, required this.firmaId, required this.firmaAd});

  @override
  State<FirmaEkstreSayfasi> createState() => _FirmaEkstreSayfasiState();
}

class _FirmaEkstreSayfasiState extends State<FirmaEkstreSayfasi> {
  // Sayfayı yenilemek için kullanacağımız anahtar
  Key _refreshKey = UniqueKey();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: Text("${widget.firmaAd} Ekstresi"),
        backgroundColor: Colors.indigo[900],
        foregroundColor: Colors.white,
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        key: _refreshKey,
        future: DatabaseHelper.instance.firmaEkstresiGetir(widget.firmaId),
        builder: (context, snap) {
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final hareketler = snap.data!;

          // 1. TOPLAM BAKİYE HESAPLAMA
          double netBakiye = 0;
          for (var h in hareketler) {
            double tutar = double.tryParse(h['tutar']?.toString() ?? "0") ?? 0.0;
            bool isOdeme = h['tip'] == "ÖDEME" || h['tip'] == "ODEME";
            if (isOdeme) {
              netBakiye -= tutar;
            } else {
              netBakiye += tutar;
            }
          }

          if (hareketler.isEmpty) return const Center(child: Text("Henüz bir hareket yok."));

          return Column(
            children: [
              // 2. ÜSTTEKİ DİNAMİK BAKİYE KARTI
              Container(
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
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: netBakiye >= 0 ? Colors.red[900] : Colors.green[900],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      "${NumberFormat.currency(locale: 'tr_TR', symbol: '').format(netBakiye.abs())} ₺",
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w900, // Hatayı düzelttik
                        color: netBakiye >= 0 ? Colors.red[900] : Colors.green[900],
                      ),
                    ),
                  ],
                ),
              ),

              // 3. LİSTE KISMI
              Expanded(
                child: ListView.builder(
                  itemCount: hareketler.length,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  itemBuilder: (context, i) {
                    final h = hareketler[i];
                    double adet = double.tryParse(h['adet']?.toString() ?? "1") ?? 1.0;
                    double toplamTutar = double.tryParse(h['tutar']?.toString() ?? "0") ?? 0.0;
                    double birimFiyat = adet > 0 ? toplamTutar / adet : 0;
                    bool isOdeme = h['tip'] == "ÖDEME" || h['tip'] == "ODEME";

                    return Card(
                      elevation: 2,
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: isOdeme ? Colors.green.withOpacity(0.1) : Colors.red.withOpacity(0.1),
                          child: Icon(isOdeme ? Icons.call_made : Icons.call_received, color: isOdeme ? Colors.green : Colors.red),
                        ),
                        title: Text(
                            "${h['urun_adi'] ?? 'İşlem'} ${!isOdeme ? '($adet Adet)' : ''}",
                            style: const TextStyle(fontWeight: FontWeight.bold)
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(h['tarih'] ?? ""),
                            if (!isOdeme) Text("Birim Fiyat: ${NumberFormat.currency(locale: 'tr_TR', symbol: '').format(birimFiyat)} ₺"),
                          ],
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              "${NumberFormat.currency(locale: 'tr_TR', symbol: '').format(toplamTutar)} ₺",
                              style: TextStyle(
                                color: isOdeme ? Colors.green[700] : Colors.red[700],
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(width: 8),
                            IconButton(
                              icon: const Icon(Icons.delete_outline, color: Colors.grey),
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
        // Başına async koyduk ve sonuna .then ekledik
        onPressed: () async {
          await _yeniOdemeDialog(context);
          setState(() {
            _refreshKey = UniqueKey(); // Dialog kapanınca sayfayı yeniler
          });
        },
        label: const Text("ÖDEME / TAHSİLAT GİR"),
        icon: const Icon(Icons.add_card),
        backgroundColor: Colors.red[900],
      ),
    );
  }

  // --- SİLME DİALOGU ---
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
              await DatabaseHelper.instance.firmaHareketiSil(
                h['id'],
                widget.firmaId,
                double.tryParse(h['tutar'].toString()) ?? 0.0,
                h['tip'],
              );
              Navigator.pop(c);
              setState(() => _refreshKey = UniqueKey());
            },
            child: const Text("EVET, SİL"),
          ),
        ],
      ),
    );
  }

  // 1. ÖNCE HATALI OLAN _input FONKSİYONUNU DÜZELTELİM
  Widget _input(TextEditingController c, String l, {TextInputType keyboard = TextInputType.text, int lines = 1}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextField(
        controller: c,
        keyboardType: keyboard,
        maxLines: lines, // Artık hata vermeyecek
        decoration: InputDecoration(
          labelText: l,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }

// 2. SENİN PAYLAŞTIĞIN DOĞRU MANTIKLA (ÖDEME = EKSİ) ÇALIŞAN DİALOG
  Future<void> _yeniOdemeDialog(BuildContext context) async {
    final tutarC = TextEditingController();
    final aciklamaC = TextEditingController();
    final tarihC = TextEditingController(text: DateFormat('dd.MM.yyyy').format(DateTime.now()));
    String kanal = "NAKİT";
    String islemTipi = "ÖDEME"; // Varsayılan Ödeme

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setS) => AlertDialog(
          backgroundColor: Colors.grey[100],
          title: Container(
            padding: const EdgeInsets.all(10),
            // Seninkine uygun: Ödeme yeşil, Mal alımı kırmızı
            color: islemTipi == "ÖDEME" ? Colors.green[800] : Colors.red[900],
            child: Text(
                islemTipi == "ÖDEME" ? "ÖDEME YAP / TAHSİLAT" : "MAL ALIMI / BORÇ YAZ",
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)
            ),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  value: islemTipi,
                  decoration: InputDecoration(
                    labelText: "İşlem Türü",
                    border: const OutlineInputBorder(),
                    labelStyle: TextStyle(color: islemTipi == "ÖDEME" ? Colors.green[800] : Colors.red[900]),
                  ),
                  items: const [
                    DropdownMenuItem(
                        value: "ÖDEME",
                        child: Text("PARA ÖDEDİM (Bakiyeden Düş)", style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold))
                    ),
                    DropdownMenuItem(
                        value: "ALACAK", // Veritabanında mal alımına karşılık gelen tip
                        child: Text("MAL ALDIM (Bakiyeye Ekle)", style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold))
                    ),
                  ],
                  onChanged: (v) => setS(() => islemTipi = v!),
                ),
                const SizedBox(height: 10),
                _input(tutarC, "Tutar (₺)", keyboard: TextInputType.number),
                const SizedBox(height: 10),
                _input(tarihC, "Tarih"),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  value: kanal,
                  decoration: const InputDecoration(labelText: "Ödeme Kanalı", border: OutlineInputBorder()),
                  items: ["NAKİT", "EFT/HAVALE", "ÇEK", "SENET", "AÇIK HESAP"]
                      .map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                  onChanged: (v) => setS(() => kanal = v!),
                ),
                const SizedBox(height: 10),
                _input(aciklamaC, "Açıklama (Opsiyonel)", lines: 2),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: Text("İPTAL", style: TextStyle(color: Colors.grey[700]))),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: islemTipi == "ÖDEME" ? Colors.green[800] : Colors.red[900],
                foregroundColor: Colors.white,
              ),
              onPressed: () async {
                double m = double.tryParse(tutarC.text.replaceAll(',', '.')) ?? 0;
                if (m > 0) {
                  // 1. Hareketi ekle (Senin döküm sayfan bunu okuyor)
                  await DatabaseHelper.instance.firmaHareketiEkle({
                    'firma_id': widget.firmaId,
                    'tip': islemTipi,
                    'urun_adi': "$kanal: ${aciklamaC.text.trim()}",
                    'tutar': m,
                    'tarih': tarihC.text,
                  });

                  // 2. SENİN MANTIĞININ TAM KARŞILIĞI:
                  // Dökümünde (netBakiye) ÖDEME ise netBakiye -= tutar diyorsun.
                  // O yüzden veritabanı ana bakiyesini de aynı şekilde güncelliyoruz.
                  double mGuncel = (islemTipi == "ÖDEME") ? -m : m;

                  await DatabaseHelper.instance.firmaBakiyeGuncelle(widget.firmaId, mGuncel);

                  Navigator.pop(context);
                  // Ekranı senin FloatingActionButton'daki mantıkla yenileyecek
                  setState(() => _refreshKey = UniqueKey());
                }
              },
              child: Text(islemTipi == "ÖDEME" ? "BAKİYEDEN DÜŞ" : "BORCA EKLE"),
            ),
          ],
        ),
      ),
    );
  }
}