import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:evren_tarim_market/models/CekModel.dart';
import 'dart:async';
import 'dart:convert';
import 'package:intl/intl.dart';
import 'package:flutter/foundation.dart'; // debugPrint için bu şart!
import 'package:synchronized/synchronized.dart';

import 'package:path_provider/path_provider.dart'; // 'getApplicationDocumentsDirectory' hatasını çözer
import 'package:evren_tarim_market/core/image_helper.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'dart:io' show File;



class DatabaseHelper {

  static const int _databaseVersion = 3;
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;
  bool _syncCalisiyor = false;
  StreamSubscription? _cekSub;
  StreamSubscription? _stokSub;
  final _lock = Lock(); // Bunu ekle

  DatabaseHelper._init();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final StreamController<List<dynamic>> _cekController = StreamController.broadcast();

  String newId() {
    return DateTime.now().millisecondsSinceEpoch.toString();
  }
  Future<Database> get database async {
    if (_database != null) return _database!;

    // Kilit mekanizması burada devreye giriyor
    return await _lock.synchronized(() async {
      if (_database == null) {
        _database = await _initDB('evren_ticaret.db');
      }
      return _database!;
    });
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: _databaseVersion,
      onCreate: _createDB,
      onUpgrade: _onUpgrade,
      onOpen: (db) async {
        await _tabloyuOnar(db);
        // 🔥 KRİTİK EKLEME: Uygulama her açıldığında arkada verileri Firebase'den çeker
        herSeyiBuluttanIndir();
      },
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
    );
  }

  // ================= ON UPGRADE =================
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    print("🔄 DB VERSİYON YÜKSELTME: $oldVersion -> $newVersion");
    await _tabloyuOnar(db);
  }

  // ================= CREATE =================
  Future<void> _createDB(Database db, int version) async {
    print("🚀 Veritabanı oluşturuluyor...");
    await _tabloyuOnar(db);


    await db.execute('''
    CREATE TABLE IF NOT EXISTS personel (
      id TEXT PRIMARY KEY,
      ad TEXT,
      gorev TEXT,
      maas REAL,
      sgk REAL,
      stopaj REAL,
      bakiye REAL,
      sube TEXT,
      is_synced INTEGER DEFAULT 0
    )
  ''');

    await db.execute('''
    CREATE TABLE IF NOT EXISTS personel_hareketleri (
      id TEXT PRIMARY KEY,
      personel_id TEXT,
      tarih TEXT,
      tur TEXT,
      tutar REAL,
      not_aciklama TEXT,
      is_synced INTEGER DEFAULT 0
    )
  ''');

    await db.execute('''
  CREATE TABLE IF NOT EXISTS tahsilatlar (
    id INTEGER PRIMARY KEY AUTOINCREMENT, 
    is_id INTEGER, -- Eksik olan ve hataya sebep olan sütun buydu!
    ciftci_ad TEXT, 
    miktar REAL, 
    tarih TEXT, 
    sezon TEXT, 
    aciklama TEXT,
    odeme_tipi TEXT, 
    is_synced INTEGER DEFAULT 0, 
    firebase_id TEXT
  )
''');

    await db.execute('''
  CREATE TABLE IF NOT EXISTS mazot_takibi (
    id INTEGER PRIMARY KEY AUTOINCREMENT, 
    petrol_adi TEXT, 
    litre REAL, 
    tutar REAL, 
    odenen REAL, 
    tarih TEXT, 
    sezon TEXT, 
    firebase_id TEXT
  )
''');

    await db.execute('''
  CREATE TABLE IF NOT EXISTS stoklar (
    id INTEGER PRIMARY KEY AUTOINCREMENT, 
    ana_stok_id INTEGER,      -- MALIN ASIL KİMLİĞİ (Transfer olsa da değişmez)
    firebase_id TEXT UNIQUE,  -- Firebase'deki benzersiz ID
    kategori TEXT, 
    marka TEXT, 
    model TEXT, 
    alt_model TEXT, 
    altmodel TEXT, 
    adet REAL, 
    fiyat REAL, 
    sube TEXT, 
    durum TEXT, 
    tarih TEXT, 
    tarim_firmalari TEXT, 
    sektor TEXT, 
    foto TEXT, 
    is_synced INTEGER DEFAULT 0
  )
''');
    // DatabaseHelper içinde bu kısmı bul ve bununla değiştir
    await db.execute('''
  CREATE TABLE IF NOT EXISTS stok_tanimlari (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    kategori TEXT,
    marka TEXT,
    model TEXT,
    alt_model TEXT,
    altmodel TEXT,
    tarim_firmalari TEXT,
    durum TEXT,
    is_synced INTEGER,
    urun TEXT,
    firebase_id TEXT,
    UNIQUE(kategori, marka, model, alt_model)
  )
''');

    await db.execute('''
    CREATE TABLE IF NOT EXISTS satislar (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        musteri_ad TEXT,
        satis_fiyati REAL,
        sube TEXT,
        tarih TEXT,
        is_synced INTEGER DEFAULT 0
    );
    ''');

    await db.execute('''
CREATE TABLE IF NOT EXISTS tarim_firmalari (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  ad TEXT UNIQUE, 
  yetkili TEXT, 
  tel TEXT, 
  adres TEXT,
  kategori TEXT,
  durum TEXT,
  marka TEXT,
  model TEXT,
  alt_model TEXT,
  borc REAL DEFAULT 0,
  alacak REAL DEFAULT 0, 
  is_synced INTEGER DEFAULT 0,
  firebase_id TEXT,
  sube TEXT DEFAULT "TEFENNİ",
  son_guncelleme TEXT,
  fatura_yolu TEXT  -- 🔥 Fatura fotoğrafının telefon daki yolunu burada tutacağız
)
''');

// Bu index zaten sendeydi, kalsın, mükerrer kaydı önler
    await db.execute(
        'CREATE UNIQUE INDEX IF NOT EXISTS idx_firma_ad ON tarim_firmalari(ad)'
    );


    await db.execute('''
  CREATE TABLE IF NOT EXISTS ciftclik_firmalari (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    ad TEXT, 
    yetkili TEXT, 
    tel TEXT, 
    adres TEXT,
    borc REAL DEFAULT 0, 
    alacak REAL DEFAULT 0, 
    is_synced INTEGER DEFAULT 0
  )
''');
    // database_helper.dart içindeki ilgili kısmı şu şekilde güncelle:

    await db.execute('''
  CREATE TABLE IF NOT EXISTS araclar (
    id INTEGER PRIMARY KEY AUTOINCREMENT, 
    plaka TEXT, 
    marka TEXT, 
    model TEXT, 
    alt_model TEXT, 
    paket TEXT, 
    motor_tipi TEXT, 
    kasa_tipi TEXT, 
    km INTEGER, 
    alis_fiyati REAL, 
    tahmini_satis REAL, 
    alis_tarihi TEXT, 
    kimden_alindi TEXT, 
    muayene_tarihi TEXT, 
    renk TEXT, 
    durum TEXT, 
    is_synced INTEGER DEFAULT 0, 
    firebase_id TEXT
  )
''');

    await db.execute('''
  CREATE TABLE IF NOT EXISTS bicer_musterileri (
    id INTEGER PRIMARY KEY AUTOINCREMENT, 
    tc TEXT, 
    ad_soyad TEXT NOT NULL, 
    telefon TEXT, 
    adres TEXT, 
    notlar TEXT, 
    is_synced INTEGER DEFAULT 0, 
    sube TEXT DEFAULT "TEFENNİ", 
    firebase_id TEXT,
    fotograf_yolu TEXT  -- Yeni sütun buraya eklendi
  )
''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS firma_hareketleri (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        firma_id INTEGER,
        stok_id INTEGER,      -- 🔥 EKLENECEK 1
        ana_stok_id INTEGER,  -- 🔥 EKLENECEK 2
        tip TEXT,
        urun_adi TEXT,
        tutar REAL,
        adet REAL,
        tarih TEXT,
        is_synced INTEGER DEFAULT 0,
        firebase_id TEXT
      )
   ''');
// DatabaseHelper içindeki faturalar tablosunu metin destekli yap
    await db.execute('''
  CREATE TABLE IF NOT EXISTS faturalar (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    firma_id TEXT,  -- 🔥 Sayı değil METİN yaptık ki 'YRDFGG' yazabilelim
    dosya_yolu TEXT,
    tarih TEXT,
    firebase_id TEXT
  )
''');

    // 1. TABLOYU DÜZELT (is_synced ekledik)
    await db.execute('''
  CREATE TABLE IF NOT EXISTS musteri_hareketleri (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    musteri_id TEXT,
    musteri_ad TEXT,
    islem TEXT,
    tutar REAL,
    aciklama TEXT,
    tarih TEXT,
    is_synced INTEGER DEFAULT 0 -- 👈 Bu eksikti, o yüzden patlıyordu!
  )
''');
    await db.execute('''
  CREATE TABLE IF NOT EXISTS musteriler (
    id TEXT PRIMARY KEY,
    ad TEXT,
    ad_norm TEXT, -- 👈 BU EKSİKTİ, EKLE!
    tc TEXT,
    tel TEXT,
    adres TEXT,
    sube TEXT,
    bakiye REAL DEFAULT 0.0,
    is_synced INTEGER DEFAULT 0
  )
''');

    await db.execute('''
   CREATE TABLE IF NOT EXISTS bicer_isleri (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        ciftci_ad TEXT,
        urun_tipi TEXT,
        dekar REAL,
        fiyat REAL,
        toplam_tutar REAL,
        odenen_miktar REAL,
        kalan_borc REAL,
        tarih TEXT,
        sezon TEXT,
        is_synced INTEGER DEFAULT 0,
        firebase_id TEXT,
        bicer_id INTEGER -- BU SATIRI EKLE
    )
    ''');

    await db.execute('''
  CREATE TABLE IF NOT EXISTS bakimlar (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    arac_id INTEGER,
    usta_tipi TEXT,
    islem_detay TEXT,
    tutar REAL,
    tarih TEXT,
    is_synced INTEGER DEFAULT 0,
    firebase_id TEXT
  )
''');
  }

  Future<void> _tabloyuOnar(Database db) async {
    print("🛠️ VERİTABANI KONTROLÜ / TAMİRİ BAŞLADI...");

    await db.execute('''
CREATE TABLE IF NOT EXISTS satislar (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    arac_id INTEGER, -- BURASI EKSİKTİ, EKLEDİK!
    musteri_ad TEXT,
    satis_fiyati REAL,
    sube TEXT,
    tarih TEXT,
    is_synced INTEGER DEFAULT 0
);
''');



    await db.execute('''
  CREATE TABLE IF NOT EXISTS mazot_takibi (
    id INTEGER PRIMARY KEY AUTOINCREMENT, 
    petrol_adi TEXT, 
    litre REAL, 
    tutar REAL, 
    odenen REAL, 
    tarih TEXT, 
    sezon TEXT, 
    firebase_id TEXT
  )
''');

    final Map<String, String> tables = {

      'ciftciler': '''
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  ad_soyad TEXT NOT NULL,
  telefon TEXT,
  adres TEXT,
  notlar TEXT,
  is_synced INTEGER DEFAULT 0,
  firebase_id TEXT
''',
      'mazot_takibi': '''
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      petrol_adi TEXT,
      litre REAL,
      tutar REAL,
      odenen REAL,
      tarih TEXT,
      sezon TEXT,
      firebase_id TEXT
    
    ''',

      'bakimlar': '''
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  arac_id INTEGER,
  usta_tipi TEXT,
  islem_detay TEXT,
  tutar REAL,
  tarih TEXT,
  is_synced INTEGER DEFAULT 0,
  firebase_id TEXT,
  FOREIGN KEY (arac_id) REFERENCES araclar (id) ON DELETE CASCADE
''',
      'ciftclik_firmalari': 'id INTEGER PRIMARY KEY AUTOINCREMENT, ad TEXT, yetkili TEXT, tel TEXT, adres TEXT, borc REAL DEFAULT 0, alacak REAL DEFAULT 0, is_synced INTEGER DEFAULT 0, firebase_id TEXT, sube TEXT DEFAULT "TEFENNİ"',
      'araclar': 'id INTEGER PRIMARY KEY AUTOINCREMENT, plaka TEXT, marka TEXT, model TEXT, alt_model TEXT, paket TEXT, motor_tipi TEXT, kasa_tipi TEXT, km INTEGER, alis_fiyati REAL, tahmini_satis REAL, alis_tarihi TEXT, kimden_alindi TEXT, muayene_tarihi TEXT, renk TEXT, durum TEXT, is_synced INTEGER DEFAULT 0, firebase_id TEXT',
      'bicer_musterileri': 'id INTEGER PRIMARY KEY AUTOINCREMENT, tc TEXT, ad_soyad TEXT NOT NULL, telefon TEXT, adres TEXT, notlar TEXT, is_synced INTEGER DEFAULT 0, sube TEXT DEFAULT "TEFENNİ", firebase_id TEXT, fotograf_yolu TEXT',

      'firma_hareketleri': 'id INTEGER PRIMARY KEY AUTOINCREMENT, firma_id INTEGER, tip TEXT, urun_adi TEXT, tutar REAL, adet REAL, tarih TEXT, is_synced INTEGER DEFAULT 0, firebase_id TEXT',
      'tarla_hasatlari': 'id INTEGER PRIMARY KEY AUTOINCREMENT, tarla_id INTEGER, ciftci_ad TEXT, alan_dekar REAL, tutar REAL, tarih TEXT, sezon TEXT, ekilen_urun TEXT, toplam_kg REAL, birim_fiyat REAL, toplam_gelir REAL, satilan_kisi TEXT, pesin_alinan REAL DEFAULT 0, kalan_alacak REAL DEFAULT 0, vade_tarihi TEXT, odeme_durumu TEXT, sube TEXT DEFAULT "TEFENNİ", is_synced INTEGER DEFAULT 0, firebase_id TEXT',
      'bicer_bakimlar': 'id INTEGER PRIMARY KEY AUTOINCREMENT, bicer_id INTEGER, parca_adi TEXT, tutar REAL, tarih TEXT, is_synced INTEGER DEFAULT 0, sube TEXT DEFAULT "TEFENNİ", firebase_id TEXT',
      'mazot_kayitlari': 'id INTEGER PRIMARY KEY AUTOINCREMENT, plaka TEXT, litre REAL, tutar REAL, tarih TEXT, sezon TEXT, firebase_id TEXT',
      'bicerler': 'id INTEGER PRIMARY KEY, marka TEXT, model TEXT, plaka TEXT, yil TEXT, durum TEXT, firebase_id TEXT',
      'bicer_isleri': 'id INTEGER PRIMARY KEY AUTOINCREMENT, ciftci_ad TEXT, urun_tipi TEXT, dekar REAL, fiyat REAL, toplam_tutar REAL, odenen_miktar REAL, kalan_borc REAL, tarih TEXT, sezon TEXT, is_synced INTEGER DEFAULT 0, firebase_id TEXT, bicer_id INTEGER',
      'mazot_takibi': 'id INTEGER PRIMARY KEY AUTOINCREMENT, petrol_adi TEXT, litre REAL, tutar REAL, odenen REAL, tarih TEXT, sezon TEXT, firebase_id TEXT',
      'faturalar': 'id INTEGER PRIMARY KEY AUTOINCREMENT, firma_id TEXT, dosya_yolu TEXT, tarih TEXT, firebase_id TEXT',

      'tarlalar': 'id INTEGER PRIMARY KEY AUTOINCREMENT, mevki TEXT, dekar REAL, ada_parsel TEXT, is_sulu INTEGER DEFAULT 0, ekilen_urun TEXT, sezon TEXT, is_icar INTEGER DEFAULT 0, tarla_sahibi TEXT, kira_tutari REAL DEFAULT 0, kira_baslangic TEXT, kira_bitis TEXT, sube TEXT DEFAULT "TEFENNİ", is_synced INTEGER DEFAULT 0, firebase_id TEXT',
      'tarla_hareketleri': 'id INTEGER PRIMARY KEY AUTOINCREMENT, tarla_id INTEGER, sezon TEXT, is_islem INTEGER, islem_tipi TEXT, islem_adi TEXT, ekilen_urun TEXT, miktar REAL, tutar REAL, tarih TEXT, sube TEXT DEFAULT "TEFENNİ", is_synced INTEGER DEFAULT 0, firebase_id TEXT',
      'musteri_hareketleri': 'id INTEGER PRIMARY KEY AUTOINCREMENT, musteri_id TEXT, musteri_ad TEXT, islem TEXT, tutar REAL, aciklama TEXT, tarih TEXT, is_synced INTEGER DEFAULT 0, firebase_id TEXT',

      'stok_tanimlari': '''
  id INTEGER PRIMARY KEY AUTOINCREMENT,
    kategori TEXT,
    marka TEXT,
    model TEXT,
    alt_model TEXT,
    altmodel TEXT,
    tarim_firmalari TEXT,
    durum TEXT,
    is_synced INTEGER,
    urun TEXT,
    firebase_id TEXT,
    UNIQUE(kategori, marka, model, alt_model)
''',

      'stoklar': '''
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  ana_stok_id INTEGER,      -- MALIN ASIL KİMLİĞİ (Birleştirme için şart)
  kategori TEXT,
  tarim_firmalari TEXT,
  marka TEXT,
  model TEXT,
  alt_model TEXT,
  adet REAL,
  fiyat REAL,
  sube TEXT,
  durum TEXT,
  tarih TEXT,
  fatura_no TEXT,
  sektor TEXT,
  foto TEXT,
  is_synced INTEGER DEFAULT 0,
  firebase_id TEXT UNIQUE
''',
      'tarim_firmalari': '''
  id INTEGER PRIMARY KEY AUTOINCREMENT, 
  ad TEXT UNIQUE, -- 🔥 Aynı isimli firma eklenmesini engeller
  yetkili TEXT, 
  tel TEXT, 
  adres TEXT, 
  kategori TEXT, 
  durum TEXT, 
  marka TEXT, 
  model TEXT, 
  alt_model TEXT, 
  borc REAL DEFAULT 0, 
  alacak REAL DEFAULT 0, 
  is_synced INTEGER DEFAULT 0, 
  firebase_id TEXT, 
  sube TEXT DEFAULT "TEFENNİ", 
  son_guncelleme TEXT,
  fatura_yolu TEXT -- 🔥 Fatura fotoğrafları buraya kaydedilecek
''',

      'eksper_kayitlari': 'id INTEGER PRIMARY KEY AUTOINCREMENT, arac_id INTEGER, hasar_notu TEXT, tarih TEXT, firebase_id TEXT',
      'tahsilatlar': 'id INTEGER PRIMARY KEY AUTOINCREMENT, is_id INTEGER, ciftci_ad TEXT, miktar REAL, tarih TEXT, sezon TEXT, odeme_tipi TEXT, is_synced INTEGER DEFAULT 0, firebase_id TEXT',
      'musteriler': 'id TEXT PRIMARY KEY, ad TEXT, ad_norm TEXT UNIQUE, tc TEXT, tel TEXT, adres TEXT, sube TEXT, bakiye REAL DEFAULT 0, is_synced INTEGER DEFAULT 0, firebase_id TEXT',
      'firmalar': 'id INTEGER PRIMARY KEY AUTOINCREMENT, ad TEXT, yetkili TEXT, tel TEXT, kategori TEXT, durum TEXT, marka TEXT, model TEXT, alt_model TEXT, altmodel TEXT, urun TEXT, adres TEXT, borc REAL DEFAULT 0, alacak REAL DEFAULT 0, is_synced INTEGER DEFAULT 0, firebase_id TEXT',
      'cekler': 'id INTEGER PRIMARY KEY AUTOINCREMENT, firmaAd TEXT, tip TEXT, kesideTarihi TEXT, vadeTarihi TEXT, tutar REAL, durum TEXT, resimYolu TEXT, is_synced INTEGER DEFAULT 0, sube TEXT, firebase_id TEXT',
      'proformalar': 'id INTEGER PRIMARY KEY AUTOINCREMENT, firebase_id TEXT, musteri_adi TEXT, toplam REAL, tarih TEXT, sube TEXT, is_synced INTEGER DEFAULT 0'
    };


    await db.execute('''
      CREATE TABLE IF NOT EXISTS firma_hareketleri (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        firma_id INTEGER,
        stok_id INTEGER,      -- 🔥 EKLENECEK 1
        ana_stok_id INTEGER,  -- 🔥 EKLENECEK 2
        tip TEXT,
        urun_adi TEXT,
        tutar REAL,
        adet REAL,
        tarih TEXT,
        is_synced INTEGER DEFAULT 0,
        firebase_id TEXT
      )
   ''');
    // 1. TABLOYU DÜZELT (is_synced ekledik)
    await db.execute('''
  CREATE TABLE IF NOT EXISTS musteri_hareketleri (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    musteri_id TEXT,
    musteri_ad TEXT,
    islem TEXT,
    tutar REAL,
    aciklama TEXT,
    tarih TEXT,
    is_synced INTEGER DEFAULT 0 -- 👈 Bu eksikti, o yüzden patlıyordu!
  )
''');
    await db.execute('''
  CREATE TABLE IF NOT EXISTS musteriler (
    id TEXT PRIMARY KEY,
    ad TEXT,
    ad_norm TEXT, -- 👈 BU EKSİKTİ, EKLE!
    tc TEXT,
    tel TEXT,
    adres TEXT,
    sube TEXT,
    bakiye REAL DEFAULT 0.0,
    is_synced INTEGER DEFAULT 0
  )
''');

    await db.execute('''
   CREATE TABLE IF NOT EXISTS bicer_isleri (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        ciftci_ad TEXT,
        urun_tipi TEXT,
        dekar REAL,
        fiyat REAL,
        toplam_tutar REAL,
        odenen_miktar REAL,
        kalan_borc REAL,
        tarih TEXT,
        sezon TEXT,
        is_synced INTEGER DEFAULT 0,
        firebase_id TEXT,
        bicer_id INTEGER -- BU SATIRI EKLE
    )
    ''');
    // DatabaseHelper içinde bu kısmı bul ve bununla değiştir
    await db.execute('''
  CREATE TABLE IF NOT EXISTS stok_tanimlari (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    kategori TEXT,
    marka TEXT,
    model TEXT,
    alt_model TEXT,
    altmodel TEXT,
    tarim_firmalari TEXT,
    durum TEXT,
    is_synced INTEGER,
    urun TEXT,
    firebase_id TEXT,
    UNIQUE(kategori, marka, model, alt_model)
  )
''');

    await db.execute('''
    CREATE TABLE IF NOT EXISTS personel (
        id TEXT PRIMARY KEY,
        ad TEXT NOT NULL,
        maas REAL,
        bakiye REAL DEFAULT 0,
        foto_yolu TEXT,
        is_synced INTEGER DEFAULT 0
      )
    ''');

    await db.execute('''
    CREATE TABLE IF NOT EXISTS personel_hareketleri (
     id TEXT PRIMARY KEY,
        personel_id TEXT,
        tarih TEXT,
        tur TEXT, -- 'MAAŞ TAHAKKUK' veya 'ÖDEME'
        tutar REAL,
        ay_bilgisi TEXT, -- 'OCAK', 'ŞUBAT' vb.
        aciklama TEXT,
        is_synced INTEGER DEFAULT 0,
        FOREIGN KEY (personel_id) REFERENCES personel (id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
  CREATE TABLE IF NOT EXISTS masraflar (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    makine_id INTEGER,
    aciklama TEXT,
    miktar REAL,
    tarih TEXT,
    yil TEXT,
    FOREIGN KEY (makine_id) REFERENCES bicerler (id) ON DELETE CASCADE
  )
''');

    // 1. Tablo Oluşturma Döngüsü
    for (var entry in tables.entries) {
      try {
        await db.execute('CREATE TABLE IF NOT EXISTS ${entry.key} (${entry.value})');
      } catch (e) {
        print("❌ ${entry.key} oluşturma hatası: $e");
      }
    }


// Tarım Firmaları özel kontrolleri
    await _sutunEkle(db, "tarim_firmalari", "borc", "REAL DEFAULT 0");
    await _sutunEkle(db, "tarim_firmalari", "alacak", "REAL DEFAULT 0");
    await _sutunEkle(db, "tarim_firmalari", "sube", "TEXT DEFAULT 'TEFENNİ'");
    await _sutunEkle(db, "tarim_firmalari", "fatura_yolu", "TEXT"); // 👈 Fotoğraf sütunu buraya
    // Genel Senkronizasyon ve Model Farklılıkları Döngüsü
    for (String tablo in ['stoklar', 'firmalar', 'stok_tanimlari', 'tarim_firmalari', 'ciftclik_firmalari']) {
      await _sutunEkle(db, tablo, "kategori", "TEXT");
      await _sutunEkle(db, tablo, "durum", "TEXT");
      await _sutunEkle(db, tablo, "marka", "TEXT");
      await _sutunEkle(db, tablo, "model", "TEXT");
      await _sutunEkle(db, tablo, "alt_model", "TEXT");
      await _sutunEkle(db, tablo, "altmodel", "TEXT");
      await _sutunEkle(db, tablo, "urun", "TEXT");
      await _sutunEkle(db, tablo, "is_synced", "INTEGER DEFAULT 0");
      await _sutunEkle(db, tablo, "firebase_id", "TEXT");
    }

    // Tarlalar tablosu güncellemeleri
    await _sutunEkle(db, "tarlalar", "ada_parsel", "TEXT");
    await _sutunEkle(db, "tarlalar", "is_sulu", "INTEGER DEFAULT 0");
    await _sutunEkle(db, "tarlalar", "is_icar", "INTEGER DEFAULT 0");
    await _sutunEkle(db, "tarlalar", "tarla_sahibi", "TEXT");
    await _sutunEkle(db, "tarlalar", "sube", "TEXT DEFAULT 'TEFENNİ'");

    // Hasat tablosu güncellemeleri
    await _sutunEkle(db, "tarla_hasatlari", "pesin_alinan", "REAL DEFAULT 0");
    await _sutunEkle(db, "tarla_hasatlari", "kalan_alacak", "REAL DEFAULT 0");
    await _sutunEkle(db, "tarla_hasatlari", "vade_tarihi", "TEXT");
    await _sutunEkle(db, "tarla_hasatlari", "toplam_kg", "REAL DEFAULT 0");
    await _sutunEkle(db, "tarla_hasatlari", "firebase_id", "TEXT");

    // Diğer kritik sütunlar
    await _sutunEkle(db, "bakimlar", "firebase_id", "TEXT");
    await _sutunEkle(db, "araclar", "firebase_id", "TEXT");
    await _sutunEkle(db, 'satislar', 'arac_id', 'INTEGER');
    // Biçer İşleri Tablosuna Senkronizasyon ve İlişki Sütunları
    await _sutunEkle(db, "bicer_isleri", "is_synced", "INTEGER DEFAULT 0");
    await _sutunEkle(db, "bicer_isleri", "firebase_id", "TEXT");
    await _sutunEkle(db, "bicer_isleri", "bicer_id", "INTEGER");
    await _sutunEkle(db, "bicer_musterileri", "fotograf_yolu", "TEXT");

// Tahsilatlara eksik olan sütunları ekliyoruz
    await _sutunEkle(db, "tahsilatlar", "odeme_tipi", "TEXT");
    await _sutunEkle(db, "tahsilatlar", "sezon", "TEXT"); // LOGDAKİ HATAYI BU ÇÖZER
    await _sutunEkle(db, "tahsilatlar", "aciklama", "TEXT");
    await _sutunEkle(db, "tahsilatlar", "is_id", "INTEGER");
    // Biçer makinelerine çalışma saati ekliyoruz
    await _sutunEkle(db, "bicerler", "calisma_saati", "INTEGER DEFAULT 0");

    // Müşteriler tablosuna TC sütununu ekliyoruz
    await _sutunEkle(db, "bicer_musterileri", "tc", "TEXT");
    await _sutunEkle(db, "firma_hareketleri", "adet", "REAL");
    await _sutunEkle(db, "firma_hareketleri", "stok_id", "INTEGER");
    await _sutunEkle(db, "firma_hareketleri", "ana_stok_id", "INTEGER");

    await _sutunEkle(db, "stoklar", "ana_stok_id", "INTEGER");
    await _sutunEkle(db, "stok_tanimlari", "tarim_firmalari", "TEXT");

    await _sutunEkle(db, "personel", "foto_yolu", "TEXT");



    print("✅ TAMİRAT BİTTİ. TÜM SİSTEM GÜNCEL.");
  }

  // ================= SÜTUN EKLEME =================
  Future<void> _sutunEkle(Database db, String tabloAdi, String sutunAdi, String sutunTipi) async {
    try {
      // Mevcut sütunları kontrol et
      var sutunlar = await db.rawQuery('PRAGMA table_info($tabloAdi)');
      bool varMi = sutunlar.any((element) => element['name'] == sutunAdi);

      if (!varMi) {
        await db.execute('ALTER TABLE $tabloAdi ADD COLUMN $sutunAdi $sutunTipi');
        print("✅ $tabloAdi tablosuna $sutunAdi sütunu eklendi.");
      }
    } catch (e) {
      print("❌ Sütun ekleme hatası ($tabloAdi -> $sutunAdi): $e");
    }
  }
// DatabaseHelper.dart içine ekle
  Future<void> tabloyuZorlaGuncelle() async {
    final db = await instance.database;

    // is_id sütunu yoksa ekle
    try {
      await db.execute("ALTER TABLE tahsilatlar ADD COLUMN is_id INTEGER");
      print("✅ is_id sütunu eklendi");
    } catch (e) {
      print("ℹ️ is_id zaten var veya eklenemedi");
    }

    // aciklama sütunu yoksa ekle
    try {
      await db.execute("ALTER TABLE tahsilatlar ADD COLUMN aciklama TEXT");
      print("✅ aciklama sütunu eklendi");
    } catch (e) {
      print("ℹ️ aciklama zaten var veya eklenemedi");
    }
  }

  // ================= INSERT =================
  Future<int> insert(String tabloAdi, Map<String, dynamic> veri) async {
    final db = await database;
    return await db.insert(
      tabloAdi,
      veri,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> ciftclikFirmaBorcEkle(int id, double miktar) async {
    final db = await instance.database;
    await db.rawUpdate(
      'UPDATE ciftclik_firmalari SET borc = borc + ? WHERE id = ?',
      [miktar, id],
    );
  }


  Future<List<Map<String, dynamic>>> tarimFirmaListesiGetir() async {
    final db = await database;

    final sonuc = await db.rawQuery('''
  SELECT 
    f.id,
    f.ad,
    f.yetkili, -- Kodunda yetkili diye bir alan kullanıyorsun, buraya ekle
    f.tel,      -- Tabloda 'telefon' mu 'tel' mi? Sen formda 'tel' yazmışsın.
    f.adres,
    f.kategori,
    f.marka,
    f.model,
    f.alt_model,
    COALESCE(SUM(
      CASE 
        WHEN h.tip = 'ÖDEME' THEN -CAST(h.tutar AS REAL)
        ELSE CAST(h.tutar AS REAL)
      END
    ), 0) as bakiye
  FROM tarim_firmalari f
  LEFT JOIN firma_hareketleri h ON h.firma_id = f.id
  GROUP BY f.id, f.ad, f.yetkili, f.tel, f.adres, f.kategori, f.marka, f.model, f.alt_model
  ORDER BY f.ad ASC
''');

    return sonuc;
  }


  Future<int> tarimFirmaEkle(Map<String, dynamic> row) async {
    final db = await instance.database;

    // 1. ADIM: SQLite'a Kaydet ve Oluşan Benzersiz ID'yi Al
    // conflictAlgorithm: replace sayesinde aynı ID gelirse üstüne yazar, çoğaltmaz.
    int localId = await db.insert(
        'tarim_firmalari',
        row,
        conflictAlgorithm: ConflictAlgorithm.replace
    );

    // 2. ADIM: Firebase ve SQLite'ı Mühürle
    try {
      // Firma adını doküman ID'si yapıyoruz (Senin istediğin yöntem)
      String docId = row['ad'].toString().toUpperCase().trim();

      await FirebaseFirestore.instance
          .collection('tarim_firmalari')
          .doc(docId)
          .set({
        ...row,
        'id': localId, // SQLite'daki gerçek ID'yi Firebase'e de çakıyoruz 🔥
        'is_synced': 1,
        'firebase_id': docId,
        'son_guncelleme': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true)); // merge:true sayesinde var olan veriyi bozmaz, günceller.

      // 3. ADIM: SQLite'daki kaydı "Firebase ile eşleşti" olarak işaretle
      await db.update(
        'tarim_firmalari',
        {'is_synced': 1, 'firebase_id': docId},
        where: 'id = ?',
        whereArgs: [localId],
      );

      debugPrint("✅ $docId hem SQLite hem Firebase'de eşitlendi.");
    } catch (e) {
      debugPrint("⚠️ Firebase Yazma Hatası: $e");
    }

    return localId;
  }


// Çiftçilik Paneli için
  Future<List<Map<String, dynamic>>> ciftclikFirmaListesiGetir() async {
    final db = await instance.database;
    return await db.query('ciftclik_firmalari', orderBy: 'ad ASC');
  }


  Future<void> herSeyiBuluttanIndir() async {
    if (_syncCalisiyor) return;
    _syncCalisiyor = true;

    print("📡 [SYNC] Büyük Baş Belası temizleniyor, veriler vakumlanıyor...");

    try {
      final db = await instance.database;

      List<String> koleksiyonlar = [
        'stoklar',
        'tarim_firmalari',
        'ciftclik_firmalari',
        'personeller',
        'cekler',
        'tarlalar',
        'stok_tanimlari',
        'musteriler',
        'araclar',
        'tarla_hasatlari'
      ];

      for (String kol in koleksiyonlar) {
        // Firebase'den verileri çekiyoruz
        QuerySnapshot snapshot = await _firestore.collection(kol).get();

        // SQLite tablosundaki kolon isimlerini alıyoruz (Hata almamak için)
        var tableInfo = await db.rawQuery("PRAGMA table_info($kol)");
        List<String> sqlKolonlari = tableInfo.map((e) => e['name'].toString()).toList();

        for (var doc in snapshot.docs) {
          Map<String, dynamic> veri = Map.from(doc.data() as Map<String, dynamic>);

          // 1. ADIM: Tarih Çevirici (Firebase Timestamp -> String)
          veri.forEach((key, value) {
            if (value is Timestamp) {
              veri[key] = value.toDate().toIso8601String();
            }
          });

          // 2. ADIM: KİMLİK EŞLEŞTİRME (Çoğalmayı engelleyen yer burası!)
          // Firebase döküman ID'sini SQLite'daki firebase_id kolonuna çakıyoruz.
          // Böylece SQLite 'ConflictAlgorithm.replace' ile bu kaydın aynısı olduğunu anlar.
          veri['firebase_id'] = doc.id;

          // 3. ADIM: İsim/Ad Kontrolü
          if (['tarim_firmalari', 'ciftclik_firmalari', 'musteriler'].contains(kol)) {
            veri['ad'] = doc.id;
          }

          // 4. ADIM: Senkronizasyon Bayrağı
          veri['is_synced'] = 1;

          // 5. ADIM: KOLON FİLTRELEME (SQL'de olmayan veriyi temizler)
          Map<String, dynamic> temizVeri = {};
          for (var kolon in sqlKolonlari) {
            if (veri.containsKey(kolon)) {
              temizVeri[kolon] = veri[kolon];
            }
          }

          // 6. ADIM: AKILLI KAYIT (Vurucu Tim)
          // Eğer aynı firebase_id varsa eskisini siler yenisini yazar. ÇOĞALTMAZ!
          await db.insert(
            kol,
            temizVeri,
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
        print("✅ $kol koleksiyonu tertemiz indirildi.");
      }
      print("🏁 [İŞLEM TAMAM] Artık stoklar sonsuz değil, sadece güncel!");
    } catch (e) {
      print("❌ [SYNC ERROR] Hata çıktı: $e");
    } finally {
      _syncCalisiyor = false;
    }
  }

  Future<void> herSeyiBulutaBas() async {
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
        'personeller',
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
    final db = await database;
    final maps = await db.query('cekler');
    return maps.map((e) => CekModel.fromMap(e)).toList();
  }


  Future<void> cekSil(int id) async {
    final db = await database;
    await db.delete('cekler', where: 'id=?', whereArgs: [id]);
  }

  Future<int> cekEkle(CekModel cek) async {
    final db = await instance.database;
    // conflictAlgorithm: replace sayesinde aynı ID'li çek varsa üstüne yazar, hata vermez.
    return await db.insert('cekler', cek.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  // --- STOK VE LİSTELEME METODLARI ---
  Future<List<Map<String, dynamic>>> sifirStoklariGetir() async {
    final db = await instance.database;
    return await db.query('stoklar', where: 'durum = ?', whereArgs: ['SIFIR']);
  }

// 1. Tüm stokları getiren metod (Kritik stok uyarısı için lazım)
  Future<List<Map<String, dynamic>>> stoklariGetir() async {
    final db = await instance.database;
    return await db.query('stoklar');
  }


// 3. Mevcut metodunu '2.EL' formatına göre kontrol et
  Future<List<Map<String, dynamic>>> ikinciElStoklariGetir() async {
    final db = await instance.database;
    // Burada sorguyu '2.EL' olarak yapıyoruz çünkü sen öyle kaydetmişsin
    return await db.query('stoklar', where: 'durum = ?', whereArgs: ['2.EL']);
  }
  // 1.  GETİR (Yerel + Hata Denetimi)
  Future<List<Map<String, dynamic>>> stokListesiGetir() async {
    final db = await instance.database;

    // 1. Önce telefondaki (SQLite) stoklara bakıyoruz
    final List<Map<String, dynamic>> yerelStoklar = await db.query('stoklar', orderBy: 'id DESC');

    // 2. Eğer telefonda hiç stok yoksa (0 geliyorsa) Firebase'e gidiyoruz
    if (yerelStoklar.isEmpty) {
      print("☁️ Yerel depo boş, Firebase'den stoklar çekiliyor...");

      try {
        var snapshot = await FirebaseFirestore.instance.collection('stoklar').get();

        if (snapshot.docs.isNotEmpty) {
          for (var doc in snapshot.docs) {
            Map<String, dynamic> veri = doc.data();

            // Firebase'den gelen veriyi yerel veritabanına (SQLite) kaydediyoruz
            // Böylece bir sonraki seferde internete gerek kalmadan cepten okuyacak
            await db.insert('stoklar', {
              'ad': (veri['ad'] ?? "").toString().toUpperCase(),
              'fiyat': double.tryParse(veri['fiyat']?.toString() ?? '0') ?? 0.0,
              'marka': veri['marka'] ?? "",
              'model': veri['model'] ?? "",
              'alt_model': veri['alt_model'] ?? "",
              // Tablonda başka hangi sütunlar varsa buraya ekle abi
            });
          }
          // Kayıt bittikten sonra yerelden tekrar oku ve döndür
          return await db.query('stoklar', orderBy: 'id DESC');
        }
      } catch (e) {
        print("❌ Firebase çekme hatası: $e");
      }
    }

    // 3. Eğer yerel doluysa veya Firebase'de de bir şey yoksa mevcut listeyi döndür
    return yerelStoklar;
  }

  // 2. STOK GÜNCELLE (Hem yerel hem bulut)
  Future<int> stokGuncelle(int id, int adet, double fiyat, String firma) async {
    final db = await instance.database;

    // Yerel güncelleme
    int res = await db.update(
      'stoklar',
      {
        'adet': adet,
        'fiyat': fiyat,
        'tarim_firmalari': firma // 🔥 Burası 'firma' olmalı, yukarıdaki değişkenle aynı
      },
      where: 'id = ?',
      whereArgs: [id],
    );

    try {
      // Firebase bulut güncelleme
      await FirebaseFirestore.instance
          .collection('isletmeler')
          .doc('evren_ticaret')
          .collection('stoklar')
          .doc(id.toString())
          .update({
        'adet': adet,
        'fiyat': fiyat,
        'tarim_firmalari': firma, // 🔥 Buluta da yeni firmayı gönderiyoruz
        'son_guncelleme': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      print("Firebase Güncelleme Hatası: $e");
    }
    return res;
  }

  // --- MÜŞTERİ VE SİLME İŞLEMLERİ ---
  Future<void> musteriSilVeBulutuGuncelle(int musteriId, String musteriAd) async {
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
  Future<void> cekSenetEkle(CekModel cek) async {
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


  Future<void> musteriSilVeStoklariGeriYukle(String musteriId) async {
    final db = await instance.database;
    print("🚀 [DEBUG] Silme işlemi başladı. Müşteri ID: '$musteriId'");

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

  Future<void> stokTransferEt({
    required int urunId,
    required String kaynakSube,
    required String hedefSube,
    required int adet, // Burada 'adet' olarak geliyor
    String? aciklama,
  }) async {
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
        'adet': adet, // 'miktar' yazan yer 'adet' yapıldı
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
        'adet': adet, // 'miktar' yazan yer 'adet' yapıldı
        'aciklama': aciklama ?? 'Şubeler Arası Sevk',
        'timestamp': FieldValue.serverTimestamp(),
      });

      print("Firebase: Sevkiyat ve hareket kaydı mühürlendi.");
    } catch (e) {
      print("Firebase Senkronizasyon Hatası: $e");
      // Burada hata alırsan internetini veya Firebase yetkilerini kontrol et abi.
    }
  }


  Future<void> firebaseStokSenkronize(Map<String, dynamic> stokVerisi) async {
    try {
      await FirebaseFirestore.instance
          .collection('isletmeler')
          .doc('evren_ticaret')
          .collection('stoklar')
          .add({
        'kategori': stokVerisi['kategori'],
        'marka': stokVerisi['marka'],
        'urun': stokVerisi['urun'],        // SQLite'daki 'urun' buraya
        'alt_model': stokVerisi['altModel'], // İSTEDİĞİN ALT MODEL BURASI
        'cins': stokVerisi['altModel'],      // Cins boş kalmasın diye alt_modeli buraya da kopyaladım
        'adet': stokVerisi['adet'],
        'fiyat': stokVerisi['fiyat'],
        'durum': stokVerisi['durum'],
        'sube': stokVerisi['sube'],         // Şube artık sadece burada görünecek
        'tarih': stokVerisi['tarih'],
        'kayit_tarihi': FieldValue.serverTimestamp(),
      });
      print("Firebase TAMAM: ${stokVerisi['urun']} - ${stokVerisi['altModel']} eklendi.");
    } catch (e) {
      print("Firebase Hatası: $e");
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

  Future<List<Map<String, dynamic>>> firmaVeyaMusteriHareketGetir(String ad) async {
    final db = await instance.database;

    // Sadece müşteri hareketlerini getirirsen çiftleme yapmaz
    return await db.query(
        'musteri_hareketleri',
        where: 'musteri_ad = ?',
        whereArgs: [ad],
        orderBy: 'tarih DESC'
    );
  }

  Future<List<Map<String, dynamic>>> firmaHareketleriniGetir(String firmaAd) async {
    final db = await instance.database;

    // firma_ad sütunu bizim aradığımız firmaya eşit olanları tarih sırasına göre getir
    return await db.query(
        'firma_hareketleri',
        where: 'firma_ad = ?',
        whereArgs: [firmaAd],
        orderBy: 'tarih DESC' // En yeni işlem en üstte görünsün
    );
  }

  Future<List<Map<String, dynamic>>> firmaHareketleriniGetirByAd(String firmaAd) async {
    final db = await instance.database;

    // Sadece sabit tabloya bakma, stok_hareketleri ile birleştir ki güncel adet/tutar gelsin
    return await db.rawQuery('''
    SELECT 
      fh.*, 
      sh.adet as guncel_adet, 
      sh.birim_fiyat as guncel_fiyat,
      (sh.adet * sh.birim_fiyat) as guncel_toplam_tutar
    FROM firma_hareketleri fh
    LEFT JOIN stok_hareketleri sh ON fh.stok_hareket_id = sh.id 
    WHERE fh.firma_id = (SELECT id FROM firmalar WHERE ad = ?)
    
    UNION ALL
    
    SELECT 
      mh.*, 
      sh.adet as guncel_adet, 
      sh.birim_fiyat as guncel_fiyat,
      (sh.adet * sh.birim_fiyat) as guncel_toplam_tutar
    FROM musteri_hareketleri mh
    LEFT JOIN stok_hareketleri sh ON mh.stok_hareket_id = sh.id
    WHERE mh.musteri_id = (SELECT id FROM musteriler WHERE ad = ?)
    
    ORDER BY tarih DESC
  ''', [firmaAd, firmaAd]);
  }


  Future<void> tahsilatYap({
    required String musteriAd,
    required double miktar,
    required String odemeYontemi,
  }) async {
    final db = await instance.database;

    await db.transaction((txn) async {
      // 1. Yerel Bakiyeyi Güncelle
      await txn.execute('UPDATE musteriler SET bakiye = bakiye - ? WHERE ad = ?', [miktar, musteriAd]);

      // 2. Yerel Hareket Kaydı
      Map<String, dynamic> hareket = {
        'musteri_ad': musteriAd,
        'islem': 'TAHSILAT',
        'tutar': miktar,
        'aciklama': 'ÖDEME ALINDI ($odemeYontemi)',
        'tarih': DateTime.now().toIso8601String(),
      };
      int hareketId = await txn.insert('musteri_hareketleri', hareket);

      // 3. KUYRUĞA EKLE (İnternet gelince Firebase bakiyesini de düşsün)
      await txn.insert('sync_queue', {
        'type': 'UPDATE_BALANCE',
        'collection': 'musteriler',
        'doc_id': musteriAd,
        'data': jsonEncode({'miktar': -miktar, 'hareket': hareket}),
        'is_synced': 0,
        'created_at': DateTime.now().toIso8601String(),
      });
    });
    print("✅ Tahsilat kaydedildi, internet bulunca buluta yansıyacak.");
  }


  Future<int> stokEkle(Map<String, dynamic> data, {bool fromFirebase = false}) async {
    final db = await instance.database;

    try {
      // 1. Veri Hazırlama
      String marka = data['marka']?.toString().toUpperCase() ?? "";
      String model = (data['model'] ?? data['urun'] ?? "").toString().toUpperCase();
      String altModel = (data['alt_model'] ?? data['altModel'] ?? "").toString().trim().toUpperCase();
      String sube = data['sube'] ?? "TEFENNİ";
      String fId = data['firebase_id']?.toString() ?? "";

      // 🔥 YENİ: Eğer veride ana_stok_id varsa al, yoksa null kalsın (aşağıda atanacak)
      int? anaStokId = data['ana_stok_id'] != null ? int.tryParse(data['ana_stok_id'].toString()) : null;

      double fiyat = double.tryParse(data['fiyat']?.toString().replaceAll(',', '.') ?? "0") ?? 0.0;
      double adet = double.tryParse(data['adet']?.toString().replaceAll(',', '.') ?? "0") ?? 0.0;
      String durum = data['durum'] ?? "SIFIR";

      // 2. KRİTİK KONTROL: Aynı şubede bu maldan zaten var mı?
      List<Map<String, dynamic>> mevcut;

      if (fId.isNotEmpty) {
        mevcut = await db.query('stoklar', where: 'firebase_id = ?', whereArgs: [fId]);
      } else {
        // Hem şube hem marka/model/alt_model kontrolü yaparak mükerrer kaydı engelliyoruz
        mevcut = await db.query(
          'stoklar',
          where: 'marka = ? AND model = ? AND IFNULL(alt_model, "") = ? AND sube = ?',
          whereArgs: [marka, model, altModel, sube],
        );
      }

      // =========================================================
      // ♻️ GÜNCELLEME (AYNI ŞUBEDE VARSA ÜSTÜNE EKLE)
      // =========================================================
      if (mevcut.isNotEmpty) {
        int id = mevcut.first['id'] as int;

        // Eğer mevcut kayıtta ana_stok_id varsa onu koru
        int? mevcutAnaId = mevcut.first['ana_stok_id'] != null
            ? int.tryParse(mevcut.first['ana_stok_id'].toString())
            : null;

        Map<String, dynamic> guncelVeri = {
          'firebase_id': fId.isNotEmpty ? fId : mevcut.first['firebase_id'],
          'adet': fromFirebase ? adet : (double.tryParse(mevcut.first['adet'].toString()) ?? 0) + adet,
          'fiyat': fiyat,
          'durum': durum,
          'ana_stok_id': anaStokId ?? mevcutAnaId, // Kimliği koru
          'is_synced': fromFirebase ? 1 : 0
        };

        await db.update('stoklar', guncelVeri, where: 'id = ?', whereArgs: [id]);
        debugPrint("♻️ Stok güncellendi: $marka $model ($sube)");
        return id;
      }

      // =========================================================
      // ➕ YENİ KAYIT (İLK KEZ EKLENİYOR VEYA FARKLI ŞUBE)
      // =========================================================
      Map<String, dynamic> temizVeri = {
        'ana_stok_id': anaStokId, // Transferden geliyorsa dolu gelir
        'firebase_id': fId,
        'kategori': data['kategori']?.toString().toUpperCase() ?? "GENEL",
        'marka': marka,
        'model': model,
        'alt_model': altModel,
        'adet': adet,
        'fiyat': fiyat,
        'sube': sube,
        'durum': durum,
        'tarih': data['tarih'] ?? DateFormat('dd.MM.yyyy').format(DateTime.now()),
        'tarim_firmalari': data['tarim_firmalari'] ?? data['firma'] ?? "BELİRTİLMEDİ",
        'sektor': data['sektor'] ?? "TARIM",
        'foto': data['foto'] ?? "",
        'is_synced': fromFirebase ? 1 : 0
      };

      int yeniId = await db.insert(
        'stoklar',
        temizVeri,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      // 🔥 KRİTİK ADIM: Eğer bu bir transfer değilse (anaStokId boşsa),
      // yeni oluşan ID'yi ana_stok_id olarak ata. Bu malın "Kökü" budur.
      if (anaStokId == null) {
        await db.update('stoklar', {'ana_stok_id': yeniId}, where: 'id = ?', whereArgs: [yeniId]);
        anaStokId = yeniId;
      }

      // Localden eklenen veriyi Firebase'e uçur
      if (!fromFirebase) {
        try {
          await _firestore.collection('stoklar').doc(yeniId.toString()).set({
            ...temizVeri,
            'ana_stok_id': anaStokId, // Güncel ana ID ile gönder
            'firebase_id': yeniId.toString(),
            'is_synced': 1
          });
          await db.update('stoklar', {'is_synced': 1, 'firebase_id': yeniId.toString()}, where: 'id = ?', whereArgs: [yeniId]);
        } catch (e) {
          debugPrint("⚠️ Firebase Sync Hatası: $e");
        }
      }

      return yeniId;
    } catch (e) {
      debugPrint("❌ stokEkle PATLADI: $e");
      return -1;
    }
  }

  Future<int> stokTanimEkle(Map<String, dynamic> data) async {
    final db = await instance.database;

    // 1. VERİ TEMİZLİĞİ VE STANDARTLAŞTIRMA
    String marka = data['marka']?.toString().toUpperCase().trim() ?? "";
    String model = data['model']?.toString().toUpperCase().trim() ?? "";
    String altV = (data['alt_model'] ?? data['altmodel'] ?? "").toString().toUpperCase().trim();
    String kategori = data['kategori']?.toString().toUpperCase().trim() ?? "GENEL";

    // Artik sadece 'tarim_firmalari' kullaniyoruz
    String firma = (data['tarim_firmalari'] ?? "BİLİNMEYEN").toString().toUpperCase().trim();
    String durum = data['durum'] ?? "AKTİF";

    // 2. MÜKERRER KONTROLÜ (Grup Mantığı)
    // Aynı Marka-Model-AltModel kombinasyonu varsa tekrar eklemesin
    final List<Map<String, dynamic>> varMi = await db.query(
      'stok_tanimlari',
      where: 'marka = ? AND model = ? AND alt_model = ?',
      whereArgs: [marka, model, altV],
    );

    // Veritabanı tablonla %100 uyumlu map
    Map<String, dynamic> sqlData = {
      'kategori': kategori,
      'marka': marka,
      'model': model,
      'alt_model': altV,
      'altmodel': altV,
      'tarim_firmalari': firma, // Sütun adını buna sabitledik
      'durum': durum,
      'is_synced': 1,
      'urun': "$marka $model $altV".trim()
    };

    int id;
    if (varMi.isNotEmpty) {
      id = varMi.first['id'];
      await db.update('stok_tanimlari', sqlData, where: 'id = ?', whereArgs: [id]);
    } else {
      id = await db.insert('stok_tanimlari', sqlData);
    }

    // 3. FIREBASE SENKRONİZASYONU (Grup ID ile)
    try {
      // Boşlukları alt tire yaparak temiz bir döküman ID'si oluşturuyoruz
      String docId = "${marka}_${model}_$altV".replaceAll(RegExp(r'\s+'), '_');

      await FirebaseFirestore.instance
          .collection('stok_tanimlari')
          .doc(docId)
          .set({
        ...sqlData,
        'firebase_id': docId,
        'sql_id': id,
        'son_guncelleme': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // Yerelde de Firebase ID'sini güncelle
      await db.update('stok_tanimlari', {'firebase_id': docId}, where: 'id = ?', whereArgs: [id]);

    } catch (e) {
      print("⚠️ Firebase Senkronize Hatası: $e");
      await db.update('stok_tanimlari', {'is_synced': 0}, where: 'id = ?', whereArgs: [id]);
    }

    return id;
  }

  Future<int> stokHareketEkle(Map<String, dynamic> row) async {
    final db = await instance.database;

    // 1. VERİLERİ HAZIRLA VE TEMİZLE
    String marka = row['marka']?.toString().toUpperCase() ?? "";
    String model = row['model']?.toString().toUpperCase() ?? "";
    String urunAdi = row['urun_adi']?.toString().toUpperCase() ?? "BİLİNMEYEN ÜRÜN";
    String firmaAd = (row['tarim_firmalari'] ?? row['ad'] ?? "BİLİNMEYEN").toString().toUpperCase();

    double miktar = double.tryParse(row['miktar']?.toString() ?? "0") ?? 0.0;
    double birimFiyat = double.tryParse(row['birim_fiyat']?.toString() ?? "0") ?? 0.0;
    double toplamTutar = miktar * birimFiyat; // PDF ve Ekstre için asıl rakam

    // SQL'e gidecek stok verisi
    Map<String, dynamic> sqlVerisi = {
      ...row,
      'marka': marka,
      'model': model,
      'tarim_firmalari': firmaAd,
      'miktar': miktar,
      'birim_fiyat': birimFiyat,
      'tutar': toplamTutar,
      'tarih': row['tarih'] ?? DateTime.now().toIso8601String(),
      'is_synced': 0,
    };

    // 2. ADIM: STOK TABLOSUNA KAYDET
    int id = await db.insert('stok_hareketleri', sqlVerisi);

    // 3. ADIM: CARİ HAREKETLERE (EKSTREYE) OTOMATİK YAZ
    // Bu kısım olmazsa PDF ve Ödemeler listesi güncellenmez!
    try {
      await db.insert('firma_hareketleri', {
        'firma_id': row['firma_id'],
        'stok_id': id, // Stokla cariyi birbirine bağladık
        'urun_adi': "$urunAdi ($marka $model)",
        'adet': miktar,
        'birim_fiyat': birimFiyat,
        'tutar': toplamTutar,
        'tip': row['tip'] ?? "ALIM", // ALIM veya SATIŞ
        'tarih': sqlVerisi['tarih'],
      });

      // Ana bakiyeyi de anında güncelle
      await firmaBakiyesiGuncelle(firmaAd, toplamTutar, row['tip'] ?? "ALIM");

    } catch (e) {
      debugPrint("Cari güncelleme hatası: $e");
    }

    // 4. ADIM: FIREBASE YEDEKLEME
    try {
      String docId = "${DateTime.now().millisecondsSinceEpoch}_$firmaAd";

      await FirebaseFirestore.instance
          .collection('stok_hareketleri')
          .doc(docId)
          .set({
        ...sqlVerisi,
        'sql_id': id,
        'server_tarih': FieldValue.serverTimestamp(),
      });

      // Başarılıysa SQL'de işaretle
      await db.update(
        'stok_hareketleri',
        {'is_synced': 1},
        where: 'id = ?',
        whereArgs: [id],
      );

      debugPrint("✅ İşlem hem SQL'e hem Buluta kaydedildi: $docId");
    } catch (e) {
      debugPrint("⚠️ Firebase Hatası (İnternet Yok): $e");
      // İnternet yoksa is_synced 0 kalır, sonraki senkronizasyonda gider.
    }

    return id;
  }

  // DatabaseHelper.dart içindeki fonksiyonu bu hale getir:
  Future<int> stokFotoGuncelle(int id, String yol, {String? firebaseId}) async {
    final db = await instance.database;
    return await db.update(
      'stoklar',
      {
        'foto': yol,   // 🔥 foto_yolu yerine foto yazdık!
        'is_synced': 0
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

// --- FİRMA VE TANIM LİSTELERİ (Eksiksiz) ---
  Future<List<Map<String, dynamic>>> firmaListesiGetir() async {
    final db = await database;
    return await db.query('tarim_firmalari');
  }

  Future<List<Map<String, dynamic>>> stokTanimlariniGetir() async {
    final db = await database;
    return await db.query('stok_tanimlari');
  }




  Future<void> bulutlaSenkronizeEt() async {
    final db = await instance.database;

    // Kuyruktaki (gönderilmemiş) işlemleri al
    List<Map<String, dynamic>> kuyruk = await db.query(
        'sync_queue',
        where: 'is_synced = ?',
        whereArgs: [0]
    );

    if (kuyruk.isEmpty) return;

    for (var islem in kuyruk) {
      try {
        String collection = islem['collection']; // urunler, cekler, musteriler vb.
        String docId = islem['doc_id'];
        Map<String, dynamic> veri = jsonDecode(islem['data']);

        // DÜZELTİLEN YOL: isletmeler/evren_ticaret kısmını sildik!
        // Direkt resimdeki gibi koleksiyon ismine gidiyoruz.
        if (islem['type'] == 'INSERT' || islem['type'] == 'UPDATE') {
          await _firestore
              .collection(collection) // Resimdeki 'urunler' veya 'cekler'e direkt gider
              .doc(docId)
              .set({...veri, 'sonGuncelleme': FieldValue.serverTimestamp()});
        }
        else if (islem['type'] == 'DELETE') {
          await _firestore
              .collection(collection)
              .doc(docId)
              .delete();
        }

        // Başarılıysa telefonun içindeki listede "tamam" diye işaretle
        await db.update('sync_queue', {'is_synced': 1}, where: 'id = ?', whereArgs: [islem['id']]);
        print("🚀 Veri mühürlendi: $collection -> $docId");

      } catch (e) {
        print("❌ Firebase Bağlantı Hatası: $e");
        break;
      }
    }
  }
  // Tüm metodlar bunu kullanacak, Firebase karmaşası bitecek
  Future<void> _kuyrugaEkle(String tip, String tablo, String docId, Map<String, dynamic> veri) async {
    final db = await instance.database;
    await db.insert('sync_queue', {
      'type': tip, // INSERT, DELETE, UPDATE_BALANCE
      'collection': tablo,
      'doc_id': docId,
      'data': jsonEncode(veri),
      'is_synced': 0,
      'created_at': DateTime.now().toIso8601String(),
    });
  }
  Future<void> herSeyiSenkronizeEt() async {
    final db = await instance.database;
    List<Map<String, dynamic>> bekleyenler = await db.query('sync_queue', where: 'is_synced = ?', whereArgs: [0]);

    if (bekleyenler.isEmpty) return;

    for (var islem in bekleyenler) {
      try {
        final data = jsonDecode(islem['data']);
        final collection = islem['collection'];
        final docId = islem['doc_id'];
        final type = islem['type'];

        if (type == 'INSERT') {
          await _firestore.collection(collection).doc(docId).set({...data, 'server_time': FieldValue.serverTimestamp()});
        }
        else if (type == 'DELETE') {
          await _firestore.collection(collection).doc(docId).delete();
        }
        else if (type == 'UPDATE_BALANCE') {
          // Hem bakiye güncelle hem hareket kaydı oluştur
          await _firestore.collection('musteriler').doc(docId).update({'bakiye': FieldValue.increment(data['miktar'])});
          await _firestore.collection('musteri_hareketleri').add({
            'musteri_ad': docId,
            'islem': data['islem'],
            'tutar': (data['miktar'] as double).abs(),
            'aciklama': data['aciklama'],
            'tarih': DateTime.now().toIso8601String()
          });
        }

        // İşlem bitince telefondan "gönderildi" olarak işaretle
        await db.update('sync_queue', {'is_synced': 1}, where: 'id = ?', whereArgs: [islem['id']]);
        print("🚀 $collection tablosundaki $docId verisi buluta mühürlendi.");

      } catch (e) {
        print("❌ İnternet yok, bekleniyor: $e");
        break;
      }
    }
  }




  Future<int> musteriHareketEkle(Map<String, dynamic> veri) async {
    final db = await instance.database;
    final firestore = FirebaseFirestore.instance;

    // 🧼 VERİ TEMİZLEME
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
      'tarih': veri['tarih'] ??
          DateFormat('dd.MM.yyyy').format(DateTime.now()),
      'is_synced': 0,
    };

    int localId = -1;

    // 💾 1. SQLITE KAYDI (HAREKET TABLOSU)
    try {
      localId = await db.insert(
        'musteri_hareketleri',
        temizVeri,
      );
      print("✅ SQL HAREKET KAYIT OK → ID: $localId");

      // 🧮 2. MATEMATİKSEL BAKİYE GÜNCELLEME (ANA TABLO)
      // Hareket eklenince ana tablodaki bakiyeyi de artıralım veya düşürelim
      double miktar = temizVeri['tutar'];
      String mId = temizVeri['musteri_id'];

      if (temizVeri['islem'] == 'TAHSILAT') {
        // Tahsilat gelince borçtan düşüyoruz
        await db.rawUpdate(
            'UPDATE musteriler SET bakiye = bakiye - ? WHERE id = ?',
            [miktar, mId]
        );
        print("📉 TAHSİLAT: Müşteri bakiyesinden $miktar TL düşüldü.");
      } else {
        // Satış veya başka bir şeyse borca ekliyoruz
        await db.rawUpdate(
            'UPDATE musteriler SET bakiye = bakiye + ? WHERE id = ?',
            [miktar, mId]
        );
        print("📈 SATIŞ: Müşteri bakiyesine $miktar TL eklendi.");
      }

    } catch (e) {
      print("❌ SQLITE HATA: $e");
      return -1;
    }

    // ☁️ 3. FIRESTORE SENKRON (BAĞIMSIZ ÇALIŞIR)
    try {
      await firestore
          .collection('musteri_hareketleri')
          .doc("HL_$localId")
          .set({
        ...temizVeri,
        'sqlite_id': localId,
        'server_tarih': FieldValue.serverTimestamp(),
      });

      // ✔ sync başarılı → SQL güncelle
      await db.update(
        'musteri_hareketleri',
        {'is_synced': 1},
        where: 'id = ?',
        whereArgs: [localId],
      );

      print("🚀 FIRESTORE SYNC OK → ID: HL_$localId");
    } catch (e) {
      print("⚠ FIRESTORE BAŞARISIZ (kuyrukta kaldı): $e");
    }

    return localId;
  }

  // DatabaseHelper.dart içinde veritabanını açtığın yere (onOpen veya onUpgrade) ekleyebilirsin
  Future<void> _tabloyuGuncelle(Database db) async {
    try {
      // Tabloya 'musteri_ad' sütununu zorla ekliyoruz
      await db.execute("ALTER TABLE musteri_hareketleri ADD COLUMN musteri_ad TEXT");
      print("✅ musteri_ad sütunu başarıyla eklendi.");
    } catch (e) {
      // Sütun zaten varsa hata verir, sorun değil; "Zaten var" demektir.
      print("Bilgi: Sütun zaten mevcut veya eklenemedi: $e");
    }
  }
  Future<void> bekleyenHareketleriSenkronizeEt() async {
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

    for (var hareket in bekleyenler) {
      try {
        // 🧼 FIRESTORE İÇİN VERİYİ HAZIRLA (Ham veriyi temizleyerek gönder)
        // SQLite'dan gelen Map değiştirilemez (immutable) olabilir, o yüzden kopyasını alıyoruz
        Map<String, dynamic> firestoreVeri = Map<String, dynamic>.from(hareket);

        // Firestore'a gitmesine gerek olmayan veya özel işlenecek alanları ayarla
        int sqliteId = firestoreVeri['id'];
        firestoreVeri.remove('id'); // SQLite'ın otomatik ID'sini kaldırıyoruz (doküman adında var zaten)
        firestoreVeri['is_synced'] = 1; // Firestore'da her zaman 1 görünsün
        firestoreVeri['server_tarih'] = FieldValue.serverTimestamp();
        firestoreVeri['sqlite_id'] = sqliteId;

        // ☁️ Buluta gönder
        await _firestore
            .collection('musteri_hareketleri')
            .doc("HL_$sqliteId")
            .set(firestoreVeri);

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
        break; // İnternet hala yoksa veya bir sorun varsa zorlama, döngüyü kır
      }
    }
  }

  Future<List<Map<String, dynamic>>> musterilerGetir() async {
    final db = await instance.database;
    // Hem bakiyeyi garantiye al hem de is_synced durumunu gör
    return await db.rawQuery('''
    SELECT id, ad, tc, tel, sube, 
    IFNULL(bakiye, 0) as bakiye, 
    IFNULL(is_synced, 0) as is_synced 
    FROM musteriler 
    ORDER BY ad ASC
  ''');
  }

  Future<int> stokSil(int id) async {
    final db = await instance.database;
    int res = 0;

    List<Map<String, dynamic>> urunSorgu = await db.query('stoklar', where: 'id = ?', whereArgs: [id]);

    if (urunSorgu.isNotEmpty) {
      var urun = urunSorgu.first;
      String firmaAdi = urun['tarim_firmalari']?.toString() ?? urun['firma']?.toString() ?? "BELİRTİLMEDİ";
      String? firebaseId = urun['firebase_id']?.toString();
      double fiyat = double.tryParse(urun['fiyat'].toString()) ?? 0;
      double adet = double.tryParse(urun['adet'].toString()) ?? 0;
      double toplamTutar = fiyat * adet;

      await db.transaction((txn) async {
        res = await txn.delete('stoklar', where: 'id = ?', whereArgs: [id]);

        if (firmaAdi != "BELİRTİLMEDİ") {
          // 🔥 Hata buradaydı, 'bakiye' yerine 'borc' yaptık.
          await txn.rawUpdate(
              'UPDATE tarim_firmalari SET borc = borc - ? WHERE ad = ?',
              [toplamTutar, firmaAdi]
          );
        }
      });

      try {
        if (firebaseId != null && firebaseId.isNotEmpty && firebaseId != "hükümsüz") {
          await _firestore.collection('stoklar').doc(firebaseId).delete();
          print("✅ Firebase: Ürün buluttan silindi.");
        } else {
          await _firestore.collection('stoklar').doc(id.toString()).delete();
        }
      } catch (e) {
        print("❌ Firebase Silme Hatası: $e");
      }
    }
    return res;
  }

// Stok Şube Değiştir: Malın yerini değiştirirken kayıt tutar.
  Future<void> stokSubeDegistir(int id, String yeniSube) async {
    final db = await instance.database;

    // 1. ADIM: Yerelde şube bilgisini güncelle
    await db.rawUpdate('UPDATE stoklar SET sube = ? WHERE id = ?', [yeniSube, id]);

    try {
      // 2. ADIM: Firebase'de şubeyi değiştir ve işlem tarihini mühürle
      await _firestore.collection('stoklar').doc(id.toString()).update({
        'sube': yeniSube,
        'sube_degisim_tarihi': FieldValue.serverTimestamp(),
      });

      // 3. ADIM (Opsiyonel): Bu transferi 'stok_hareketleri' tablosuna da "SEVK" olarak işle
      // Böylece malın Tefenni'den Aksu'ya geçtiği kayıt altına alınır.
      print("Firebase: Ürün şubesi $yeniSube olarak güncellendi.");
    } catch (e) { print("Firebase Şube Değişim Hatası: $e"); }
  }

  Future<int> stokTanimSil(String firma, String marka, String model, String altModel) async {
    final db = await instance.database;
    int res = 0;

    String f = firma.trim().toUpperCase();
    String m = marka.trim().toUpperCase();
    String mod = model.trim().toUpperCase();
    String alt = altModel.trim().toUpperCase();

    try {
      // 1. ADIM: SQLite Silme
      // Not: SQLite'da hangi sütun adını eklediysen (alt_model mi altmodel mi) onu buraya yazmalısın.
      // Eğer ikisini de eklediysen en garantisi 'alt_model' üzerinden gitmektir.
      if (alt.isNotEmpty) {
        res = await db.delete('stok_tanimlari',
            where: 'tarim_firmalari = ? AND marka = ? AND model = ? AND (alt_model = ? OR altmodel = ?)',
            whereArgs: [f, m, mod, alt, alt]); // Çift kontrol!
      } else if (mod.isNotEmpty) {
        res = await db.delete('stok_tanimlari',
            where: 'tarim_firmalari = ? AND marka = ? AND model = ?',
            whereArgs: [f, m, mod]);
      } else {
        res = await db.delete('stok_tanimlari',
            where: 'tarim_firmalari = ? AND marka = ?',
            whereArgs: [f, m]);
      }

      // 2. ADIM: Firebase Silme
      var sorgu = _firestore.collection('stok_tanimlari')
          .where('tarim_firmalari', isEqualTo: f)
          .where('marka', isEqualTo: m);

      if (mod.isNotEmpty) sorgu = sorgu.where('model', isEqualTo: mod);

      // Firebase tarafında bitişik mi alt tireli mi? İkisine de bakıyoruz.
      final snapshot = await sorgu.get();
      for (var doc in snapshot.docs) {
        // Eğer döküman içinde bizim aradığımız alt model varsa (iki ihtimalden biriyle) sil
        var d = doc.data();
        if (alt.isEmpty || d['alt_model'] == alt || d['altmodel'] == alt) {
          await doc.reference.delete();
        }
      }
      print("✅ Silme işlemi tamam.");
    } catch (e) {
      print("❌ Silme Hatası: $e");
    }
    return res;
  }

  Future<int> stokTanimGuncelleById(int id, Map<String, dynamic> veri) async {
    final db = await instance.database;
    return await db.update(
      'stok_tanimlari',
      veri,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> stokTanimGuncelle(
      String firma,
      String eskiMarka,
      String eskiModel,
      String eskiAltModel,
      String yeniDeger,
      String tip) async {
    final db = await instance.database;

    try {
      // 1. ADIM: SQLite Güncelleme
      if (tip == "MARKA") {
        await db.update('stoklar', {'marka': yeniDeger}, where: 'marka = ?', whereArgs: [eskiMarka]);
        await db.update('stok_tanimlari', {'marka': yeniDeger}, where: 'tarim_firmalari = ? AND marka = ?', whereArgs: [firma, eskiMarka]);
      }
      else if (tip == "MODEL") {
        await db.update('stok_tanimlari', {'model': yeniDeger}, where: 'tarim_firmalari = ? AND marka = ? AND model = ?', whereArgs: [firma, eskiMarka, eskiModel]);
      }
      else if (tip == "ALTMODEL") {
        // GARANTİ: Hem alt_model hem altmodel sütunlarını güncellemeye çalış
        Map<String, dynamic> updateData = {};
        updateData['alt_model'] = yeniDeger;
        updateData['altmodel'] = yeniDeger;

        await db.update('stok_tanimlari', updateData,
            where: 'tarim_firmalari = ? AND marka = ? AND model = ? AND (alt_model = ? OR altmodel = ?)',
            whereArgs: [firma, eskiMarka, eskiModel, eskiAltModel, eskiAltModel]);
      }

      // 2. ADIM: Firebase Senkronizasyonu
      var sorgu = _firestore.collection('stok_tanimlari')
          .where('tarim_firmalari', isEqualTo: firma)
          .where('marka', isEqualTo: eskiMarka);

      if (tip == "MODEL" || tip == "ALTMODEL") sorgu = sorgu.where('model', isEqualTo: eskiModel);

      final snapshot = await sorgu.get();

      for (var doc in snapshot.docs) {
        var d = doc.data();
        // Alt model güncellemesi ise sadece doğru alt modeli bulup güncelle
        if (tip == "ALTMODEL") {
          if (d['alt_model'] == eskiAltModel || d['altmodel'] == eskiAltModel) {
            await doc.reference.update({
              'alt_model': yeniDeger,
              'altmodel': yeniDeger, // Firebase'de de ikisini birden güncelle, kafa rahat olsun
              'son_guncelleme': FieldValue.serverTimestamp(),
            });
          }
        } else {
          // Marka veya Model güncellemesi
          String alan = tip == "MARKA" ? "marka" : "model";
          await doc.reference.update({
            alan: yeniDeger,
            'son_guncelleme': FieldValue.serverTimestamp(),
          });
        }
      }
      print("✅ Güncelleme tamam.");
    } catch (e) {
      print("❌ Güncelleme Hatası: $e");
    }
  }

  Future<int> stokHareketiEkle(Map<String, dynamic> veri) async {
    final db = await instance.database;
    int id = 0;

    // 1. ADIM: SQLite Transaction (Ya hep ya hiç)
    // Hareket eklenip miktar güncellenemezse işlem iptal edilir.
    await db.transaction((txn) async {
      id = await txn.insert('stok_hareketleri', veri);

      // Hareket türüne göre (Giriş: +, Çıkış: -) ana stoğu güncelle
      // 'miktar' alanının çıkışlarda eksi değerli geldiğinden emin ol abi.
      // stokHareketiEkle içindeki SQL kısmını buna çevir:
      await txn.execute('''
  UPDATE stoklar 
  SET adet = adet + ? 
  WHERE id = ?
''', [veri['miktar'], veri['stok_id']]);
    });

    // 2. ADIM: Firebase Senkronizasyonu
    try {
      // Hareketi buluta işle
      await _firestore.collection('stok_hareketleri').doc(id.toString()).set({
        ...veri,
        'id': id,
        'islem_tarihi': FieldValue.serverTimestamp(),
      });

      // Burada 'stok_tanimlari' koleksiyonuna gidiyorsun
      await _firestore.collection('stok_tanimlari').doc(veri['stok_id'].toString()).update({
        'mevcut_adet': FieldValue.increment(veri['miktar']),
      });

      print("Firebase: Stok hareketi ve güncel miktar buluta işlendi.");
    } catch (e) {
      print("Firebase Stok Hatası: $e");
    }

    return id;
  }
  Future<List<Map<String, dynamic>>> subeyeGoreStokGetir(String subeAdi) async {
    print("📡 Firebase'den $subeAdi şubesi için stoklar çekiliyor...");
    try {
      // 1. Firebase'den çekiyoruz (Senin yapına göre 'alt' alanını kontrol ediyoruz)
      final snapshot = await _firestore.collection('stoklar')
          .where('alt', isEqualTo: subeAdi) // Firebase'deki 'alt' alanına bakıyoruz
          .get();

      if (snapshot.docs.isNotEmpty) {
        print("✅ Firebase'den ${snapshot.docs.length} adet stok geldi.");
        return snapshot.docs.map((doc) {
          var data = doc.data();
          data['id_bulut'] = doc.id; // Firebase ID'sini de kaybetme
          return data;
        }).toList();
      } else {
        print("⚠️ Firebase'de bu şubeye ait veri bulunamadı.");
      }
    } catch (e) {
      print("❌ Firebase Sorgu Hatası: $e");
    }

    // 2. Firebase boşsa veya hata verirse yerel SQLite'a bak
    print("🏠 Yerel veritabanına (SQLite) bakılıyor...");
    final db = await instance.database;
    return await db.query('stoklar', where: 'sube = ?', whereArgs: [subeAdi]);
  }
  Future<int> mazotEkle(Map<String, dynamic> veri) async {
    int id = await (await instance.database).insert('mazot_kayitlari', veri);
    try {
      await _firestore.collection('mazot_kayitlari').doc(id.toString()).set({
        ...veri,
        'id': id,
        'kayit_tarihi': FieldValue.serverTimestamp(),
      });
    } catch (e) { print("Firebase Mazot Kayıt Hatası: $e"); }
    return id;
  }


  Future<List<Map<String, dynamic>>> mazotListesiGetir(String sezon) async {
    final db = await instance.database;
    // SORGUNUN SEZON FİLTRELİ OLDUĞUNDAN EMİN OL
    return await db.query('mazot_takibi', where: 'sezon = ?', whereArgs: [sezon]);
  }
  // Mazot Güncelle: Kaydı hem yerelde hem bulutta düzeltir
  Future<int> mazotGuncelle(int id, Map<String, dynamic> data) async {
    final db = await instance.database;

    // 1. ADIM: Yerel SQLite güncellemesi (Tablo adı: mazot_takibi)
    int res = await db.update(
        "mazot_takibi",
        data,
        where: 'id = ?',
        whereArgs: [id]
    );

    // 2. ADIM: Firebase senkronizasyonu
    try {
      // Koleksiyon adını projenle uyumlu hale getir (Örn: bicer_mazotlar)
      await _firestore.collection('bicer_mazotlar').doc(id.toString()).set({
        ...data,
        'son_guncelleme': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true)); // Tamamen silip yazmak yerine sadece değişeni günceller

      print("✅ Firebase: Mazot kaydı güncellendi.");
    } catch (e) {
      print("❌ Firebase Mazot Güncelleme Hatası: $e");
    }

    return res;
  }

  Future<void> bicerFaturaGorseliEkleTC(String tcNo, File imageFile) async {
    try {
      // 1. Dosyayı telefon hafızasına kopyala
      final directory = await getApplicationDocumentsDirectory();
      final String fileName = "fatura_${tcNo}_${DateTime.now().millisecondsSinceEpoch}.jpg";
      final File localImage = await imageFile.copy('${directory.path}/$fileName');

      final db = await instance.database;

      // İşlemleri toplu (Transaction) yapmak daha sağlıklıdır
      await db.transaction((txn) async {
        // ADIM A: Ana müşteri tablosunu güncelle (Rehber kısmı)
        await txn.update(
          'bicer_musterileri',
          {'fotograf_yolu': localImage.path}, // Yeni eklediğin sütun
          where: 'firebase_id = ? OR tc = ?',
          whereArgs: [tcNo, tcNo],
        );

        // ADIM B: O müşteriye ait tüm hasat kayıtlarını güncelle (İşler kısmı)
        await txn.update(
          'bicer_isleri',
          {'fatura_yolu': localImage.path},
          where: 'firebase_id = ?',
          whereArgs: [tcNo],
        );
      });

      print("✅ Müşteri ve Hasat tabloları güncellendi: ${localImage.path}");
    } catch (e) {
      print("❌ bicerFaturaGorseliEkleTC Hatası: $e");
      rethrow;
    }
  }

  Future<int> mazotSil(int id, {String? firebaseId}) async {
    final db = await instance.database;

    // 1. Yerel SQLite'dan sil (Tablo adı: mazot_takibi)
    int res = await db.delete(
        'mazot_takibi',
        where: 'id = ?',
        whereArgs: [id]
    );

    // 2. Firebase'den sil
    if (firebaseId != null && firebaseId.isNotEmpty) {
      try {
        // KOLEKSİYON ADINI BURADA 'bicer_mazotlar' OLARAK SABİTLEDİK
        await FirebaseFirestore.instance
            .collection('bicer_mazotlar')
            .doc(firebaseId)
            .delete();
        print("✅ Firebase: $firebaseId buluttan uçuruldu.");
      } catch (e) {
        print("❌ Firebase Silme Hatası: $e");
      }
    }
    return res;
  }


  Future<List<Map<String, dynamic>>> tahsilatListesiGetir(String isim) async {
    final db = await instance.database;

    try {
      // 1. ADIM: Firebase'den çekmeyi dene
      final snapshot = await _firestore
          .collection('tahsilatlar')
          .where('ciftci_ad', isEqualTo: isim)
          .orderBy('tarih', descending: true)
          .get(const GetOptions(source: Source.serverAndCache)); // Hem sunucu hem önbellek

      // Eğer Firebase'e ulaşabildiyse (boş olsa bile), bulut verisini döndür
      // Bu sayede "bulutta silinmiş bir verinin telefonda kalması" hatasını önleriz
      return snapshot.docs.map((doc) => {
        'id_firebase': doc.id,
        ...doc.data(),
      }).toList();

    } catch (e) {
      // 2. ADIM: İnternet hatası (Timeout veya Bağlantı yok) durumunda SQLite'a dön
      print("Firebase erişim hatası, yerel veriye dönülüyor: $e");

      return await db.query(
          'tahsilatlar',
          where: 'ciftci_ad = ?',
          whereArgs: [isim],
          orderBy: 'tarih DESC'
      );
    }
  }

  Future<int> tahsilatEkle(Map<String, dynamic> veri) async {
    final db = await instance.database;

    // Eğer veri içinde odeme_tipi yoksa varsayılan olarak NAKİT ata
    Map<String, dynamic> guncelVeri = Map.from(veri);
    guncelVeri['odeme_tipi'] = veri['odeme_tipi'] ?? "NAKİT";

    int id = await db.insert('tahsilatlar', guncelVeri);

    try {
      await _firestore.collection('tahsilatlar').doc(id.toString()).set({
        ...guncelVeri,
        'id': id,
        'kayit_zamani': FieldValue.serverTimestamp(),
      });
    } catch (e) { print("Firebase Tahsilat Hatası: $e"); }

    return id;
  }

  Future<void> odemeEkle(int isId, double miktar, String tarih) async {
    final db = await instance.database;

    // 1. ADIM: SQLite Transaction (Ya hep ya hiç kuralı)
    // Eğer ödeme eklenip bakiye güncellenemezse, tüm işlem geri alınır.
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

    // 2. ADIM: Firebase Senkronizasyonu
    try {
      // Ödeme kaydını buluta ekle
      await _firestore.collection('odemeler').add({
        'is_id': isId,
        'miktar': miktar,
        'tarih': tarih,
        'islem_zamani': FieldValue.serverTimestamp(),
      });

      // Biçer işindeki bakiyeyi Firebase'in 'increment' özelliği ile güvenli artır
      await _firestore.collection('bicer_isleri').doc(isId.toString()).update({
        'odenen_miktar': FieldValue.increment(miktar),
      });

      print("Firebase: Ödeme ve İş Bakiyesi bulutta eşitlendi.");
    } catch (e) {
      print("Firebase Ödeme Kayıt Hatası: $e");
      // SQLite güncellendiği için uygulama çalışır, internet gelince senkron olur.
    }
  }




  // --- MARKET MÜŞTERİSİ (EVREN TARIM) TAHSİLAT SİL ---
  Future<void> musteriTahsilatSil(int tahsilatId, String musteriAd, double miktar) async {
    final db = await instance.database;
    await db.transaction((txn) async {
      // 1. Ekstre tablosundan (musteri_hareketleri) kaydı sil
      await txn.delete('musteri_hareketleri', where: 'id = ?', whereArgs: [tahsilatId]);

      // 2. Müşterinin borcuna parayı geri ekle (Bakiyeyi artır)
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
      print("Market tahsilatı silindi, bakiye geri yüklendi.");
    } catch (e) {
      print("Market Firebase Hatası: $e");
    }
  }

  Future<int> customUpdate(String query, List<dynamic> arguments) async {
    final db = await instance.database;
    return await db.rawUpdate(query, arguments);
  }

  Future<int> customDelete(String query, [List<dynamic>? arguments]) async {
    final db = await instance.database;
    return await db.rawDelete(query, arguments);
  }



  // --- BİÇER ÇİFTÇİSİ (ÖZÇOBANLAR) TAHSİLAT SİL ---
  Future<void> bicerTahsilatSil(int tahsilatId, String ciftciAd, double miktar) async {
    final db = await instance.database;
    await db.transaction((txn) async {
      // 1. Tahsilatlar tablosundan kaydı sil
      await txn.delete('tahsilatlar', where: 'id = ?', whereArgs: [tahsilatId]);

      // 2. Çiftçinin Biçer işlerindeki ödenen miktarını düş (Borcu geri aç)
      await txn.execute(
          'UPDATE bicer_isleri SET odenen_miktar = odenen_miktar - ? WHERE ciftci_ad = ?',
          [miktar, ciftciAd]
      );
    });

    try {
      // Firebase Senkronu
      await _firestore.collection('tahsilatlar').doc(tahsilatId.toString()).delete();
      print("Biçer tahsilatı silindi, çiftçi borcu geri açıldı.");
    } catch (e) {
      print("Biçer Firebase Hatası: $e");
    }
  }


  Future<void> tahsilatGuncelle(int tahsilatId, int isId, double eskiMiktar, double yeniMiktar, Map<String, dynamic> yeniVeri) async {
    final db = await instance.database;

    // 1. ADIM: SQLite Transaction (Her iki tablo aynı anda güncellenmeli)
    await db.transaction((txn) async {
      // Tahsilat tablosunu güncelle
      await txn.update('tahsilatlar', yeniVeri, where: 'id = ?', whereArgs: [tahsilatId]);

      // Biçer işleri tablosundaki ödenen miktarı matematiksel olarak düzelt
      await txn.execute(
          'UPDATE bicer_isleri SET odenen_miktar = odenen_miktar - ? + ? WHERE id = ?',
          [eskiMiktar, yeniMiktar, isId]
      );
    });

    // 2. ADIM: Firebase Senkronizasyonu
    try {
      // Tahsilat dökümanını güncelle
      await _firestore.collection('tahsilatlar').doc(tahsilatId.toString()).update(yeniVeri);

      // Biçer işindeki bakiyeyi Firebase'in 'increment' özelliği ile güvenli şekilde güncelle
      // Farkı (yeni - eski) gönderiyoruz ki mevcut değere eklensin/çıkarılsın
      double fark = yeniMiktar - eskiMiktar;
      await _firestore.collection('bicer_isleri').doc(isId.toString()).update({
        'odenen_miktar': FieldValue.increment(fark),
        'son_guncelleme': FieldValue.serverTimestamp(),
      });

      print("Firebase: Tahsilat ve İş bakiyesi bulutta eşitlendi.");
    } catch (e) {
      print("Firebase Tahsilat Güncelleme Hatası: $e");
      // Not: SQLite güncellendiği için uygulama çalışmaya devam eder,
      // ama internet gelince manuel senkronizasyon gerekebilir.
    }
  }
  Future<int> aracSil(int id) async {
    final db = await instance.database;

    try {
      // 1. ADIM: Yerel SQLite'dan sil
      int res = await db.delete(
          "galeri",
          where: "id = ?",
          whereArgs: [id]
      );

      // 2. ADIM: Firebase'den kaldır
      // NOT: 'id.id' hatalıydı, sadece 'id' kullanmalısın.
      await _firestore.collection('galeri').doc(id.toString()).delete();

      print("İşlem Başarılı: Araç hem yerelden hem Firebase'den silindi.");
      return res;

    } catch (e) {
      print("Silme İşlemi Sırasında Hata: $e");
      // Hata durumunda -1 döndürerek arayüzde hata mesajı gösterebilirsin
      return -1;
    }
  }
  // --- ARAÇ İŞLEMLERİ (GÜNCEL VE HATASIZ) ---
  Future<List<Map<String, dynamic>>> aracListesi() async {
    try {
      // 1. Önce buluttan çekmeyi dene
      // NOT: Koleksiyon adını Firebase'de ne koyduysan o olmalı (araclar mı galeri mi?)
      final snapshot = await _firestore.collection('araclar').get();

      if (snapshot.docs.isNotEmpty) {
        debugPrint("☁️ Veriler Firebase'den getirildi.");
        return snapshot.docs.map((doc) {
          var data = doc.data();
          // Firebase'den gelen veride 'id' yoksa doküman ID'sini ekliyoruz
          if (data['id'] == null) data['id'] = doc.id;
          return data;
        }).toList();
      }
    } catch (e) {
      debugPrint("⚠️ Firebase Hatası (İnternet yoksa normaldir): $e");
    }

    // 2. İnternet yoksa veya Firebase boşsa yerel SQLite
    debugPrint("📱 Veriler yerel cihazdan (SQLite) getirildi.");
    final db = await instance.database;

    // BURASI KRİTİK: Loglarda 'galeri' tablosu bulunamadı diyordu.
    // Eğer tabloyu 'araclar' diye kurduysan burayı 'araclar' yap!
    return await db.query('araclar', orderBy: 'id DESC');
  }



  Future<int> aracEkle(Map<String, dynamic> row) async {
    final db = await instance.database;

    // 1. Yerel veritabanına (SQLite) ekle
    int id = await db.insert('araclar', row);

    try {
      // 2. Firebase Firestore'a ekle
      // Döküman ID'sini manuel veriyoruz (SQLite ID'si ile aynı olsun diye)
      DocumentReference docRef = _firestore.collection('araclar').doc(id.toString());

      await docRef.set({
        ...row,
        'id': id, // Firestore içinde de yerel ID'yi tutalım
        'olusturma_tarihi': FieldValue.serverTimestamp(),
      });

      // 3. Başarıyla senkronize edildiyse SQLite'ı güncelle
      await db.update(
        'araclar',
        {'is_synced': 1, 'firebase_id': docRef.id},
        where: 'id = ?',
        whereArgs: [id],
      );
    } catch (e) {
      print("Firebase Senkronizasyon Hatası: $e");
      // İnternet yoksa is_synced zaten 0 kalacak, sonra tekrar denenebilir.
    }

    return id;
  }

  Future<void> _firebaseSenkronizasyon(int localId, Map<String, dynamic> veri) async {
    try {
      // 1. Verinin bir kopyasını al (orijinal veriyi bozmamak için)
      var firebaseVeri = Map<String, dynamic>.from(veri);

      // 2. Gereksiz veya hatalı olabilecek alanları temizle/ekle
      firebaseVeri.remove('is_synced'); // Firebase'de bu sütuna gerek yok
      firebaseVeri['id'] = localId;      // SQLite ID'sini verinin içine de koy

      // 3. Firebase'e yaz
      await FirebaseFirestore.instance
          .collection('araclar')
          .doc(localId.toString()) // Doküman adı SQLite ID'si ile aynı olsun (Takibi kolaydır)
          .set(firebaseVeri);

      // 4. SQLite'ı güncelle
      final db = await instance.database;
      await db.update(
        'araclar',
        {'is_synced': 1},
        where: 'id = ?',
        whereArgs: [localId],
      );

      print("✅ Başarılı: Araç #$localId Firebase ile senkronize edildi.");
    } catch (e) {
      // Hata durumunda is_synced zaten 0 olduğu için bir şey yapmana gerek yok.
      // Kullanıcı interneti açtığında toplu senkronizasyon yaparsın.
      print("❌ Firebase Senkronizasyon Hatası: $e");
    }
  }

// Senkronize edilmeyenleri listele
  Future<List<Map<String, dynamic>>> getUnsyncedAraclar() async {
    final db = await instance.database;
    return await db.query('araclar', where: 'is_synced = ?', whereArgs: [0]);
  }

  Future<void> senkronizeEt() async {
    // 1. Henüz gönderilmemiş araçları yerelden çek
    List<Map<String, dynamic>> bekleyenler = await getUnsyncedAraclar();

    if (bekleyenler.isEmpty) {
      print("Senkronize edilecek araç yok.");
      return;
    }

    print("${bekleyenler.length} araç gönderiliyor...");

    for (var arac in bekleyenler) {
      // Daha önce yazdığımız _firebaseSenkronizasyon fonksiyonunu her araç için çağırıyoruz
      // NOT: SQLite'dan gelen veride 'id' olduğu için localId olarak onu yolluyoruz.
      await _firebaseSenkronizasyon(arac['id'], arac);
    }
  }

  Future<int> firmaOdemesiEkle({

    required int firmaId,
    required String firmaAd,
    required double miktar,
    required String odemeTipi, // NAKİT, HAVALE, ÇEK vs.
    String? aciklama,
  }) async {
    final db = await instance.database;
    int id = 0;

    await db.transaction((txn) async {
      // 1. ADIM: Firma Hareketlerine (Ekstreye) "ÖDEME" olarak işle
      id = await txn.insert('firma_hareketleri', {
        'firma_id': firmaId,
        'tip': 'ODEME', // İşte bu "ODEME" tipi borcu kapatan tiptir
        'urun_adi': 'NAKİT ÖDEME ($odemeTipi)',
        'miktar': 1,
        'tutar': miktar,
        'tarih': DateTime.now().toIso8601String(),
      });

      // 2. ADIM: Firmalar tablosundaki borçtan bu parayı DÜŞ
      await txn.rawUpdate(
          'UPDATE firmalar SET borc = borc - ? WHERE id = ?',
          [miktar, firmaId]
      );
    });

    // 3. ADIM: Firebase Senkronizasyonu (Buluta da gönder)
    try {
      await _firestore.collection('firma_hareketleri').doc(id.toString()).set({
        'firma_id': firmaId,
        'firma_ad': firmaAd,
        'tip': 'ODEME',
        'tutar': miktar,
        'odeme_tipi': odemeTipi,
        'aciklama': aciklama ?? 'Tedarikçi Ödemesi',
        'tarih': DateTime.now().toIso8601String(),
      });
      print("Firebase: Tedarikçi ödemesi buluta işlendi.");
    } catch (e) {
      print("Firebase Ödeme Hatası: $e");
    }

    return id;
  }

  Future<void> bakiyeEkle(String musteriId, double tutar, String tip) async {
    final db = await instance.database;

    await db.rawUpdate(
      'UPDATE musteriler SET bakiye = bakiye + ? WHERE id = ?',
      [tutar, musteriId],
    );

    await _firestore.collection('musteriler').doc(musteriId).update({
      'bakiye': FieldValue.increment(tutar),
      'son_odeme_tipi': tip,
      'son_islem': FieldValue.serverTimestamp(),
    });
  }
  Future<void> satisBitir(
      String musteriId,
      List<Map<String, dynamic>> sepet,
      double toplam,
      String odemeTipi,
      DateTime tarih,
      ) async {
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
  Future<void> stokDus(String stokId, int adet) async {
    final db = await instance.database;
    final String temizId = stokId.toString().trim(); // Boşlukları temizle

    // 1. Yerel SQLite Güncelleme
    await db.rawUpdate(
      'UPDATE stoklar SET adet = IFNULL(adet, 0) - ? WHERE CAST(id AS TEXT) = ?',
      [adet, temizId],
    );

    // 2. Firebase Güncelleme (Garantili Yöntem)
    try {
      // 🔥 .set yerine .update kullanıyoruz ki olmayan ID için boş kayıt açmasın!
      await FirebaseFirestore.instance.collection('stoklar').doc(temizId).update({
        'adet': FieldValue.increment(-adet),
      });
      print("✅ Stok düşüldü: $temizId");
    } catch (e) {
      // Eğer belge yoksa buraya düşer, asla boş kayıt açmaz.
      print("⚠️ UYARI: Stok belgesi Firestore'da bulunamadı, düşülemedi: $temizId");
    }
  }

  Future<void> stogaGeriEkle(int urunId, int iadeAdet) async {
    final db = await instance.database;
    if (iadeAdet <= 0) return;

    await db.rawUpdate(
        'UPDATE stoklar SET adet = IFNULL(adet, 0) + ? WHERE id = ?',
        [iadeAdet, urunId]
    );

    try {
      await _firestore.collection('stoklar').doc(urunId.toString()).update({
        'adet': FieldValue.increment(iadeAdet),
      });
    } catch (e) { print("Firebase İade Hatası: $e"); }
  }


  Future<void> musteriBakiyeGuncelle(String id, double tutar, String tip) async {
    final db = await instance.database;
    final String temizId = id.trim();

    // 1. Önce SQL'de bakiyeyi mevcut olanın üzerine ekleyerek güncelle
    // Bu yöntem 'eskiBakiye'yi çekip Dart'ta toplamaktan çok daha güvenlidir.
    await db.rawUpdate(
        'UPDATE musteriler SET bakiye = bakiye + ? WHERE id = ?',
        [tutar, temizId]
    );

    // 2. Güncel bakiyeyi Firebase'e göndermek için son halini çek
    final res = await db.rawQuery('SELECT bakiye FROM musteriler WHERE id = ?', [temizId]);
    if (res.isNotEmpty) {
      double guncelBakiye = double.tryParse(res.first['bakiye'].toString()) ?? 0.0;

      // 3. FIREBASE GÜNCELLE (Sadece hesaplanmış son rakamı gönder)
      await FirebaseFirestore.instance
          .collection('musteriler')
          .doc(temizId)
          .set({
        'bakiye': guncelBakiye,
        'son_islem': tip,
        'guncelleme': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      print("✅ Bakiye Güncellendi: $guncelBakiye");
    }
  }

  Future<Map<String, dynamic>> getMusteri(String id) async {
    final db = await instance.database;
    final res = await db.query(
      'musteriler',
      where: 'id = ?',
      whereArgs: [id.trim()],
      limit: 1,
    );
    if (res.isNotEmpty) {
      return res.first;
    } else {
      // Eğer müşteri bulunamazsa boş dönmesin diye varsayılan değerler
      return {'id': id, 'bakiye': 0.0, 'ad': 'Bilinmeyen'};
    }
  }

// 1. ADIM: Satış Hareketini Galeri İçin Özelleştir (Hacı, burası Galeri için!)
  Future<void> satisHareketiEkle(Map<String, dynamic> veri) async {
    final db = await instance.database;

    // Galeri araç satışı olduğu için 'arac_id' kontrolü yapıyoruz
    int yerelId = await db.insert('satislar', veri);

    try {
      await _firestore.collection('galeri_satislar').doc(yerelId.toString()).set({
        ...veri,
        'firebase_tarih': FieldValue.serverTimestamp(),
      });
    } catch (e) { print("Firebase Galeri Satış Hatası: $e"); }
  }


// 🔥 EVREN ABİ, BAKİYE DÜZELTME MOTORU BURASI
  Future<void> hareketSilVeBakiyeyiDuzelt(String hareketId, String mId) async {
    final db = await instance.database;

    print("\n--- 🗑️ HAREKET SİLME VE BAKİYE DÜZELTME BAŞLADI ---");

    // 1. Önce silinecek hareketi bulalım (Tutarını ve tipini öğrenmek şart)
    var hareketler = await db.query('musteri_hareketleri', where: 'id = ?', whereArgs: [hareketId]);

    if (hareketler.isNotEmpty) {
      var h = hareketler.first;
      double tutar = double.tryParse(h['tutar'].toString()) ?? 0.0;
      String islemTipi = h['islem']?.toString() ?? "SATIS";

      // 2. MATEMATİK: Satış siliniyorsa bakiye AZALMALI (-), Tahsilat siliniyorsa ARTMALI (+)
      // Sen bakiyeGuncelle'ye direkt sonucu değil, eklenecek farkı gönderiyorsun.
      double farkTutari = (islemTipi == 'SATIS' || islemTipi == 'SATIŞ') ? -tutar : tutar;

      print("📦 Silinen İşlem: $islemTipi | Tutar: $tutar TL");
      print("⚖️ Bakiyeye Uygulanacak Düzeltme: $farkTutari TL");

      // 3. Senin yazdığın ana fonksiyonu çağırıyoruz (Hem yerel hem bulut güncellenir)
      await musteriBakiyeGuncelle(mId, farkTutari, "HAREKET_SILINDI");

      // 4. Şimdi kaydı her yerden silelim
      try {
        // Yerelden sil
        await db.delete('musteri_hareketleri', where: 'id = ?', whereArgs: [hareketId]);
        // Buluttan sil (Senin Firestore yapına göre 'satislar' veya 'musteri_hareketleri')
        await FirebaseFirestore.instance.collection('satislar').doc(hareketId).delete();

        print("✅ [BAŞARILI]: Hareket silindi ve bakiye geri sarıldı.");
      } catch (e) {
        print("❌ [HATA]: Silme işlemi sırasında patladı: $e");
      }
    } else {
      print("⚠️ [UYARI]: Silinecek hareket bulunamadı! ID: $hareketId");
    }
    print("--- 🏁 DÜZELTME İŞLEMİ BİTTİ ---\n");
  }

  Future<void> satisYapFirebase({
    required Map<String, dynamic> veri,
  }) async {
    final db = await instance.database;

    // 1. Verileri Sağlama Al
    String mAd = veri['musteri_ad']?.toString().trim().toUpperCase() ?? 'BILINMEYEN';
    double tutar = double.tryParse(veri['satis_fiyati'].toString()) ?? 0.0;
    int? sId = int.tryParse(veri['stok_id'].toString());
    int adet = int.tryParse(veri['adet'].toString()) ?? 1;
    // Tarihi Türkiye formatına uygun veya ISO yapalım (tercih senin)
    String tarihStr = DateFormat('dd.MM.yyyy HH:mm').format(DateTime.now());

    String marka = veri['marka'] ?? '';
    String model = veri['model'] ?? '';
    String altModel = veri['alt_model'] ?? '';
    String urunDetay = "$marka $model $altModel ($adet Adet)".trim().toUpperCase();

    // 2. SQL İŞLEMLERİ (Transaction içinde)
    await db.transaction((txn) async {
      // A- Bakiyeyi Güncelle
      await txn.execute(
          'UPDATE musteriler SET bakiye = IFNULL(bakiye, 0) + ? WHERE id = ?',
          [tutar, veri['musteri_id']]
      );

      // B- Müşteri Hareketine İşle
      await txn.insert('musteri_hareketleri', {
        'musteri_ad': mAd,
        'islem': 'SATIS',
        'tutar': tutar,
        'aciklama': urunDetay,
        'tarih': tarihStr,
      });

      // C- Stoktan Düş
      if (sId != null) {
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

    // 3. FIREBASE SENKRONU
    try {
      // Müşteri Bakiyesini Bulutta Artır
      await FirebaseFirestore.instance.collection('musteriler')..doc(veri['musteri_id']).set({
        'bakiye': FieldValue.increment(tutar),
        'son_islem': tarihStr
      }, SetOptions(merge: true));

      // Stok Adedini Bulutta Düş
      if (sId != null) {
        await FirebaseFirestore.instance.collection('stoklar').doc(sId.toString()).update({
          'adet': FieldValue.increment(-adet)
        });
      }

      // Satış Kaydını Arşive At
      await FirebaseFirestore.instance.collection('satislar_genel').add({
        'musteri_ad': mAd,
        'urun_detay': urunDetay,
        'tutar': tutar,
        'tarih': tarihStr,
        'sube': veri['sube'] ?? 'BELIRTILMEMIS'
      });

      print("✅ Satış başarıyla hem telefona hem buluta işlendi.");
    } catch (e) {
      print("❌ Firebase senkron hatası (Ama telefon kaydı tamam): $e");
    }
  }
  Future<void> musteriSil(String musteriId) async {
    final db = await instance.database;

    try {
      // 🔥 1. SQLITE SİLME
      // SQLite'ta ID'n INTEGER ise int.tryParse mecburi ama ID metinse direkt yolla.
      // En garanti yol: musteriId neyse onu hem metin hem sayı ihtimaline göre dene.
      await db.delete(
        'musteriler',
        where: 'id = ?',
        whereArgs: [musteriId], // SQLite bunu otomatik eşleştirir
      );

      // 🔥 2. FIREBASE SİLME (ASIL ÖNEMLİ YER)
      // Firebase doküman ID'si her zaman String'dir.
      // musteriId "vXOQRK..." gibi bir şeyse direkt siler.
      await _firestore
          .collection('musteriler')
          .doc(musteriId)
          .delete();

      print("Müşteri hem telefondan hem buluttan temizlendi: $musteriId");
    } catch (e) {
      print("Müşteri Silme Hatası: $e");
      // Kullanıcıya da bir uyarı gösterelim ki silinmediğini bilsin
    }
  }


// DatabaseHelper.dart içine
  Future<List<Map<String, dynamic>>> satisIcinStoklariGetir() async {
    final db = await instance.database;
    // Sadece elinde olan (adet > 0) ürünleri getir ki olmayan malı satma abi
    return await db.query('stoklar', where: 'adet > 0', orderBy: 'urun ASC');
  }
  Future<void> cekleriFirebaseDenAl() async {
    final db = await database;

    var snapshot = await FirebaseFirestore.instance.collection("cekler").get();

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

    print("🔥 ÇEKLER SQL'e BASILDI");
  }



  void cekleriCanliDinle() {
    _cekSub?.cancel(); // eski varsa kapat

    _cekSub = FirebaseFirestore.instance
        .collection("cekler")
        .snapshots()
        .listen((snapshot) async {
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

      print("🔥 ÇEKLER CANLI SENKRON OK");
    });
  }


  void stoklariCanliDinle() {
    _stokSub?.cancel();

    _stokSub = _firestore
        .collection('isletmeler')
        .doc('evren_ticaret')
        .collection('stoklar')
        .snapshots()
        .listen((snapshot) async {
      for (var doc in snapshot.docs) {
        var data = doc.data();

        // 🔥 LOOP ENGELİ
        if (data['kaynak'] == 'local') continue;

        await stokEkle(data, fromFirebase: true);
      }

      print("🔥 CANLI STOK SENKRON TAMAM");
    });
  }
  Future<void> stoklariFirebaseDenAl() async {
    final db = await database;

    var snapshot = await FirebaseFirestore.instance.collection("stoklar").get();

    for (var doc in snapshot.docs) {
      await db.insert(
        "stoklar",
        doc.data(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }

    print("🔥 STOKLAR SQL'e BASILDI");
  }

  Future<void> satisIptalEtVeStoguGeriAl({
    required int satisId,
    required int stokId,
    required int miktar,
    required String musteriAd,
    required double tutar
  }) async {
    final db = await instance.database;

    await db.transaction((txn) async {
      // 1. Satışı sil
      await txn.delete('satislar', where: 'id = ?', whereArgs: [satisId]);

      // 2. STOĞU GERİ ARTIR (Kritik nokta burası)
      await txn.execute(
          'UPDATE stoklar SET adet = adet + ? WHERE id = ?',
          [miktar, stokId]
      );

      // 3. Müşteri borcunu geri düş (Bakiye azalır)
      await txn.execute(
          'UPDATE musteriler SET bakiye = bakiye - ? WHERE ad = ?',
          [tutar, musteriAd]
      );
    });

    // Firebase kullanıyorsan orayı da güncelleyelim
    try {
      await _firestore.collection('stoklar').doc(stokId.toString()).update({
        'adet': FieldValue.increment(miktar)
      });
    } catch (e) { print("Firebase iade hatası: $e"); }
  }
  Future<List<Map<String, dynamic>>> musteriEkstresiGetir(String musteriAd) async {
    final db = await instance.database;
    // Arama yaparken sağındaki solundaki boşlukları temizle
    String aranan = musteriAd.trim();

    return await db.rawQuery('''
    SELECT 
      id, 
      tarih, 
      islem, 
      -- Eğer aciklama null ise boş metin döndür ki UI hata vermesin
      IFNULL(aciklama, 'Detay Yok') as aciklama, 
      CAST(tutar AS REAL) as tutar 
    FROM musteri_hareketleri 
    WHERE UPPER(musteri_ad) = UPPER(?) 
    ORDER BY 
      substr(tarih, 7, 4) DESC, 
      substr(tarih, 4, 2) DESC, 
      substr(tarih, 1, 2) DESC
  ''', [aranan]);
  }

  Future<void> musteriHareketiSilFirebaseDestekli(int sqliteId) async {
    final db = await instance.database;

    // 1. Önce SQLite'dan siliyoruz (ama silmeden önce bilgilerini almamız lazım)
    List<Map<String, dynamic>> maps = await db.query(
      'musteri_hareketleri',
      where: 'id = ?',
      whereArgs: [sqliteId],
    );

    if (maps.isNotEmpty) {
      // Firebase'den silmek için musteri_id ve sqlite_id lazım
      String mId = maps.first['musteri_id'].toString();

      // 2. Yerelden (SQL) Sil
      await db.delete(
        'musteri_hareketleri',
        where: 'id = ?',
        whereArgs: [sqliteId],
      );

      // 3. Firebase'den Sil
      try {
        var snapshot = await FirebaseFirestore.instance
            .collection('musteri_hareketleri')
            .where('musteri_id', isEqualTo: mId)
            .where('sqlite_id', isEqualTo: sqliteId)
            .get();

        for (var doc in snapshot.docs) {
          await doc.reference.delete();
          print("✅ Buluttan silindi.");
        }
      } catch (e) {
        print("❌ Firebase silme hatası: $e");
      }
    }
  }

  Future<void> tabloBakimiYap(Database db) async {
    debugPrint("🛠️ [BAKIM] Akıllı tablo kontrolü başlatıldı...");

    // Bakım yapılacak gerçek tabloları buraya yazıyoruz
    final tablolar = ['musteriler', 'stoklar', 'stok_tanimlari', 'firmalar', 'firma_hareketleri', 'tahsilatlar', 'cekler', 'musteri_hareketleri'];

    for (String tablo in tablolar) {
      // 1. Tablo var mı kontrol et
      var tabloCheck = await db.rawQuery("SELECT name FROM sqlite_master WHERE type='table' AND name='$tablo'");
      if (tabloCheck.isEmpty) continue; // Tablo yoksa sonrakine geç

      // 2. Sütunlar var mı kontrol et
      var columns = await db.rawQuery("PRAGMA table_info($tablo)");
      var columnNames = columns.map((c) => c['name'].toString()).toList();

      // is_synced ekle
      if (!columnNames.contains('is_synced')) {
        await db.execute("ALTER TABLE $tablo ADD COLUMN is_synced INTEGER DEFAULT 0");
        debugPrint("✅ $tablo: is_synced eklendi.");
      }

      // sube ekle
      if (!columnNames.contains('sube')) {
        await db.execute("ALTER TABLE $tablo ADD COLUMN sube TEXT DEFAULT 'TEFENNİ'");
        debugPrint("✅ $tablo: sube eklendi.");
      }

      // musteri_hareketleri'ne özel musteri_ad kontrolü
      if (tablo == 'musteri_hareketleri' && !columnNames.contains('musteri_ad')) {
        await db.execute("ALTER TABLE musteri_hareketleri ADD COLUMN musteri_ad TEXT");
        debugPrint("✅ musteri_hareketleri: musteri_ad eklendi.");
      }
    }
    debugPrint("🏁 [BAKIM] Tüm kontroller hatasız tamamlandı.");
  }
// DatabaseHelper.dart içine eklenecekler:

  // Çekin durumunu (Ödendi/Beklemede) hem telefonda hem bulutta günceller
  Future<void> cekDurumGuncelle(int id, String yeniDurum) async {
    final db = await database;
    await db.update(
      'cekler',
      {'durum': yeniDurum, 'is_synced': 0}, // is_synced: 0 yaptık ki buluta tekrar atsın
      where: 'id = ?',
      whereArgs: [id],
    );
    // Firebase'i de hemen güncelle
    await FirebaseFirestore.instance.collection('cekler').doc(id.toString()).update({
      'durum': yeniDurum,
    });
  }

  Future<void> cekResimGuncelle(int id, String yeniYol) async {
    final db = await database;
    await db.update(
      'cekler',
      {'resimYolu': yeniYol},
      where: 'id = ?',
      whereArgs: [id],
    );
    // Bulutta da güncelle
    await FirebaseFirestore.instance.collection('cekler').doc(id.toString()).update({
      'resimYolu': yeniYol,
    });
  }

// Mevcut çeki tamamen günceller (Düzenleme ekranı için)
  Future<void> cekGuncelle(CekModel cek) async {
    final db = await database;
    await db.update(
      'cekler',
      cek.toMap(),
      where: 'id = ?',
      whereArgs: [cek.id],
    );
    await FirebaseFirestore.instance.collection('cekler').doc(cek.id.toString()).set(cek.toMap());
  }




  Future<void> satisEkle(Map<String, dynamic> veri) async {
    final db = await instance.database;

    try {
      await db.insert(
        'satislar',
        veri,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      print("SATIŞ SQLITE KAYDEDİLDİ");
    } catch (e) {
      print("SATIŞ KAYIT HATASI: $e");
    }
  }
  Future<void> pesinSatisVeTahsilat({
    required String musteriAd,
    required int stokId,
    required int miktar,
    required double birimFiyat,
    required String odemeYontemi, // NAKİT, POS, HAVALE
  }) async {
    final db = await instance.database;
    double toplamTutar = miktar * birimFiyat;
    String suAnkiTarih = DateTime.now().toIso8601String();

    // --- 1. YEREL VERİTABANI (SQLite) İŞLEMLERİ ---
    await db.transaction((txn) async {
      // A. Stoktan Malı Düş
      await txn.execute('UPDATE stoklar SET adet = adet - ? WHERE id = ?', [miktar, stokId]);

      // B. Müşteri Ekstresine SATIŞI İşle (Düzeltildi: 'islem' kullanıldı)
      await txn.insert('musteri_hareketleri', {
        'musteri_ad': musteriAd,
        'islem': 'SATIS', // <--- 'tip' değil 'islem'
        'tutar': toplamTutar,
        'aciklama': '$miktar ADET ÜRÜN (PEŞİN SATIŞ)',
        'tarih': suAnkiTarih,
      });

      // C. Müşteri Ekstresine TAHSİLATI İşle (Düzeltildi: 'islem' kullanıldı)
      await txn.insert('musteri_hareketleri', {
        'musteri_ad': musteriAd,
        'islem': 'TAHSILAT', // <--- 'tip' değil 'islem'
        'tutar': toplamTutar,
        'aciklama': 'SATIŞ ANINDA $odemeYontemi TAHSİLAT',
        'tarih': suAnkiTarih,
      });
    });

    // --- 2. BULUT VERİTABANI (Firebase) İŞLEMLERİ ---
    try {
      await _firestore.collection('stoklar').doc(stokId.toString()).update({
        'adet': FieldValue.increment(-miktar),
      });

      var batch = _firestore.batch();

      // Satış hareketi (İsimlendirme birliği için burada da 'islem' kullanıyoruz)
      var satisRef = _firestore.collection('musteri_hareketleri').doc();
      batch.set(satisRef, {
        'musteri_ad': musteriAd,
        'islem': 'SATIS',
        'tutar': toplamTutar,
        'tarih': suAnkiTarih,
      });

      // Tahsilat hareketi
      var tahsilatRef = _firestore.collection('musteri_hareketleri').doc();
      batch.set(tahsilatRef, {
        'musteri_ad': musteriAd,
        'islem': 'TAHSILAT',
        'tutar': toplamTutar,
        'tarih': suAnkiTarih,
      });

      await batch.commit();
      print("Evren Abi: Peşin işlem tertemiz halloldu!");
    } catch (e) {
      print("Firebase Hatası: $e");
    }
  }

  Future<List<Map<String, dynamic>>> evraklariGetir(dynamic musteriId) async {
    List<Map<String, dynamic>> tumEvraklar = [];

    try {
      // 1. ADIM: Firebase'den sadece bu müşteriye ait olanları çek
      // .where() kullanarak başkasının verisinin gelmesini engelliyoruz
      var snapshot = await _firestore
          .collection('evraklar')
          .where('musteri_id', isEqualTo: musteriId.toString())
          .get();

      if (snapshot.docs.isNotEmpty) {
        for (var doc in snapshot.docs) {
          var data = doc.data();
          data['doc_id'] = doc.id; // Firebase döküman ID'sini ekle (silme/güncelleme için lazım olur)
          tumEvraklar.add(data);
        }
        print("Firebase'den ${tumEvraklar.length} evrak getirildi.");
        return tumEvraklar; // Firebase'de veri varsa hemen döndür
      }
    } catch (e) {
      print("Evrak Firebase Hatası: $e");
    }

    // 2. ADIM: Firebase boşsa veya hata verdiyse yerel SQLite'a bak
    try {
      final db = await instance.database;
      // Yerel tabloda da musteri_id kontrolü yapıyoruz, başkasınınki gelmez.
      final List<Map<String, dynamic>> yerelEvraklar = await db.query(
          'evraklar',
          where: 'musteri_id = ?',
          whereArgs: [musteriId.toString()]
      );
      print("SQLite'dan ${yerelEvraklar.length} evrak getirildi.");
      return yerelEvraklar;
    } catch (e) {
      print("SQLite Evrak Hatası: $e");
      return [];
    }
  }
  Future<void> firmaBakiyesiGuncelle(String firmaAd, double tutar, String tip) async {
    final db = await instance.database;

    // 1. ADIM: YEREL DB GÜNCELLEME (Tablo adını 'tarim_firmalari' yapıyoruz)
    String updateQuery = "";
    if (tip == "ÖDEME") {
      // Firmaya ödeme yaptık, borcumuz azaldı
      updateQuery = 'UPDATE tarim_firmalari SET borc = borc - ? WHERE ad = ?';
    } else if (tip == "TAHSİLAT") {
      // Firmadan para aldık, alacağımız arttı
      updateQuery = 'UPDATE tarim_firmalari SET alacak = alacak + ? WHERE ad = ?';
    } else {
      // Mal Alımı vb. durumlarda firmaya borcumuz artar
      updateQuery = 'UPDATE tarim_firmalari SET borc = borc + ? WHERE ad = ?';
    }

    try {
      await db.rawUpdate(updateQuery, [tutar, firmaAd]);
      print("Yerel DB Güncellendi: $firmaAd - $tip - $tutar");
    } catch (e) {
      print("Yerel DB hatası: $e");
    }

    // 2. ADIM: FIREBASE GÜNCELLEME
    try {
      // Firebase koleksiyon adın da yerelle aynı olmalı
      var querySnapshot = await _firestore.collection('tarim_firmalari')
          .where('ad', isEqualTo: firmaAd)
          .get();

      if (querySnapshot.docs.isNotEmpty) {
        // Kayıt varsa üzerine ekle/çıkar
        var docRef = querySnapshot.docs.first.reference;
        if (tip == "ÖDEME") {
          await docRef.update({'borc': FieldValue.increment(-tutar)});
        } else if (tip == "TAHSİLAT") {
          await docRef.update({'alacak': FieldValue.increment(tutar)});
        } else {
          await docRef.update({'borc': FieldValue.increment(tutar)});
        }
        print("Firebase Güncellendi (Mevcut Kayıt)");
      } else {
        // EĞER FİREBASE'DE FİRMA YOKSA SIFIRDAN OLUŞTUR (Firebase'de gözükmeme sebebi buydu!)
        double ilkBorc = (tip == "ÖDEME") ? -tutar : (tip == "TAHSİLAT" ? 0.0 : tutar);
        double ilkAlacak = (tip == "TAHSİLAT") ? tutar : 0.0;

        await _firestore.collection('tarim_firmalari').add({
          'ad': firmaAd,
          'borc': ilkBorc,
          'alacak': ilkAlacak,
          'tarih': DateTime.now().toIso8601String(),
        });
        print("Firebase'e Yeni Firma Kaydıyla Bakiye Eklendi");
      }
    } catch (e) {
      print("Firebase senkronizasyon hatası: $e");
    }
  }

  // Firma hareketlerini (Ödeme/Tahsilat) kaydeden fonksiyon
  Future<int> cariHareketEkle(Map<String, dynamic> row) async {
    final db = await instance.database;
    // 'firma_hareketleri' tablosuna satırı ekle
    return await db.insert('firma_hareketleri', row);
  }

  Future<void> firmaHareketiEkle(Map<String, dynamic> h) async {
    final db = await instance.database;

    // SQLite kaydı
    await db.insert('firma_hareketleri', h);

    try {
      await _firestore.collection('firma_hareketleri').add({
        'firma_id': h['firma_id'].toString(),
        'tip': h['tip'],
        'tutar': h['tutar'],
        'tarih': h['tarih'],
        'urun_adi': h['urun_adi'],
        'adet': h['adet'],
        'stok_id': h['stok_id'], // 🔥 Bunları da ekle ki bulutta da
        'ana_stok_id': h['ana_stok_id'], // 🔥 kimlik belli olsun
      });
      print("✅ Hareket Firebase'e yedeklendi.");
    } catch (e) {
      print("❌ Firebase kayıt hatası: $e");
    }
  }

  Future<List<Map<String, dynamic>>> firmaEkstresiGetir(dynamic firmaId) async {
    try {
      final db = await instance.database;

      // SADECE BU SATIR YETERLİ: Hiçbir gruplama yapmadan her şeyi olduğu gibi çekiyoruz
      final List<Map<String, dynamic>> sonuclar = await db.query(
          'firma_hareketleri',
          where: 'firma_id = ? AND tip != ?',
          whereArgs: [firmaId.toString(), 'AKTARIM'],
          orderBy: 'tarih DESC'
      );

      debugPrint("PDF İÇİN VERİ: ${sonuclar.length} satır hareket çekildi.");
      return sonuclar;

    } catch (e) {
      debugPrint("Sorgu hatası: $e");
      return [];
    }
  }


  Future<void> firmaSil(int id) async {
    final db = await instance.database;

    try {
      // 1. Önce firmanın adını alalım (Firebase araması için lazım)
      final res = await db.query('tarim_firmalari', columns: ['ad'], where: 'id = ?', whereArgs: [id]);

      if (res.isNotEmpty) {
        String firmaAd = res.first['ad'].toString();
        String firmaIdStr = id.toString(); // ID'yi yazıya çevirdik (Firebase için)

        // --- SQLITE (TELEFON) TEMİZLİĞİ ---
        // Önce o firmaya ait yerel hareketleri sil
        await db.delete('firma_hareketleri', where: 'firma_id = ?', whereArgs: [id]);
        // Sonra firmayı sil
        await db.delete('tarim_firmalari', where: 'id = ?', whereArgs: [id]);

        // --- FIREBASE (BULUT) TEMİZLİĞİ ---

        // A) ÖNCE HAREKETLERİ SİL (Eksik olan kısım burasıydı)
        var hareketler = await _firestore.collection('firma_hareketleri')
            .where('firma_id', isEqualTo: firmaIdStr)
            .get();

        for (var doc in hareketler.docs) {
          await doc.reference.delete();
        }
        print("✅ Firebase: Firmaya ait tüm hareketler silindi.");

        // B) FİRMANIN KENDİSİNİ SİL
        var firmalar = await _firestore.collection('tarim_firmalari')
            .where('ad', isEqualTo: firmaAd)
            .get();

        for (var doc in firmalar.docs) {
          await doc.reference.delete();
        }

        print("✅ Evren Abi: Firma ve hareketleri hem telefondan hem buluttan tamamen temizlendi.");
      }
    } catch (e) {
      print("❌ Silme hatası: $e");
    }
  }


  Future<void> firmaBakiyeGuncelle(dynamic firmaId, double miktar, {String tip = "ALIS"}) async {
    final db = await instance.database;

    // ÖDEME ise miktarı eksiye çeviriyoruz ki alacak azalsın
    double guncellenecekMiktar = (tip == "ODEME" || tip == "ÖDEME") ? -miktar : miktar;

    try {
      // 1. SQLite Güncellemesi
      await db.execute(
          "UPDATE tarim_firmalari SET alacak = alacak + ?, is_synced = 0 WHERE id = ?",
          [guncellenecekMiktar, firmaId]
      );

      // 2. Firebase Güncellemesi
      final List<Map<String, dynamic>> res = await db.query(
          'tarim_firmalari', columns: ['ad'], where: 'id = ?', whereArgs: [firmaId]
      );

      if (res.isNotEmpty) {
        String firmaAd = res.first['ad'];

        // DİKKAT: Firebase'deki o "onlara" ve "borc" karmaşasını bitirmek için
        // hepsini tek bir 'alacak' alanında toplayalım veya mevcutları güncelleyelim.
        await _firestore.collection('tarim_firmalari').doc(firmaAd).update({
          'alacak': FieldValue.increment(guncellenecekMiktar),
          // Eğer Firebase'deki 'onlara' kısmını hala kullanıyorsan onu da güncelle:
          'onlara': FieldValue.increment(guncellenecekMiktar),
          'is_synced': 1,
          'son_guncelleme': DateTime.now().toIso8601String(),
        });

        await db.update('tarim_firmalari', {'is_synced': 1}, where: 'id = ?', whereArgs: [firmaId]);
      }
      print("✅ Bakiye Güncellendi ($tip): $guncellenecekMiktar");
    } catch (e) {
      print("❌ Firebase Güncelleme Hatası: $e");
      // Hata alırsan SQLite'da is_synced = 0 kalır, sonraki senkronizasyonda düzelir.
    }
  }
  Future<void> musteriHareketSil(
      String hareketId,
      String musteriId,
      double tutar,
      String islemTipi
      ) async {
    final db = await instance.database;

    try {
      // 1. TELEFONUN İÇİNDEN (SQLite) SİL
      await db.delete(
        'musteri_hareketleri',
        where: 'id = ?',
        whereArgs: [hareketId],
      );

      // 2. MÜŞTERİ BAKİYESİNİ DÜZELT
      // Tahsilat siliniyorsa (borçtan düşmüştü), bakiyeye geri ekliyoruz (+)
      // Satış siliniyorsa (borca eklenmişti), bakiyeden geri düşüyoruz (-)

      // Büyük/küçük harf hatası olmasın diye toUpperCase ekledim
      double duzeltmeTutari = (islemTipi.toUpperCase() == "TAHSILAT") ? tutar : -tutar;

      await db.execute(
          "UPDATE musteriler SET bakiye = bakiye + ? WHERE id = ? OR tc = ?",
          [duzeltmeTutari, musteriId, musteriId]
      );

      // 🔥 3. FIREBASE'DEN (BULUTTAN) SİL
      try {
        await FirebaseFirestore.instance
            .collection('musteri_hareketleri')
            .doc("HL_$hareketId")
            .delete();

        print("☁️ Firebase'den kayıt başarıyla silindi! (HL_$hareketId)");
      } catch (fbError) {
        print("☁️ Firebase Silme Hatası (İnternet olmayabilir): $fbError");
      }

      print("✅ Yerel kayıt silindi ve bakiye düzeltildi: $duzeltmeTutari");
    } catch (e) {
      print("❌ Silme İşlemi Başarısız: $e");
      throw e;
    }
  }

  Future<List<Map<String, dynamic>>> musteriproformaekstresi(String musteriId) async {
    final db = await instance.database; // SQLite bağlantısı
    final String temizId = musteriId.trim();

    try {
      print("📡 Sistem: $temizId için ekstre hazırlanıyor...");

      // 1. ADIM: ÖNCE TELEFONDAKİ (SQLite) KAYITLARI GETİR
      // Satış yaparken nereye kaydediyorsan oradan çekmelisin.
      // Tablo adın 'musteri_hareketleri' ise onu kullan:
      final List<Map<String, dynamic>> yerelKayitlar = await db.query(
        'musteri_hareketleri', // Tablo ismin neyse o (hareketler veya proformalar)
        where: 'musteri_id = ?',
        whereArgs: [temizId],
        orderBy: 'id DESC',
      );

      if (yerelKayitlar.isNotEmpty) {
        print("✅ Yerel veritabanından ${yerelKayitlar.length} kayıt getirildi.");
        return yerelKayitlar;
      }

      // 2. ADIM: YERELDE YOKSA FİREBASE'E BAK (Yedek Plan)
      final snapshot = await FirebaseFirestore.instance
          .collection('proformalar') // Veya 'musteri_hareketleri'
          .where('musteri_id', isEqualTo: temizId)
          .get();

      if (snapshot.docs.isNotEmpty) {
        print("☁️ Yerelde yoktu, Firebase'den çekildi.");
        return snapshot.docs.map((doc) => doc.data()).toList();
      }

      return []; // İkisinde de yoksa boş dön
    } catch (e) {
      print("❌ Sorgu Hatası: $e");
      return [];
    }
  }

  Future<void> firmaHareketiSil(int hareketId, int firmaId, double tutar, String tip) async {
    final db = await instance.database;

    // 1. TELEFONDAKİ (SQLITE) İŞLEMLER
    await db.transaction((txn) async {
      // Hareketi siliyoruz
      await txn.delete('firma_hareketleri', where: 'id = ?', whereArgs: [hareketId]);

      // Bakiyeyi düzeltiyoruz
      bool isOdeme = (tip.toUpperCase() == "ÖDEME" || tip.toUpperCase() == "ODEME");
      if (isOdeme) {
        // Ödeme silinirse borç geri artar
        await txn.execute('UPDATE tarim_firmalari SET borc = borc + ? WHERE id = ?', [tutar, firmaId]);
      } else {
        // Mal alımı silinirse borç azalır
        await txn.execute('UPDATE tarim_firmalari SET borc = borc - ? WHERE id = ?', [tutar, firmaId]);
      }
    });

    // 2. FİREBASE SENKRONU (Senin kodun burasıyla değişecek abi)
    try {
      // Firmanın adını SQL'den çekiyoruz (Firebase döküman ID'si "HFFG" olduğu için)
      final res = await db.query('tarim_firmalari', columns: ['ad'], where: 'id = ?', whereArgs: [firmaId]);

      if (res.isNotEmpty) {
        String firmaAd = res.first['ad'].toString().trim(); // Boşlukları temizle
        bool isOdeme = (tip.toUpperCase() == "ÖDEME" || tip.toUpperCase() == "ODEME");

        // Ödeme silindiyse borcu (+) arttır, Mal alımı silindiyse borcu (-) azalt
        double miktar = isOdeme ? tutar : -tutar;

        // ÖNCE: 'tarim_firmalari' içindeki o HFFG dökümanının borç hanesini düzelt
        await _firestore.collection('tarim_firmalari').doc(firmaAd).update({
          'borc': FieldValue.increment(miktar),
        });

        // SONRA: 'firma_hareketleri' koleksiyonundan bu faturayı tamamen sil
        await _firestore.collection('firma_hareketleri').doc(hareketId.toString()).delete();

        print("✅ Evren Abi: Firebase'de bakiye düzeldi, hareket silindi.");
      }
    } catch (e) {
      print("❌ Firebase Hatası: $e");
    }
  }

  Future<void> refreshCekler() async {
    final veri = await getCekler();
    _cekController.add(veri);
  }

  Future<void> firmaHareketiGuncelle(int hareketId, int firmaId, double eskiTutar, double yeniTutar, String tip) async {
    final db = await instance.database;
    double fark = yeniTutar - eskiTutar;

    await db.transaction((txn) async {
      await txn.update('firma_hareketleri',
          {'tutar': yeniTutar, 'tarih': DateTime.now().toIso8601String()},
          where: 'id = ?', whereArgs: [hareketId]);

      bool isOdeme = (tip.toUpperCase() == "ÖDEME" || tip.toUpperCase() == "ODEME");
      if (isOdeme) {
        // Ödeme arttıysa borç azalır (-)
        await txn.execute('UPDATE tarim_firmalari SET borc = borc - ? WHERE id = ?', [fark, firmaId]);
      } else {
        // Borçlanma arttıysa borç artar (+)
        await txn.execute('UPDATE tarim_firmalari SET borc = borc + ? WHERE id = ?', [fark, firmaId]);
      }
    });

    try {
      final res = await db.query('tarim_firmalari', columns: ['ad'], where: 'id = ?', whereArgs: [firmaId]);
      if (res.isNotEmpty) {
        // Değişken adı: firmaAd
        String firmaAd = res.first['ad'].toString();

        double fireFark = (tip.toUpperCase() == "ÖDEME" || tip.toUpperCase() == "ODEME") ? -fark : fark;

        // Buradaki fAd hatasını düzelttim, firmaAd yaptım:
        await _firestore.collection('tarim_firmalari').doc(firmaAd).update({
          'borc': FieldValue.increment(fireFark)
        });

        print("Evren Abi: Firebase bakiyesi fark kadar güncellendi ($fireFark).");
      }
    } catch (e) {
      print("Firebase Güncelleme Hatası: $e");
    }
  }


  Future<void> stokAdetGuncelle(int stokId, int yeniAdet, double birimFiyat, String firmaAdi) async {
    final db = await instance.database;

    final eskiStok = await db.query('stoklar', columns: ['adet'], where: 'id = ?', whereArgs: [stokId]);
    int eskiAdet = int.tryParse(eskiStok.first['adet'].toString()) ?? 0;
    int fark = yeniAdet - eskiAdet;
    double farkTutar = fark * birimFiyat;

    await db.update('stoklar', {'adet': yeniAdet}, where: 'id = ?', whereArgs: [stokId]);

    if (firmaAdi.isNotEmpty) {
      // Hem yerel hem Firebase borcunu güncelle
      await db.rawUpdate('UPDATE tarim_firmalari SET borc = borc + ? WHERE ad = ?', [farkTutar, firmaAdi]);
      try {
        await _firestore.collection('tarim_firmalari').doc(firmaAdi).update({
          'borc': FieldValue.increment(farkTutar)
        });
      } catch (e) { print("Firma Borç Güncelleme Hatası: $e"); }
    }
  }

  Future<int> stokTaniminiIdIleSil(int id) async {
    final db = await instance.database;
    // Yerelden sil
    int res = await db.delete('stok_tanimlari', where: 'id = ?', whereArgs: [id]);
    // Firebase'den sil
    try {
      await _firestore.collection('stok_tanimlari').doc(id.toString()).delete();
    } catch (e) { print("Firebase Silme Hatası: $e"); }
    return res;
  }
  // DatabaseHelper.dart içindeki fonksiyonu bu hale getir:
  Future<int> aracGuncelle(int id, Map<String, dynamic> data) async {
    final db = await instance.database;

    // BURASI KRİTİK: Loglarda "no such table: galeri" diyor.
    // Tablo adın neyse (örneğin 'stoklar') onu buraya yaz.
    int res = await db.update("stoklar", data, where: "id = ?", whereArgs: [id]);

    try {
      // Firestore koleksiyonun 'galeri' olabilir, orası kalsın.
      await _firestore.collection('galeri').doc(id.toString()).update(data);
    } catch (e) {
      print("Firebase Güncelleme Hatası: $e");
    }
    return res;
  }

  Future<int> faturaSil(int id) async {
    final db = await instance.database;
    int res = await db.delete('faturalar', where: 'id = ?', whereArgs: [id]);
    try {
      // Doküman ID'si olarak id kullanıldıysa direkt siler
      await _firestore.collection('faturalar').doc(id.toString()).delete();
    } catch (e) { print("Firebase Fatura Silme Hatası: $e"); }
    return res;
  }

  Future<void> faturaGorseliEkle(dynamic musteriId, String dosyaYolu) async {
    final db = await instance.database;

    try {
      // SADECE SQLite kaydı kalsın burada
      await db.insert('faturalar', {
        'firma_id': musteriId,
        'dosya_yolu': dosyaYolu,
        'tarih': DateTime.now().toIso8601String(),
      });
      print("✅ Yerel veritabanına kaydedildi.");

      // 🔥 BURADAKİ FIREBASE KAYDINI KOMPLE SİL VEYA YORUMA AL!
      /*
    await FirebaseFirestore.instance.collection('musteri_faturalari').add({
      'musteri_id': musteriId.toString(),
      'dosya_yolu': dosyaYolu,
      'tarih': DateTime.now().toIso8601String(),
    });
    */

    } catch (e) {
      print("❌ SQLite Kayıt Hatası: $e");
      rethrow;
    }
  }

  // DatabaseHelper.dart dosyasının içi
  Future<int> faturaEkle(Map<String, dynamic> row) async { // Sadece (Map row) bekliyor
    try {
      Database db = await instance.database;
      return await db.insert('faturalar', row);
    } catch (e) {
      debugPrint("❌ SQLite Fatura Yazma Hatası: $e");
      return -1;
    }
  }

  Future<List<Map<String, dynamic>>> firmaFaturalariniGetir(dynamic firmaId) async {
    final db = await instance.database;
    // firmaId ne gelirse gelsin (int veya string), biz onu string olarak arayalım
    return await db.query(
        'faturalar',
        where: 'firma_id = ?',
        whereArgs: [firmaId.toString()],
        orderBy: 'id DESC'
    );
  }

// Eksper Kaydı Ekle: Aracın ekspertiz raporunu buluta yedekler.
  Future<int> eksperKaydiEkle(Map<String, dynamic> veri) async {
    final db = await instance.database;
    int id = await db.insert('eksper_kayitlari', veri);
    try {
      await _firestore.collection('eksper_kayitlari').doc(id.toString()).set({
        ...veri,
        'kayit_tarihi': FieldValue.serverTimestamp(),
      });
    } catch (e) { print("Firebase Eksper Kayıt Hatası: $e"); }
    return id;
  }

// Eksper Kayıtlarını Getir: Belirli bir aracın ekspertiz geçmişini çeker.
  Future<List<Map<String, dynamic>>> eksperKayitlariniGetir(int aracId) async {
    try {
      final snapshot = await _firestore.collection('eksper_kayitlari')
          .where('arac_id', isEqualTo: aracId).get();
      if (snapshot.docs.isNotEmpty) {
        return snapshot.docs.map((doc) => doc.data()).toList();
      }
    } catch (e) { print("Firebase Eksper Liste Hatası: $e"); }
    final db = await instance.database;
    return await db.query('eksper_kayitlari', where: 'arac_id = ?', whereArgs: [aracId], orderBy: "id DESC");
  }


  Future<int> bakimEkle(Map<String, dynamic> veri) async {
    final db = await instance.database;

    // 1. ADIM: FOREIGN KEY HATASINI ÖNLEME
    // Eğer SQLite'da bu araç henüz yoksa (senkronizasyon gecikmişse vs.)
    // hata almamak için aracı anında 'hayalet kayıt' olarak oluşturuyoruz.
    await db.rawInsert('''
    INSERT OR IGNORE INTO araclar (id, firebase_id, plaka) 
    VALUES (?, ?, ?)
  ''', [
      veri['arac_id'],
      veri['arac_id'].toString(),
      "00 GECICI 00"
    ]);

    // 2. ADIM: BAKIMI KAYDET
    // Artık üstteki işlem sayesinde SQLite 'arac_id'yi bulacağı için hata vermeyecek.
    int id = await db.insert('bakimlar', veri);

    try {
      // 3. ADIM: FIREBASE'E YEDEKLE
      await _firestore.collection('bakimlar').doc(id.toString()).set({
        ...veri,
        'id': id,
        'islem_zamani': FieldValue.serverTimestamp(),
      });
      print("✅ İşlem Başarılı: Yerel ID $id buluta gönderildi.");
    } catch (e) {
      // İnternet olmasa bile id döndüğü için kullanıcı işlemine devam eder.
      print("⚠️ Bulut senkronizasyon hatası (Yerel kayıt OK): $e");
    }

    return id;
  }


  Future<List<Map<String, dynamic>>> bakimlariGetir(int aracId) async {
    try {
      // 1. Firebase sorgusu
      final snapshot = await _firestore.collection('bakimlar')
          .where('arac_id', isEqualTo: aracId)
          .orderBy('id', descending: true)
          .get();

      if (snapshot.docs.isNotEmpty) {
        // Firebase'den gelen verileri map'lerken döküman ID'sini de içeri ekliyoruz
        return snapshot.docs.map((doc) {
          final data = doc.data();
          return {
            ...data,
            'firebase_id': doc.id, // Silme/Güncelleme işlemleri için kritik
          };
        }).toList();
      }
    } catch (e) {
      // Eğer hata 'FAILED_PRECONDITION' ise index eksiktir
      print("Firebase Bakım Liste Hatası: $e");
    }

    // 2. Firebase başarısız olursa veya veri yoksa yerel DB'ye bak
    final db = await instance.database;
    final yerelVeri = await db.query(
        'bakimlar',
        where: 'arac_id = ?',
        whereArgs: [aracId],
        orderBy: "id DESC"
    );

    print("📡 Veriler yerel veritabanından getirildi. Toplam: ${yerelVeri.length}");
    return yerelVeri;
  }

  Future<int> eksperKaydiGuncelle(int id, Map<String, dynamic> veri) async {
    final db = await instance.database;
    int res = await db.update('eksper_kayitlari', veri, where: 'id = ?', whereArgs: [id]);
    try { await _firestore.collection('eksper_kayitlari').doc(id.toString()).update(veri); } catch (e) {}
    return res;
  }

  Future<int> eksperKaydiSil(int id) async {
    final db = await instance.database;
    int res = await db.delete('eksper_kayitlari', where: 'id = ?', whereArgs: [id]);
    try { await _firestore.collection('eksper_kayitlari').doc(id.toString()).delete(); } catch (e) {}
    return res;
  }

  Future<int> bakimSil(int id) async {
    final db = await instance.database;
    int res = await db.delete('bakimlar', where: 'id = ?', whereArgs: [id]);
    try { await _firestore.collection('bakimlar').doc(id.toString()).delete(); } catch (e) {}
    return res;
  }


  Future<List<Map<String, dynamic>>> satisGetir(int aracId) async {
    try {
      // 1. Önce Firebase Firestore'dan çekmeyi dene
      final snapshot = await _firestore
          .collection('satislar')
          .where('arac_id', isEqualTo: aracId)
          .get();

      if (snapshot.docs.isNotEmpty) {
        // Firebase'de veri varsa onu döndür
        return snapshot.docs.map((doc) => {
          'id': doc.id,
          ...doc.data(),
        }).toList();
      }
    } catch (e) {
      print("Firebase satisGetir Hatası (Yerel veriye dönülüyor): $e");
    }

    // 2. Firebase'de yoksa veya internet kapalıysa SQLite'dan getir
    final db = await instance.database;
    return await db.query(
        "satislar",
        where: "arac_id = ?",
        whereArgs: [aracId]
    );
  }

  Future<void> ciftciEkle(Map<String, dynamic> ciftciVerisi) async {
    try {
      // 1. Veriyi hazırla
      String tcNo = ciftciVerisi['tc'].toString();

      // 2. FIREBASE KAYIT (TC'yi Doküman ID yaparak mükerrerliği önler)
      await FirebaseFirestore.instance
          .collection('bicer_musterileri')
          .doc(tcNo)
          .set({
        'tc': tcNo,
        'ad_soyad': ciftciVerisi['ad_soyad'],
        'telefon': ciftciVerisi['telefon'],
        'adres': ciftciVerisi['adres'],
        'notlar': ciftciVerisi['notlar'],
        'sube': "TEFENNİ",
        'firebase_id': tcNo,
        'kayit_tarihi': FieldValue.serverTimestamp(),
      });
      print("✅ Firebase: Kayıt/Güncelleme başarılı.");

      // 3. SQL KAYIT (Senin 'database' getter'ın ile)
      final db = await DatabaseHelper.instance.database;

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
      print("✅ SQL: Kayıt/Güncelleme başarılı.");

    } catch (e) {
      print("❌ HATA OLUŞTU: $e");
    }
  }

  Future<List<Map<String, dynamic>>> ciftciListesiGetir() async {
    try {
      // Firebase'den verileri çekiyoruz
      final snapshot = await FirebaseFirestore.instance
          .collection('bicer_musterileri')
          .get(); // İlk başta orderBy'ı kaldırdım ki index hatasıyla uğraşma

      if (snapshot.docs.isNotEmpty) {
        var liste = snapshot.docs.map((doc) {
          var data = doc.data();
          return {
            'id': doc.id, // Dismissible'ın istediği benzersiz key
            'ad_soyad': data['ad_soyad'] ?? "İsimsiz",
            'telefon': data['telefon'] ?? "Telefon Yok",
            'adres': data['adres'] ?? "",
            'notlar': data['notlar'] ?? "",
          };
        }).toList();

        // Dart tarafında isim sırasına diziyoruz (Firebase Index istemesin diye)
        liste.sort((a, b) => a['ad_soyad'].toString().compareTo(b['ad_soyad'].toString()));

        return liste;
      }
      return []; // Veri yoksa boş liste
    } catch (e) {
      print("Firebase Çiftçi Listesi Hatası: $e");
      return [];
    }
  }

  Future<int> ciftciGuncelle(int id, Map<String, dynamic> veri) async {
    final db = await instance.database;

    // 1. ADIM: Yerel SQLite Güncellemesi
    int res = await db.update(
        'bicer_musterileri',
        veri,
        where: 'id = ?',
        whereArgs: [id]
    );

    // 2. ADIM: Firebase Senkronizasyonu
    try {
      // SQLite'daki 'id' ile Firebase'deki 'doc id' aynı olduğu için şak diye bulur
      await _firestore
          .collection('bicer_musterileri')
          .doc(id.toString())
          .update({
        ...veri,
        'son_guncelleme': FieldValue.serverTimestamp(),
      });
      print("Firebase: Çiftçi bilgileri bulutta güncellendi.");
    } catch (e) {
      // İnternet yoksa sadece log basar, kullanıcıyı bekletmez
      print("Firebase Güncelleme Hatası: $e");
    }

    return res;
  }
  Future<int> ciftciSil(int id) async {
    final db = await instance.database;

    // 1. ADIM: Yerel SQLite'dan sil
    // Önce telefonun içindeki kaydı temizliyoruz.
    int res = await db.delete(
        'bicer_musterileri',
        where: 'id = ?',
        whereArgs: [id]
    );

    // 2. ADIM: Firebase'den sil
    try {
      // SQLite ID'si ile Firebase döküman ID'si aynı olduğu için direkt bulup siler
      await _firestore
          .collection('bicer_musterileri')
          .doc(id.toString())
          .delete();

      print("Firebase: Çiftçi kaydı buluttan da silindi.");
    } catch (e) {
      // İnternet yoksa bile SQLite'dan silindiği için listeden kalkar
      print("Firebase Silme Hatası (Bulutta kalmış olabilir): $e");
    }

    return res;
  }

  Future<int> bicerEkle(Map<String, dynamic> row) async {
    Database db = await instance.database;
    return await db.insert(
        'bicerler',
        row,
        // BU SATIR ÇOK KRİTİK: Eğer aynı id varsa eskisini SİLİP yenisini yazar.
        conflictAlgorithm: ConflictAlgorithm.replace
    );
  }

  Future<List<Map<String, dynamic>>> bicerListesi() async {
    try {
      // 1. ADIM: Firebase'den güncel makine listesini çekmeyi dene
      // En son eklenen en üstte görünsün diye 'id'ye göre azalan sıralıyoruz
      final snapshot = await _firestore
          .collection('bicerler')
          .orderBy('id', descending: true)
          .get();

      if (snapshot.docs.isNotEmpty) {
        // Bulutta veri varsa onu döndür (en güncel makine parkuru budur)
        return snapshot.docs.map((doc) => {
          'id_firebase': doc.id,
          ...doc.data(),
        }).toList();
      }
    } catch (e) {
      print("Firebase Biçer Listesi Hatası (Yerel veriye dönülüyor): $e");
    }

    // 2. ADIM: İnternet yoksa veya Firebase boşsa SQLite'dan getir
    final db = await instance.database;
    return await db.query("bicerler", orderBy: "id DESC");
  }


  /// Makineyi ve o makineye bağlı tüm bakım/masraf kayıtlarını temizler.
  Future<int> bicerSil(int id) async {
    final db = await instance.database;

    // 1. ADIM: Bağlı verileri temizle
    // (Tablo adın 'bicer_bakimlar' da olsa 'masraflar' da olsa ikisini de dener)
    try {
      await db.delete('bicer_bakimlar', where: 'makine_id = ?', whereArgs: [id]);
    } catch (e) {
      debugPrint("bicer_bakimlar tablosu silme sırasında atlandı (Tablo yok olabilir)");
    }

    try {
      await db.delete('masraflar', where: 'makine_id = ?', whereArgs: [id]);
    } catch (e) {
      debugPrint("masraflar tablosu silme sırasında atlandı (Tablo yok olabilir)");
    }

    // 2. ADIM: Makineyi ana tablodan sil
    return await db.delete(
      'bicerler',
      where: 'id = ?',
      whereArgs: [id],
    );
  }



  Future<int> bicerGuncelle(int id, Map<String, dynamic> data) async {
    final db = await instance.database;

    // 1. ADIM: Yerel SQLite Güncellemesi
    // Önce telefonun hafızasındaki veriyi değiştiriyoruz.
    int res = await db.update(
        "bicerler",
        data,
        where: "id = ?",
        whereArgs: [id]
    );

    // 2. ADIM: Firebase Senkronizasyonu
    try {
      // SQLite ID'si ile Firebase döküman adı aynı olduğu için nokta atışı yapar.
      // .update() kullanarak sadece değişen alanları gönderiyoruz (Veri tasarrufu sağlar).
      await _firestore
          .collection('bicerler')
          .doc(id.toString())
          .update({
        ...data,
        'son_guncelleme': FieldValue.serverTimestamp(), // Google saatiyle damga
      });
      print("Firebase: Biçerdöver bilgileri bulutta güncellendi.");
    } catch (e) {
      // İnternet yoksa bile işlem SQLite'da bittiği için kullanıcı bekletilmez.
      print("Firebase Güncelleme Hatası (Biçer): $e");
    }

    return res;
  }
  Future<int> bicerIsEkle(Map<String, dynamic> veri) async {
    final db = await instance.database;

    // 1. ADIM: Yerel Kayıt (SQLite)
    // İşlem çok hızlı biter, tarlada internet gitse de kaydın hazır olur.
    int id = await db.insert('bicer_isleri', veri);

    // 2. ADIM: Bulut Yedekleme (Firebase)
    try {
      // Hasat verisini Firebase'e gönderiyoruz.
      // Döküman ID'si olarak SQLite ID'sini kullanmak takibi kolaylaştırır.
      await _firestore.collection('bicer_isleri').doc(id.toString()).set({
        ...veri,
        'is_kayit_tarihi': FieldValue.serverTimestamp(), // Google sunucu saati
      });
      print("Firebase: Biçer iş kaydı buluta başarıyla yedeklendi.");
    } catch (e) {
      // İnternet yoksa hata basar ama SQLite'da kayıtlı olduğu için işin aksamaz.
      print("Firebase Yedekleme Hatası (Biçer İş): $e");
    }

    return id;
  }
  // İşleri Getir: Önce Firebase'den güncel sezonu çeker, yoksa yerel hafızaya bakar.
  Future<List<Map<String, dynamic>>> bicerIsleriGetir(String sezon) async {
    try {
      final snapshot = await _firestore.collection('bicer_isleri')
          .where('sezon', isEqualTo: sezon).get();
      if (snapshot.docs.isNotEmpty) {
        return snapshot.docs.map((doc) => {'id_firebase': doc.id, ...doc.data()}).toList();
      }
    } catch (e) { print("Firebase İş Listesi Hatası: $e"); }

    final db = await instance.database;
    return await db.query('bicer_isleri', where: 'sezon = ?', whereArgs: [sezon]);
  }

  Future<int> bicerBakimSil(int id) async {
    final db = await instance.database;

    // 1. Önce yerelden sil
    int result = await db.delete(
        'bicer_bakimlar',
        where: 'id = ?',
        whereArgs: [id]
    );

    // 2. Firestore'dan asenkron sil (beklemeden devam etmesin)
    try {
      await FirebaseFirestore.instance
          .collection('bicer_bakimlar')
          .doc(id.toString())
          .delete();
      print("✅ Buluttan da silindi");
    } catch (e) {
      print("❌ Bulut silme hatası: $e");
    }

    return result;
  }

  // 3. Makineleri Masraflarıyla Beraber Çekme (Hani plakanın yanında görünsün demiştin ya, bu o)
  Future<List<Map<String, dynamic>>> makineleriGetir() async {
    final db = await instance.database;
    // Bu sorgu her makineye ait masraf toplamını otomatik hesaplar getirir
    return await db.rawQuery('''
      SELECT bicerler.*, 
      (SELECT IFNULL(SUM(tutar), 0) FROM bicer_bakimlari WHERE bicer_id = bicerler.id) as toplam_masraf
      FROM bicerler
    ''');
  }

  // --- 1. TÜM MÜŞTERİ KAYITLARINI SİL (Ana Listeden) ---
  Future<void> tumMusteriKayitlariniTemizle(String ciftciAd) async {
    final db = await instance.database;
    // Bu müşteriye ait ne varsa süpürüyoruz
    await db.delete('bicer_isleri', where: 'ciftci_ad = ?', whereArgs: [ciftciAd]);
    await db.delete('tahsilatlar', where: 'ciftci_ad = ?', whereArgs: [ciftciAd]);

    // Firebase'den de bu müşterinin dökümanlarını topluca silmek gerekir (Opsiyonel)
  }

// --- 2. TEK BİR HAREKETİ SİL (Ekstre İçinden) ---
  Future<void> tekilHareketSil({required int id, required bool isHasat, int? bagliIsId, double? miktar}) async {
    final db = await instance.database;

    if (isHasat) {
      // Sadece o hasat işini sil
      await db.delete('bicer_isleri', where: 'id = ?', whereArgs: [id]);
      // Bu hasata bağlı ödemeleri de sil ki sistem karışmasın
      await db.delete('tahsilatlar', where: 'is_id = ?', whereArgs: [id]);
    } else {
      // Sadece o ödemeyi sil
      await db.delete('tahsilatlar', where: 'id = ?', whereArgs: [id]);
      // Borcu geri yükle
      if (bagliIsId != null && miktar != null) {
        await db.rawUpdate('UPDATE bicer_isleri SET odenen_miktar = odenen_miktar - ? WHERE id = ?', [miktar, bagliIsId]);
      }
    }
  }
// DatabaseHelper.dart içindeki ilgili fonksiyonları bunlarla değiştir:

  Future<void> bicerIsSil(int id, {String? firebaseId}) async {
    final db = await instance.database;
    // SQLite'dan sil
    await db.delete('bicer_isleri', where: 'id = ?', whereArgs: [id]);

    // Firebase'den sil
    if (firebaseId != null) {
      try {
        await FirebaseFirestore.instance.collection('bicer_isleri').doc(firebaseId).delete();
      } catch (e) { debugPrint("Firebase Hatası: $e"); }
    }
  }
  Future<void> tahsilatSil(int id, int isId, double miktar) async { // 3 parametre!
    final db = await instance.database;
    await db.delete('tahsilatlar', where: 'id = ?', whereArgs: [id]);
    await db.rawUpdate(
        'UPDATE bicer_isleri SET odenen_miktar = odenen_miktar - ? WHERE id = ?',
        [miktar, isId]
    );
  }

// --- 1. FONKSİYON: MÜŞTERİYİ VE TÜM GEÇMİŞİNİ SİL (Ana Ekran İçin) ---
  Future<void> musteriyiKompleSil(int id) async {
    final db = await instance.database;
    // Bu işi sil
    await db.delete('bicer_isleri', where: 'id = ?', whereArgs: [id]);
    // Bu işe bağlı ne kadar ödeme varsa onları da süpür
    await db.delete('tahsilatlar', where: 'is_id = ?', whereArgs: [id]);

    debugPrint("Müşteri ve tüm hareketleri silindi.");
  }

// --- 2. FONKSİYON: EKSTREDEKİ TEK BİR SATIRI SİL (Ekstre İçin) ---
  Future<void> ekstreSatirSil({
    required int id,
    required bool isHasat,
    int? bagliIsId,
    double? miktar
  }) async {
    final db = await instance.database;

    if (isHasat) {
      // Sadece o hasat kaydını sil
      await db.delete('bicer_isleri', where: 'id = ?', whereArgs: [id]);
    } else {
      // Sadece o ödemeyi sil
      await db.delete('tahsilatlar', where: 'id = ?', whereArgs: [id]);

      // Ödeme silindiği için borcu geri yükle (Matematik burada)
      if (bagliIsId != null && miktar != null) {
        await db.rawUpdate(
            'UPDATE bicer_isleri SET odenen_miktar = odenen_miktar - ? WHERE id = ?',
            [miktar, bagliIsId]
        );
      }
    }
  }

  Future<void> satisIptalEtVeStokGeriYukle(Map<String, dynamic> satisVerisi) async {
    final db = await instance.database;

    // Satıştan gelen veriler
    String satisId = satisVerisi['id'].toString();
    String stokId = satisVerisi['stok_id'].toString(); // Satış tablanda stok_id tutuyor olmalısın
    double miktar = double.tryParse(satisVerisi['miktar'].toString()) ?? 0;

    await db.transaction((txn) async {
      // 1. Satışı sil
      await txn.delete('satislar', where: 'id = ?', whereArgs: [satisId]);

      // 2. Stoğu geri yükle (Miktarı artır)
      await txn.rawUpdate(
          'UPDATE stoklar SET adet = adet + ? WHERE id = ?', // miktar yerine adet yazdık
          [miktar, stokId]
      );

      // 3. Firebase'den de sil (Eğer senkronize ediyorsan)
      await _firestore.collection('satislar').doc(satisId).delete();
    });
    print("Hacı işlem tamam: Satış silindi, $miktar kadar mal stoka geri döndü.");
  }
  // database_helper.dart içine ekle
  Future<void> satisIptalEt(String satisId, String stokId, double miktar) async {
    final db = await instance.database;

    await db.transaction((txn) async {
      // 1. Satışı veritabanından siliyoruz
      await txn.delete('satislar', where: 'id = ?', whereArgs: [satisId]);

      // 2. STOĞU GÜNCELLİYORUZ (Miktarı geri ekliyoruz)
      await txn.rawUpdate(
          'UPDATE stoklar SET adet = adet + ? WHERE id = ?', // miktar yerine adet yazdık
          [miktar, stokId]
      );
    });
    print("EVREN ABİ: Satış silindi, stok güncellendi.");
  }

  // Hasat işini silmek için
  Future<int> isSil(int id) async {
    final db = await instance.database;
    return await db.delete('isler', where: 'id = ?', whereArgs: [id]);
  }



// İş Güncelle: Dekar veya fiyat değişirse her iki tarafa da işler.
  Future<int> bicerIsGuncelle(int id, Map<String, dynamic> veri) async {
    final db = await instance.database;
    int res = await db.update('bicer_isleri', veri, where: 'id = ?', whereArgs: [id]);
    try {
      await _firestore.collection('bicer_isleri').doc(id.toString()).update(veri);
    } catch (e) { print("Firebase İş Güncelleme Hatası: $e"); }
    return res;
  }

  // Bakım Ekle: Parça veya servis kaydını yedekler.
  Future<int> bicerBakimEkle(Map<String, dynamic> veri) async {
    final db = await instance.database;
    int id = await db.insert('bicer_bakimlar', veri);
    try {
      await _firestore.collection('bicer_bakimlar').doc(id.toString()).set({
        ...veri,
        'kayit_tarihi': FieldValue.serverTimestamp(),
      });
    } catch (e) { print("Firebase Bakım Kayıt Hatası: $e"); }
    return id;
  }

// Bakımları Getir: Belirli bir biçerin tüm servis geçmişini listeler.
  Future<List<Map<String, dynamic>>> bicerBakimlariGetir(int bicerId) async {
    try {
      final snapshot = await _firestore.collection('bicer_bakimlar')
          .where('bicer_id', isEqualTo: bicerId)
          .orderBy('id', descending: true).get();
      if (snapshot.docs.isNotEmpty) {
        return snapshot.docs.map((doc) => doc.data()).toList();
      }
    } catch (e) { print("Firebase Bakım Liste Hatası: $e"); }

    final db = await instance.database;
    return await db.query('bicer_bakimlar', where: 'bicer_id = ?', whereArgs: [bicerId], orderBy: "id DESC");
  }

// Bakım Güncelle ve Sil
  Future<int> bicerBakimGuncelle(int id, Map<String, dynamic> row) async {
    final db = await instance.database;
    int res = await db.update('bicer_bakimlar', row, where: 'id = ?', whereArgs: [id]);
    try { await _firestore.collection('bicer_bakimlar').doc(id.toString()).update(row); } catch (e) {}
    return res;
  }




  Future<int> hasatEkle(Map<String, dynamic> veri) async {
    final db = await instance.database;

    // 1. SQLite'a kaydet
    int id = await db.insert('tarla_hasatlari', veri);

    try {
      // 2. Firebase'e gönder
      Map<String, dynamic> firebaseVeri = Map.from(veri);

      firebaseVeri['sql_id'] = id;
      firebaseVeri['is_synced'] = 1;
      firebaseVeri['olusturma_tarihi'] = FieldValue.serverTimestamp();

      // ❗ ÖNEMLİ: tek doküman ID = SQL ID
      String docId = id.toString();

      await FirebaseFirestore.instance
          .collection('tarla_hasatlari')
          .doc(docId)
          .set(firebaseVeri);

      // 3. firebase_id geri yaz
      await db.update(
        'tarla_hasatlari',
        {
          'is_synced': 1,
          'firebase_id': docId,
        },
        where: 'id = ?',
        whereArgs: [id],
      );

    } catch (e) {
      print("⚠️ Firebase sync hatası: $e");
    }

    return id;
  }

  Future<int> tarlaEkle(Map<String, dynamic> veri) async {
    final db = await instance.database;

    debugPrint("🚀 DEBUG 1: Tarla ekleme işlemi başladı. Veri: $veri");

    // 1. Yerel veritabanına ekle
    int id = await db.insert('tarlalar', veri);
    debugPrint("🚀 DEBUG 2: Yerel SQL kaydı başarılı. Alınan ID: $id");

    try {
      Map<String, dynamic> fbVeri = Map.from(veri);
      fbVeri['id'] = id;
      fbVeri['is_synced'] = 1;

      debugPrint("🚀 DEBUG 3: Firebase'e gönderiliyor... Hedef Döküman: TRL_$id");

      // 'doc().set()' kullanarak ID'yi çiviliyoruz
      await FirebaseFirestore.instance
          .collection('tarlalar')
          .doc("TRL_$id")
          .set(fbVeri, SetOptions(merge: true));

      debugPrint("🚀 DEBUG 4: Firebase yazma başarılı (TRL_$id).");

      // Yerelde 'gitti' diye işaretle
      int updateSonuc = await db.update(
          'tarlalar',
          {'is_synced': 1},
          where: 'id = ?',
          whereArgs: [id]
      );

      debugPrint("🚀 DEBUG 5: Yerel SQL 'is_synced' güncellendi. Etkilenen Satır: $updateSonuc");

    } catch (e) {
      debugPrint("❌ HATA: Bulut senkronizasyonunda patladı: $e");
    }

    debugPrint("🚀 DEBUG 6: Fonksiyon tamamlandı, ID dönüyor: $id");
    return id;
  }

  // --- VERİ GETİRME FONKSİYONLARI ---

  Future<List<Map<String, dynamic>>> tarlaListesiGetir() async {
    final db = await instance.database;
    return await db.query('tarlalar');
  }

  // --- TEK VE TAM YETKİLİ TARLA HAREKETİ EKLEME ---
  Future<int> tarlaHareketiEkle(Map<String, dynamic> veri) async {
    final db = await instance.database;

    try {
      // 1. ADIM: SQLite'a hareketi kaydet (tarla_hareketleri tablosuna)
      // conflictAlgorithm sayesinde çakışmaları önleriz
      int id = await db.insert(
          'tarla_hareketleri',
          veri,
          conflictAlgorithm: ConflictAlgorithm.replace
      );

      // 2. ADIM: Firebase'e (Buluta) gönder
      await _firestore.collection('tarla_hareketleri').doc(id.toString()).set({
        ...veri,
        'sql_id': id,
        'is_synced': 1,
        'kayit_tarihi': FieldValue.serverTimestamp(),
      });

      // 3. ADIM: KRİTİK NOKTA - Eğer bir firma seçildiyse borcunu işle
      // 'firma_id' dolu geliyorsa, ciftclik_firmalari tablosundaki o adamın borcunu artır
      if (veri['firma_id'] != null && veri['firma_id'] != 0) {
        double tutar = double.tryParse(veri['tutar']?.toString() ?? "0") ?? 0;

        await db.rawUpdate(
          'UPDATE ciftclik_firmalari SET borc = borc + ? WHERE id = ?',
          [tutar, veri['firma_id']],
        );
        print("💰 Firma Borcu Güncellendi: ID ${veri['firma_id']} -> +$tutar TL");
      }

      // 4. ADIM: Senkronize edildi bayrağını 1 yap
      await db.update(
          'tarla_hareketleri',
          {'is_synced': 1},
          where: 'id = ?',
          whereArgs: [id]
      );

      print("✅ Tarla Hareketi Mühürlendi, ID: $id");
      return id;
    } catch (e) {
      print("❌ tarlaHareketiEkle Hatası: $e");
      return -1;
    }
  }


// --- TARLA HAREKETLERİNİ LİSTELE ---
  Future<List<Map<String, dynamic>>> tumTarlaHareketleriniGetir() async {
    final db = await instance.database;
    // En yeni işlemler en üstte görünecek şekilde sıralıyoruz
    return await db.query('tarla_hareketleri', orderBy: 'tarih DESC');
  }

  // 1. Tarla Hareketi Silme (Hem Yerel Hem Bulut)
  Future<void> tarlaHareketiSil(String id) async {
    final db = await instance.database;
    try {
      // Önce Yerelden Sil
      await db.delete(
        'tarla_hareketleri',
        where: 'firebase_id = ? OR id = ?',
        whereArgs: [id, id],
      );

      // Sonra Firebase'den Sil
      await _firestore.collection('tarla_hareketleri').doc(id).delete();
      print("✅ Kayıt silindi: $id");
    } catch (e) {
      print("❌ Silme sırasında hata: $e");
    }
  }

  // 2. Tarla Hareketi Güncelleme (Hem Yerel Hem Bulut)
  Future<void> tarlaHareketiGuncelle(String id, Map<String, dynamic> veri) async {
    final db = await instance.database;
    try {
      // SQLite'ın anlayacağı dile çevir (Sütun isimlerini eşitle)
      Map<String, dynamic> sqlVeri = {
        'islem_adi': veri['aciklama'],
        'tutar': veri['toplam'],
        'miktar': veri['miktar'],
        'is_synced': 1,
      };

      // Yereli Güncelle
      await db.update(
        'tarla_hareketleri',
        sqlVeri,
        where: 'firebase_id = ? OR id = ?',
        whereArgs: [id, id],
      );

      // Firebase'i Güncelle
      await _firestore.collection('tarla_hareketleri').doc(id).update({
        'aciklama': veri['aciklama'],
        'toplam': veri['toplam'],
        'miktar': veri['miktar'],
        'birimFiyat': veri['birimFiyat'],
      });
      print("✅ Kayıt güncellendi: $id");
    } catch (e) {
      print("❌ Güncelleme sırasında hata: $e");
    }
  }

  Future<List<Map<String, dynamic>>> tumHasatlariGetir() async {
    final db = await instance.database;
    return await db.query('tarla_hasatlari', orderBy: 'tarih DESC');
  }


// Tarla Sil: Telefonda ve bulutta iz bırakmaz.
  Future<int> tarlaSil(int id) async {
    final db = await instance.database;
    int res = await db.delete('tarlalar', where: 'id = ?', whereArgs: [id]);
    try {
      await _firestore.collection('tarlalar').doc(id.toString()).delete();
    } catch (e) { print("Firebase Tarla Silme Hatası: $e"); }
    return res;
  }

  Future<int> hasatKaydet(Map<String, dynamic> veri) async {
    final db = await instance.database;

    // 1. Önce SQLite'a ekle (is_synced varsayılan 0 olarak girer)
    int id = await db.insert('tarla_hasatlari', veri);

    try {
      // 2. Firebase'e gönderirken SQL ID'sini doküman ismi yapıyoruz
      await _firestore.collection('tarla_hasatlari').doc(id.toString()).set({
        ...veri,
        'sql_id': id, // Takip kolaylığı sağlar
        'kayit_anlik': FieldValue.serverTimestamp(),
      });

      // 3. Buluta yazma başarılıysa SQLite'da 'is_synced' bayrağını 1 yap
      await db.update(
          'tarla_hasatlari',
          {'is_synced': 1},
          where: 'id = ?',
          whereArgs: [id]
      );
      print("✅ Hasat hem yerel hem buluta kaydedildi.");
    } catch (e) {
      print("⚠️ Firebase Kayıt Hatası (İnternet yoksa normal): $e");
      // Hata alırsa is_synced 0 kalır, sonraki eşitlemede gider.
    }
    return id;
  }

  Future<int> hasatGuncelle(int id, Map<String, dynamic> row) async {
    final db = await instance.database;

    // 1. Güncelleme yapıldığı için senkronizasyon bayrağını sıfıra çekiyoruz
    row['is_synced'] = 0;

    int res = await db.update(
        'tarla_hasatlari',
        row,
        where: 'id = ?',
        whereArgs: [id]
    );

    try {
      // 2. Firebase tarafına 'is_synced' bilgisini göndermeye gerek yok
      Map<String, dynamic> fireVeri = Map.from(row)..remove('is_synced');

      await _firestore.collection('tarla_hasatlari').doc(id.toString()).set(
          fireVeri,
          SetOptions(merge: true) // Sadece değişen alanları üzerine yazar
      );

      // 3. Bulut güncellemesi de bittiyse tekrar 1 yapalım
      await db.update(
          'tarla_hasatlari',
          {'is_synced': 1},
          where: 'id = ?',
          whereArgs: [id]
      );
      print("✅ Hasat güncellemesi buluta yansıtıldı.");
    } catch (e) {
      print("⚠️ Firebase Güncelleme Hatası: $e");
    }
    return res;
  }




// DatabaseHelper içindeki kayıt fonksiyonunu şu mantığa çevir:
  Future<void> musteriHareketEkleVeyaGuncelle(Map<String, dynamic> veri) async {
    final db = await instance.database;

    // 1. Önce bu kayıt SQL'de var mı diye kontrol et (firebase_id üzerinden)
    final varMi = await db.query(
        'musteri_hareketleri',
        where: 'firebase_id = ?',
        whereArgs: [veri['firebase_id']]
    );

    if (varMi.isEmpty) {
      // 2. Eğer yoksa YENİ KAYIT ekle
      await db.insert('musteri_hareketleri', veri);
      print("Yeni kayıt eklendi");
    } else {
      // 3. Eğer varsa kayıt MÜKERRERDİR, ekleme yapma (veya güncelle)
      print("Bu kayıt zaten var, eklenmedi.");
    }
  }


  Future<void> musteriHareketGuncelle(
      String hareketId,
      String musteriId,
      double yeniTutar,
      double eskiTutar
      ) async {
    final db = await instance.database;

    try {
      // 1. TELEFONUN İÇİNİ (SQLite) GÜNCELLE
      // Sadece 'tutar'ı güncelliyoruz, hata veren sütunları temizledik.
      await db.update(
        'musteri_hareketleri',
        {'tutar': yeniTutar},
        where: 'id = ?',
        whereArgs: [hareketId],
      );

      // 2. MÜŞTERİ BAKİYESİNİ (SQLite) DÜZELT
      // Hesap: Yeni Tutar - Eski Tutar = Fark.
      // Örnek: 60.000 - 65.000 = -5.000 (Bakiyeden 5 bin düşer, şişkinlik biter)
      double fark = yeniTutar - eskiTutar;

      await db.execute(
          "UPDATE musteriler SET bakiye = bakiye + ? WHERE id = ? OR tc = ?",
          [fark, musteriId, musteriId]
      );

      // 🔥 3. FIREBASE'İ (BULUTU) ANINDA GÜNCELLE
      try {
        await FirebaseFirestore.instance
            .collection('musteri_hareketleri')
            .doc("HL_$hareketId") // Resimdeki gibi HL_5 yapısı
            .update({
          'tutar': yeniTutar,
          'senkronize ediliyor': 0 // Firebase alan ismindeki boşluğa dikkat!
        });

        print("☁️ Firebase (Bulut) başarıyla güncellendi!");
      } catch (fbError) {
        print("☁️ Firebase Güncellenemedi (İnternet yoksa normaldir): $fbError");
      }

      print("✅ İşlem Tamam: Tutar $yeniTutar oldu, Bakiye farkı ($fark) yansıtıldı.");
    } catch (e) {
      print("❌ Veritabanı Hatası: $e");
      throw e;
    }
  }

  Future<int> musteriHareketiEkle(Map<String, dynamic> veri) async {
    final db = await instance.database;

    // 1. ADIM: KAPIDAKİ DEDEKTİF (Senin kod buraya geliyor)
    // Aynı müşteri, aynı tarih ve aynı tutarda kayıt var mı diye bakıyoruz
    final mukerrerKontrol = await db.query(
        'musteri_hareketleri',
        where: 'musteri_id = ? AND tarih = ? AND tutar = ?',
        whereArgs: [veri['musteri_id'], veri['tarih'], veri['tutar']]
    );

    // 2. ADIM: EĞER LİSTE BOŞSA (Yani daha önce kaydedilmemişse)
    if (mukerrerKontrol.isEmpty) {
      print("✅ Bu kayıt yeni, ekleniyor...");
      return await db.insert('musteri_hareketleri', veri);
    } else {
      // 3. ADIM: EĞER VARSA
      print("⚠️ DİKKAT: Bu kayıt zaten sistemde var! Mükerrer işlem engellendi.");
      return -1; // -1 döndürerek işlemin yapılmadığını anlayabiliriz
    }
  }

  Future<List<String>> kategorileriGetirGaranti() async {
    Set<String> kategoriSeti = {"RÖMORK", "EKİMMİMZERİ", "PULLUK", "İLAÇLAMA", "GÜBRELEME", "TRAKTÖR", "DİĞER"};
    try {
      // Firebase'den çek
      final snapshot = await FirebaseFirestore.instance.collection('stok_tanimlari').get();
      for (var doc in snapshot.docs) {
        String? kat = doc.data()['kategori'];
        if (kat != null) kategoriSeti.add(kat.toUpperCase().trim());
      }
      // Yerel SQL'den çek
      final yerel = await stokTanimlariniGetir();
      for (var t in yerel) {
        String? kat = t['kategori'];
        if (kat != null) kategoriSeti.add(kat.toUpperCase().trim());
      }
    } catch (e) { print("Hata: $e"); }

    List<String> liste = kategoriSeti.toList();
    liste.sort();
    return liste;
  }

// --- Firma Güncelle ---
  Future<int> firmaGuncelle(int id, Map<String, dynamic> veri) async {
    final db = await instance.database;

    // 1. Yerel SQLite Güncellemesi
    int res = await db.update(
        'firmalar',
        veri,
        where: 'id = ?',
        whereArgs: [id]
    );

    try {
      // 2. Firebase Firestore Güncellemesi
      // set ve merge:true kullanımı, doküman yoksa oluşturur, varsa sadece değişen alanları günceller.
      await _firestore.collection('firmalar').doc(id.toString()).set(
          {
            ...veri,
            'son_guncelleme': FieldValue.serverTimestamp(), // Güncelleme zamanını takip etmek için
          },
          SetOptions(merge: true)
      );
    } catch (e) {
      print("Firebase Güncelleme Hatası: $e");
    }

    return res;
  }


// Çek/Senet Listesi: Vadesi en yakın olanı en üste getirir
  Future<List<Map<String, dynamic>>> cekSenetListesiGetir() async {
    try {
      final snapshot = await _firestore.collection('portfoy_evraklari')
          .orderBy('vade_tarihi', descending: false).get();
      if (snapshot.docs.isNotEmpty) {
        return snapshot.docs.map((doc) => doc.data()).toList();
      }
    } catch (e) { print("Firebase Evrak Liste Hatası: $e"); }
    final db = await instance.database;
    // ESKİ HALİ: SELECT * FROM portfoy_evraklari ...
// YENİ HALİ:
    return await db.query('cekler', orderBy: 'vadeTarihi ASC');
  }

  Future<List<Map<String, dynamic>>> musteriListesiGetir() async {
    final db = await instance.database;

    // Önce tabloların varlığını ve verileri basitçe çekelim
    // Karmaşık bakiye hesabı yerine, önce temel veriyi sağlama alıyoruz.
    return await db.rawQuery('''
  SELECT 
    m.*, 
    -- Eğer bakiye_guncel null gelirse m.bakiye'yi kullan, o da yoksa 0.0 yap
    IFNULL(
      (m.bakiye + 
        IFNULL((SELECT SUM(satis_fiyati) FROM satislar WHERE musteri_ad = m.ad), 0) - 
        IFNULL((SELECT SUM(miktar) FROM tahsilatlar WHERE ciftci_ad = m.ad), 0)
      ), m.bakiye
    ) as bakiye_hesaplanan,
    -- Şubeyi de sağlama alalım
    IFNULL(
      (SELECT sube FROM satislar WHERE musteri_ad = m.ad ORDER BY id DESC LIMIT 1), 
      m.sube
    ) as sube_guncel
  FROM musteriler m
  ORDER BY m.ad ASC
  ''');
  }

  Future<void> musteriEkle(Map<String, dynamic> m) async {
    final db = await instance.database;

    final adNorm = normalizeAd(m['ad']);

    // 1. ADIM: ID'Yİ SABİTLE (Mükerrerliği bitiren nokta burası)
    // Eğer dışarıdan bir ID gelmişse onu kullan (Firebase ile eşleşme için),
    // gelmemişse TC veya Telefonu ID yap.
    String sabitId = m['id']?.toString() ??
        (m['tc'] != null && m['tc'].toString().isNotEmpty
            ? m['tc'].toString()
            : m['tel'].toString());

    if (sabitId.isEmpty) {
      print("⚠️ HATA: Müşterinin TC veya Telefonu boş olamaz, ID oluşturulamadı.");
      return;
    }

    final veri = {
      'id': sabitId, // Artık newId() değil, sabit ID kullanıyoruz
      'ad': adNorm,
      'ad_norm': adNorm,
      'tc': m['tc'] ?? '',
      'tel': m['tel'] ?? '',
      'adres': m['adres'] ?? '',
      'sube': m['sube'] ?? 'TEFENNİ',
      'bakiye': m['bakiye'] ?? 0.0,
      'is_synced': 1, // Firebase'e de yazacağımız için senkronize sayıyoruz
    };

    try {
      await db.transaction((txn) async {
        // 2. ADIM: ÖNCE SQL KONTROLÜ
        // Aynı ID (TC) var mı diye bakıyoruz
        final existing = await txn.query('musteriler', where: 'id = ?', whereArgs: [sabitId]);

        if (existing.isEmpty) {
          // Eğer SQL'de yoksa EKLE
          await txn.insert(
            'musteriler',
            veri,
            conflictAlgorithm: ConflictAlgorithm.fail,
          );
          print("✅ SQL: Müşteri başarıyla eklendi.");
        } else {
          // Eğer SQL'de varsa GÜNCELLE (Böylece çift kayıt yerine veriyi tazeleriz)
          await txn.update('musteriler', veri, where: 'id = ?', whereArgs: [sabitId]);
          print("🔄 SQL: Müşteri zaten var, bilgileri güncellendi.");
        }
      });

      // 3. ADIM: FIREBASE GARANTİSİ
      // .doc(sabitId).set() dersen Firebase'de asla çift oluşmaz, eskisinin üzerine yazar.
      await _firestore.collection('musteriler').doc(sabitId).set(veri, SetOptions(merge: true));
      print("🔥 Firebase: Senkronizasyon tamam.");

    } on DatabaseException catch (e) {
      if (e.isUniqueConstraintError()) {
        print("🚫 DUPLICATE: Bu ID ile başka bir kayıt var.");
        return;
      }
      rethrow;
    } catch (e) {
      print("❌ HATA: musteriEkle sırasında bir problem oluştu: $e");
    }
  }

  Future<void> musteriGuncelle(String id, Map<String, dynamic> veri) async {
    final db = await instance.database;

    // 1. Veri Hazırlığı
    Map<String, dynamic> guncellenecekVeri = Map.from(veri);

    // Normalizasyon: İsmi her zaman düzgün kaydet (Hata payını siler)
    if (guncellenecekVeri.containsKey('ad')) {
      guncellenecekVeri['ad'] = normalizeAd(guncellenecekVeri['ad']);
      guncellenecekVeri['ad_norm'] = guncellenecekVeri['ad'];
    }

    // ID'yi güncelleme setinden çıkarıyoruz çünkü ID değişmez (WHERE kısmında kullanıyoruz)
    guncellenecekVeri.remove('id');

    try {
      // 2. Yerel SQLite Güncelleme
      int count = await db.update(
        'musteriler',
        guncellenecekVeri,
        where: 'id = ?',
        whereArgs: [id],
      );

      if (count == 0) {
        print("⚠️ UYARI: Yerel veritabanında bu ID ile müşteri bulunamadı ($id).");
      }

      // 3. Firebase Güncelleme (ZIRHLI YÖNTEM)
      // .update() yerine .set(..., merge: true) kullanıyoruz.
      // Neden? Çünkü doküman Firebase'de bir sebeple silinmişse .update() hata verir,
      // ama .set() o dokümanı tekrar oluşturur. Mükerrerliği böyle bitiririz.

      await _firestore
          .collection('musteriler')
          .doc(id.toString())
          .set(guncellenecekVeri, SetOptions(merge: true));

      print("✅ Müşteri hem telefonda hem bulutta başarıyla senkronize edildi.");

    } catch (e) {
      // Hata olsa bile kullanıcıya "İnternet gidince senkronize edilecek" diyebiliriz
      print("❌ Güncelleme sırasında hata: $e");

      // İnternet hatasıysa is_synced işaretini 0 yapabilirsin (İleride tekrar göndermek için)
      await db.update('musteriler', {'is_synced': 0}, where: 'id = ?', whereArgs: [id]);
    }
  }

  Future<double> musteriBorcuGetir(String musteriId) async { // <-- Parametreyi ID yaptık
    final db = await instance.database;

    // 1. Satışlar (Borç): musteri_id üzerinden çekiyoruz
    // Sütun isimleri tablonla aynı olmalı (musteri_id mi yoksa musteri_ad mı? ID her zaman daha güvenlidir)
    var satislar = await db.rawQuery(
        'SELECT SUM(satis_fiyati) as toplam FROM satislar WHERE musteri_id = ?',
        [musteriId]
    );

    // 2. Tahsilatlar (Ödeme)
    double toplamOdeme = 0.0;
    try {
      var tahsilatlar = await db.rawQuery(
          'SELECT SUM(miktar) as toplam FROM tahsilatlar WHERE musteri_id = ?',
          [musteriId]
      );
      toplamOdeme = (tahsilatlar.first['toplam'] as num?)?.toDouble() ?? 0.0;
    } catch (e) {
      print("Tahsilatlar tablosu hatası: $e");
    }

    double toplamSatis = (satislar.first['toplam'] as num?)?.toDouble() ?? 0.0;

    // 3. Başlangıç Bakiyesi (Açılış borcu)
    var mSorgu = await db.query('musteriler', columns: ['bakiye'], where: 'id = ?', whereArgs: [musteriId]);
    double acilisBakiyesi = 0.0;
    if (mSorgu.isNotEmpty) {
      acilisBakiyesi = (mSorgu.first['bakiye'] as num?)?.toDouble() ?? 0.0;
    }

    // Borç Hesabı: (Satışlar + Eski Borç) - Yapılan Ödemeler
    return (toplamSatis + acilisBakiyesi) - toplamOdeme;
  }

  Future<int> musteriUpsert(Map<String, dynamic> m) async {
    final db = await instance.database;

    // ID her şeyin temelidir. Yoksa milisaniye veriyoruz (ama senin yapıda hep olmalı)
    String mId = (m['id'] ?? m['ID'] ?? m['tc'] ?? DateTime.now().millisecondsSinceEpoch).toString();

    // 🔥 ŞUBE TESPİTİ (Senin Firebase yapına göre 'alt' alanını da kontrol ediyoruz)
    String subeTespit = (m['sube'] ?? m['alt'] ?? 'TEFENNİ').toString().toUpperCase();

    Map<String, dynamic> temizVeri = {
      'id': mId,
      'ad': (m['ad'] ?? m['reklam'] ?? 'İSİMSİZ').toString().toUpperCase().trim(),
      'tc': m['tc'] ?? '',
      'tel': (m['tel'] ?? m['phone'] ?? '').toString(),
      'adres': m['adres'] ?? '',
      'sube': subeTespit,
      'bakiye': double.tryParse(m['bakiye']?.toString() ?? '0') ?? 0.0,
      'is_synced': 1, // Upsert ediliyorsa buluttan gelmiş veya buluta gitmiş demektir
    };

    // ConflictAlgorithm.replace kullanarak 'if empty/update' kodunu tek satıra indirebiliriz:
    return await db.insert(
        'musteriler',
        temizVeri,
        conflictAlgorithm: ConflictAlgorithm.replace // Varsa üzerine yazar (update gibi), yoksa ekler.
    );
  }

// Bu fonksiyonu DatabaseHelper sınıfının içine, en alta ekle
  String normalizeAd(String ad) {
    if (ad == null) return "";
    return ad
        .toUpperCase()
        .trim()
        .replaceAll(RegExp(r'\s+'), ' ');
  }

// DatabaseHelper.dart içindeki isim değişikliği
  Future<void> galeriSatisYap({required Map<String, dynamic> veri}) async {
    final db = await instance.database;

    // 1. Yerel SQLite kaydı
    await db.insert("satislar", veri); // Tablo adının 'satislar' olduğundan emin ol

    try {
      // 2. Firebase Bulut kaydı
      await _firestore.collection('satislar').add(veri);
      debugPrint("✅ Satış buluta ve yerele işlendi.");
    } catch (e) {
      debugPrint("⚠️ Satış yerelde kaldı, internet hatası: $e");
    }
  }

  Future<Map<String, dynamic>> genelRaporGetir() async {
    final db = await instance.database;

    // Varsayılan (Yerel) değerler
    int stokSayisi = 0;
    double toplamTahsilat = 0.0;
    int aktifArac = 0;

    try {
      // 1. ADIM: Firebase'den Güncel Verileri Çek
      // Not: Bu koleksiyonların Firebase'de olduğunu varsayıyoruz
      final stokSnapshot = await _firestore.collection('stoklar').get();
      final tahsilatSnapshot = await _firestore.collection('tahsilatlar').get();
      final galeriSnapshot = await _firestore.collection('galeri')
          .where('durum', isNotEqualTo: 'Satıldı').get();

      stokSayisi = stokSnapshot.docs.length;
      aktifArac = galeriSnapshot.docs.length;

      // Tahsilatları topla
      for (var doc in tahsilatSnapshot.docs) {
        toplamTahsilat += double.tryParse(doc.data()['miktar'].toString()) ?? 0.0;
      }

      print("Firebase: Rapor verileri buluttan güncellendi.");
    } catch (e) {
      print("Firebase Rapor Hatası (Yerel veriye dönülüyor): $e");

      // 2. ADIM: İnternet yoksa SQLite'dan hesapla
      stokSayisi = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM stoklar')) ?? 0;
      var tahsilatQuery = await db.rawQuery('SELECT SUM(miktar) as toplam FROM tahsilatlar');
      toplamTahsilat = double.tryParse(tahsilatQuery.first['toplam'].toString()) ?? 0.0;
      aktifArac = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM galeri WHERE durum != "Satıldı"')) ?? 0;
    }

    return {
      'stok_sayisi': stokSayisi,
      'toplam_tahsilat': toplamTahsilat,
      'aktif_arac': aktifArac,
      'guncelleme_tarihi': DateTime.now().toString(),
    };
  }
// --- BİÇER MÜŞTERİ HAREKETLERİ (BİÇER DÖVER İŞLERİ) ---
  Future<List<Map<String, dynamic>>> bicerMusteriHareketleriGetir(String isim) async {
    try {
      // 1. ADIM: Firebase'den bu çiftçiye ait tüm işleri çekmeyi dene
      final snapshot = await _firestore
          .collection('bicer_isleri')
          .where('ciftci_ad', isEqualTo: isim)
          .orderBy('tarih', descending: true)
          .get();

      if (snapshot.docs.isNotEmpty) {
        return snapshot.docs.map((doc) => {
          'id_firebase': doc.id,
          ...doc.data(),
        }).toList();
      }
    } catch (e) {
      print("Firebase Biçer Hareket Hatası: $e");
    }

    // 2. ADIM: Yerel SQLite'dan getir (bicer_isleri tablosu)
    final db = await instance.database;
    return await db.query(
        'bicer_isleri',
        where: 'ciftci_ad = ?',
        whereArgs: [isim],
        orderBy: 'tarih DESC'
    );
  }
  // --- MÜŞTERİ HAREKETLERİ (EN SAĞLAM HALİ) ---
  Future<List<Map<String, dynamic>>> musteriHareketleriGetir(String isim) async {
    try {
      // Firebase tarafında 'isEqualTo' tam eşleşme arar.
      // O yüzden kaydederken ve sorgularken hep toUpperCase() kullanmak en iyisidir.
      final snapshot = await _firestore
          .collection('musteri_hareketleri')
          .where('musteri_ad', isEqualTo: isim.trim())
          .orderBy('tarih', descending: true)
          .get();

      if (snapshot.docs.isNotEmpty) {
        return snapshot.docs.map((doc) => {
          'id_firebase': doc.id,
          ...doc.data(),
        }).toList();
      }
    } catch (e) {
      print("Firebase Hatası: $e");
    }

    final db = await instance.database;

    // SQLite'da hem sütunu hem gelen ismi büyük harfe çevirip kıyaslıyoruz (HATA PAYI SIFIR)
    return await db.query(
        'musteri_hareketleri',
        where: 'UPPER(musteri_ad) = UPPER(?)',
        whereArgs: [isim.trim()],
        orderBy: 'tarih DESC'
    );
  }


  // --- FIREBASE SENKRONİZASYONU ---

  // Personel Ekle ve Firebase'e Bas
  Future<void> personelEkle(Map<String, dynamic> veri) async {
    final db = await instance.database;
    await db.insert('personel', veri);

    // Firebase'e gönder
    try {
      await FirebaseFirestore.instance.collection('personel').doc(veri['id']).set(veri);
      await db.update('personel', {'is_synced': 1}, where: 'id = ?', whereArgs: [veri['id']]);
    } catch (e) {
      print("Firebase hatası: $e");
    }
  }



  Future<int> personelSil(String id) async {
    final db = await instance.database;

    // 1. Önce personelin hareketlerini sil (Foreign Key kısıtı varsa hata vermesin)
    await db.delete('personel_hareketleri', where: 'personel_id = ?', whereArgs: [id]);

    // 2. Personeli sil
    int sonuc = await db.delete('personel', where: 'id = ?', whereArgs: [id]);

    // 3. Firebase'den de sil
    try {
      await FirebaseFirestore.instance.collection('personel').doc(id).delete();
      // Varsa hareketlerini de Firebase'den temizleyebilirsin
    } catch (e) {
      print("Firebase silme hatası: $e");
    }

    return sonuc;
  }

  Future<void> personelHareketEkle(Map<String, dynamic> hareket) async {
    final db = await instance.database;

    // 1. Yerel veritabanına kayıt (Tablo adın fotoğrafta 'personel_hareketleri' idi)
    await db.insert('personel_hareketleri', hareket);

    // 2. Yerel personel tablosunu güncelle
    await db.rawUpdate('''
    UPDATE personel 
    SET bakiye = bakiye + ? 
    WHERE id = ?
  ''', [hareket['tutar'], hareket['personel_id']]);

    try {
      // 3. Hareketi Firebase'e at
      // (Koleksiyon adın 'personel_hareketleri' mi 'personel_hareketler' mi kontrol et!)
      await FirebaseFirestore.instance
          .collection('personel_hareketleri')
          .doc(hareket['id'])
          .set(hareket);

      // 4. Firebase'deki ana bakiyeyi artır/azalt
      await FirebaseFirestore.instance
          .collection('personel')
          .doc(hareket['personel_id'])
          .update({
        'bakiye': FieldValue.increment(hareket['tutar']),
      });

      print("Bulut ve yerel bakiye güncellendi reisim.");
      // Catch bloğunu şöyle değiştir ki hatayı görelim
    } catch (e, stacktrace) {
      print("HATA ÇIKTI REİS: $e");
      print("NEREDE PATLADI: $stacktrace");
    }
  }

  Future<List<Map<String, dynamic>>> personelListesiGetir() async {
    final db = await instance.database;
    return await db.query('personel', orderBy: 'ad ASC');
  }

  Future<void> personelGuncelle(String id, Map<String, dynamic> v) async {
    final db = await instance.database;
    await db.update('personel', v, where: 'id = ?', whereArgs: [id]);
    await FirebaseFirestore.instance.collection('personel').doc(id).update(v);
  }

// --- SENKRONİZASYON DURUMU GÜNCELLE ---
  Future<void> hareketSyncUpdate(String id) async {
    final db = await instance.database;
    await db.update(
        'personel_hareketleri',
        {'is_synced': 1},
        where: 'id = ?',
        whereArgs: [id]
    );
  }


  Future<List<Map<String, dynamic>>> personelHareketleriGetir(String personelId) async {
    final db = await instance.database;

    return await db.query(
      'personel_hareketleri',
      where: 'personel_id = ?',
      whereArgs: [personelId],
      orderBy: 'tarih DESC',
    );
  }

  Future<void> herSeyiFirebaseGeriYukle() async {
    final db = await instance.database;
    print("🚀 [GERİ YÜKLEME] İşlem başlatıldı...");

    Map<String, String> tabloEslesmeleri = {
      'musteriler': 'musteriler',
      'stoklar': 'stoklar',
      'stok_tanimlari': 'stok_tanimlari',
      'firmalar': 'firmalar',
      'firma_hareketleri': 'firma_hareketleri',
      'tarlalar': 'tarlalar',
      'tarla_hareketleri': 'tarla_hareketleri',
      'tarla_hasatlari': 'tarla_hasatlari',
      'cekler': 'cekler',
      'araclar': 'araclar',
      'personeller': 'personeller',
      'proformalar': 'proformalar',
      'bicer_isleri': 'bicer_isleri',
    };

    for (var entry in tabloEslesmeleri.entries) {
      String fbKoleksiyon = entry.key;
      String sqlTablo = entry.value;

      try {
        await db.delete(sqlTablo); // Önce yereli sıfırla

        var snapshots = await FirebaseFirestore.instance.collection(fbKoleksiyon).get();

        if (snapshots.docs.isNotEmpty) {
          // SQL Şemasındaki kolonları alalım (Yanlış kolonu insert etmemek için filtreleme yapacağız)
          var tableInfo = await db.rawQuery("PRAGMA table_info($sqlTablo)");
          List<String> sqlKolonlari = tableInfo.map((e) => e['name'].toString()).toList();

          for (var doc in snapshots.docs) {
            Map<String, dynamic> veri = Map.from(doc.data());

            // 1. ADIM: Timestamp (Tarih) Çevirici
            // Firebase'den gelen özel tarih objelerini SQLite'ın anlayacağı yazıya çeviriyoruz.
            veri.forEach((key, value) {
              if (value is Timestamp) {
                veri[key] = value.toDate().toIso8601String();
              }
            });

            // 2. ADIM: İsim, Tutar ve ID Eşitlemeleri (Firebase -> SQLite)
            if (sqlTablo == 'tarla_hareketleri') {

              // 1. İŞLEM ADI: Firebase'de "İslam" yazıyor, SQLite "islem_adi" bekliyor
              if (veri.containsKey('İslam')) {
                veri['islem_adi'] = veri['İslam'];
              } else if (veri.containsKey('islem')) {
                veri['islem_adi'] = veri['islem'];
              }

              // 2. TUTAR: Firebase'de "toplam" yazıyor, SQLite "tutar" bekliyor
              if (veri.containsKey('toplam')) {
                veri['tutar'] = veri['toplam'];
              } else if (veri.containsKey('birimFiyat')) {
                veri['tutar'] = veri['birimFiyat'];
              }

              // 3. TARLA ID: Firebase'de "tarlaId" yazıyor, SQLite "tarla_id" bekliyor
              if (veri.containsKey('tarlaId')) {
                veri['tarla_id'] = veri['tarlaId'];
              }

              // 4. SEZON: Eğer Firebase'de sezon yoksa varsayılan 2026 ata
              if (!veri.containsKey('sezon')) {
                veri['sezon'] = "2026";
              }
            }

            // 3. ADIM: Dinamik Filtreleme (KRİTİK!)
            // Firebase'den gelen veride senin SQLite tablanda OLMAYAN bir alan varsa onu siliyoruz.
            // Bu sayede "no column named aciklama" gibi hatalar tarih oluyor.
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
          print("✅ $sqlTablo indirildi (${snapshots.docs.length} kayıt).");
        }
      } catch (e) {
        print("❌ Hata ($sqlTablo): $e");
      }
    }
    print("🏁 Geri yükleme bitti! Her şey yerli yerinde.");
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
      'eksper_kayitlari',
      'adacıklar',
      'musteri_faturalari',
      'araclar',
      'bakimlar',
      'isletmeler',
      'evren_ticaret',
      'bicer_mazotlar',
      'mazot_takibi',
      'personel',
      'personel_hareketleri',


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