import 'package:flutter/material.dart';
import 'package:intl/intl.dart'; // 🔥 TL Formatı için şart
import '../db/database_helper.dart';

Future<void> hizliSecimDialog({
  required BuildContext context,
  required String tip,
  List<Map<String, dynamic>>? musteriler,
  required Function(Map<String, dynamic> musteri, String satisTipi) onSecim,
}) async {
  String secilenSatisTipi = "AÇIK HESAP";
  List<Map<String, dynamic>> tumMusteriler = List.from(musteriler ?? []);
  String aramaKelimesi = "";
  bool isLoading = false;
  bool tapLock = false;

  // 🔥 PARA FORMATI (0.00 ₺ şeklinde gösterir)
  final tlFormat = NumberFormat.currency(locale: 'tr_TR', symbol: '₺', decimalDigits: 2);

  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (c) {
      return StatefulBuilder(
        builder: (context, setModalState) {

          Future<void> loadData() async {
            if (isLoading) return;
            isLoading = true;
            final liste = await DatabaseHelper.instance.musteriListesiGetir();
            if (context.mounted) {
              setModalState(() {
                tumMusteriler = List.from(liste);
              });
            }
            isLoading = false;
          }

          if (tumMusteriler.isEmpty) {
            loadData();
          }

          final filtreliListe = tumMusteriler.where((m) {
            final ad = (m['ad'] ?? "").toString().toLowerCase();
            final tc = (m['tc'] ?? "").toString();
            return ad.contains(aramaKelimesi.toLowerCase()) || tc.contains(aramaKelimesi);
          }).toList();

          return SizedBox(
            height: MediaQuery.of(context).size.height * 0.85, // Biraz daha yükselttim
            child: Column(
              children: [
                const SizedBox(height: 12),
                Container(width: 50, height: 5, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(10))),

                Padding(
                  padding: const EdgeInsets.all(18.0),
                  child: Text(
                    "$tip İÇİN MÜŞTERİ SEÇİN",
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.blue[900]),
                  ),
                ),

                // ARAMA
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: "İsim veya TC ile ara...",
                      prefixIcon: const Icon(Icons.search),
                      filled: true,
                      fillColor: Colors.grey[100],
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none),
                    ),
                    onChanged: (v) => setModalState(() => aramaKelimesi = v),
                  ),
                ),

                // SATIŞ TİPİ SEÇİMİ
                if (tip == "SATIŞ")
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 15, 20, 0),
                    child: DropdownButtonFormField<String>(
                      value: secilenSatisTipi,
                      items: const ["PEŞİN", "VADELİ", "AÇIK HESAP", "TAKSİTLİ"]
                          .map((e) => DropdownMenuItem(value: e, child: Text(e, style: const TextStyle(fontWeight: FontWeight.bold))))
                          .toList(),
                      onChanged: (v) => setModalState(() => secilenSatisTipi = v!),
                      decoration: InputDecoration(
                        labelText: "İşlem Tipi",
                        filled: true,
                        fillColor: Colors.blue[50],
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),

                const Divider(height: 30),

                // MÜŞTERİ LİSTESİ
                Expanded(
                  child: filtreliListe.isEmpty
                      ? const Center(child: Text("Müşteri bulunamadı."))
                      : ListView.builder(
                    itemCount: filtreliListe.length,
                    itemBuilder: (context, i) {
                      final m = filtreliListe[i];
                      final String netId = (m['id'] ?? m['tc'] ?? "").toString().trim();
                      double bakiye = double.tryParse(m['bakiye']?.toString() ?? '0.0') ?? 0.0;

                      return Card(
                        margin: const EdgeInsets.symmetric(horizontal: 15, vertical: 5),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(color: Colors.grey[200]!),
                        ),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: bakiye > 0 ? Colors.red[50] : Colors.green[50],
                            child: Icon(Icons.person, color: bakiye > 0 ? Colors.red : Colors.green),
                          ),
                          title: Text(
                            (m['ad'] ?? "İSİMSİZ").toString().toUpperCase(),
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                          ),
                          subtitle: Text(
                            tlFormat.format(bakiye),
                            style: TextStyle(
                              color: bakiye > 0 ? Colors.red : Colors.green[700],
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          // 🔥 YANDAKİ BUTONLAR BURADA
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Eğer tip Ekstre ise direkt oraya uçuracak ikon
                              if (tip == "EKSTRE")
                                const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),

                              // Hızlı Silme veya Detay ikonu (İstersen ekleyebilirsin)
                              if (tip == "SATIŞ")
                                const Icon(Icons.shopping_cart_checkout, color: Colors.blue),
                            ],
                          ),
                          onTap: () async {
                            if (tapLock) return;
                            tapLock = true;

                            Navigator.pop(context);

                            final secilenMusteri = Map<String, dynamic>.from(m);
                            secilenMusteri['id'] = netId;
                            secilenMusteri['musteriId'] = netId;

                            onSecim(secilenMusteri, secilenSatisTipi);

                            await Future.delayed(const Duration(milliseconds: 300));
                            tapLock = false;
                          },
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
      );
    },
  );
}