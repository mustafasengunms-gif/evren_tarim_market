import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:cloud_firestore/cloud_firestore.dart';

class PersonelPaneli extends StatefulWidget {
  const PersonelPaneli({super.key});

  @override
  State<PersonelPaneli> createState() => _PersonelPaneliState();
}

class _PersonelPaneliState extends State<PersonelPaneli> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  List<Map<String, dynamic>> _personeller = [];
  bool _yukleniyor = true;
  final trFormat = NumberFormat.currency(locale: 'tr_TR', symbol: '₺', decimalDigits: 0);

  double safeDouble(dynamic v) {
    if (v == null) return 0;
    if (v is int) return v.toDouble();
    if (v is double) return v;
    return double.tryParse(v.toString()) ?? 0;
  }

  String formatPara(dynamic v) {
    double val = safeDouble(v);
    return trFormat.format(val);
  }

  @override
  void initState() {
    super.initState();
    _verileriYukle();
  }

  /// 🔄 1. Firebase Firestore'dan Personel Listesini Çekme (DÜZELTİLDİ)
  Future<void> _verileriYukle() async {
    if (!mounted) return;
    setState(() => _yukleniyor = true);

    try {
      // 🔥 DOĞRU KOLEKSİYON: 'personel' (Resim 1'deki gibi)
      QuerySnapshot querySnapshot = await _firestore.collection('personel').get();

      final List<Map<String, dynamic>> veriler = querySnapshot.docs.map((doc) {
        Map<String, dynamic> data = doc.data() as Map<String, dynamic>;

        // 🔥 Firestore'daki büyük 'İD' alanını kodun anlayacağı küçük 'id'ye eşitliyoruz
        String pId = data['İD'] ?? data['id'] ?? doc.id;
        data['id'] = pId;
        return data;
      }).toList();

      if (mounted) {
        setState(() {
          _personeller = veriler.map((p) {
            return {
              ...p,
              'bakiye': safeDouble(p['bakiye']),
              'maas': safeDouble(p['maas']),
            };
          }).toList();
          _yukleniyor = false;
        });
      }
    } catch (e) {
      debugPrint("Firebase veri yükleme hatası: $e");
      if (mounted) setState(() => _yukleniyor = false);
    }
  }

  double get _aylikMaasYuku => _personeller.fold(0.0, (sum, p) => sum + safeDouble(p['maas']));

  double get _toplamOdenecek => _personeller.fold(0.0, (sum, p) {
    double b = safeDouble(p['bakiye']);
    return b > 0 ? sum + b : sum;
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text("PERSONEL VE FİNANS", style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.blue.shade900,
        foregroundColor: Colors.white,
        centerTitle: true,
      ),
      body: Column(
        children: [
          _ustBilgiPaneli(),
          _aksiyonButonlari(),
          Expanded(
            child: _yukleniyor
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              itemCount: _personeller.length,
              itemBuilder: (context, index) => _personelKarti(_personeller[index]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _ustBilgiPaneli() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
          color: Colors.blue.shade900,
          borderRadius: const BorderRadius.only(bottomLeft: Radius.circular(30), bottomRight: Radius.circular(30))
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _ozetMetin("PERSONEL", "${_personeller.length}"),
          _ozetMetin("AYLIK YÜK", trFormat.format(_aylikMaasYuku)),
          _ozetMetin("ÖDENECEK", trFormat.format(_toplamOdenecek)),
        ],
      ),
    );
  }

  Widget _ozetMetin(String b, String d) => Column(children: [
    Text(b, style: const TextStyle(color: Colors.white60, fontSize: 10)),
    Text(d, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
  ]);

  Widget _aksiyonButonlari() {
    return Padding(
      padding: const EdgeInsets.all(15.0),
      child: Row(
        children: [
          Expanded(child: _ustButon("YENİ EKLE", Icons.person_add, Colors.green.shade700, () => _personelFormu())),
          const SizedBox(width: 10),
          Expanded(child: _ustButon("RAPOR AL", Icons.picture_as_pdf, Colors.red.shade700, () => _pdfRaporYap())),
        ],
      ),
    );
  }

  Widget _ustButon(String l, IconData i, Color c, VoidCallback t) => ElevatedButton.icon(
    onPressed: t, icon: Icon(i, size: 18), label: Text(l),
    style: ElevatedButton.styleFrom(backgroundColor: c, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 12)),
  );

  Widget _personelKarti(Map<String, dynamic> p) {
    double bakiye = safeDouble(p['bakiye']);
    Color durumRengi = bakiye > 0 ? Colors.green.shade700 : (bakiye < 0 ? Colors.red.shade700 : Colors.grey);
    String durumMetni = bakiye > 0 ? "Pers. Alacaklı" : (bakiye < 0 ? "Pers. Borçlu" : "Bakiye Sıfır");

    ImageProvider? profilResmi;
    if (p['foto_yolu'] != null && p['foto_yolu'].toString().isNotEmpty) {
      profilResmi = NetworkImage(p['foto_yolu']);
    }

    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      child: ExpansionTile(
        leading: CircleAvatar(
          backgroundColor: durumRengi.withOpacity(0.1),
          backgroundImage: profilResmi,
          child: profilResmi == null ? Text(p['ad']?[0] ?? "?", style: TextStyle(color: durumRengi, fontWeight: FontWeight.bold)) : null,
        ),
        title: Text(p['ad'] ?? "İsimsiz", style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Row(
          children: [
            Text(trFormat.format(bakiye.abs()), style: TextStyle(color: durumRengi, fontWeight: FontWeight.bold)),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(color: durumRengi.withOpacity(0.1), borderRadius: BorderRadius.circular(5)),
              child: Text(durumMetni, style: TextStyle(fontSize: 10, color: durumRengi, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            color: Colors.grey.shade50,
            child: Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                _kucukButon("ÖDEME YAP", Icons.outbound, Colors.red, () => _hareketDialog(p, "ÖDEME/AVANS")),
                _kucukButon("MAAŞ İŞLE", Icons.assignment_turned_in, Colors.green, () => _hareketDialog(p, "MAAŞ TAHAKKUK")),
                _kucukButon("EKSTRE", Icons.description, Colors.blue, () => _ekstreGoster(p)),
                _kucukButon("FOTO", Icons.camera_alt, Colors.purple, () => _fotoEkle(p)),
                _kucukButon("DÜZENLE", Icons.edit, Colors.blueGrey, () => _personelFormu(personel: p)),
                _kucukButon("SİL", Icons.delete, Colors.red, () => _silOnay(p)),
              ],
            ),
          )
        ],
      ),
    );
  }

  /// ➕ 2. Firebase Firestore'a Hareket Ekleme ve Bakiye Güncelleme (DÜZELTİLDİ)
  void _hareketDialog(Map<String, dynamic> p, String tur) {
    final tC = TextEditingController(text: tur == "MAAŞ TAHAKKUK" ? (p['maas']?.toString() ?? "") : "");
    final aC = TextEditingController();
    final List<String> aylar = ["OCAK","ŞUBAT","MART","NİSAN","MAYIS","HAZİRAN","TEMMUZ","AĞUSTOS","EYLÜL","EKİM","KASIM","ARALIK"];
    int secilenAyIndex = DateTime.now().month - 1;

    showDialog(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(tur == "MAAŞ TAHAKKUK" ? "MAAŞ İŞLE" : "ÖDEME YAP"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (tur == "MAAŞ TAHAKKUK") ...[
                const Text("Hangi Ayın Maaşı?", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                DropdownButton<int>(
                  isExpanded: true,
                  value: secilenAyIndex,
                  items: List.generate(aylar.length, (i) => DropdownMenuItem(value: i, child: Text(aylar[i]))),
                  onChanged: (v) { if (v != null) setDialogState(() => secilenAyIndex = v); },
                ),
                const SizedBox(height: 10),
              ],
              TextField(
                controller: tC,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: "Tutar", hintText: "0,00 ₺", border: OutlineInputBorder()),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: aC,
                decoration: InputDecoration(
                  labelText: "Açıklama",
                  hintText: tur == "MAAŞ TAHAKKUK" ? "${aylar[secilenAyIndex]} MAAŞI" : "Banka, Elden...",
                  border: const OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: const Text("İPTAL")),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: tur == "MAAŞ TAHAKKUK" ? Colors.green : Colors.red),
              onPressed: () async {
                double tutar = double.tryParse(tC.text) ?? 0;
                if (tutar <= 0) return;

                double netDegisim = (tur == "MAAŞ TAHAKKUK") ? tutar : -tutar;
                String hareketId = const Uuid().v4();
                String pId = p['id'].toString();

                String baslikAciklama = aC.text.isEmpty
                    ? (tur == "MAAŞ TAHAKKUK" ? "${aylar[secilenAyIndex]} MAAŞI" : "ÖDEME")
                    : aC.text.toUpperCase();

                // 🔥 DOĞRU KOLEKSİYON: 'personel_hareketleri' (Resim 2'deki gibi)
                // 🔥 ALAN İSİMLERİ BULUTTAKİ GİBİ TÜRKÇE/UYUMLU AYARLANDI
                await _firestore.collection('personel_hareketleri').doc(hareketId).set({
                  'İD': hareketId,
                  'personel_kimliği': pId,
                  'tarih': DateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS").format(DateTime.now()),
                  'tur': tur,
                  'tutar': tutar,
                  'ay_bilgisi': tur == "MAAŞ TAHAKKUK" ? aylar[secilenAyIndex] : "MAYIS",
                  'açıklama': baslikAciklama,
                  'senkronize_ediliyor': 0
                });

                // 🔥 DOĞRU KOLEKSİYON VE GÜNCELLEME: 'personel'
                await _firestore.collection('personel').doc(pId).update({
                  'bakiye': FieldValue.increment(netDegisim)
                });

                Navigator.pop(c);
                await _verileriYukle();
              },
              child: const Text("KAYDET", style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _kucukButon(String l, IconData i, Color c, VoidCallback t) => InkWell(
    onTap: t,
    child: Container(
      width: 75,
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(color: c.withOpacity(0.1), borderRadius: BorderRadius.circular(10), border: Border.all(color: c.withOpacity(0.3))),
      child: Column(children: [Icon(i, size: 18, color: c), const SizedBox(height: 4), Text(l, style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: c))]),
    ),
  );

  /// 📝 3. Firebase Firestore Personel Ekleme / Güncelleme (DÜZELTİLDİ)
  void _personelFormu({Map<String, dynamic>? personel}) {
    final adC = TextEditingController(text: personel?['ad']);
    final maasC = TextEditingController(text: personel?['maas']?.toString() ?? "");

    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(personel == null ? "YENİ PERSONEL" : "BİLGİLERİ DÜZENLE"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: adC, decoration: const InputDecoration(labelText: "Ad Soyad", border: OutlineInputBorder())),
            const SizedBox(height: 10),
            TextField(controller: maasC, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: "Net Maaş", border: OutlineInputBorder())),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text("İPTAL")),
          ElevatedButton(
            onPressed: () async {
              String pId = personel == null ? const Uuid().v4() : personel['id'].toString();

              final v = {
                'İD': pId, // Buluttaki büyük İD alanı
                'ad': adC.text.toUpperCase(),
                'maas': double.tryParse(maasC.text) ?? 0,
              };

              // 🔥 DOĞRU KOLEKSİYON: 'personel'
              if (personel == null) {
                v['bakiye'] = 0.0;
                v['foto_yolu'] = '';
                v['reklam'] = 'FFV';
                v['senkronize_ediliyor'] = 0;
                await _firestore.collection('personel').doc(pId).set(v);
              } else {
                await _firestore.collection('personel').doc(pId).update(v);
              }
              Navigator.pop(c);
              await _verileriYukle();
            },
            child: const Text("KAYDET"),
          )
        ],
      ),
    );
  }

  /// ❌ 4. Firebase Firestore'dan Personel Silme (DÜZELTİLDİ)
  void _silOnay(Map<String, dynamic> p) {
    showDialog(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text("SİLME ONAYI"),
          content: Text("${p['ad']} personeli tamamen silinecek. Emin misiniz?"),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: const Text("HAYIR")),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () async {
                final String personelId = p['id'].toString();

                // 🔥 DOĞRU KOLEKSİYONLAR temizleniyor
                await _firestore.collection('personel').doc(personelId).delete();

                var hareketlerSorgu = await _firestore.collection('personel_hareketleri')
                    .where('personel_kimliği', isEqualTo: personelId).get();
                for (var doc in hareketlerSorgu.docs) {
                  await doc.reference.delete();
                }

                if (mounted) {
                  Navigator.pop(context);
                  _verileriYukle();
                }
              },
              child: const Text("SİL", style: TextStyle(color: Colors.white)),
            ),
          ],
        )
    );
  }

  /// 📸 5. Web Uyumlu Fotoğraf İşlemi (DÜZELTİLDİ)
  void _fotoEkle(Map<String, dynamic> p) async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery);

    if (image != null) {
      // 🔥 DOĞRU KOLEKSİYON: 'personel'
      await _firestore.collection('personel').doc(p['id'].toString()).update({
        'foto_yolu': image.path
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Fotoğraf güncellendi")));
        await _verileriYukle();
      }
    }
  }

  /// 📊 6. Firebase Firestore'dan Hareketleri (Ekstre) Getirme (DÜZELTİLDİ)
  void _ekstreGoster(Map<String, dynamic> p) async {
    try {
      // 🔥 DOĞRU KOLEKSİYON VE ALAN ADI: 'personel_hareketleri' -> 'personel_kimliği'
      QuerySnapshot hSnapshot = await _firestore.collection('personel_hareketleri')
          .where('personel_kimliği', isEqualTo: p['id'].toString())
          .get();

      List<Map<String, dynamic>> hareketler = hSnapshot.docs.map((doc) => doc.data() as Map<String, dynamic>).toList();

      hareketler.sort((a, b) => b['tarih'].toString().compareTo(a['tarih'].toString()));

      double toplamMaas = 0;
      double toplamOdeme = 0;

      for (var h in hareketler) {
        double tutar = safeDouble(h['tutar']);
        String tur = (h['tur'] ?? "").toString().toUpperCase();
        if (tur.contains("MAAŞ")) {
          toplamMaas += tutar;
        } else {
          toplamOdeme += tutar;
        }
      }

      if (!mounted) return;

      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (context) => Container(
          height: MediaQuery.of(context).size.height * 0.85,
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
          ),
          child: Column(
            children: [
              Container(
                margin: const EdgeInsets.only(top: 10, bottom: 20),
                width: 40, height: 5,
                decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(10)),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(p['ad'].toString().toUpperCase(), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                          const Text("Personel Hesap Özeti", style: TextStyle(color: Colors.grey, fontSize: 13)),
                        ],
                      ),
                    ),
                    IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close, color: Colors.red)),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 15),
                child: Row(
                  children: [
                    _ozetKart("TOPLAM MAAŞ", toplamMaas, Colors.blue.shade900),
                    const SizedBox(width: 10),
                    _ozetKart("TOPLAM ÖDEME", toplamOdeme, Colors.orange.shade800),
                  ],
                ),
              ),
              const Padding(padding: EdgeInsets.all(15.0), child: Divider(thickness: 1)),
              Expanded(
                child: hareketler.isEmpty
                    ? const Center(child: Text("Henüz hareket kaydı bulunamadı."))
                    : ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 15),
                  itemCount: hareketler.length,
                  separatorBuilder: (context, i) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final h = hareketler[i];
                    double tutar = safeDouble(h['tutar']);
                    bool isMaas = h['tur'].toString().toUpperCase().contains("MAAŞ");

                    // 🔥 Buluttaki Türkçe 'açıklama' anahtarını karşılıyoruz
                    String hAciklama = h['açıklama'] ?? h['aciklama'] ?? "Açıklama yok";

                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      leading: CircleAvatar(
                        backgroundColor: isMaas ? Colors.green.withOpacity(0.1) : Colors.red.withOpacity(0.1),
                        child: Icon(isMaas ? Icons.arrow_upward : Icons.arrow_downward, color: isMaas ? Colors.green : Colors.red, size: 20),
                      ),
                      title: Text(h['tur'].toString(), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(hAciklama, style: const TextStyle(fontSize: 12)),
                          if (h['ay_bilgisi'] != null)
                            Text("Dönem: ${h['ay_bilgisi']}", style: TextStyle(fontSize: 10, color: Colors.blue.shade700)),
                          Text(h['tarih']?.toString().substring(0, 10) ?? "", style: const TextStyle(fontSize: 10, color: Colors.grey)),
                        ],
                      ),
                      trailing: Text(
                        formatPara(tutar),
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: isMaas ? Colors.green.shade700 : Colors.red.shade700,
                        ),
                      ),
                    );
                  },
                ),
              ),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(color: Colors.grey.shade100, border: Border(top: BorderSide(color: Colors.grey.shade300))),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text("GÜNCEL BAKİYE:", style: TextStyle(fontWeight: FontWeight.bold)),
                    Text(formatPara(safeDouble(p['bakiye'])),
                        style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: safeDouble(p['bakiye']) >= 0 ? Colors.green.shade800 : Colors.red.shade800
                        )
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    } catch (e) {
      debugPrint("EKSTRE HATA: $e");
    }
  }

  Widget _ozetKart(String baslik, double deger, Color renk) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: renk.withOpacity(0.05),
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: renk.withOpacity(0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(baslik, style: TextStyle(color: renk, fontSize: 10, fontWeight: FontWeight.bold)),
            const SizedBox(height: 5),
            FittedBox(
              child: Text(formatPara(deger), style: TextStyle(color: renk, fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  /// 📄 7. Web Uyumlu PDF Raporu Oluşturma (DÜZELTİLDİ)
  Future<void> _pdfRaporYap() async {
    try {
      final pdf = pw.Document();
      final font = await PdfGoogleFonts.robotoRegular();
      final boldFont = await PdfGoogleFonts.robotoBold();

      String f(dynamic d) => NumberFormat.currency(locale: 'tr_TR', symbol: '₺', decimalDigits: 2).format(safeDouble(d));

      pw.MemoryImage? logo;
      try {
        final ByteData bytes = await rootBundle.load('assets/images/logo.png');
        logo = pw.MemoryImage(bytes.buffer.asUint8List());
      } catch (_) {}

      Map<String, List<List<String>>> tumEkstreler = {};

      for (var p in _personeller) {
        String pId = p['id'].toString();

        // 🔥 DOĞRU KOLEKSİYON: 'personel_hareketleri' -> 'personel_kimliği'
        QuerySnapshot hSnapshot = await _firestore.collection('personel_hareketleri')
            .where('personel_kimliği', isEqualTo: pId).get();

        List<Map<String, dynamic>> hareketler = hSnapshot.docs.map((doc) => doc.data() as Map<String, dynamic>).toList();

        List<List<String>> personelTabloData = [["TARİH", "İŞLEM", "AÇIKLAMA", "TUTAR"]];

        if (hareketler.isEmpty) {
          personelTabloData.add(["-", "-", "HAREKET YOK", "0.00"]);
        } else {
          for (var h in hareketler) {
            double tutar = safeDouble(h['tutar']);
            String tarih = h['tarih'] != null ? h['tarih'].toString().substring(0, 10) : "-";
            String hAciklama = h['açıklama'] ?? h['aciklama'] ?? "";
            personelTabloData.add([tarih, h['tur'].toString().toUpperCase(), hAciklama, f(tutar)]);
          }
        }
        tumEkstreler[pId] = personelTabloData;
      }

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(25),
          header: (context) => pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Row(children: [
                if (logo != null) pw.Container(width: 40, height: 40, child: pw.Image(logo)),
                pw.SizedBox(width: 10),
                pw.Text("EVREN TARIM - DETAYLI PERSONEL EKSTRESİ", style: pw.TextStyle(font: boldFont, fontSize: 14)),
              ]),
              pw.Text(DateFormat('dd.MM.yyyy').format(DateTime.now()), style: pw.TextStyle(font: font, fontSize: 10)),
            ],
          ),
          build: (context) {
            List<pw.Widget> widgets = [];
            for (var p in _personeller) {
              String pId = p['id'].toString();
              widgets.add(pw.SizedBox(height: 15));
              widgets.add(
                pw.Container(
                  padding: const pw.EdgeInsets.all(6),
                  decoration: const pw.BoxDecoration(color: PdfColors.grey200, border: pw.Border(left: pw.BorderSide(color: PdfColors.blue900, width: 3))),
                  child: pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text("PERSONEL: ${p['ad'].toString().toUpperCase()}", style: pw.TextStyle(font: boldFont, fontSize: 10)),
                      pw.Text("GÜNCEL BAKİYE: ${f(p['bakiye'])}", style: pw.TextStyle(font: boldFont, fontSize: 10)),
                    ],
                  ),
                ),
              );

              widgets.add(
                pw.TableHelper.fromTextArray(
                  data: tumEkstreler[pId]!,
                  cellStyle: pw.TextStyle(font: font, fontSize: 8),
                  headerStyle: pw.TextStyle(font: boldFont, fontSize: 8, color: PdfColors.white),
                  headerDecoration: const pw.BoxDecoration(color: PdfColors.blueGrey800),
                  columnWidths: {0: const pw.FixedColumnWidth(60), 1: const pw.FixedColumnWidth(80), 2: const pw.FlexColumnWidth(), 3: const pw.FixedColumnWidth(70)},
                  cellAlignments: {3: pw.Alignment.centerRight},
                ),
              );
            }
            return widgets;
          },
        ),
      );

      if (!mounted) return;

      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => Scaffold(
            appBar: AppBar(title: const Text("PERSONEL EKSTRE RAPORU")),
            body: PdfPreview(
              build: (format) => pdf.save(),
            ),
          ),
        ),
      );
    } catch (e) {
      debugPrint("PDF HATA: $e");
    }
  }
}