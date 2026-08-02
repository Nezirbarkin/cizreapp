# Supabase Migration Konsolidasyonu — Uygulama Planı

**Tarih:** 2026-07-27
**Yazar:** Claude
**Durum:** Öneri — onay bekliyor
**Kapsam:** `supabase/` dizini (root SQL + `migrations/`)

---

## 1. Mevcut Durum Özeti

| Klasör | Dosya Sayısı | Yorum |
|---|---:|---|
| `supabase/` (root, `*.sql`) | **54** | Versiyonsuz + dağınık isimler |
| `supabase/migrations/` | **277** | Zaman damgalı, çoğu iyi |
| `supabase/.temp/` | 30+ | Geçici dosyalar (Supabase CLI önbelleği) |
| `supabase/tests/` | 1 dosya | Boş |
| `supabase/functions/` | 30+ edge function | Düzenli görünüyor |

**Tespit edilen 5 temel sorun:**

1. **Çift kayıt:** Aynı işi yapan SQL'ler hem `migrations/` hem root'ta (örn. `FLASH_SALE_AND_PRICE_ALERT_SETUP.sql` (root, 13.7K) + `migrations/20260715*_ad_reward*` serisi).
2. **İsimlendirme disiplinsizliği:** `STEP1_*`, `STEP2_*`, `FINAL_*`, `DEBUG_*`, `FIX_*`, `query1..4_*.sql` — production'da kalmamalı.
3. **Debug/rehber SQL'leri prod'a deploy edilmiş:** `query1_orders_columns.sql`, `debug_admin_panel.sql`, `query4_auth_is_admin.sql` — bunlar SELECT sorguları, çalıştırılıp sonucu göndermek için yazılmış yardım dosyaları. Prod'da çalıştırılmamalı.
4. **Eski/tek seferlik fix dosyaları:** `FIX_MISSING_COLUMN.sql`, `FIX_COMMISSION_TRIGGER.sql`, `COURIER_STATUS_CHANGE.sql` vb. — bunlar muhtemelen zaten uygulandı ama git'te kaldı; "şimdi çalıştırsam ne olur?" sorusu belirsiz.
5. **Paralel "FINAL" / "COMPLETE_FIX" dosyaları:** `COMMISSION_SYSTEM_COMPLETE_FIX.sql` + `FINAL_COMMISSION_FIX.sql` + `DEBUG_COMMISSION_SYSTEM.sql` + `DEBUG_DUPLICATE_TRIGGERS.sql` — hangisi aktif?

---

## 2. Uygulama Stratejisi (Güvenli, 4 Aşamalı)

### Aşama 1 — Sınıflandırma ve Etiketleme (Sadece Okuma)
Her dosyayı 4 kategoriye ayır:

- **KEEP_AS_MIGRATION:** İçeriği kalıcı, idempotent veya CREATE/ALTER olan dosyalar → `migrations/`'a taşı.
- **ARCHIVE_HISTORICAL:** Eskiden uygulanmış ama artık gerekli olmayan, idempotent `CREATE OR REPLACE` fix'leri → `archive/2025/` veya `archive/2026/` altına taşı.
- **DEBUG_OR_QUERY:** `query1..4_*.sql`, `debug_*.sql`, `CHECK_*.sql` — production'a deploy edilmemiş analiz dosyaları → `archive/debug-queries/` altına taşı.
- **DOC_OR_TEST:** SQL içermeyen/dokümantasyon amaçlı olanlar → `docs/sql-notes/` veya sil.

### Aşama 2 — Fiziksel Düzenleme
- Yeni klasör yapısı:
  ```
  supabase/
  ├── migrations/         # Tüm zaman damgalı migration'lar (300+)
  ├── archive/
  │   ├── 2025-q1/        # Erken dönem migration'lar
  │   ├── 2025-q2/
  │   ├── 2026-q2/
  │   ├── 2026-q3/
  │   └── debug-queries/  # SELECT/analiz amaçlı SQL'ler
  ├── functions/          # Edge function'lar (değişmedi)
  ├── tests/              # pgTAP testleri (yeni)
  ├── .temp/              # Supabase CLI (dokunma)
  └── config.toml         # Supabase CLI config (korunur)
  ```
- Tüm dosyalar Supabase CLI standart formatına uygun isimlendirmeye çevrilir:
  `YYYYMMDDHHMMSS_<kategori>_<kısa_açıklama>.sql`

### Aşama 3 — Manifest ve Şema Snapshot
- **`supabase/SCHEMA_INDEX.md`** oluştur: tüm tablolar, view'lar, function'lar, RLS policy'ler, trigger'lar — hangi migration'da tanımlandıkları.
- **`supabase/MIGRATION_LOG.md`** oluştur: kronolojik özet (PROJE_HAVIZA_CHANGELOG.md ile entegre).
- **`supabase/ARCHIVE_INVENTORY.md`** oluştur: arşive alınan her dosyanın neden arşive alındığı, içeriği, uygulanıp uygulanmadığı.

### Aşama 4 — Doğrulama
- `supabase db diff` ile canlı şema ile migration'lar arasında tutarsızlık var mı kontrol et.
- `supabase migration up --dry-run` (yapılabilirse).
- Her taşınan dosya için "apply edildi mi?" kontrolü: dosya içeriğinde idempotent guard'lar (`IF NOT EXISTS`, `DROP IF EXISTS`, `CREATE OR REPLACE`) var mı?

---

## 3. Tehlike Analizi

### 🔴 Yüksek Risk
- **Üretim şemasını bozma:** Yanlış bir DROP ifadesi prod'u kırabilir. **Çözüm:** Hiçbir SQL dosyası otomatik olarak yeniden çalıştırılmayacak. Sadece dosya organizasyonu yapılacak; SQL içerikleri aynen korunacak.
- **Kullanılan ama sanılan migration'ın silinmesi:** Bir fix'in tek bir yerden uygulandığını varsaymak riskli. **Çözüm:** Silme yok, sadece taşıma. Arşivden geri çağırma mümkün.

### 🟡 Orta Risk
- **Git history karmaşıklığı:** `git mv` ile taşıma history'yi korur, ama büyük toplu taşımalar PR'da zor review edilir. **Çözüm:** Taşımaları özellik bazlı grupla (her PR tek bir konuya odaklı).

### 🟢 Düşük Risk
- **IDE/index bozulması:** `.dart_tool/` ve arama index'i etkilenmez çünkü sadece `.sql` dosyaları taşınır.

---

## 4. Yapılacak İşler Listesi (Sıralı)

### Adım 1 — Envanter Çıkarma ✅ (Tamamlandı keşifte)
54 root + 277 migration + ~30 alt klasör = ~360 SQL dosyası listelendi.

### Adım 2 — Sınıflandırma (Sırada)
Her dosyayı tek tek okuyup 4 kategoriye ayır. Bu **dosya değiştirmez**, sadece bir envanter tablosu üretir (`MIGRATION_INVENTORY.csv`).

### Adım 3 — Yapı Düzenleme (Geri Dönüşü Olan Hareketler)
1. `archive/` klasör yapısını oluştur
2. **KEEP_AS_MIGRATION** kategorisindekileri uygun isimle `migrations/`'a taşı
3. **ARCHIVE_HISTORICAL** kategorisindekileri `archive/YYYY-qN/`'e taşı
4. **DEBUG_OR_QUERY** kategorisindekileri `archive/debug-queries/`'e taşı
5. Her taşıma `git mv` ile yapılır (history korunur)

### Adım 4 — Manifestler Oluştur
- `SCHEMA_INDEX.md` (şema nesnesi → migration eşlemesi)
- `ARCHIVE_INVENTORY.md` (arşivdeki dosyalar + nedenleri)
- `MIGRATION_LOG.md` (PROJE_HAVIZA ile senkron)

### Adım 5 — Doğrulama
- Supabase CLI kuruluysa `supabase db diff` çalıştır
- Hiçbir değişiklik yoksa temiz ✅
- Fark varsa → yeni bir "tutarlılık migration'ı" öner

### Adım 6 — Dokümantasyon
- `README.md`'ye migration workflow'u yaz
- Ekip için "yeni migration nasıl eklenir" rehberi

---

## 5. Dokunulmayacak Şeyler

- ✅ Hiçbir SQL içeriği değiştirilmeyecek
- ✅ `migrations/` içindeki dosyalar asla silinmeyecek, sadece taşınabilir
- ✅ `functions/` (edge functions) bu refactor kapsamı dışında
- ✅ `.temp/` (Supabase CLI cache) dokunulmayacak
- ✅ Prod şemasına hiçbir SQL gönderilmeyecek — sadece dosya organizasyonu

---

## 6. Rollback Planı

Eğer bir şeyler ters giderse:
1. Tüm taşımalar `git mv` ile yapıldığı için `git checkout HEAD~1` ile eski haline dönülebilir
2. Manifest dosyaları yeni oluşturulduğu için silinmesi sorun olmaz
3. `archive/` klasörü tamamen geri alınabilir

---

## 7. Tahmini Süre ve Adımlar

| Adım | Tahmini Süre | Risk |
|---|---:|---|
| Envanter + sınıflandırma | 30 dk | Yok (sadece okuma) |
| Klasör yapısı oluşturma | 5 dk | Düşük |
| Dosya taşımaları (3 kategori) | 30 dk | Düşük (git mv) |
| Manifest yazımı | 20 dk | Yok |
| Doğrulama | 15 dk | Düşük |
| **Toplam** | **~1.5 saat** | **Düşük** |

---

## 8. Kabul Kriterleri

- [ ] `supabase/` root'unda 0 SQL dosyası kalmış olmalı
- [ ] Tüm aktif migration'lar `migrations/` altında, sıralı ve isimlendirilmiş
- [ ] `archive/` içindeki her dosya için envanter girişi var
- [ ] `SCHEMA_INDEX.md` mevcut
- [ ] Hiçbir SQL içeriği değişmemiş
- [ ] `git status` temiz (taşımalar commit'lendikten sonra)
- [ ] `flutter analyze` ve `flutter test` hâlâ geçiyor (bu refactor onları etkilememeli)

---

## 9. Açık Sorular (Onayınızı bekliyorum)

1. **"Arşiv" klasörünü gerçekten oluşturmalı mıyım, yoksa sadece root'taki dağınık SQL'leri silmeli miyim?**
   - Güvenli yol: Arşiv (geri alınabilir)
   - Agresif yol: Sil (geri alınamaz)

2. **Debug SQL'leri (query1..4, debug_*) tamamen silinebilir mi?**
   - Bunlar production'a deploy edilmemiş, sadece geliştirme yardımı. Çoğu zaten 1 yıllık.

3. **`migrations/` içindeki büyük dosyaların bazıları bölünebilir mi?**
   - Örn. `20260725000001_sehirici_services.sql` 33.7 KB (tek dosyada tablo+RPC+RLS+trigger). Bölmek faydalı ama büyük PR.
   - **Öneri:** Şu an bölme, sadece organize et.

4. **Supabase CLI kurulumu yapayım mı?**
   - Eğer kuruluysa `supabase db diff` ile canlı şema doğrulanabilir. Değilse bu adımı atlıyoruz.

5. **PROJE_HAVIZA_CHANGELOG.md'yi bu refactor ile güncelleyeyim mi?**
   - Önerim: Evet, yeni bir kayıt ekle: "2026-07-27 | REFACTOR | sql/ | local | low | SQL dosyalarını konsolide ettim, migrations/ + archive/ yapısına geçtim"

---

**Not:** Bu plan onaylandığında `ExitPlanMode` ile onayınızı alıp uygulamaya geçeceğim. Hiçbir SQL değişmez, sadece dosya organizasyonu yapılır.
