import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../db/database_helper.dart';
import '../utils/pdf_helper.dart';

class TeslimatTakipPaneli extends StatefulWidget {
  const TeslimatTakipPaneli({super.key});

  @override
  State<TeslimatTakipPaneli> createState() =>
      _TeslimatTakipPaneliState();
}

class _TeslimatTakipPaneliState
    extends State<TeslimatTakipPaneli> {

  List<Map<String, dynamic>> _tumHareketler = [];
  List<Map<String, dynamic>> _filtreliHareketler = [];

  String _seciliFiltre = 'TESLİM EDİLMEDİ';

  final formatTR = NumberFormat.currency(
    locale: 'tr_TR',
    symbol: 'TL',
    decimalDigits: 2,
  );

  @override
  void initState() {
    super.initState();
    _verileriGetir();
  }

  Future<void> _verileriGetir() async {

    try {

      print("☁️ FIREBASE MUSTERI_HAREKETLERI ÇEKİLİYOR");

      final snapshot = await FirebaseFirestore.instance
          .collection('musteri_hareketleri')
          .where('islem', whereIn: ['SATIS', 'SATIŞ'])
          .get();

      List<Map<String, dynamic>> veriler = [];

      for (var doc in snapshot.docs) {

        Map<String, dynamic> data = doc.data();

        data['id'] = doc.id;

        veriler.add(data);
      }

      // TARİHE GÖRE SIRALA
      veriler.sort((a, b) {

        String ta =
        (a['tarih'] ?? '').toString();

        String tb =
        (b['tarih'] ?? '').toString();

        return tb.compareTo(ta);
      });

      if (mounted) {

        setState(() {

          _tumHareketler = veriler;

          _filtrele();
        });
      }

      print("✅ FIREBASE VERİ SAYISI: ${veriler.length}");

    } catch (e) {

      print("🚨 FIREBASE VERİ ÇEKME HATASI: $e");

      if (mounted) {

        ScaffoldMessenger.of(context)
            .showSnackBar(

          SnackBar(

            content: Text(
              "Veriler yüklenemedi: $e",
            ),

            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _filtrele() {

    setState(() {

      _filtreliHareketler =
          _tumHareketler.where((hareket) {

            final durum =
                hareket['teslim_durumu'] ??
                    'TESLİM EDİLMEDİ';

            return durum == _seciliFiltre;

          }).toList();
    });
  }

  Future<void> _durumDegistir(
      Map<String, dynamic> hareket) async {

    try {

      final db =
      await DatabaseHelper.instance.database;

      String mevcutDurum =
          hareket['teslim_durumu'] ??
              'TESLİM EDİLMEDİ';

      String yeniDurum =
      mevcutDurum == 'TESLİM EDİLMEDİ'
          ? 'TESLİM EDİLDİ'
          : 'TESLİM EDİLMEDİ';

      String docId =
      hareket['id'].toString();

      print("🔄 DURUM DEĞİŞİYOR");
      print("🆔 DOC ID: $docId");
      print("🆕 YENİ DURUM: $yeniDurum");

      // =====================================================
      // 1. SQLITE GÜNCELLE
      // =====================================================

      try {

        await db.update(

          'musteri_hareketleri',

          {
            'teslim_durumu': yeniDurum,
            'is_synced': 0,
          },

          where: 'id = ?',

          whereArgs: [docId],
        );

        print("✅ SQLITE GÜNCELLENDİ");

      } catch (e) {

        print("🚨 SQLITE HATASI: $e");
      }

      // =====================================================
      // 2. FIREBASE MUSTERI_HAREKETLERI
      // =====================================================

      try {

        await FirebaseFirestore.instance
            .collection('musteri_hareketleri')
            .doc(docId)
            .set({

          'teslim_durumu': yeniDurum,

          'guncelleme_tarihi':
          FieldValue.serverTimestamp(),

        }, SetOptions(merge: true));

        print("✅ FIREBASE musteri_hareketleri GÜNCELLENDİ");

      } catch (e) {

        print("🚨 musteri_hareketleri HATASI: $e");
      }

      // =====================================================
      // 3. FIREBASE SATISLAR
      // =====================================================

      try {

        await FirebaseFirestore.instance
            .collection('satislar')
            .doc(docId)
            .set({

          'teslim_durumu': yeniDurum,

          'guncelleme_tarihi':
          FieldValue.serverTimestamp(),

        }, SetOptions(merge: true));

        print("✅ FIREBASE satislar GÜNCELLENDİ");

      } catch (e) {

        print("🚨 satislar HATASI: $e");
      }

      // =====================================================
      // 4. LOCAL LIST GÜNCELLE
      // =====================================================

      hareket['teslim_durumu'] = yeniDurum;

      // =====================================================
      // 5. EKRANI TAZELE
      // =====================================================

      await _verileriGetir();

      // =====================================================
      // 6. MESAJ
      // =====================================================

      if (mounted) {

        ScaffoldMessenger.of(context)
            .showSnackBar(

          SnackBar(

            content: Text(
              "Durum '$yeniDurum' olarak güncellendi.",
            ),

            backgroundColor: Colors.green,
          ),
        );
      }

    } catch (e) {

      print("🚨 GENEL HATA: $e");

      if (mounted) {

        ScaffoldMessenger.of(context)
            .showSnackBar(

          SnackBar(

            content: Text(
              "Durum güncellenirken hata oluştu: $e",
            ),

            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {

    return Scaffold(

      appBar: AppBar(

        title: const Text(
            "Emanet / Teslimat Takip"),

        backgroundColor: Colors.deepOrange,

        foregroundColor: Colors.white,

        actions: [

          // ==================================================
          // PDF RAPOR
          // ==================================================

          IconButton(

            icon: const Icon(
              Icons.picture_as_pdf,
              size: 28,
            ),

            tooltip: "PDF Raporu Al",

            onPressed: () async {

              if (_filtreliHareketler.isEmpty) {

                ScaffoldMessenger.of(context)
                    .showSnackBar(

                  const SnackBar(
                    content: Text(
                        "Yazdırılacak veri bulunamadı!"),
                  ),
                );

                return;
              }

              await PdfHelper
                  .teslimatRaporuGoster(

                context,

                _filtreliHareketler,

                _seciliFiltre,
              );
            },
          ),

          const SizedBox(width: 10),
        ],
      ),

      body: Column(

        children: [

          // ==================================================
          // FİLTRE BUTONLARI
          // ==================================================

          Padding(

            padding: const EdgeInsets.all(10.0),

            child: Row(

              mainAxisAlignment:
              MainAxisAlignment.spaceEvenly,

              children: [

                _filtreButon(
                  'TESLİM EDİLMEDİ',
                  Colors.orange,
                ),

                _filtreButon(
                  'TESLİM EDİLDİ',
                  Colors.green,
                ),
              ],
            ),
          ),

          // ==================================================
          // SAYAÇ
          // ==================================================

          Container(

            width: double.infinity,

            margin: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 5,
            ),

            padding: const EdgeInsets.all(15),

            decoration: BoxDecoration(

              color:
              _seciliFiltre ==
                  'TESLİM EDİLMEDİ'

                  ? Colors.orange
                  .withOpacity(0.1)

                  : Colors.green
                  .withOpacity(0.1),

              borderRadius:
              BorderRadius.circular(10),

              border: Border.all(

                color:
                _seciliFiltre ==
                    'TESLİM EDİLMEDİ'

                    ? Colors.orange
                    : Colors.green,
              ),
            ),

            child: Text(

              "$_seciliFiltre Durumundaki Kayıtlar (${_filtreliHareketler.length} Adet)",

              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),

              textAlign: TextAlign.center,
            ),
          ),

          // ==================================================
          // LİSTE
          // ==================================================

          Expanded(

            child: _filtreliHareketler.isEmpty

                ? const Center(
              child: Text(
                "Bu kategoride herhangi bir kayıt bulunamadı.",
              ),
            )

                : ListView.builder(

              itemCount:
              _filtreliHareketler.length,

              itemBuilder:
                  (context, index) {

                final h =
                _filtreliHareketler[index];

                return Card(

                  margin:
                  const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),

                  elevation: 2,

                  child: ListTile(

                    title: Text(

                      h['musteri_ad'] ??
                          "Bilinmeyen Müşteri",

                      style: const TextStyle(
                        fontWeight:
                        FontWeight.bold,
                      ),
                    ),

                    subtitle: Column(

                      crossAxisAlignment:
                      CrossAxisAlignment.start,

                      children: [

                        const SizedBox(height: 4),

                        Text(
                          "Açıklama: ${h['aciklama'] ?? ''}",
                        ),

                        Text(
                          "Tarih: ${h['tarih'] ?? ''}",
                        ),

                        Text(

                          "Tutar: ${formatTR.format(h['tutar'] ?? h['toplam_tutar'] ?? 0)}",

                          style: const TextStyle(
                            fontWeight:
                            FontWeight.bold,
                            color: Colors.blueGrey,
                          ),
                        ),
                      ],
                    ),

                    trailing: ElevatedButton(

                      style:
                      ElevatedButton.styleFrom(

                        backgroundColor:

                        h['teslim_durumu'] ==
                            'TESLİM EDİLMEDİ'

                            ? Colors.orange
                            : Colors.green,

                        foregroundColor:
                        Colors.white,
                      ),

                      onPressed: () =>
                          _durumDegistir(h),

                      child: Text(

                        h['teslim_durumu'] ==
                            'TESLİM EDİLMEDİ'

                            ? "Teslim Et"
                            : "Emanete Al",
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _filtreButon(
      String durum,
      Color renk,
      ) {

    bool seciliMi =
        _seciliFiltre == durum;

    return ElevatedButton(

      style:
      ElevatedButton.styleFrom(

        backgroundColor:
        seciliMi
            ? renk
            : Colors.grey[300],

        foregroundColor:
        seciliMi
            ? Colors.white
            : Colors.black87,

        padding:
        const EdgeInsets.symmetric(
          horizontal: 20,
          vertical: 12,
        ),
      ),

      onPressed: () {

        setState(() {

          _seciliFiltre = durum;

          _filtrele();
        });
      },

      child: Text(

        durum,

        style: const TextStyle(
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}