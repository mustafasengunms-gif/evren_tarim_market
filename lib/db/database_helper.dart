import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:evren_tarim_market/models/CekModel.dart';
import 'dart:async';
import 'dart:convert';
import 'package:intl/intl.dart';
import 'package:flutter/foundation.dart'; // debugPrint için bu şart!
import 'package:synchronized/synchronized.dart';
import 'dart:io'; // 'File' hatasını çözer
import 'package:path_provider/path_provider.dart'; // 'getApplicationDocumentsDirectory' hatasını çözer
import 'package:uuid/uuid.dart'; // Benzersiz ID üretmek için
import 'package:flutter/foundation.dart' show kIsWeb; // Platform kontrolü için
import 'package:flutter/foundation.dart' show kIsWeb; // Web kontrolü için
import 'package:cloud_firestore/cloud_firestore.dart'; // Firebase için
import 'package:firebase_storage/firebase_storage.dart'; // Web'de resim saklamak için şart
import 'package:image_picker/image_picker.dart';


class DatabaseHelper {
  static const int _databaseVersion = 3;
  static final DatabaseHelper instance = DatabaseHelper._init();

  static Database? _database;
  bool _syncCalisiyor = false;
  StreamSubscription? _cekSub;
  StreamSubscription? _stokSub;
  final _lock = Lock();

  DatabaseHelper._init();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final StreamController<List<dynamic>> _cekController = StreamController.broadcast();

  String newId() {
    return DateTime.now().millisecondsSinceEpoch.toString();
  }

  Future<Database> get database async {
    // Web kontrolü
    if (kIsWeb) {
      throw UnsupportedError("Web platformunda SQLite kullanılamaz.");
    }

    if (_database != null) return _database!;

    return await _lock.synchronized(() async {
      if (_database == null) {
        _database = await _initDB('evren_ticaret.db');
      }
      return _database!;
    });
  }

  Future<Database> _initDB(String filePath) async {
    if (kIsWeb) {
      print("🌐 Web platformu: SQLite devre dışı.");
      // Hata veren fonksiyon yerine direkt Unsupported fırlatıyoruz.
      throw UnsupportedError("Web'de SQLite çalışmaz.");
    }

    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: _databaseVersion,
      onCreate: _createDB,
      onUpgrade: _onUpgrade,
      onOpen: (db) async {
        await _tabloyuOnar(db);
        herSeyiBuluttanIndir();
      },
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
    );
  }

  // ================= ON UPGRADE (SİGORTALI SİSTEM) =================
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    print("🔄 DB VERSİYON YÜKSELTME BAŞLADI: $oldVersion -> $newVersion");

    // 1. ADIM: Tablo yapısını genel olarak onar
    await _tabloyuOnar(db);

    // 2. ADIM: Her tablo için eksik kolonları "tek tek" kontrol et ve ekle
    // Bu yöntemle 'duplicate column' hatası almazsın, varsa atlar yoksa ekler.

    // --- STOK TANIMLARI TABLOSU ---
    await _kolonVarsaEkle(db, 'stok_tanimlari', 'silindi', 'INTEGER DEFAULT 0');
    await _kolonVarsaEkle(db, 'stok_tanimlari', 'updated_at', 'TEXT');
    await _kolonVarsaEkle(db, 'stok_tanimlari', 'is_synced', 'INTEGER DEFAULT 0');

    // --- STOKLAR (HAREKETLER) TABLOSU ---
    await _kolonVarsaEkle(db, 'stoklar', 'durum', 'TEXT DEFAULT "AKTİF"');
    await _kolonVarsaEkle(db, 'stoklar', 'sube', 'TEXT');

    // --- TARIM FİRMA HAREKETLERİ TABLOSU (Hatanın Kaynağı Burasıydı) ---
    await _kolonVarsaEkle(db, 'tarim_firma_hareketleri', 'updated_at', 'TEXT');
    await _kolonVarsaEkle(db, 'tarim_firma_hareketleri', 'islem_tipi', 'TEXT');
    await _kolonVarsaEkle(db, 'tarim_firma_hareketleri', 'tip', 'TEXT');

    print("✅ DB YÜKSELTME VE KOLON KONTROLLERİ TAMAMLANDI.");
  }

// --- YARDIMCI METOD: Kolon Kontrolü ve Ekleme ---
  Future<void> _kolonVarsaEkle(Database db, String tabloAdi, String kolonAdi, String tip) async {
    try {
      var check = await db.rawQuery("PRAGMA table_info($tabloAdi)");
      bool varMi = check.any((c) => c['name'].toString().toLowerCase() == kolonAdi.toLowerCase());

      if (!varMi) {
        await db.execute("ALTER TABLE $tabloAdi ADD COLUMN $kolonAdi $tip");
        print("➕ [KOLON EKLENDİ]: $tabloAdi -> $kolonAdi");
      } else {
        print("ℹ️ [ZATEN VAR]: $tabloAdi -> $kolonAdi");
      }
    } catch (e) {
      print("❌ [KOLON HATASI]: $tabloAdi -> $kolonAdi : $e");
    }
  }

  Future<void> _createDB(Database db, int version) async {
    print("🚀 Veritabanı oluşturuluyor...");
    // Önce tabloları kur, sonra onar!
    await _tabloyuOnar(db);
  }

  Future<void> _tabloyuOnar(Database db) async {
    print("🛠️ VERİTABANI KURULUMU VE TAMİRİ BAŞLADI...");



    await db.execute('''
CREATE TABLE IF NOT EXISTS tarim_firma_hareketleri (
  id TEXT PRIMARY KEY,
  firebase_id TEXT UNIQUE,
  cari_kod TEXT NOT NULL,
  firma_adi TEXT,
  stok_id TEXT,
  ana_stok_id TEXT,
  islem_tipi TEXT,   -- HATA VEREN KOLON BURASI, EKLEDİK
  tip TEXT,          -- Eski kolon da dursun
  urun_adi TEXT,
  tutar REAL DEFAULT 0,
  adet REAL DEFAULT 0,
  tarih TEXT NOT NULL,
  sube TEXT DEFAULT 'TEFENNİ',
  son_guncelleme TEXT,
  updated_at TEXT, 
  is_synced INTEGER DEFAULT 0,
  silindi INTEGER DEFAULT 0
)
''');


    // Bunu kopyala ve noktaların olduğu yerle değiştir
    await db.execute('''
  CREATE TABLE IF NOT EXISTS personel (
    id TEXT PRIMARY KEY,
    firebase_id TEXT UNIQUE,
    ad TEXT NOT NULL,
    gorev TEXT,
    maas REAL DEFAULT 0,
    sgk REAL DEFAULT 0,
    stopaj REAL DEFAULT 0,
    bakiye REAL DEFAULT 0,
    foto_yolu TEXT,
    sube TEXT DEFAULT 'TEFENNİ',
    durum TEXT DEFAULT 'AKTIF',
    son_guncelleme TEXT,
    is_synced INTEGER DEFAULT 0
  )
''');

    await db.execute('''
    CREATE TABLE IF NOT EXISTS personel_hareketleri (
      id TEXT PRIMARY KEY,                -- 1. MÜHÜR
      firebase_id TEXT UNIQUE,            -- 2. MÜHÜR
      personel_id TEXT NOT NULL,          -- ZORUNLU
      tarih TEXT NOT NULL,                -- ZORUNLU
      tur TEXT NOT NULL,                  -- ZORUNLU
      tutar REAL DEFAULT 0,
      ay_bilgisi TEXT,
      not_aciklama TEXT,
      aciklama TEXT,
      sube TEXT DEFAULT 'TEFENNİ',
      is_synced INTEGER DEFAULT 0,
      FOREIGN KEY (personel_id) REFERENCES personel(id) ON DELETE CASCADE
    )
  ''');

    // =========================================================
    // TAHSİLATLAR
    // =========================================================

    await db.execute('''
    CREATE TABLE IF NOT EXISTS tahsilatlar (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      firebase_id TEXT UNIQUE,            -- 2. MÜHÜR
      is_id INTEGER,
      ciftci_ad TEXT NOT NULL,            -- ZORUNLU
      miktar REAL DEFAULT 0,
      tarih TEXT NOT NULL,                -- ZORUNLU
      sezon TEXT,
      aciklama TEXT,
      odeme_tipi TEXT,
      sube TEXT DEFAULT 'TEFENNİ',
      son_guncelleme TEXT,
      is_synced INTEGER DEFAULT 0
    )
  ''');

    // =========================================================
    // MAZOT TAKİBİ
    // =========================================================

    await db.execute('''
    CREATE TABLE IF NOT EXISTS mazot_takibi (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      firebase_id TEXT UNIQUE,            -- 2. MÜHÜR
      petrol_adi TEXT NOT NULL,           -- ZORUNLU
      litre REAL DEFAULT 0,
      tutar REAL DEFAULT 0,
      odenen REAL DEFAULT 0,
      tarih TEXT,
      sezon TEXT,
      sube TEXT DEFAULT 'TEFENNİ',
      son_guncelleme TEXT,
      is_synced INTEGER DEFAULT 0
    )
  ''');

    await db.execute('''
    CREATE TABLE IF NOT EXISTS bicer_mazotlar (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      firebase_id TEXT UNIQUE,            -- 2. MÜHÜR
      is_id INTEGER,
      miktar REAL DEFAULT 0,
      tarih TEXT,
      sezon TEXT,
      sube TEXT DEFAULT 'TEFENNİ',
      is_synced INTEGER DEFAULT 0
    )
  ''');

    await db.execute('''
  CREATE TABLE IF NOT EXISTS stoklar (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    ana_stok_id TEXT, -- SQL yorumu boyle olur (--) 
    firebase_id TEXT UNIQUE,
    urun TEXT,
    stok_kodu TEXT UNIQUE,
    barkod TEXT UNIQUE,
    cari_kod TEXT,
    kategori TEXT, -- NOT NULL kısımlarını kaldırdım ki senkronizasyon takılmasın
    marka TEXT,
    model TEXT,
    alt_model TEXT,
    altmodel TEXT,
    adet REAL DEFAULT 0,
    fiyat REAL DEFAULT 0,      -- Yerel kodlarının ve ekranlarının aramaya devam ettiği sütun
    alis_fiyati REAL DEFAULT 0, -- 🎯 FİREBASE'DEN GELEN ORİJİNAL ALAN (BURAYA DA EKLENDİ)
    sube TEXT DEFAULT 'TEFENNİ',
    durum TEXT DEFAULT 'AKTIF',
    tarih TEXT,
    tarim_firmalari TEXT,
    sektor TEXT,
    fatura_no TEXT,
    foto TEXT,
    silindi INTEGER DEFAULT 0,
    son_guncelleme TEXT,
    is_synced INTEGER DEFAULT 0
  )
''');

    await db.execute('''
  CREATE TABLE IF NOT EXISTS stok_tanimlari (
    id INTEGER PRIMARY KEY AUTOINCREMENT,

    firebase_id TEXT UNIQUE,            
    stok_kodu TEXT UNIQUE,              

    kategori TEXT NOT NULL,             
    marka TEXT NOT NULL,                
    model TEXT NOT NULL,                

    alt_model TEXT,
    altmodel TEXT,

    urun TEXT,
    tarim_firmalari TEXT,

    durum TEXT DEFAULT 'AKTIF',
    sube TEXT DEFAULT 'TEFENNİ',

    son_guncelleme TEXT,
    is_synced INTEGER DEFAULT 0,
    
    -- EKSİK OLAN VE HATAYA SEBEP OLAN SÜTUN BURASI:
    silindi INTEGER DEFAULT 0, 

    UNIQUE(kategori, marka, model, alt_model)
  )
''');
    // DatabaseHelper içinde olması gereken tablolar:
    await db.execute('''
  CREATE TABLE IF NOT EXISTS stok_hareketleri (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    stok_id INTEGER,
    cari_kod TEXT,
    islem_tipi TEXT, -- 'ALIM' veya 'SATIS'
    adet REAL,
    tarih TEXT
  )
''');

    // =========================================================
    // SATIŞLAR
    // =========================================================

    await db.execute('''
    CREATE TABLE IF NOT EXISTS satislar (
      id INTEGER PRIMARY KEY AUTOINCREMENT,

      firebase_id TEXT UNIQUE,            -- 2. MÜHÜR

      arac_id INTEGER NOT NULL,           -- ZORUNLU
      musteri_ad TEXT NOT NULL,           -- ZORUNLU

      satis_fiyati REAL DEFAULT 0,
      satis_km INTEGER DEFAULT 0,

      satis_tarihi TEXT,
      odeme_tipi TEXT,

      kapora REAL DEFAULT 0,
      kalan_tutar REAL DEFAULT 0,

      vade_tarihi TEXT,
      durum TEXT DEFAULT 'AKTIF',

      sube TEXT DEFAULT 'TEFENNİ',
      son_guncelleme TEXT,
      is_synced INTEGER DEFAULT 0
    )
  ''');
// DatabaseHelper içindeki tablo oluşturma kısmını bu şekilde netleştirelim
    await db.execute('''
CREATE TABLE IF NOT EXISTS tarim_firmalari (
  cari_kod TEXT PRIMARY KEY,
  firebase_id TEXT UNIQUE,
  ad TEXT NOT NULL,          -- Firestore'daki 'reklam' alanı buraya gelecek
  yetkili TEXT,
  tel TEXT,
  adres TEXT,
  kategori TEXT,
  durum TEXT DEFAULT 'AKTIF',
  borc REAL DEFAULT 0,
  alacak REAL DEFAULT 0,
  toplam_borc REAL DEFAULT 0,
  toplam_alacak REAL DEFAULT 0,
  sube TEXT DEFAULT 'TEFENNİ',
  son_guncelleme TEXT,
  is_synced INTEGER DEFAULT 0,
  silindi INTEGER DEFAULT 0
)
''');
    await db.execute('''
  CREATE TABLE IF NOT EXISTS tarla_hasatlari (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    firebase_id TEXT UNIQUE,
    tarla_id INTEGER,
    sezon TEXT,             -- 👈 Hatanın ana sebebi olan eksik kolon
    ekilen_urun TEXT,
    toplam_kg REAL,
    birim_fiyat REAL,
    toplam_gelir REAL,
    satilan_kisi TEXT,
    pesin_alinan REAL,
    kalan_alacak REAL,
    vade_tarihi TEXT,
    odeme_durumu TEXT,
    tarih TEXT,
    is_synced INTEGER DEFAULT 0,
    silindi INTEGER DEFAULT 0
  )
''');


// EĞER TABLO ZATEN VARSA VE KOLON EKSİKSE DİYE ŞU KONTROLÜ DE ALTINA EKLE:
    try {
      await db.execute("ALTER TABLE tarim_firma_hareketleri ADD COLUMN updated_at TEXT");
      print("✅ updated_at kolonu başarıyla eklendi.");
    } catch (e) {
      // Eğer kolon zaten varsa hata verir, sorun değil; "print" ile geçiyoruz.
      print("ℹ️ updated_at kolonu zaten mevcut veya tablo yeni oluşturuldu.");
    }

    // =========================================================
    // ÇİFTÇİLİK FİRMALARI
    // =========================================================

    await db.execute('''
    CREATE TABLE IF NOT EXISTS ciftclik_firmalari (
      id INTEGER PRIMARY KEY AUTOINCREMENT,

      firebase_id TEXT UNIQUE,            -- 2. MÜHÜR
      cari_kod TEXT UNIQUE,               -- 1. MÜHÜR

      ad TEXT NOT NULL,                   -- ZORUNLU
      yetkili TEXT,
      tel TEXT,
      adres TEXT,

      borc REAL DEFAULT 0,
      alacak REAL DEFAULT 0,

      sube TEXT DEFAULT 'TEFENNİ',

      son_guncelleme TEXT,
      is_synced INTEGER DEFAULT 0
    )
  ''');

    // =========================================================
    // ARAÇLAR
    // =========================================================

    await db.execute('''
    CREATE TABLE IF NOT EXISTS araclar (
      id INTEGER PRIMARY KEY AUTOINCREMENT,

      firebase_id TEXT UNIQUE,            -- 2. MÜHÜR
      plaka TEXT UNIQUE NOT NULL,         -- 1. MÜHÜR

      marka TEXT,
      model TEXT,
      alt_model TEXT,

      paket TEXT,
      motor_tipi TEXT,
      kasa_tipi TEXT,

      km INTEGER DEFAULT 0,

      alis_fiyati REAL DEFAULT 0,
      tahmini_satis REAL DEFAULT 0,

      alis_tarihi TEXT,
      kimden_alindi TEXT,

      muayene_tarihi TEXT,
      renk TEXT,

      durum TEXT DEFAULT 'AKTIF',

      sube TEXT DEFAULT 'TEFENNİ',

      son_guncelleme TEXT,
      is_synced INTEGER DEFAULT 0
    )
  ''');

    // =========================================================
    // BİÇER MÜŞTERİLERİ
    // =========================================================

    await db.execute('''
    CREATE TABLE IF NOT EXISTS bicer_musterileri (
      id INTEGER PRIMARY KEY AUTOINCREMENT,

      firebase_id TEXT UNIQUE,            -- 2. MÜHÜR
      tc TEXT UNIQUE,                     -- 1. MÜHÜR

      ad_soyad TEXT NOT NULL,             -- ZORUNLU

      telefon TEXT,
      adres TEXT,
      notlar TEXT,

      fotograf_yolu TEXT,

      sube TEXT DEFAULT 'TEFENNİ',
      durum TEXT DEFAULT 'AKTIF',

      son_guncelleme TEXT,
      is_synced INTEGER DEFAULT 0
    )
  ''');

    // =========================================================
    // BİÇER MÜŞTERİ HAREKETLERİ
    // =========================================================

    await db.execute('''
    CREATE TABLE IF NOT EXISTS bicermusteri_hareketleri (
      id INTEGER PRIMARY KEY AUTOINCREMENT,

      firebase_id TEXT UNIQUE,            -- 2. MÜHÜR

      is_id INTEGER,
      ciftci_ad TEXT NOT NULL,            -- ZORUNLU

      miktar REAL DEFAULT 0,

      tarih TEXT NOT NULL,                -- ZORUNLU
      sezon TEXT,

      odeme_tipi TEXT,

      tip TEXT NOT NULL,                  -- ZORUNLU

      aciklama TEXT,

      sube TEXT DEFAULT 'TEFENNİ',

      son_guncelleme TEXT,
      is_synced INTEGER DEFAULT 0
    )
  ''');



    // =========================================================
    // FATURALAR
    // =========================================================

    await db.execute('''
    CREATE TABLE IF NOT EXISTS faturalar (
      id INTEGER PRIMARY KEY AUTOINCREMENT,

      firebase_id TEXT UNIQUE,            -- 2. MÜHÜR

      firma_id TEXT NOT NULL,             -- ZORUNLU
      dosya_yolu TEXT NOT NULL,           -- ZORUNLU

      tarih TEXT,

      sube TEXT DEFAULT 'TEFENNİ',

      son_guncelleme TEXT,
      is_synced INTEGER DEFAULT 0
    )
  ''');

    // =========================================================
    // MÜŞTERİ HAREKETLERİ
    // =========================================================

    await db.execute('''
    CREATE TABLE IF NOT EXISTS musteri_hareketleri (
      id INTEGER PRIMARY KEY AUTOINCREMENT,

      firebase_id TEXT UNIQUE,            -- 2. MÜHÜR

      musteri_id TEXT NOT NULL,           -- ZORUNLU
      musteri_ad TEXT NOT NULL,           -- ZORUNLU

      islem TEXT NOT NULL,                -- ZORUNLU

      tutar REAL DEFAULT 0,

      aciklama TEXT,

      tarih TEXT NOT NULL,                -- ZORUNLU

      sube TEXT DEFAULT 'TEFENNİ',

      son_guncelleme TEXT,
      is_synced INTEGER DEFAULT 0
    )
  ''');

    // =========================================================
    // MÜŞTERİLER
    // =========================================================

    await db.execute('''
    CREATE TABLE IF NOT EXISTS musteriler (

      id TEXT PRIMARY KEY,                -- 1. MÜHÜR
      firebase_id TEXT UNIQUE,            -- 2. MÜHÜR
      tc TEXT UNIQUE,                     -- 3. MÜHÜR
      ad_norm TEXT UNIQUE,                -- 4. MÜHÜR

      ad TEXT NOT NULL,                   -- 5. MÜHÜR

      tel TEXT,
      adres TEXT,

      sube TEXT DEFAULT 'TEFENNİ',

      bakiye REAL DEFAULT 0,

      son_guncelleme TEXT,
      is_synced INTEGER DEFAULT 0
    )
  ''');

    // =========================================================
    // BİÇER İŞLERİ
    // =========================================================

    await db.execute('''
    CREATE TABLE IF NOT EXISTS bicer_isleri (
      id INTEGER PRIMARY KEY AUTOINCREMENT,

      firebase_id TEXT UNIQUE,            -- 2. MÜHÜR

      ciftci_ad TEXT NOT NULL,            -- ZORUNLU

      urun_tipi TEXT,
      dekar REAL DEFAULT 0,
      fiyat REAL DEFAULT 0,

      toplam_tutar REAL DEFAULT 0,
      odenen_miktar REAL DEFAULT 0,
      kalan_borc REAL DEFAULT 0,

      tarih TEXT NOT NULL,                -- ZORUNLU
      sezon TEXT,

      bicer_id INTEGER,

      fatura_yolu TEXT,

      sube TEXT DEFAULT 'TEFENNİ',

      son_guncelleme TEXT,
      is_synced INTEGER DEFAULT 0
    )
  ''');

    // =========================================================
    // BAKIMLAR
    // =========================================================

    await db.execute('''
    CREATE TABLE IF NOT EXISTS bakimlar (
      id INTEGER PRIMARY KEY AUTOINCREMENT,

      firebase_id TEXT UNIQUE,            -- 2. MÜHÜR

      arac_id INTEGER NOT NULL,           -- ZORUNLU

      usta_tipi TEXT,
      islem_detay TEXT,

      tutar REAL DEFAULT 0,

      tarih TEXT NOT NULL,                -- ZORUNLU

      sube TEXT DEFAULT 'TEFENNİ',

      son_guncelleme TEXT,
      is_synced INTEGER DEFAULT 0
    )
  ''');
    // --- ÇEKLER TABLOSU MÜHÜRÜ ---
    await db.execute('''
  CREATE TABLE IF NOT EXISTS cekler (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    
    firebase_id TEXT UNIQUE,            -- FIREBASE MÜHÜRÜ (ÇİFT KAYDI ÖNLER)
    
    firmaAd TEXT,                       -- FİRMA ADI
    tip TEXT,                           -- ÇEK / SENET
    
    kesideTarihi TEXT,                  -- VERİLİŞ TARİHİ
    vadeTarihi TEXT,                    -- ÖDEME TARİHİ
    
    tutar REAL DEFAULT 0,
    durum TEXT DEFAULT 'BEKLEMEDE',     -- BEKLEMEDE, ÖDENDİ, İPTAL
    
    resimYolu TEXT,                     -- ÇEKİN FOTOĞRAFI
    sube TEXT DEFAULT 'TEFENNİ',
    
    is_synced INTEGER DEFAULT 0,
    son_guncelleme TEXT
  )
''');

    await db.execute('''
  CREATE TABLE IF NOT EXISTS tarla_hasatlari (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    firebase_id TEXT UNIQUE,
    tarla_id INTEGER,
    sezon TEXT,             -- 👈 Hatanın ana sebebi olan eksik kolon
    ekilen_urun TEXT,
    toplam_kg REAL,
    birim_fiyat REAL,
    toplam_gelir REAL,
    satilan_kisi TEXT,
    pesin_alinan REAL,
    kalan_alacak REAL,
    vade_tarihi TEXT,
    odeme_durumu TEXT,
    tarih TEXT,
    is_synced INTEGER DEFAULT 0,
    silindi INTEGER DEFAULT 0
  )
''');

    await db.execute('''
  CREATE TABLE IF NOT EXISTS tarla_hareketleri (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    firebase_id TEXT UNIQUE,
    tarla_id TEXT,          -- Hangi tarlaya ait olduğunu bağlamak için
    islem_tipi TEXT,        -- Gelir, Gider, Gübreleme, Sürüm vb.
    miktar REAL,
    tutar REAL,
    tarih TEXT,
    notlar TEXT,
    is_synced INTEGER DEFAULT 0,
    silindi INTEGER DEFAULT 0
  )
''');

    await db.execute('''
  CREATE TABLE IF NOT EXISTS tarlalar (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    firebase_id TEXT UNIQUE,
    tarla_adi TEXT,
    mevki TEXT,
    dekar REAL,          -- 👈 "donum" yerine "dekar" yaptık
    ada_parsel TEXT,     -- 👈 Eksik olan diğer kolonları da ekliyoruz
    is_sulu INTEGER,
    is_icar INTEGER,
    tarla_sahibi TEXT,
    kira_tutari REAL,
    kira_baslangic TEXT,
    kira_bitis TEXT,
    sezon TEXT,
    ekilen_urun TEXT,
    is_synced INTEGER DEFAULT 0,
    silindi INTEGER DEFAULT 0
  )
''');

// --- FİRMALAR TABLOSU MÜHÜRÜ ---
    await db.execute('''
  CREATE TABLE IF NOT EXISTS firmalar (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    firebase_id TEXT UNIQUE,
    ad TEXT,
    yetkili TEXT,
    tel TEXT,
    kategori TEXT,
    durum TEXT,
    marka TEXT,
    model TEXT,
    alt_model TEXT,
    altmodel TEXT,
    urun TEXT,
    adres TEXT,
    borc REAL DEFAULT 0,
    alacak REAL DEFAULT 0,
    is_synced INTEGER DEFAULT 0,
    sube TEXT DEFAULT 'TEFENNİ'
  )
''');
    await db.execute('''
  CREATE TABLE IF NOT EXISTS proformalar (
    firebase_id TEXT PRIMARY KEY,
    musteri_adi TEXT,
    toplam REAL,
    tarih TEXT,
    sube TEXT,
    is_synced INTEGER DEFAULT 0
  )
''');

    // 2. ADIM: TABLO OLUŞTUKTAN SONRA ONARIM YAP (Şimdi Güvendesin)
    try {
      // islem_tipi yoksa ekle (Eski versiyondan gelenler için)
      await db.execute("ALTER TABLE tarim_firma_hareketleri ADD COLUMN islem_tipi TEXT");
    } catch (e) { print("ℹ️ islem_tipi zaten var veya tablo yeni."); }

    try {
      // tip yoksa ekle
      await db.execute("ALTER TABLE tarim_firma_hareketleri ADD COLUMN tip TEXT");
    } catch (e) { print("ℹ️ tip zaten var."); }

    // 3. ADIM: VERİLERİ EŞİTLE (Mühürleme)
    // Burada NULL olan yerleri birbirine kopyalıyoruz ki bakiye 0.0 çıkmasın
    await db.execute("UPDATE tarim_firma_hareketleri SET islem_tipi = tip WHERE islem_tipi IS NULL AND tip IS NOT NULL");
    await db.execute("UPDATE tarim_firma_hareketleri SET tip = islem_tipi WHERE tip IS NULL AND islem_tipi IS NOT NULL");

    // 4. ADIM: MÜKERRER KAYIT TEMİZLİĞİ
    await db.execute('''
      DELETE FROM tarim_firma_hareketleri 
      WHERE rowid NOT IN (
        SELECT MIN(rowid) 
        FROM tarim_firma_hareketleri 
        WHERE firebase_id IS NOT NULL
        GROUP BY firebase_id
      )
    ''');

    print("✅ TÜM TABLOLAR VE VERİLER MÜHÜRLENDİ.");
  }

  // ================= SÜTUN EKLEME =================
  Future<void> _sutunEkle(
      Database db,
      String tabloAdi,
      String sutunAdi,
      String sutunTipi,
      {bool zorunlu = false}
      ) async {

    try {

      // ================= TABLO VAR MI =================
      final tabloKontrol = await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table' AND name=?",
          [tabloAdi]
      );

      if (tabloKontrol.isEmpty) {
        print("❌ Tablo bulunamadı: $tabloAdi");
        return;
      }

      // ================= MEVCUT SÜTUNLARI AL =================
      final sutunlar = await db.rawQuery('PRAGMA table_info($tabloAdi)');

      bool varMi = sutunlar.any(
            (element) => element['name'].toString().toLowerCase() ==
            sutunAdi.toLowerCase(),
      );

      // ================= SÜTUN YOKSA EKLE =================
      if (!varMi) {

        String finalTip = sutunTipi;

        // ================= ZORUNLU ALAN =================
        if (zorunlu) {

          // TEXT ise boş string varsayılan ver
          if (sutunTipi.toUpperCase().contains("TEXT")) {
            finalTip = "$sutunTipi NOT NULL DEFAULT ''";
          }

          // INTEGER ise 0 ver
          else if (sutunTipi.toUpperCase().contains("INTEGER")) {
            finalTip = "$sutunTipi NOT NULL DEFAULT 0";
          }

          // REAL ise 0 ver
          else if (sutunTipi.toUpperCase().contains("REAL")) {
            finalTip = "$sutunTipi NOT NULL DEFAULT 0";
          }

          // Diğerleri
          else {
            finalTip = "$sutunTipi NOT NULL";
          }
        }

        // ================= EKLE =================
        await db.execute(
            'ALTER TABLE $tabloAdi ADD COLUMN $sutunAdi $finalTip'
        );

        print("✅ $tabloAdi tablosuna $sutunAdi sütunu eklendi.");
      }

    } catch (e) {

      print("❌ Sütun ekleme hatası ($tabloAdi -> $sutunAdi): $e");

    }
  }

  Future<Database> _initFakeWebDatabase() async {
    // Web'de SQLite dosyası arayan kodlara "Dur!" diyen barikat.
    return throw UnsupportedError(
        "SQLite Web üzerinde desteklenmiyor. Web tarafında işlemler doğrudan Firebase üzerinden yürütülür."
    );
  }

  Future<void> tabloyuZorlaGuncelle() async {
    // Web'deysen SQLite tablosu olmadığı için işlem yapmaya gerek yok
    if (kIsWeb) return;

    final db = await instance.database;
    print("🛠️ Veritabanı şeması kontrol ediliyor...");

    // tahsilatlar tablosuna is_id ekle (İş takibi için)
    try {
      await db.execute("ALTER TABLE tahsilatlar ADD COLUMN is_id INTEGER");
      print("✅ SQL: is_id sütunu eklendi.");
    } catch (e) {
      print("ℹ️ SQL: is_id zaten mevcut.");
    }

    // tahsilatlar tablosuna aciklama ekle
    try {
      await db.execute("ALTER TABLE tahsilatlar ADD COLUMN aciklama TEXT");
      print("✅ SQL: aciklama sütunu eklendi.");
    } catch (e) {
      print("ℹ️ SQL: aciklama zaten mevcut.");
    }
  }

  Future<int> insert(String tabloAdi, Map<String, dynamic> veri) async {
    // Web'deysen bu metodu çağırmak yerine Firebase add/set kullanmalısın
    if (kIsWeb) {
      debugPrint("⚠️ UYARI: Web'de doğrudan insert kullanılamaz. Firebase'e yönlenmeli.");
      return 0;
    }

    final db = await instance.database;
    return await db.insert(
      tabloAdi,
      veri,
      conflictAlgorithm: ConflictAlgorithm.replace, // Varsa üzerine yazar, hata vermez
    );
  }


  Future<List<Map<String, dynamic>>> tarimFirmaListesiGetir() async {
    print("🛠️ DEBUG: tarimFirmaListesiGetir TETİKLENDİ");

    try {
      List<Map<String, dynamic>> donusListesi = [];

      if (kIsWeb) {
        final snapshot = await FirebaseFirestore.instance
            .collection('isletmeler')
            .doc('evren_ticaret')
            .collection('tarim_firmalari')
            .orderBy('ad')
            .get();

        for (var doc in snapshot.docs) {
          Map<String, dynamic> data = Map<String, dynamic>.from(doc.data());
          data['id'] = doc.id;
          String cariKod = data['cari_kod'] ?? "";

          // ÖNEMLİ: Her firma için hareketlerini çekiyoruz (PDF hesabı için)
          final hareketSnapshot = await FirebaseFirestore.instance
              .collection('isletmeler')
              .doc('evren_ticaret')
              .collection('tarim_hareketleri')
              .where('cari_kod', isEqualTo: cariKod)
              .get();

          List<Map<String, dynamic>> hareketler = hareketSnapshot.docs
              .map((hDoc) => Map<String, dynamic>.from(hDoc.data()))
              .toList();

          // Şimdi 3 parametreyi de gönderiyoruz
          donusListesi.add(_mapFirmaData(data, "WEB", hareketler));
        }
      } else {
        final db = await database;
        final List<Map<String, dynamic>> sonuc = await db.query(
            'tarim_firmalari',
            where: 'silindi = 0',
            orderBy: 'ad ASC'
        );

        for (var row in sonuc) {
          Map<String, dynamic> data = Map<String, dynamic>.from(row);
          String cariKod = data['cari_kod'] ?? "";

          // Eski hali: 'tarim_hareketleri'
          final List<Map<String, dynamic>> hareketler = await db.query(
            'tarim_firma_hareketleri', // Buradaki ismi veritabanındakiyle aynı yap!
            where: 'cari_kod = ? AND silindi = 0',
            whereArgs: [cariKod],
          );

          donusListesi.add(_mapFirmaData(data, "MOBİL", hareketler));
        }
      }
      return donusListesi;
    } catch (e) {
      print("❌ HATA: tarimFirmaListesiGetir patladı: $e");
      return [];
    }
  }

  Map<String, dynamic> _mapFirmaData(Map<String, dynamic> data, String mod, List<Map<String, dynamic>> hareketler) {
    double yuruyenBakiye = 0.0;
    double toplamBorc = 0.0;
    double toplamAlacak = 0.0;

    for (var h in hareketler) {
      // 1. Tip kolonunu al ve güvenli hale getir (Büyük harfe çevir, boşlukları sil)
      String tipRaw = (h['tip'] ?? "").toString().trim().toUpperCase();

      // PDF'deki gibi AKTARIM ve TRANSFER'leri pas geç
      if (tipRaw == 'AKTARIM' || tipRaw == 'TRANSFER') continue;

      double tutar = double.tryParse(h['tutar']?.toString() ?? "0") ?? 0.0;

      // 2. MÜHÜRLÜ SÜZGEÇ (Harf duyarlılığını ortadan kaldırdık)
      // "ALIM" veya "ALIM" kelimesini içerenleri yakalar
      bool isAlim = tipRaw.contains("ALIM");

      // "ÖDEME", "ODEME" veya "TAHSİLAT" kelimesini içerenleri yakalar
      bool isOdeme = tipRaw.contains("ÖDEME") ||
          tipRaw.contains("ODEME") ||
          tipRaw.contains("TAHSİLAT");

      if (isAlim) {
        toplamBorc += tutar;
        yuruyenBakiye += tutar;
      } else if (isOdeme) {
        toplamAlacak += tutar;
        yuruyenBakiye -= tutar;
      }
    }

    data['borcumuz_label'] = toplamBorc;
    data['alacagimiz_label'] = toplamAlacak;
    data['bakiye'] = yuruyenBakiye;

    print("✅ [$mod] ${data['ad']} -> Borç: $toplamBorc, Ödeme: $toplamAlacak, Net: $yuruyenBakiye");

    return data;
  }


  Future<int> tarimFirmaEkle(Map<String, dynamic> row) async {
    // 1. MÜHÜR: Cari kodu belirle. Yoksa zaman damgalı tekil kod üret.
    String muhur = row['cari_kod']?.toString() ?? "";

    // Eğer cari kod hatalıysa veya boşsa, sistemi kurtarmak için yeni mühür bas
    if (muhur.isEmpty || muhur.trim() == "" || muhur.contains("null") || muhur.contains("HATA")) {
      muhur = "F-${DateTime.now().millisecondsSinceEpoch}";
    }

    // Veriyi temizle ve mühürleri eşitle
    Map<String, dynamic> finalRow = Map<String, dynamic>.from(row);
    finalRow['cari_kod'] = muhur;
    finalRow['firebase_id'] = muhur;
    finalRow['id'] = muhur; // Hem Web hem Mobil ID'yi cari_kod yapıyoruz ki çakışmasın

    // 2. MÜHÜR: Firebase tarafını temizle
    // Firebase'e gönderirken 'son_guncelleme' tipini ayarla
    Map<String, dynamic> firestoreData = {...finalRow};
    firestoreData['son_guncelleme'] = FieldValue.serverTimestamp();
    firestoreData['is_synced'] = 1;

    try {
      // .doc(muhur) kullanarak Firebase'deki doküman adını cari_kod yapıyoruz.
      // SetOptions(merge: true) sayesinde eğer varsa sadece değişenleri günceller, mükerrer yaratmaz.
      await FirebaseFirestore.instance
          .collection('tarim_firmalari')
          .doc(muhur)
          .set(firestoreData, SetOptions(merge: true));

      print("☁️ Firebase Mühürlendi: $muhur");
    } catch (e) {
      print("⚠️ Firebase Senkron Hatası: $e");
      finalRow['is_synced'] = 0; // İnternet yoksa SQL'e "senkronize edilmedi" diye yaz
    }

    // ... (Kodun üst kısımları aynı kalıyor)

    // 3. MÜHÜR: Mobil / SQL tarafı
    if (kIsWeb) {
      return 1;
    } else {
      final db = await instance.database;

      // --- 🚨 KRİTİK MÜDAHALE BURASI 🚨 ---
      // SQL tablosunda 'id' kolonu olmadığı için, göndermeden önce onu siliyoruz
      Map<String, dynamic> sqlVerisi = Map<String, dynamic>.from(finalRow);
      sqlVerisi.remove('id');
      // -----------------------------------

      int res = await db.insert(
          'tarim_firmalari',
          sqlVerisi, // Artık içinde 'id' yok, SQLite mutlu!
          conflictAlgorithm: ConflictAlgorithm.replace
      );

      print("📦 SQL Mühürlendi: $muhur");
      return res;
    }
  }
  Future<bool> hareketVarMi(String id) async {
    final db = await instance.database;
    var res = await db.query("tarim_firma_hareketleri", where: "id = ?", whereArgs: [id]);
    return res.isNotEmpty;
  }


  Future<void> tarimfirmaHareketiEkle(Map<String, dynamic> h) async {
    print("\n--- 🛠️ ZORUNLU SENKRONİZASYON BAŞLATILDI ---");

    final firestore = FirebaseFirestore.instance;

    final String cKod = h['cari_kod']?.toString() ?? "";
    final double tutarVal = double.tryParse(h['tutar']?.toString().replaceAll(',', '.') ?? "0") ?? 0.0;
    final String islemTipi = h['tip']?.toString().toUpperCase() ?? "ALIM"; // İsmi islemTipi yapalım
    final String hareketId = h['id']?.toString() ?? "H-${DateTime.now().millisecondsSinceEpoch}";
    final String urunAdi = h['urun_adi']?.toString().toUpperCase() ?? "BELİRTİLMEMİŞ";

    if (cKod.isEmpty) {
      print("❌ HATA: Cari Kod boş, işlem iptal edildi!");
      return;
    }

    // --- KRİTİK DÜZELTME: ÇİFT MÜHÜR ---
    final Map<String, dynamic> temizVeri = {
      'firebase_id': hareketId, // Logdaki firebase_id kolonu için
      'id': hareketId,
      'cari_kod': cKod,
      'stok_id': h['stok_id'] ?? hareketId, // Eksikse hata vermesin diye eklendi
      'islem_tipi': islemTipi, // Senin yeni kolonun
              // HATA VEREN ESKİ KOLON (SQLite'ı susturmak için şart)
      'urun_adi': urunAdi,
      'tutar': tutarVal,
      'adet': double.tryParse(h['adet']?.toString() ?? "1") ?? 1.0,
      'tarih': h['tarih']?.toString() ?? "",
      'is_synced': 1,
      'silindi': 0,
    };

    // --- SQLITE KAYDI ---
    if (!kIsWeb) {
      try {
        final db = await instance.database;
        print("📦 1. DURAK: SQLite'a yazılıyor...");

        // MÜHÜR: Tüm kolonları içeren garanti sorgu
        await db.rawInsert('''
        INSERT OR REPLACE INTO tarim_firma_hareketleri 
        (firebase_id, cari_kod, stok_id, islem_tipi, tip, urun_adi, tutar, adet, tarih, is_synced, silindi) 
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ''', [
          temizVeri['firebase_id'],
          temizVeri['cari_kod'],
          temizVeri['stok_id'],
          temizVeri['islem_tipi'],
          temizVeri['tip'], // İşte bu satır o NOT NULL hatasını bitirecek!
          temizVeri['urun_adi'],
          temizVeri['tutar'],
          temizVeri['adet'],
          temizVeri['tarih'],
          temizVeri['is_synced'],
          temizVeri['silindi']
        ]);

        print("✅ SQLite Mühürlendi.");

        // Çakışma olursa (replace) üstüne yazar
        await db.insert('tarim_firma_hareketleri', temizVeri, conflictAlgorithm: ConflictAlgorithm.replace);

        print("📉 2. DURAK: SQLite Bakiye güncelleniyor...");
        // Mühür: Tip kontrolünü islemTipi üzerinden yapıyoruz
        await db.execute(
            islemTipi == "ALIM"
                ? "UPDATE tarim_firmalari SET alacak = alacak + ? WHERE cari_kod = ?"
                : "UPDATE tarim_firmalari SET alacak = alacak - ? WHERE cari_kod = ?",
            [tutarVal, cKod]
        );
      } catch (e) {
        print("⚠️ SQLite Hatası: $e");
      }
    }

    // --- FIREBASE KAYDI ---
    try {
      print("☁️ 3. DURAK: Firebase'e gönderiliyor...");
      await firestore.collection('tarim_firma_hareketleri').doc(hareketId).set({
        ...temizVeri,
        'server_tarih': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      print("📉 4. DURAK: Firebase Bakiye güncelleniyor...");
      DocumentReference firmaRef = firestore.collection('tarim_firmalari').doc(cKod);

      await firmaRef.update({
        'alacak': FieldValue.increment(islemTipi == "ALIM" ? tutarVal : -tutarVal)
      });

      print("✅ İŞLEM TAMAM: SQL ve Firebase el sıkıştı.");
    } catch (e) {
      print("🚨 FIREBASE HATASI: $e");
    }
  }

  Future<List<Map<String, dynamic>>> tarimfirmaEkstresiGetir(String cariKod) async {
    final String temizKod = cariKod.trim();
    if (temizKod.isEmpty) {
      print("⚠️ Sorgu İptal: Cari kod boş.");
      return [];
    }

    // --- 1. WEB & BULUT SORGUSU (Firebase) ---
    if (kIsWeb) {
      try {
        var snapshot = await FirebaseFirestore.instance
            .collection('tarim_firma_hareketleri')
            .where('cari_kod', isEqualTo: temizKod)
            .where('silindi', isNotEqualTo: 1) // Silinenleri getirme
            .get();

        print("☁️ Firebase'den ${snapshot.docs.length} adet hareket çekildi.");

        return snapshot.docs.map((doc) {
          Map<String, dynamic> data = Map<String, dynamic>.from(doc.data());
          data['id'] = doc.id;
          return _ekstreVeriFormatla(data);
        }).toList();
      } catch (e) {
        print("❌ Firebase Ekstre Hatası: $e");
        return [];
      }
    }

    // --- 2. MOBİL SORGUSU (SQLite) ---
    try {
      final db = await instance.database;

      // Logdaki "no such table" hatasını önlemek için tablo adını mühürledik.
      // 'silindi' sütunu kontrolünü try-catch içinde yaparak güvenliği artırdık.
      final List<Map<String, dynamic>> maps = await db.query(
        'tarim_firma_hareketleri',
        where: 'cari_kod = ? AND (silindi IS NULL OR silindi = 0)',
        whereArgs: [temizKod],
        orderBy: 'tarih DESC, id DESC',
      );

      print("📦 SQLite'dan ${maps.length} adet hareket çekildi (Cari: $temizKod).");

      return maps.map((e) => _ekstreVeriFormatla(e)).toList();
    } catch (e) {
      print("🚨 SQLite Ekstre Hatası: $e");
      // Eğer tablo ismi yanlışsa veya sütun yoksa en azından uygulamayı çökertmez.
      return [];
    }
  }
  Map<String, dynamic> _ekstreVeriFormatla(Map<String, dynamic> e) {
    var map = Map<String, dynamic>.from(e);

    // MÜHÜR: Hem 'tip' hem 'islem_tipi' kolonuna bakıyoruz, hangisi doluysa onu alıyoruz.
    String gelenTip = (map['islem_tipi'] ?? map['tip'] ?? "ALIM").toString().trim().toUpperCase();

    map['islem_tipi'] = gelenTip; // Veritabanı standardına eşitle
    map['tip'] = gelenTip;        // Arayüz (UI) uyumu için bunu da tut

    var hamTutar = map['tutar'].toString().replaceAll(',', '.');
    map['tutar'] = double.tryParse(hamTutar) ?? 0.0;
    map['tarih'] = map['tarih'] ?? DateFormat('dd.MM.yyyy').format(DateTime.now());

    return map;
  }


// Yardımcı Fonksiyon: Veri tipini mühürler
  Map<String, dynamic> _veriFormatla(Map<String, dynamic> e) {
    var map = Map<String, dynamic>.from(e);
    map['tip'] = (map['tip'] ?? "ALIM").toString().toUpperCase();
    map['tutar'] = double.tryParse(map['tutar'].toString()) ?? 0.0;
    map['tarih'] = map['tarih'] ?? "";
    return map;
  }
// DatabaseHelper.dart içinde bu metodu bul ve böyle mühürle:
  Future<void> tarimfirmaHareketiEkleSenkron(Map<String, dynamic> veri) async {
    final db = await instance.database;

    // 1. Veriyi hazırla (Eksik kolonları birbirine eşitle)
    final String muhur = (veri['id'] ?? veri['firebase_id']).toString();

    // Hem 'tip' hem 'islem_tipi' göndererek NOT NULL hatasını engelliyoruz
    final Map<String, dynamic> eklenecekVeri = {
      'firebase_id': muhur,
      'cari_kod': veri['cari_kod'],
      'tip': veri['tip'] ?? veri['islem_tipi'] ?? 'BELİRSİZ',
      'islem_tipi': veri['islem_tipi'] ?? veri['tip'] ?? 'BELİRSİZ',
      'urun_adi': veri['urun_adi'] ?? "BİLİNMEYEN İŞLEM",
      'tutar': veri['tutar'] ?? 0.0,
      'adet': (veri['adet'] ?? 0.0).toDouble(),
      'tarih': veri['tarih'],
      'is_synced': 1, // Buluttan geldiği için onaylı
      'silindi': 0,
    };

    // 2. Mühürlü Kayıt (ConflictAlgorithm.replace sayesinde varsa günceller, yoksa ekler)
    await db.insert(
      'tarim_firma_hareketleri',
      eklenecekVeri,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    print("✅ Hareket mühürlendi: $muhur");
  }

  Future<double> firmaBorcuGetir(String cariKod) async {
    try {
      final db = await instance.database;
      // MÜHÜR: Tablo adı tarim_firma_hareketleri olarak güncellendi
      var res = await db.rawQuery(
          "SELECT SUM(tutar) as borc FROM tarim_firma_hareketleri WHERE cari_kod = ? AND (silindi IS NULL OR silindi = 0)",
          [cariKod]
      );

      if (res.isNotEmpty && res.first['borc'] != null) {
        return double.parse(res.first['borc'].toString());
      }
      return 0.0;
    } catch (e) {
      debugPrint("❌ Borç hesaplama hatası (Tablo ismi kontrol et): $e");
      return 0.0;
    }
  }

  Future<void> tarimHareketiGuncelle(String id, Map<String, dynamic> veri) async {
    final db = await instance.database;
    await db.update(
        'tarim_firma_hareketleri',
        veri,
        where: 'id = ?',
        whereArgs: [id]
    );
  }

  Future<void> tarimfirmaHareketiSil(String muhurID, String cariKod, double tutar, String tip) async {
    final String suan = DateTime.now().toIso8601String();
    final String temizKod = cariKod.trim().toUpperCase();

    try {
      String temizID = muhurID.trim();
      if (temizID.isEmpty) return;

      // 1. FIREBASE (BULUT) SİLME İŞARETİ
      await FirebaseFirestore.instance
          .collection('tarim_firma_hareketleri')
          .doc(temizID)
          .update({
        'silindi': 1,
        'updated_at': suan
      });

      // 2. SQLITE (YEREL) SİLME İŞARETİ
      if (!kIsWeb) {
        final db = await instance.database;
        await db.update(
            'tarim_firma_hareketleri',
            {'silindi': 1, 'updated_at': suan},
            where: 'firebase_id = ? OR id = ?', // SQLite ID'si veya Firebase ID'si olma ihtimaline karşı ikisini de sağlama alıyoruz
            whereArgs: [temizID, temizID]
        );
      }

      // --- KRİTİK DEĞİŞİKLİK BURASI ---
      // Bir hareketi SİLMEK, o hareketin TAM TERSİ bir işlem yapmak demektir.
      // Alımı siliyorsan ödeme gibi (-), ödemeyi siliyorsan alım gibi (+) bakiye etki eder.
      String kontrolTipi = tip.trim().toUpperCase();
      String tersTip = "ALIS";

      if (kontrolTipi == "ALIM" || kontrolTipi == "BORC" || kontrolTipi == "ALIS") {
        // Mal alımını siliyorsak, sanki ÖDEME yapmış gibi borcu azaltacağız (-)
        tersTip = "ODEME";
      } else if (kontrolTipi == "ODEME" || kontrolTipi == "TAHSILAT" || kontrolTipi == "ALACAK") {
        // Yaptığımız ödemeyi siliyorsak, sanki yeniden MAL ALMIŞ gibi borcu geri yükleyeceğiz (+)
        tersTip = "ALIS";
      }

      // Yeni ve güvenli fonksiyonumuzu çağırarak yerel ve bulut bakiyelerini mühürlüyoruz.
      // Bu sayede Excel'den gelen bakiye yapısı asla bozulmaz ve sıfırlanmaz.
      await tarimfirmaBakiyeGuncelle(temizKod, tutar, tip: tersTip);

      print("✅ Hareket başarıyla silindi ve bakiye ters işlem yönünde ($tersTip) güncellendi.");

    } catch (e) {
      debugPrint("❌ Hareket Silme Hatası: $e");
    }
  }





// Eğer firmalar tablosunda kayıt bulunamazsa sistemin patlamaması için eski kodunu buraya yedekledim
  Future<double> _yedekHareketlerdenHesapla(String cariKod) async {
    final db = await instance.database;
    List<Map> columns = await db.rawQuery('PRAGMA table_info(tarim_firma_hareketleri)');
    bool hasIslemTipi = columns.any((c) => c['name'] == 'islem_tipi');
    bool hasTip = columns.any((c) => c['name'] == 'tip');

    String tipSorgusuAlim = "";
    String tipSorgusuOdeme = "";

    if (hasIslemTipi && hasTip) {
      tipSorgusuAlim = "(islem_tipi IN ('ALIM', 'BORC') OR tip IN ('ALIM', 'BORC'))";
      tipSorgusuOdeme = "(islem_tipi IN ('ODEME', 'TAHSILAT', 'ALACAK') OR tip IN ('ODEME', 'TAHSILAT', 'ALACAK'))";
    } else if (hasIslemTipi) {
      tipSorgusuAlim = "islem_tipi IN ('ALIM', 'BORC')";
      tipSorgusuOdeme = "islem_tipi IN ('ODEME', 'TAHSILAT', 'ALACAK')";
    } else if (hasTip) {
      tipSorgusuAlim = "tip IN ('ALIM', 'BORC')";
      tipSorgusuOdeme = "tip IN ('ODEME', 'TAHSILAT', 'ALACAK')";
    } else {
      return 0.0;
    }

    var alimlar = await db.rawQuery('''
    SELECT SUM(tutar) as toplam FROM tarim_firma_hareketleri 
    WHERE cari_kod = ? AND $tipSorgusuAlim AND (silindi IS NULL OR silindi = 0)
  ''', [cariKod]);

    var odemeler = await db.rawQuery('''
    SELECT SUM(tutar) as toplam FROM tarim_firma_hareketleri 
    WHERE cari_kod = ? AND $tipSorgusuOdeme AND (silindi IS NULL OR silindi = 0)
  ''', [cariKod]);

    double toplamAlim = double.tryParse(alimlar.first['toplam']?.toString() ?? '0') ?? 0.0;
    double toplamOdeme = double.tryParse(odemeler.first['toplam']?.toString() ?? '0') ?? 0.0;

    return toplamAlim - toplamOdeme;
  }


  Future<void> tarimfirmaSil(String cariKod) async {
    String cKod = cariKod.trim(); // Mühür büyük/küçük harf duyarlı olabilir, dokunma
    String suan = DateFormat('dd.MM.yyyy HH:mm').format(DateTime.now());

    if (cKod.isEmpty) return;

    try {
      // 1. FIREBASE TARAFI (BATCH İŞLEMİ)
      final WriteBatch batch = FirebaseFirestore.instance.batch();

      // Hareketleri bul (Doğru tablo: tarim_firma_hareketleri)
      var hareketler = await FirebaseFirestore.instance
          .collection('tarim_firma_hareketleri')
          .where('cari_kod', isEqualTo: cKod)
          .get();

      // Tüm hareketleri "silindi" olarak işaretle
      for (var doc in hareketler.docs) {
        batch.update(doc.reference, {
          'silindi': 1,
          'is_synced': 1,
          'updated_at': FieldValue.serverTimestamp()
        });
      }

      // Firmayı "silindi" olarak işaretle
      batch.update(
          FirebaseFirestore.instance.collection('tarim_firmalari').doc(cKod),
          {
            'silindi': 1,
            'is_synced': 1,
            'updated_at': FieldValue.serverTimestamp()
          }
      );

      // Bulutu mühürle
      await batch.commit();

      // 2. SQLITE TARAFI (MOBİL)
      if (!kIsWeb) {
        final db = await instance.database;

        await db.transaction((txn) async {
          // Hareketleri yerelde pasife al (Doğru tablo: tarim_firma_hareketleri)
          int hM = await txn.update(
              'tarim_firma_hareketleri',
              {'silindi': 1, 'is_synced': 1},
              where: 'cari_kod = ?',
              whereArgs: [cKod]
          );

          // Firmayı yerelde pasife al
          int fM = await txn.update(
              'tarim_firmalari',
              {'silindi': 1, 'is_synced': 1},
              where: 'cari_kod = ?',
              whereArgs: [cKod]
          );

          debugPrint("📱 Mobil: $fM firma ve $hM hareket pasife alındı.");
        });
      }

      debugPrint("✅ $cKod mühürlü firma ve geçmişi başarıyla silindi (Soft Delete).");

    } catch (e) {
      debugPrint("❌ Silme Hatası: $e");
      throw "Firma silinirken bir hata oluştu: $e";
    }
  }
  Future<void> herSeyiBuluttanIndir() async {
    // Web'de SQLite olmadığı için veya zaten çalışıyorsa durdur
    if (kIsWeb || _syncCalisiyor) return;
    _syncCalisiyor = true;

    try {
      final db = await instance.database;

      // 1. Tablo ve Koleksiyon Eşleşmelerini Tanımla (Doğru isimler)
      // Format: {'BuluttakiKoleksiyonAdi': 'TelefondakiTabloAdi'}
      Map<String, String> senkronHaritasi = {
        'stoklar': 'stoklar',
        'tarim_firmalari': 'tarim_firmalari',
        'tarim_firma_hareketleri': 'tarim_firma_hareketleri', // Eskisi 'firma_hareketleri' idi, düzelttik
        'musteriler': 'musteriler'
      };

      for (var giris in senkronHaritasi.entries) {
        String kolAdi = giris.key; // Firebase'deki adı
        String tabloAdi = giris.value; // SQLite'daki adı

        debugPrint("🔄 $tabloAdi verileri buluttan çekiliyor...");

        // Firebase'den veriyi çek (Sadece silinmemişleri getirmek istersen .where ekleyebilirsin)
        var snapshot = await FirebaseFirestore.instance.collection(kolAdi).get();

        // SQLite tablosundaki kolonları öğren (Hata almamak için şart)
        var tableInfo = await db.rawQuery("PRAGMA table_info($tabloAdi)");
        List<String> sqlKolonlari = tableInfo.map((e) => e['name'].toString()).toList();

        for (var doc in snapshot.docs) {
          Map<String, dynamic> veri = Map.from(doc.data());

          // Veri Dönüşümleri (Mühürleme)
          veri.forEach((key, value) {
            // Firebase Timestamp'i String'e çevir (Senin sistemin dd.MM.yyyy kullanıyor ama indirmede ISO iyidir)
            if (value is Timestamp) {
              veri[key] = DateFormat('dd.MM.yyyy').format(value.toDate());
            }
            // Boolean gelirse SQLite için 1-0 yap
            if (value is bool) {
              veri[key] = value ? 1 : 0;
            }
          });

          // Kritik mühür alanları
          veri['firebase_id'] = doc.id;
          veri['is_synced'] = 1;

          // SQLite Şemasına Uygun Hale Getir (Tabloda olmayan kolonu temizle)
          Map<String, dynamic> temizVeri = {};
          for (var kolon in sqlKolonlari) {
            if (veri.containsKey(kolon)) {
              temizVeri[kolon] = veri[kolon];
            }
          }

          // Varsa güncelle yoksa ekle (ConflictAlgorithm.replace mühürdür)
          await db.insert(tabloAdi, temizVeri, conflictAlgorithm: ConflictAlgorithm.replace);
        }
        debugPrint("✅ $tabloAdi başarıyla güncellendi.");
      }

      debugPrint("🚀 Senkronizasyon Tamam: Tüm veriler mühürlendi.");
    } catch (e) {
      debugPrint("❌ Senkronizasyon Hatası: $e");
    } finally {
      _syncCalisiyor = false;
    }
  }


  Future<void> tarimfirmaBakiyeGuncelle(String cariKod, double miktar, {String tip = "ALIS"}) async {
    // Excel'den gelen kodlarda boşluk veya küçük harf varsa senkronizasyon patlamasın diye mühürlüyoruz
    final String temizKod = cariKod.trim().toUpperCase();
    if (temizKod.isEmpty) return;

    // MANTIK: Ödeme yapıyorsam borcum azalır (-), mal alıyorsam artar (+)
    String t = tip.toUpperCase();
    double guncellenecekMiktar = (t == "ODEME" || t == "ODEMEA" || t == "TAHSILAT") ? -miktar : miktar;

    // --- 1. SQLITE MÜHÜRÜ (Yerel Güvenlik) ---
    if (!kIsWeb) {
      try {
        final db = await instance.database;

        // Önce bu firma SQL'de var mı?
        var kontrol = await db.query('tarim_firmalari', where: 'cari_kod = ?', whereArgs: [temizKod]);

        if (kontrol.isEmpty) {
          // --- KRİTİK DÜZELTME BURASI ---
          // Sorgulama yaparken hangi kolonları kullanıyorsan (toplam_borc/toplam_alacak veya alacak)
          // buraya o kolonları ekliyoruz ki çıkıp girince sıfırlanmasın.
          await db.insert('tarim_firmalari', {
            'cari_kod': temizKod,
            'ad': "YENİ FİRMA ($temizKod)",
            'toplam_borc': guncellenecekMiktar > 0 ? guncellenecekMiktar : 0.0,
            'toplam_alacak': guncellenecekMiktar < 0 ? guncellenecekMiktar.abs() : 0.0,
            'alacak': guncellenecekMiktar, // Eski sisteme uyumluluk için dursun
            'is_synced': 0
          });
        } else {
          // Varsa direkt üzerine ekle (Hem eski 'alacak' alanını hem de sorguladığın borç/alacak alanlarını besliyoruz)
          if (guncellenecekMiktar > 0) {
            await db.rawUpdate(
                "UPDATE tarim_firmalari SET toplam_borc = toplam_borc + ?, alacak = alacak + ?, is_synced = 0 WHERE cari_kod = ?",
                [guncellenecekMiktar, guncellenecekMiktar, temizKod]
            );
          } else {
            await db.rawUpdate(
                "UPDATE tarim_firmalari SET toplam_alacak = toplam_alacak + ?, alacak = alacak + ?, is_synced = 0 WHERE cari_kod = ?",
                [guncellenecekMiktar.abs(), guncellenecekMiktar, temizKod]
            );
          }
        }
        print("🚀 Yerel bakiye mühürlendi.");
      } catch (e) {
        print("❌ Yerel bakiye hatası (Tablo yapısını kontrol et!): $e");
      }
    }

    // --- 2. FIREBASE MÜHÜRÜ (Bulutla Eşitleme) ---
    try {
      // Firestore'da 'borc' ve 'alacak' isimlerini net kullanıyorduk, onları da buraya sağlama alıyoruz
      Map<String, dynamic> updateData = {
        'alacak': FieldValue.increment(guncellenecekMiktar),
        'cari_kod': temizKod,
        'updated_at': DateTime.now().toIso8601String(),
      };

      if (guncellenecekMiktar > 0) {
        updateData['borc'] = FieldValue.increment(guncellenecekMiktar);
      } else {
        updateData['alacak_gercek'] = FieldValue.increment(guncellenecekMiktar.abs()); // İsim karmaşasını çözmek için bulutta increment
      }

      await FirebaseFirestore.instance
          .collection('tarim_firmalari')
          .doc(temizKod)
          .set(updateData, SetOptions(merge: true));

      print("✅ Bulut bakiye mühürlendi (Sync OK).");
    } catch (e) {
      print("❌ Bulut bakiye hatası: $e");
    }
  }




  Future<void> herSeyiBulutaBas() async {
    // WEB KONTROLÜ: Web platformunda SQLite olmadığı için kirli kayıt aranacak yer yoktur.
    if (kIsWeb) {
      print("ℹ️ Web platformunda buluta basma (SQLite'dan Firebase'e) işlemi atlandı.");
      return;
    }

    // 1. KONTROL: Eğer zaten bir eşitleme varsa ikinciyi başlatma (Kilit)
    if (_syncCalisiyor) {
      print("⏳ [SYNC] Zaten bir eşitleme sürüyor, bekleyiniz...");
      return;
    }

    _syncCalisiyor = true;
    print("🚀 [SYNC] Akıllı Bulut Eşitleme Başlatıldı...");

    try {
      final db = await instance.database;
      final firestore = FirebaseFirestore.instance;

      // Eşitlenecek tabloların listesi
      final List<String> tablolar = [
        'stok_tanimlari',
        'stoklar',
        'firmalar',
        'tarim_firmalari',
        'tarim_firma_hareketleri', // Bu eksikti, ekledik!
        'cekler',
        'tarlalar'
      ];

      for (String tablo in tablolar) {
        // Sadece 'is_synced = 0' olan yani henüz buluta gitmemiş (kirli) kayıtları al
        final List<Map<String, dynamic>> kirliKayitlar = await db.query(
            tablo,
            where: 'is_synced = ?',
            whereArgs: [0]
        );

        if (kirliKayitlar.isEmpty) continue;

        print("📦 $tablo tablosundan ${kirliKayitlar.length} adet yeni kayıt buluta gönderiliyor...");

        for (var kayit in kirliKayitlar) {
          // SQLite ID'sini alıyoruz (Firebase'de doküman ID'si yapacağız)
          String docId = kayit['id'].toString();

          // Gönderilecek veriyi hazırla (is_synced alanını Firebase'e gönderme, gerek yok)
          Map<String, dynamic> veri = Map.from(kayit)..remove('is_synced');

          // 2. ADIM: Firebase'e Yaz (Merge: true sayesinde varsa günceller, yoksa ekler)
          await firestore.collection(tablo).doc(docId).set(
              veri,
              SetOptions(merge: true)
          );

          // 3. ADIM: Yerel SQLite'ı Güncelle (is_synced = 1 yap ki bir daha çekmesin)
          await db.update(
              tablo,
              {'is_synced': 1},
              where: 'id = ?',
              whereArgs: [kayit['id']]
          );
        }
        print("✅ $tablo eşitlemesi tamamlandı.");
      }

      print("🏁 [SYNC] Tüm kirli kayıtlar temizlendi, bulut mühürlendi.");
    } catch (e) {
      print("❌ [SYNC] HATA ÇIKTI: $e");
    } finally {
      // İşlem bitince veya hata alınca kilidi mutlaka aç!
      _syncCalisiyor = false;
    }
  }

// ================= CEK =================
  Future<List<CekModel>> getCekler() async {
    if (kIsWeb) {
      // --- WEB İÇİN: DOĞRUDAN FIREBASE'DEN ÇEK ---
      try {
        final snapshot = await FirebaseFirestore.instance
            .collection('cekler')
            .get();

        return snapshot.docs.map((doc) {
          Map<String, dynamic> data = doc.data();
          // Firebase'den gelen veride ID yoksa doküman ID'sini kullanıyoruz
          if (data['id'] == null) {
            data['id'] = doc.id;
          }
          return CekModel.fromMap(data);
        }).toList();
      } catch (e) {
        debugPrint("Web Cek Listesi Hatası: $e");
        return [];
      }
    } else {
      // --- MOBİL İÇİN: SENİN ORİJİNAL KODUN ---
      final db = await database;
      final maps = await db.query('cekler');
      return maps.map((e) => CekModel.fromMap(e)).toList();
    }
  }


  Future<void> cekSil(dynamic id) async { // id hem int hem String gelebileceği için dynamic yaptık
    if (kIsWeb) {
      // --- WEB İÇİN: FIREBASE'DEN SİL ---
      try {
        await FirebaseFirestore.instance
            .collection('cekler')
            .doc(id.toString())
            .delete();
        debugPrint("✅ Çek Firebase'den silindi: $id");
      } catch (e) {
        debugPrint("⚠️ Web Çek Silme Hatası: $e");
      }
    } else {
      // --- MOBİL İÇİN: SENİN ORİJİNAL KODUN ---
      final db = await database;
      await db.delete('cekler', where: 'id=?', whereArgs: [id]);
    }
  }
  Future<int> cekEkle(CekModel cek) async {
    if (kIsWeb) {
      // --- WEB İÇİN: DOĞRUDAN FIREBASE'E EKLE ---
      try {
        Map<String, dynamic> veri = cek.toMap();

        // Eğer ID varsa o ID ile, yoksa otomatik ID ile kaydet
        String docId = (cek.id != null && cek.id.toString().length > 5)
            ? cek.id.toString()
            : FirebaseFirestore.instance.collection('cekler').doc().id;

        await FirebaseFirestore.instance
            .collection('cekler')
            .doc(docId)
            .set({
          ...veri,
          'id': docId, // Firebase ID'sini verinin içine de yazıyoruz
          'is_synced': 1,
          'son_guncelleme': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        debugPrint("✅ Çek Web üzerinden Firebase'e eklendi.");
        return 1;
      } catch (e) {
        debugPrint("⚠️ Web Çek Ekleme Hatası: $e");
        return 0;
      }
    } else {
      // --- MOBİL İÇİN: SENİN ORİJİNAL KODUN ---
      final db = await instance.database;
      // conflictAlgorithm: replace sayesinde aynı ID'li çek varsa üstüne yazar, hata vermez.
      return await db.insert('cekler', cek.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
    }
  }
// --- STOK VE LİSTELEME METODLARI ---
  Future<List<Map<String, dynamic>>> sifirStoklariGetir() async {
    if (kIsWeb) {
      // --- WEB İÇİN: DOĞRUDAN FIREBASE'DEN SIFIR STOKLARI ÇEK ---
      try {
        final snapshot = await FirebaseFirestore.instance
            .collection('stoklar')
            .where('durum', isEqualTo: 'SIFIR')
            .get();

        return snapshot.docs.map((doc) {
          Map<String, dynamic> data = doc.data();
          // SQLite 'id' beklediği için döküman ID'sini ekliyoruz
          data['id'] = doc.id;
          return data;
        }).toList();
      } catch (e) {
        debugPrint("Web Sıfır Stok Getirme Hatası: $e");
        return [];
      }
    } else {
      // --- MOBİL İÇİN: SENİN ORİJİNAL KODUN ---
      final db = await instance.database;
      return await db.query('stoklar', where: 'durum = ?', whereArgs: ['SIFIR']);
    }
  }

// 1. Tüm stokları getiren metod (Kritik stok uyarısı ve liste için)
  Future<List<Map<String, dynamic>>> stoklariGetir() async {
    // --- WEB İÇİN: BELİRLEDİĞİMİZ TAM YOLDAN ÇEK ---
    if (kIsWeb) {
      try {
        final snapshot = await FirebaseFirestore.instance
            .collection('isletmeler')
            .doc('evren_ticaret')
            .collection('stoklar')
            .where('silindi', isEqualTo: 0) // Sadece silinmeyenleri getir
            .get();

        return snapshot.docs.map((doc) {
          Map<String, dynamic> data = doc.data();
          // Web'de mühür (doc.id) bizim birincil kimliğimizdir
          data['id'] = doc.id;
          return data;
        }).toList();
      } catch (e) {
        debugPrint("🌐 Web Stok Çekme Hatası: $e");
        return [];
      }
    }

    // --- MOBİL İÇİN: SQLITE MÜHÜR KONTROLLÜ ÇEK ---
    else {
      try {
        final db = await instance.database;
        // Sadece silinmemiş kayıtları, en son güncellenene göre sırala
        return await db.query(
          'stoklar',
          where: 'silindi = 0',
          orderBy: 'son_guncelleme DESC',
        );
      } catch (e) {
        debugPrint("📱 Mobil SQLite Stok Çekme Hatası: $e");
        return [];
      }
    }
  }

// 3. Mevcut metodunu '2.EL' formatına göre kontrol et
  Future<List<Map<String, dynamic>>> ikinciElStoklariGetir() async {
    if (kIsWeb) {
      // --- WEB İÇİN: DOĞRUDAN FIREBASE'DEN 2.EL STOKLARI ÇEK ---
      try {
        final snapshot = await FirebaseFirestore.instance
            .collection('stoklar')
            .where('durum', isEqualTo: '2.EL')
            .get();

        return snapshot.docs.map((doc) {
          Map<String, dynamic> data = doc.data();
          // SQLite uyumu için döküman ID'sini (doc.id) ekliyoruz
          data['id'] = doc.id;
          return data;
        }).toList();
      } catch (e) {
        debugPrint("Web 2.El Stok Getirme Hatası: $e");
        return [];
      }
    } else {
      // --- MOBİL İÇİN: SENİN ORİJİNAL KODUN ---
      final db = await instance.database;
      // Burada sorguyu '2.EL' olarak yapıyoruz çünkü sen öyle kaydetmişsin
      return await db.query('stoklar', where: 'durum = ?', whereArgs: ['2.EL']);
    }
  }

  Future<List<Map<String, dynamic>>> stokListesiGetir() async {
    final db = await instance.database;

    if (kIsWeb) {
      try {
        var snapshot = await FirebaseFirestore.instance.collection('stoklar').get();
        var firmaSnap = await FirebaseFirestore.instance.collection('tarim_firmalari').get();
        Map<String, String> firmaMap = {for (var d in firmaSnap.docs) d.id: (d.data()['ad'] ?? 'GENEL').toString()};

        return snapshot.docs.map((doc) {
          Map<String, dynamic> data = doc.data();
          String cKod = data['cari_kod']?.toString() ?? "";

          // 🔥 WEB ÇİFT MÜHÜR: Buluttaki iki ihtimali de (ı ve i) yakala
          double tazeFiyat = double.tryParse((data['alis_fiyatı'] ?? data['alis_fiyati'] ?? data['fiyat'] ?? '0').toString()) ?? 0.0;

          return {
            ...data,
            'id': doc.id.hashCode,
            'firebase_id': doc.id,
            'fiyat': tazeFiyat,
            'firma_unvani': firmaMap[cKod] ?? 'GENEL',
            'sube': (data['sube'] ?? 'TEFENNİ').toString().toUpperCase(),
          };
        }).toList();
      } catch (e) { return []; }
    }

    // --- MOBİL İÇİN ASIL MÜHÜR: JOIN'Lİ SORGU ---
    final List<Map<String, dynamic>> yerelStoklar = await db.rawQuery('''
    SELECT 
      s.*, 
      f.ad as firma_unvani,
      s.fiyat as fiyat 
    FROM stoklar s
    LEFT JOIN tarim_firmalari f ON s.cari_kod = f.cari_kod
    WHERE s.silindi = 0
    ORDER BY s.id DESC
  ''');

    // Eğer yerel boşsa veya fiyatlar sıfır kalmışsa Firebase'den indir/güncelle
    if (yerelStoklar.isEmpty) {
      try {
        var snapshot = await FirebaseFirestore.instance.collection('stoklar').get();
        for (var doc in snapshot.docs) {
          Map<String, dynamic> veri = doc.data();

          // 🔥 EN KRİTİK TAMİRAT:
          // Firestore dökümanındaki 'alis_fiyatı' (ı ile) ve 'alis_fiyati' (i ile) alanlarının
          // hangisinde veri varsa havada yakalayıp garantiliyoruz!
          double cekilenFiyat = double.tryParse((veri['alis_fiyatı'] ?? veri['alis_fiyati'] ?? veri['fiyat'] ?? '0').toString()) ?? 0.0;

          await db.insert('stoklar', {
            'firebase_id': doc.id,
            'urun': (veri['urun'] ?? "").toString().toUpperCase(),
            'marka': (veri['marka'] ?? "").toString().toUpperCase(),
            'model': (veri['model'] ?? "").toString().toUpperCase(),
            'alt_model': (veri['alt_model'] ?? "").toString().toUpperCase(),
            'cari_kod': veri['cari_kod'],

            // SQLite'daki adı 'fiyat' olan kolona temiz sayıyı çiviliyoruz
            'fiyat': cekilenFiyat,

            'adet': double.tryParse(veri['adet']?.toString() ?? '0') ?? 0.0,
            'durum': (veri['durum']?.toString().contains("SIF") ?? true) ? "SIFIR" : "2. EL",
            'sube': (veri['sube'] ?? "TEFENNİ").toString().toUpperCase(),
            'silindi': 0,
            'is_synced': 1,
          });
        }

        return await db.rawQuery('''
        SELECT s.*, f.ad as firma_unvani FROM stoklar s 
        LEFT JOIN tarim_firmalari f ON s.cari_kod = f.cari_kod 
        WHERE s.silindi = 0 ORDER BY s.id DESC
      ''');
      } catch (e) { print("Senkron hatası: $e"); }
    }

    return yerelStoklar;
  }

  Future<int> stokGuncelle(dynamic id, int adet, double fiyat, String firma) async {
    // 🔥 ÇİFT MÜHÜRLÜ GÜNCELLEME PAKETİ:
    // Bulutta 'ı' veya 'i' hangisi varsa ikisini de besliyoruz ki sistem açık vermesin!
    final guncellemePaketi = {
      'adet': adet,
      'alis_fiyatı': fiyat, // Firestore'daki ı harfli alan
      'alis_fiyati': fiyat, // Firestore'daki i harfli alan (Garantiye alıyoruz)
      'tarim_firmalari': firma,
      'son_guncelleme': FieldValue.serverTimestamp(),
    };

    if (kIsWeb) {
      try {
        // Web'de gelen id zaten döküman ID'sidir
        await FirebaseFirestore.instance
            .collection('stoklar')
            .doc(id.toString())
            .update(guncellemePaketi);
        return 1;
      } catch (e) {
        debugPrint("❌ Web bulut güncelleme hatası: $e");
        return 0;
      }
    } else {
      final db = await instance.database;

      // 1. Yerel SQLite Güncelleme (SQLite'da sütun adın her zaman 'fiyat')
      int res = await db.update(
        'stoklar',
        {
          'adet': adet,
          'fiyat': fiyat,
          'tarim_firmalari': firma,
          'is_synced': 0
        },
        where: 'id = ?',
        whereArgs: [id],
      );

      try {
        // Mobilde parametre olarak gelen 'id' yerel int ID'dir.
        // Firestore'u güncellemek için bu kayda ait 'firebase_id'yi yerelden sorgulayıp buluyoruz.
        final List<Map<String, dynamic>> maps = await db.query(
          'stoklar',
          columns: ['firebase_id'],
          where: 'id = ?',
          whereArgs: [id],
        );

        String? firebaseDocId;
        if (maps.isNotEmpty && maps.first['firebase_id'] != null) {
          firebaseDocId = maps.first['firebase_id'].toString();
        }

        // Eğer geçerli bir firebase_id bulabildiysek buluta gönderiyoruz
        if (firebaseDocId != null && firebaseDocId.isNotEmpty) {
          // 2. Firebase Bulut Güncelleme (Çift mühürlü paketle gerçek dökümana vuruyoruz)
          await FirebaseFirestore.instance
              .collection('stoklar')
              .doc(firebaseDocId)
              .update(guncellemePaketi);

          // Başarılıysa yerelde 'senkronize edildi' mühürü vur
          await db.update('stoklar', {'is_synced': 1}, where: 'id = ?', whereArgs: [id]);
          print("✅ Bulut ve yerel çift mühürlü fiyatla senkronize şekilde güncellendi.");
        } else {
          print("⚠️ Uyarı: Bu kayda ait yerelde 'firebase_id' bulunamadı, ilk senkronizasyonda buluta çıkacak.");
        }

      } catch (e) {
        print("❌ Güncelleme buluta gönderilemedi, yerelde kaldı (İnternet yok veya yetki hatası): $e");
      }
      return res;
    }
  }

  // --- 1. YALANCI SİLME (SOFT DELETE) FONKSİYONU ---
  Future<void> kaydiSil(int id, String tabloAdi) async {
    final db = await instance.database;
    // Kaydı gerçekten silmiyoruz, sadece 'silindi' bayrağını 1 yapıyoruz
    // is_sync'i de 0 yapıyoruz ki motor bunu fark edip Firebase'den silsin
    await db.update(
      tabloAdi,
      {'silindi': 1, 'is_synced': 0},
      where: 'id = ?',
      whereArgs: [id],
    );
    print("✅ Yerel Kayıt Silindi İşaretlendi: $tabloAdi -> $id");
  }

// --- 2. DEV SENKRONİZASYON MOTORU ---
  Future<void> tamSenkronizasyon() async {
    if (kIsWeb) return; // Web'de çalışmaz

    final db = await instance.database;

    // 40 tablonu buraya ekle (Şimdilik en kritikleri yazdım)
    List<String> tablolar = ['stoklar', 'musteriler', 'araclar', 'tarim_firmalari'];

    for (String tablo in tablolar) {
      try {
        // A) YERELDE SİLİNENLERİ WEB'DEN TEMİZLE
        var silinecekler = await db.query(tablo, where: 'silindi = 1');
        for (var kayit in silinecekler) {
          // Firebase döküman ID'si senin yerel ID'n ile aynı (Örn: 1718012...)
          await FirebaseFirestore.instance.collection(tablo).doc(kayit['id'].toString()).delete();
          // Firebase'den silme başarılıysa, yerelden tamamen uçurabiliriz
          await db.delete(tablo, where: 'id = ?', whereArgs: [kayit['id']]);
          print("🗑️ $tablo: ${kayit['id']} Buluttan ve Cepten Temizlendi.");
        }

        // B) WEB'DEN SİLİNENLERİ CEBE YANSIT
        var snapshot = await FirebaseFirestore.instance.collection(tablo).get();
        Set<String> webIds = snapshot.docs.map((d) => d.id.toString()).toSet();

        var yerelKayitlar = await db.query(tablo, where: 'silindi = 0');
        for (var yerel in yerelKayitlar) {
          if (!webIds.contains(yerel['id'].toString())) {
            await db.delete(tablo, where: 'id = ?', whereArgs: [yerel['id']]);
            print("🚨 Web'de Yoktu, Cepten de Silindi: ${yerel['id']}");
          }
        }
      } catch (e) {
        print("⚠️ $tablo Senkronizasyon Hatası (Muhtemelen İnternet Yok): $e");
      }
    }
  }

  // --- MÜŞTERİ VE SİLME İŞLEMLERİ ---
  Future<void> musteriSilVeBulutuGuncelle(dynamic musteriId, String musteriAd) async {
    if (kIsWeb) {
      // --- WEB İÇİN: DOĞRUDAN FIREBASE TEMİZLİĞİ ---
      try {
        // 1. Önce müşterinin satışlarını bulup stokları iade edelim
        var satislarSnapshot = await _firestore
            .collection('satislar')
            .where('musteri_ad', isEqualTo: musteriAd)
            .get();

        for (var doc in satislarSnapshot.docs) {
          var satisData = doc.data();
          if (satisData['stok_id'] != null) {
            // Stok adedini 1 artır (İade mantığı)
            await _firestore
                .collection('stoklar')
                .doc(satisData['stok_id'].toString())
                .update({'adet': FieldValue.increment(1)});
          }
          // Satış kaydını sil
          await doc.reference.delete();
        }

        // 2. Müşteri hareketlerini sil
        var hareketlerSnapshot = await _firestore
            .collection('musteri_hareketleri')
            .where('musteri_ad', isEqualTo: musteriAd)
            .get();

        for (var doc in hareketlerSnapshot.docs) {
          await doc.reference.delete();
        }

        // 3. Müşterinin kendisini sil
        await _firestore.collection('musteriler').doc(musteriAd).delete();

        debugPrint("✅ Web: Müşteri, hareketleri ve satışları silindi, stoklar iade edildi.");
      } catch (e) {
        debugPrint("❌ Web Müşteri Silme Hatası: $e");
      }
    } else {
      // --- MOBİL İÇİN: SENİN ORİJİNAL SAĞLAM TRANSACTION KODUN ---
      final db = await instance.database;
      await db.transaction((txn) async {
        List<Map<String, dynamic>> sonSatislar = await txn.query('satislar', where: 'musteri_ad = ?', whereArgs: [musteriAd]);
        for (var satis in sonSatislar) {
          if (satis['stok_id'] != null) {
            await txn.execute('UPDATE stoklar SET adet = adet + 1 WHERE id = ?', [satis['stok_id']]);
            await _firestore.collection('stoklar').doc(satis['stok_id'].toString()).update({'adet': FieldValue.increment(1)});
          }
        }
        await txn.delete('musteriler', where: 'id = ?', whereArgs: [musteriId]);
        await txn.delete('musteri_hareketleri', where: 'musteri_ad = ?', whereArgs: [musteriAd]);
        await _firestore.collection('musteriler').doc(musteriAd).delete();
      });
    }
  }

  Future<void> cekSenetEkle(CekModel cek) async {
    if (kIsWeb) {
      // --- WEB İÇİN: KUYRUĞA GİRMEDEN DİREKT BULUTA ---
      try {
        // Eğer ID yoksa Firebase kendisi bir ID oluştursun
        String docId = (cek.id != null && cek.id.toString().length > 5)
            ? cek.id.toString()
            : FirebaseFirestore.instance.collection('cekler').doc().id;

        await FirebaseFirestore.instance
            .collection('cekler')
            .doc(docId)
            .set({
          ...cek.toMap(),
          'id': docId, // Firebase ID'sini modele geri çakıyoruz
          'is_synced': 1,
          'son_guncelleme': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        print("✅ Web: Çek saniyeler içinde buluta mühürlendi.");
      } catch (e) {
        print("❌ Web: Çek buluta yazılamadı: $e");
      }
    } else {
      // --- MOBİL İÇİN: SENİN ORİJİNAL KUYRUKLU SİSTEMİN ---
      final db = await instance.database;

      // 1. SQLite Kaydı
      await db.insert('cekler', cek.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);

      // 2. Kuyruğa Ekle
      await db.insert('sync_queue', {
        'type': 'INSERT',
        'collection': 'cekler',
        'doc_id': cek.id.toString(),
        'data': jsonEncode(cek.toMap()),
        'is_synced': 0,
        'created_at': DateTime.now().toIso8601String(),
      });
      print("✅ Çek kaydedildi ve sıraya alındı.");
    }
  }


  Future<void> musteriSilVeStoklariGeriYukle(String musteriId) async {
    print("🚀 [DEBUG] Silme işlemi başladı. Müşteri ID: '$musteriId'");

    if (kIsWeb) {
      // --- WEB İÇİN: DOĞRUDAN FIREBASE TEMİZLİĞİ ---
      try {
        print("🌐 [DEBUG] Web: Firebase üzerinden müşteri ve hareketleri siliniyor...");

        // 1. Önce müşteriye ait hareketleri Firebase'den bulup silelim
        var hareketlerSnapshot = await FirebaseFirestore.instance
            .collection('musteri_hareketleri')
            .where('musteri_id', isEqualTo: musteriId)
            .get();

        for (var doc in hareketlerSnapshot.docs) {
          await doc.reference.delete();
          print("✅ [DEBUG] Firebase: Hareket silindi (ID: ${doc.id})");
        }

        // 2. Müşterinin ana kaydini sil
        await FirebaseFirestore.instance
            .collection('musteriler')
            .doc(musteriId)
            .delete();

        print("✅ [DEBUG] Firebase: Müşteri ana kaydı silindi.");
        print("🏁 [DEBUG] Web: Silme işlemi başarıyla tamamlandı.");
      } catch (e) {
        print("❌ [DEBUG] Web Silme Hatası: $e");
      }
    } else {
      // --- MOBİL İÇİN: SENİN ORİJİNAL TRANSACTION MANTIĞIN ---
      final db = await instance.database;
      try {
        // 1. Önce SQL'den hareketleri alalım (Firebase'den de silmek için)
        final hareketler = await db.query(
          'musteri_hareketleri',
          where: 'musteri_id = ?',
          whereArgs: [musteriId],
        );
        print("🔍 [DEBUG] SQL'de bu müşteriye ait ${hareketler.length} adet hareket bulundu.");

        await db.transaction((txn) async {
          // 2. SQL Temizliği
          int hareketSilinen = await txn.delete('musteri_hareketleri', where: 'musteri_id = ?', whereArgs: [musteriId]);
          print("🗑️ [DEBUG] SQL: $hareketSilinen adet hareket silindi.");

          int musteriSilinen = await txn.delete('musteriler', where: 'id = ?', whereArgs: [musteriId]);
          print("🗑️ [DEBUG] SQL: $musteriSilinen adet müşteri kaydı silindi.");

          // --- FIREBASE TEMİZLİĞİ ---
          print("🌐 [DEBUG] Firebase silme denemesi başlatılıyor...");

          // Müşteriyi Firebase'den uçur
          await FirebaseFirestore.instance.collection('musteriler').doc(musteriId).delete().then((_) {
            print("✅ [DEBUG] Firebase: Müşteri ana kaydı silindi.");
          }).catchError((e) => print("❌ [DEBUG] Firebase Hata (Müşteri): $e"));

          // Hareketleri Firebase'den uçur
          for (var h in hareketler) {
            String hId = h['id'].toString();
            await FirebaseFirestore.instance.collection('musteri_hareketleri').doc(hId).delete().then((_) {
              print("✅ [DEBUG] Firebase: Hareket silindi (ID: $hId)");
            }).catchError((e) => print("❌ [DEBUG] Firebase Hata (Hareket $hId): $e"));
          }
        });

        print("🏁 [DEBUG] Silme işlemi başarıyla tamamlandı.");
      } catch (e) {
        print("‼️ [DEBUG] KRİTİK HATA: $e");
      }
    }
  }

  Future<void> stokTransferEt({
    required dynamic urunId, // Web'de String ID gelebileceği için dynamic yaptık
    required String kaynakSube,
    required String hedefSube,
    required int adet,
    String? aciklama,
  }) async {
    if (kIsWeb) {
      // --- WEB İÇİN: DOĞRUDAN FIREBASE GÜNCELLEME ---
      try {
        print("🌐 [DEBUG] Web: Stok transferi Firebase üzerinden yapılıyor...");

        // 1. Ana stok kartında şubeyi güncelle
        await _firestore.collection('stoklar').doc(urunId.toString()).update({
          'sube': hedefSube,
          'son_islem_tarihi': FieldValue.serverTimestamp(),
        });

        // 2. Firebase'de hareket dökümanı oluştur
        await _firestore.collection('stok_hareketleri').add({
          'urun_id': urunId,
          'islem': 'TRANSFER',
          'nereden': kaynakSube,
          'nereye': hedefSube,
          'adet': adet,
          'aciklama': aciklama ?? 'Şubeler Arası Sevk',
          'timestamp': FieldValue.serverTimestamp(),
        });

        print("✅ Web: Sevkiyat ve hareket kaydı Firebase'de mühürlendi.");
      } catch (e) {
        print("❌ Web Firebase Transfer Hatası: $e");
      }
    } else {
      // --- MOBİL İÇİN: SENİN ORİJİNAL TRANSACTION KODUN ---
      final db = await instance.database;

      // 1. ADIM: SQLite Transaction
      await db.transaction((txn) async {
        // Şubeyi güncelle
        await txn.update(
          'stoklar',
          {'sube': hedefSube},
          where: 'id = ?',
          whereArgs: [urunId],
        );

        // Stok hareketlerine yerel kayıt
        await txn.insert('stok_hareketleri', {
          'stok_id': urunId,
          'marka': 'SEVK',
          'model': '$kaynakSube -> $hedefSube',
          'adet': adet,
          'sube': hedefSube,
          'tarih': DateTime.now().toIso8601String(),
        });
      });

      // 2. ADIM: Firebase Senkronizasyonu
      try {
        // A - Ana stok kartında şubeyi güncelle
        await _firestore.collection('stoklar').doc(urunId.toString()).update({
          'sube': hedefSube,
          'son_islem_tarihi': FieldValue.serverTimestamp(),
        });

        // B - Firebase'de hareket dökümanı oluştur
        await _firestore.collection('stok_hareketleri').add({
          'urun_id': urunId,
          'islem': 'TRANSFER',
          'nereden': kaynakSube,
          'nereye': hedefSube,
          'adet': adet,
          'aciklama': aciklama ?? 'Şubeler Arası Sevk',
          'timestamp': FieldValue.serverTimestamp(),
        });

        print("✅ Firebase: Sevkiyat ve hareket kaydı mühürlendi.");
      } catch (e) {
        print("❌ Firebase Senkronizasyon Hatası: $e");
      }
    }
  }


  Future<void> firebaseStokSenkronize(Map<String, dynamic> stokVerisi) async {
    try {
      // Web veya Mobil fark etmeksizin doğrudan Firebase'e yazar.
      // Ancak Web'de işlem yaparken bir log düşmesi hata ayıklamanı kolaylaştırır.
      if (kIsWeb) {
        print("🌐 Web: ${stokVerisi['urun']} doğrudan buluta gönderiliyor...");
      }

      await FirebaseFirestore.instance
          .collection('isletmeler')
          .doc('evren_ticaret')
          .collection('stoklar')
          .add({
        'kategori': stokVerisi['kategori'],
        'marka': stokVerisi['marka'],
        'urun': stokVerisi['urun'],
        'alt_model': stokVerisi['altModel'],
        'cins': stokVerisi['altModel'],
        'adet': stokVerisi['adet'],
        'fiyat': stokVerisi['fiyat'],
        'durum': stokVerisi['durum'],
        'sube': stokVerisi['sube'],
        'tarih': stokVerisi['tarih'],
        'is_synced': 1, // Web'de eklenen zaten senkronize sayılır
        'kayit_tarihi': FieldValue.serverTimestamp(),
      });

      print("✅ Firebase TAMAM: ${stokVerisi['urun']} - ${stokVerisi['altModel']} eklendi.");
    } catch (e) {
      print("❌ Firebase Hatası: $e");
    }
  }

// --- STOK MİKTARINI GÜNCELLEME (Senin Tablo Yapına Göre) ---
  Future<int> stokMiktariGuncelle(int stokId, double miktar) async {
    final db = await instance.database;

    // Senin tablonda sütun adı 'adet', miktar değil.
    // O yüzden burayı 'adet = adet + ?' olarak düzelttik.
    return await db.rawUpdate('''
    UPDATE stoklar 
    SET adet = adet + ? 
    WHERE id = ?
  ''', [miktar, stokId]);
  }




  // Süslü parantez { } içindeki kısımlar opsiyonel parametredir
  Future<int> stokEkle(Map<String, dynamic> data, {bool fromFirebase = false}) async {
    try {
      String normalize(dynamic v) => (v == null) ? "" : v.toString().trim().toUpperCase();


      final String marka = normalize(data['marka']);
      final String model = normalize(data['model']);
      final String altModel = normalize(data['alt_model'] ?? data['altmodel']);
      final String sube = normalize(data['sube'] ?? "TEFENNİ");

      // Önce cari kodu yakala (Excel'den 'cari_kod' veya 'tarim_firmalari' gelebilir)
      final String cariKod = normalize(data['tarim_firmalari'] ?? data['cari_kod'] ?? "");

// Mühür'e cari kodu da ekle ki farklı firmaların aynı ürünü birbirini ezmesin
      final String muhur = [sube, marka, model, altModel, cariKod].join("|");


      Map<String, dynamic> stokVerisi = {
        'firebase_id': muhur,
        'urun': [marka, model, altModel].where((e) => e.isNotEmpty).join(" "),
        'marka': marka,
        'model': model,
        'alt_model': altModel,
        'altmodel': altModel,
        'sube': sube,
        'adet': double.tryParse(data['adet']?.toString() ?? "0") ?? 0.0,
        // Eski hali: 'fiyat': double.tryParse(data['fiyat']?.toString() ?? "0") ?? 0.0,
// Yeni ve Garantili Hali:
        'fiyat': double.tryParse((data['alis_fiyatı'] ?? data['alis_fiyati'] ?? data['fiyat'] ?? "0").toString()) ?? 0.0,
        'kategori': normalize(data['kategori']),
        'tarim_firmalari': normalize(data['tarim_firmalari']),
        'silindi': data['silindi'] ?? 0,
        'is_synced': fromFirebase ? 1 : 0, // Firebase'den gelmişse zaten senkronludur
        'son_guncelleme': DateTime.now().toIso8601String(),
      };

      final db = await instance.database;

      // SQL'e Kaydet/Güncelle
      int id = await db.insert(
          'stoklar',
          stokVerisi,
          conflictAlgorithm: ConflictAlgorithm.replace
      );

      // 🔥 KRİTİK NOKTA: Eğer veri zaten Firebase'den gelmişse,
      // tekrar Firebase'e geri gönderme! (Döngü engelleyici)
      if (!fromFirebase) {
        try {
          await FirebaseFirestore.instance
              .collection('isletmeler')
              .doc('evren_ticaret')
              .collection('stoklar')
              .doc(muhur)
              .set(stokVerisi, SetOptions(merge: true));

          // Başarıyla gittiyse SQL'de senkron edildi yap
          await db.update('stoklar', {'is_synced': 1}, where: 'id = ?', whereArgs: [id]);
        } catch (e) {
          print("☁️ Firebase'e ulaşılamadı, mühür yerelde kaldı.");
        }
      }

      return id;
    } catch (e) {
      debugPrint("❌ stokEkle HATA: $e");
      return -1;
    }
  }


// Yardımcı Fonksiyon (Firebase'e asenkron basar) - "ü" harfi "u" yapıldı
  void _firebaseStokGuncelle(String muhur, double adet, double fiyat, {Map<String, dynamic>? fullData}) {
    // .doc(muhur) kısmında gelen string içinde hala "ü" varsa o da patlatır!
    // O yüzden muhur'u buraya göndermeden önce turkceKarakterTemizle'den geçirmiş olmalısın.

    var ref = FirebaseFirestore.instance.collection('stoklar').doc(muhur);

    if (fullData != null) {
      ref.set({
        ...fullData,
        'son_guncelleme': FieldValue.serverTimestamp()
      }, SetOptions(merge: true));
    } else {
      ref.update({
        'adet': adet,
        'fiyat': fiyat,
        'son_guncelleme': FieldValue.serverTimestamp()
      });
    }
  }

  String turkceKarakterTemizle(String metin) {
  var turkishChars = {'ı': 'i', 'İ': 'I', 'ş': 's', 'Ş': 'S', 'ğ': 'g', 'Ğ': 'G', 'ü': 'u', 'Ü': 'U', 'ö': 'o', 'Ö': 'O', 'ç': 'c', 'Ç': 'C'};
  turkishChars.forEach((key, value) {
  metin = metin.replaceAll(key, value);
  });
  // Boşlukları alt tire yap ve sadece harf/rakam bırak
  return metin.replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_').toUpperCase();
  }
  // Bu fonksiyonu DatabaseHelper sınıfının içine yapıştır:

  Future<int> stokSyncGuncelle(String stokKodu, int durum) async {
    final db = await instance.database;
    return await db.update(
      'stoklar',
      {'is_synced': durum}, // durum: 1 (başarılı), 0 (bekliyor)
      where: 'stok_kodu = ?',
      whereArgs: [stokKodu],
    );
  }

  Future<int> stokTanimEkle(Map<String, dynamic> data) async {
    try {
      String normalize(dynamic v) => (v == null) ? "" : v.toString().trim().toUpperCase();

      final String marka = normalize(data['marka']);
      final String model = normalize(data['model']);
      final String altModel = normalize(data['alt_model'] ?? data['altmodel']);
      final String kategori = normalize(data['kategori']);
      final String firmaKod = normalize(data['firma_kod'] ?? data['tarim_firmalari'] ?? "GENEL");
      final String sube = normalize(data['sube'] ?? "TEFENNİ");

      // ==========================================
      // STOK TANIM MÜHRÜ (Kimlik Kartı)
      // ==========================================
      final String muhur = [firmaKod, sube, kategori, marka, model, altModel].join("|");

      Map<String, dynamic> tanimVerisi = {
        'firebase_id': muhur,
        'stok_kodu': "SK-$muhur", // Stok kodu mühürden türetildi
        'kategori': kategori,
        'marka': marka,
        'model': model,
        'alt_model': altModel,
        'altmodel': altModel, // Geriye dönük uyumluluk
        'tarim_firmalari': firmaKod,
        'sube': sube,
        'urun': [marka, model, altModel].where((e) => e.isNotEmpty).join(" "),
        'durum': normalize(data['durum'] ?? "AKTIF"),
        'silindi': 0,
        'is_synced': 0,
        'son_guncelleme': DateTime.now().toIso8601String(),
      };

      final db = await instance.database;
      final mevcut = await db.query('stok_tanimlari', where: 'firebase_id = ?', whereArgs: [muhur]);

      int id;
      if (mevcut.isNotEmpty) {
        id = mevcut.first['id'] as int;
        await db.update('stok_tanimlari', tanimVerisi, where: 'id = ?', whereArgs: [id]);
      } else {
        id = await db.insert('stok_tanimlari', tanimVerisi);
      }

      // FIREBASE SENKRON (Mühür döküman ID'sidir)
      try {
        await FirebaseFirestore.instance.collection('stok_tanimlari').doc(muhur).set({
          ...tanimVerisi,
          'sql_id': id,
          'server_timestamp': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        await db.update('stok_tanimlari', {'is_synced': 1}, where: 'id = ?', whereArgs: [id]);
      } catch (_) {}

      return id;
    } catch (e) {
      debugPrint("❌ stokTanimEkle HATA: $e");
      return -1;
    }
  }


  Future<int> stokHareketEkle(Map<String, dynamic> row) async {
    // 1. VERİLERİ HAZIRLA VE STANDARTLAŞTIR
    final String marka = row['marka']?.toString().toUpperCase().trim() ?? "";
    final String model = row['model']?.toString().toUpperCase().trim() ?? "";
    final String urunAdi = row['urun']?.toString().toUpperCase().trim() ?? "ÜRÜN";

    // KRİTİK: Cari kod döküman ID'sidir, isimle karıştırma
    final String cariKod = row['cari_kod']?.toString() ?? "";
    final String tip = row['tip']?.toString().toUpperCase() ?? "ALIM";

    final double miktar = double.tryParse(row['adet']?.toString() ?? "0") ?? 0.0;
    final double birimFiyat = double.tryParse(row['fiyat']?.toString() ?? "0") ?? 0.0;
    final double toplamTutar = miktar * birimFiyat;

    // Senin sisteminin ana tarih formatı: dd.MM.yyyy
    final String tarihFormat = DateFormat('dd.MM.yyyy').format(DateTime.now());
    final String suanIso = DateTime.now().toIso8601String();

    // Benzersiz Hareket Mühürü (H-TIMESTAMP)
    final String hareketMuhuru = "H-${DateTime.now().millisecondsSinceEpoch}";

    // ORTAK VERİ PAKETİ (SQLite ve Firebase için)
    Map<String, dynamic> hareketVerisi = {
      'stok_kodu': row['stok_kodu'] ?? "S-${DateTime.now().millisecondsSinceEpoch}",
      'cari_kod': cariKod,
      'urun_adi': "$urunAdi $marka $model".trim(),
      'adet': miktar,
      'fiyat': birimFiyat,
      'tutar': toplamTutar,
      'tarih': tarihFormat,
      'tip': tip,
      'is_synced': 1,
      'firebase_id': hareketMuhuru,
      'silindi': 0,
    };

    // --- WEB İÇİN: DOĞRUDAN BULUT KAYDI ---
    if (kIsWeb) {
      try {
        final batch = FirebaseFirestore.instance.batch();

        // A. Firma Hareketlerine (Ekstreye) Yaz
        var hareketRef = FirebaseFirestore.instance.collection('tarim_firma_hareketleri').doc(hareketMuhuru);
        batch.set(hareketRef, {
          ...hareketVerisi,
          'server_tarih': FieldValue.serverTimestamp(),
        });

        // B. Bakiyeyi Güncelle (Alacak/Borç mühürleniyor)
        var firmaRef = FirebaseFirestore.instance.collection('tarim_firmalari').doc(cariKod);
        String alan = (tip == 'ALIM') ? 'alacak' : 'borc';
        batch.update(firmaRef, {
          alan: FieldValue.increment(toplamTutar),
          'son_islem_tarihi': FieldValue.serverTimestamp(),
        });

        await batch.commit();
        return 1;
      } catch (e) {
        debugPrint("❌ Web Hareket Hatası: $e");
        return -1;
      }
    }

    // --- MOBİL İÇİN: SQLite + FIREBASE BATCH ---
    final db = await instance.database;

    try {
      await db.transaction((txn) async {
        // 1. Firma Hareketini Yerel SQLite'a Yaz (Doğru Tablo: tarim_firma_hareketleri)
        await txn.insert('tarim_firma_hareketleri', {
          ...hareketVerisi,
          'is_synced': 0, // Önce 0, bulut onaylayınca 1 olacak
        });

        // 2. Bakiyeyi Yerelde Güncelle
        String alan = (tip == 'ALIM') ? 'alacak' : 'borc';
        await txn.rawUpdate(
            'UPDATE tarim_firmalari SET $alan = $alan + ? WHERE cari_kod = ?',
            [toplamTutar, cariKod]
        );
      });

      // 3. FIREBASE SENKRONU (İnternet varsa)
      try {
        final batch = FirebaseFirestore.instance.batch();

        var hareketRef = FirebaseFirestore.instance.collection('tarim_firma_hareketleri').doc(hareketMuhuru);
        batch.set(hareketRef, {
          ...hareketVerisi,
          'server_tarih': FieldValue.serverTimestamp(),
        });

        var firmaRef = FirebaseFirestore.instance.collection('tarim_firmalari').doc(cariKod);
        String alan = (tip == 'ALIM') ? 'alacak' : 'borc';
        batch.update(firmaRef, {
          alan: FieldValue.increment(toplamTutar),
          'son_islem_tarihi': FieldValue.serverTimestamp(),
        });

        await batch.commit();

        // Buluta gittiyse SQL'de mühürle
        await db.update('tarim_firma_hareketleri', {'is_synced': 1},
            where: 'firebase_id = ?', whereArgs: [hareketMuhuru]);

        debugPrint("✅ Mobil: Hareket ve Bakiye bulutta mühürlendi.");
      } catch (e) {
        debugPrint("⚠️ İnternet Yok: Kayıt sadece yerelde kaldı, sonra senkron olacak.");
      }

      return 1;
    } catch (e) {
      debugPrint("❌ Mobil İşlem Hatası: $e");
      return -1;
    }
  }


  // DatabaseHelper içindeki ilgili kısmı şöyle güncelle:
  Future<int> stokFotoGuncelle(int id, String yol, {String? firebaseId}) async {
    final db = await instance.database;

    // 1. Yerel Veritabanını Güncelle (Bu zaten çalışıyor)
    int result = await db.update(
      'stoklar',
      {'foto': yol},
      where: 'id = ?',
      whereArgs: [id],
    );

    // 2. Firebase Güncelleme Mantığı
    if (firebaseId != null && firebaseId != "null" && firebaseId.isNotEmpty) {
      try {
        String gonderilecekVeri = yol;

        // Eğer yol internet linki DEĞİLSE (yani yerel dosyaysa) Base64'e çevir
        if (!yol.startsWith('http')) {
          File file = File(yol);
          if (await file.exists()) {
            List<int> imageBytes = await file.readAsBytes();
            String base64Image = base64Encode(imageBytes);
            gonderilecekVeri = "data:image/jpeg;base64,$base64Image";
            debugPrint("📸 [FIREBASE] Yerel foto Base64'e çevrildi.");
          }
        }

        await FirebaseFirestore.instance
            .collection('stoklar')
            .doc(firebaseId)
            .update({'foto': gonderilecekVeri});

        debugPrint("✅ [FIREBASE] Bulut güncelleme başarılı.");
      } catch (e) {
        debugPrint("❌ [FIREBASE HATA] Yazılamadı: $e");
      }
    } else {
      debugPrint("⚠️ [FIREBASE] Firebase ID bulunamadığı için bulut güncellenmedi.");
    }

    return result;
  }




  Future<List<Map<String, dynamic>>> stokTanimlariniGetir() async {
    final db = await database;

    if (kIsWeb) {
      try {
        print("🌐 Web: Stok tanımları buluttan canlı çekiliyor...");
        final snapshot = await FirebaseFirestore.instance.collection('stok_tanimlari').get();
        return snapshot.docs.map((doc) {
          Map<String, dynamic> data = doc.data();
          data['id'] = doc.id; // Web'de doküman ID'sini kullanıyoruz
          return data;
        }).toList();
      } catch (e) {
        print("❌ Web Stok Hatası: $e");
        return [];
      }
    } else {
      // --- MOBİL: FIREBASE'DEN ÇEK VE SQL'E MÜHÜRLE ---
      try {
        print("🚀 Mobil: Stok tanımları senkronize ediliyor...");
        final snapshot = await FirebaseFirestore.instance.collection('stok_tanimlari').get();

        if (snapshot.docs.isNotEmpty) {
          for (var doc in snapshot.docs) {
            Map<String, dynamic> data = doc.data();

            // Senin yeni tablo yapına tam uyumlu veri haritası
            await db.insert(
              "stok_tanimlari",
              {
                "firebase_id": doc.id,
                "stok_kodu": data["stok_kodu"], // Eğer Firebase'de varsa
                "kategori": (data["kategori"] ?? "GENEL").toString().toUpperCase(),
                "marka": (data["marka"] ?? "").toString().toUpperCase(),
                "model": (data["model"] ?? "").toString().toUpperCase(),
                "alt_model": (data["alt_model"] ?? data["altmodel"] ?? "").toString().toUpperCase(),
                "urun": data["urun"],
                "tarim_firmalari": data["tarim_firmalari"],
                "durum": data["durum"] ?? "AKTIF",
                "sube": data["sube"] ?? "TEFENNİ",
                "is_synced": 1, // Firebase'den geldiği için senkronlu işaretliyoruz
                "son_guncelleme": DateTime.now().toIso8601String(),
              },
              // KRİTİK: Mühürler çakışırsa (aynı stok varsa) veriyi güncelle, hata verme.
              conflictAlgorithm: ConflictAlgorithm.replace,
            );
          }
          print("✅ Mobil: ${snapshot.docs.length} adet stok tanımı güncellendi.");
        }
      } catch (e) {
        print("⚠️ Mobil Sync Atlandı (Muhtemelen İnternet Yok): $e");
      }

      // Her durumda en son yerel veritabanından güncel listeyi dön
      return await db.query('stok_tanimlari', orderBy: "kategori, marka, model");
    }
  }




  Future<void> bulutlaSenkronizeEt() async {
    // --- WEB KORUMASI: Web'de kuyruk olmadığı için bu fonksiyonu hemen bitir ---
    if (kIsWeb) {
      print("🌐 Web: Senkronizasyon kuyruğuna gerek yok, işlemler anlık yapılıyor.");
      return;
    }

    // --- MOBİL İÇİN: SENİN ORİJİNAL POSTACI MANTIĞIN ---
    final db = await instance.database;

    // Kuyruktaki (gönderilmemiş) işlemleri al
    List<Map<String, dynamic>> kuyruk = await db.query(
        'sync_queue',
        where: 'is_synced = ?',
        whereArgs: [0]
    );

    if (kuyruk.isEmpty) {
      print("☁️ Senkronize edilecek veri yok.");
      return;
    }

    print("🚀 ${kuyruk.length} adet işlem buluta gönderiliyor...");

    for (var islem in kuyruk) {
      try {
        String collection = islem['collection'];
        String docId = islem['doc_id'];
        Map<String, dynamic> veri = jsonDecode(islem['data']);

        if (islem['type'] == 'INSERT' || islem['type'] == 'UPDATE') {
          await _firestore
              .collection(collection)
              .doc(docId)
              .set({...veri, 'sonGuncelleme': FieldValue.serverTimestamp()}, SetOptions(merge: true));
        }
        else if (islem['type'] == 'DELETE') {
          await _firestore
              .collection(collection)
              .doc(docId)
              .delete();
        }

        // Başarılıysa telefonun içindeki listede "tamam" diye işaretle
        await db.update('sync_queue', {'is_synced': 1}, where: 'id = ?', whereArgs: [islem['id']]);
        print("✅ Veri mühürlendi: $collection -> $docId");

      } catch (e) {
        print("❌ Firebase Bağlantı Hatası: $e");
        break; // Bir hata olursa döngüyü kır, internet gelince tekrar dener
      }
    }
  }

  // Tüm metodlar bunu kullanacak, Firebase karmaşası bitecek
  Future<void> _kuyrugaEkle(String tip, String tablo, String docId, Map<String, dynamic> veri) async {

    if (kIsWeb) {
      // --- WEB İÇİN: KUYRUK YOK, DİREKT BULUTA GÖNDER ---
      try {
        print("🌐 Web: Kuyruk baypas edildi, direkt Firebase'e gidiyor: $tablo -> $docId");

        if (tip == 'DELETE') {
          await FirebaseFirestore.instance.collection(tablo).doc(docId).delete();
        }
        else if (tip == 'UPDATE_BALANCE') {
          // Tahsilat/Ödeme için atomik bakiye güncelleme
          double miktar = double.tryParse(veri['miktar'].toString()) ?? 0.0;
          await FirebaseFirestore.instance.collection(tablo).doc(docId).update({
            'bakiye': FieldValue.increment(miktar),
            'son_islem': FieldValue.serverTimestamp(),
          });
        }
        else {
          // INSERT veya UPDATE durumunda
          await FirebaseFirestore.instance.collection(tablo).doc(docId).set({
            ...veri,
            'sonGuncelleme': FieldValue.serverTimestamp()
          }, SetOptions(merge: true));
        }
        print("✅ Web: İşlem anında mühürlendi.");
      } catch (e) {
        print("❌ Web Direkt Gönderim Hatası: $e");
      }
    } else {
      // --- MOBİL İÇİN: SENİN ORİJİNAL KUYRUK MANTIĞIN ---
      final db = await instance.database;
      await db.insert('sync_queue', {
        'type': tip, // INSERT, DELETE, UPDATE_BALANCE
        'collection': tablo,
        'doc_id': docId,
        'data': jsonEncode(veri),
        'is_synced': 0,
        'created_at': DateTime.now().toIso8601String(),
      });
      print("📦 Mobil: İşlem yerel kuyruğa eklendi ($tip)");
    }
  }

  Future<void> herSeyiSenkronizeEt() async {
    // --- WEB KORUMASI ---
    // Web'de SQLite/Kuyruk yapısı olmadığı için bu fonksiyonu hemen bitiriyoruz.
    if (kIsWeb) {
      print("🌐 Web: Senkronizasyon kuyruğuna gerek yok, işlemler anlık yapılıyor.");
      return;
    }

    // --- MOBİL İÇİN: SENİN ORİJİNAL SENKRONİZE MOTORUN ---
    final db = await instance.database;

    // Kuyrukta gönderilmeyi bekleyen (is_synced = 0) işlemleri çek
    List<Map<String, dynamic>> bekleyenler = await db.query(
        'sync_queue',
        where: 'is_synced = ?',
        whereArgs: [0]
    );

    if (bekleyenler.isEmpty) {
      print("☁️ Bekleyen veri yok, bulut güncel.");
      return;
    }

    print("🚀 ${bekleyenler.length} adet işlem buluta gönderiliyor...");

    for (var islem in bekleyenler) {
      try {
        final data = jsonDecode(islem['data']);
        final collection = islem['collection'];
        final docId = islem['doc_id'];
        final type = islem['type'];

        if (type == 'INSERT' || type == 'UPDATE') {
          await _firestore.collection(collection).doc(docId).set({
            ...data,
            'server_time': FieldValue.serverTimestamp()
          }, SetOptions(merge: true));
        }
        else if (type == 'DELETE') {
          await _firestore.collection(collection).doc(docId).delete();
        }
        else if (type == 'UPDATE_BALANCE') {
          // Müşteri bakiyesini atomik olarak güncelle
          await _firestore.collection('musteriler').doc(docId).update({
            'bakiye': FieldValue.increment(data['miktar'])
          });

          // Varsa hareket kaydını da ekle (Kuyruktaki veri içinde 'hareket' varsa)
          if (data['hareket'] != null) {
            await _firestore.collection('musteri_hareketleri').add({
              ...data['hareket'],
              'server_time': FieldValue.serverTimestamp()
            });
          }
        }

        // İşlem bitince telefonda (SQLite) "gönderildi" olarak işaretle
        await db.update(
            'sync_queue',
            {'is_synced': 1},
            where: 'id = ?',
            whereArgs: [islem['id']]
        );

        print("✅ $collection -> $docId mühürlendi.");

      } catch (e) {
        print("❌ İnternet yok veya bağlantı koptu, bekleniyor: $e");
        break; // Bir hata olursa döngüyü kır, internet gelince tekrar dener.
      }
    }
  }



  Future<int> musteriHareketEkle(Map<String, dynamic> veri) async {
    // 🔑 ID ÇÖZÜMLEME: Buluttan veya başka yerden gelen mühürlü bir ID var mı?
    String? gelenId = (veri['id'] ?? veri['sqlite_id'])?.toString();

    // 🧼 VERİ TEMİZLEME (Ortak Kısım)
    Map<String, dynamic> temizVeri = {
      'musteri_id': (veri['musteri_id'] ?? veri['id'] ?? '').toString(),
      'musteri_ad': (veri['musteri_ad'] ?? veri['ad'] ?? 'BİLİNMEYEN')
          .toString()
          .toUpperCase()
          .trim(),
      'islem': (veri['islem'] ?? veri['tip'] ?? 'SATIŞ')
          .toString()
          .toUpperCase(),
      'tutar': double.tryParse(veri['tutar']?.toString() ?? '0') ?? 0.0,
      'aciklama': (veri['aciklama'] ?? '').toString(),
      'tarih': veri['tarih'] ?? DateFormat('dd.MM.yyyy').format(DateTime.now()),
      'is_synced': kIsWeb ? 1 : 0,
    };

    // --- WEB İÇİN: DOĞRUDAN FIREBASE İŞLEMLERİ ---
    if (kIsWeb) {
      try {
        print("🌐 Web: Müşteri hareketi buluta işleniyor...");
        String mId = temizVeri['musteri_id'];
        double miktar = temizVeri['tutar'];

        // Web'de de döküman adını mühürlü yapalım ki çakışmasın
        String docId = gelenId ?? "HL_${DateTime.now().millisecondsSinceEpoch}";

        await FirebaseFirestore.instance
            .collection('musteri_hareketleri')
            .doc(docId)
            .set({
          ...temizVeri,
          'server_tarih': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        double guncellemeMiktari = (temizVeri['islem'] == 'TAHSILAT') ? -miktar : miktar;

        await FirebaseFirestore.instance
            .collection('musteriler')
            .doc(mId)
            .update({
          'bakiye': FieldValue.increment(guncellemeMiktari),
          'son_islem': FieldValue.serverTimestamp(),
        });

        print("✅ Web: Hareket ve Bakiye başarıyla güncellendi.");
        return 1;
      } catch (e) {
        print("❌ Web Müşteri Hareket Hatası: $e");
        return -1;
      }
    }

    // --- MOBİL İÇİN: GÜVENLİ SQLite MANTIĞIN ---
    final db = await instance.database;

    // 🔥 KRİTİK KONTROL: Eğer buluttan gelen senkronizasyon verisiyse
    // ve lokalde bu "HL_..." veya sayısal ID zaten varsa İŞLEMİ DURDUR!
    if (gelenId != null) {
      // Sayısal kısmını ayıkla (Örn: "HL_45" -> "45")
      String temizSqlId = gelenId.replaceAll("HL_", "");

      final kontrol = await db.query(
          'musteri_hareketleri',
          where: 'id = ?',
          whereArgs: [temizSqlId]
      );

      if (kontrol.isNotEmpty) {
        print("ℹ️ [MÜHÜR ENGELLEDİ] Bu hareket kaydı (ID: $temizSqlId) lokalde zaten var. Mükerrer kayıt engellendi.");
        return int.tryParse(temizSqlId) ?? 1; // Zaten var olduğu için eklemeden mevcut ID'yi dönüyoruz
      }
    }

    int localId = -1;

    try {
      // 🔥 SQLITE ÇAKIŞMA ÖNLEYİCİ ALGORİTMA: conflictAlgorithm
      localId = await db.insert(
        'musteri_hareketleri',
        temizVeri,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      double miktar = temizVeri['tutar'];
      String mId = temizVeri['musteri_id'];

      if (temizVeri['islem'] == 'TAHSILAT') {
        await db.rawUpdate('UPDATE musteriler SET bakiye = bakiye - ? WHERE id = ?', [miktar, mId]);
      } else {
        await db.rawUpdate('UPDATE musteriler SET bakiye = bakiye + ? WHERE id = ?', [miktar, mId]);
      }
    } catch (e) {
      print("❌ SQLITE HATA: $e");
      return -1;
    }

    // FIRESTORE SENKRON (Mobil)
    try {
      String nihaiDocId = "HL_$localId";

      await FirebaseFirestore.instance
          .collection('musteri_hareketleri')
          .doc(nihaiDocId)
          .set({
        ...temizVeri,
        'sqlite_id': localId,
        'id': nihaiDocId, // Firebase dökümanıyla içerideki ID eşitlendi
        'server_tarih': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      await db.update('musteri_hareketleri', {'is_synced': 1}, where: 'id = ?', whereArgs: [localId]);
      print("✅ Mobil: Hareket buluta mühürlendi: $nihaiDocId");
    } catch (e) {
      print("⚠ FIRESTORE BAŞARISIZ (kuyrukta kaldı): $e");
    }

    return localId;
  }
// DatabaseHelper.dart içinde veritabanını açtığın yere (onOpen veya onUpgrade) ekleyebilirsin
  Future<void> _tabloyuGuncelle(dynamic db) async {
    // --- WEB KORUMASI ---
    if (kIsWeb) {
      // Web'de tablo yapısı Firebase koleksiyonları üzerinden dinamik yürüdüğü için
      // sütun ekleme işlemine gerek yoktur.
      return;
    }

    // --- MOBİL İÇİN: SQLITE ŞEMA GÜNCELLEME ---
    try {
      // Tabloya 'musteri_ad' sütununu zorla ekliyoruz
      // Not: db parametresini 'dynamic' yaptık çünkü sqflite Database tipi Web'de tanımsızdır.
      await db.execute("ALTER TABLE musteri_hareketleri ADD COLUMN musteri_ad TEXT");
      print("✅ musteri_ad sütunu başarıyla eklendi.");
    } catch (e) {
      // Sütun zaten varsa hata verir, sorun değil; "Zaten var" demektir.
      print("Bilgi: Sütun zaten mevcut veya eklenemedi: $e");
    }
  }

  Future<void> bekleyenHareketleriSenkronizeEt() async {
    // --- WEB KORUMASI ---
    if (kIsWeb) {
      // Web'de yerel veritabanı (SQLite) olmadığı için senkronize edilecek bir şey de yoktur.
      return;
    }

    // --- MOBİL İÇİN: SQLITE'DAN BULUTA TAŞIMA MANTIĞI ---
    final db = await instance.database;

    // Gitmeyenleri bul (is_synced = 0 olanlar)
    final List<Map<String, dynamic>> bekleyenler = await db.query(
        'musteri_hareketleri',
        where: 'is_synced = ?',
        whereArgs: [0]
    );

    if (bekleyenler.isEmpty) {
      print("✅ Bekleyen kayıt yok.");
      return;
    }

    print("🔄 ${bekleyenler.length} adet bekleyen hareket senkronize ediliyor...");

    for (var hareket in bekleyenler) {
      try {
        // SQLite'dan gelen Map değiştirilemez olabilir, kopyasını alıyoruz
        Map<String, dynamic> firestoreVeri = Map<String, dynamic>.from(hareket);

        int sqliteId = firestoreVeri['id'];
        firestoreVeri.remove('id');
        firestoreVeri['is_synced'] = 1;
        firestoreVeri['server_tarih'] = FieldValue.serverTimestamp();
        firestoreVeri['sqlite_id'] = sqliteId;

        // ☁️ Buluta gönder
        await _firestore
            .collection('musteri_hareketleri')
            .doc("HL_$sqliteId")
            .set(firestoreVeri, SetOptions(merge: true)); // merge:true ile üzerine yazmayı güvenli hale getirdik

        // ✅ Başarılıysa yerel SQL'i güncelle
        await db.update(
            'musteri_hareketleri',
            {'is_synced': 1},
            where: 'id = ?',
            whereArgs: [sqliteId]
        );

        print("🚀 Bekleyen kayıt başarıyla gönderildi: HL_$sqliteId");
      } catch (e) {
        print("❌ Senkronizasyon hatası: $e");
        break;
      }
    }
  }


  Future<List<Map<String, dynamic>>> musterilerGetir() async {
    if (kIsWeb) {
      // --- WEB İÇİN: FIREBASE ÜZERİNDEN LİSTELEME ---
      try {
        print("🌐 Web: Müşteri listesi buluttan çekiliyor...");

        final snapshot = await FirebaseFirestore.instance
            .collection('musteriler')
            .orderBy('ad') // ASC varsayılan gelir
            .get();

        return snapshot.docs.map((doc) {
          Map<String, dynamic> data = doc.data();

          // SQLite'daki IFNULL(bakiye, 0) mantığını burada kuruyoruz:
          return {
            'id': doc.id, // Web'de döküman ID'si anahtardır
            'ad': data['ad'] ?? 'İSİMSİZ',
            'tc': data['tc'] ?? '',
            'tel': data['tel'] ?? '',
            'sube': data['sube'] ?? '',
            'bakiye': double.tryParse(data['bakiye']?.toString() ?? '0') ?? 0.0,
            'is_synced': 1, // Buluttan geldiği için her zaman senkronize
          };
        }).toList();
      } catch (e) {
        print("❌ Web Müşteri Listesi Hatası: $e");
        return [];
      }
    } else {
      // --- MOBİL İÇİN: SENİN ORİJİNAL SQL SORĞUN ---
      final db = await instance.database;
      return await db.rawQuery('''
      SELECT id, ad, tc, tel, sube, 
      IFNULL(bakiye, 0) as bakiye, 
      IFNULL(is_synced, 0) as is_synced 
      FROM musteriler 
      ORDER BY ad ASC
    ''');
    }
  }

  Future<int> stokSil(int id) async {
    // --- WEB İÇİN: DOĞRUDAN FIREBASE SİLME VE BORÇ DÜŞME ---
    if (kIsWeb) {
      try {
        print("🌐 Web: Stok siliniyor ve firma borcu güncelleniyor...");

        // 1. Önce ürünü bulutta bulup bilgilerini almamız lazım (Borç düşmek için)
        var urunDoc = await FirebaseFirestore.instance.collection('stoklar').doc(id.toString()).get();

        if (urunDoc.exists) {
          var urun = urunDoc.data()!;
          String firmaAdi = urun['tarim_firmalari']?.toString() ?? urun['firma']?.toString() ?? "BELİRTİLMEDİ";
          double fiyat = double.tryParse(urun['fiyat']?.toString() ?? "0") ?? 0;
          double adet = double.tryParse(urun['adet']?.toString() ?? "0") ?? 0;
          double toplamTutar = fiyat * adet;

          // 2. Ürünü Sil
          await FirebaseFirestore.instance.collection('stoklar').doc(id.toString()).delete();

          // 3. Firma Borcunu Güncelle (Atomik)
          if (firmaAdi != "BELİRTİLMEDİ") {
            // Firebase'de firma döküman ID'sinin firma adı olduğunu varsayıyoruz
            await FirebaseFirestore.instance
                .collection('tarim_firmalari')
                .doc(firmaAdi)
                .update({
              'borc': FieldValue.increment(-toplamTutar),
            });
            print("📉 Web: Firma borcu $toplamTutar TL düşürüldü.");
          }
          return 1;
        }
        return 0;
      } catch (e) {
        print("❌ Web Stok Silme Hatası: $e");
        return 0;
      }
    }

    // --- MOBİL İÇİN: SENİN ORİJİNAL TRANSACTION MANTIĞIN ---
    final db = await instance.database;
    int res = 0;

    List<Map<String, dynamic>> urunSorgu = await db.query('stoklar', where: 'id = ?', whereArgs: [id]);

    if (urunSorgu.isNotEmpty) {
      var urun = urunSorgu.first;
      String firmaAdi = urun['tarim_firmalari']?.toString() ?? urun['firma']?.toString() ?? "BELİRTİLMEDİ";
      String? firebaseId = urun['firebase_id']?.toString();
      double fiyat = double.tryParse(urun['fiyat']?.toString() ?? "0") ?? 0;
      double adet = double.tryParse(urun['adet']?.toString() ?? "0") ?? 0;
      double toplamTutar = fiyat * adet;

      await db.transaction((txn) async {
        res = await txn.delete('stoklar', where: 'id = ?', whereArgs: [id]);

        if (firmaAdi != "BELİRTİLMEDİ") {
          await txn.rawUpdate(
              'UPDATE tarim_firmalari SET borc = borc - ? WHERE ad = ?',
              [toplamTutar, firmaAdi]
          );
        }
      });

      try {
        String silinecekId = (firebaseId != null && firebaseId.isNotEmpty && firebaseId != "hükümsüz")
            ? firebaseId
            : id.toString();

        await _firestore.collection('stoklar').doc(silinecekId).delete();
        print("✅ Firebase: Ürün buluttan silindi.");
      } catch (e) {
        print("❌ Firebase Silme Hatası: $e");
      }
    }
    return res;
  }

  Future<bool> stokKesinSil(int localId) async {
    final db = await instance.database;

    // 1. Önce veriyi çekelim ki Firebase ID'sini ve borç tutarını bilelim
    List<Map<String, dynamic>> urun = await db.query('stoklar', where: 'id = ?', whereArgs: [localId]);

    if (urun.isEmpty) return false;

    String? fId = urun.first['firebase_id'];
    double borcAzalacak = (double.tryParse(urun.first['fiyat'].toString()) ?? 0) * (double.tryParse(urun.first['adet'].toString()) ?? 0);
    String firma = urun.first['tarim_firmalari'] ?? "";

    // 2. SQL İşlemleri (Transaction: Ya hep ya hiç!)
    await db.transaction((txn) async {
      await txn.delete('stoklar', where: 'id = ?', whereArgs: [localId]);
      if (firma.isNotEmpty) {
        await txn.rawUpdate('UPDATE tarim_firmalari SET borc = borc - ? WHERE ad = ?', [borcAzalacak, firma]);
      }
    });

    // 3. Firebase'den Temizle (Eğer fId varsa)
    // DatabaseHelper.dart içinde bu kısmı kontrol et
    if (fId != null && fId.isNotEmpty && fId != "null") {
      try {
        // 1. BULUTTAN TAMAMEN SİL
        await FirebaseFirestore.instance.collection('stoklar').doc(fId).delete();
        print("✅ Bulut mühürü söküldü, artık geri gelemez: $fId");
      } catch (e) {
        // 2. EĞER SİLEMEZSEK (İnternet yoksa), "SİLİNDİ" BAYRAĞINI 1 YAP
        await FirebaseFirestore.instance.collection('stoklar').doc(fId).update({'silindi': 1});
        print("⚠️ Bulut silinemedi ama 'silindi=1' olarak mühürlendi.");
      }
    }
    return true;
  }

// Stok Şube Değiştir: Malın yerini değiştirirken kayıt tutar.
  Future<void> stokSubeDegistir(int id, String yeniSube) async {
    // --- WEB İÇİN: DOĞRUDAN FIREBASE GÜNCELLEME ---
    if (kIsWeb) {
      try {
        print("🌐 Web: Ürün şubesi bulutta değiştiriliyor: $yeniSube");

        await FirebaseFirestore.instance.collection('stoklar').doc(id.toString()).update({
          'sube': yeniSube,
          'sube_degisim_tarihi': FieldValue.serverTimestamp(),
          'son_guncelleme': FieldValue.serverTimestamp(),
        });

        print("✅ Web: Şube değişimi başarıyla mühürlendi.");
        return;
      } catch (e) {
        print("❌ Web Şube Değişim Hatası: $e");
        return;
      }
    }

    // --- MOBİL İÇİN: SENİN ORİJİNAL HİBRİT MANTIĞIN ---
    final db = await instance.database;

    // 1. ADIM: Yerelde şube bilgisini güncelle
    await db.rawUpdate('UPDATE stoklar SET sube = ? WHERE id = ?', [yeniSube, id]);

    try {
      // 2. ADIM: Firebase'de şubeyi değiştir
      await _firestore.collection('stoklar').doc(id.toString()).update({
        'sube': yeniSube,
        'sube_degisim_tarihi': FieldValue.serverTimestamp(),
      });

      print("✅ Firebase: Ürün şubesi $yeniSube olarak güncellendi.");
    } catch (e) {
      print("❌ Firebase Şube Değişim Hatası: $e");
    }
  }

  Future<int> stokTanimSil(String firma, String marka, String model, String altModel) async {
    String f = firma.trim().toUpperCase();
    String m = marka.trim().toUpperCase();
    String mod = model.trim().toUpperCase();
    String alt = altModel.trim().toUpperCase();

    // --- WEB İÇİN: FIREBASE ÜZERİNDEN SORGULAYARAK SİL ---
    if (kIsWeb) {
      try {
        print("🌐 Web: Stok tanımları buluttan siliniyor...");

        // 1. Firebase Sorgusunu Hazırla
        var sorgu = FirebaseFirestore.instance.collection('stok_tanimlari')
            .where('tarim_firmalari', isEqualTo: f)
            .where('marka', isEqualTo: m);

        if (mod.isNotEmpty) sorgu = sorgu.where('model', isEqualTo: mod);

        // 2. Dökümanları Getir ve Alt Model Kontrolü Yaparak Sil
        final snapshot = await sorgu.get();
        int silinenAdet = 0;

        for (var doc in snapshot.docs) {
          var d = doc.data();
          // Alt model boşsa o markanın/modelin her şeyini siler, doluysa sadece o alt modeli siler
          if (alt.isEmpty || d['alt_model'] == alt || d['altmodel'] == alt) {
            await doc.reference.delete();
            silinenAdet++;
          }
        }

        print("✅ Web: $silinenAdet adet tanım buluttan temizlendi.");
        return silinenAdet;
      } catch (e) {
        print("❌ Web Silme Hatası: $e");
        return 0;
      }
    }

    // --- MOBİL İÇİN: SENİN ORİJİNAL SQLite + FIREBASE MANTIĞIN ---
    final db = await instance.database;
    int res = 0;

    try {
      // 1. ADIM: SQLite Silme
      if (alt.isNotEmpty) {
        res = await db.delete('stok_tanimlari',
            where: 'tarim_firmalari = ? AND marka = ? AND model = ? AND (alt_model = ? OR altmodel = ?)',
            whereArgs: [f, m, mod, alt, alt]);
      } else if (mod.isNotEmpty) {
        res = await db.delete('stok_tanimlari',
            where: 'tarim_firmalari = ? AND marka = ? AND model = ?',
            whereArgs: [f, m, mod]);
      } else {
        res = await db.delete('stok_tanimlari',
            where: 'tarim_firmalari = ? AND marka = ?',
            whereArgs: [f, m]);
      }

      // 2. ADIM: Firebase Silme (Mobil için paralel güncelleme)
      var sorgu = _firestore.collection('stok_tanimlari')
          .where('tarim_firmalari', isEqualTo: f)
          .where('marka', isEqualTo: m);

      if (mod.isNotEmpty) sorgu = sorgu.where('model', isEqualTo: mod);

      final snapshot = await sorgu.get();
      for (var doc in snapshot.docs) {
        var d = doc.data();
        if (alt.isEmpty || d['alt_model'] == alt || d['altmodel'] == alt) {
          await doc.reference.delete();
        }
      }
      print("✅ Mobil: Silme işlemi tamam.");
    } catch (e) {
      print("❌ Silme Hatası: $e");
    }
    return res;
  }

  Future<int> stokTanimGuncelleById(dynamic id, Map<String, dynamic> veri) async {
    if (kIsWeb) {
      try {
        print("🌐 Web: Stok tanımı bulutta güncelleniyor (ID: $id)...");

        // ÖNEMLİ: Tüm metin verilerini büyük harfe çevirerek mühürle
        Map<String, dynamic> temizVeri = {};
        veri.forEach((key, value) {
          if (value is String) {
            temizVeri[key] = value.toUpperCase().trim();
          } else {
            temizVeri[key] = value;
          }
        });

        await FirebaseFirestore.instance
            .collection('stok_tanimlari') // Koleksiyon isminden emin ol!
            .doc(id.toString())
            .set(temizVeri, SetOptions(merge: true));

        return 1;
      } catch (e) {
        print("❌ Web Güncelleme Hatası: $e");
        return 0;
      }
    } else {
      final db = await instance.database;
      return await db.update(
        'stok_tanimlari',
        veri,
        where: 'id = ?',
        whereArgs: [id],
      );
    }
  }

  Future<void> stokTanimGuncelle(
      String firma,
      String eskiMarka,
      String eskiModel,
      String eskiAltModel,
      String yeniDeger,
      String tip) async {

    // Arama kriterlerini baştan sağlama alıyoruz
    String f = firma.toUpperCase().trim();
    String eMa = eskiMarka.toUpperCase().trim();
    String eMo = eskiModel.toUpperCase().trim();
    String eAlt = eskiAltModel.toUpperCase().trim();
    String yeni = yeniDeger.toUpperCase().trim();

    // --- WEB VE MOBİL ORTAK FIREBASE SORGUSU ---
    Future<void> bulutGuncelle() async {
      try {
        var sorgu = FirebaseFirestore.instance.collection('stok_tanimlari')
            .where('tarim_firmalari', isEqualTo: f)
            .where('marka', isEqualTo: eMa);

        if (tip == "MODEL" || tip == "ALTMODEL") {
          sorgu = sorgu.where('model', isEqualTo: eMo);
        }

        final snapshot = await sorgu.get();
        for (var doc in snapshot.docs) {
          // Alt model güncellemesinde hem 'alt_model' hem 'altmodel' mühürlenmeli
          Map<String, dynamic> up = {};
          if (tip == "MARKA") up = {'marka': yeni};
          if (tip == "MODEL") up = {'model': yeni};
          if (tip == "ALTMODEL") up = {'alt_model': yeni, 'altmodel': yeni};

          await doc.reference.update(up);
        }
      } catch (e) {
        print("☁️ Bulut Güncelleme Hatası: $e");
      }
    }

    if (kIsWeb) {
      await bulutGuncelle();
      print("✅ Web: Tamamlandı.");
      return;
    }

    // --- MOBİL İÇİN YEREL SQL GÜNCELLEMESİ ---
    final db = await instance.database;
    try {
      if (tip == "MARKA") {
        await db.update('stoklar', {'marka': yeni}, where: 'marka = ?', whereArgs: [eMa]);
        await db.update('stok_tanimlari', {'marka': yeni}, where: 'tarim_firmalari = ? AND marka = ?', whereArgs: [f, eMa]);
      } else if (tip == "MODEL") {
        await db.update('stok_tanimlari', {'model': yeni}, where: 'tarim_firmalari = ? AND marka = ? AND model = ?', whereArgs: [f, eMa, eMo]);
      } else if (tip == "ALTMODEL") {
        await db.update('stok_tanimlari', {'alt_model': yeni, 'altmodel': yeni},
            where: 'tarim_firmalari = ? AND marka = ? AND model = ? AND (alt_model = ? OR altmodel = ?)',
            whereArgs: [f, eMa, eMo, eAlt, eAlt]);
      }

      // SQL bittikten sonra Firebase'i de güncelle
      await bulutGuncelle();
      print("✅ Mobil: Yerel ve Bulut eşitlendi.");
    } catch (e) {
      print("❌ Mobil Hata: $e");
    }
  }

// Yardımcı Alt Metod (Kod kalabalığını önlemek için)
  Future<void> _firebaseDocGuncelle(QueryDocumentSnapshot doc, String tip, String eskiAlt, String yeni) async {
    var d = doc.data() as Map<String, dynamic>;
    if (tip == "ALTMODEL") {
      if (d['alt_model'] == eskiAlt || d['altmodel'] == eskiAlt) {
        await doc.reference.update({
          'alt_model': yeni,
          'altmodel': yeni,
          'son_guncelleme': FieldValue.serverTimestamp(),
        });
      }
    } else {
      String alan = tip == "MARKA" ? "marka" : "model";
      await doc.reference.update({
        alan: yeni,
        'son_guncelleme': FieldValue.serverTimestamp(),
      });
    }
  }

  Future<void> stokHareketiIsle({
    required Map<String, dynamic> firma,
    required Map<String, dynamic> stok,
    required double adet,
    required double birimFiyat,
    required String islemTipi,
  }) async {

    final db = await instance.database;

    double toplamTutar = adet * birimFiyat;

    String tarih =
        stok['tarih'] ??
            DateFormat('dd.MM.yyyy')
                .format(DateTime.now());

    String hareketMuhuru =
        "HRK-${DateTime.now().millisecondsSinceEpoch}";

    try {

      await db.transaction((txn) async {

        // =========================================================
        // 1. AYNI STOK VAR MI
        // =========================================================

        final mevcutStok = await txn.query(
          'stoklar',
          where:
          'marka = ? AND model = ? AND alt_model = ? AND sube = ?',
          whereArgs: [
            stok['marka'],
            stok['model'],
            stok['alt_model'],
            stok['sube'],
          ],
        );

        // =========================================================
        // 2. STOK GÜNCELLE
        // =========================================================

        if (mevcutStok.isNotEmpty) {

          int stokId =
          mevcutStok.first['id'] as int;

          double mevcutAdet =
              double.tryParse(
                mevcutStok.first['adet']
                    .toString(),
              ) ??
                  0;

          double yeniAdet = mevcutAdet;

          // -------------------------------------------------
          // ALIM
          // -------------------------------------------------

          if (islemTipi == 'ALIM') {
            yeniAdet += adet;
          }

          // -------------------------------------------------
          // SATIŞ
          // -------------------------------------------------

          else if (islemTipi == 'SATIS') {
            yeniAdet -= adet;

            if (yeniAdet < 0) {
              yeniAdet = 0;
            }
          }

          // -------------------------------------------------
          // GÜNCELLE
          // -------------------------------------------------

          await txn.update(
            'stoklar',
            {
              'adet': yeniAdet,
              'fiyat': birimFiyat,
              'is_synced': 0,
            },
            where: 'id = ?',
            whereArgs: [stokId],
          );
        }

        // =========================================================
        // 3. YENİ STOK OLUŞTUR
        // =========================================================

        else {

          double ilkAdet =
          islemTipi == 'SATIS'
              ? 0
              : adet;

          await txn.insert(
            'stoklar',
            {
              'stok_kodu':
              stok['stok_kodu'],
              'urun':
              stok['urun'],
              'adet':
              ilkAdet,
              'fiyat':
              birimFiyat,
              'alis_fiyati':
              stok['alis_fiyati'] ?? 0,
              'marka':
              stok['marka'],
              'model':
              stok['model'],
              'alt_model':
              stok['alt_model'],
              'kategori':
              stok['kategori'],
              'sube':
              stok['sube'],
              'durum':
              stok['durum'],
              'fatura_no':
              stok['fatura_no'],
              'tarih':
              tarih,
              'cari_kod':
              firma['cari_kod'],
              'firebase_id':
              stok['firebase_id'],
              'is_synced': 0,
              'silindi': 0,
            },
          );
        }

        // =========================================================
        // 4. FİRMA BAKİYE
        // =========================================================

        if (firma['cari_kod'] != 'TRANSFER') {

          if (islemTipi == 'ALIM') {

            await txn.rawUpdate(
              '''
            UPDATE tarim_firmalari
            SET alacak = alacak + ?,
                is_synced = 0
            WHERE cari_kod = ?
            ''',
              [
                toplamTutar,
                firma['cari_kod'],
              ],
            );
          }

          else {

            await txn.rawUpdate(
              '''
            UPDATE tarim_firmalari
            SET borc = borc + ?,
                is_synced = 0
            WHERE cari_kod = ?
            ''',
              [
                toplamTutar,
                firma['cari_kod'],
              ],
            );
          }
        }

        // =========================================================
        // 5. HAREKET KAYDI
        // =========================================================

        await txn.insert(
          'tarim_firma_hareketleri',
          {
            'firebase_id':
            hareketMuhuru,
            'cari_kod':
            firma['cari_kod'],
            'firma_adi':
            firma['ad']
                ?.toString()
                .toUpperCase(),
            'stok_id':
            stok['stok_kodu'],
            'islem_tipi':
            islemTipi,
            'urun_adi':
            stok['urun'],
            'tutar':
            toplamTutar,
            'adet':
            adet,
            'tarih':
            tarih,
            'is_synced': 0,
            'silindi': 0,
          },
        );
      });

      // =========================================================
      // FIREBASE
      // =========================================================

      await _firebaseSenkronEt(
        firma,
        stok,
        adet,
        birimFiyat,
        toplamTutar,
        islemTipi,
        hareketMuhuru,
      );

    } catch (e) {

      debugPrint(
          "🚨 stokHareketiIsle Hatası: $e");

      rethrow;
    }
  }

// =============================================================
// FIREBASE SENKRON
// =============================================================

  Future<void> _firebaseSenkronEt(
      Map<String, dynamic> firma,
      Map<String, dynamic> stok,
      double adet,
      double birimFiyat,
      double toplamTutar,
      String islemTipi,
      String hareketMuhuru,
      ) async {

    try {

      WriteBatch batch =
      FirebaseFirestore.instance.batch();

      String cariKod =
      (firma['cari_kod'] ?? "")
          .toString()
          .trim()
          .toUpperCase();

      String firebaseId =
      (stok['firebase_id'] ??
          stok['stok_kodu'])
          .toString();

      // =========================================================
      // FIREBASE REFERANSLARI
      // =========================================================

      var fbStok =
      FirebaseFirestore.instance
          .collection('stoklar')
          .doc(firebaseId);

      var fbHareket =
      FirebaseFirestore.instance
          .collection('tarim_firma_hareketleri')
          .doc(hareketMuhuru);

      // =========================================================
      // STOK DEĞİŞİMİ
      // =========================================================

      double degisim = 0;

      if (islemTipi == 'ALIM') {
        degisim = adet;
      }

      else if (islemTipi == 'SATIS') {
        degisim = -adet;
      }

      else if (islemTipi == 'SUBE_TRANSFER') {
        degisim = 0;
      }

      // =========================================================
      // STOK GÜNCELLE
      // =========================================================

      batch.set(
        fbStok,
        {

          'stok_kodu':
          stok['stok_kodu'] ?? '',

          'urun':
          stok['urun'] ?? '',

          'kategori':
          stok['kategori'] ?? '',

          'marka':
          stok['marka'] ?? '',

          'model':
          stok['model'] ?? '',

          'alt_model':
          stok['alt_model'] ?? '',

          'sube':
          stok['sube'] ?? 'TEFENNİ',

          'durum':
          stok['durum'] ?? 'SIFIR',

          'fatura_no':
          stok['fatura_no'] ?? '',

          'cari_kod':
          cariKod,

          'alis_fiyati':
          double.tryParse(
              stok['alis_fiyati']
                  .toString()) ??
              0,

          'fiyat':
          birimFiyat,

          // SADECE ALIM/SATIŞTA ETKİLE
          'adet':
          FieldValue.increment(degisim),

          'is_synced': 1,

          'son_guncelleme':
          FieldValue.serverTimestamp(),
        },

        SetOptions(merge: true),
      );

      // =========================================================
      // FİRMA BAKİYE
      // =========================================================

      if (cariKod != 'TRANSFER') {

        var fbFirma =
        FirebaseFirestore.instance
            .collection('tarim_firmalari')
            .doc(cariKod);

        // -----------------------------------------------------

        if (islemTipi == 'ALIM') {

          batch.set(
            fbFirma,
            {
              'alacak':
              FieldValue.increment(
                  toplamTutar),

              'son_islem_tarihi':
              FieldValue.serverTimestamp(),
            },
            SetOptions(merge: true),
          );
        }

        // -----------------------------------------------------

        else if (islemTipi == 'SATIS') {

          batch.set(
            fbFirma,
            {
              'borc':
              FieldValue.increment(
                  toplamTutar),

              'son_islem_tarihi':
              FieldValue.serverTimestamp(),
            },
            SetOptions(merge: true),
          );
        }
      }

      // =========================================================
      // HAREKET KAYDI
      // =========================================================

      batch.set(
        fbHareket,
        {

          'firebase_id':
          hareketMuhuru,

          'cari_kod':
          cariKod,

          'firma_adi':

          cariKod == 'TRANSFER'
              ? 'ŞUBE TRANSFER'

              : (firma['ad'] ??
              'FİRMA YOK'),

          'stok_id':
          stok['stok_kodu'] ?? '',

          'islem_tipi':
          islemTipi,

          'urun_adi':
          stok['urun'] ?? '',

          'tutar':
          toplamTutar,

          'adet':
          adet,

          'tarih':
          stok['tarih'] ??
              DateFormat('dd.MM.yyyy')
                  .format(DateTime.now()),

          'server_tarih':
          FieldValue.serverTimestamp(),

          'is_synced': 1,
        },
      );

      // =========================================================
      // FIREBASE COMMIT
      // =========================================================

      await batch.commit();

      // =========================================================
      // SQLITE SENKRON MÜHÜRÜ
      // =========================================================

      final db =
      await instance.database;

      await db.update(
        'tarim_firma_hareketleri',
        {
          'is_synced': 1,
        },
        where: 'firebase_id = ?',
        whereArgs: [
          hareketMuhuru,
        ],
      );

      debugPrint(
          "✅ Firebase senkron başarılı");

    } catch (e) {

      debugPrint(
          "❌ Firebase Senkron Hatası: $e");
    }
  }



  Future<int> stokHareketiEkle(Map<String, dynamic> veri) async {
    // --- WEB İÇİN: DOĞRUDAN FIREBASE ATOMİK İŞLEM ---
    if (kIsWeb) {
      try {
        print("🌐 Web: Stok hareketi buluta işleniyor...");

        // 1. Hareket kaydını oluştur
        var hareketRef = await FirebaseFirestore.instance
            .collection('stok_hareketleri')
            .add({
          ...veri,
          'islem_tarihi': FieldValue.serverTimestamp(),
        });

        // 2. Ana stok miktarını güncelle (Atomik Increment)
        // Hem 'stoklar' hem 'stok_tanimlari' koleksiyonlarını güncel tutuyoruz
        double miktar = double.tryParse(veri['miktar'].toString()) ?? 0.0;
        String stokId = veri['stok_id'].toString();

        // Stoklar koleksiyonundaki adedi güncelle
        await FirebaseFirestore.instance.collection('stoklar').doc(stokId).update({
          'adet': FieldValue.increment(miktar),
          'son_hareket': FieldValue.serverTimestamp(),
        });

        // Stok tanımları koleksiyonundaki mevcut adedi güncelle
        await FirebaseFirestore.instance.collection('stok_tanimlari').doc(stokId).update({
          'mevcut_adet': FieldValue.increment(miktar),
        });

        print("✅ Web: Hareket işlendi ve stok miktarları güncellendi.");
        return 1; // Başarılı
      } catch (e) {
        print("❌ Web Stok Hareketi Hatası: $e");
        return -1;
      }
    }

    // --- MOBİL İÇİN: SENİN ORİJİNAL TRANSACTION MANTIĞIN ---
    final db = await instance.database;
    int id = 0;

    try {
      await db.transaction((txn) async {
        id = await txn.insert('stok_hareketleri', veri);

        // Ana stoğu güncelle
        await txn.execute('''
        UPDATE stoklar 
        SET adet = adet + ? 
        WHERE id = ?
      ''', [veri['miktar'], veri['stok_id']]);
      });

      // Firebase Senkronizasyonu (Mobil Arka Plan)
      try {
        await _firestore.collection('stok_hareketleri').doc(id.toString()).set({
          ...veri,
          'id': id,
          'islem_tarihi': FieldValue.serverTimestamp(),
        });

        await _firestore.collection('stok_tanimlari').doc(veri['stok_id'].toString()).update({
          'mevcut_adet': FieldValue.increment(veri['miktar']),
        });
        print("🚀 Firebase: Mobil verisi buluta başarıyla itildi.");
      } catch (e) {
        print("⚠️ Firebase Senkron Hatası: $e");
      }

      return id;
    } catch (e) {
      print("❌ Mobil SQLite Hatası: $e");
      return -1;
    }
  }

  Future<List<Map<String, dynamic>>> subeyeGoreStokGetir(String subeAdi) async {
    // --- WEB İÇİN: SADECE FIREBASE ---
    if (kIsWeb) {
      try {
        print("🌐 Web: $subeAdi şubesi için buluttan stoklar çekiliyor...");
        final snapshot = await FirebaseFirestore.instance
            .collection('stoklar')
            .where('alt', isEqualTo: subeAdi)
            .get();

        return snapshot.docs.map((doc) {
          var data = doc.data();
          data['id_bulut'] = doc.id;
          // SQLite'dan gelen verilerde 'id' integer olur, Web uyumu için ekliyoruz
          data['id'] = data['id'] ?? doc.id;
          return data;
        }).toList();
      } catch (e) {
        print("❌ Web Sorgu Hatası: $e");
        return [];
      }
    }

    // --- MOBİL İÇİN: SENİN ORİJİNAL HİBRİT MANTIĞIN ---
    print("📡 Mobil: $subeAdi şubesi için Firebase kontrol ediliyor...");
    try {
      final snapshot = await _firestore.collection('stoklar')
          .where('alt', isEqualTo: subeAdi)
          .get();

      if (snapshot.docs.isNotEmpty) {
        return snapshot.docs.map((doc) {
          var data = doc.data();
          data['id_bulut'] = doc.id;
          return data;
        }).toList();
      }
    } catch (e) {
      print("❌ Firebase Sorgu Hatası: $e");
    }

    print("🏠 Yerel SQLite bakılıyor...");
    final db = await instance.database;
    return await db.query('stoklar', where: 'sube = ?', whereArgs: [subeAdi]);
  }


  Future<List<Map<String, dynamic>>> mazotListesiGetir(String sezon) async {
    if (kIsWeb) return await _firebaseMazotCek(sezon);

    final db = await instance.database;

    // Yerelden çekmeyi dene
    var localData = await db.query('bicer_mazotlar', where: 'sezon = ?', whereArgs: [sezon]);

    print("MAZOT RAW: ${localData.length}");

    // 🔥 EĞER YEREL BOŞSA HEMEN FİREBASE'E KOŞ
    if (localData.isEmpty) {
      print("🏠 Yerel boş, veriler Firebase'den getiriliyor...");
      return await _firebaseMazotCek(sezon);
    }

    return localData;
  }

  // --- MÜHÜRLÜ SENKRONİZASYON GÜNCELLEME METODU ---
  Future<int> musteriHareketGuncelleSyncDurumu(String islemId, int syncDurumu) async {
    try {
      final db = await instance.database;

      // musteri_hareketleri tablonun adını ve kolon isimlerini kontrol et abi.
      // id alanı mühürlü String ID'yi (HL_...) tuttuğu için WHERE koşuluna doğrudan String veriyoruz.
      return await db.update(
        'musteri_hareketleri',
        {'is_synced': syncDurumu}, // 0 veya 1 değerini basacak
        where: 'id = ?',
        whereArgs: [islemId],
      );
    } catch (e) {
      print("🚨 DatabaseHelper -> Sync durumu güncellenirken SQLite hatası: $e");
      return -1;
    }
  }

  // --- MÜŞTERİYE AİT TÜM SATIŞLARI SİLME ---
  Future<int> musteriSatislariniSil(String musteriId) async {
    try {
      final db = await instance.database;
      // SQLite'daki 'satislar' tablosundan müşterinin id'sine uyan her şeyi siler
      return await db.delete(
        'satislar',
        where: 'musteri_id = ?',
        whereArgs: [musteriId],
      );
    } catch (e) {
      print("🚨 DatabaseHelper -> Müşteri satışları silinirken SQLite hatası: $e");
      return -1;
    }
  }


  Future<void> musteriyiGuvenliSil(int? id, String isim) async {
    final db = await instance.database;

    // 1. Eğer ID mantıklı bir sayıysa (milisaniye kadar devasa değilse) önce ID ile dene
    if (id != null && id < 2000000000) {
      await db.delete('bicer_isleri', where: 'id = ?', whereArgs: [id]);
    } else {
      // 2. ID bozuksa veya geçici üretilmişse (logdaki gibi), ISIM üzerinden temizle
      // Bu sayede o 'DENEME BİÇER' kaydı ne olursa olsun silinir.
      await db.delete('bicer_isleri', where: 'ciftci_ad = ?', whereArgs: [isim]);
    }

    // Varsa müşteriye bağlı diğer alt tabloları da temizle
    // await db.delete('tahsilatlar', where: 'ciftci_ad = ?', whereArgs: [isim]);
  }

  Future<List<Map<String, dynamic>>> bicerMusterileriGetir() async {
    final db = await instance.database;
    // Tablo adın farklıysa (örneğin sadece 'musteriler') burayı düzelt
    return await db.query('bicer_musterileri', orderBy: 'ad_soyad ASC');
  }

// Firebase'den çekme işlemini ortak bir fonksiyona alalım ki her yerden çağıralım
  Future<List<Map<String, dynamic>>> _firebaseMazotCek(String sezon) async {
    try {
      print("🌐 Firebase: $sezon sezonu verileri çekiliyor...");
      final snapshot = await FirebaseFirestore.instance
          .collection('bicer_mazotlar')
          .where('sezon', isEqualTo: sezon)
          .get();

      return snapshot.docs.map((doc) {
        var data = doc.data();
        return {
          ...data,
          'id': data['id'] ?? doc.id,
          'firebase_id': doc.id, // Silme işlemi için lazım olur
          'is_synced': 1,
        };
      }).toList();
    } catch (e) {
      print("❌ Firebase Hatası: $e");
      return [];
    }
  }



  // Mazot Güncelle: Kaydı hem yerelde hem bulutta düzeltir
  Future<int> mazotGuncelle(dynamic id, Map<String, dynamic> data) async {
    // --- WEB İÇİN: DOĞRUDAN FIREBASE GÜNCELLEME ---
    if (kIsWeb) {
      try {
        print("🌐 Web: Mazot kaydı bulutta güncelleniyor...");

        // Koleksiyon adını projenle uyumlu (bicer_mazotlar) kullanıyoruz
        await FirebaseFirestore.instance
            .collection('bicer_mazotlar')
            .doc(id.toString())
            .set({
          ...data,
          'son_guncelleme': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        print("✅ Web: Mazot kaydı başarıyla mühürlendi.");
        return 1; // Başarılı
      } catch (e) {
        print("❌ Web Mazot Güncelleme Hatası: $e");
        return 0;
      }
    }

    // --- MOBİL İÇİN: SENİN ORİJİNAL SQLite + FIREBASE MANTIĞIN ---
    final db = await instance.database;

    // 1. ADIM: Yerel SQLite güncellemesi
    int res = await db.update(
        "bicer_mazotlar ", // Tablo adının SQLite'da 'mazot_takibi' olduğundan emin ol abi
        data,
        where: 'id = ?',
        whereArgs: [id]
    );

    // 2. ADIM: Firebase senkronizasyonu
    try {
      await _firestore.collection('bicer_mazotlar').doc(id.toString()).set({
        ...data,
        'son_guncelleme': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      print("✅ Mobil: Mazot kaydı Firebase ile senkron edildi.");
    } catch (e) {
      print("❌ Firebase Mazot Güncelleme Hatası: $e");
    }

    return res;
  }


  Future<String?> tcBulIsimden(String ad) async {
    final db = await instance.database;
    final list = await db.query(
      'bicer_musterileri',
      columns: ['tc'],
      where: 'ad_soyad = ?',
      whereArgs: [ad.trim()],
    );

    if (list.isNotEmpty) {
      return list.first['tc']?.toString();
    }
    return null;
  }

  Future<void> bicerFaturaGorseliEkleTC(String tcNo, dynamic imageFile) async {
    // --- WEB MANTIĞI ---
    if (kIsWeb) {
      try {
        Uint8List fileBytes;
        if (imageFile is XFile) {
          fileBytes = await imageFile.readAsBytes();
        } else if (imageFile is Uint8List) {
          fileBytes = imageFile;
        } else {
          throw "Web'de dosya formatı desteklenmiyor (Uint8List veya XFile gerekli)";
        }

        final String fileName = "fatura_${tcNo}_${DateTime.now().millisecondsSinceEpoch}.jpg";
        final storageRef = FirebaseStorage.instance.ref().child('faturalar/$fileName');

        // Metadata eklemek ileride dosyaları yönetirken işine yarar
        final uploadTask = storageRef.putData(
          fileBytes,
          SettableMetadata(contentType: 'image/jpeg'),
        );

        final snapshot = await uploadTask;
        final String downloadUrl = await snapshot.ref.getDownloadURL();

        // Firestore Güncellemeleri
        // Müşteri Belgesi
        final musteriler = await FirebaseFirestore.instance
            .collection('bicer_musterileri')
            .where('tc', isEqualTo: tcNo)
            .get();

        for (var doc in musteriler.docs) {
          await doc.reference.update({'fotograf_yolu': downloadUrl});
        }

        // Hasat Kayıtları (Tüm sezon işlerini günceller)
        final isler = await FirebaseFirestore.instance
            .collection('bicer_isleri')
            .where('musteri_tc', isEqualTo: tcNo)
            .get();

        for (var doc in isler.docs) {
          await doc.reference.update({'fatura_yolu': downloadUrl});
        }

        print("✅ Web: Bulut yükleme ve Firestore güncelleme tamam.");
        return;
      } catch (e) {
        print("❌ Web Hatası: $e");
        rethrow;
      }
    }

    // --- MOBİL MANTIĞI ---
    try {
      final directory = await getApplicationDocumentsDirectory();
      final String fileName = "fatura_${tcNo}_${DateTime.now().millisecondsSinceEpoch}.jpg";

      // imageFile XFile ise File'a çevir, zaten File ise direkt kullan
      File fileToCopy = (imageFile is XFile) ? File(imageFile.path) : imageFile as File;
      final File localImage = await fileToCopy.copy('${directory.path}/$fileName');

      final db = await instance.database;

      await db.transaction((txn) async {
        // 1. Müşteri profilini güncelle
        await txn.update(
          'bicer_musterileri',
          {
            'fotograf_yolu': localImage.path,
            'is_synced': 0 // Sunucuya henüz gitmediği için işaretle
          },
          where: 'tc = ?',
          whereArgs: [tcNo],
        );

        // 2. O müşterinin tüm işlerine fatura yolunu işle
        // Not: Sadece son işe mi yoksa hepsine mi işleneceği senin iş akışına bağlı
        await txn.update(
          'bicer_isleri',
          {
            'fatura_yolu': localImage.path,
            'is_synced': 0
          },
          where: 'musteri_tc = ?', // tcNo kullandık çünkü musteri_tc daha güvenli
          whereArgs: [tcNo],
        );
      });

      print("✅ Mobil: Yerel kayıt tamam: ${localImage.path}");
    } catch (e) {
      print("❌ Mobil Hatası: $e");
      rethrow;
    }
  }

  Future<int> mazotSil(dynamic id, {String? firebaseId}) async {
    // --- WEB İÇİN: DOĞRUDAN FIREBASE SİLME ---
    if (kIsWeb) {
      try {
        print("🌐 Web: Mazot kaydı buluttan siliniyor...");

        // Web'de id genelde Firebase döküman ID'sidir
        String silinecekId = firebaseId ?? id.toString();

        await FirebaseFirestore.instance
            .collection('bicer_mazotlar')
            .doc(silinecekId)
            .delete();

        print("✅ Web: $silinecekId başarıyla buluttan uçuruldu.");
        return 1;
      } catch (e) {
        print("❌ Web Mazot Silme Hatası: $e");
        return 0;
      }
    }

    // --- MOBİL İÇİN: SENİN ORİJİNAL SQLite + FIREBASE MANTIĞIN ---
    final db = await instance.database;

    // 1. Yerel SQLite'dan sil
    int res = await db.delete(
        'bicer_mazotlar ',
        where: 'id = ?',
        whereArgs: [id]
    );

    // 2. Firebase'den sil
    String? silinecekFirebaseId = firebaseId ?? id.toString();

    if (silinecekFirebaseId != null) {
      try {
        await FirebaseFirestore.instance
            .collection('bicer_mazotlar')
            .doc(silinecekFirebaseId)
            .delete();
        print("✅ Mobil: $silinecekFirebaseId buluttan temizlendi.");
      } catch (e) {
        print("❌ Firebase Silme Hatası: $e");
      }
    }

    return res;
  }


  Future<List<Map<String, dynamic>>> bicertahsilatListesiGetir(String isim) async {
    String temizIsim = isim.trim().toUpperCase();

    // --- WEB KORUMASI ---
    if (kIsWeb) {
      try {
        print("🌐 Web: '$temizIsim' için tahsilatlar 'bicermusteri_hareketleri' koleksiyonundan çekiliyor...");
        final snapshot = await FirebaseFirestore.instance
            .collection('bicermusteri_hareketleri') // 👈 Standart koleksiyon adı
            .where('ciftci_ad', isEqualTo: temizIsim)
            .orderBy('tarih', descending: true)
            .get();

        return snapshot.docs.map((doc) => {
          'id': doc.id, // Arayüz silme işlemi için bu ID'yi bekler
          ...doc.data(),
        }).toList();
      } catch (e) {
        print("❌ Web Tahsilat Listesi Hatası: $e");
        return [];
      }
    }

    // --- MOBİL İÇİN: HİBRİT MANTIK ---
    final db = await instance.database;

    try {
      // 1. ADIM: Firebase'den çekmeyi dene (Önce Güncel Bulut Verisi)
      final snapshot = await FirebaseFirestore.instance
          .collection('bicermusteri_hareketleri') // 👈 Standart koleksiyon adı
          .where('ciftci_ad', isEqualTo: temizIsim)
          .orderBy('tarih', descending: true)
          .get(const GetOptions(source: Source.serverAndCache));

      if (snapshot.docs.isNotEmpty) {
        return snapshot.docs.map((doc) {
          var data = doc.data();
          return {
            'id': doc.id, // Firestore doküman ID'si
            ...data,
          };
        }).toList();
      }

      // Eğer Firebase boşsa yerel SQLite'a bak
      throw Exception("Firebase boş, yerelden çek");

    } catch (e) {
      // 2. ADIM: İnternet hatası veya boş veri durumunda SQLite'a dön
      print("🏠 Mobil: Yerel veritabanından çekiliyor...");

      return await db.query(
          'bicermusteri_hareketleri', // 👈 Senin gerçek SQLite tablo adın
          where: 'UPPER(ciftci_ad) = ?',
          whereArgs: [temizIsim],
          orderBy: 'tarih DESC'
      );
    }
  }




  Future<void> odemeEkle(dynamic isId, double miktar, String tarih) async {
    // --- WEB İÇİN: FIREBASE BATCH (TRANSACTIONAL) İŞLEM ---
    if (kIsWeb) {
      try {
        print("🌐 Web: Ödeme kaydı ve bakiye güncelleme başlatılıyor...");

        // Firebase'de toplu işlem (Batch) başlatalım
        WriteBatch batch = FirebaseFirestore.instance.batch();

        // 1. Ödemeler koleksiyonuna yeni kayıt ekle
        DocumentReference yeniOdemeRef = FirebaseFirestore.instance.collection('odemeler').doc();
        batch.set(yeniOdemeRef, {
          'is_id': isId.toString(),
          'miktar': miktar,
          'tarih': tarih,
          'islem_zamani': FieldValue.serverTimestamp(),
        });

        // 2. Biçer işleri tablosundaki ödenen_miktar alanını artır
        DocumentReference isRef = FirebaseFirestore.instance.collection('bicer_isleri').doc(isId.toString());
        batch.update(isRef, {
          'odenen_miktar': FieldValue.increment(miktar),
        });

        // Hepsini tek seferde onayla (Ya hep ya hiç)
        await batch.commit();

        print("✅ Web: Ödeme işlendi ve iş bakiyesi güncellendi.");
        return;
      } catch (e) {
        print("❌ Web Ödeme Hatası: $e");
        rethrow;
      }
    }

    // --- MOBİL İÇİN: SENİN ORİJİNAL TRANSACTION MANTIĞIN ---
    final db = await instance.database;

    await db.transaction((txn) async {
      await txn.insert('odemeler', {
        'is_id': isId,
        'miktar': miktar,
        'tarih': tarih
      });

      await txn.execute(
          'UPDATE bicer_isleri SET odenen_miktar = odenen_miktar + ? WHERE id = ?',
          [miktar, isId]
      );
    });

    // Mobil Firebase Senkronizasyonu
    try {
      await _firestore.collection('odemeler').add({
        'is_id': isId,
        'miktar': miktar,
        'tarih': tarih,
        'islem_zamani': FieldValue.serverTimestamp(),
      });

      await _firestore.collection('bicer_isleri').doc(isId.toString()).update({
        'odenen_miktar': FieldValue.increment(miktar),
      });

      print("🚀 Firebase: Mobil verisi bulutla eşitlendi.");
    } catch (e) {
      print("⚠️ Firebase Senkron Hatası: $e");
    }
  }




  // --- MARKET MÜŞTERİSİ (EVREN TARIM) TAHSİLAT SİL ---
  Future<void> musteriTahsilatSil(dynamic tahsilatId, String musteriAd, double miktar) async {

    // --- WEB İÇİN: FIREBASE BATCH (TOPLU İŞLEM) ---
    if (kIsWeb) {
      try {
        print("🌐 Web: Market tahsilatı siliniyor ve bakiye geri yükleniyor...");

        WriteBatch batch = FirebaseFirestore.instance.batch();

        // 1. Ekstre kaydını (hareketini) buluttan sil
        DocumentReference hareketRef = FirebaseFirestore.instance
            .collection('musteri_hareketleri')
            .doc(tahsilatId.toString());
        batch.delete(hareketRef);

        // 2. Müşterinin bakiyesine parayı geri ekle
        // Not: 'musteriler' koleksiyonunda döküman ID'sinin 'musteriAd' olduğunu varsayıyoruz.
        DocumentReference musteriRef = FirebaseFirestore.instance
            .collection('musteriler')
            .doc(musteriAd);
        batch.update(musteriRef, {
          'bakiye': FieldValue.increment(miktar)
        });

        // İşlemi onayla
        await batch.commit();

        print("✅ Web: Market tahsilatı silindi, bakiye müşteriye iade edildi.");
        return;
      } catch (e) {
        print("❌ Web Market Silme Hatası: $e");
        return;
      }
    }

    // --- MOBİL İÇİN: SENİN ORİJİNAL TRANSACTION MANTIĞIN ---
    final db = await instance.database;
    await db.transaction((txn) async {
      // 1. Ekstre tablosundan kaydı sil
      await txn.delete('musteri_hareketleri', where: 'id = ?', whereArgs: [tahsilatId]);

      // 2. Müşterinin borcuna parayı geri ekle
      await txn.execute(
          'UPDATE musteriler SET bakiye = bakiye + ? WHERE ad = ?',
          [miktar, musteriAd]
      );
    });

    try {
      // Firebase Senkronu
      await _firestore.collection('musteri_hareketleri').doc(tahsilatId.toString()).delete();
      await _firestore.collection('musteriler').doc(musteriAd).update({
        'bakiye': FieldValue.increment(miktar)
      });
      print("✅ Mobil: Market tahsilatı silindi, bakiye güncellendi.");
    } catch (e) {
      print("⚠️ Market Firebase Hatası: $e");
    }
  }

  // --- ÖZEL GÜNCELLEME (RAW SQL) ---
  Future<int> customUpdate(String query, List<dynamic> arguments) async {
    // --- WEB KORUMASI ---
    if (kIsWeb) {
      print("⚠️ Web Uyarı: 'customUpdate' Web'de doğrudan SQL çalıştıramaz.");
      print("Sorgu: $query | Argümanlar: $arguments");

      // Buraya çok sık kullandığın bir SQL varsa Firebase karşılığını ekleyebiliriz.
      // Şimdilik çökmemesi için 0 döndürüyoruz.
      return 0;
    }

    // --- MOBİL İÇİN: SQLite ---
    final db = await instance.database;
    return await db.rawUpdate(query, arguments);
  }

// --- ÖZEL SİLME (RAW SQL) ---
  Future<int> customDelete(String query, [List<dynamic>? arguments]) async {
    // --- WEB KORUMASI ---
    if (kIsWeb) {
      print("⚠️ Web Uyarı: 'customDelete' Web'de doğrudan SQL çalıştıramaz.");
      print("Sorgu: $query");

      return 0;
    }

    // --- MOBİL İÇİN: SQLite ---
    final db = await instance.database;
    return await db.rawDelete(query, arguments);
  }


  Future<void> bicerHareketEkle(Map<String, dynamic> veri) async {
    final db = await instance.database;

    // 1. MÜKERRER KONTROLÜ (Görseldeki is_id, tip ve miktar verilerine göre)
    List<Map> kontrol = await db.query(
      'bicermusteri_hareketleri',
      where: 'is_id = ? AND tip = ? AND miktar = ?',
      whereArgs: [veri['is_id'], veri['tip'], veri['miktar']],
    );

    if (kontrol.isNotEmpty) {
      print("⚠️ MÜKERRER ENGELİ: Bu hareket zaten kayıtlı.");
      return;
    }

    // 2. KAYIT İŞLEMİ
    if (kIsWeb) {
      // Web ise direkt Firebase'e (is_synced burada 1 sayılır)
      await FirebaseFirestore.instance.collection('bicermusteri_hareketleri').add(veri);
      print("✅ Web üzerinden Firebase'e kaydedildi.");
    } else {
      // Mobil ise önce yerel SQLite'a (Varsayılan is_synced: 0)
      int id = await db.insert('bicermusteri_hareketleri', veri);
      print("✅ Yerel kayıt ID: $id. Firebase senkronizasyonu deneniyor...");

      // 3. ANINDA SENKRONİZASYON DENEMESİ
      try {
        // Sadece bu yeni eklenen kaydı gönderiyoruz
        await FirebaseFirestore.instance.collection('bicermusteri_hareketleri').add({
          'is_id': veri['is_id'],
          'ciftci_ad': veri['ciftci_ad'],
          'miktar': veri['miktar'], // Görseldeki miktar sütunu
          'tarih': veri['tarih'],
          'sezon': veri['sezon'],
          'tip': veri['tip'], // HASAT veya TAHSİLAT
          'aciklama': veri['aciklama'], // Görseldeki aciklama sütunu
          'odeme_tipi': veri['odeme_tipi'],
        });

        // Firebase'e gittiyse yerelde is_synced = 1 yap
        await db.update(
          'bicermusteri_hareketleri',
          {'is_synced': 1},
          where: 'id = ?',
          whereArgs: [id],
        );
        print("✅ Firebase anlık senkronizasyon başarılı.");
      } catch (e) {
        // İnternet yoksa veya hata varsa hata verme, sadece logla
        // Veri zaten SQLite'da (is_synced=0) olduğu için sonra toplu gönderilecek.
        print("⚠️ Anlık senkronizasyon başarısız (İnternet yok?): $e");
      }
    }
  }

  Future<void> bicerHareketleriniBulutaGonder() async {
    final db = await instance.database;

    // Henüz gitmeyenleri bul
    final List<Map<String, dynamic>> gitmeyenler = await db.query(
      'bicermusteri_hareketleri',
      where: 'is_synced = ?',
      whereArgs: [0],
    );

    if (gitmeyenler.isEmpty) {
      print("ℹ️ Gönderilecek yeni veri yok.");
      return;
    }

    for (var hareket in gitmeyenler) {
      try {
        await FirebaseFirestore.instance
            .collection('bicermusteri_hareketleri')
            .add({
          'is_id': hareket['is_id'],
          'ciftci_ad': hareket['ciftci_ad'],
          'miktar': hareket['miktar'],
          'tarih': hareket['tarih'],
          'sezon': hareket['sezon'],
          'tip': hareket['tip'],
          'aciklama': hareket['aciklama'],
          'odeme_tipi': hareket['odeme_tipi'],
        });

        // Başarılıysa güncelle
        await db.update(
          'bicermusteri_hareketleri',
          {'is_synced': 1},
          where: 'id = ?',
          whereArgs: [hareket['id']],
        );
      } catch (e) {
        print("❌ Senkronizasyon hatası: $e");
        break; // Bir hata varsa döngüyü kır (internet kopmuş olabilir)
      }
    }
    print("✅ Senkronizasyon tamamlandı.");
  }


  Future<int> bicerTahsilatEkle(Map<String, dynamic> veri) async {
    // 1. Veri Hazırlama (Şema ile %100 uyumlu anahtarlar)
    Map<String, dynamic> guncelVeri = {
      'is_id': int.tryParse(veri['is_id']?.toString() ?? '0') ?? 0,
      'ciftci_ad': (veri['ciftci_ad'] ?? '').toString().toUpperCase().trim(),
      'miktar': double.tryParse(veri['miktar']?.toString() ?? '0') ?? 0.0, // Görseldeki miktar
      'tarih': veri['tarih'] ?? DateTime.now().toString().split(' ')[0],
      'sezon': veri['sezon']?.toString() ?? "2026",
      'odeme_tipi': veri['odeme_tipi'] ?? "NAKİT",
      'tip': 'TAHSİLAT', // 👈 Kritik: Ekstrede 'miktar'ın düşmesi için şart!
      'aciklama': veri['aciklama'] ?? "NAKİT TAHSİLAT", // Görseldeki aciklama
    };

    // --- WEB APP (FIRESTORE) ---
    if (kIsWeb) {
      try {
        await FirebaseFirestore.instance
            .collection('bicermusteri_hareketleri')
            .add({
          ...guncelVeri,
          'kayit_zamani': FieldValue.serverTimestamp(),
          'is_synced': 1,
        });
        print("✅ Web: Tahsilat başarıyla kaydedildi.");
        return 1;
      } catch (e) {
        print("❌ Web Kayıt Hatası: $e");
        return -1;
      }
    }

    // --- MOBIL (SQLITE + FIREBASE) ---
    try {
      final db = await instance.database;

      // 1. Yerel SQLite'a kaydet (is_synced: 0)
      int id = await db.insert('bicermusteri_hareketleri', {
        ...guncelVeri,
        'is_synced': 0,
      });

      // 2. Anlık Firebase Senkronizasyonu
      try {
        await FirebaseFirestore.instance
            .collection('bicermusteri_hareketleri')
            .doc(id.toString())
            .set({
          ...guncelVeri,
          'id': id,
          'kayit_zamani': FieldValue.serverTimestamp(),
          'is_synced': 1,
        });

        // Başarılıysa yerelde 1 yap
        await db.update(
          'bicermusteri_hareketleri',
          {'is_synced': 1},
          where: 'id = ?',
          whereArgs: [id],
        );
        print("🚀 Mobil: Tahsilat bulutla eşitlendi (ID: $id).");
      } catch (e) {
        print("⚠️ Mobil: Bulut senkronizasyonu ertelendi.");
      }

      return id;
    } catch (e) {
      print("❌ Mobil Kayıt Hatası: $e");
      return -1;
    }
  }


  Future<void> bicertamMusteriSil(int id, String adSoyad) async {
    final db = await instance.database;
    String temizAd = adSoyad.trim().toUpperCase();

    print("\n--- 🗑️ MÜŞTERİ TÜM VERİLERİYLE SİLİNİYOR: $temizAd ---");

    // 1. SQLite Temizliği (Transaction ile tek seferde güvenli silme)
    try {
      await db.transaction((txn) async {
        // Müşterinin ana kartını sil
        await txn.delete('bicer_musterileri', where: 'id = ?', whereArgs: [id]);

        // Müşteriye ait tüm hasat işlerini sil
        await txn.delete('bicer_isleri', where: 'UPPER(ciftci_ad) = ?', whereArgs: [temizAd]);

        // Müşteriye ait tüm tahsilat hareketlerini sil (DOĞRU TABLO ADI)
        await txn.delete('bicermusteri_hareketleri', where: 'UPPER(ciftci_ad) = ?', whereArgs: [temizAd]);
      });
      print("✅ Mobil: Yerel veriler temizlendi.");
    } catch (e) {
      print("❌ Mobil Silme Hatası: $e");
    }

    // 2. Firebase Temizliği (İşleri ve Tahsilatları topluca siler)
    try {
      // A. Müşteri Kartını Sil
      await FirebaseFirestore.instance.collection('bicer_musterileri').doc(id.toString()).delete();

      // B. Hasat İşlerini (bicer_isleri) Sil
      var isler = await FirebaseFirestore.instance
          .collection('bicer_isleri')
          .where('ciftci_ad', isEqualTo: temizAd)
          .get();
      for (var doc in isler.docs) { await doc.reference.delete(); }

      // C. Tahsilatları (bicermusteri_hareketleri) Sil
      // DİKKAT: Firebase görselindeki isme göre burayı güncelledik.
      var tahsilatlar = await FirebaseFirestore.instance
          .collection('bicermusteri_hareketleri')
          .where('ciftci_ad', isEqualTo: temizAd)
          .get();
      for (var doc in tahsilatlar.docs) { await doc.reference.delete(); }

      print("🚀 Firebase: Tüm bulut verileri temizlendi.");
    } catch (e) {
      print("⚠️ Firebase Hatası (İnternet olmayabilir): $e");
    }
  }

  // --- KATEGORİ MÜHÜRLEME FONKSİYONLARI ---

  Future<void> kategoriEkleGaranti(String kategoriAdi) async {
    // 'instance.database' yerine sınıfın içindeki 'database' getter'ını kullanıyoruz
    final db = await database;

    try {
      // 'kategoriler' tablon varsa oraya ekler
      // 'ConflictAlgorithm.ignore' için sqflite paketinin içe aktarılması şarttır
      await db.insert(
        'kategoriler',
        {'ad': kategoriAdi.toUpperCase()},
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
      print("✅ Kategori mühürlendi: $kategoriAdi");
    } catch (e) {
      // Tablo yoksa sadece log atar, uygulama çökmez
      print("⚠️ Kategori tablosu yok, stok verisinden okunacak.");
    }
  }


  Future<void> kategoriEkle(String ad) async => await kategoriEkleGaranti(ad);

  // Kategorileri garantiye alan çekme fonksiyonu
  Future<List<String>> kategorileriGetirGaranti() async {
    final db = await database;

    // Stok tanımları tablosundaki benzersiz (DISTINCT) kategorileri tarar
    final List<Map<String, dynamic>> maps = await db.rawQuery(
        'SELECT DISTINCT kategori FROM stok_tanimlari WHERE kategori IS NOT NULL'
    );

    return List.generate(maps.length, (i) {
      return maps[i]['kategori'].toString().toUpperCase();
    });
  }

  // --- BİÇER ÇİFTÇİSİ (ÖZÇOBANLAR) TAHSİLAT SİL ---
  Future<void> bicerTahsilatSil(dynamic tahsilatId, String ciftciAd, double miktar) async {

    // --- WEB İÇİN: FIREBASE BATCH (GÜVENLİ SİLME) ---
    if (kIsWeb) {
      try {
        print("🌐 Web: Biçer tahsilatı siliniyor ve borç geri açılıyor...");

        WriteBatch batch = FirebaseFirestore.instance.batch();

        // 1. Tahsilat kaydını buluttan sil
        DocumentReference tahsilatRef = FirebaseFirestore.instance
            .collection('tahsilatlar')
            .doc(tahsilatId.toString());
        batch.delete(tahsilatRef);

        // 2. Çiftçinin Biçer işlerindeki ödenen miktarını düş (Borcu geri artır)
        // ÖNEMLİ: Burada çiftçinin tüm işlerini etkilememek için genellikle 'is_id' üzerinden gidilir
        // ama senin SQLite sorgun 'ciftci_ad' üzerinden gittiği için ben de öyle kuruyorum:
        var islerSnapshot = await FirebaseFirestore.instance
            .collection('bicer_isleri')
            .where('ciftci_ad', isEqualTo: ciftciAd)
            .get();

        for (var doc in islerSnapshot.docs) {
          batch.update(doc.reference, {
            'odenen_miktar': FieldValue.increment(-miktar) // Pozitif ödemeyi negatife çevirip düşüyoruz
          });
        }

        // İşlemi onayla
        await batch.commit();

        print("✅ Web: Biçer tahsilatı silindi, borçlar güncellendi.");
        return;
      } catch (e) {
        print("❌ Web Biçer Silme Hatası: $e");
        return;
      }
    }

    // --- MOBİL İÇİN: SENİN ORİJİNAL SQLite + FIREBASE MANTIĞIN ---
    final db = await instance.database;
    await db.transaction((txn) async {
      // 1. Tahsilatlar tablosundan kaydı sil
      await txn.delete('tahsilatlar', where: 'id = ?', whereArgs: [tahsilatId]);

      // 2. Çiftçinin Biçer işlerindeki ödenen miktarını düş
      await txn.execute(
          'UPDATE bicer_isleri SET odenen_miktar = odenen_miktar - ? WHERE ciftci_ad = ?',
          [miktar, ciftciAd]
      );
    });

    try {
      // Firebase Senkronu
      await _firestore.collection('tahsilatlar').doc(tahsilatId.toString()).delete();
      print("✅ Mobil: Biçer tahsilatı silindi, borç geri açıldı.");
    } catch (e) {
      print("⚠️ Biçer Firebase Hatası: $e");
    }
  }


  Future<void> tahsilatGuncelle(dynamic tahsilatId, dynamic isId, double eskiMiktar, double yeniMiktar, Map<String, dynamic> yeniVeri) async {

    // Aradaki farkı hesapla (Bakiyeye eklenecek veya çıkarılacak tutar)
    double fark = yeniMiktar - eskiMiktar;

    // --- WEB İÇİN: FIREBASE BATCH UPDATE ---
    if (kIsWeb) {
      try {
        print("🌐 Web: Tahsilat güncelleniyor ve bakiye farkı işleniyor (Fark: $fark)...");

        WriteBatch batch = FirebaseFirestore.instance.batch();

        // 1. Tahsilat dökümanını güncelle
        DocumentReference tahsilatRef = FirebaseFirestore.instance
            .collection('tahsilatlar')
            .doc(tahsilatId.toString());
        batch.update(tahsilatRef, {
          ...yeniVeri,
          'son_guncelleme': FieldValue.serverTimestamp(),
        });

        // 2. Biçer işindeki bakiyeyi fark kadar güncelle
        DocumentReference isRef = FirebaseFirestore.instance
            .collection('bicer_isleri')
            .doc(isId.toString());
        batch.update(isRef, {
          'odenen_miktar': FieldValue.increment(fark),
          'son_guncelleme': FieldValue.serverTimestamp(),
        });

        // İşlemleri toplu olarak onayla
        await batch.commit();

        print("✅ Web: Tahsilat ve bakiye başarıyla güncellendi.");
        return;
      } catch (e) {
        print("❌ Web Tahsilat Güncelleme Hatası: $e");
        rethrow;
      }
    }

    // --- MOBİL İÇİN: SENİN ORİJİNAL SQLite + FIREBASE MANTIĞIN ---
    final db = await instance.database;

    await db.transaction((txn) async {
      // Tahsilat tablosunu güncelle
      await txn.update('tahsilatlar', yeniVeri, where: 'id = ?', whereArgs: [tahsilatId]);

      // Biçer işleri tablosundaki ödenen miktarı düzelt
      await txn.execute(
          'UPDATE bicer_isleri SET odenen_miktar = odenen_miktar - ? + ? WHERE id = ?',
          [eskiMiktar, yeniMiktar, isId]
      );
    });

    try {
      // Firebase Senkronu
      await _firestore.collection('tahsilatlar').doc(tahsilatId.toString()).update(yeniVeri);

      await _firestore.collection('bicer_isleri').doc(isId.toString()).update({
        'odenen_miktar': FieldValue.increment(fark),
        'son_guncelleme': FieldValue.serverTimestamp(),
      });

      print("🚀 Firebase: Mobil verisi bulutla eşitlendi.");
    } catch (e) {
      print("⚠️ Firebase Senkron Hatası: $e");
    }
  }

  Future<int> aracSil(dynamic id) async {
    // --- WEB İÇİN: DOĞRUDAN FIREBASE SİLME ---
    if (kIsWeb) {
      try {
        print("🌐 Web: Araç kaydı buluttan siliniyor (ID: $id)...");

        await FirebaseFirestore.instance
            .collection('araclar')
            .doc(id.toString())
            .delete();

        print("✅ Web: Araç başarıyla silindi.");
        return 1; // Başarılı kabul ediyoruz
      } catch (e) {
        print("❌ Web Araç Silme Hatası: $e");
        return -1;
      }
    }

    // --- MOBİL İÇİN: SENİN ORİJİNAL SQLite + FIREBASE MANTIĞIN ---
    final db = await instance.database;

    try {
      // 1. ADIM: Yerel SQLite'dan sil
      int res = await db.delete(
          "araclar",
          where: "id = ?",
          whereArgs: [id]
      );

      // 2. ADIM: Firebase'den kaldır
      await _firestore.collection('araclar').doc(id.toString()).delete();

      print("✅ Mobil: Araç hem yerelden hem Firebase'den silindi.");
      return res;

    } catch (e) {
      print("❌ Mobil Silme Hatası: $e");
      return -1;
    }
  }

  Future<List<Map<String, dynamic>>> aracListesi() async {
    // --- WEB İÇİN: SADECE FIREBASE ---
    if (kIsWeb) {
      try {
        debugPrint("🌐 Web: Araçlar buluttan çekiliyor...");
        // Not: Koleksiyon adı önceki metodunla uyumlu olması için 'galeri' yapıldı.
        // Eğer Firebase'de 'araclar' ise burayı ona göre güncelle abi.
        final snapshot = await FirebaseFirestore.instance.collection('araclar').get();

        return snapshot.docs.map((doc) {
          var data = doc.data();
          data['id_bulut'] = doc.id;
          data['id'] = data['id'] ?? doc.id; // ID null ise döküman ID'sini bas
          return data;
        }).toList();
      } catch (e) {
        debugPrint("❌ Web Araç Listesi Hatası: $e");
        return [];
      }
    }

    // --- MOBİL İÇİN: HİBRİT MANTIK (ÖNCE BULUT, SONRA YEREL) ---
    try {
      debugPrint("📡 Mobil: Firebase'den araçlar çekiliyor...");
      final snapshot = await _firestore.collection('araclar').get();

      if (snapshot.docs.isNotEmpty) {
        debugPrint("☁️ Veriler Firebase'den getirildi.");
        return snapshot.docs.map((doc) {
          var data = doc.data();
          if (data['id'] == null) data['id'] = doc.id;
          return data;
        }).toList();
      }
    } catch (e) {
      debugPrint("⚠️ Firebase Hatası (İnternet yoksa normaldir): $e");
    }

    // Firebase boşsa veya hata varsa SQLite'a bak
    debugPrint("📱 Veriler yerel cihazdan (SQLite) getirildi.");
    final db = await instance.database;

    // Tablo adını 'galeri' olarak düzeltiyorum, hata alıyorsan veritabanı kurulumundaki tablo adıyla eşitlemelisin.
    try {
      return await db.query('araclar', orderBy: 'id DESC');
    } catch (e) {
      debugPrint("❌ SQLite Sorgu Hatası (Tablo adını kontrol et!): $e");
      return [];
    }
  }



  Future<int> aracEkle(Map<String, dynamic> row) async {
    // --- WEB İÇİN: DOĞRUDAN FIREBASE KAYDI ---
    if (kIsWeb) {
      try {
        print("🌐 Web: Yeni araç buluta işleniyor...");

        // 1. Firebase'e ekle (Otomatik ID oluşturur)
        DocumentReference docRef = await FirebaseFirestore.instance
            .collection('araclar') // Koleksiyon adını 'galeri' olarak sabitledik
            .add({
          ...row,
          'olusturma_tarihi': FieldValue.serverTimestamp(),
          'is_synced': 1,
        });

        // 2. Web'de döküman ID'sini 'id' alanına geri yazalım ki listelemede sorun olmasın
        await docRef.update({'id': docRef.id});

        print("✅ Web: Araç başarıyla eklendi. ID: ${docRef.id}");
        return 1; // Başarılı dönüşü
      } catch (e) {
        print("❌ Web Araç Ekleme Hatası: $e");
        return -1;
      }
    }

    // --- MOBİL İÇİN: ÖNCE YEREL (SQLite), SONRA BULUT (Firebase) ---
    final db = await instance.database;

    // 1. Yerel veritabanına ekle
    // Tablo adını 'galeri' olarak düzeltiyorum (önceki metodlarla uyum için)
    int id = await db.insert('araclar', row);

    try {
      // 2. Firebase Firestore'a ekle
      DocumentReference docRef = _firestore.collection('araclar').doc(id.toString());

      await docRef.set({
        ...row,
        'id': id,
        'olusturma_tarihi': FieldValue.serverTimestamp(),
      });

      // 3. Başarıyla senkronize edildiyse SQLite'ı güncelle
      await db.update(
        'araclar',
        {'is_synced': 1, 'firebase_id': docRef.id},
        where: 'id = ?',
        whereArgs: [id],
      );
      print("🚀 Mobil: Araç yerel ve buluta başarıyla kaydedildi.");
    } catch (e) {
      print("⚠️ Firebase Senkronizasyon Hatası: $e");
    }

    return id;
  }


  Future<void> _firebaseSenkronizasyon(int localId, Map<String, dynamic> veri) async {
    // --- WEB KORUMASI ---
    // Web'de veriler zaten doğrudan Firebase'e yazıldığı için
    // bu metodu Web'de sessizce pas geçiyoruz.
    if (kIsWeb) return;

    try {
      print("🔄 Mobil: Araç #$localId senkronize ediliyor...");

      // 1. Verinin bir kopyasını al
      var firebaseVeri = Map<String, dynamic>.from(veri);

      // 2. Alanları düzenle
      firebaseVeri.remove('is_synced');
      firebaseVeri['id'] = localId;

      // 3. Firebase'e yaz
      await FirebaseFirestore.instance
          .collection('araclar')
          .doc(localId.toString())
          .set(firebaseVeri);

      // 4. SQLite'ı güncelle (Sadece Mobilde çalışır)
      final db = await instance.database;
      await db.update(
        'araclar',
        {'is_synced': 1},
        where: 'id = ?',
        whereArgs: [localId],
      );

      print("✅ Başarılı: Araç #$localId Firebase ile senkronize edildi.");
    } catch (e) {
      print("❌ Firebase Senkronizasyon Hatası: $e");
    }
  }
// Senkronize edilmeyenleri listele
  Future<List<Map<String, dynamic>>> getUnsyncedAraclar() async {
    // --- WEB KORUMASI ---
    if (kIsWeb) {
      // Web'de yerel kayıt (SQLite) olmadığı için her şey her zaman senkronizedir.
      return [];
    }

    // --- MOBİL İÇİN: SQLite SORGUSU ---
    final db = await instance.database;

    // Tablo adını 'araclar' veya 'galeri' olarak projenizle eşitlemeyi unutmayın abi.
    return await db.query(
        'araclar',
        where: 'is_synced = ?',
        whereArgs: [0]
    );
  }


  Future<void> senkronizeEt() async {
    // --- WEB KORUMASI ---
    if (kIsWeb) {
      // Web'de veriler anlık yazıldığı için senkronizasyon gerekmez
      print("🌐 Web: Veriler zaten bulutta, senkronizasyona gerek yok.");
      return;
    }

    // --- MOBİL İÇİN: TOPLU GÖNDERİM MANTIĞI ---
    try {
      // 1. Henüz gönderilmemiş araçları yerelden çek
      List<Map<String, dynamic>> bekleyenler = await getUnsyncedAraclar();

      if (bekleyenler.isEmpty) {
        print("📱 Mobil: Senkronize edilecek araç yok.");
        return;
      }

      print("🚀 Mobil: ${bekleyenler.length} araç buluta gönderiliyor...");

      for (var arac in bekleyenler) {
        // Orijinal _firebaseSenkronizasyon metodunu çağırıyoruz
        // Not: arac['id'] SQLite'dan gelen int değerdir
        await _firebaseSenkronizasyon(arac['id'], arac);
      }

      print("✅ Mobil: Tüm araçlar başarıyla senkronize edildi.");
    } catch (e) {
      print("❌ Mobil Senkronizasyon Hatası: $e");
    }
  }



// --- BU METODU DA SINIFIN EN ALTINA (SON PARANTEZDEN ÖNCE) EKLE ---
  String normalizeAd(String ad) {
    return ad.trim().toUpperCase()
        .replaceAll('ı', 'I')
        .replaceAll('i', 'İ')
        .replaceAll('ğ', 'Ğ')
        .replaceAll('ü', 'Ü')
        .replaceAll('ş', 'Ş')
        .replaceAll('ö', 'Ö')
        .replaceAll('ç', 'Ç');
  }

  Future<void> bakiyeEkle(String musteriId, double tutar, String tip) async {

    // --- WEB İÇİN: DOĞRUDAN FIREBASE GÜNCELLEME ---
    if (kIsWeb) {
      try {
        print("🌐 Web: Müşteri bakiyesi bulutta güncelleniyor (ID: $musteriId)...");

        await FirebaseFirestore.instance.collection('musteriler').doc(musteriId).update({
          'bakiye': FieldValue.increment(tutar),
          'son_odeme_tipi': tip,
          'son_islem': FieldValue.serverTimestamp(),
        });

        print("✅ Web: Müşteri bakiyesi başarıyla güncellendi.");
        return;
      } catch (e) {
        print("❌ Web Bakiye Güncelleme Hatası: $e");
        rethrow;
      }
    }

    // --- MOBİL İÇİN: SQLite + FIREBASE SENKRONU ---
    final db = await instance.database;

    try {
      // 1. SQLite Güncelleme
      await db.rawUpdate(
        'UPDATE musteriler SET bakiye = bakiye + ? WHERE id = ?',
        [tutar, musteriId],
      );

      // 2. Firebase Senkronizasyonu
      await _firestore.collection('musteriler').doc(musteriId).update({
        'bakiye': FieldValue.increment(tutar),
        'son_odeme_tipi': tip,
        'son_islem': FieldValue.serverTimestamp(),
      });

      print("🚀 Mobil: Bakiye hem yerelde hem bulutta güncellendi.");
    } catch (e) {
      print("⚠️ Mobil Bakiye Senkron Hatası: $e");
      // SQLite güncellendiği için kullanıcı işlem tamam sanır,
      // ama internet gelince manuel senkronizasyon gerekecektir.
    }
  }


  Future<void> satisBitir(
      String musteriId,
      List<Map<String, dynamic>> sepet,
      double toplam,
      String odemeTipi,
      DateTime tarih,
      ) async {

    // --- WEB İÇİN: FIREBASE BATCH (TAM GÜVENLİ SATIŞ) ---
    if (kIsWeb) {
      try {
        print("🌐 Web: Satış işlemi başlatılıyor (Müşteri: $musteriId, Tutar: $toplam)...");

        WriteBatch batch = FirebaseFirestore.instance.batch();
        String tarihStr = tarih.toIso8601String();

        // 1. Müşteri Bakiyesini Güncelle
        DocumentReference musteriRef = FirebaseFirestore.instance.collection('musteriler').doc(musteriId);
        batch.update(musteriRef, {
          'bakiye': FieldValue.increment(toplam),
          'son_odeme_tipi': odemeTipi,
          'son_islem': FieldValue.serverTimestamp(),
        });

        // 2. Sepetteki her ürün için Stok Düş ve Satış Hareketi Ekle
        for (var u in sepet) {
          // Stok Güncelleme
          DocumentReference stokRef = FirebaseFirestore.instance.collection('stoklar').doc(u['id'].toString());
          batch.update(stokRef, {
            'miktar': FieldValue.increment(-u['adet']), // Stoğu düş
          });

          // Satış Hareketi Ekle
          DocumentReference hareketRef = FirebaseFirestore.instance.collection('satis_hareketleri').doc();
          batch.set(hareketRef, {
            'stok_id': u['id'],
            'musteri_id': musteriId,
            'urun_ad': u['ad'],
            'adet': u['adet'],
            'tutar': u['toplam'],
            'odeme_tipi': odemeTipi,
            'tarih': tarihStr,
          });
        }

        // Tüm işlemleri tek seferde onayla (Ya hep ya hiç)
        await batch.commit();
        print("✅ Web: Satış başarıyla tamamlandı, stoklar ve bakiye güncellendi.");
        return;
      } catch (e) {
        print("❌ Web Satış Hatası: $e");
        rethrow;
      }
    }

    // --- MOBİL İÇİN: MEVCUT MANTIK (SQLite + Firebase) ---
    // Not: Mobil tarafta bakiyeEkle, stokDus ve satisHareketiEkle
    // metodlarının zaten kendi içlerinde SQLite ve Firebase kontrolleri olduğu için
    // orijinal akışı bozmuyoruz.

    await bakiyeEkle(musteriId, toplam, odemeTipi);

    for (var u in sepet) {
      await stokDus(u['id'], u['adet']);

      await satisHareketiEkle({
        'stok_id': u['id'],
        'musteri_id': musteriId,
        'urun_ad': u['ad'],
        'adet': u['adet'],
        'tutar': u['toplam'],
        'odeme_tipi': odemeTipi,
        'tarih': tarih.toIso8601String(),
      });
    }
  }


  Future<void> stokDus(String stokId, double miktar) async {
    final String temizId = stokId.toString().trim();
    print("🔄 STOK DÜŞME TETİKLENDİ -> Aranan ID: '$temizId', Düşülecek Miktar: $miktar");

    // --- WEB ÇÖZÜMÜ ---
    if (kIsWeb) {
      try {
        await FirebaseFirestore.instance.collection('stoklar').doc(temizId).update({
          'adet': FieldValue.increment(-miktar),
        });
        print("✅ Web: Firestore stok düşüldü.");
        return;
      } catch (e) {
        print("❌ Web Stok Düşme Hatası: $e");
        return;
      }
    }

    // --- MOBİL (SQLite + Firestore) ÇÖZÜMÜ ---
    final db = await instance.database;
    try {
      // 1. Önce veritabanından bu ürünün gerçek bulut ID'sini (firebase_id) bulalım abi
      String fId = temizId; // Varsayılan olarak eldekini tutalım
      final List<Map<String, dynamic>> urunSorgu = await db.query(
        'stoklar',
        columns: ['firebase_id'],
        where: 'CAST(id AS TEXT) = ? OR firebase_id = ? OR stok_kodu = ?',
        whereArgs: [temizId, temizId, temizId],
        limit: 1,
      );

      if (urunSorgu.isNotEmpty && urunSorgu.first['firebase_id'] != null) {
        fId = urunSorgu.first['firebase_id'].toString().trim();
      }

      // 2. Şimdi SQLite üzerinde stoğu düşüyoruz (Senin mevcut kod)
      int etkilenenSatir = await db.rawUpdate(
        'UPDATE stoklar SET adet = IFNULL(adet, 0) - ? '
            'WHERE CAST(id AS TEXT) = ? OR firebase_id = ? OR stok_kodu = ?',
        [miktar, temizId, temizId, temizId],
      );

      print("📊 SQLite Stok Güncelleme Sonucu: $etkilenenSatir satır etkilendi.");

      // 3. İşte sihirli dokunuş: Firestore'a artık '40' değil, 'STK-EXCEL-...' kimliğini gönderiyoruz!
      print("☁️ Firestore Güncelleniyor -> Hedef Döküman ID: '$fId'");
      await FirebaseFirestore.instance.collection('stoklar').doc(fId).update({
        'adet': FieldValue.increment(-miktar),
      }).then((_) {
        print("✅ Mobil: Firestore stok düşme senkronize edildi.");
      }).catchError((err) {
        print("⚠️ Mobil: Firestore stok güncellenemedi: $err");
      });

    } catch (e) {
      print("⚠️ Mobil UYARI: Stok düşme işleminde hata çıktı: $e");
    }
  }

  Future<void> stogaGeriEkle(dynamic urunId, int iadeAdet) async {
    // Eğer iade edilecek miktar 0 veya negatifse işlem yapma
    if (iadeAdet <= 0) return;

    // --- WEB İÇİN: DOĞRUDAN FIREBASE GÜNCELLEME ---
    if (kIsWeb) {
      try {
        print("🌐 Web: Ürün stoga geri ekleniyor (ID: $urunId, Adet: $iadeAdet)...");

        // Firebase'de 'adet' alanını güvenli bir şekilde artırıyoruz
        await FirebaseFirestore.instance
            .collection('stoklar')
            .doc(urunId.toString())
            .update({
          'adet': FieldValue.increment(iadeAdet),
        });

        print("✅ Web: Stok başarıyla iade alındı.");
        return; // İşlem tamamlandı
      } catch (e) {
        print("❌ Web İade Hatası: $e");
        return;
      }
    }

    // --- MOBİL İÇİN: SQLite + FIREBASE SENKRONU ---
    final db = await instance.database;

    try {
      // 1. Yerel SQLite Güncelleme
      await db.rawUpdate(
          'UPDATE stoklar SET adet = IFNULL(adet, 0) + ? WHERE id = ?',
          [iadeAdet, urunId]
      );

      // 2. Firebase Senkronizasyonu
      await _firestore.collection('stoklar').doc(urunId.toString()).update({
        'adet': FieldValue.increment(iadeAdet),
      });

      print("🚀 Mobil: Ürün hem yerelde hem bulutta stoga iade edildi.");
    } catch (e) {
      print("⚠️ Mobil Firebase İade Hatası: $e");
    }
  }


  Future<void> musteriBakiyeGuncelle(String id, double tutar, String tip) async {
    final String temizId = id.trim();

    // --- WEB İÇİN: DOĞRUDAN FIREBASE MANTIĞI ---
    if (kIsWeb) {
      try {
        print("🌐 Web: Müşteri bakiyesi güncelleniyor (ID: $temizId)...");

        await FirebaseFirestore.instance
            .collection('musteriler')
            .doc(temizId)
            .set({
          'bakiye': FieldValue.increment(tutar), // Firebase mevcut bakiyeyi bulup üzerine ekler
          'son_islem': tip,
          'guncelleme': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        print("✅ Web: Bakiye bulutta başarıyla güncellendi.");
        return;
      } catch (e) {
        print("❌ Web Bakiye Hatası: $e");
        return;
      }
    }

    // --- MOBİL İÇİN: SQLite + FIREBASE SENKRONU ---
    final db = await instance.database;

    // 1. Önce SQL'de bakiyeyi mevcut olanın üzerine ekleyerek güncelle
    await db.rawUpdate(
        'UPDATE musteriler SET bakiye = bakiye + ? WHERE id = ?',
        [tutar, temizId]
    );

    // 2. Güncel bakiyeyi Firebase'e göndermek için son halini çek
    final res = await db.rawQuery('SELECT bakiye FROM musteriler WHERE id = ?', [temizId]);

    if (res.isNotEmpty) {
      double guncelBakiye = double.tryParse(res.first['bakiye'].toString()) ?? 0.0;

      try {
        // 3. FIREBASE GÜNCELLE (Hesaplanmış son rakamı gönderiyoruz)
        await FirebaseFirestore.instance
            .collection('musteriler')
            .doc(temizId)
            .set({
          'bakiye': guncelBakiye,
          'son_islem': tip,
          'guncelleme': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        print("🚀 Mobil: Yerel bakiye ve bulut eşitlendi: $guncelBakiye");
      } catch (e) {
        print("⚠️ Mobil Firebase Senkron Hatası (İnternet yoksa normaldir): $e");
      }
    }
  }


  Future<Map<String, dynamic>> getMusteri(String id) async {
    final String temizId = id.trim();

    // --- WEB İÇİN: FIREBASE ÜZERİNDEN GETİR ---
    if (kIsWeb) {
      try {
        print("🌐 Web: Müşteri bilgisi buluttan çekiliyor (ID: $temizId)...");

        var doc = await FirebaseFirestore.instance
            .collection('musteriler')
            .doc(temizId)
            .get();

        if (doc.exists) {
          var data = doc.data() as Map<String, dynamic>;
          // Firebase döküman ID'sini de haritaya ekleyelim (lazım olabilir)
          data['id'] = doc.id;
          return data;
        } else {
          print("⚠️ Web: Müşteri dökümanı bulunamadı.");
          return {'id': temizId, 'bakiye': 0.0, 'ad': 'Bilinmeyen'};
        }
      } catch (e) {
        print("❌ Web Müşteri Getirme Hatası: $e");
        return {'id': temizId, 'bakiye': 0.0, 'ad': 'Bilinmeyen'};
      }
    }

    // --- MOBİL İÇİN: SQLite SORGUSU ---
    final db = await instance.database;

    try {
      final res = await db.query(
        'musteriler',
        where: 'id = ?',
        whereArgs: [temizId],
        limit: 1,
      );

      if (res.isNotEmpty) {
        return res.first;
      } else {
        // Eğer müşteri yerelde bulunamazsa (belki henüz senkronize olmamıştır)
        return {'id': temizId, 'bakiye': 0.0, 'ad': 'Bilinmeyen'};
      }
    } catch (e) {
      print("❌ Mobil Müşteri Sorgu Hatası: $e");
      return {'id': temizId, 'bakiye': 0.0, 'ad': 'Bilinmeyen'};
    }
  }

// 1. ADIM: Satış Hareketini Galeri İçin Özelleştir (Hacı, burası Galeri için!)
  Future<void> satisHareketiEkle(Map<String, dynamic> veri) async {

    // --- WEB İÇİN: DOĞRUDAN FIREBASE KAYDI ---
    if (kIsWeb) {
      try {
        print("🌐 Web: Galeri satış hareketi buluta işleniyor...");

        // Web'de SQLite ID'si olmadığı için Firebase'in otomatik ID'sini kullanıyoruz
        await FirebaseFirestore.instance
            .collection('galeri_satislar')
            .add({
          ...veri,
          'firebase_tarih': FieldValue.serverTimestamp(),
        });

        print("✅ Web: Galeri satışı başarıyla kaydedildi.");
        return;
      } catch (e) {
        print("❌ Web Galeri Satış Hatası: $e");
        return;
      }
    }

    // --- MOBİL İÇİN: SQLite + FIREBASE SENKRONU ---
    final db = await instance.database;

    // 1. Yerel SQLite'a ekle (Satışlar tablosu)
    int yerelId = await db.insert('satislar', veri);

    try {
      // 2. Firebase'e gönder (Koleksiyon adı: galeri_satislar)
      await _firestore.collection('galeri_satislar').doc(yerelId.toString()).set({
        ...veri,
        'firebase_tarih': FieldValue.serverTimestamp(),
      });
      print("🚀 Mobil: Galeri satışı hem yerelde hem bulutta.");
    } catch (e) {
      print("⚠️ Firebase Galeri Satış Hatası: $e");
    }
  }

// 🔥 EVREN ABİ, BAKİYE DÜZELTME MOTORU (WEB UYUMLU)
  Future<void> hareketSilVeBakiyeyiDuzelt(String hareketId, String mId) async {
    print("\n--- 🗑️ HAREKET SİLME VE BAKİYE DÜZELTME BAŞLADI ---");

    double tutar = 0.0;
    String islemTipi = "SATIS";
    bool hareketBulundu = false;

    // --- WEB İÇİN: ÖNCE FIREBASE'DEN BİLGİLERİ AL ---
    if (kIsWeb) {
      try {
        // Senin Firestore yapına göre 'satislar' koleksiyonuna bakıyoruz
        var doc = await FirebaseFirestore.instance.collection('satislar').doc(hareketId).get();

        if (doc.exists) {
          var data = doc.data()!;
          tutar = double.tryParse(data['tutar'].toString()) ?? 0.0;
          islemTipi = data['islem']?.toString() ?? "SATIS";
          hareketBulundu = true;
        }
      } catch (e) {
        print("❌ Web: Hareket bilgisi alınırken hata: $e");
      }
    }
    // --- MOBİL İÇİN: SQLite'DAN BİLGİLERİ AL ---
    else {
      final db = await instance.database;
      var hareketler = await db.query('musteri_hareketleri', where: 'id = ?', whereArgs: [hareketId]);

      if (hareketler.isNotEmpty) {
        var h = hareketler.first;
        tutar = double.tryParse(h['tutar'].toString()) ?? 0.0;
        islemTipi = h['islem']?.toString() ?? "SATIS";
        hareketBulundu = true;
      }
    }

    // --- ORTAK MATEMATİK VE SİLME İŞLEMİ ---
    if (hareketBulundu) {
      // Satış siliniyorsa bakiye AZALMALI (-), Tahsilat siliniyorsa ARTMALI (+)
      double farkTutari = (islemTipi == 'SATIS' || islemTipi == 'SATIŞ') ? -tutar : tutar;

      print("📦 Silinecek İşlem: $islemTipi | Tutar: $tutar TL");
      print("⚖️ Bakiyeye Uygulanacak Düzeltme: $farkTutari TL");

      // 1. Bakiyeyi düzelt (Daha önce yazdığımız Web uyumlu metod)
      await musteriBakiyeGuncelle(mId, farkTutari, "HAREKET_SILINDI");

      // 2. Kayıtları temizle
      try {
        if (kIsWeb) {
          // Sadece buluttan sil
          await FirebaseFirestore.instance.collection('satislar').doc(hareketId).delete();
        } else {
          final db = await instance.database;
          // Hem yerelden hem buluttan sil
          await db.delete('musteri_hareketleri', where: 'id = ?', whereArgs: [hareketId]);
          await FirebaseFirestore.instance.collection('satislar').doc(hareketId).delete();
        }
        print("✅ [BAŞARILI]: Hareket silindi ve bakiye geri sarıldı.");
      } catch (e) {
        print("❌ [HATA]: Silme işlemi başarısız: $e");
      }
    } else {
      print("⚠️ [UYARI]: Silinecek hareket bulunamadı! ID: $hareketId");
    }
    print("--- 🏁 DÜZELTME İŞLEMİ BİTTİ ---\n");
  }
  Future<void> satisYapFirebase({
    required Map<String, dynamic> veri,
  }) async {
    // 1. Verileri Sağlama Al (Ortak Hazırlık)
    String mAd = veri['musteri_ad']?.toString().trim().toUpperCase() ?? 'BILINMEYEN';
    String mId = veri['musteri_id'].toString();
    double tutar = double.tryParse(veri['satis_fiyati'].toString()) ?? 0.0;
    String? sId = veri['stok_id']?.toString();
    int adet = int.tryParse(veri['adet'].toString()) ?? 1;
    String tarihStr = DateFormat('dd.MM.yyyy HH:mm').format(DateTime.now());

    String marka = veri['marka'] ?? '';
    String model = veri['model'] ?? '';
    String altModel = veri['alt_model'] ?? '';
    String urunDetay = "$marka $model $altModel ($adet Adet)".trim().toUpperCase();

    // --- WEB İÇİN: FIREBASE BATCH İŞLEMİ (SQL Transaction Yerine) ---
    if (kIsWeb) {
      try {
        print("🌐 Web: Satış işlemi bulut üzerinde başlatılıyor...");
        WriteBatch batch = FirebaseFirestore.instance.batch();

        // A- Müşteri Bakiyesini ve Son İşlemi Güncelle
        DocumentReference musteriRef = FirebaseFirestore.instance.collection('musteriler').doc(mId);
        batch.set(musteriRef, {
          'bakiye': FieldValue.increment(tutar),
          'son_islem': tarihStr
        }, SetOptions(merge: true));

        // B- Stoktan Düş
        if (sId != null && sId != "null") {
          DocumentReference stokRef = FirebaseFirestore.instance.collection('stoklar').doc(sId);
          batch.update(stokRef, {'adet': FieldValue.increment(-adet)});
        }

        // C- Satış Kaydını Arşive At (satislar_genel)
        DocumentReference satisRef = FirebaseFirestore.instance.collection('satislar_genel').doc();
        batch.set(satisRef, {
          'musteri_id': mId,
          'musteri_ad': mAd,
          'urun_detay': urunDetay,
          'tutar': tutar,
          'tarih': tarihStr,
          'sube': veri['sube'] ?? 'WEB_SUBE'
        });

        // Hepsini Tek Seferde Onayla
        await batch.commit();
        print("✅ Web: Satış başarıyla tamamlandı.");
        return;
      } catch (e) {
        print("❌ Web Satış Hatası: $e");
        return;
      }
    }

    // --- MOBİL İÇİN: SQL TRANSACTION + FIREBASE SENKRONU ---
    final db = await instance.database;

    await db.transaction((txn) async {
      // A- Bakiyeyi Güncelle
      await txn.execute(
          'UPDATE musteriler SET bakiye = IFNULL(bakiye, 0) + ? WHERE id = ?',
          [tutar, mId]
      );

      // B- Müşteri Hareketine İşle
      await txn.insert('musteri_hareketleri', {
        'musteri_id': mId,
        'musteri_ad': mAd,
        'islem': 'SATIS',
        'tutar': tutar,
        'aciklama': urunDetay,
        'tarih': tarihStr,
      });

      // C- Stoktan Düş
      if (sId != null && sId != "null") {
        await txn.execute('UPDATE stoklar SET adet = adet - ? WHERE id = ?', [adet, sId]);
      }

      // D- Satışlar Tablosuna Kayıt
      await txn.insert("satislar", {
        'stok_id': sId,
        'musteri_ad': mAd,
        'satis_fiyati': tutar,
        'tarih': tarihStr,
        'durum': 'TAMAMLANDI'
      });
    });

    // Mobil Firebase Senkronu
    try {
      await FirebaseFirestore.instance.collection('musteriler').doc(mId).set({
        'baye': FieldValue.increment(tutar),
        'son_islem': tarihStr
      }, SetOptions(merge: true));

      if (sId != null && sId != "null") {
        await FirebaseFirestore.instance.collection('stoklar').doc(sId).update({
          'adet': FieldValue.increment(-adet)
        });
      }

      await FirebaseFirestore.instance.collection('satislar_genel').add({
        'musteri_ad': mAd,
        'urun_detay': urunDetay,
        'tutar': tutar,
        'tarih': tarihStr,
        'sube': veri['sube'] ?? 'BELIRTILMEMIS'
      });

      print("🚀 Mobil: Satış yerel ve buluta işlendi.");
    } catch (e) {
      print("⚠️ Mobil Firebase Hatası: $e");
    }
  }


  Future<void> musteriSil(String musteriId) async {
    // --- 1. BULUT TEMİZLİĞİ (Web ve Mobil Ortak) ---
    try {
      print("☁️ Firebase: Müşteri ve hareketleri siliniyor...");

      // A. Önce Müşterinin Kendisini Sil
      await FirebaseFirestore.instance.collection('musteriler').doc(musteriId).delete();

      // B. Müşteriye Ait Tüm Hareketleri Bul ve Sil
      var hareketler = await FirebaseFirestore.instance
          .collection('musteri_hareketleri')
          .where('musteri_id', isEqualTo: musteriId)
          .get();

      for (var doc in hareketler.docs) {
        await doc.reference.delete();
      }
      print("✅ Firebase: Her şey temizlendi.");
    } catch (e) {
      print("❌ Firebase Silme Hatası: $e");
    }

    // --- 2. YEREL TEMİZLİK (Sadece Mobil/SQLite) ---
    if (!kIsWeb) {
      try {
        final db = await instance.database;

        // A. Müşteriyi Sil
        await db.delete(
          'musteriler',
          where: 'id = ?',
          whereArgs: [musteriId],
        );

        // B. Hareketleri Sil (İşte eksik olan kısım burasıydı)
        await db.delete(
          'musteri_hareketleri',
          where: 'musteri_id = ?',
          whereArgs: [musteriId],
        );

        print("🚀 SQLite: Müşteri ve geçmişi telefondan silindi.");
      } catch (e) {
        print("❌ SQLite Silme Hatası: $e");
      }
    }
  }


// DatabaseHelper.dart içine
  Future<List<Map<String, dynamic>>> satisIcinStoklariGetir() async {

    // --- WEB İÇİN: CANLI FIREBASE SORGUSU ---
    if (kIsWeb) {
      try {
        print("🌐 Web: Eldeki stoklar buluttan çekiliyor...");

        // Firebase'de 'adet' alanı 0'dan büyük olanları filtrele ve isme göre sırala
        var snapshot = await FirebaseFirestore.instance
            .collection('stoklar')
            .where('adet', isGreaterThan: 0)
            .orderBy('adet') // Not: Firebase'de 'where' kullandığın alanla 'orderBy' başlamalıdır
            .get();

        // Firebase verisini SQLite formatına (Map listesine) çeviriyoruz
        return snapshot.docs.map((doc) {
          var data = doc.data();
          data['id'] = doc.id; // SQLite'daki ID yapısıyla uyum için
          return data;
        }).toList();

      } catch (e) {
        print("❌ Web Stok Getirme Hatası: $e");
        return [];
      }
    }

    // --- MOBİL İÇİN: HIZLI SQLite SORGUSU ---
    final db = await instance.database;

    // Sadece elinde olan (adet > 0) ürünleri getir ki olmayan malı satma abi
    return await db.query(
        'stoklar',
        where: 'adet > 0',
        orderBy: 'urun ASC'
    );
  }


  Future<void> cekleriFirebaseDenAl() async {
    // --- WEB KORUMASI ---
    if (kIsWeb) {
      // Web'de SQLite yok, veriler zaten Firebase'de olduğu için indirmeye gerek yok.
      print("🌐 Web: Çekler zaten bulutta canlı, SQL kaydı atlanıyor.");
      return;
    }

    // --- MOBİL İÇİN: FIREBASE -> SQLite AKTARIMI ---
    try {
      final db = await database;

      print("🚀 Mobil: Çekler buluttan indiriliyor...");
      var snapshot = await FirebaseFirestore.instance.collection("cekler").get();

      if (snapshot.docs.isEmpty) {
        print("⚠️ Mobil: Bulutta hiç çek bulunamadı.");
        return;
      }

      for (var doc in snapshot.docs) {
        var data = doc.data();

        await db.insert(
          "cekler",
          {
            "firebase_id": doc.id, // Firebase döküman adını buraya mühürle
            "firmaAd": data["firmaAd"] ?? "BİLİNMEYEN",
            "tutar": data["tutar"] ?? 0,
            "vadeTarihi": data["vadeTarihi"] ?? "",
            "durum": data["durum"] ?? "BEKLEMEDE",
            "tip": data["tip"] ?? "CEK",
            "is_synced": 1, // Zaten Firebase'den geldiği için 1 yapıyoruz
          },
          conflictAlgorithm: ConflictAlgorithm.replace, // Aynı mühür gelirse üzerine yazar, hata vermez
        );
      }

      print("✅ Mobil: ÇEKLER SQL'e başarıyla BASILDI.");
    } catch (e) {
      print("❌ Mobil Çek Senkronizasyon Hatası: $e");
    }
  }



  void cekleriCanliDinle() {
    _cekSub?.cancel(); // Eski abonelik varsa kapat

    // --- WEB KORUMASI ---
    // Web'de verileri SQLite'a kopyalamaya gerek yok,
    // arayüzde doğrudan StreamBuilder kullanmak yeterlidir.
    if (kIsWeb) {
      print("🌐 Web: Çekler canlı dinleniyor (Arayüz üzerinden).");
      return;
    }

    // --- MOBİL İÇİN: FIREBASE -> SQLite CANLI AKTARIM ---
    _cekSub = FirebaseFirestore.instance
        .collection("cekler")
        .snapshots()
        .listen((snapshot) async {
      try {
        final db = await database;

        for (var doc in snapshot.docs) {
          var data = doc.data();

          await db.insert(
            "cekler",
            {
              "id": data["id"],
              "firmaAd": data["firmaAd"],
              "tutar": data["tutar"],
              "vadeTarihi": data["vadeTarihi"],
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
        print("🔥 Mobil: ÇEKLER CANLI SENKRON OK");
      } catch (e) {
        print("❌ Mobil Canlı Dinleme Hatası: $e");
      }
    });
  }


  void stoklariCanliDinle() {
    _stokSub?.cancel();

    // --- WEB KORUMASI ---
    if (kIsWeb) {
      print("🌐 Web: Stoklar canlı dinleniyor (Arayüzde StreamBuilder kullanılmalı).");
      return;
    }

    // --- MOBİL İÇİN: FIREBASE -> SQLite CANLI AKTARIM ---
    _stokSub = _firestore
        .collection('isletmeler')
        .doc('evren_ticaret')
        .collection('stoklar')
        .snapshots()
        .listen((snapshot) async {
      try {
        for (var doc in snapshot.docs) {
          var data = doc.data();

          // 🔥 LOOP ENGELİ: Kendi gönderdiğimiz veriyi tekrar yazmayalım
          if (data['kaynak'] == 'local') continue;

          // fromFirebase: true parametresi stokEkle içinde
          // tekrar Firebase'e yazılmasını engellemeli!
          await stokEkle(data, fromFirebase: true);
        }
        print("🔥 Mobil: CANLI STOK SENKRON TAMAM");
      } catch (e) {
        print("❌ Mobil Stok Dinleme Hatası: $e");
      }
    });
  }

  Future<void> stoklariFirebaseDenAl() async {
    // --- WEB KORUMASI ---
    if (kIsWeb) {
      // Web'de yerel veritabanı yok, veriler zaten bulutta.
      print("🌐 Web: Stoklar zaten bulutta canlı, SQL aktarımı atlanıyor.");
      return;
    }

    // --- MOBİL İÇİN: FIREBASE -> SQLite AKTARIMI ---
    try {
      final db = await database;

      print("🚀 Mobil: Stoklar buluttan indiriliyor...");
      var snapshot = await FirebaseFirestore.instance.collection("stoklar").get();

      if (snapshot.docs.isEmpty) {
        print("⚠️ Mobil: Bulutta hiç stok kaydı bulunamadı.");
        return;
      }

      for (var doc in snapshot.docs) {
        // SQLite'a veriyi gömüyoruz
        await db.insert(
          "stoklar",
          doc.data(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }

      print("✅ Mobil: STOKLAR SQL'e başarıyla BASILDI.");
    } catch (e) {
      print("❌ Mobil Stok Senkronizasyon Hatası: $e");
    }
  }


  Future<void> satisIptalEtVeStoguGeriAl({
    required String satisId, // Web/Mobil uyumu için String daha esnek
    required String stokId,
    required int miktar,
    required String musteriId, // İsim yerine ID ile işlem yapmak her zaman daha güvenlidir
    required double tutar,
  }) async {

    // --- WEB İÇİN: FIREBASE BATCH (ATOMIC) İŞLEMİ ---
    if (kIsWeb) {
      try {
        print("🌐 Web: Satış iptal ediliyor ve stok iade alınıyor...");
        WriteBatch batch = FirebaseFirestore.instance.batch();

        // 1. Satış kaydını sil
        DocumentReference satisRef = FirebaseFirestore.instance.collection('satislar').doc(satisId);
        batch.delete(satisRef);

        // 2. Stoğu geri artır
        DocumentReference stokRef = FirebaseFirestore.instance.collection('stoklar').doc(stokId);
        batch.update(stokRef, {'adet': FieldValue.increment(miktar)});

        // 3. Müşteri bakiyesini düzelt (Borç azalır)
        DocumentReference musteriRef = FirebaseFirestore.instance.collection('musteriler').doc(musteriId);
        batch.update(musteriRef, {'bakiye': FieldValue.increment(-tutar)});

        await batch.commit();
        print("✅ Web: Satış iptali ve iade işlemi başarılı.");
        return;
      } catch (e) {
        print("❌ Web İptal Hatası: $e");
        return;
      }
    }

    // --- MOBİL İÇİN: SQL TRANSACTION + FIREBASE GÜNCELLEME ---
    final db = await instance.database;

    await db.transaction((txn) async {
      // 1. Satışı yerel SQL'den sil
      await txn.delete('satislar', where: 'id = ?', whereArgs: [satisId]);

      // 2. STOĞU GERİ ARTIR
      await txn.execute(
          'UPDATE stoklar SET adet = adet + ? WHERE id = ?',
          [miktar, stokId]
      );

      // 3. Müşteri borcunu geri düş
      // Not: musteriAd yerine musteriId kullanmanı öneririm ama mevcut yapını korudum
      await txn.execute(
          'UPDATE musteriler SET bakiye = bakiye - ? WHERE id = ?',
          [tutar, musteriId]
      );
    });

    // Firebase Senkronu
    try {
      // Satış kaydını Firebase'den de sil
      await _firestore.collection('satislar').doc(satisId).delete();

      // Stoğu bulutta artır
      await _firestore.collection('stoklar').doc(stokId).update({
        'adet': FieldValue.increment(miktar)
      });

      // Bakiyeyi bulutta düş
      await _firestore.collection('musteriler').doc(musteriId).update({
        'bakiye': FieldValue.increment(-tutar)
      });

      print("🚀 Mobil: İptal işlemi yerel ve bulutta tamamlandı.");
    } catch (e) {
      print("⚠️ Firebase iade senkron hatası: $e");
    }
  }
  Future<List<Map<String, dynamic>>> musteriEkstresiGetir(String mId) async {
    String arananId = mId.trim();
    List<Map<String, dynamic>> hareketler = [];

    // 1. ADIM: ÖNCE SQLITE'A BAK (MOBİL İSE)
    if (!kIsWeb) {
      try {
        final db = await instance.database;
        hareketler = await db.rawQuery('''
        SELECT id, tarih, islem, IFNULL(aciklama, 'Detay Yok') as aciklama, 
               CAST(tutar AS REAL) as tutar 
        FROM musteri_hareketleri 
        WHERE musteri_id = ? 
        ORDER BY substr(tarih, 7, 4) DESC, substr(tarih, 4, 2) DESC, substr(tarih, 1, 2) DESC
      ''', [arananId]);

        print("📱 Mobil: SQLite'dan ${hareketler.length} adet veri bulundu.");
      } catch (e) {
        print("❌ SQLite Hatası: $e");
      }
    }

    // 2. ADIM: SQLITE BOŞSA VEYA WEB'DEYSEK FIREBASE'E GİT
    if (hareketler.isEmpty) {
      try {
        print("🌐 Bulut: Yerelde veri yok, Firebase sorgulanıyor: $arananId");

        var snapshot = await FirebaseFirestore.instance
            .collection('musteri_hareketleri')
            .where('musteri_id', isEqualTo: arananId)
            .get();

        if (snapshot.docs.isNotEmpty) {
          hareketler = snapshot.docs.map((doc) {
            var data = doc.data();
            return {
              'id': doc.id,
              'tarih': data['tarih'] ?? '',
              'islem': data['islem'] ?? 'SATIS',
              'aciklama': data['aciklama'] ?? 'Detay Yok',
              'tutar': double.tryParse(data['tutar'].toString()) ?? 0.0,
            };
          }).toList();

          // Firebase'den gelenleri tarihe göre sırala
          hareketler.sort((a, b) {
            try {
              DateFormat format = DateFormat("dd.MM.yyyy");
              return format.parse(b['tarih']).compareTo(format.parse(a['tarih']));
            } catch (e) { return 0; }
          });
        }
      } catch (e) {
        print("❌ Firebase Ekstre Hatası: $e");
      }
    }

    return hareketler;
  }

  Future<void> musteriHareketiSilFirebaseDestekli(dynamic id) async {
    print("\n--- 🗑️ HAREKET SİLME İŞLEMİ BAŞLADI ---");

    // --- WEB İÇİN: DOĞRUDAN FIREBASE SİLME ---
    if (kIsWeb) {
      try {
        print("🌐 Web: Hareket buluttan siliniyor (DocID: $id)...");

        // Web'de 'id' parametresi doğrudan Firestore döküman ID'si (String) olmalı
        await FirebaseFirestore.instance
            .collection('musteri_hareketleri')
            .doc(id.toString())
            .delete();

        print("✅ Web: Hareket başarıyla temizlendi.");
        return;
      } catch (e) {
        print("❌ Web Silme Hatası: $e");
        return;
      }
    }

    // --- MOBİL İÇİN: SQLite + FIREBASE SENKRONU ---
    final db = await instance.database;
    int sqliteId = int.tryParse(id.toString()) ?? 0;

    try {
      // 1. Bilgileri yedekle (Firebase'de bulabilmek için)
      List<Map<String, dynamic>> maps = await db.query(
        'musteri_hareketleri',
        where: 'id = ?',
        whereArgs: [sqliteId],
      );

      if (maps.isNotEmpty) {
        String mId = maps.first['musteri_id'].toString();

        // 2. Yerelden (SQL) Sil
        await db.delete(
          'musteri_hareketleri',
          where: 'id = ?',
          whereArgs: [sqliteId],
        );

        // 3. Firebase'den Sil (Senin mevcut mantığınla: mId ve sqlite_id eşleşmesi)
        var snapshot = await FirebaseFirestore.instance
            .collection('musteri_hareketleri')
            .where('musteri_id', isEqualTo: mId)
            .where('sqlite_id', isEqualTo: sqliteId)
            .get();

        for (var doc in snapshot.docs) {
          await doc.reference.delete();
          print("🚀 Mobil: Buluttan senkron silindi.");
        }

        print("✅ Mobil: İşlem başarıyla tamamlandı.");
      } else {
        print("⚠️ Mobil: Silinecek kayıt yerelde bulunamadı.");
      }
    } catch (e) {
      print("❌ Mobil Silme Hatası: $e");
    }
  }

  Future<void> tabloBakimiYap(Database db) async {
    if (kIsWeb) return; // Web'de SQLite yok, pas geç.

    try {
      debugPrint("🛠️ [BAKIM] Yeni Tarım Sistemi Şema Kontrolü Başladı...");

      // 1. Yeni Sistemdeki Güncel Tablo Listesi
      final tablolar = [
        'musteriler',
        'stoklar',
        'stok_tanimlari',
        'tarim_firmalari',         // GÜNCEL
        'tarim_firma_hareketleri', // GÜNCEL
        'tahsilatlar',
        'musteri_hareketleri'
      ];

      for (String tablo in tablolar) {
        // Tablo var mı? (Yoksa bakım yapmaya gerek yok, CreateTable zaten halleder)
        var tabloCheck = await db.rawQuery(
            "SELECT name FROM sqlite_master WHERE type='table' AND name=?", [tablo]);
        if (tabloCheck.isEmpty) {
          debugPrint("⚠️ $tablo bulunamadı, atlanıyor.");
          continue;
        }

        // Mevcut kolonları al
        var columns = await db.rawQuery("PRAGMA table_info($tablo)");
        var columnNames = columns.map((c) => c['name'].toString()).toList();

        // --- GENEL MÜHÜRLER (Tüm tablolarda olması gerekenler) ---

        // Senkronizasyon mührü
        if (!columnNames.contains('is_synced')) {
          await db.execute("ALTER TABLE $tablo ADD COLUMN is_synced INTEGER DEFAULT 0");
          debugPrint("✅ $tablo: 'is_synced' mührü çakıldı.");
        }

        // Firebase döküman kimliği (En kritik mühür)
        if (!columnNames.contains('firebase_id')) {
          await db.execute("ALTER TABLE $tablo ADD COLUMN firebase_id TEXT");
          debugPrint("✅ $tablo: 'firebase_id' alanı açıldı.");
        }

        // Silinme işareti (Soft Delete)
        if (!columnNames.contains('silindi')) {
          await db.execute("ALTER TABLE $tablo ADD COLUMN silindi INTEGER DEFAULT 0");
          debugPrint("✅ $tablo: 'silindi' kontrolü eklendi.");
        }

        // Şube yönetimi
        if (!columnNames.contains('sube')) {
          await db.execute("ALTER TABLE $tablo ADD COLUMN sube TEXT DEFAULT 'MERKEZ'");
          debugPrint("✅ $tablo: 'sube' alanı eklendi.");
        }

        // --- ÖZEL MÜHÜRLER (Tablo bazlı eksikler) ---

        // Firma Hareketleri için cari_kod eksikse (Eski sistemden geçişte gerekebilir)
        if (tablo == 'tarim_firma_hareketleri' && !columnNames.contains('cari_kod')) {
          await db.execute("ALTER TABLE tarim_firma_hareketleri ADD COLUMN cari_kod TEXT");
          debugPrint("✅ tarim_firma_hareketleri: 'cari_kod' alanı eklendi.");
        }
      }

      debugPrint("🏁 [BAKIM] Tüm tablolar yeni sisteme göre mühürlendi.");
    } catch (e) {
      debugPrint("❌ [BAKIM HATASI]: $e");
    }
  }
// DatabaseHelper.dart içine eklenecekler:

  // Çekin durumunu hem telefonda hem bulutta günceller
  Future<void> cekDurumGuncelle(dynamic id, String yeniDurum) async {

    // --- WEB İÇİN: DOĞRUDAN FIREBASE GÜNCELLEME ---
    if (kIsWeb) {
      try {
        print("🌐 Web: Çek durumu bulutta güncelleniyor (ID: $id)...");

        await FirebaseFirestore.instance
            .collection('cekler')
            .doc(id.toString())
            .update({
          'durum': yeniDurum,
        });

        print("✅ Web: Çek durumu '$yeniDurum' olarak güncellendi.");
        return;
      } catch (e) {
        print("❌ Web Çek Güncelleme Hatası: $e");
        return;
      }
    }

    // --- MOBİL İÇİN: SQLite + FIREBASE SENKRONU ---
    try {
      final db = await database;

      // 1. Yerel SQLite Güncelleme
      await db.update(
        'cekler',
        {'durum': yeniDurum, 'is_synced': 0}, // Tekrar senkron olması için 0 yaptık
        where: 'id = ?',
        whereArgs: [id],
      );

      // 2. Firebase Güncelleme
      await FirebaseFirestore.instance
          .collection('cekler')
          .doc(id.toString())
          .update({
        'durum': yeniDurum,
      });

      print("🚀 Mobil: Çek durumu hem yerelde hem bulutta güncellendi.");
    } catch (e) {
      print("❌ Mobil Çek Güncelleme Hatası: $e");
    }
  }

  Future<void> cekResimGuncelle(dynamic id, String yeniYol) async {
    print("\n--- 📸 ÇEK RESİM GÜNCELLEME BAŞLADI ---");

    // --- WEB İÇİN: SADECE FIREBASE GÜNCELLE ---
    if (kIsWeb) {
      try {
        print("🌐 Web: Çek resmi bulutta güncelleniyor (URL/Yol: $yeniYol)");

        await FirebaseFirestore.instance
            .collection('cekler')
            .doc(id.toString())
            .update({
          'resimYolu': yeniYol, // Web'de bu genellikle bir 'https://...' linkidir
        });

        print("✅ Web: Resim yolu başarıyla güncellendi.");
        return;
      } catch (e) {
        print("❌ Web Resim Güncelleme Hatası: $e");
        return;
      }
    }

    // --- MOBİL İÇİN: SQLite + FIREBASE SENKRONU ---
    try {
      final db = await database;

      // 1. Yerel SQLite Güncelleme
      await db.update(
        'cekler',
        {'resimYolu': yeniYol},
        where: 'id = ?',
        whereArgs: [id],
      );

      // 2. Firebase Güncelleme
      await FirebaseFirestore.instance
          .collection('cekler')
          .doc(id.toString())
          .update({
        'resimYolu': yeniYol,
      });

      print("🚀 Mobil: Resim yolu hem yerelde hem bulutta güncellendi.");
    } catch (e) {
      print("❌ Mobil Resim Güncelleme Hatası: $e");
    }
  }

// Mevcut çeki tamamen günceller (Düzenleme ekranı için)
  Future<void> cekGuncelle(CekModel cek) async {
    print("\n--- 📝 ÇEK GÜNCELLEME BAŞLADI (ID: ${cek.id}) ---");

    // --- WEB İÇİN: DOĞRUDAN FIREBASE ÜZERİNE YAZ ---
    if (kIsWeb) {
      try {
        print("🌐 Web: Çek verileri bulutta güncelleniyor...");

        // set() ve merge:true kullanarak tüm modeli buluta basıyoruz
        await FirebaseFirestore.instance
            .collection('cekler')
            .doc(cek.id.toString())
            .set(cek.toMap(), SetOptions(merge: true));

        print("✅ Web: Çek başarıyla güncellendi.");
        return;
      } catch (e) {
        print("❌ Web Güncelleme Hatası: $e");
        return;
      }
    }

    // --- MOBİL İÇİN: SQLite + FIREBASE SENKRONU ---
    try {
      final db = await database;

      // 1. Yerel SQLite Güncelleme
      // is_synced: 0 ekliyoruz ki arka plan servisi bu değişikliği fark etsin
      Map<String, dynamic> veri = cek.toMap();
      veri['is_synced'] = 0;

      await db.update(
        'cekler',
        veri,
        where: 'id = ?',
        whereArgs: [cek.id],
      );

      // 2. Firebase Güncelleme
      await FirebaseFirestore.instance
          .collection('cekler')
          .doc(cek.id.toString())
          .set(cek.toMap(), SetOptions(merge: true));

      print("🚀 Mobil: Çek hem yerelde hem bulutta güncellendi.");
    } catch (e) {
      print("❌ Mobil Güncelleme Hatası: $e");
    }
  }




  Future<void> satisEkle(Map<String, dynamic> veri) async {
    print("\n--- 💰 SATIŞ KAYDI BAŞLATILDI ---");

    // --- WEB İÇİN: DOĞRUDAN BULUTA YAZ ---
    if (kIsWeb) {
      try {
        print("🌐 Web: Satış verisi Firebase'e gönderiliyor...");

        // Web'de döküman ID'sini Firestore otomatik versin veya 'id' varsa onu kullan
        String docId = veri['id']?.toString() ??
            FirebaseFirestore.instance.collection('satislar').doc().id;

        await FirebaseFirestore.instance
            .collection('satislar')
            .doc(docId)
            .set(veri, SetOptions(merge: true));

        print("✅ Web: Satış buluta başarıyla işlendi.");
        return; // Web işlemi burada biter
      } catch (e) {
        print("❌ Web Satış Kayıt Hatası: $e");
        return;
      }
    }

    // --- MOBİL İÇİN: SQLite + FIREBASE SENKRONU ---
    final db = await instance.database;

    try {
      // 1. Yerel SQLite Kaydı
      // is_synced: 0 ekliyoruz ki internet yoksa bile sonra buluta atılsın
      Map<String, dynamic> localVeri = Map.from(veri);
      localVeri['is_synced'] = 0;

      await db.insert(
        'satislar',
        localVeri,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      print("🚀 Mobil: Satış telefona kaydedildi.");

      // 2. Anlık Firebase Senkronu (İnternet varsa)
      await FirebaseFirestore.instance
          .collection('satislar')
          .doc(veri['id'].toString())
          .set(veri, SetOptions(merge: true));

      print("✅ Mobil: Satış buluta da gönderildi.");

    } catch (e) {
      print("⚠️ Mobil Kayıt Hatası: $e (Yerel kayıt yapılmış olabilir)");
    }
  }

  Future<void> pesinSatisVeTahsilat({
    required String musteriAd,
    required String stokId, // dynamic/String yapmak Web uyumu için daha iyi
    required int miktar,
    required double birimFiyat,
    required String odemeYontemi, // NAKİT, POS, HAVALE
  }) async {
    double toplamTutar = miktar * birimFiyat;
    String suAnkiTarih = DateFormat("dd.MM.yyyy HH:mm").format(DateTime.now());

    // --- WEB İÇİN: FIREBASE ATOMIC BATCH ---
    if (kIsWeb) {
      try {
        print("🌐 Web: Peşin satış ve tahsilat buluta işleniyor...");
        var batch = FirebaseFirestore.instance.batch();

        // 1. Stoktan Malı Düş
        var stokRef = FirebaseFirestore.instance.collection('stoklar').doc(stokId.toString());
        batch.update(stokRef, {'adet': FieldValue.increment(-miktar)});

        // 2. Müşteri Ekstresine SATIŞI İşle
        var satisRef = FirebaseFirestore.instance.collection('musteri_hareketleri').doc();
        batch.set(satisRef, {
          'musteri_ad': musteriAd.toUpperCase(),
          'islem': 'SATIS',
          'tutar': toplamTutar,
          'aciklama': '$miktar ADET ÜRÜN (PEŞİN SATIŞ)',
          'tarih': suAnkiTarih,
        });

        // 3. Müşteri Ekstresine TAHSİLATI İşle
        var tahsilatRef = FirebaseFirestore.instance.collection('musteri_hareketleri').doc();
        batch.set(tahsilatRef, {
          'musteri_ad': musteriAd.toUpperCase(),
          'islem': 'TAHSILAT',
          'tutar': toplamTutar,
          'aciklama': 'SATIŞ ANINDA $odemeYontemi TAHSİLAT',
          'tarih': suAnkiTarih,
        });

        await batch.commit();
        print("✅ Web: İşlem başarıyla tamamlandı.");
        return;
      } catch (e) {
        print("❌ Web Hatası: $e");
        return;
      }
    }

    // --- MOBİL İÇİN: SQLite TRANSACTION + FIREBASE SENKRONU ---
    final db = await instance.database;
    await db.transaction((txn) async {
      // A. Stoktan Malı Düş
      await txn.execute('UPDATE stoklar SET adet = adet - ? WHERE id = ?', [miktar, stokId]);

      // B. Satış Hareketi
      await txn.insert('musteri_hareketleri', {
        'musteri_ad': musteriAd,
        'islem': 'SATIS',
        'tutar': toplamTutar,
        'aciklama': '$miktar ADET ÜRÜN (PEŞİN SATIŞ)',
        'tarih': suAnkiTarih,
      });

      // C. Tahsilat Hareketi
      await txn.insert('musteri_hareketleri', {
        'musteri_ad': musteriAd,
        'islem': 'TAHSILAT',
        'tutar': toplamTutar,
        'aciklama': 'SATIŞ ANINDA $odemeYontemi TAHSİLAT',
        'tarih': suAnkiTarih,
      });
    });

    // Mobil için bulut senkronu
    try {
      var batch = FirebaseFirestore.instance.batch();

      // Stok güncelleme
      batch.update(FirebaseFirestore.instance.collection('stoklar').doc(stokId.toString()), {
        'adet': FieldValue.increment(-miktar),
      });

      // Hareketleri buluta bas
      batch.set(FirebaseFirestore.instance.collection('musteri_hareketleri').doc(), {
        'musteri_ad': musteriAd.toUpperCase(),
        'islem': 'SATIS',
        'tutar': toplamTutar,
        'tarih': suAnkiTarih,
      });

      batch.set(FirebaseFirestore.instance.collection('musteri_hareketleri').doc(), {
        'musteri_ad': musteriAd.toUpperCase(),
        'islem': 'TAHSILAT',
        'tutar': toplamTutar,
        'tarih': suAnkiTarih,
      });

      await batch.commit();
      print("🚀 Mobil: Peşin işlem senkronize edildi.");
    } catch (e) {
      print("⚠️ Firebase Senkron Hatası: $e");
    }
  }

  Future<List<Map<String, dynamic>>> evraklariGetir(dynamic musteriId) async {
    List<Map<String, dynamic>> tumEvraklar = [];
    String mId = musteriId.toString();

    // --- 1. ADIM: FIREBASE (BULUT) SORGUSU ---
    try {
      print("🚀 Evraklar buluttan sorgulanıyor... (Müşteri ID: $mId)");

      var snapshot = await FirebaseFirestore.instance
          .collection('evraklar')
          .where('musteri_id', isEqualTo: mId)
          .get();

      if (snapshot.docs.isNotEmpty) {
        for (var doc in snapshot.docs) {
          var data = doc.data();
          data['doc_id'] = doc.id; // Silme/Güncelleme için bu ID şart
          tumEvraklar.add(data);
        }
        print("✅ Firebase'den ${tumEvraklar.length} evrak getirildi.");
        return tumEvraklar; // Bulutta veri varsa hemen döndür, aşağıya bakma
      }
    } catch (e) {
      print("❌ Evrak Firebase Hatası: $e");
    }

    // --- WEB KORUMASI ---
    if (kIsWeb) {
      // Web'de SQLite olmadığı için Firebase boşsa boş liste döndürür
      print("🌐 Web: Bulutta evrak bulunamadı, işlem sonlandırıldı.");
      return [];
    }

    // --- 2. ADIM: MOBİL İÇİN YEREL (SQLite) SORGUSU ---
    try {
      print("📱 Mobil: Bulutta yok, yerel arşive bakılıyor...");
      final db = await instance.database;

      final List<Map<String, dynamic>> yerelEvraklar = await db.query(
          'evraklar',
          where: 'musteri_id = ?',
          whereArgs: [mId]
      );

      print("✅ SQLite'dan ${yerelEvraklar.length} evrak getirildi.");
      return yerelEvraklar;
    } catch (e) {
      print("❌ SQLite Evrak Hatası: $e");
      return [];
    }
  }

  // Tüm çiftçileri (müşterileri) getiren fonksiyon
  Future<List<Map<String, dynamic>>> tumCiftcileriGetir() async {
    final db = await instance.database;
    // Tablo adının 'bicer_musterileri' olduğundan emin olun
    return await db.query('bicer_musterileri', orderBy: 'ad_soyad ASC');
  }

  // =========================================================
  // 1. FİRMA BAKİYE GÜNCELLEME (Harcama/Ödeme İşlemleri İçin)
  // =========================================================
  Future<void> firmaBakiyesiGuncelle(String firmaAd, double tutar, String tip) async {
    print("\n--- 🏢 FİRMA BAKİYE GÜNCELLEME BAŞLADI ---");
    String fAd = firmaAd.trim().toUpperCase();

    // --- WEB TARAFI ---
    if (kIsWeb) {
      await _bulutBakiyeIslemi(fAd, tutar, tip);
      return;
    }

    // --- MOBİL TARAFI ---
    final db = await instance.database;
    String query = "";

    // Tip kontrolü (Bakiye mantığı)
    if (tip == "ÖDEME" || tip == "TAHSİLAT") {
      query = 'UPDATE tarim_firmalari SET alacak = alacak - ? WHERE ad = ?';
    } else {
      query = 'UPDATE tarim_firmalari SET alacak = alacak + ? WHERE ad = ?';
    }

    try {
      await db.rawUpdate(query, [tutar, fAd]);
      // Firebase'i arkada sessizce güncelliyoruz (Await yok, donma yok!)
      _bulutBakiyeIslemi(fAd, tutar, tip);
      print("✅ Mobil: Yerel ve Bulut bakiye mühürlendi.");
    } catch (e) {
      print("❌ Bakiye Güncelleme Hatası: $e");
    }
  }

  // =========================================================
  // 2. FİRMA BİLGİ GÜNCELLEME (Ad, Tel, Yetkili Değişimi İçin)
  // =========================================================
  Future<int> firmaGuncelle(dynamic id, Map<String, dynamic> veri, {String? cariKod}) async {
    const String tabloAdi = 'tarim_firmalari';
    Map<String, dynamic> temizVeri = Map<String, dynamic>.from(veri);

    // --- WEB TARAFI ---
    if (kIsWeb) {
      try {
        String docId = (cariKod != null && cariKod.isNotEmpty) ? cariKod : id.toString();
        await FirebaseFirestore.instance.collection(tabloAdi).doc(docId).set(
            {...temizVeri, 'son_guncelleme': FieldValue.serverTimestamp()},
            SetOptions(merge: true)
        );
        return 1;
      } catch (e) { return 0; }
    }

    // --- MOBİL TARAFI ---
    try {
      final db = await instance.database;
      int res = await db.update(tabloAdi, temizVeri, where: 'id = ?', whereArgs: [id]);

      // Bulut senkronunu await etmeden (void gibi) çağırıyoruz
      _bulutBilgiSenkronEt(id, temizVeri, cariKod);
      return res;
    } catch (e) { return 0; }
  }

  // =========================================================
  // YARDIMCI (PRIVATE) METODLAR - HATALARI ÖNLEYEN KISIM
  // =========================================================

  // Bakiye için Firebase Yardımcısı
  Future<void> _bulutBakiyeIslemi(String fAd, double tutar, String tip) async {
    try {
      double miktar = (tip == "ÖDEME" || tip == "TAHSİLAT") ? -tutar : tutar;
      await FirebaseFirestore.instance.collection('tarim_firmalari').doc(fAd).update({
        'alacak': FieldValue.increment(miktar),
        'son_islem': FieldValue.serverTimestamp(),
      });
    } catch (e) { print("☁️ Bulut bakiye hatası (İnternet yoksa normal): $e"); }
  }

  // Bilgi güncelleme için Firebase Yardımcısı
  void _bulutBilgiSenkronEt(dynamic id, Map<String, dynamic> veri, String? cariKod) {
    String docId = (cariKod != null && cariKod.isNotEmpty) ? cariKod : id.toString();
    FirebaseFirestore.instance.collection('tarim_firmalari').doc(docId).set(
        {...veri, 'son_guncelleme': FieldValue.serverTimestamp()},
        SetOptions(merge: true)
    ).then((_) => print("✅ Firma bilgileri bulutta güncellendi."))
        .catchError((e) => print("⚠️ Firma bilgileri buluta gönderilemedi."));
  }





  Future<void> musteriHareketSil(
      String hareketId, // Bu ID'nin Firebase'deki doküman ismiyle birebir aynı olması şart!
      String musteriId,
      double tutar,
      String islemTipi
      ) async {
    print("\n--- 🗑️ HAREKET SİLME VE BAKİYE DÜZELTME BAŞLADI ---");

    // 1. MATEMATİKSEL DÜZELTME HESABI
    // Tahsilat siliniyorsa borç artar (+), Satış siliniyorsa borç azalır (-)
    double duzeltmeTutari = (islemTipi.toUpperCase() == "TAHSILAT")
        ? tutar.abs()
        : -tutar.abs();

    // --- WEB İÇİN: SADECE FIREBASE ---
    if (kIsWeb) {
      try {
        var batch = FirebaseFirestore.instance.batch();

        // 🚀 DİKKAT: Fotoğraftaki ID'lerin başında "HL_" yok.
        // O yüzden direkt hareketId kullanıyoruz.
        var hareketRef = FirebaseFirestore.instance
            .collection('musteri_hareketleri')
            .doc(hareketId);

        batch.delete(hareketRef);

        var musteriRef = FirebaseFirestore.instance
            .collection('musteriler')
            .doc(musteriId);

        batch.update(musteriRef, {
          'bakiye': FieldValue.increment(duzeltmeTutari),
          'guncelleme': DateTime.now().toIso8601String(),
        });

        await batch.commit();
        print("✅ Web: Firebase'den silindi ve bakiye $duzeltmeTutari güncellendi.");
        return;
      } catch (e) {
        print("❌ Web Silme Hatası: $e");
        return;
      }
    }

    // --- MOBİL İÇİN: ÖNCE SQLITE, SONRA FIREBASE ---
    final db = await instance.database;
    try {
      // 1. SQLite'dan Sil
      // Eğer veriyi bulut üzerinden çekiyorsan, SQLite'da bu hareket zaten olmayabilir.
      await db.delete(
        'musteri_hareketleri',
        where: 'id = ?',
        whereArgs: [hareketId],
      );

      // 2. SQLite Bakiyesini Güncelle
      await db.execute(
          "UPDATE musteriler SET bakiye = bakiye + ? WHERE id = ? OR tc = ?",
          [duzeltmeTutari, musteriId, musteriId]
      );

      // 3. Firebase'den de Sil (Senkronizasyon)
      try {
        var batch = FirebaseFirestore.instance.batch();

        // Doküman ID'sini direkt kullanıyoruz
        batch.delete(FirebaseFirestore.instance
            .collection('musteri_hareketleri')
            .doc(hareketId));

        batch.update(FirebaseFirestore.instance
            .collection('musteriler')
            .doc(musteriId), {
          'bakiye': FieldValue.increment(duzeltmeTutari),
          'guncelleme': DateTime.now().toIso8601String(),
        });

        await batch.commit();
        print("☁️ Mobil: Firebase senkronu tamam, buluttan da silindi.");
      } catch (fbError) {
        print("⚠️ Mobil: Firebase'e ulaşılamadı, veri sadece yerelde silindi.");
      }

      print("✅ Mobil: İşlem başarıyla sonuçlandı.");
    } catch (e) {
      print("❌ Mobil Silme Hatası: $e");
    }
  }

  Future<List<Map<String, dynamic>>> musteriproformaekstresi(String musteriId) async {
    final String temizId = musteriId.trim();
    List<Map<String, dynamic>> ekstre = [];

    // --- WEB İÇİN: DOĞRUDAN FIREBASE'DEN ÇEK ---
    if (kIsWeb) {
      try {
        print("🌐 Web: $temizId için proforma ekstresi buluttan sorgulanıyor...");

        // Proformalar koleksiyonuna bakıyoruz
        final snapshot = await FirebaseFirestore.instance
            .collection('proformalar')
            .where('musteri_id', isEqualTo: temizId)
            .get();

        if (snapshot.docs.isNotEmpty) {
          ekstre = snapshot.docs.map((doc) {
            var data = doc.data();
            data['doc_id'] = doc.id; // Silme işlemi gerekirse lazım olur
            return data;
          }).toList();

          // Tarihe göre sıralama (En yeni en üstte)
          ekstre.sort((a, b) => (b['tarih'] ?? "").compareTo(a['tarih'] ?? ""));

          print("✅ Web: Firebase'den ${ekstre.length} kayıt getirildi.");
        }
        return ekstre;
      } catch (e) {
        print("❌ Web Sorgu Hatası: $e");
        return [];
      }
    }

    // --- MOBİL İÇİN: ÖNCE SQLite, SONRA FIREBASE ---
    try {
      final db = await instance.database;
      print("📱 Mobil: $temizId için yerel sorgu başlatıldı...");

      // 1. ADIM: SQLite (Cepteki Defter)
      final List<Map<String, dynamic>> yerelKayitlar = await db.query(
        'musteri_hareketleri', // Tablo ismine dikkat abi (proformalar mı hareketler mi?)
        where: 'musteri_id = ?',
        whereArgs: [temizId],
        orderBy: 'id DESC',
      );

      if (yerelKayitlar.isNotEmpty) {
        print("✅ Mobil: SQLite'dan ${yerelKayitlar.length} kayıt getirildi.");
        return yerelKayitlar;
      }

      // 2. ADIM: Firebase (Yedek Plan)
      final snapshot = await FirebaseFirestore.instance
          .collection('proformalar')
          .where('musteri_id', isEqualTo: temizId)
          .get();

      if (snapshot.docs.isNotEmpty) {
        print("☁️ Mobil: Yerelde yoktu, Firebase'den çekildi.");
        return snapshot.docs.map((doc) => doc.data()).toList();
      }

      return [];
    } catch (e) {
      print("❌ Mobil Sorgu Hatası: $e");
      return [];
    }
  }

  Future<void> firmaHareketiSil({
    required String hareketId,
    required String cariKod,
    required double tutar,
    required String tip,
  }) async {
    print("\n--- 🗑️ FİRMA HAREKETİ İPTAL EDİLİYOR: $hareketId ---");

    final db = await instance.database;
    final batch = FirebaseFirestore.instance.batch();

    // MANTIK:
    // ALIM silinirse -> Firmanın bizdeki ALACAĞI azalır (-)
    // SATIŞ silinirse -> Firmanın bize olan BORCU azalır (-)
    // ÖDEME silinirse -> Borç/Alacak tipine göre geri artar (+)
    // (Basit tutmak için işleme göre tersine çeviriyoruz)

    double duzeltmeTutari = -tutar;
    String bakiyeAlani = (tip.toUpperCase() == "ALIM") ? "alacak" : "borc";

    try {
      // 1. SQLITE İŞLEMLERİ (Mobil ise)
      if (!kIsWeb) {
        await db.transaction((txn) async {
          // Hareketi yerelden sil
          await txn.delete('tarim_firma_hareketleri',
              where: 'firebase_id = ?', whereArgs: [hareketId]);

          // Bakiyeyi yerelde düzelt
          await txn.rawUpdate(
              'UPDATE tarim_firmalari SET $bakiyeAlani = $bakiyeAlani + ? WHERE cari_kod = ?',
              [duzeltmeTutari, cariKod]
          );
        });
      }

      // 2. FIREBASE İŞLEMLERİ (Her ikisi için)
      // Firma dökümanını bul
      var firmaRef = FirebaseFirestore.instance.collection('tarim_firmalari').doc(cariKod);
      // Hareket dökümanını bul
      var hareketRef = FirebaseFirestore.instance.collection('tarim_firma_hareketleri').doc(hareketId);

      // Bakiyeyi bulutta geri çek
      batch.update(firmaRef, {
        bakiyeAlani: FieldValue.increment(duzeltmeTutari),
        'son_guncelleme': FieldValue.serverTimestamp(),
      });

      // Hareket kaydını buluttan sil
      batch.delete(hareketRef);

      // Her şeyi tek seferde gönder
      await batch.commit();

      print("✅ Hareket silindi, bakiye ($bakiyeAlani) $duzeltmeTutari kadar düzeltildi.");

    } catch (e) {
      print("❌ Silme Hatası: $e");
      throw "İşlem geri alınırken hata oluştu: $e";
    }
  }

  Future<void> refreshCekler() async {
    try {
      print("🔄 Çek listesi tazeleniyor...");

      // getCekler zaten DatabaseHelper içinde hem Web hem Mobil uyumlu olmalı
      final veri = await getCekler();

      // Akış (Stream) kapalı değilse yeni veriyi gönder
      if (!_cekController.isClosed) {
        _cekController.add(veri);
        print("✅ Liste güncellendi: ${veri.length} adet çek bulundu.");
      }
    } catch (e) {
      print("❌ Liste tazelenirken hata oluştu: $e");

      // Hata durumunda boş liste göndererek ekranın takılı kalmasını önleyebilirsin
      if (!_cekController.isClosed) {
        _cekController.add([]);
      }
    }
  }

  Future<void> firmaHareketiGuncelle({
    required String hareketId,
    required String cariKod,
    required double eskiTutar,
    required double yeniTutar,
    required String tip,
  }) async {
    print("\n--- 📝 FİRMA HAREKETİ GÜNCELLEME (FARK HESABI) ---");

    // Aradaki farkı buluyoruz
    double fark = yeniTutar - eskiTutar;

    // Alım ise ALACAK, Satış ise BORÇ hanesine farkı yansıtacağız
    String bakiyeAlani = (tip.toUpperCase() == "ALIM") ? "alacak" : "borc";

    final db = await instance.database;
    final batch = FirebaseFirestore.instance.batch();
    String yeniTarih = DateFormat('dd.MM.yyyy').format(DateTime.now());

    try {
      // 1. SQLITE İŞLEMLERİ (Mobil ise)
      if (!kIsWeb) {
        await db.transaction((txn) async {
          // Hareketi güncelle
          await txn.update(
            'tarim_firma_hareketleri',
            {'tutar': yeniTutar, 'tarih': yeniTarih, 'is_synced': 0},
            where: 'firebase_id = ?',
            whereArgs: [hareketId],
          );

          // Bakiyeyi fark kadar yerelde güncelle
          await txn.rawUpdate(
            'UPDATE tarim_firmalari SET $bakiyeAlani = $bakiyeAlani + ? WHERE cari_kod = ?',
            [fark, cariKod],
          );
        });
      }

      // 2. FIREBASE İŞLEMLERİ (Her ikisi için)
      var firmaRef = FirebaseFirestore.instance.collection('tarim_firmalari').doc(cariKod);
      var hareketRef = FirebaseFirestore.instance.collection('tarim_firma_hareketleri').doc(hareketId);

      // Bakiyeyi bulutta fark kadar artır/azalt
      batch.update(firmaRef, {
        bakiyeAlani: FieldValue.increment(fark),
        'son_islem_tarihi': FieldValue.serverTimestamp(),
      });

      // Hareket kaydındaki tutarı bulutta güncelle
      batch.update(hareketRef, {
        'tutar': yeniTutar,
        'tarih': yeniTarih,
        'server_tarih': FieldValue.serverTimestamp(),
        'is_synced': 1,
      });

      // Hepsini tek seferde mühürle
      await batch.commit();

      // Yerelde "bulutla eşitlendi" işaretini çak
      if (!kIsWeb) {
        await db.update('tarim_firma_hareketleri', {'is_synced': 1},
            where: 'firebase_id = ?', whereArgs: [hareketId]);
      }

      print("✅ Güncelleme Başarılı: $bakiyeAlani hanesine $fark fark yansıtıldı.");

    } catch (e) {
      print("❌ Güncelleme Hatası: $e");
      throw "Hareket güncellenirken bir hata oluştu: $e";
    }
  }


  Future<void> stokAdetGuncelle(dynamic stokId, int yeniAdet, double birimFiyat, String firmaAdi) async {
    print("\n--- 📦 STOK VE BORÇ GÜNCELLEME BAŞLATILDI ---");

    int eskiAdet = 0;

    // --- 1. ADIM: ESKİ ADEDİ BUL VE FARKI HESAPLA ---
    if (kIsWeb) {
      // Web'de veriyi Firebase'den çekiyoruz
      var doc = await FirebaseFirestore.instance.collection('stoklar').doc(stokId.toString()).get();
      if (doc.exists) {
        eskiAdet = int.tryParse(doc.data()?['adet']?.toString() ?? "0") ?? 0;
      }
    } else {
      // Mobilde SQLite'dan çekiyoruz
      final db = await instance.database;
      final res = await db.query('stoklar', columns: ['adet'], where: 'id = ?', whereArgs: [stokId]);
      if (res.isNotEmpty) {
        eskiAdet = int.tryParse(res.first['adet'].toString()) ?? 0;
      }
    }

    int fark = yeniAdet - eskiAdet;
    double farkTutar = fark * birimFiyat;
    print("📝 Sayım Farkı: $fark adet | Borca Etkisi: $farkTutar TL");

    // --- 2. ADIM: GÜNCELLEME İŞLEMLERİ ---

    if (kIsWeb) {
      // --- WEB İÇİN: FIREBASE BATCH ---
      try {
        var batch = FirebaseFirestore.instance.batch();

        // Stok güncelle
        var stokRef = FirebaseFirestore.instance.collection('stoklar').doc(stokId.toString());
        batch.update(stokRef, {'adet': yeniAdet});

        // Firma borcunu güncelle (Firma adı doluysa)
        if (firmaAdi.isNotEmpty) {
          var firmaRef = FirebaseFirestore.instance.collection('tarim_firmalari').doc(firmaAdi);
          batch.update(firmaRef, {'borc': FieldValue.increment(farkTutar)});
        }

        await batch.commit();
        print("✅ Web: Stok ve Firma borcu bulutta güncellendi.");
      } catch (e) {
        print("❌ Web Güncelleme Hatası: $e");
      }
      return; // Web işlemi biter
    }

    // --- MOBİL İÇİN: SQLite + FIREBASE SENKRONU ---
    try {
      final db = await instance.database;

      // 1. Yerel SQLite Güncellemesi
      await db.update('stoklar', {'adet': yeniAdet}, where: 'id = ?', whereArgs: [stokId]);

      if (firmaAdi.isNotEmpty) {
        await db.rawUpdate('UPDATE tarim_firmalari SET borc = borc + ? WHERE ad = ?', [farkTutar, firmaAdi]);
      }

      // 2. Firebase Senkronu
      var batch = FirebaseFirestore.instance.batch();
      batch.update(FirebaseFirestore.instance.collection('stoklar').doc(stokId.toString()), {'adet': yeniAdet});

      if (firmaAdi.isNotEmpty) {
        batch.update(FirebaseFirestore.instance.collection('tarim_firmalari').doc(firmaAdi), {
          'borc': FieldValue.increment(farkTutar)
        });
      }

      await batch.commit();
      print("🚀 Mobil: Stok ve Borç her iki tarafta da güncellendi.");

    } catch (e) {
      print("❌ Mobil Güncelleme Hatası: $e");
    }
  }

  Future<dynamic> stokTaniminiIdIleSil(dynamic id) async {
    print("\n--- 🗑️ STOK TANIMI TAMAMEN SİLİNİYOR (ID: $id) ---");

    try {
      final db = await instance.database;

      // 1. TELEFONDAN KÖKTEN SİL (Update değil, Delete!)
      int res = await db.delete(
        'stok_tanimlari',
        where: 'id = ?',
        whereArgs: [id],
      );
      print("🚀 Mobil: Kayıt telefondan tamamen kazındı.");

      // 2. FIREBASE'DEN DE TEMİZLE (Hata verse de durma)
      try {
        // Not: ID'ler eşleşmediği için hata alıyordun, o yüzden try-catch içinde tutuyoruz.
        await FirebaseFirestore.instance
            .collection('stok_tanimlari')
            .doc(id.toString())
            .delete(); // update değil delete
        print("✅ Mobil: Bulut kaydı silindi.");
      } catch (fbError) {
        print("⚠️ Mobil: Bulutta döküman bulunamadı veya silinemedi, devam ediliyor.");
      }

      return res;
    } catch (e) {
      print("❌ Kritik Silme Hatası: $e");
      return 0;
    }
  }

  Future<int> aracGuncelle(dynamic id, Map<String, dynamic> data) async {
    print("\n--- 🚗 ARAÇ BİLGİSİ GÜNCELLENİYOR (ID: $id) ---");

    // --- WEB İÇİN: DOĞRUDAN FIREBASE GÜNCELLEME ---
    if (kIsWeb) {
      try {
        print("🌐 Web: Araç bilgileri bulutta güncelleniyor...");

        // Firestore koleksiyonun 'galeri' ise burası doğru
        await FirebaseFirestore.instance
            .collection('araclar')
            .doc(id.toString())
            .update(data);

        print("✅ Web: Araç başarıyla güncellendi.");
        return 1;
      } catch (e) {
        print("❌ Web Güncelleme Hatası: $e");
        return 0;
      }
    }

    // --- MOBİL İÇİN: SQLite + FIREBASE SENKRONU ---
    try {
      final db = await instance.database;

      // 1. Yerel SQLite Güncellemesi
      // HATA BURADAYDI: Tablo adını 'stoklar' (veya senin gerçek tablo adın neyse) yaptık.
      int res = await db.update(
          "stoklar",
          data,
          where: "id = ?",
          whereArgs: [id]
      );
      print("🚀 Mobil: Yerel tablo ('stoklar') güncellendi.");

      // 2. Firebase Senkronu
      try {
        await FirebaseFirestore.instance
            .collection('araclar')
            .doc(id.toString())
            .update(data);
        print("✅ Mobil: Firebase senkronu tamamlandı.");
      } catch (fbError) {
        print("⚠️ Mobil: Firebase güncellenemedi (İnternet?), yerelde kaldı: $fbError");
      }

      return res;
    } catch (e) {
      print("❌ Mobil Güncelleme Hatası: $e");
      return 0;
    }
  }
  Future<int> faturaSil(dynamic id) async {
    print("\n--- 📄 FATURA SİLİNİYOR (ID: $id) ---");

    // --- WEB İÇİN: DOĞRUDAN FIREBASE SİLME ---
    if (kIsWeb) {
      try {
        print("🌐 Web: Fatura buluttan siliniyor...");
        await FirebaseFirestore.instance
            .collection('faturalar')
            .doc(id.toString())
            .delete();

        print("✅ Web: Fatura başarıyla silindi.");
        return 1; // Başarılı işlem simülasyonu
      } catch (e) {
        print("❌ Web Fatura Silme Hatası: $e");
        return 0;
      }
    }

    // --- MOBİL İÇİN: SQLite + FIREBASE SENKRONU ---
    try {
      final db = await instance.database;

      // 1. Yerel SQLite'dan Sil
      int res = await db.delete('faturalar', where: 'id = ?', whereArgs: [id]);
      print("🚀 Mobil: Yerel kayıt silindi.");

      // 2. Firebase'den Sil
      try {
        await FirebaseFirestore.instance
            .collection('faturalar')
            .doc(id.toString())
            .delete();
        print("✅ Mobil: Firebase senkronu tamamlandı.");
      } catch (fbError) {
        print("⚠️ Mobil: Buluttan silinemedi (İnternet yok?), sonra senkron olacak.");
      }

      return res;
    } catch (e) {
      print("❌ Mobil Fatura Silme Hatası: $e");
      return 0;
    }
  }

  Future<void> faturaGorseliEkle(dynamic musteriId, String dosyaYolu) async {
    print("\n--- 📸 FATURA GÖRSELİ KAYDEDİLİYOR ---");

    // --- WEB İÇİN: ŞİMDİLİK SADECE LOG ATALIM ---
    // Web'de dosya yolları (path) Mobildeki gibi çalışmaz.
    // Web'de dosyalar genelde 'Blob' veya 'Uint8List' olarak işlenir.
    if (kIsWeb) {
      print("🌐 Web: Görsel yolu kaydedildi (Tarayıcıda dosya sistemi sınırlıdır): $dosyaYolu");
      // Web'de Firebase Storage kullanana kadar burayı boş geçebiliriz
      // veya tarayıcı hafızasına (IndexedDB) yazabiliriz.
      return;
    }

    // --- MOBİL İÇİN: SADECE SQLite KAYDI ---
    try {
      final db = await instance.database;

      await db.insert('faturalar', {
        'firma_id': musteriId,
        'dosya_yolu': dosyaYolu,
        'tarih': DateTime.now().toIso8601String(),
      });

      print("✅ Mobil: Fatura görseli yolu telefona kaydedildi.");

      /*
    🔥 NOT: Dediğin gibi Firebase kaydı yoruma alındı.
    İleride resmin kendisini (Bytes) Firebase Storage'a yüklemek istersen
    buraya o kodu ekleriz.
    */

    } catch (e) {
      print("❌ SQLite Kayıt Hatası: $e");
      rethrow;
    }
  }
  Future<int> faturaEkle(Map<String, dynamic> row) async {
    print("\n--- 🧾 YENİ FATURA KAYDEDİLİYOR ---");

    // --- WEB İÇİN: DOĞRUDAN FIREBASE KAYDI ---
    if (kIsWeb) {
      try {
        print("🌐 Web: Fatura buluta işleniyor...");

        // Firebase'e eklerken döküman referansını alıyoruz
        var ref = await FirebaseFirestore.instance.collection('faturalar').add({
          ...row,
          'olusturma_tarihi': FieldValue.serverTimestamp(), // Sunucu saati her zaman daha garantidir
        });

        print("✅ Web: Fatura Firebase'e eklendi (ID: ${ref.id})");
        return 1; // Başarılı simülasyonu
      } catch (e) {
        debugPrint("❌ Web Fatura Yazma Hatası: $e");
        return -1;
      }
    }

    // --- MOBİL İÇİN: SQLite + FIREBASE YEDEKLEME ---
    try {
      Database db = await instance.database;

      // 1. Yerel SQLite Kaydı
      int id = await db.insert('faturalar', row);
      print("🚀 Mobil: Fatura yerel veritabanına işlendi (ID: $id)");

      // 2. Firebase'e Yedekle (Geri planda)
      // ID'yi çakışmasın diye SQLite'dan gelen ID ile eşliyoruz
      FirebaseFirestore.instance.collection('faturalar').doc(id.toString()).set({
        ...row,
        'is_synced': 1,
        'yerel_id': id,
      }).catchError((e) => print("⚠️ Firebase Yedekleme Aksadı: $e"));

      return id;
    } catch (e) {
      debugPrint("❌ Mobil SQLite Fatura Yazma Hatası: $e");
      return -1;
    }
  }

  Future<List<Map<String, dynamic>>> firmaFaturalariniGetir(dynamic firmaId) async {
    print("\n--- 📂 FİRMA FATURALARI LİSTELENİYOR ---");
    String fId = firmaId.toString();

    // --- WEB İÇİN: FIREBASE SORGUSU ---
    if (kIsWeb) {
      try {
        print("🌐 Web: $fId ID'li firmanın faturaları buluttan çekiliyor...");

        var snapshot = await FirebaseFirestore.instance
            .collection('faturalar')
            .where('firma_id', isEqualTo: fId)
            .get();

        List<Map<String, dynamic>> faturalar = snapshot.docs.map((doc) {
          var data = doc.data();
          data['doc_id'] = doc.id; // Gerekirse silme/güncelleme için döküman ID'sini ekliyoruz
          return data;
        }).toList();

        // Web'de manuel sıralama (En yeni en üstte - Tarihe veya ID'ye göre)
        faturalar.sort((a, b) => (b['id'] ?? 0).toString().compareTo((a['id'] ?? 0).toString()));

        print("✅ Web: ${faturalar.length} adet fatura bulundu.");
        return faturalar;
      } catch (e) {
        print("❌ Web Fatura Çekme Hatası: $e");
        return [];
      }
    }

    // --- MOBİL İÇİN: SQLite SORGUSU ---
    try {
      final db = await instance.database;

      final List<Map<String, dynamic>> res = await db.query(
          'faturalar',
          where: 'firma_id = ?',
          whereArgs: [fId],
          orderBy: 'id DESC'
      );

      print("🚀 Mobil: SQLite'dan ${res.length} adet fatura getirildi.");
      return res;
    } catch (e) {
      print("❌ Mobil Fatura Çekme Hatası: $e");
      return [];
    }
  }

  Future<dynamic> eksperKaydiEkle(Map<String, dynamic> veri) async {
    print("\n--- 🔍 EKSPERTİZ KAYDI İŞLENİYOR ---");

    // --- WEB İÇİN: DOĞRUDAN FIREBASE KAYDI ---
    if (kIsWeb) {
      try {
        print("🌐 Web: Eksper raporu buluta işleniyor...");

        // Web'de dökümanı ekleyip referansını alıyoruz
        var ref = await FirebaseFirestore.instance.collection('eksper_kayitlari').add({
          ...veri,
          'kayit_tarihi': FieldValue.serverTimestamp(),
        });

        print("✅ Web: Eksper kaydı başarıyla oluşturuldu (Doc ID: ${ref.id})");
        return 1; // Başarılı dönüş simülasyonu
      } catch (e) {
        print("❌ Web Eksper Kayıt Hatası: $e");
        return 0;
      }
    }

    // --- MOBİL İÇİN: SQLite + FIREBASE SENKRONU ---
    try {
      final db = await instance.database;

      // 1. Yerel SQLite Kaydı
      int id = await db.insert('eksper_kayitlari', veri);
      print("🚀 Mobil: Eksper raporu yerel deftere işlendi (ID: $id)");

      // 2. Firebase Yedekleme
      try {
        await FirebaseFirestore.instance.collection('eksper_kayitlari').doc(id.toString()).set({
          ...veri,
          'kayit_tarihi': FieldValue.serverTimestamp(),
          'yerel_id': id,
        });
        print("✅ Mobil: Eksper raporu buluta yedeklendi.");
      } catch (fbError) {
        print("⚠️ Mobil: Firebase yedekleme o an yapılamadı (İnternet?), yerelde güvende.");
      }

      return id;
    } catch (e) {
      print("❌ Mobil Eksper Kayıt Hatası: $e");
      return 0;
    }
  }

  Future<List<Map<String, dynamic>>> eksperKayitlariniGetir(dynamic aracId) async {
    print("\n--- 🔍 ARAÇ EKSPERTİZ GEÇMİŞİ SORGULANIYOR (ID: $aracId) ---");

    // --- WEB İÇİN: DOĞRUDAN FIREBASE SORGUSU ---
    if (kIsWeb) {
      try {
        print("🌐 Web: Eksper kayıtları buluttan çekiliyor...");

        final snapshot = await FirebaseFirestore.instance
            .collection('eksper_kayitlari')
            .where('arac_id', isEqualTo: aracId)
            .get();

        if (snapshot.docs.isNotEmpty) {
          List<Map<String, dynamic>> liste = snapshot.docs.map((doc) {
            var data = doc.data();
            data['doc_id'] = doc.id; // Düzenleme/Silme için lazım olur
            return data;
          }).toList();

          // Tarihe göre sıralama (En yeni en üstte)
          liste.sort((a, b) => (b['id'] ?? 0).toString().compareTo((a['id'] ?? 0).toString()));

          print("✅ Web: Bulutta ${liste.length} adet kayıt bulundu.");
          return liste;
        }
      } catch (e) {
        print("❌ Web Eksper Liste Hatası: $e");
      }
      return [];
    }

    // --- MOBİL İÇİN: ÖNCE FIREBASE (GÜNCEL VERİ), SONRA SQLite ---
    try {
      print("📱 Mobil: Güncel raporlar için Firebase kontrol ediliyor...");
      final snapshot = await FirebaseFirestore.instance
          .collection('eksper_kayitlari')
          .where('arac_id', isEqualTo: aracId)
          .get();

      if (snapshot.docs.isNotEmpty) {
        print("✅ Mobil: Güncel raporlar buluttan getirildi.");
        return snapshot.docs.map((doc) => doc.data()).toList();
      }
    } catch (e) {
      print("⚠️ Mobil: Firebase'e ulaşılamadı, yerel hafızaya bakılıyor...");
    }

    // Firebase boşsa veya hata verdiyse yerel SQLite'a bak
    try {
      final db = await instance.database;
      final List<Map<String, dynamic>> res = await db.query(
          'eksper_kayitlari',
          where: 'arac_id = ?',
          whereArgs: [aracId],
          orderBy: "id DESC"
      );
      print("🚀 Mobil: Yerel veritabanından ${res.length} kayıt getirildi.");
      return res;
    } catch (e) {
      print("❌ Mobil SQLite Liste Hatası: $e");
      return [];
    }
  }


  Future<dynamic> bakimEkle(Map<String, dynamic> veri) async {
    print("\n--- 🛠️ BAKIM KAYDI İŞLENİYOR ---");

    // --- WEB İÇİN: DOĞRUDAN FIREBASE KAYDI ---
    if (kIsWeb) {
      try {
        print("🌐 Web: Bakım kaydı buluta işleniyor...");

        // Firebase'de yeni bir doküman oluştur
        var ref = await FirebaseFirestore.instance.collection('bakimlar').add({
          ...veri,
          'islem_zamani': FieldValue.serverTimestamp(),
        });

        print("✅ Web: Bakım kaydı başarıyla oluşturuldu (ID: ${ref.id})");
        return 1; // Başarılı dönüş simülasyonu
      } catch (e) {
        print("❌ Web Bakım Kayıt Hatası: $e");
        return 0;
      }
    }

    // --- MOBİL İÇİN: SQLite (HAYALET KAYIT DESTEKLİ) + FIREBASE ---
    try {
      final db = await instance.database;

      // 1. ADIM: FOREIGN KEY HATASINI ÖNLEME (Hayalet Kayıt)
      // SQLite'da araç yoksa hata vermesin diye boş bir araç şablonu atıyoruz.
      await db.rawInsert('''
      INSERT OR IGNORE INTO araclar (id, firebase_id, plaka) 
      VALUES (?, ?, ?)
    ''', [
        veri['arac_id'],
        veri['arac_id'].toString(),
        "00 GECICI 00"
      ]);

      // 2. ADIM: BAKIMI YEREL KAYDET
      int id = await db.insert('bakimlar', veri);
      print("🚀 Mobil: Bakım yerel deftere işlendi (ID: $id)");

      // 3. ADIM: FIREBASE'E YEDEKLE
      try {
        await FirebaseFirestore.instance.collection('bakimlar').doc(id.toString()).set({
          ...veri,
          'id': id,
          'islem_zamani': FieldValue.serverTimestamp(),
        });
        print("✅ Mobil: Kayıt buluta gönderildi.");
      } catch (fbError) {
        print("⚠️ Mobil: Bulut senkronu aksadı (İnternet?), yerel kayıt tamam: $fbError");
      }

      return id;
    } catch (e) {
      print("❌ Mobil Bakım Kayıt Hatası: $e");
      return 0;
    }
  }


  Future<List<Map<String, dynamic>>> bakimlariGetir(dynamic aracId) async {
    print("\n--- 🛠️ BAKIM GEÇMİŞİ SORGULANIYOR (Arac ID: $aracId) ---");

    // --- WEB İÇİN: DOĞRUDAN FIREBASE SORGUSU ---
    if (kIsWeb) {
      try {
        print("🌐 Web: Bakım kayıtları buluttan çekiliyor...");

        final snapshot = await FirebaseFirestore.instance
            .collection('bakimlar')
            .where('arac_id', isEqualTo: aracId)
            .get(); // İndeks hatası riskine karşı önce düz çekiyoruz

        if (snapshot.docs.isNotEmpty) {
          List<Map<String, dynamic>> bakimlar = snapshot.docs.map((doc) {
            final data = doc.data();
            return {
              ...data,
              'firebase_id': doc.id,
            };
          }).toList();

          // Manuel Sıralama (En yeni ID en üstte)
          bakimlar.sort((a, b) => (b['id'] ?? 0).toString().compareTo((a['id'] ?? 0).toString()));

          print("✅ Web: Bulutta ${bakimlar.length} adet bakım kaydı bulundu.");
          return bakimlar;
        }
      } catch (e) {
        print("❌ Web Bakım Liste Hatası: $e");
      }
      return [];
    }

    // --- MOBİL İÇİN: ÖNCE FIREBASE, SONRA SQLite ---
    try {
      print("📱 Mobil: Güncel bakımlar için Firebase sorgulanıyor...");
      final snapshot = await FirebaseFirestore.instance
          .collection('bakimlar')
          .where('arac_id', isEqualTo: aracId)
          .orderBy('id', descending: true)
          .get();

      if (snapshot.docs.isNotEmpty) {
        print("✅ Mobil: Güncel veriler buluttan getirildi.");
        return snapshot.docs.map((doc) {
          final data = doc.data();
          return { ...data, 'firebase_id': doc.id };
        }).toList();
      }
    } catch (e) {
      print("⚠️ Mobil: Firebase sorgusu yapılamadı (İndeks eksik veya internet yok): $e");
    }

    // Firebase boşsa veya hata verdiyse yerel SQLite'a bak
    try {
      final db = await instance.database;
      final yerelVeri = await db.query(
          'bakimlar',
          where: 'arac_id = ?',
          whereArgs: [aracId],
          orderBy: "id DESC"
      );

      print("🚀 Mobil: Yerel veritabanından ${yerelVeri.length} kayıt getirildi.");
      return yerelVeri;
    } catch (e) {
      print("❌ Mobil SQLite Bakım Liste Hatası: $e");
      return [];
    }
  }

  Future<int> eksperKaydiGuncelle(dynamic id, Map<String, dynamic> veri) async {
    print("\n--- 🔍 EKSPER KAYDI GÜNCELLENİYOR (ID: $id) ---");

    // --- WEB İÇİN: DOĞRUDAN FIREBASE GÜNCELLEME ---
    if (kIsWeb) {
      try {
        print("🌐 Web: Eksper raporu bulutta güncelleniyor...");

        await FirebaseFirestore.instance
            .collection('eksper_kayitlari')
            .doc(id.toString())
            .update(veri);

        print("✅ Web: Güncelleme başarıyla tamamlandı.");
        return 1;
      } catch (e) {
        print("❌ Web Eksper Güncelleme Hatası: $e");
        return 0;
      }
    }

    // --- MOBİL İÇİN: SQLite + FIREBASE SENKRONU ---
    try {
      final db = await instance.database;

      // 1. Yerel SQLite Güncellemesi
      int res = await db.update(
          'eksper_kayitlari',
          veri,
          where: 'id = ?',
          whereArgs: [id]
      );
      print("🚀 Mobil: Yerel kayıt güncellendi.");

      // 2. Firebase Senkronu
      try {
        await FirebaseFirestore.instance
            .collection('eksper_kayitlari')
            .doc(id.toString())
            .update(veri);
        print("✅ Mobil: Firebase senkronu tamamlandı.");
      } catch (fbError) {
        print("⚠️ Mobil: Firebase güncellenemedi (İnternet?), yerelde kaldı: $fbError");
      }

      return res;
    } catch (e) {
      print("❌ Mobil Eksper Güncelleme Hatası: $e");
      return 0;
    }
  }

  Future<int> eksperKaydiSil(dynamic id) async {
    print("\n--- 🗑️ EKSPERTİZ KAYDI SİLİNİYOR (ID: $id) ---");

    // --- WEB İÇİN: DOĞRUDAN FIREBASE SİLME ---
    if (kIsWeb) {
      try {
        await FirebaseFirestore.instance
            .collection('eksper_kayitlari')
            .doc(id.toString())
            .delete();
        print("✅ Web: Eksper raporu buluttan silindi.");
        return 1;
      } catch (e) {
        print("❌ Web Eksper Silme Hatası: $e");
        return 0;
      }
    }

    // --- MOBİL İÇİN: SQLite + FIREBASE SENKRONU ---
    try {
      final db = await instance.database;
      int res = await db.delete('eksper_kayitlari', where: 'id = ?', whereArgs: [id]);

      try {
        await FirebaseFirestore.instance
            .collection('eksper_kayitlari')
            .doc(id.toString())
            .delete();
        print("✅ Mobil: Eksper raporu her iki taraftan silindi.");
      } catch (e) {
        print("⚠️ Mobil: Bulut silme başarısız (İnternet?), yerel silindi.");
      }
      return res;
    } catch (e) {
      print("❌ Mobil Eksper Silme Hatası: $e");
      return 0;
    }
  }
  Future<int> bakimSil(dynamic id) async {
    print("\n--- 🗑️ BAKIM KAYDI SİLİNİYOR (ID: $id) ---");

    // --- WEB İÇİN: DOĞRUDAN FIREBASE SİLME ---
    if (kIsWeb) {
      try {
        await FirebaseFirestore.instance
            .collection('bakimlar')
            .doc(id.toString())
            .delete();
        print("✅ Web: Bakım kaydı buluttan silindi.");
        return 1;
      } catch (e) {
        print("❌ Web Bakım Silme Hatası: $e");
        return 0;
      }
    }

    // --- MOBİL İÇİN: SQLite + FIREBASE SENKRONU ---
    try {
      final db = await instance.database;
      int res = await db.delete('bakimlar', where: 'id = ?', whereArgs: [id]);

      try {
        await FirebaseFirestore.instance
            .collection('bakimlar')
            .doc(id.toString())
            .delete();
        print("✅ Mobil: Bakım kaydı her iki taraftan silindi.");
      } catch (e) {
        print("⚠️ Mobil: Buluttan silinemedi, yerel kayıt temizlendi.");
      }
      return res;
    } catch (e) {
      print("❌ Mobil Bakım Silme Hatası: $e");
      return 0;
    }
  }


  Future<List<Map<String, dynamic>>> satisGetir(dynamic aracId) async {
    print("\n--- 💰 SATIŞ KAYDI SORGULANIYOR (Arac ID: $aracId) ---");

    // --- WEB İÇİN: DOĞRUDAN FIREBASE SORGUSU ---
    if (kIsWeb) {
      try {
        print("🌐 Web: Satış bilgisi buluttan çekiliyor...");

        final snapshot = await FirebaseFirestore.instance
            .collection('satislar')
            .where('arac_id', isEqualTo: aracId)
            .get();

        if (snapshot.docs.isNotEmpty) {
          print("✅ Web: Satış kaydı bulundu.");
          return snapshot.docs.map((doc) => {
            'id': doc.id, // Web'de Firestore döküman ID'sini kullanıyoruz
            ...doc.data(),
          }).toList();
        }
      } catch (e) {
        print("❌ Web satisGetir Hatası: $e");
      }
      return [];
    }

    // --- MOBİL İÇİN: ÖNCE FIREBASE, SONRA SQLite ---
    try {
      print("📱 Mobil: Güncel satış verisi için Firebase kontrol ediliyor...");
      final snapshot = await FirebaseFirestore.instance
          .collection('satislar')
          .where('arac_id', isEqualTo: aracId)
          .get();

      if (snapshot.docs.isNotEmpty) {
        print("✅ Mobil: Satış verisi buluttan getirildi.");
        return snapshot.docs.map((doc) => {
          'firebase_id': doc.id,
          ...doc.data(),
        }).toList();
      }
    } catch (e) {
      print("⚠️ Mobil: Firebase'e ulaşılamadı (İnternet?), yerel hafızaya bakılıyor: $e");
    }

    // Firebase boşsa veya hata verdiyse yerel SQLite'a bak
    try {
      final db = await instance.database;
      final res = await db.query(
          "satislar",
          where: "arac_id = ?",
          whereArgs: [aracId]
      );

      print("🚀 Mobil: Yerel veritabanından ${res.length} kayıt getirildi.");
      return res;
    } catch (e) {
      print("❌ Mobil SQLite satisGetir Hatası: $e");
      return [];
    }
  }

  Future<void> ciftciEkle(Map<String, dynamic> ciftciVerisi) async {
    print("\n--- 👨‍🌾 ÇİFTÇİ KAYDI BAŞLATILDI ---");

    try {
      // 1. Veriyi hazırla
      String tcNo = ciftciVerisi['tc'].toString();

      // Ortak veri haritası (Tekrar yazmamak için)
      Map<String, dynamic> firestoreVeri = {
        'tc': tcNo,
        'ad_soyad': ciftciVerisi['ad_soyad'],
        'telefon': ciftciVerisi['telefon'],
        'adres': ciftciVerisi['adres'],
        'notlar': ciftciVerisi['notlar'],
        'sube': "TEFENNİ",
        'firebase_id': tcNo,
        'kayit_tarihi': FieldValue.serverTimestamp(),
      };

      // --- 2. FIREBASE KAYIT (TC'yi Doküman ID yaparak mükerrerliği önler) ---
      // Bu kısım hem Web'de hem Mobilde çalışır.
      await FirebaseFirestore.instance
          .collection('bicer_musterileri')
          .doc(tcNo)
          .set(firestoreVeri);

      print("✅ Firebase: $tcNo kayıt/güncelleme başarılı.");

      // --- 3. SQL KAYIT (Sadece Mobil Cihazlarda) ---
      if (!kIsWeb) {
        try {
          final db = await instance.database;
          await db.insert(
            'bicer_musterileri',
            {
              'tc': tcNo,
              'ad_soyad': ciftciVerisi['ad_soyad'],
              'telefon': ciftciVerisi['telefon'],
              'adres': ciftciVerisi['adres'],
              'notlar': ciftciVerisi['notlar'],
              'is_synced': 1,
              'sube': "TEFENNİ",
              'firebase_id': tcNo,
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
          print("✅ SQLite: Yerel kayıt güncellendi.");
        } catch (sqlError) {
          print("⚠️ SQLite Kayıt Hatası (Yine de Firebase yüklendi): $sqlError");
        }
      } else {
        print("🌐 Web: SQLite atlandı, sadece bulut kaydı yapıldı.");
      }

    } catch (e) {
      print("❌ HATA OLUŞTU: $e");
    }
  }

  Future<List<Map<String, dynamic>>> ciftciListesiGetir() async {
    print("\n--- 👨‍🌾 ÇİFTÇİ LİSTESİ ÇEKİLİYOR ---");

    // --- WEB İÇİN: DOĞRUDAN FIREBASE SORGUSU ---
    if (kIsWeb) {
      try {
        print("🌐 Web: Çiftçi listesi buluttan çekiliyor...");
        final snapshot = await FirebaseFirestore.instance
            .collection('bicer_musterileri')
            .get();

        if (snapshot.docs.isNotEmpty) {
          var liste = snapshot.docs.map((doc) {
            var data = doc.data();
            return {
              'id': doc.id, // Dismissible veya Liste anahtarı için TC veya ID
              'ad_soyad': data['ad_soyad'] ?? "İsimsiz",
              'telefon': data['telefon'] ?? "Telefon Yok",
              'adres': data['adres'] ?? "",
              'notlar': data['notlar'] ?? "",
              'firebase_id': doc.id,
            };
          }).toList();

          // İsim sırasına göre dizelim
          liste.sort((a, b) => a['ad_soyad'].toString().compareTo(b['ad_soyad'].toString()));

          print("✅ Web: ${liste.length} çiftçi bulundu.");
          return liste;
        }
        return [];
      } catch (e) {
        print("❌ Web Çiftçi Listesi Hatası: $e");
        return [];
      }
    }

    // --- MOBİL İÇİN: ÖNCE BULUT, İNTERNET YOKSA YEREL ---
    try {
      print("📱 Mobil: Güncel liste için Firebase kontrol ediliyor...");
      final snapshot = await FirebaseFirestore.instance
          .collection('bicer_musterileri')
          .get();

      if (snapshot.docs.isNotEmpty) {
        var liste = snapshot.docs.map((doc) => doc.data()).toList();
        liste.sort((a, b) => a['ad_soyad'].toString().compareTo(b['ad_soyad'].toString()));
        print("✅ Mobil: Güncel liste buluttan getirildi.");
        return liste;
      }
    } catch (e) {
      print("⚠️ Mobil: Firebase'e ulaşılamadı, SQLite'a bakılıyor: $e");
    }

    // Firebase'de veri yoksa veya internet çekmiyorsa SQLite'dan getir
    try {
      final db = await instance.database;
      final res = await db.query('bicer_musterileri', orderBy: "ad_soyad ASC");
      print("🚀 Mobil: Yerel veritabanından ${res.length} çiftçi getirildi.");
      return res;
    } catch (e) {
      print("❌ Mobil SQLite Çiftçi Liste Hatası: $e");
      return [];
    }
  }

  Future<int> ciftciGuncelle(dynamic id, Map<String, dynamic> veri) async {
    print("\n--- 👨‍🌾 ÇİFTÇİ BİLGİSİ GÜNCELLENİYOR (ID: $id) ---");

    // --- WEB İÇİN: DOĞRUDAN FIREBASE GÜNCELLEME ---
    if (kIsWeb) {
      try {
        print("🌐 Web: Çiftçi bilgileri bulutta güncelleniyor...");

        await FirebaseFirestore.instance
            .collection('bicer_musterileri')
            .doc(id.toString())
            .update({
          ...veri,
          'son_guncelleme': FieldValue.serverTimestamp(),
        });

        print("✅ Web: Güncelleme başarıyla tamamlandı.");
        return 1;
      } catch (e) {
        print("❌ Web Çiftçi Güncelleme Hatası: $e");
        return 0;
      }
    }

    // --- MOBİL İÇİN: SQLite + FIREBASE SENKRONU ---
    try {
      final db = await instance.database;

      // 1. Yerel SQLite Güncellemesi
      int res = await db.update(
          'bicer_musterileri',
          veri,
          where: 'id = ?',
          whereArgs: [id]
      );
      print("🚀 Mobil: Yerel kayıt güncellendi.");

      // 2. Firebase Senkronu
      try {
        await FirebaseFirestore.instance
            .collection('bicer_musterileri')
            .doc(id.toString())
            .update({
          ...veri,
          'son_guncelleme': FieldValue.serverTimestamp(),
        });
        print("✅ Mobil: Firebase senkronu tamamlandı.");
      } catch (fbError) {
        print("⚠️ Mobil: Firebase güncellenemedi (İnternet?), yerelde kaldı: $fbError");
      }

      return res;
    } catch (e) {
      print("❌ Mobil Çiftçi Güncelleme Hatası: $e");
      return 0;
    }
  }


  Future<int> ciftciSil(dynamic id) async {
    print("\n--- 🗑️ ÇİFTÇİ KAYDI SİLİNİYOR (ID: $id) ---");

    // --- WEB İÇİN: DOĞRUDAN FIREBASE SİLME ---
    if (kIsWeb) {
      try {
        print("🌐 Web: Çiftçi kaydı buluttan siliniyor...");
        await FirebaseFirestore.instance
            .collection('bicer_musterileri')
            .doc(id.toString())
            .delete();

        print("✅ Web: Silme işlemi başarılı.");
        return 1; // Başarılı dönüş simülasyonu
      } catch (e) {
        print("❌ Web Çiftçi Silme Hatası: $e");
        return 0;
      }
    }

    // --- MOBİL İÇİN: SQLite + FIREBASE SENKRONU ---
    try {
      final db = await instance.database;

      // 1. Yerel SQLite'dan sil
      int res = await db.delete(
          'bicer_musterileri',
          where: 'id = ?',
          whereArgs: [id]
      );
      print("🚀 Mobil: Yerel kayıt temizlendi.");

      // 2. Firebase'den sil
      try {
        await FirebaseFirestore.instance
            .collection('bicer_musterileri')
            .doc(id.toString())
            .delete();
        print("✅ Mobil: Bulut senkronu tamamlandı.");
      } catch (fbError) {
        print("⚠️ Mobil: Buluttan silinemedi (İnternet?), yerelde işlem tamam: $fbError");
      }

      return res;
    } catch (e) {
      print("❌ Mobil Çiftçi Silme Hatası: $e");
      return 0;
    }
  }

  Future<int> bicerEkle(Map<String, dynamic> row) async {
    print("\n--- 🚜 BİÇERDÖVER SİSTEME KAYDEDİLİYOR ---");

    // --- WEB İÇİN: DOĞRUDAN FIREBASE KAYDI ---
    if (kIsWeb) {
      try {
        print("🌐 Web: Makine bilgileri buluta işleniyor...");

        // Eğer row içinde bir 'id' varsa onu doküman ID'si yapalım (Conflict Replace mantığı için)
        String docId = row['id']?.toString() ?? DateTime.now().millisecondsSinceEpoch.toString();

        await FirebaseFirestore.instance
            .collection('bicerler')
            .doc(docId)
            .set({
          ...row,
          'son_guncelleme': FieldValue.serverTimestamp(),
        });

        print("✅ Web: Makine Firebase'e eklendi/güncellendi.");
        return 1;
      } catch (e) {
        print("❌ Web Biçer Kayıt Hatası: $e");
        return -1;
      }
    }

    // --- MOBİL İÇİN: SQLite + FIREBASE YEDEKLEME ---
    try {
      Database db = await instance.database;

      // 1. Yerel SQLite Kaydı (Replace algoritmasıyla)
      int id = await db.insert(
          'bicerler',
          row,
          conflictAlgorithm: ConflictAlgorithm.replace
      );
      print("🚀 Mobil: Makine yerel veritabanına işlendi (ID: $id)");

      // 2. Firebase Yedekleme (Arka planda)
      FirebaseFirestore.instance
          .collection('bicerler')
          .doc(id.toString())
          .set({
        ...row,
        'is_synced': 1,
        'yerel_id': id,
      }).catchError((e) => print("⚠️ Firebase Yedekleme Aksadı: $e"));

      return id;
    } catch (e) {
      print("❌ Mobil SQLite Biçer Yazma Hatası: $e");
      return -1;
    }
  }

  Future<List<Map<String, dynamic>>> bicerListesi() async {
    print("\n--- 🚜 MAKİNE PARKURU LİSTELENİYOR ---");

    // --- WEB İÇİN: DOĞRUDAN FIREBASE SORGUSU ---
    if (kIsWeb) {
      try {
        print("🌐 Web: Makine listesi buluttan çekiliyor...");
        final snapshot = await FirebaseFirestore.instance
            .collection('bicerler')
            .get(); // Önce düz çekiyoruz (Index hatasını önlemek için)

        if (snapshot.docs.isNotEmpty) {
          var liste = snapshot.docs.map((doc) => {
            'id_firebase': doc.id,
            ...doc.data(),
          }).toList();

          // Dart tarafında ID'ye göre azalan sıralama (En yeni en üstte)
          liste.sort((a, b) => (b['id'] ?? 0).toString().compareTo((a['id'] ?? 0).toString()));

          print("✅ Web: Bulutta ${liste.length} makine bulundu.");
          return liste;
        }
      } catch (e) {
        print("❌ Web Biçer Listesi Hatası: $e");
      }
      return [];
    }

    // --- MOBİL İÇİN: ÖNCE FIREBASE, SONRA SQLite ---
    try {
      print("📱 Mobil: Güncel makine parkuru için Firebase kontrol ediliyor...");
      final snapshot = await FirebaseFirestore.instance
          .collection('bicerler')
          .orderBy('id', descending: true)
          .get();

      if (snapshot.docs.isNotEmpty) {
        print("✅ Mobil: Güncel liste buluttan getirildi.");
        return snapshot.docs.map((doc) => {
          'id_firebase': doc.id,
          ...doc.data(),
        }).toList();
      }
    } catch (e) {
      print("⚠️ Mobil: Firebase'e ulaşılamadı (İnternet?), yerel hafızaya bakılıyor: $e");
    }

    // Firebase boşsa veya hata verdiyse yerel SQLite'a bak
    try {
      final db = await instance.database;
      final res = await db.query("bicerler", orderBy: "id DESC");
      print("🚀 Mobil: Yerel veritabanından ${res.length} makine getirildi.");
      return res;
    } catch (e) {
      print("❌ Mobil SQLite Biçer Listesi Hatası: $e");
      return [];
    }
  }

  Future<int> bicerSil(dynamic id) async {
    print("\n--- 🚜 BİÇERDÖVER VE BAĞLI KAYITLAR SİLİNİYOR (ID: $id) ---");

    // --- WEB İÇİN: FIREBASE ZİNCİRLEME SİLME ---
    if (kIsWeb) {
      try {
        print("🌐 Web: Makine ve bağlı tüm kayıtlar buluttan temizleniyor...");

        // 1. Bağlı bakımları sil
        var bakimlar = await FirebaseFirestore.instance
            .collection('bicer_bakimlar')
            .where('makine_id', isEqualTo: id)
            .get();
        for (var doc in bakimlar.docs) { await doc.reference.delete(); }

        // 2. Bağlı masrafları sil
        var masraflar = await FirebaseFirestore.instance
            .collection('masraflar')
            .where('makine_id', isEqualTo: id)
            .get();
        for (var doc in masraflar.docs) { await doc.reference.delete(); }

        // 3. Ana makine kaydını sil
        await FirebaseFirestore.instance
            .collection('bicerler')
            .doc(id.toString())
            .delete();

        print("✅ Web: Temizlik tamamlandı.");
        return 1;
      } catch (e) {
        print("❌ Web Silme Hatası: $e");
        return 0;
      }
    }

    // --- MOBİL İÇİN: SQLite TEMİZLİĞİ ---
    try {
      final db = await instance.database;

      // 1. ADIM: Bağlı verileri temizle
      try {
        await db.delete('bicer_bakimlar', where: 'makine_id = ?', whereArgs: [id]);
      } catch (e) {
        debugPrint("⚠️ bicer_bakimlar atlandı.");
      }

      try {
        await db.delete('masraflar', where: 'makine_id = ?', whereArgs: [id]);
      } catch (e) {
        debugPrint("⚠️ masraflar atlandı.");
      }

      // 2. ADIM: Makineyi ana tablodan sil
      int res = await db.delete(
        'bicerler',
        where: 'id = ?',
        whereArgs: [id],
      );

      // 3. ADIM: Firebase'den de silmeyi dene (Opsiyonel Senkron)
      FirebaseFirestore.instance
          .collection('bicerler')
          .doc(id.toString())
          .delete()
          .catchError((e) => print("Bulut silme ertelendi: $e"));

      print("🚀 Mobil: Makine ve bağlı kayıtlar yerelden silindi.");
      return res;
    } catch (e) {
      print("❌ Mobil Silme Hatası: $e");
      return 0;
    }
  }



  Future<int> bicerGuncelle(dynamic id, Map<String, dynamic> data) async {
    print("\n--- 🚜 MAKİNE BİLGİLERİ GÜNCELLENİYOR (ID: $id) ---");

    // --- WEB İÇİN: DOĞRUDAN FIREBASE GÜNCELLEME ---
    if (kIsWeb) {
      try {
        print("🌐 Web: Makine bilgileri bulutta güncelleniyor...");

        await FirebaseFirestore.instance
            .collection('bicerler')
            .doc(id.toString())
            .update({
          ...data,
          'son_guncelleme': FieldValue.serverTimestamp(),
        });

        print("✅ Web: Güncelleme başarıyla tamamlandı.");
        return 1;
      } catch (e) {
        print("❌ Web Biçer Güncelleme Hatası: $e");
        return 0;
      }
    }

    // --- MOBİL İÇİN: SQLite + FIREBASE SENKRONU ---
    try {
      final db = await instance.database;

      // 1. Yerel SQLite Güncellemesi
      int res = await db.update(
          "bicerler",
          data,
          where: "id = ?",
          whereArgs: [id]
      );
      print("🚀 Mobil: Yerel kayıt güncellendi.");

      // 2. Firebase Senkronu
      try {
        await FirebaseFirestore.instance
            .collection('bicerler')
            .doc(id.toString())
            .update({
          ...data,
          'son_guncelleme': FieldValue.serverTimestamp(),
        });
        print("✅ Mobil: Firebase senkronu tamamlandı.");
      } catch (fbError) {
        print("⚠️ Mobil: Firebase o an güncellenemedi (İnternet?), yerelde işlem tamam: $fbError");
      }

      return res;
    } catch (e) {
      print("❌ Mobil Biçer Güncelleme Hatası: $e");
      return 0;
    }
  }

  Future<dynamic> bicerIsEkle(Map<String, dynamic> veri) async {
    print("\n--- 🌾 SADECE HASAT KAYDI YAPILIYOR ---");

    if (kIsWeb) {
      var ref = await FirebaseFirestore.instance.collection('bicer_isleri').add(veri);
      return ref.id;
    }

    final db = await instance.database;
    int id = await db.insert('bicer_isleri', veri);

    // BURADAKİ bicerHareketEkle KISMINI SİLDİK!
    // Çünkü hareketleri Dialog içinden kontrollü ekleyeceğiz.

    return id;
  }

  // Bir hasat işi silindiğinde, ona bağlı tüm hareketleri (ekstre kayıtlarını) temizler
  Future<int> bicerHareketleriniSil(dynamic isId) async {
    final db = await instance.database; // Veritabanı bağlantısını al

    print("🧹 Hareketler temizleniyor. İş ID: $isId");

    return await db.delete(
      'bicermusteri_hareketleri', // Silinecek tablo adı
      where: 'is_id = ?',        // Hangi sütuna göre silinecek
      whereArgs: [isId],         // Hangi ID'ye sahip olanlar silinecek
    );
  }

  Future<List<Map<String, dynamic>>> bicerIsleriGetir(String sezon) async {
    print("\n--- 🌾 $sezon SEZONU HASAT KAYITLARI SORGULANIYOR ---");

    // --- WEB İÇİN: DOĞRUDAN FIREBASE SORGUSU ---
    if (kIsWeb) {
      try {
        print("🌐 Web: $sezon sezonu verileri buluttan çekiliyor...");
        final snapshot = await FirebaseFirestore.instance
            .collection('bicer_isleri')
            .where('sezon', isEqualTo: sezon)
            .get();

        if (snapshot.docs.isNotEmpty) {
          var liste = snapshot.docs.map((doc) => {
            'id_firebase': doc.id,
            ...doc.data(),
          }).toList();

          // En son yapılan iş en üstte görünsün (Tarihe göre sıralama)
          liste.sort((a, b) => (b['is_kayit_tarihi']?.toString() ?? "")
              .compareTo(a['is_kayit_tarihi']?.toString() ?? ""));

          print("✅ Web: Bulutta ${liste.length} iş kaydı bulundu.");
          return liste;
        }
      } catch (e) {
        print("❌ Web Biçer İş Listesi Hatası: $e");
      }
      return [];
    }

    // --- MOBİL İÇİN: ÖNCE FIREBASE, SONRA SQLite ---
    try {
      print("📱 Mobil: $sezon sezonu güncel verileri için Firebase kontrol ediliyor...");
      final snapshot = await FirebaseFirestore.instance
          .collection('bicer_isleri')
          .where('sezon', isEqualTo: sezon)
          .get();

      if (snapshot.docs.isNotEmpty) {
        print("✅ Mobil: Güncel liste buluttan getirildi.");
        return snapshot.docs.map((doc) => {
          'id_firebase': doc.id,
          ...doc.data(),
        }).toList();
      }
    } catch (e) {
      print("⚠️ Mobil: Firebase'e ulaşılamadı (İnternet?), yerel hafızaya bakılıyor: $e");
    }

    // Firebase boşsa veya hata verdiyse yerel SQLite'a bak
    try {
      final db = await instance.database;
      final res = await db.query(
          'bicer_isleri',
          where: 'sezon = ?',
          whereArgs: [sezon],
          orderBy: "id DESC" // En son girilen iş en üstte
      );

      print("🚀 Mobil: Yerel veritabanından ${res.length} iş kaydı getirildi.");
      return res;
    } catch (e) {
      print("❌ Mobil SQLite İş Listesi Hatası: $e");
      return [];
    }
  }

  Future<int> bicerBakimSil(dynamic id) async {
    print("\n--- 🔧 BİÇER BAKIM KAYDI SİLİNİYOR (ID: $id) ---");

    // --- WEB İÇİN: DOĞRUDAN FIREBASE SİLME ---
    if (kIsWeb) {
      try {
        print("🌐 Web: Bakım kaydı buluttan siliniyor...");
        await FirebaseFirestore.instance
            .collection('bicer_bakimlar')
            .doc(id.toString())
            .delete();

        print("✅ Web: Silme işlemi başarıyla tamamlandı.");
        return 1;
      } catch (e) {
        print("❌ Web Bakım Silme Hatası: $e");
        return 0;
      }
    }

    // --- MOBİL İÇİN: SQLite + FIREBASE SENKRONU ---
    try {
      final db = await instance.database;

      // 1. Yerel SQLite'dan sil
      int result = await db.delete(
          'bicer_bakimlar',
          where: 'id = ?',
          whereArgs: [id]
      );
      print("🚀 Mobil: Yerel kayıt silindi.");

      // 2. Firestore'dan sil (await kullanarak işlemin bittiğinden emin oluyoruz)
      try {
        await FirebaseFirestore.instance
            .collection('bicer_bakimlar')
            .doc(id.toString())
            .delete();
        print("✅ Mobil: Bulut senkronu tamamlandı.");
      } catch (fbError) {
        // İnternet yoksa bile yerelden silindiği için kullanıcıya hata hissettirmeyiz
        print("⚠️ Mobil: Bulut silme başarısız (İnternet?), yerel işlem tamam: $fbError");
      }

      return result;
    } catch (e) {
      print("❌ Mobil Bakım Silme Genel Hatası: $e");
      return 0;
    }
  }
  Future<List<Map<String, dynamic>>> makineleriGetir() async {
    print("\n--- 🚜 MAKİNE PARKURU VE MASRAF ANALİZİ BAŞLATILDI ---");

    // --- WEB İÇİN: FIREBASE VERİ BİRLEŞTİRME (MASHUP) ---
    if (kIsWeb) {
      try {
        print("🌐 Web: Makineler ve masraflar buluttan çekiliyor...");

        // 1. Tüm makineleri çek
        final bicerlerSnapshot = await FirebaseFirestore.instance.collection('bicerler').get();

        // 2. Tüm bakımları çek (Basitlik için hepsini çekip kodla eşleştiriyoruz)
        final bakimlarSnapshot = await FirebaseFirestore.instance.collection('bicer_bakimlari').get();

        List<Map<String, dynamic>> sonucListesi = [];

        for (var doc in bicerlerSnapshot.docs) {
          Map<String, dynamic> bicerVerisi = doc.data();
          String bicerId = doc.id;

          // Bu makineye ait masrafları topla
          double toplamMasraf = 0;
          for (var bakim in bakimlarSnapshot.docs) {
            if (bakim.data()['bicer_id'].toString() == bicerId) {
              toplamMasraf += double.tryParse(bakim.data()['tutar'].toString()) ?? 0;
            }
          }

          bicerVerisi['id'] = bicerId;
          bicerVerisi['toplam_masraf'] = toplamMasraf;
          sonucListesi.add(bicerVerisi);
        }

        print("✅ Web: ${sonucListesi.length} makine masraflarıyla hesaplandı.");
        return sonucListesi;
      } catch (e) {
        print("❌ Web Veri Çekme Hatası: $e");
        return [];
      }
    }

    // --- MOBİL İÇİN: GÜÇLÜ SQLite SQL SORGUSU ---
    try {
      final db = await instance.database;
      print("🚀 Mobil: SQLite üzerinden masraf analizi yapılıyor...");

      // Senin yazdığın o canavar SQL sorgusu:
      final res = await db.rawQuery('''
      SELECT bicerler.*, 
      (SELECT IFNULL(SUM(tutar), 0) FROM bicer_bakimlari WHERE bicer_id = bicerler.id) as toplam_masraf
      FROM bicerler
      ORDER BY id DESC
    ''');

      print("✅ Mobil: ${res.length} makine yerel veritabanından getirildi.");
      return res;
    } catch (e) {
      print("❌ Mobil SQLite Sorgu Hatası: $e");
      return [];
    }
  }
  Future<void> tumMusteriKayitlariniTemizle(String ciftciAd) async {
    print("\n--- 🧹 MÜŞTERİ ARŞİVİ TEMİZLENİYOR (Ad: $ciftciAd) ---");

    // --- WEB İÇİN: FIREBASE TOPLU SİLME (BATCH DELETE) ---
    if (kIsWeb) {
      try {
        print("🌐 Web: Firebase'deki tüm kayıtlar aranıyor...");
        WriteBatch batch = FirebaseFirestore.instance.batch();

        // 1. Biçer İşlerini Bul ve Batch'e Ekle
        var isler = await FirebaseFirestore.instance
            .collection('bicer_isleri')
            .where('ciftci_ad', isEqualTo: ciftciAd)
            .get();
        for (var doc in isler.docs) { batch.delete(doc.reference); }

        // 2. Tahsilatları Bul ve Batch'e Ekle
        var tahsilatlar = await FirebaseFirestore.instance
            .collection('tahsilatlar')
            .where('ciftci_ad', isEqualTo: ciftciAd)
            .get();
        for (var doc in tahsilatlar.docs) { batch.delete(doc.reference); }

        // 3. Hepsini Tek Seferde Sil
        await batch.commit();
        print("✅ Web: Müşteriye ait tüm bulut verileri süpürüldü.");
      } catch (e) {
        print("❌ Web Toplu Silme Hatası: $e");
      }
      return;
    }

    // --- MOBİL İÇİN: SQLite + FIREBASE SENKRONU ---
    try {
      final db = await instance.database;

      // 1. SQLite Yerel Temizlik
      int isSilinen = await db.delete('bicer_isleri', where: 'ciftci_ad = ?', whereArgs: [ciftciAd]);
      int tahsilatSilinen = await db.delete('tahsilatlar', where: 'ciftci_ad = ?', whereArgs: [ciftciAd]);

      print("🚀 Mobil: Yerelde $isSilinen iş ve $tahsilatSilinen tahsilat silindi.");

      // 2. Firebase Temizliği (Arka Planda)
      // Mobilde kullanıcıyı bekletmemek için await koymadan tetikleyebilirsin
      _firebaseTopluSil(ciftciAd);

    } catch (e) {
      print("❌ Mobil Toplu Silme Hatası: $e");
    }
  }

// Yardımcı metod: Mobilde arka planda Firebase'i süpürmek için
  Future<void> _firebaseTopluSil(String ad) async {
    try {
      WriteBatch batch = FirebaseFirestore.instance.batch();
      var isler = await FirebaseFirestore.instance.collection('bicer_isleri').where('ciftci_ad', isEqualTo: ad).get();
      var tahs = await FirebaseFirestore.instance.collection('tahsilatlar').where('ciftci_ad', isEqualTo: ad).get();

      for (var doc in isler.docs) batch.delete(doc.reference);
      for (var doc in tahs.docs) batch.delete(doc.reference);

      await batch.commit();
      print("✅ Bulut senkronu arka planda tamamlandı.");
    } catch (e) {
      print("⚠️ Bulut süpürme aksadı: $e");
    }
  }

  Future<void> tekilHareketSil({
    required dynamic id, // dynamic yaparak Web/Mobil ID uyumunu sağladık
    required bool isHasat,
    dynamic bagliIsId,
    double? miktar
  }) async {
    print("\n--- 🗑️ TEKİL HAREKET SİLİNİYOR (${isHasat ? 'HASAT' : 'TAHSİLAT'}) ---");

    // --- WEB İÇİN: FIREBASE ÜZERİNDEN SİLME VE GÜNCELLEME ---
    if (kIsWeb) {
      try {
        if (isHasat) {
          // 1. Hasat işini sil
          await FirebaseFirestore.instance.collection('bicer_isleri').doc(id.toString()).delete();
          // 2. Bu hasata bağlı tahsilatları temizle
          var tahsilatlar = await FirebaseFirestore.instance
              .collection('tahsilatlar')
              .where('is_id', isEqualTo: id)
              .get();
          for (var doc in tahsilatlar.docs) { await doc.reference.delete(); }
          print("✅ Web: Hasat ve bağlı ödemeleri silindi.");
        } else {
          // 1. Tahsilatı sil
          await FirebaseFirestore.instance.collection('tahsilatlar').doc(id.toString()).delete();
          // 2. Borcu geri yükle (Eğer bağlı bir iş varsa)
          if (bagliIsId != null && miktar != null) {
            await FirebaseFirestore.instance
                .collection('bicer_isleri')
                .doc(bagliIsId.toString())
                .update({
              'odenen_miktar': FieldValue.increment(-miktar), // Miktarı borca geri ekler
            });
          }
          print("✅ Web: Ödeme silindi, borç güncellendi.");
        }
      } catch (e) {
        print("❌ Web Tekil Silme Hatası: $e");
      }
      return;
    }

    // --- MOBİL İÇİN: SQLite + FIREBASE SENKRONU ---
    try {
      final db = await instance.database;

      if (isHasat) {
        // 1. Yerel Silme
        await db.delete('bicer_isleri', where: 'id = ?', whereArgs: [id]);
        await db.delete('tahsilatlar', where: 'is_id = ?', whereArgs: [id]);

        // 2. Bulut Senkronu (Arka Planda)
        _tekilFirebaseSil(id, true);
      } else {
        // 1. Yerel Silme
        await db.delete('tahsilatlar', where: 'id = ?', whereArgs: [id]);

        // 2. Borcu geri yükle (Yerel SQLite)
        if (bagliIsId != null && miktar != null) {
          await db.rawUpdate(
              'UPDATE bicer_isleri SET odenen_miktar = odenen_miktar - ? WHERE id = ?',
              [miktar, bagliIsId]
          );
        }

        // 3. Bulut Senkronu (Arka Planda)
        _tekilFirebaseSil(id, false, bagliIsId: bagliIsId, miktar: miktar);
      }
      print("🚀 Mobil: İşlem yerelde tamamlandı, bulut senkronu başlatıldı.");
    } catch (e) {
      print("❌ Mobil Tekil Silme Hatası: $e");
    }
  }

// Yardımcı metod: Mobilde arka planda Firebase'i temizlemek için
  Future<void> _tekilFirebaseSil(dynamic id, bool isHasat, {dynamic bagliIsId, double? miktar}) async {
    try {
      if (isHasat) {
        await FirebaseFirestore.instance.collection('bicer_isleri').doc(id.toString()).delete();
        var docs = await FirebaseFirestore.instance.collection('tahsilatlar').where('is_id', isEqualTo: id).get();
        for (var d in docs.docs) await d.reference.delete();
      } else {
        await FirebaseFirestore.instance.collection('tahsilatlar').doc(id.toString()).delete();
        if (bagliIsId != null && miktar != null) {
          await FirebaseFirestore.instance.collection('bicer_isleri').doc(bagliIsId.toString())
              .update({'odenen_miktar': FieldValue.increment(-miktar)});
        }
      }
    } catch (e) { print("⚠️ Bulut senkron hatası: $e"); }
  }

  Future<void> bicerIsSil(dynamic id, {String? firebaseId}) async {
    print("\n--- 🌾 HASAT İŞİ SİLİNİYOR (ID: $id) ---");

    // --- WEB İÇİN: SADECE FIREBASE SİLME ---
    if (kIsWeb) {
      try {
        // Eğer firebaseId verilmişse onu kullan, verilmemişse id'yi kullan
        String docId = firebaseId ?? id.toString();
        print("🌐 Web: İş kaydı buluttan siliniyor (ID: $docId)...");

        await FirebaseFirestore.instance
            .collection('bicer_isleri')
            .doc(docId)
            .delete();

        print("✅ Web: Silme işlemi başarılı.");
      } catch (e) {
        print("❌ Web Silme Hatası: $e");
      }
      return; // Web'de SQLite kısmına geçme
    }

    // --- MOBİL İÇİN: SQLite + FIREBASE SENKRONU ---
    try {
      final db = await instance.database;

      // 1. Yerel SQLite'dan sil
      await db.delete('bicer_isleri', where: 'id = ?', whereArgs: [id]);
      print("🚀 Mobil: Kayıt yerel hafızadan temizlendi.");

      // 2. Firebase'den sil
      if (firebaseId != null || id != null) {
        try {
          String docId = firebaseId ?? id.toString();
          await FirebaseFirestore.instance
              .collection('bicer_isleri')
              .doc(docId)
              .delete();
          print("✅ Mobil: Bulut senkronu tamamlandı.");
        } catch (e) {
          print("⚠️ Mobil: Firebase silme aksadı (İnternet?), yerel işlem tamam: $e");
        }
      }
    } catch (e) {
      print("❌ Mobil Genel Silme Hatası: $e");
    }
  }

  Future<void> tahsilatSil(dynamic id, dynamic isId, double miktar) async {
    print("\n--- 💰 TAHSİLAT SİLİNİYOR VE BORÇ GÜNCELLENİYOR ---");

    // --- WEB İÇİN: FIREBASE ÜZERİNDEN SİLME VE BAKİYE DÜZELTME ---
    if (kIsWeb) {
      try {
        print("🌐 Web: Tahsilat siliniyor ve hasat borcu geri yükleniyor...");

        // 1. Tahsilat dökümanını buluttan sil
        await FirebaseFirestore.instance
            .collection('tahsilatlar')
            .doc(id.toString())
            .delete();

        // 2. Hasat işindeki 'odenen_miktar' alanından bu tutarı düş (borca geri ekle)
        await FirebaseFirestore.instance
            .collection('bicer_isleri')
            .doc(isId.toString())
            .update({
          'odenen_miktar': FieldValue.increment(-miktar), // Eksi değer borcu artırır (ödeneni azaltır)
        });

        print("✅ Web: İşlem başarıyla tamamlandı.");
      } catch (e) {
        print("❌ Web Tahsilat Silme Hatası: $e");
      }
      return;
    }

    // --- MOBİL İÇİN: SQLite + FIREBASE SENKRONU ---
    try {
      final db = await instance.database;

      // 1. Yerel SQLite'dan tahsilatı sil
      await db.delete('tahsilatlar', where: 'id = ?', whereArgs: [id]);

      // 2. Hasat işinin ödenen miktarını güncelle (Borcu geri yükle)
      await db.rawUpdate(
          'UPDATE bicer_isleri SET odenen_miktar = odenen_miktar - ? WHERE id = ?',
          [miktar, isId]
      );
      print("🚀 Mobil: Yerel kayıtlar güncellendi.");

      // 3. Firebase Senkronu (Arka Planda)
      FirebaseFirestore.instance.collection('tahsilatlar').doc(id.toString()).delete();
      FirebaseFirestore.instance.collection('bicer_isleri').doc(isId.toString()).update({
        'odenen_miktar': FieldValue.increment(-miktar),
      }).catchError((e) => print("⚠️ Bulut senkron hatası: $e"));

    } catch (e) {
      print("❌ Mobil Tahsilat Silme Hatası: $e");
    }
  }


  Future<void> musteriyiKompleSil(dynamic id) async {
    print("\n--- 🧹 MÜŞTERİ VE GEÇMİŞİ SİLİNİYOR (ID: $id) ---");

    // --- WEB İÇİN: FIREBASE TOPLU TEMİZLİK ---
    if (kIsWeb) {
      try {
        print("🌐 Web: Hasat ve bağlı ödemeler buluttan temizleniyor...");

        // 1. Hasat işini sil
        await FirebaseFirestore.instance
            .collection('bicer_isleri')
            .doc(id.toString())
            .delete();

        // 2. Bu işe bağlı tahsilatları bul ve sil
        var tahsilatlar = await FirebaseFirestore.instance
            .collection('tahsilatlar')
            .where('is_id', isEqualTo: id)
            .get();

        WriteBatch batch = FirebaseFirestore.instance.batch();
        for (var doc in tahsilatlar.docs) {
          batch.delete(doc.reference);
        }
        await batch.commit();

        print("✅ Web: Temizlik başarıyla tamamlandı.");
      } catch (e) {
        print("❌ Web Silme Hatası: $e");
      }
      return;
    }

    // --- MOBİL İÇİN: SQLite + FIREBASE SENKRONU ---
    try {
      final db = await instance.database;

      // 1. Yerel SQLite'dan sil
      await db.delete('bicer_isleri', where: 'id = ?', whereArgs: [id]);
      await db.delete('tahsilatlar', where: 'is_id = ?', whereArgs: [id]);
      print("🚀 Mobil: Yerel kayıtlar süpürüldü.");

      // 2. Firebase'den asenkron sil (Kullanıcıyı bekletmeden arka planda)
      _firebaseKompleTemizlik(id);

    } catch (e) {
      print("❌ Mobil Silme Hatası: $e");
    }
  }

// Yardımcı Metod: Arka planda Firebase'i temizler
  Future<void> _firebaseKompleTemizlik(dynamic id) async {
    try {
      await FirebaseFirestore.instance.collection('bicer_isleri').doc(id.toString()).delete();
      var docs = await FirebaseFirestore.instance.collection('tahsilatlar').where('is_id', isEqualTo: id).get();
      WriteBatch batch = FirebaseFirestore.instance.batch();
      for (var d in docs.docs) batch.delete(d.reference);
      await batch.commit();
      print("✅ Bulut senkronu tamamlandı.");
    } catch (e) {
      print("⚠️ Bulut temizliği aksadı: $e");
    }
  }

  Future<void> bicerEkstreSatirSil({
    required dynamic id,
    required bool isHasat,
    dynamic bagliIsId,
    double? miktar
  }) async {
    // GÜVENLİK: ID null gelirse SQLite hata verir, bunu engelliyoruz.
    if (id == null || id.toString() == "null") {
      print("⚠️ İptal: Silinecek kaydın ID'si null.");
      return;
    }

    print("\n--- 📝 BİÇER EKSTRE SATIRI SİLİNİYOR (${isHasat ? 'HASAT' : 'TAHSİLAT'}) ---");

    // ÖNEMLİ: SQLite tablonun adı 'bicermusteri_hareketleri' olarak güncellendi.
    String sqlTablo = isHasat ? 'bicer_isleri' : 'bicermusteri_hareketleri';
    // Firebase koleksiyon adın (Görsellere göre tahsilatlar burada)
    String firebaseKoleksiyon = isHasat ? 'bicer_isleri' : 'bicermusteri_hareketleri';

    if (kIsWeb) {
      try {
        await FirebaseFirestore.instance.collection(firebaseKoleksiyon).doc(id.toString()).delete();

        if (!isHasat && bagliIsId != null && miktar != null) {
          await FirebaseFirestore.instance.collection('bicer_isleri').doc(bagliIsId.toString()).update({
            'odenen_miktar': FieldValue.increment(-miktar),
          });
        }
        print("✅ Web: Silme ve bakiye düzeltme başarılı.");
      } catch (e) { print("❌ Web Hatası: $e"); }
      return;
    }

    // --- MOBİL (SQLite + Firebase) ---
    try {
      final db = await instance.database;

      // 1. Yerel Silme (Doğru tablo ismi kullanıldı)
      int count = await db.delete(sqlTablo, where: 'id = ?', whereArgs: [id.toString()]);

      if (count > 0) {
        // 2. Bakiye Düzeltme (Borcu geri yükleme)
        if (!isHasat && bagliIsId != null && miktar != null) {
          await db.rawUpdate(
              'UPDATE bicer_isleri SET odenen_miktar = odenen_miktar - ? WHERE id = ?',
              [miktar, bagliIsId]
          );
        }

        // 3. Buluttan Silme
        await FirebaseFirestore.instance.collection(firebaseKoleksiyon).doc(id.toString()).delete();
        print("✅ Mobil: Yerel ve bulut silme işlemi tamamlandı.");
      }
    } catch (e) {
      print("❌ Mobil Silme Hatası: $e");
    }
  }

// Mobilde arka planda Firebase bakiye düzeltme yardımcısı
  Future<void> _firebaseEkstreGuncelle(dynamic tahsilatId, dynamic isId, double? miktar) async {
    try {
      await FirebaseFirestore.instance.collection('tahsilatlar').doc(tahsilatId.toString()).delete();
      if (isId != null && miktar != null) {
        await FirebaseFirestore.instance.collection('bicer_isleri').doc(isId.toString()).update({
          'odenen_miktar': FieldValue.increment(-miktar),
        });
      }
    } catch (e) { print("⚠️ Bulut senkron hatası: $e"); }
  }

  Future<void> satisIptalEtVeStokGeriYukle(Map<String, dynamic> satisVerisi) async {
    print("\n--- 📦 SATIŞ İPTAL VE STOK GERİ YÜKLEME BAŞLATILDI ---");

    // Satıştan gelen verileri ayıklayalım
    dynamic satisId = satisVerisi['id'];
    dynamic stokId = satisVerisi['stok_id'];
    double miktar = double.tryParse(satisVerisi['miktar'].toString()) ?? 0;

    // --- WEB İÇİN: FIREBASE ATOMIC UPDATE ---
    if (kIsWeb) {
      try {
        print("🌐 Web: Satış buluttan siliniyor ve stok miktarı artırılıyor...");

        // Firebase'de toplu işlem (WriteBatch) başlatalım
        WriteBatch batch = FirebaseFirestore.instance.batch();

        // 1. Satış kaydını sil
        DocumentReference satisRef = FirebaseFirestore.instance.collection('satislar').doc(satisId.toString());
        batch.delete(satisRef);

        // 2. Stok miktarını güncelle (adet + miktar)
        DocumentReference stokRef = FirebaseFirestore.instance.collection('stoklar').doc(stokId.toString());
        batch.update(stokRef, {
          'adet': FieldValue.increment(miktar), // Stok miktarını tam olarak miktar kadar artırır
          'son_guncelleme': FieldValue.serverTimestamp(),
        });

        // 3. İşlemleri onayla
        await batch.commit();

        print("✅ Web: İade işlemi tamam. $miktar adet mal stoka geri döndü.");
        return;
      } catch (e) {
        print("❌ Web İade Hatası: $e");
        return;
      }
    }

    // --- MOBİL İÇİN: SQLite TRANSACTION + FIREBASE SENKRONU ---
    try {
      final db = await instance.database;

      await db.transaction((txn) async {
        // 1. Yerel Satışı sil
        await txn.delete('satislar', where: 'id = ?', whereArgs: [satisId]);

        // 2. Yerel Stoğu geri yükle
        await txn.rawUpdate(
            'UPDATE stoklar SET adet = adet + ? WHERE id = ?',
            [miktar, stokId]
        );

        print("🚀 Mobil: Yerel stok ve satış kaydı güncellendi.");

        // 3. Firebase Senkronu (Transaction içinden güvenle çağırıyoruz)
        try {
          await FirebaseFirestore.instance.collection('satislar').doc(satisId.toString()).delete();
          await FirebaseFirestore.instance.collection('stoklar').doc(stokId.toString()).update({
            'adet': FieldValue.increment(miktar),
          });
          print("✅ Mobil: Bulut senkronu başarılı.");
        } catch (fbError) {
          print("⚠️ Mobil: Bulut yedeklemesi o an yapılamadı: $fbError");
        }
      });

    } catch (e) {
      print("❌ Mobil İade Genel Hatası: $e");
    }
  }
  // database_helper.dart içine ekle
  Future<void> satisIptalEt(dynamic satisId, dynamic stokId, double miktar) async {
    print("\n--- 📦 SATIŞ İPTAL EDİLİYOR (ID: $satisId) ---");

    // --- WEB İÇİN: FIREBASE BATCH UPDATE ---
    if (kIsWeb) {
      try {
        print("🌐 Web: Satış siliniyor ve stok miktarı artırılıyor...");
        WriteBatch batch = FirebaseFirestore.instance.batch();

        // 1. Satış kaydını sil
        batch.delete(FirebaseFirestore.instance.collection('satislar').doc(satisId.toString()));

        // 2. Stoğu geri yükle (adet + miktar)
        batch.update(FirebaseFirestore.instance.collection('stoklar').doc(stokId.toString()), {
          'adet': FieldValue.increment(miktar),
        });

        await batch.commit();
        print("✅ Web: Satış iptal edildi, $miktar adet stok geri yüklendi.");
        return;
      } catch (e) {
        print("❌ Web Satis Iptal Hatası: $e");
        return;
      }
    }

    // --- MOBİL İÇİN: SQLite TRANSACTION + FIREBASE SENKRONU ---
    try {
      final db = await instance.database;

      await db.transaction((txn) async {
        // 1. SQLite: Satışı sil
        await txn.delete('satislar', where: 'id = ?', whereArgs: [satisId]);

        // 2. SQLite: Stoğu güncelle
        await txn.rawUpdate(
            'UPDATE stoklar SET adet = adet + ? WHERE id = ?',
            [miktar, stokId]
        );

        // 3. Firebase: Senkronizasyon (İnternet varsa bulutu da düzelt)
        FirebaseFirestore.instance.collection('satislar').doc(satisId.toString()).delete();
        FirebaseFirestore.instance.collection('stoklar').doc(stokId.toString()).update({
          'adet': FieldValue.increment(miktar),
        });
      });

      print("🚀 Mobil: Satış silindi, yerel ve bulut stokları güncellendi.");
    } catch (e) {
      print("❌ Mobil Satis Iptal Hatası: $e");
    }
  }


  Future<int> isSil(dynamic id) async {
    print("\n--- 🚜 HASAT İŞİ SİLİNİYOR (ID: $id) ---");

    // --- WEB İÇİN: SADECE FIREBASE ---
    if (kIsWeb) {
      try {
        await FirebaseFirestore.instance.collection('isler').doc(id.toString()).delete();
        print("✅ Web: İş kaydı buluttan silindi.");
        return 1;
      } catch (e) {
        print("❌ Web Is Sil Hatası: $e");
        return 0;
      }
    }

    // --- MOBİL İÇİN: SQLite + FIREBASE ---
    try {
      final db = await instance.database;

      // 1. Yerelden sil
      int res = await db.delete('isler', where: 'id = ?', whereArgs: [id]);

      // 2. Buluttan asenkron sil (İnternet varsa gider)
      FirebaseFirestore.instance.collection('isler').doc(id.toString()).delete();

      print("🚀 Mobil: İş kaydı yerelden ve buluttan temizlendi.");
      return res;
    } catch (e) {
      print("❌ Mobil Is Sil Hatası: $e");
      return 0;
    }
  }

// İş Güncelle: Dekar veya fiyat değişirse her iki tarafa da işler.
  Future<int> bicerIsGuncelle(dynamic id, Map<String, dynamic> veri) async {
    print("\n--- 🌾 HASAT İŞİ GÜNCELLENİYOR (ID: $id) ---");

    // --- WEB İÇİN: DOĞRUDAN FIREBASE GÜNCELLEME ---
    if (kIsWeb) {
      try {
        print("🌐 Web: Hasat verileri bulutta güncelleniyor...");

        await FirebaseFirestore.instance
            .collection('bicer_isleri')
            .doc(id.toString())
            .update({
          ...veri,
          'son_guncelleme': FieldValue.serverTimestamp(), // Güncelleme zamanını damgalıyoruz
        });

        print("✅ Web: Güncelleme başarıyla tamamlandı.");
        return 1;
      } catch (e) {
        print("❌ Web İş Güncelleme Hatası: $e");
        return 0;
      }
    }

    // --- MOBİL İÇİN: SQLite + FIREBASE SENKRONU ---
    try {
      final db = await instance.database;

      // 1. Yerel SQLite Güncellemesi
      int res = await db.update(
          'bicer_isleri',
          veri,
          where: 'id = ?',
          whereArgs: [id]
      );
      print("🚀 Mobil: Yerel kayıt güncellendi.");

      // 2. Firebase Senkronizasyonu
      try {
        await FirebaseFirestore.instance
            .collection('bicer_isleri')
            .doc(id.toString())
            .update({
          ...veri,
          'son_guncelleme': FieldValue.serverTimestamp(),
        });
        print("✅ Mobil: Firebase senkronu başarılı.");
      } catch (fbError) {
        // İnternet yoksa bile yerelde güncellendiği için kullanıcıya sorun yansıtmayız
        print("⚠️ Mobil: Firebase o an güncellenemedi (İnternet?), yerel işlem tamam: $fbError");
      }

      return res;
    } catch (e) {
      print("❌ Mobil İş Güncelleme Genel Hatası: $e");
      return 0;
    }
  }

  // Bakım Ekle: Parça veya servis kaydını yedekler.
  Future<dynamic> bicerBakimEkle(Map<String, dynamic> veri) async {
    print("\n--- 🔧 YENİ BAKIM/SERVİS KAYDI İŞLENİYOR ---");

    // --- WEB İÇİN: DOĞRUDAN FIREBASE KAYDI ---
    if (kIsWeb) {
      try {
        print("🌐 Web: Bakım verileri buluta gönderiliyor...");

        // Firebase'de döküman oluştur
        var ref = await FirebaseFirestore.instance.collection('bicer_bakimlar').add({
          ...veri,
          'kayit_tarihi': FieldValue.serverTimestamp(),
        });

        print("✅ Web: Bakım kaydı bulutta oluşturuldu (ID: ${ref.id})");
        return ref.id;
      } catch (e) {
        print("❌ Web Bakım Kayıt Hatası: $e");
        return 0;
      }
    }

    // --- MOBİL İÇİN: SQLite + FIREBASE SENKRONU ---
    try {
      final db = await instance.database;

      // 1. Yerel SQLite Kaydı
      // Sanayide internet çekmese bile kayıt anında cepte.
      int id = await db.insert('bicer_bakimlar', veri);
      print("🚀 Mobil: Bakım kaydı yerel deftere işlendi (ID: $id)");

      // 2. Firebase Yedekleme
      try {
        await FirebaseFirestore.instance.collection('bicer_bakimlar').doc(id.toString()).set({
          ...veri,
          'id': id, // SQLite ID'sini Firebase'de de tutalım ki eşleşsin
          'kayit_tarihi': FieldValue.serverTimestamp(),
        });
        print("✅ Mobil: Bakım kaydı buluta başarıyla yedeklendi.");
      } catch (fbError) {
        print("⚠️ Mobil: Firebase yedekleme aksadı (İnternet?), yerel kayıt tamam: $fbError");
      }

      return id;
    } catch (e) {
      print("❌ Mobil Bakım Kayıt Genel Hatası: $e");
      return 0;
    }
  }

// Bakımları Getir: Belirli bir biçerin tüm servis geçmişini listeler.
  Future<List<Map<String, dynamic>>> bicerBakimlariGetir(dynamic bicerId) async {
    print("\n--- 🛠️ MAKİNE BAKIM GEÇMİŞİ SORGULANIYOR (ID: $bicerId) ---");

    // --- WEB İÇİN: DOĞRUDAN FIREBASE SORGUSU ---
    if (kIsWeb) {
      try {
        print("🌐 Web: Bakım kayıtları buluttan çekiliyor...");
        final snapshot = await FirebaseFirestore.instance
            .collection('bicer_bakimlar')
            .where('bicer_id', isEqualTo: bicerId)
            .get();

        if (snapshot.docs.isNotEmpty) {
          var liste = snapshot.docs.map((doc) => {
            'id_firebase': doc.id,
            ...doc.data(),
          }).toList();

          // En son yapılan bakım en üstte görünsün (Tarihe göre sıralama)
          // Eğer Firebase'de 'kayit_tarihi' varsa ona göre, yoksa ID'ye göre süzüyoruz
          liste.sort((a, b) => (b['kayit_tarihi']?.toString() ?? "")
              .compareTo(a['kayit_tarihi']?.toString() ?? ""));

          print("✅ Web: Bulutta ${liste.length} bakım kaydı bulundu.");
          return liste;
        }
      } catch (e) {
        print("❌ Web Bakım Liste Hatası: $e");
      }
      return [];
    }

    // --- MOBİL İÇİN: ÖNCE FIREBASE, SONRA SQLite ---
    try {
      print("📱 Mobil: Güncel bakım geçmişi için Firebase kontrol ediliyor...");
      final snapshot = await FirebaseFirestore.instance
          .collection('bicer_bakimlar')
          .where('bicer_id', isEqualTo: bicerId)
          .get();

      if (snapshot.docs.isNotEmpty) {
        print("✅ Mobil: Bakım geçmişi buluttan tazelendi.");
        return snapshot.docs.map((doc) => doc.data()).toList();
      }
    } catch (e) {
      print("⚠️ Mobil: Firebase'e ulaşılamadı (İnternet?), yerel hafızaya bakılıyor.");
    }

    // Firebase boşsa veya hata verdiyse yerel SQLite'a bak
    try {
      final db = await instance.database;
      final res = await db.query(
          'bicer_bakimlar',
          where: 'bicer_id = ?',
          whereArgs: [bicerId],
          orderBy: "id DESC" // Yerelde ID (veya tarih) üzerinden en yeni üstte
      );

      print("🚀 Mobil: Yerel veritabanından ${res.length} bakım kaydı getirildi.");
      return res;
    } catch (e) {
      print("❌ Mobil SQLite Bakım Liste Hatası: $e");
      return [];
    }
  }

  Future<int> bicerBakimGuncelle(dynamic id, Map<String, dynamic> row) async {
    print("\n--- 🔧 BAKIM KAYDI GÜNCELLENİYOR (ID: $id) ---");

    if (kIsWeb) {
      try {
        await FirebaseFirestore.instance.collection('bicer_bakimlar').doc(id.toString()).update(row);
        print("✅ Web: Bakım bulutta güncellendi.");
        return 1;
      } catch (e) {
        print("❌ Web Güncelleme Hatası: $e");
        return 0;
      }
    }

    try {
      final db = await instance.database;
      int res = await db.update('bicer_bakimlar', row, where: 'id = ?', whereArgs: [id]);

      // Firebase Senkronu
      await FirebaseFirestore.instance.collection('bicer_bakimlar').doc(id.toString()).update(row);
      print("🚀 Mobil: Yerel ve Bulut güncellendi.");
      return res;
    } catch (e) {
      print("❌ Mobil Güncelleme Hatası: $e");
      return 0;
    }
  }

  Future<dynamic> hasatEkle(Map<String, dynamic> veri) async {
    print("\n--- 🌾 YENİ HASAT KAYDI İŞLENİYOR ---");

    if (kIsWeb) {
      try {
        var ref = FirebaseFirestore.instance.collection('tarla_hasatlari').doc();
        Map<String, dynamic> fbVeri = Map.from(veri);
        fbVeri['sql_id'] = ref.id;
        fbVeri['olusturma_tarihi'] = FieldValue.serverTimestamp();

        await ref.set(fbVeri);
        print("✅ Web: Hasat buluta eklendi (ID: ${ref.id})");
        return ref.id;
      } catch (e) {
        print("❌ Web Hasat Hatası: $e");
        return 0;
      }
    }

    final db = await instance.database;
    int id = await db.insert('tarla_hasatlari', veri);

    try {
      Map<String, dynamic> firebaseVeri = Map.from(veri);
      firebaseVeri['sql_id'] = id;
      firebaseVeri['is_synced'] = 1;
      firebaseVeri['olusturma_tarihi'] = FieldValue.serverTimestamp();

      await FirebaseFirestore.instance.collection('tarla_hasatlari').doc(id.toString()).set(firebaseVeri);

      await db.update('tarla_hasatlari', {'is_synced': 1, 'firebase_id': id.toString()}, where: 'id = ?', whereArgs: [id]);
      print("🚀 Mobil: Hasat yerel ve bulut kaydı tamam.");
    } catch (e) {
      print("⚠️ Firebase sync hatası: $e");
    }
    return id;
  }

  Future<dynamic> tarlaEkle(Map<String, dynamic> veri) async {
    print("\n--- 🚜 TARLA KAYDI BAŞLADI ---");

    if (kIsWeb) {
      try {
        var ref = FirebaseFirestore.instance.collection('tarlalar').doc();
        Map<String, dynamic> fbVeri = Map.from(veri);
        fbVeri['id'] = ref.id;
        fbVeri['is_synced'] = 1;

        await FirebaseFirestore.instance.collection('tarlalar').doc("TRL_${ref.id}").set(fbVeri);
        print("✅ Web: Tarla TRL_${ref.id} olarak buluta eklendi.");
        return ref.id;
      } catch (e) {
        print("❌ Web Tarla Ekleme Hatası: $e");
        return 0;
      }
    }

    // ---- MOBİL TARAFINDA ÇAKIŞMAYI ÖNLEYEN GÜNCELLEME ----
    final db = await instance.database;

    // Önce SQLite'a normal kaydet ve yerel ID'sini al
    int localId = await db.insert('tarlalar', veri);

    try {
      // Farklı telefonların aynı ID'yi üretip bulutta birbirini silmemesi için
      // Firestore'dan benzersiz bir doküman ID'si ürettiriyoruz
      var uuidRef = FirebaseFirestore.instance.collection('tarlalar').doc();
      String benzersizBulutId = uuidRef.id;

      Map<String, dynamic> fbVeri = Map.from(veri);
      fbVeri['id'] = benzersizBulutId; // Bulut verisinde ID artık benzersiz
      fbVeri['local_id'] = localId;    // İleride yerel eşitleme gerekirse diye sakla
      fbVeri['is_synced'] = 1;

      // Buluta asla çakışmayacak benzersiz ID ile kaydediyoruz
      await FirebaseFirestore.instance.collection('tarlalar').doc("TRL_$benzersizBulutId").set(fbVeri, SetOptions(merge: true));

      // Yerel veritabanını da güncelle (Eğer yerel tabloda id string değilse local_id veya sync durumunu işaretle)
      await db.update('tarlalar', {'is_synced': 1}, where: 'id = ?', whereArgs: [localId]);
      print("🚀 Mobil: TRL_$benzersizBulutId kaydı yerel ve bulutta tamam.");
    } catch (e) {
      print("❌ HATA: Bulut senkronizasyonunda patladı: $e");
    }
    return localId;
  }


  Future<List<Map<String, dynamic>>> tarlaListesiGetir() async {
    print("\n--- 🚜 TARLA LİSTESİ ÇEKİLİYOR ---");

    // --- WEB İÇİN: DOĞRUDAN FIREBASE ---
    if (kIsWeb) {
      try {
        print("🌐 Web: Tarlalar buluttan çekiliyor...");

        // ⚠️ KRİTİK DÜZELTME: Firestore'da 'tarla_adi' alanı olmadığı için
        // şimdilik 'sezon' alanına göre sıralıyoruz veya orderBy'ı tamamen kaldırabilirsin.
        final snapshot = await FirebaseFirestore.instance
            .collection('tarlalar')
            .orderBy('sezon')
            .get();

        print("🌐 Web: Buluttan gelen döküman sayısı: ${snapshot.docs.length}");

        if (snapshot.docs.isNotEmpty) {
          final data = snapshot.docs.map((doc) => {
            'id': doc.id,
            'firebase_id': doc.id,
            ...doc.data(),
          }).toList();
          print("🌐 Web: Haritalanan veri: $data");
          return data;
        }
        return [];
      } catch (e) {
        print("❌ Web Tarla Çekme Hatası: $e");
        return [];
      }
    }

    // --- MOBİL İÇİN: ÖNCE GÜNCEL BULUT, SONRA YEREL ---
    try {
      print("📱 Mobil: Güncel tarla listesi için Firebase kontrol ediliyor...");

      // ⚠️ KRİTİK DÜZELTME: Firestore dökümanında 'tarla_adi' kolonu olmadığı için
      // sıralamayı 'sezon' yaptık. Eğer tarla ismi ekleyeceksen burayı tekrar güncelleriz.
      final snapshot = await FirebaseFirestore.instance
          .collection('tarlalar')
          .orderBy('sezon')
          .get();

      print("📱 Mobil: Firebase'den dönen döküman sayısı: ${snapshot.docs.length}");

      if (snapshot.docs.isNotEmpty) {
        final bulutVerisi = snapshot.docs.map((doc) => {
          'id': doc.id,               // 👈 Arayüzün tanıması için ID'leri gömdük
          'firebase_id': doc.id,
          ...doc.data(),
        }).toList();

        print("✅ Mobil: Liste buluttan başarıyla tazelendi. Veri: $bulutVerisi");
        return bulutVerisi;
      } else {
        print("⚠️ Mobil: Firebase'de 'tarlalar' koleksiyonu boş veya döküman bulunamadı.");
      }
    } catch (e) {
      print("❌ Mobil Buluttan Çekme Hatası (Büyük ihtimalle orderBy veya Yetki hatası): $e");
      print("⚠️ Mobil: Bulut başarısız oldu, yerel SQLite hafızasına yönlendiriliyorsunuz...");
    }

    // Firebase'e ulaşılamazsa, hata verirse veya boşsa SQLite'dan çek
    try {
      final db = await instance.database;

      // ⚠️ Yerel SQLite tablonuzda 'tarla_adi' kolonu varsa burası çalışır.
      // Eğer yerelde de yoksa hata vermemesi için şimdilik 'id ASC' veya 'sezon ASC' yapabilirsin.
      print("🚀 Mobil: Yerel SQLite sorgusu başlatılıyor...");
      final res = await db.query('tarlalar', orderBy: 'id ASC');

      print("🚀 Mobil: Yerel veritabanından ${res.length} adet tarla başarıyla getirildi.");
      print("🚀 Mobil: Yerel veri içeriği: $res");
      return res;
    } catch (e) {
      print("❌ Mobil SQLite Sorgu Hatası: $e");
      return [];
    }
  }

  Future<dynamic> tarlaHareketiEkle(Map<String, dynamic> veri) async {
    print("\n--- 🚜 TARLA HAREKETİ VE BORÇ SİSTEMİ BAŞLATILDI ---");

    // Arayüzden gelen anahtar isimlerini veritabanı şemana göre güvenli hale getiriyoruz
    Map<String, dynamic> localVeri = {
      'tarla_id': veri['tarla_id'],
      'islem_tipi': veri['islem_tipi'] ?? veri['aciklama'], // şemandaki kolon 'islem_tipi'
      'miktar': double.tryParse(veri['miktar']?.toString() ?? "0") ?? 0,
      'tutar': double.tryParse(veri['tutar']?.toString() ?? veri['toplam']?.toString() ?? "0") ?? 0,
      'tarih': veri['tarih'] ?? DateTime.now().toString().split(' ')[0],
      'notlar': veri['notlar'] ?? "",
      'firma_id': veri['firma_id'],
      'is_synced': 0,
      'silindi': 0
    };

    // --- WEB İÇİN: FIREBASE ATOMIC BATCH ---
    if (kIsWeb) {
      try {
        print("🌐 Web: Hareket işleniyor ve firma borcu güncelleniyor...");
        WriteBatch batch = FirebaseFirestore.instance.batch();

        DocumentReference hareketRef = FirebaseFirestore.instance.collection('tarla_hareketleri').doc();

        batch.set(hareketRef, {
          ...localVeri,
          'sql_id': hareketRef.id,
          'is_synced': 1,
          'kayit_tarihi': FieldValue.serverTimestamp(),
        });

        if (veri['firma_id'] != null && veri['firma_id'] != 0 && veri['firma_id'] != "") {
          double tutar = localVeri['tutar'];
          DocumentReference firmaRef = FirebaseFirestore.instance.collection('ciftclik_firmalari').doc(veri['firma_id'].toString());

          batch.update(firmaRef, {
            'borc': FieldValue.increment(tutar),
          });
          print("💰 Web: Firma borcu bulutta tetiklendi: +$tutar TL");
        }

        await batch.commit();
        print("✅ Web: Hareket ve borç mühürlendi.");
        return hareketRef.id;
      } catch (e) {
        print("❌ Web Hata: $e");
        return -1;
      }
    }

    // --- MOBİL İÇİN: SQLite + FIREBASE SENKRONU ---
    final db = await instance.database;
    try {
      // 1. ADIM: Yerel SQLite Kaydı (GÜVENLİ localVeri kullanılıyor)
      int id = await db.insert(
          'tarla_hareketleri',
          localVeri,
          conflictAlgorithm: ConflictAlgorithm.replace
      );

      // 2. ADIM: Firma Borcu İşleme (Yerel)
      if (veri['firma_id'] != null && veri['firma_id'] != 0) {
        double tutar = localVeri['tutar'];
        await db.rawUpdate(
          'UPDATE ciftclik_firmalari SET borc = borc + ? WHERE id = ?',
          [tutar, veri['firma_id']],
        );
      }

      // 3. ADIM: Firebase Senkronu
      try {
        await FirebaseFirestore.instance.collection('tarla_hareketleri').doc(id.toString()).set({
          ...localVeri,
          'sql_id': id,
          'is_synced': 1,
          'kayit_tarihi': FieldValue.serverTimestamp(),
        });

        if (veri['firma_id'] != null && veri['firma_id'] != 0) {
          double tutar = localVeri['tutar'];
          await FirebaseFirestore.instance.collection('ciftclik_firmalari').doc(veri['firma_id'].toString()).update({
            'borc': FieldValue.increment(tutar),
          });
        }

        // 4. ADIM: Bayrağı işaretle
        await db.update('tarla_hareketleri', {'is_synced': 1}, where: 'id = ?', whereArgs: [id]);

      } catch (fbError) {
        print("⚠️ Mobil: Bulut senkronu aksadı, yerel kayıt ve borç tamam: $fbError");
      }

      print("✅ Mobil: Tarla Hareketi Mühürlendi, ID: $id");
      return id;
    } catch (e) {
      print("❌ Mobil Hata: $e");
      return -1;
    }
  }


  Future<List<Map<String, dynamic>>> tumTarlaHareketleriniGetir() async {
    print("\n--- 📜 TÜM TARLA HAREKETLERİ LİSTELENİYOR ---");

    // --- WEB İÇİN: FIREBASE ÜZERİNDEN GETİR ---
    if (kIsWeb) {
      try {
        print("🌐 Web: Hareketler buluttan çekiliyor...");
        // Not: Firebase'de 'tarih' alanına göre sıralama yapabilmek için
        // bu alana ait bir index (indeks) oluşturulmuş olması gerekebilir.
        final snapshot = await FirebaseFirestore.instance
            .collection('tarla_hareketleri')
            .orderBy('tarih', descending: true)
            .get();

        if (snapshot.docs.isNotEmpty) {
          return snapshot.docs.map((doc) => {
            'id': doc.id,
            ...doc.data(),
          }).toList();
        }
        return [];
      } catch (e) {
        print("❌ Web Liste Çekme Hatası: $e");
        return [];
      }
    }

    // --- MOBİL İÇİN: SQLite (Çevrimdışı Dostu) ---
    try {
      final db = await instance.database;
      // En yeni işlemler en üstte görünecek şekilde (DESC) sıralıyoruz
      final res = await db.query('tarla_hareketleri', orderBy: 'tarih DESC');

      print("🚀 Mobil: Yerel hafızadan ${res.length} hareket getirildi.");
      return res;
    } catch (e) {
      print("❌ Mobil Liste Çekme Hatası: $e");
      return [];
    }
  }

  // 1. Tarla Hareketi Silme (Hesap Düzeltme Destekli)
  Future<void> tarlaHareketiSil({
    required dynamic id,
    dynamic firmaId,
    double? tutar
  }) async {
    print("\n--- 🗑️ TARLA HAREKETİ SİLİNİYOR (ID: $id) ---");

    // --- WEB İÇİN: FIREBASE SİLME VE BORÇ DÜZELTME ---
    if (kIsWeb) {
      try {
        print("🌐 Web: Hareket buluttan siliniyor...");

        WriteBatch batch = FirebaseFirestore.instance.batch();

        // 1. Hareketi sil
        DocumentReference hareketRef = FirebaseFirestore.instance.collection('tarla_hareketleri').doc(id.toString());
        batch.delete(hareketRef);

        // 2. Eğer firma borcu varsa geri yükle (eksi miktar göndererek)
        if (firmaId != null && firmaId != 0 && tutar != null) {
          DocumentReference firmaRef = FirebaseFirestore.instance.collection('ciftclik_firmalari').doc(firmaId.toString());
          batch.update(firmaRef, {
            'borc': FieldValue.increment(-tutar), // Borcu tutar kadar azaltır
          });
          print("💰 Web: Firma borcu geri çekildi: -$tutar TL");
        }

        await batch.commit();
        print("✅ Web: Kayıt ve bağlı borç temizlendi.");
        return;
      } catch (e) {
        print("❌ Web Silme Hatası: $e");
        return;
      }
    }

    // --- MOBİL İÇİN: SQLite + FIREBASE SENKRONU ---
    try {
      final db = await instance.database;

      // 1. Yerel SQLite'dan sil
      await db.delete(
        'tarla_hareketleri',
        where: 'id = ?',
        whereArgs: [id],
      );

      // 2. Yerel Firma Borcunu Düzelt
      if (firmaId != null && firmaId != 0 && tutar != null) {
        await db.rawUpdate(
          'UPDATE ciftclik_firmalari SET borc = borc - ? WHERE id = ?',
          [tutar, firmaId],
        );
        print("💰 Mobil: Yerel firma borcu düşürüldü: -$tutar TL");
      }

      // 3. Firebase'den asenkron sil ve bulut borcunu düzelt
      _firebaseHareketSil(id, firmaId, tutar);

      print("🚀 Mobil: İşlem tamamlandı.");
    } catch (e) {
      print("❌ Mobil Silme Hatası: $e");
    }
  }



  Future<void> tarlaHareketiGuncelle(dynamic id, Map<String, dynamic> veri, {double? eskiTutar, dynamic firmaId}) async {
    print("\n--- 📝 TARLA HAREKETİ GÜNCELLENİYOR (ID: $id) ---");

    // Arayüzden gelen veriyi SQL formatına hazırlıyoruz
    Map<String, dynamic> sqlVeri = {
      'islem_adi': veri['aciklama'],
      'tutar': veri['toplam'],
      'miktar': veri['miktar'],
      'is_synced': 1,
    };

    // --- WEB İÇİN: FIREBASE GÜNCELLEME ---
    if (kIsWeb) {
      try {
        WriteBatch batch = FirebaseFirestore.instance.batch();
        DocumentReference hareketRef = FirebaseFirestore.instance.collection('tarla_hareketleri').doc(id.toString());

        batch.update(hareketRef, {
          'aciklama': veri['aciklama'],
          'toplam': veri['toplam'],
          'miktar': veri['miktar'],
          'birimFiyat': veri['birimFiyat'],
        });

        // Firma borcu farkını işlet (Yeni Tutar - Eski Tutar)
        if (firmaId != null && eskiTutar != null) {
          double yeniTutar = double.tryParse(veri['toplam'].toString()) ?? 0;
          double fark = yeniTutar - eskiTutar;
          batch.update(FirebaseFirestore.instance.collection('ciftclik_firmalari').doc(firmaId.toString()), {
            'borc': FieldValue.increment(fark),
          });
        }
        await batch.commit();
        return;
      } catch (e) { print("❌ Web Güncelleme Hatası: $e"); return; }
    }

    // --- MOBİL İÇİN: SQLite + FIREBASE ---
    try {
      final db = await instance.database;
      await db.update('tarla_hareketleri', sqlVeri, where: 'id = ?', whereArgs: [id]);

      if (firmaId != null && eskiTutar != null) {
        double yeniTutar = double.tryParse(veri['toplam'].toString()) ?? 0;
        double fark = yeniTutar - eskiTutar;
        await db.rawUpdate('UPDATE ciftclik_firmalari SET borc = borc + ? WHERE id = ?', [fark, firmaId]);
      }

      // Firebase senkronu (Arka planda)
      FirebaseFirestore.instance.collection('tarla_hareketleri').doc(id.toString()).update(veri);
      print("✅ Mobil: Güncelleme ve bakiye düzeltme tamam.");
    } catch (e) { print("❌ Mobil Güncelleme Hatası: $e"); }
  }

  Future<List<Map<String, dynamic>>> tumHasatlariGetir() async {
    if (kIsWeb) {
      var snap = await FirebaseFirestore.instance.collection('tarla_hasatlari').orderBy('tarih', descending: true).get();
      return snap.docs.map((doc) => doc.data()).toList();
    }

    final db = await instance.database;
    return await db.query('tarla_hasatlari', orderBy: 'tarih DESC');
  }
  Future<int> tarlaSil(dynamic id) async {
    print("\n--- 🗑️ TARLA SİLİNİYOR (ID: $id) ---");

    if (kIsWeb) {
      await FirebaseFirestore.instance.collection('tarlalar').doc("TRL_$id").delete();
      return 1;
    }

    final db = await instance.database;
    int res = await db.delete('tarlalar', where: 'id = ?', whereArgs: [id]);

    try {
      await FirebaseFirestore.instance.collection('tarlalar').doc("TRL_$id").delete();
    } catch (e) { print("⚠️ Firebase Tarla Silme Hatası: $e"); }

    return res;
  }


  Future<dynamic> hasatKaydet(Map<String, dynamic> veri) async {
    print("\n--- 🌾 YENİ HASAT KAYDI BAŞLATILDI ---");

    // --- WEB İÇİN: DOĞRUDAN FIREBASE ---
    if (kIsWeb) {
      try {
        print("🌐 Web: Hasat verisi buluta işleniyor...");
        // Web'de döküman ID'sini Firebase otomatik oluşturur
        var ref = await FirebaseFirestore.instance.collection('tarla_hasatlari').add({
          ...veri,
          'sql_id': null, // Web'de SQL ID'si olmaz
          'is_synced': 1,
          'kayit_anlik': FieldValue.serverTimestamp(),
        });
        print("✅ Web: Hasat buluta eklendi (ID: ${ref.id})");
        return ref.id;
      } catch (e) {
        print("❌ Web Hasat Kayıt Hatası: $e");
        return 0;
      }
    }

    // --- MOBİL İÇİN: SQLite + FIREBASE SENKRONU ---
    try {
      final db = await instance.database;

      // 1. Önce SQLite'a ekle (İnternet olmasa da veri cepte)
      int id = await db.insert('tarla_hasatlari', veri);
      print("🚀 Mobil: Yerel SQL kaydı başarılı (ID: $id)");

      try {
        // 2. Firebase'e gönderirken SQL ID'sini doküman ismi (docId) yapıyoruz
        await FirebaseFirestore.instance.collection('tarla_hasatlari').doc(id.toString()).set({
          ...veri,
          'sql_id': id,
          'is_synced': 1,
          'kayit_anlik': FieldValue.serverTimestamp(),
        });

        // 3. Buluta yazma başarılıysa bayrağı 1 yap
        await db.update(
            'tarla_hasatlari',
            {'is_synced': 1},
            where: 'id = ?',
            whereArgs: [id]
        );
        print("✅ Mobil: Senkronizasyon tamamlandı.");
      } catch (e) {
        print("⚠️ Mobil: Firebase'e o an ulaşılamadı (İnternet?), sonra senkron edilecek.");
      }

      return id;
    } catch (e) {
      print("❌ Mobil Genel Hata: $e");
      return 0;
    }
  }

  Future<int> hasatGuncelle(dynamic id, Map<String, dynamic> row) async {
    print("\n--- 🌾 HASAT KAYDI GÜNCELLENİYOR (ID: $id) ---");

    // --- WEB İÇİN: DOĞRUDAN FIREBASE GÜNCELLEME ---
    if (kIsWeb) {
      try {
        print("🌐 Web: Hasat verileri bulutta güncelleniyor...");
        // 'is_synced' web'de anlamsız olduğu için temizliyoruz
        Map<String, dynamic> fireVeri = Map.from(row)..remove('is_synced');

        await FirebaseFirestore.instance
            .collection('tarla_hasatlari')
            .doc(id.toString())
            .set(fireVeri, SetOptions(merge: true));

        print("✅ Web: Güncelleme buluta başarıyla yansıtıldı.");
        return 1;
      } catch (e) {
        print("❌ Web Güncelleme Hatası: $e");
        return 0;
      }
    }

    // --- MOBİL İÇİN: SQLite + FIREBASE SENKRONU ---
    try {
      final db = await instance.database;

      // 1. Yerelde bayrağı sıfıra çek ve güncelle
      row['is_synced'] = 0;
      int res = await db.update(
          'tarla_hasatlari',
          row,
          where: 'id = ?',
          whereArgs: [id]
      );
      print("🚀 Mobil: Yerel kayıt 'senkron bekleniyor' moduna alındı.");

      try {
        // 2. Firebase tarafına gönder (is_synced hariç)
        Map<String, dynamic> fireVeri = Map.from(row)..remove('is_synced');

        await FirebaseFirestore.instance
            .collection('tarla_hasatlari')
            .doc(id.toString())
            .set(fireVeri, SetOptions(merge: true));

        // 3. Bulut güncellemesi bittiyse bayrağı tekrar 1 yap
        await db.update(
            'tarla_hasatlari',
            {'is_synced': 1},
            where: 'id = ?',
            whereArgs: [id]
        );
        print("✅ Mobil: Yerel ve bulut senkronizasyonu tamamlandı.");
      } catch (e) {
        print("⚠️ Mobil: Firebase'e ulaşılamadı, kayıt yerelde '0' olarak kaldı: $e");
      }

      return res;
    } catch (e) {
      print("❌ Mobil Genel Güncelleme Hatası: $e");
      return 0;
    }
  }


  Future<void> musteriHareketEkleVeyaGuncelle(Map<String, dynamic> veri) async {
    print("\n--- 👥 MÜŞTERİ HAREKETİ KONTROLÜ (ID: ${veri['firebase_id']}) ---");

    // --- WEB İÇİN: ZATEN DOĞRUDAN FIREBASE KULLANILIYOR ---
    if (kIsWeb) {
      try {
        // Web'de SQLite olmadığı için doğrudan Firebase'e 'set' (merge ile) yapıyoruz
        await FirebaseFirestore.instance
            .collection('musteri_hareketleri')
            .doc(veri['firebase_id'].toString())
            .set(veri, SetOptions(merge: true));
        print("✅ Web: Kayıt bulutta güncellendi/eklendi.");
      } catch (e) {
        print("❌ Web Hata: $e");
      }
      return;
    }

    // --- MOBİL İÇİN: SQLite MÜKERRER KONTROLÜ ---
    try {
      final db = await instance.database;

      // 1. firebase_id üzerinden bu kayıt SQL'de var mı bak
      final varMi = await db.query(
          'musteri_hareketleri',
          where: 'firebase_id = ?',
          whereArgs: [veri['firebase_id']]
      );

      if (varMi.isEmpty) {
        // 2. Eğer yoksa YENİ KAYIT ekle
        await db.insert('musteri_hareketleri', veri);
        print("✅ Mobil: Yeni kayıt yerel deftere işlendi.");
      } else {
        // 3. Eğer varsa MÜKERRERDİR, üzerine yaz (Update)
        // Bu sayede bulutta değişen bir şey varsa yerel de güncellenir.
        await db.update(
            'musteri_hareketleri',
            veri,
            where: 'firebase_id = ?',
            whereArgs: [veri['firebase_id']]
        );
        print("🔄 Mobil: Bu kayıt zaten vardı, veriler güncellendi.");
      }

      // 4. Firebase yedekleme (Garantiye almak için)
      await FirebaseFirestore.instance
          .collection('musteri_hareketleri')
          .doc(veri['firebase_id'].toString())
          .set(veri, SetOptions(merge: true));

    } catch (e) {
      print("❌ Mobil Kayıt Hatası: $e");
    }
  }

  Future<void> musteriHareketGuncelle(
      dynamic hareketId,
      dynamic musteriId,
      double yeniTutar,
      double eskiTutar
      ) async {
    print("\n--- 💸 MÜŞTERİ HAREKETİ VE BAKİYE DÜZELTME BAŞLATILDI ---");

    // Hesap: Yeni Tutar - Eski Tutar = Fark.
    double fark = yeniTutar - eskiTutar;

    // --- WEB İÇİN: FIREBASE ATOMIC BATCH ---
    if (kIsWeb) {
      try {
        print("🌐 Web: Hareket ve müşteri bakiyesi bulutta güncelleniyor...");
        WriteBatch batch = FirebaseFirestore.instance.batch();

        // 1. Hareket kaydını güncelle
        DocumentReference hareketRef = FirebaseFirestore.instance
            .collection('musteri_hareketleri')
            .doc("HL_$hareketId");

        batch.update(hareketRef, {
          'tutar': yeniTutar,
          'senkronize ediliyor': 0
        });

        // 2. Müşteri bakiyesini düzelt
        DocumentReference musteriRef = FirebaseFirestore.instance
            .collection('musteriler')
            .doc(musteriId.toString());

        batch.update(musteriRef, {
          'bakiye': FieldValue.increment(fark),
        });

        await batch.commit();
        print("✅ Web: Hareket güncellendi, bakiye farkı ($fark) yansıtıldı.");
        return;
      } catch (e) {
        print("❌ Web Güncelleme Hatası: $e");
        return;
      }
    }

    // --- MOBİL İÇİN: SQLite TRANSACTION + FIREBASE SENKRONU ---
    try {
      final db = await instance.database;

      await db.transaction((txn) async {
        // 1. Yerel Hareketi Güncelle
        await txn.update(
          'musteri_hareketleri',
          {'tutar': yeniTutar},
          where: 'id = ?',
          whereArgs: [hareketId],
        );

        // 2. Yerel Müşteri Bakiyesini Düzelt (TC veya ID üzerinden)
        await txn.execute(
            "UPDATE musteriler SET bakiye = bakiye + ? WHERE id = ? OR tc = ?",
            [fark, musteriId, musteriId]
        );

        print("🚀 Mobil: Yerel SQLite güncellendi, fark: $fark");

        // 3. Firebase Senkronu (Bulutu anında güncelle)
        try {
          await FirebaseFirestore.instance
              .collection('musteri_hareketleri')
              .doc("HL_$hareketId")
              .update({
            'tutar': yeniTutar,
            'senkronize ediliyor': 0
          });

          await FirebaseFirestore.instance
              .collection('musteriler')
              .doc(musteriId.toString())
              .update({
            'bakiye': FieldValue.increment(fark),
          });

          print("☁️ Mobil: Firebase senkronu başarılı.");
        } catch (fbError) {
          print("⚠️ Mobil: Bulut senkronu aksadı (İnternet?), yerel işlem tamam.");
        }
      });

    } catch (e) {
      print("❌ Mobil Veritabanı Hatası: $e");
      throw e;
    }
  }
  Future<int> musteriTumHareketleriniSil(String musteriId) async {
    final db = await instance.database;
    return await db.delete(
      'musteri_hareketleri',
      where: 'musteri_id = ?',
      whereArgs: [musteriId],
    );
  }

  Future<dynamic> musteriHareketiEkle(Map<String, dynamic> veri) async {
    print("\n--- 👥 MÜŞTERİ HAREKETİ KAYDI BAŞLADI ---");

    // --- WEB İÇİN: FIREBASE ÜZERİNDEN KONTROL VE KAYIT ---
    if (kIsWeb) {
      try {
        print("🌐 Web: Mükerrer kayıt kontrolü bulutta yapılıyor...");

        // Firebase'de aynı müşteri, tarih ve tutarda kayıt var mı?
        final snapshot = await FirebaseFirestore.instance
            .collection('musteri_hareketleri')
            .where('musteri_id', isEqualTo: veri['musteri_id'])
            .where('tarih', isEqualTo: veri['tarih'])
            .where('tutar', isEqualTo: veri['tutar'])
            .get();

        if (snapshot.docs.isNotEmpty) {
          print("⚠️ Web: Bu kayıt bulutta zaten var! Engellendi.");
          return -1;
        }

        // Yeni kayıt ekleme ve Bakiye güncelleme (Batch İşlemi)
        WriteBatch batch = FirebaseFirestore.instance.batch();
        DocumentReference hareketRef = FirebaseFirestore.instance.collection('musteri_hareketleri').doc();

        batch.set(hareketRef, {
          ...veri,
          'firebase_id': hareketRef.id,
          'kayit_tarihi': FieldValue.serverTimestamp(),
        });

        // Müşteri bakiyesini güncelle
        DocumentReference musteriRef = FirebaseFirestore.instance.collection('musteriler').doc(veri['musteri_id'].toString());
        batch.update(musteriRef, {'bakiye': FieldValue.increment(veri['tutar'])});

        await batch.commit();
        return hareketRef.id;
      } catch (e) {
        print("❌ Web Hata: $e");
        return -1;
      }
    }

    // --- MOBİL İÇİN: SQLite + FIREBASE SENKRONU ---
    try {
      final db = await instance.database;

      // 1. ADIM: Mükerrer Kontrolü (Senin Dedektif)
      final mukerrerKontrol = await db.query(
          'musteri_hareketleri',
          where: 'musteri_id = ? AND tarih = ? AND tutar = ?',
          whereArgs: [veri['musteri_id'], veri['tarih'], veri['tutar']]
      );

      if (mukerrerKontrol.isNotEmpty) {
        print("⚠️ Mobil: Bu kayıt sistemde var! Mükerrer işlem engellendi.");
        return -1;
      }

      // 2. ADIM: SQLite İşlemleri (Hareket Ekle + Bakiye Güncelle)
      int id = -1;
      await db.transaction((txn) async {
        id = await txn.insert('musteri_hareketleri', veri);

        // Müşteri bakiyesini otomatik artır
        await txn.execute(
            "UPDATE musteriler SET bakiye = bakiye + ? WHERE id = ?",
            [veri['tutar'], veri['musteri_id']]
        );
      });

      // 3. ADIM: Firebase Senkronu
      try {
        String docId = "HL_$id"; // Hareket Log ID formatı
        await FirebaseFirestore.instance.collection('musteri_hareketleri').doc(docId).set({
          ...veri,
          'firebase_id': docId,
          'kayit_tarihi': FieldValue.serverTimestamp(),
        });

        // Bulut bakiyesini de güncelle
        await FirebaseFirestore.instance.collection('musteriler').doc(veri['musteri_id'].toString()).update({
          'bakiye': FieldValue.increment(veri['tutar']),
        });

        print("✅ Mobil: Kayıt ve bakiye hem yerelde hem bulutta güncellendi.");
      } catch (e) {
        print("⚠️ Mobil: Bulut senkronu yapılamadı (İnternet?), yerel işlem tamam.");
      }

      return id;
    } catch (e) {
      print("❌ Mobil Genel Hata: $e");
      return -1;
    }
  }


// Yardımcı Metod: Mobilde arka planda bulut temizliği ve borç düzeltmesi yapar
  Future<void> _firebaseHareketSil(dynamic id, dynamic firmaId, double? tutar) async {
    // Web tarafında bu metod genellikle ana fonksiyonun içinde Batch ile halledilir,
    // ama her ihtimale karşı hata kontrolünü sıkı tutuyoruz.
    try {
      print("☁️ Firebase: Arka plan temizlik işlemi başlatıldı (ID: $id)...");

      WriteBatch batch = FirebaseFirestore.instance.batch();

      // 1. Tarla hareketini buluttan sil
      DocumentReference hareketRef = FirebaseFirestore.instance
          .collection('tarla_hareketleri')
          .doc(id.toString());
      batch.delete(hareketRef);

      // 2. Eğer firmaya bağlı bir borç varsa, o borcu geri düş
      if (firmaId != null && firmaId != 0 && tutar != null) {
        DocumentReference firmaRef = FirebaseFirestore.instance
            .collection('ciftclik_firmalari')
            .doc(firmaId.toString());

        batch.update(firmaRef, {
          'borc': FieldValue.increment(-tutar), // Eksilterek borcu düzeltir
        });
        print("💰 Firebase: Firma borcu düşürülüyor (-$tutar TL)");
      }

      // Paketi fırına veriyoruz
      await batch.commit();
      print("✅ Firebase: Arka plan senkronu ve bakiye düzeltme başarılı.");

    } catch (e) {
      // Burası patlasa bile yerel hafızadan (SQLite) silindiği için
      // kullanıcıya hata hissettirmeyiz, sadece loglara yazarız.
      print("⚠️ Firebase Arka Plan Silme Hatası: $e");
    }
  }

  Future<List<Map<String, dynamic>>> cekSenetListesiGetir() async {
    print("\n--- 🏦 ÇEK/SENET PORTFÖYÜ LİSTELENİYOR ---");

    // --- WEB İÇİN: DOĞRUDAN FIREBASE ---
    if (kIsWeb) {
      try {
        print("🌐 Web: Evraklar buluttan çekiliyor...");
        final snapshot = await FirebaseFirestore.instance
            .collection('portfoy_evraklari')
            .orderBy('vade_tarihi', descending: false) // Vadesi en yakın olan en üste
            .get();

        if (snapshot.docs.isNotEmpty) {
          return snapshot.docs.map((doc) => {
            'id': doc.id,
            ...doc.data(),
          }).toList();
        }
        return [];
      } catch (e) {
        print("❌ Web Evrak Liste Hatası: $e");
        return [];
      }
    }

    // --- MOBİL İÇİN: ÖNCE BULUT, SONRA YEREL ---
    try {
      print("📱 Mobil: Güncel portföy için Firebase kontrol ediliyor...");
      final snapshot = await FirebaseFirestore.instance
          .collection('portfoy_evraklari')
          .orderBy('vade_tarihi', descending: false)
          .get();

      if (snapshot.docs.isNotEmpty) {
        print("✅ Mobil: Portföy buluttan tazelendi.");
        return snapshot.docs.map((doc) => doc.data()).toList();
      }
    } catch (e) {
      print("⚠️ Mobil: Firebase'e ulaşılamadı (İnternet?), yerel hafızaya bakılıyor...");
    }

    // Firebase'e ulaşılamazsa veya boşsa SQLite'dan çek
    try {
      final db = await instance.database;
      // Yerel tablondaki isim farklılıklarına dikkat ederek çekiyoruz
      final res = await db.query('cekler', orderBy: 'vadeTarihi ASC');
      print("🚀 Mobil: Yerel hafızadan ${res.length} evrak getirildi.");
      return res;
    } catch (e) {
      print("❌ Mobil SQLite Hata: $e");
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> musteriListesiGetir() async {
    print("\n--- 👥 MÜŞTERİ LİSTESİ VE BAKİYE ANALİZİ BAŞLADI ---");

    // --- WEB İÇİN: FIREBASE ÜZERİNDEN HESAPLAMA ---
    if (kIsWeb) {
      try {
        print("🌐 Web: Müşteri verileri ve bakiyeler buluttan çekiliyor...");
        final snapshot = await FirebaseFirestore.instance
            .collection('musteriler')
            .orderBy('ad')
            .get();

        // Web'de SQL'deki JOIN/SUM mantığını kod tarafında simüle ediyoruz
        if (snapshot.docs.isNotEmpty) {
          return snapshot.docs.map((doc) {
            final data = doc.data();
            // Web tarafında bakiye hesaplanan alanını hazır bakiye olarak döneriz
            // (Web'de bu hesaplamalar genellikle Cloud Functions ile yapılır)
            return {
              'id': doc.id,
              ...data,
              'bakiye_hesaplanan': data['bakiye'] ?? 0.0,
              'sube_guncel': data['sube'] ?? 'Merkez',
            };
          }).toList();
        }
        return [];
      } catch (e) {
        print("❌ Web Müşteri Liste Hatası: $e");
        return [];
      }
    }

    // --- MOBİL İÇİN: SQLite GÜCÜ ---
    try {
      final db = await instance.database;
      print("🚀 Mobil: SQLite üzerinden kompleks bakiye hesabı yapılıyor...");

      // Senin yazdığın o meşhur Query:
      final res = await db.rawQuery('''
      SELECT 
        m.*, 
        IFNULL(
          (m.bakiye + 
            IFNULL((SELECT SUM(satis_fiyati) FROM satislar WHERE musteri_ad = m.ad), 0) - 
            IFNULL((SELECT SUM(miktar) FROM tahsilatlar WHERE ciftci_ad = m.ad), 0)
          ), m.bakiye
        ) as bakiye_hesaplanan,
        IFNULL(
          (SELECT sube FROM satislar WHERE musteri_ad = m.ad ORDER BY id DESC LIMIT 1), 
          m.sube
        ) as sube_guncel
      FROM musteriler m
      ORDER BY m.ad ASC
    ''');

      print("✅ Mobil: ${res.length} müşteri ve güncel bakiye verisi getirildi.");
      return res;
    } catch (e) {
      print("❌ Mobil SQLite Hata: $e");
      return [];
    }
  }

  Future<void> musteriEkle(Map<String, dynamic> m) async {
    print("\n--- 👥 MÜŞTERİ KAYIT / GÜNCELLEME BAŞLATILDI ---");

    // 1. ADIM: İSİM NORMALİZASYONU
    final String adNorm = normalizeAd(m['ad'] ?? '');

    // 2. ADIM: SABİT ID OLUŞTURMA (TC > TEL > ID)
    // Bu ID dükkanın tapusu gibidir, asla değişmez.
    String sabitId = (m['tc'] ?? '').toString().trim();
    if (sabitId.isEmpty) {
      sabitId = (m['tel'] ?? '').toString().trim();
    }
    if (sabitId.isEmpty) {
      sabitId = DateTime.now().millisecondsSinceEpoch.toString();
    }

    // Veriyi paketleyelim
    final Map<String, dynamic> veri = {
      'id': sabitId,
      'ad': adNorm,
      'ad_norm': adNorm,
      'tc': m['tc'] ?? '',
      'tel': m['tel'] ?? '',
      'adres': m['adres'] ?? '',
      'sube': m['sube'] ?? 'TEFENNİ',
      'bakiye': double.tryParse(m['bakiye']?.toString() ?? "0.0") ?? 0.0,
      'is_synced': 1,
    };

    // --- WEB İÇİN: FIREBASE ÜZERİNDEN UPSERT ---
    if (kIsWeb) {
      try {
        print("🌐 Web: Müşteri bulutta kontrol ediliyor...");
        await FirebaseFirestore.instance
            .collection('musteriler')
            .doc(sabitId)
            .set(veri, SetOptions(merge: true));
        print("✅ Web: Müşteri mühürlendi (ID: $sabitId)");
        return;
      } catch (e) {
        print("❌ Web Hata: $e");
        return;
      }
    }

    // --- MOBİL İÇİN: SQLite TRANSACTION + FIREBASE ---
    try {
      final db = await instance.database;

      await db.transaction((txn) async {
        // 3. ADIM: ÖNCE SQL KONTROLÜ
        final existing = await txn.query('musteriler', where: 'id = ?', whereArgs: [sabitId]);

        if (existing.isEmpty) {
          // SQL'de yoksa YENİ KAYIT
          await txn.insert(
            'musteriler',
            veri,
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
          print("✅ Mobil SQL: Yeni müşteri eklendi.");
        } else {
          // SQL'de varsa GÜNCELLE (Mükerrerliği önleyen can damarı)
          await txn.update('musteriler', veri, where: 'id = ?', whereArgs: [sabitId]);
          print("🔄 Mobil SQL: Kayıt zaten var, bilgiler güncellendi.");
        }
      });

      // 4. ADIM: FIREBASE GARANTİSİ
      try {
        await FirebaseFirestore.instance
            .collection('musteriler')
            .doc(sabitId)
            .set(veri, SetOptions(merge: true));
        print("🔥 Firebase: Senkronizasyon tamam.");
      } catch (fbError) {
        print("⚠️ Mobil: Firebase'e o an yazılamadı, yerel işlem tamam.");
      }

    } on DatabaseException catch (e) {
      if (e.isUniqueConstraintError()) {
        print("🚫 DUPLICATE: Bu ID ile başka bir kayıt zaten var.");
      } else {
        rethrow;
      }
    } catch (e) {
      print("❌ HATA: musteriEkle sırasında bir problem oluştu: $e");
    }
  }

  Future<void> musteriGuncelle(dynamic id, Map<String, dynamic> veri) async {
    print("\n--- 👥 MÜŞTERİ BİLGİLERİ GÜNCELLENİYOR (ID: $id) ---");

    // 🔒 1. SAFE ID
    final String safeId = id.toString().trim();

    // 🧠 2. Veri kopyala
    Map<String, dynamic> guncelVeri = Map.from(veri);

    // 🧼 3. İsim normalizasyon
    if (guncelVeri.containsKey('ad')) {
      guncelVeri['ad'] = normalizeAd(guncelVeri['ad']);
      guncelVeri['ad_norm'] = guncelVeri['ad'];
    }

    // ❌ ID ASLA UPDATE EDİLMEZ
    guncelVeri.remove('id');

    // 🔥 4. WEB
    if (kIsWeb) {
      try {
        await FirebaseFirestore.instance
            .collection('musteriler')
            .doc(safeId)
            .set(guncelVeri, SetOptions(merge: true));

        print("✅ Web: Müşteri güncellendi");
        return;
      } catch (e) {
        print("❌ Web Hata: $e");
        return;
      }
    }

    // 📱 5. MOBİL
    try {
      final db = await instance.database;

      await db.transaction((txn) async {

        // 🟡 5.1 SQLite update
        int result = await txn.update(
          'musteriler',
          guncelVeri,
          where: 'id = ?',
          whereArgs: [safeId],
        );

        if (result == 0) {
          print("⚠️ Lokal kayıt bulunamadı, insert yapılabilir.");
        }
      });

      // ☁️ 6. FIREBASE SYNC
      try {
        await FirebaseFirestore.instance
            .collection('musteriler')
            .doc(safeId)
            .set(guncelVeri, SetOptions(merge: true));

        // ✔ sync başarılı
        final db = await instance.database;
        await db.update(
          'musteriler',
          {'is_synced': 1},
          where: 'id = ?',
          whereArgs: [safeId],
        );

        print("✅ Mobil + Firebase sync OK");

      } catch (fbError) {
        print("⚠️ Firebase offline, sync beklemede");

        final db = await instance.database;
        await db.update(
          'musteriler',
          {'is_synced': 0},
          where: 'id = ?',
          whereArgs: [safeId],
        );
      }

    } catch (e) {
      print("❌ Mobil Genel Hata: $e");
    }
  }

  Future<double> musteriBorcuGetir(String musteriId) async {
    final String safeId = musteriId.toString().trim();

    print("\n--- 🧮 BAKİYE HESAPLANIYOR (Müşteri ID: $safeId) ---");

    double toplamSatis = 0.0;
    double toplamTahsilat = 0.0;
    double acilisBakiyesi = 0.0;

    try {

      // ======================================================
      // 🌐 WEB + MOBİL ORTAK (FIRESTORE TEK KAYNAK)
      // ======================================================
      if (kIsWeb) {
        var hareketler = await FirebaseFirestore.instance
            .collection('musteri_hareketleri')
            .where('musteri_id', isEqualTo: safeId)
            .get();

        for (var doc in hareketler.docs) {
          final data = doc.data();

          final String islem = (data['islem'] ?? '').toString();
          final double tutar = double.tryParse(data['tutar'].toString()) ?? 0.0;

          if (islem == 'SATIS') {
            toplamSatis += tutar;
          } else if (islem == 'TAHSILAT') {
            toplamTahsilat += tutar;
          }
        }

        // Açılış bakiyesi (müşteri kartı)
        var mDoc = await FirebaseFirestore.instance
            .collection('musteriler')
            .doc(safeId)
            .get();

        if (mDoc.exists) {
          acilisBakiyesi =
              double.tryParse(mDoc['bakiye']?.toString() ?? '0') ?? 0.0;
        }

      } else {

        // ======================================================
        // 📱 SQLITE (TEK KAYNAK MANTIK)
        // ======================================================

        final db = await instance.database;

        // SATIŞ + TAHSİLAT TEK TABLODAN (EĞER VARSA)
        var hareketler = await db.query(
          'musteri_hareketleri',
          where: 'musteri_id = ?',
          whereArgs: [safeId],
        );

        for (var row in hareketler) {
          final String islem = (row['islem'] ?? '').toString();
          final double tutar = double.tryParse(row['tutar'].toString()) ?? 0.0;

          if (islem == 'SATIS') {
            toplamSatis += tutar;
          } else if (islem == 'TAHSILAT') {
            toplamTahsilat += tutar;
          }
        }

        // Açılış bakiyesi
        var mQuery = await db.query(
          'musteriler',
          columns: ['bakiye'],
          where: 'id = ?',
          whereArgs: [safeId],
        );

        if (mQuery.isNotEmpty) {
          acilisBakiyesi =
              double.tryParse(mQuery.first['bakiye'].toString()) ?? 0.0;
        }
      }

      // ======================================================
      // 💣 NET BORÇ FORMÜLÜ
      // ======================================================
      double sonuc = (toplamSatis + acilisBakiyesi) - toplamTahsilat;

      print("📊 SATIŞ: $toplamSatis");
      print("📊 TAHSİLAT: $toplamTahsilat");
      print("📊 AÇILIŞ: $acilisBakiyesi");
      print("💰 NET BORÇ: $sonuc");

      return sonuc;

    } catch (e) {
      print("❌ BAKİYE HESAP HATASI: $e");
      return 0.0;
    }
  }


  Future<int> musteriUpsert(Map<String, dynamic> m) async {

    // ======================================================
    // 🆔 1. STABLE ID (TEK KAYNAK)
    // ======================================================
    String mId = (m['id'] ?? '').toString().trim();

    if (mId.isEmpty) {
      mId = (m['tc'] ?? '').toString().trim();
    }

    if (mId.isEmpty) {
      mId = (m['tel'] ?? '').toString().trim();
    }

    if (mId.isEmpty) {
      mId = DateTime.now().millisecondsSinceEpoch.toString();
    }

    String subeTespit =
    (m['sube'] ?? m['alt'] ?? 'TEFENNİ').toString().toUpperCase();

    // ======================================================
    // 🧼 2. VERİ TEMİZLEME
    // ======================================================
    Map<String, dynamic> temizVeri = {
      'id': mId,
      'ad': normalizeAd(m['ad'] ?? m['reklam'] ?? 'İSİMSİZ'),
      'tc': (m['tc'] ?? '').toString(),
      'tel': (m['tel'] ?? m['phone'] ?? '').toString(),
      'adres': (m['adres'] ?? '').toString(),
      'sube': subeTespit,
      'bakiye': double.tryParse(m['bakiye']?.toString() ?? '0') ?? 0.0,
      'is_synced': 1,
    };

    try {

      // ======================================================
      // 🌐 WEB
      // ======================================================
      if (kIsWeb) {
        await FirebaseFirestore.instance
            .collection('musteriler')
            .doc(mId)
            .set(temizVeri, SetOptions(merge: true));

        return 1;
      }

      // ======================================================
      // 📱 MOBİL SQLITE UPSERT
      // ======================================================
      final db = await instance.database;

      int result = await db.insert(
        'musteriler',
        temizVeri,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      // ======================================================
      // ☁️ FIREBASE BACKGROUND SYNC (SAFE)
      // ======================================================
      try {
        await FirebaseFirestore.instance
            .collection('musteriler')
            .doc(mId)
            .set(temizVeri, SetOptions(merge: true));
      } catch (e) {
        // offline olabilir → sorun değil
        await db.update(
          'musteriler',
          {'is_synced': 0},
          where: 'id = ?',
          whereArgs: [mId],
        );
      }

      return result;

    } catch (e) {
      print("❌ musteriUpsert HATA: $e");
      return 0;
    }
  }


  Future<Map<String, dynamic>> genelRaporGetir() async {
    print("\n--- 📊 GENEL DURUM RAPORU HAZIRLANIYOR ---");
    int stokSayisi = 0;
    double toplamTahsilat = 0.0;
    int aktifArac = 0;

    try {
      // Firebase'den güncel veriler
      final stokSnapshot = await FirebaseFirestore.instance.collection('stoklar').get();
      final tahsilatSnapshot = await FirebaseFirestore.instance.collection('tahsilatlar').get();
      final galeriSnapshot = await FirebaseFirestore.instance.collection('araclar').where('durum', isNotEqualTo: 'Satıldı').get();

      stokSayisi = stokSnapshot.docs.length;
      aktifArac = galeriSnapshot.docs.length;
      for (var doc in tahsilatSnapshot.docs) {
        toplamTahsilat += double.tryParse(doc.data()['miktar'].toString()) ?? 0.0;
      }
    } catch (e) {
      print("⚠️ Rapor: İnternet yok, SQLite üzerinden hesaplanıyor...");
      final db = await instance.database;
      stokSayisi = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM stoklar')) ?? 0;
      var tQuery = await db.rawQuery('SELECT SUM(miktar) as toplam FROM tahsilatlar');
      toplamTahsilat = double.tryParse(tQuery.first['toplam'].toString()) ?? 0.0;
      aktifArac = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM araclar WHERE durum != "Satıldı"')) ?? 0;
    }

    return {
      'stok_sayisi': stokSayisi,
      'toplam_tahsilat': toplamTahsilat,
      'aktif_arac': aktifArac,
      'guncelleme_tarihi': DateTime.now().toString(),
    };
  }

  // --- GALERİ SATIŞ YAP (HEM YEREL HEM BULUT) ---
  Future<void> galeriSatisYap({required Map<String, dynamic> veri}) async {
    print("\n--- 🏎️ GALERİ SATIŞ İŞLEMİ BAŞLATILDI ---");

    // Web kontrolü
    if (kIsWeb) {
      try {
        await FirebaseFirestore.instance.collection('satislar').add(veri);
        if (veri.containsKey('arac_id')) {
          await FirebaseFirestore.instance
              .collection('araclar') // ❌ 'galeri' idi, 'araclar' yaptık
              .doc(veri['arac_id'].toString())
              .update({'durum': 'SATILDI'}); // Durumu büyük harf yapmakta fayda var
        }
        print("✅ Web: Satış buluta işlendi.");
      } catch (e) {
        print("❌ Web Satış Hatası: $e");
      }
      return;
    }

    // Mobil (SQLite) İşlemi
    try {
      final db = await instance.database;

      await db.transaction((txn) async {
        // 1. Satış kaydını ekle (Tablo adının 'satislar' olduğundan emin ol)
        await txn.insert("satislar", veri);

        // 2. Araç tablosunda durum güncellemesi
        if (veri.containsKey('arac_id')) {
          await txn.update(
              'araclar', // ❌ BURASI HATALIYDI: 'galeri' olan yeri 'araclar' yaptık
              {'durum': 'SATILDI'},
              where: 'id = ?',
              whereArgs: [veri['arac_id']]
          );
        }
      });

      // 3. Firebase Senkronu
      try {
        await FirebaseFirestore.instance.collection('satislar').add(veri);
        print("☁️ Mobil: Satış buluta yedeklendi.");
      } catch (e) {
        print("⚠️ Mobil: Satış yerelde kaydedildi ancak buluta gönderilemedi.");
      }

    } catch (e) {
      print("❌ Mobil Satış Hatası: $e");
      throw e;
    }
  }

// --- 1. BİÇER EKSTREYE HAREKET EKLEME ---
  Future<void> bicerekstreyeHareketEkle({
    required String musteriAd,
    required String islem,
    required double tutar,
    required String tarih,
  }) async {
    final veri = {
      'musteri_ad': musteriAd.trim().toUpperCase(),
      'islem': islem,
      'tutar': tutar,
      'tarih': tarih,
      'is_synced': kIsWeb ? 1 : 0,
    };

    if (kIsWeb) {
      await FirebaseFirestore.instance
          .collection('bicermusteri_hareketleri')
          .add(veri);
    } else {
      final db = await instance.database;
      await db.insert('bicermusteri_hareketleri', veri);
    }
  }



  // ✅ TUTARLARIN 0 GELMESİ DÜZELTİLDİ - PDF VE VERİTABANI İLE TAM UYUMLU
  Future<List<Map<String, dynamic>>> bicerMusteriHareketleriGetir(String isim, String secilenSezon) async {
    String temizIsim = isim.trim().toUpperCase();
    List<Map<String, dynamic>> tumHareketler = [];

    if (kIsWeb) {
      try {
        // WEB: Firestore üzerinden görseldeki gerçek isimlerle çekiyoruz
        var hareketSnap = await FirebaseFirestore.instance
            .collection('bicermusteri_hareketleri')
            .where('ciftci_ad', isEqualTo: temizIsim)
            .where('sezon', isEqualTo: secilenSezon)
            .get();

        for (var doc in hareketSnap.docs) {
          var data = doc.data();
          tumHareketler.add({
            'id': doc.id,
            'aciklama': data['aciklama'] ?? "İŞLEM", // PDF'in beklediği anahtar
            'miktar': double.tryParse(data['miktar']?.toString() ?? '0') ?? 0.0, // PDF'in beklediği anahtar
            'tarih': data['tarih'] ?? '',
            'tip': data['tip'] ?? 'HASAT', // PDF'in beklediği anahtar
            'dekar': data['dekar'] ?? '0',
            'urun_tipi': data['urun_tipi'],
            'is_synced': 1,
          });
        }
      } catch (e) {
        debugPrint("❌ Web Hareket Hatası: $e");
      }
    } else {
      // --- MOBİL (SQLite) ---
      final db = await instance.database;

      // Görseldeki şemaya göre miktar, tip ve aciklama alanlarını çekiyoruz
      // SQLite'dan gelen veriler zaten 'miktar', 'tip', 'aciklama' anahtarlarıyla geliyor.
      final List<Map<String, dynamic>> sqliteHareketler = await db.query(
        'bicermusteri_hareketleri',
        where: 'UPPER(ciftci_ad) = ? AND sezon = ?',
        whereArgs: [temizIsim, secilenSezon],
        orderBy: 'tarih DESC',
      );

      // SQLite verisini Map listesine çevirirken tiplerin doğruluğundan emin oluyoruz
      tumHareketler = sqliteHareketler.map((e) => Map<String, dynamic>.from(e)).toList();
    }

    // Tarih sıralaması (Yeni tarihler her zaman en üstte)
    tumHareketler.sort((a, b) => (b['tarih'] ?? '').toString().compareTo((a['tarih'] ?? '').toString()));

    return tumHareketler;
  }

  // DatabaseHelper sınıfının içine yapıştır
  Future<void> bicerHareketSil(dynamic id) async {
    if (kIsWeb) {
      await FirebaseFirestore.instance.collection('bicermusteri_hareketleri').doc(id).delete();
    } else {
      final db = await instance.database;
      await db.delete('bicermusteri_hareketleri', where: 'id = ?', whereArgs: [id]);
    }
  }




  // --- 3. ÖZEL SQL ÇALIŞTIRICI ---
  Future<int> customInsert(String query, List<dynamic> arguments) async {
    final db = await instance.database;
    return await db.rawInsert(query, arguments);
  }


  // --- PERSONEL EKLE ---
  Future<void> personelEkle(Map<String, dynamic> veri) async {
    if (kIsWeb) {
      await FirebaseFirestore.instance.collection('personel').doc(veri['id']).set(veri);
      return;
    }
    final db = await instance.database;
    await db.insert('personel', veri);
    try {
      await FirebaseFirestore.instance.collection('personel').doc(veri['id']).set(veri);
      await db.update('personel', {'is_synced': 1}, where: 'id = ?', whereArgs: [veri['id']]);
    } catch (e) { print("☁️ Firebase Hatası: $e"); }
  }

// --- PERSONEL SİL (TAM TEMİZLİK) ---
  Future<int> personelSil(String id) async {
    if (kIsWeb) {
      await FirebaseFirestore.instance.collection('personel').doc(id).delete();
      return 1;
    }
    final db = await instance.database;
    await db.delete('personel_hareketleri', where: 'personel_id = ?', whereArgs: [id]);
    int sonuc = await db.delete('personel', where: 'id = ?', whereArgs: [id]);
    try {
      await FirebaseFirestore.instance.collection('personel').doc(id).delete();
    } catch (e) { print("☁️ Firebase Silme Hatası: $e"); }
    return sonuc;
  }
  Future<void> personelHareketEkle(Map<String, dynamic> hareket) async {
    print("\n--- 💸 PERSONEL HAREKETİ İŞLENİYOR ---");

    if (kIsWeb) {
      WriteBatch batch = FirebaseFirestore.instance.batch();
      batch.set(FirebaseFirestore.instance.collection('personel_hareketleri').doc(hareket['id']), hareket);
      batch.update(FirebaseFirestore.instance.collection('personel').doc(hareket['personel_id']), {
        'bakiye': FieldValue.increment(hareket['tutar']),
      });
      await batch.commit();
      return;
    }

    final db = await instance.database;
    await db.insert('personel_hareketleri', hareket);
    await db.rawUpdate('UPDATE personel SET bakiye = bakiye + ? WHERE id = ?', [hareket['tutar'], hareket['personel_id']]);

    try {
      await FirebaseFirestore.instance.collection('personel_hareketleri').doc(hareket['id']).set(hareket);
      await FirebaseFirestore.instance.collection('personel').doc(hareket['personel_id']).update({
        'bakiye': FieldValue.increment(hareket['tutar']),
      });
    } catch (e) { print("⚠️ Bulut senkronu internet gelince hallolacak."); }
  }
// --- PERSONEL LİSTESİ (WEB & MOBİL UYUMLU) ---
  Future<List<Map<String, dynamic>>> personelListesiGetir() async {
    if (kIsWeb) {
      try {
        final snapshot = await FirebaseFirestore.instance.collection('personel').get();
        return snapshot.docs.map((doc) {
          Map<String, dynamic> data = doc.data();
          data['id'] = doc.id;
          return data;
        }).toList();
      } catch (e) {
        print("Web personel çekme hatası: $e");
        return [];
      }
    } else {
      final db = await instance.database;
      return await db.query('personel', orderBy: 'ad ASC');
    }
  }

  // --- PERSONEL GÜNCELLEME ---
  Future<void> personelGuncelle(String id, Map<String, dynamic> v) async {
    if (!kIsWeb) {
      final db = await instance.database;
      await db.update('personel', v, where: 'id = ?', whereArgs: [id]);
    }
    try {
      await FirebaseFirestore.instance.collection('personel').doc(id).update(v);
      print("✅ Personel hem yerelde hem bulutta güncellendi.");
    } catch (e) {
      print("⚠️ Personel bulut güncelleme hatası: $e");
    }
  }

  // --- PERSONEL HAREKETLERİNİ GETİR ---
  Future<List<Map<String, dynamic>>> personelHareketleriGetir(String personelId) async {
    if (kIsWeb) {
      try {
        final snapshot = await FirebaseFirestore.instance
            .collection('personel_hareketleri')
            .where('personel_id', isEqualTo: personelId)
            .orderBy('tarih', descending: true)
            .get();
        return snapshot.docs.map((doc) => doc.data()).toList();
      } catch (e) {
        print("Web personel hareket hatası: $e");
        return [];
      }
    } else {
      final db = await instance.database;
      return await db.query(
        'personel_hareketleri',
        where: 'personel_id = ?',
        whereArgs: [personelId],
        orderBy: 'tarih DESC',
      );
    }
  }

  Future<void> herSeyiFirebaseGeriYukle() async {
    final db = await instance.database;
    print("\n🚀 [GERİ YÜKLEME] Buluttan yerele aktarım başlatıldı...");

    // Koleksiyon -> Tablo eşleşmesi
    Map<String, String> tabloEslesmeleri = {
      // Mevcutlar
      'musteriler': 'musteriler',
      'stoklar': 'stoklar',
      'stok_tanimlari': 'stok_tanimlari',
      'firmalar': 'firmalar',
      'tarim_firma_hareketleri': 'tarim_firma_hareketleri',
      'tarlalar': 'tarlalar',
      'tarla_hareketleri': 'tarla_hareketleri',
      'tarla_hasatlari': 'tarla_hasatlari',
      'cekler': 'cekler',
      'araclar': 'araclar',
      'proformalar': 'proformalar',
      'bicer_isleri': 'bicer_isleri',

      // YENİ EKLENEN EKSİKLER (Mühürlendi)
      'tarim_firmalari': 'tarim_firmalari',
      'faturalar': 'faturalar',
      'tahsilatlar': 'tahsilatlar',
      'satislar': 'satislar',
      'musteri_hareketleri': 'musteri_hareketleri',
      'bicer_musterileri': 'bicer_musterileri',
      'bicermusteri_hareketleri': 'bicermusteri_hareketleri',
      'bicer_mazotlar': 'bicer_mazotlar',
      'mazot_takibi': 'mazot_takibi',
      'personel_hareketleri': 'personel_hareketleri',
      'personel': 'personel', // BU EKSİKTİ!
      'bakimlar': 'bakimlar',

      // Eğer Firebase'de isimleri farklıysa buraya dikkat et:
      'stoklistesi': 'stoklar', // Firebase'de 'stoklistesi' ise SQL'de 'stoklar'a yazar
      'firmahareketleri': 'tarim_firma_hareketleri',
      'firma_hareketleri': 'tarim_firma_hareketleri',
      'proforma': 'proformalar',
    };

    for (var entry in tabloEslesmeleri.entries) {
      String fbKoleksiyon = entry.key;
      String sqlTablo = entry.value;

      try {
        // 1. Önce yerel tabloyu temizle (Mükerrer olmasın)
        await db.delete(sqlTablo);

        var snapshots = await FirebaseFirestore.instance.collection(fbKoleksiyon).get();

        if (snapshots.docs.isNotEmpty) {
          // SQL Şemasındaki kolonları alalım
          var tableInfo = await db.rawQuery("PRAGMA table_info($sqlTablo)");
          List<String> sqlKolonlari = tableInfo.map((e) => e['name'].toString()).toList();

          for (var doc in snapshots.docs) {
            Map<String, dynamic> veri = Map.from(doc.data());

            // Firebase doküman ID'sini veriye ekle
            if (sqlKolonlari.contains('id')) {
              // Eğer verinin içinde zaten bir 'id' yoksa doküman ID'sini kullan
              veri['id'] = veri['id'] ?? doc.id;
            }

            // 1. Timestamp (Tarih) Çevirici
            veri.forEach((key, value) {
              if (value is Timestamp) {
                veri[key] = value.toDate().toIso8601String();
              }
            });

            // 2. Tarla Hareketleri Özel Eşitleme
            if (sqlTablo == 'tarla_hareketleri') {
              if (veri.containsKey('İslam')) veri['islem_adi'] = veri['İslam'];
              else if (veri.containsKey('islem')) veri['islem_adi'] = veri['islem'];

              if (veri.containsKey('toplam')) veri['tutar'] = veri['toplam'];
              else if (veri.containsKey('birimFiyat')) veri['tutar'] = veri['birimFiyat'];

              if (veri.containsKey('tarlaId')) veri['tarla_id'] = veri['tarlaId'];
              if (!veri.containsKey('sezon')) veri['sezon'] = "2026";
            }

            // 3. Dinamik Filtreleme: Sadece SQLite'da olan kolonları paketle
            Map<String, dynamic> temizVeri = {};
            for (var kolon in sqlKolonlari) {
              if (veri.containsKey(kolon)) {
                temizVeri[kolon] = veri[kolon];
              }
            }

            // Senkronizasyon bayrağını işaretle
            if (sqlKolonlari.contains('is_synced')) {
              temizVeri['is_synced'] = 1;
            }

            await db.insert(sqlTablo, temizVeri, conflictAlgorithm: ConflictAlgorithm.replace);
          }
          print("✅ $sqlTablo: ${snapshots.docs.length} kayıt indirildi.");
        }
      } catch (e) {
        print("❌ $sqlTablo indirilirken hata: $e");
      }
    }
    print("\n🏁 Geri yükleme bitti! Defterler güncel.");
  }

  Future<dynamic> islemYap(String tabloAdi, Map<String, dynamic> veri, {String islemTipi = 'INSERT', String? id}) async {
    print("\n--- 🌐 WEB/MOBİL İŞLEM: $tabloAdi ---");

    // 1. WEB TARAFI (Sadece Firebase)
    if (kIsWeb) {
      try {
        if (islemTipi == 'INSERT') {
          var docRef = await _firestore.collection(tabloAdi).add(veri);
          return docRef.id;
        } else if (islemTipi == 'UPDATE' && id != null) {
          await _firestore.collection(tabloAdi).doc(id).set(veri, SetOptions(merge: true));
          return id;
        } else if (islemTipi == 'DELETE' && id != null) {
          await _firestore.collection(tabloAdi).doc(id).delete();
          return id;
        }
      } catch (e) {
        print("❌ Web Hatası: $e");
        return null;
      }
    }

    // 2. MOBİL TARAFI (SQLite + Firebase Senkronu)
    final db = await instance.database;
    try {
      if (islemTipi == 'INSERT') {
        int newId = await db.insert(tabloAdi, veri, conflictAlgorithm: ConflictAlgorithm.replace);
        // SQLite ID'sini döküman adı yaparak Firebase'e de yolla (Mükemmel eşleşme)
        await _firestore.collection(tabloAdi).doc(newId.toString()).set(veri);
        return newId;
      }
      // Diğer mobil işlemler (Update/Delete) yukarıdaki mantıkla devam eder...
    } catch (e) {
      print("❌ Mobil Hatası: $e");
    }
    return null;
  }

  Future<void> herSeyiSifirla() async {
    final db = await instance.database;

    // 1. TELEFONDAKİ (SQLite) TÜM TABLOLARI LİSTELE
    List<String> tablolar = [
      'musteriler',
      'stoklar',
      'stoklistesi',
      'stok_tanimlari',
      'firmalar',
      'faturalar',
      'firmahareketleri',
      'firma_hareketleri',
      'tarim_firma_hareketleri',
      'tarim_firmalari',
      'tahsilatlar',
      'cekler',
      'foto',
      'formal',
      'tarlalar',
      'tarla_hareketleri',
      'tarla_hasatlari',
      'proforma',
      'proformalar',
      'satislar',
      'kasa_hareketleri',
      'stok_hareketleri',
      'musteri_hareketleri', // Senin koddaki diğer hareket tablosu
      'alislar',
      'bicer_bakimlar',
      'bicer_musterileri',
      'bicerler',
      'bicer_isleri',
      'bicer_tahsilatlari',
      'bicermusteri_hareketleri',
      'eksper_kayitlari',
      'adacıklar',
      'musteri_faturalari',
      'araclar',
      'bakimlar',
      'isletmeler',
      'evren_ticaret',
      'bicer_mazotlar',
      'mazot_takibi',
      'personel_hareketleri',
      'personel',



    ];

    // SQLite Temizliği
    for (String tablo in tablolar) {
      try {
        await db.delete(tablo);
        debugPrint("📱 Yerel Tablo Silindi: $tablo");
      } catch (e) {
        debugPrint("⚠️ Tablo atlandı (Zaten yok veya hata): $tablo");
      }
    }

    // 2. BULUTTAKİ (Firebase) TÜM VERİLERİ TEMİZLE
    // Buradaki isimlerin Firebase'deki koleksiyon isimlerinle aynı olması lazım
    List<String> fbKoleksiyonlar = [
      'musteriler',
      'stoklar',
      'stoklistesi',
      'stok_tanimlari',
      'firmalar',
      'faturalar',
      'firmahareketleri',
      'firma_hareketleri',
      'tarim_firmalari',
      'tarim_firma_hareketleri',
      'tahsilatlar',
      'cekler',
      'foto',
      'formal',
      'tarlalar',
      'tarla_hareketleri',
      'tarla_hasatlari',
      'proforma',
      'proformalar',
      'satislar',
      'kasa_hareketleri',
      'stok_hareketleri',
      'musteri_hareketleri', // Senin koddaki diğer hareket tablosu
      'alislar',
      'bicer_bakimlar',
      'bicer_musterileri',
      'bicer_isleri',
      'bicer_tahsilatlari',
      'bicermusteri_hareketleri',
      'bicerler',
      'eksper_kayitlari',
      'adacıklar',
      'musteri_faturalari',
      'araclar',
      'bakimlar',
      'evren_ticaret',
      'bicer_mazotlar',
      'mazot_takibi',
      'isletmeler',
      'personel_hareketleri',
      'personel',







    ];

    for (String kol in fbKoleksiyonlar) {
      try {
        var snapshots = await FirebaseFirestore.instance.collection(kol).get();
        for (var doc in snapshots.docs) {
          await doc.reference.delete();
        }
        debugPrint("☁️ Firebase Koleksiyonu Tertemiz: $kol");
      } catch (e) {
        debugPrint("❌ Firebase Hatası ($kol): $e");
      }
    }
  }
}