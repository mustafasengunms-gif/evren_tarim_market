import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart'; // Gerekli olabilir
import 'dart:typed_data'; // Uint8List için gerekli
import 'package:flutter/services.dart'; // rootBundle (Logo yükleme) için gerekli
import 'package:evren_tarim_market/models/CekModel.dart';
import 'package:evren_tarim_market/db/database_helper.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../services/firebase_foto_service.dart'; // Bu satırı ekle



class CekSenetSayfasi extends StatefulWidget {
  final List<Map<String, dynamic>> veriler;
  const CekSenetSayfasi({super.key, required this.veriler});

  @override
  State<CekSenetSayfasi> createState() => _CekSenetSayfasiState();
}

class _CekSenetSayfasiState extends State<CekSenetSayfasi> {
  List<CekModel> cekler = [];
  String? seciliFirma;
  CekTipi seciliTip = CekTipi.cek;
  DateTime keside = DateTime.now();
  DateTime vade = DateTime.now().add(const Duration(days: 30));
  final ImagePicker _picker = ImagePicker();
  final TextEditingController _tutarController = TextEditingController();
  final NumberFormat tlFormat = NumberFormat.currency(locale: 'tr_TR', symbol: '₺', decimalDigits: 2);

  List<String> get mevcutFirmalar => widget.veriler.map((f) => f['ad'].toString()).toList();

  @override
  void initState() {
    super.initState();
    _cekleriYukle();
  }

  Future<void> _cekleriYukle() async {
    final veri = await DatabaseHelper.instance.getCekler();
    setState(() {
      cekler = veri;
    });
  }

  Future<void> refreshCekler() async => _cekleriYukle();

  Future<void> _fotoGuncelle(int index) async {
    try {
      final XFile? image = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 50,
      );

      if (image == null) return; // Kullanıcı iptal ettiyse çık

      var cek = cekler[index];
      print("📸 Fotoğraf seçildi: ${image.path}"); // DEBUG 1

      showDialog(context: context, barrierDismissible: false, builder: (c) => const Center(child: CircularProgressIndicator()));

      // --- 1. FIREBASE STORAGE'A YÜKLE ---
      // Buraya dikkat: FotoKategori.cek_senetler'in karşılığı servis dosyasında "cek_senetler" olmalı
      String? bulutUrl = await FirebaseFotoService().fotoYukle(
          FotoKategori.cek_senetler,
          File(image.path)
      );

      print("☁️ Firebase'den dönen URL: $bulutUrl"); // DEBUG 2

      if (bulutUrl != null && bulutUrl.isNotEmpty) {
        // --- 2. VERİTABANLARINI GÜNCELLE ---
        await DatabaseHelper.instance.cekResimGuncelle(cek.id, bulutUrl);

        await FirebaseFirestore.instance
            .collection('cekler')
            .doc(cek.id.toString())
            .update({'resimYolu': bulutUrl});

        if (mounted) Navigator.pop(context);
        await refreshCekler();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Fotoğraf Firebase'e uçtu! ✅"), backgroundColor: Colors.green),
          );
        }
      } else {
        if (mounted) Navigator.pop(context);
        // Eğer buraya düşüyorsa FirebaseFotoService içinde bir sorun var demektir
        print("❌ HATA: bulutUrl BOŞ DÖNDÜ!");
        throw "Firebase yükleme yaptı ama link vermedi!";
      }
    } catch (e) {
      debugPrint("🔥 FOTO HATASI: $e");
      if (mounted) {
        if(Navigator.canPop(context)) Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Hata: $e"), backgroundColor: Colors.red));
      }
    }
  }

  Future<void> _cekSil(int id) async {
    await DatabaseHelper.instance.cekSil(id);
    await FirebaseFirestore.instance.collection('cekler').doc(id.toString()).delete();
    refreshCekler();
  }

  Future<void> _pdfRaporuOlustur() async {
    // 1. Loading göster
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final pdf = pw.Document();
      // Fontları hafızaya alalım
      final font = await PdfGoogleFonts.robotoRegular();
      final boldFont = await PdfGoogleFonts.robotoBold();

      // Logo yükleme (assets/images/logo.png klasöründe dosya olduğundan emin ol abi)
      pw.MemoryImage? logoResmi;
      try {
        final ByteData logoData = await rootBundle.load('assets/images/logo.png');
        logoResmi = pw.MemoryImage(logoData.buffer.asUint8List());
      } catch (e) {
        debugPrint("⚠️ Logo bulunamadı, logosuz devam ediliyor.");
      }

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          theme: pw.ThemeData.withFont(base: font, bold: boldFont),
          build: (pw.Context context) => [
            // BAŞLIK ALANI
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Row(
                  children: [
                    if (logoResmi != null) pw.Image(logoResmi, width: 40, height: 40),
                    pw.SizedBox(width: 10),
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text("EVREN TARIM", style: pw.TextStyle(font: boldFont, fontSize: 18)),
                        pw.Text("Tefenni / BURDUR", style: const pw.TextStyle(fontSize: 9)),
                      ],
                    ),
                  ],
                ),
                pw.Text("CEK/SENET LISTESI", style: pw.TextStyle(font: boldFont)),
              ],
            ),
            pw.Divider(),
            pw.SizedBox(height: 10),

            // TABLO
            pw.TableHelper.fromTextArray(
              headers: ['Firma', 'Vade', 'Tutar'],
              data: cekler.map((c) => [
                c.firmaAd.toUpperCase(),
                DateFormat('dd.MM.yyyy').format(c.vadeTarihi),
                tlFormat.format(c.tutar),
              ]).toList(),
              headerStyle: pw.TextStyle(font: boldFont, color: PdfColors.white),
              headerDecoration: const pw.BoxDecoration(color: PdfColors.black),
              cellHeight: 30,
              cellAlignments: {
                0: pw.Alignment.centerLeft,
                1: pw.Alignment.center,
                2: pw.Alignment.centerRight,
              },
            ),
          ],
        ),
      );

      if (mounted) Navigator.pop(context); // Loading'i kapat

      // Önizleme Ekranına Git
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => Scaffold(
            appBar: AppBar(title: const Text("Yazdır / Paylaş")),
            body: PdfPreview(build: (format) => pdf.save()),
          ),
        ),
      );
    } catch (e) {
      if (mounted) Navigator.pop(context);
      debugPrint("PDF HATASI: $e");
    }
  }

  void _yeniKayitPaneli(BuildContext context, {CekModel? duzenlenecekCek}) {
    if (duzenlenecekCek != null) {
      seciliFirma = duzenlenecekCek.firmaAd;
      seciliTip = duzenlenecekCek.tip;
      _tutarController.text = duzenlenecekCek.tutar.toString();
      keside = duzenlenecekCek.kesideTarihi;
      vade = duzenlenecekCek.vadeTarihi;
    } else {
      _tutarController.clear();
      seciliFirma = null;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom + 20, left: 20, right: 20, top: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text("EVRAK KAYDI", style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 15),
              ToggleButtons(
                borderRadius: BorderRadius.circular(8),
                constraints: const BoxConstraints(minHeight: 40, minWidth: 100),
                isSelected: [seciliTip == CekTipi.cek, seciliTip == CekTipi.senet],
                onPressed: (index) => setModalState(() => seciliTip = index == 0 ? CekTipi.cek : CekTipi.senet),
                children: const [Text("ÇEK"), Text("SENET")],
              ),
              DropdownButtonFormField<String>(
                value: seciliFirma,
                items: mevcutFirmalar.map((f) => DropdownMenuItem(value: f, child: Text(f))).toList(),
                onChanged: (v) => setModalState(() => seciliFirma = v),
                decoration: const InputDecoration(labelText: "Firma"),
              ),
              TextField(controller: _tutarController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: "Tutar", suffixText: "₺")),
              Row(
                children: [
                  Expanded(child: TextButton(onPressed: () async {
                    final d = await showDatePicker(context: context, initialDate: keside, firstDate: DateTime(2020), lastDate: DateTime(2100));
                    if (d != null) setModalState(() => keside = d);
                  }, child: Text("Keşide: ${DateFormat('dd.MM.yy').format(keside)}"))),
                  Expanded(child: TextButton(onPressed: () async {
                    final d = await showDatePicker(context: context, initialDate: vade, firstDate: DateTime(2020), lastDate: DateTime(2100));
                    if (d != null) setModalState(() => vade = d);
                  }, child: Text("Vade: ${DateFormat('dd.MM.yy').format(vade)}"))),
                ],
              ),
              const SizedBox(height: 15),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.black, minimumSize: const Size(double.infinity, 45)),
                onPressed: () async {
                  if (seciliFirma == null || _tutarController.text.isEmpty) return;
                  double? girilenTutar = double.tryParse(_tutarController.text.replaceAll(',', '.'));
                  if (girilenTutar == null) return;

                  final yeniCek = CekModel(
                    id: duzenlenecekCek?.id ?? DateTime.now().millisecondsSinceEpoch,
                    firmaAd: seciliFirma!,
                    tip: seciliTip,
                    kesideTarihi: keside,
                    vadeTarihi: vade,
                    tutar: girilenTutar,
                    durum: duzenlenecekCek?.durum ?? CekDurumu.beklemede,
                    resimYolu: duzenlenecekCek?.resimYolu ?? "",
                  );

                  if (duzenlenecekCek != null) {
                    await DatabaseHelper.instance.cekGuncelle(yeniCek);
                  } else {
                    await DatabaseHelper.instance.cekEkle(yeniCek);
                  }

                  await FirebaseFirestore.instance.collection('cekler').doc(yeniCek.id.toString()).set(yeniCek.toMap());
                  refreshCekler();
                  if (context.mounted) Navigator.pop(context);
                },
                child: const Text("KAYDET", style: TextStyle(color: Color(0xFFFFD700))),
              )
            ],
          ),
        ),
      ),
    );
  }

  Widget _cekKart(int index) {
    var cek = cekler[index];
    Color durumRenk = cek.durum == CekDurumu.odendi
        ? Colors.green
        : (cek.durum == CekDurumu.iptal ? Colors.red : Colors.orange);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      child: Column(
        children: [
          ListTile(
            onTap: () => _yeniKayitPaneli(context, duzenlenecekCek: cek),

            // FOTOĞRAF KÜÇÜK GÖRÜNÜM VE TIKLAYINCA BÜYÜTME
            leading: GestureDetector(
              onTap: () {
                if (cek.resimYolu != null && cek.resimYolu!.isNotEmpty) {
                  showDialog(
                    context: context,
                    builder: (context) => Dialog(
                      backgroundColor: Colors.transparent,
                      insetPadding: const EdgeInsets.all(10),
                      child: Stack(
                        alignment: Alignment.topRight,
                        children: [
                          // BÜYÜK FOTOĞRAF (Akıllı Seçici)
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: cek.resimYolu!.startsWith('http')
                                ? Image.network(cek.resimYolu!, fit: BoxFit.contain) // Buluttan çek
                                : Image.file(File(cek.resimYolu!), fit: BoxFit.contain), // Telefondan çek
                          ),
                          CircleAvatar(
                            backgroundColor: Colors.black54,
                            child: IconButton(
                              icon: const Icon(Icons.close, color: Colors.white),
                              onPressed: () => Navigator.pop(context),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }
              },
              child: (cek.resimYolu != null && cek.resimYolu!.isNotEmpty)
                  ? ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: SizedBox(
                  width: 45,
                  height: 45,
                  child: cek.resimYolu!.startsWith('http')
                      ? Image.network(
                    cek.resimYolu!,
                    fit: BoxFit.cover,
                    loadingBuilder: (c, child, p) => p == null ? child : const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                    errorBuilder: (c, e, s) => const Icon(Icons.broken_image, color: Colors.red),
                  )
                      : Image.file(
                    File(cek.resimYolu!),
                    fit: BoxFit.cover,
                    errorBuilder: (c, e, s) => const Icon(Icons.broken_image, color: Colors.red),
                  ),
                ),
              )
                  : Icon(
                cek.tip == CekTipi.cek ? Icons.confirmation_number_outlined : Icons.description_outlined,
                color: Colors.blueGrey,
              ),
            ),
            title: Text(cek.firmaAd.toUpperCase(),
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            subtitle: Text(
                "Vade: ${DateFormat('dd.MM.yyyy').format(cek.vadeTarihi)}",
                style: const TextStyle(fontSize: 12)),
            trailing: Text(tlFormat.format(cek.tutar),
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          ),
          const Divider(height: 1),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              TextButton.icon(
                  onPressed: () => _fotoGuncelle(index),
                  icon: const Icon(Icons.camera_alt, size: 16),
                  label: const Text("FOTO", style: TextStyle(fontSize: 11))),
              PopupMenuButton<CekDurumu>(
                initialValue: cek.durum,
                onSelected: (yeniDurum) async {
                  await DatabaseHelper.instance.cekDurumGuncelle(cek.id, yeniDurum.name);
                  refreshCekler();
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(value: CekDurumu.beklemede, child: Text("Beklemede")),
                  const PopupMenuItem(value: CekDurumu.odendi, child: Text("Ödendi")),
                  const PopupMenuItem(value: CekDurumu.iptal, child: Text("İptal")),
                ],
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                      color: durumRenk.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(4)),
                  child: Text(cek.durum.name.toUpperCase(),
                      style: TextStyle(
                          fontSize: 11,
                          color: durumRenk,
                          fontWeight: FontWeight.bold)),
                ),
              ),
              IconButton(
                  onPressed: () async {
                    bool? silOnay = await showDialog<bool>(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: const Text("Kayıt Silinecek"),
                          content: const Text("Bu evrak kaydını silmek istediğine emin misin?"),
                          actions: [
                            TextButton(
                                onPressed: () => Navigator.pop(context, false),
                                child: const Text("VAZGEÇ")),
                            TextButton(
                                onPressed: () => Navigator.pop(context, true),
                                child: const Text("SİL",
                                    style: TextStyle(color: Colors.red)))
                          ],
                        ));
                    if (silOnay == true) _cekSil(cek.id);
                  },
                  icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20)),
            ],
          )
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[200],
      appBar: AppBar(
        title: const Text("EVREN TARIM | PORTFÖY"),
        backgroundColor: Colors.black,
        foregroundColor: const Color(0xFFFFD700),
        actions: [IconButton(onPressed: _pdfRaporuOlustur, icon: const Icon(Icons.picture_as_pdf))],
      ),
      body: Column(
        children: [
          _miniOzetPaneli(),
          Expanded(child: cekler.isEmpty ? const Center(child: Text("Kayıtlı evrak bulunamadı.")) : ListView.builder(itemCount: cekler.length, itemBuilder: (context, index) => _cekKart(index))),
        ],
      ),
      floatingActionButton: FloatingActionButton(backgroundColor: Colors.black, onPressed: () => _yeniKayitPaneli(context), child: const Icon(Icons.add, color: Color(0xFFFFD700))),
    );
  }

  Widget _miniOzetPaneli() {
    double toplam = cekler.fold(0, (sum, item) => sum + item.tutar);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
      color: Colors.black,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(children: [const Text("TOPLAM", style: TextStyle(color: Colors.white60, fontSize: 9)), Text(tlFormat.format(toplam), style: const TextStyle(color: Color(0xFFFFD700), fontSize: 13, fontWeight: FontWeight.bold))]),
          Text("ÖDENEN: ${cekler.where((c) => c.durum == CekDurumu.odendi).length}", style: const TextStyle(color: Colors.green, fontSize: 11)),
          Text("BEKLEYEN: ${cekler.where((c) => c.durum == CekDurumu.beklemede).length}", style: const TextStyle(color: Colors.orange, fontSize: 11)),
        ],
      ),
    );
  }
}