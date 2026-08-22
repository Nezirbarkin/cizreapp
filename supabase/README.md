# Supabase (CizreApp)

Bu dizin, CizreApp'in Supabase (Postgres + Auth + Storage + Realtime + Edge Functions) altyapisini yonetir.

> ## ⚠️ `supabase db push` SU AN GUVENLI DEGIL
>
> **Tespit tarihi:** 2026-08-05 — bkz. [`diagnostics/`](diagnostics/)
>
> `supabase_migrations.schema_migrations` defterinde **13 kayit** var; en yenisi
> `20240123000009` (Ocak 2024). Ikisi (`0`, `09`) gecerli surum numarasi bile degil.
> Oysa canli veritabaninda 2026'nin tum isleri duruyor.
>
> Yani **~320 migration canliya elle uygulanmis, deftere hic yazilmamis.**
>
> Bunun sonucu: `supabase db push` defterde olmayan her dosyayi uygulamaya
> calisir — zaten uygulanmis ~320 dosyayi yeniden calistirmayi dener.
> Ayrica repoda **23 grup cift versiyon prefix'i (56 dosya)** var; ayni
> `version` degeri `schema_migrations` icinde birden fazla satir olamaz.
>
> **Defter gercekle hizalanana kadar `db push` calistirma.** Migration'lari
> bugune kadarki gibi Supabase SQL Editor'den elle uygula.
>
> En yikici iki dosya onlem olarak [`deferred/`](deferred/) altina tasindi.

## Dizin Yapisi

```
supabase/
├── migrations/             # 331 aktif SQL: 309 standard + 22 legacy adli
│   └── ...                # Yerel kaynak envanteri; remote-applied kaniti degil
├── deferred/               # Gecerli ama HENUZ uygulanamaz migration'lar
│   └── ...                # Flutter cutover'i beklerler; bkz. deferred/README.md
├── diagnostics/            # Salt-okunur durum tespiti sorgulari
├── archive/                # Arsivlenmis SQL'ler (calistirilmamali)
│   ├── 2025-q1/           # 2025-2026 erken donem fix'leri
│   ├── 2026-q2/           # 2026 Nisan-Haziran eski dosyalar
│   └── debug-queries/     # SELECT/analiz SQL'leri
├── functions/              # Edge Functions (Deno tabanli)
│   ├── confirm-balance-topup/
│   ├── create-balance-topup/
│   └── ...
├── tests/                  # pgTAP / entegrasyon testleri
├── .temp/                  # Supabase CLI gecici dosyalari (dokunma)
├── config.toml             # Supabase CLI konfigurasyonu
├── SCHEMA_INDEX.md         # Otomatik uretilen sema indeksi
├── MIGRATION_LOG.md        # Standard migration kronolojisi + legacy kapsam notu
└── ARCHIVE_INVENTORY.md    # Arsivdeki dosyalarin neden arsivde oldugu
```

## Yeni Migration Ekleme

**Format:** `YYYYMMDDHHMMSS_kisa_aciklama.sql`

**Ornek:** `20260727120000_add_new_feature.sql`

**Adimlar:**

1. Supabase CLI ile yeni dosya olustur:
   ```bash
   supabase migration new add_new_feature
   ```
   Bu komut `supabase/migrations/20260727120000_add_new_feature.sql` dosyasini olusturur.

2. SQL'i yaz. **Idempotent olmali** (birden fazla calistirildiginda hata vermemeli):
   ```sql
   -- CREATE TABLE yerine:
   CREATE TABLE IF NOT EXISTS public.new_table (...);

   -- ALTER TABLE yerine:
   ALTER TABLE public.new_table ADD COLUMN IF NOT EXISTS new_col TEXT;

   -- CREATE POLICY yerine:
   DROP POLICY IF EXISTS "policy_name" ON public.new_table;
   CREATE POLICY "policy_name" ON public.new_table FOR SELECT USING (true);
   ```

3. **RLS** eklemeyi unutma:
   ```sql
   ALTER TABLE public.new_table ENABLE ROW LEVEL SECURITY;
   ```

4. **Realtime** gerekirse:
   ```sql
   ALTER PUBLICATION supabase_realtime ADD TABLE public.new_table;
   ```

5. Local'de test et:
   ```bash
   supabase db reset         # Tum migration'lari sifirdan calistirir
   supabase db diff          # Canli sema ile farki gosterir
   ```

6. Production'a uygula:
   ```bash
   supabase db push          # Tum local-yeni migration'lari remote'a gonderir
   ```

## Manifest'leri Guncelleme

Migration ekledikten/duzenledikten sonra:

```bash
python plans/scripts/build_schema_index.py
python plans/scripts/build_manifests.py
```

Bu komutlar `supabase/SCHEMA_INDEX.md`, `MIGRATION_LOG.md` ve `ARCHIVE_INVENTORY.md` dosyalarini yeniden olusturur.

> **Manifest kapsam uyarisi:** [`build_schema_index.py`](../plans/scripts/build_schema_index.py:7) ve [`build_manifests.py`](../plans/scripts/build_manifests.py:46) yalniz `^\d{14}_` adli dosyalari tarar. 2026-07-30 yerel sayimi **314 aktif SQL = 292 standard + 22 legacy adli SQL** seklindedir. Betikleri calistirmak 22 legacy dosyayi toplamlardan dusurur ve elle eklenen kapsam/remote-kanit notlarini ezebilir. Uzak ortamin gercek durumu her zaman `supabase migration list` ile ayrica dogrulanir.

## Guvenlik Uyarilari

- **API key/secret** iceren SQL dosyalari **asla** `migrations/` altinda olmamali. Supabase Dashboard > Settings > API uzerinden yapilandirilmali.
- Tum RLS policy'ler `auth.uid()` veya `auth.jwt()` uzerinden kullanici bazli olmali (sadece `true` olan policy'ler public veri icin).
- `SECURITY DEFINER` fonksiyonlar dikkatli yazilmali — supabase linter uyarisi verirse `SET search_path = ''` ve `auth.<func>()` kullanimi onerilir.

## AdMob SSV / Odul Puani Deploy Runbook'u

Bu runbook'un kaynak gercegi additive [`20260730000002_admob_reward_points_system.sql`](migrations/20260730000002_admob_reward_points_system.sql:1), Edge Function sozlesmesi [`functions/README.md`](functions/README.md:1) ve gateway ayari [`config.toml`](config.toml:1)'dir. Belge, herhangi bir migration'in production'a uygulanmis oldugunu varsaymaz.

### 1. Preflight ve test

1. Hedef proje/ref'i ve aktif terminal ortamını teyit et; `supabase migration list` ile local/remote farkini kaydet. Belgelerdeki 314/292/22 sayimi remote-applied kaniti degildir.
2. `supabase db push` oncesinde listelenen **tum** pending migration'lari incele; komut yalniz odul migration'ini degil diger pending dosyalari da uygulayabilir.
3. Docker acikken temiz local zinciri ve pgTAP paketlerini calistir:

   ```powershell
   supabase start
   supabase db reset
   supabase test db
   ```

4. Edge kriptografi/SSV unit testlerini calistir:

   ```powershell
   Push-Location .\supabase\functions
   deno task test:reward
   Pop-Location
   ```

5. Flutter odul/puan ve composition testlerini calistir:

   ```powershell
   flutter test .\test\models\ad_settings_model_test.dart .\test\models\reward_points_model_test.dart .\test\models\digital_order_composition_test.dart .\test\services\reward_verification_poller_test.dart .\test\widgets\watch_ad_earn_card_test.dart
   flutter analyze
   ```

### 2. Migration once, function sonra

1. Preflight farki onaylandiktan sonra migration'lari uygula:

   ```powershell
   supabase db push
   supabase migration list
   ```

2. Additive migration tamamlanmadan yeni function'lari deploy etme. Migration baslangicta `reward_feature_mode='disabled'`, earn/spend kapali, eski reklam TL grant'i kapali ve urun puan uygunlugu varsayilan `false` birakir.
3. Function deploy'undan once §3'teki custom secret/allowlist sozlesmesini guvenli ortamda tamamla ve ilk durumda `ADMOB_SSV_MODE=disabled` kullan. Ardindan asagidaki sirayla deploy et. Yalniz Google'in Supabase JWT gondermedigi callback icin gateway JWT kapatilir:

   ```powershell
   supabase functions deploy admob-reward-session
   supabase functions deploy admob-ssv-callback --no-verify-jwt
   supabase functions deploy grant-ad-reward
   supabase functions deploy smm-order-create
   supabase functions deploy smm-order-manual-status
   supabase functions deploy smm-order-status-check
   ```

4. Deploy sonrasinda [`config.toml`](config.toml:13) ile ortam ayarini karsilastir: `admob-ssv-callback.verify_jwt=false`, [`admob-reward-session`](config.toml:16) icin `verify_jwt=true`. AdMob kapsaminda baska bir kullanici endpoint'ine `--no-verify-jwt` verme.
5. Legacy [`grant-ad-reward`](functions/grant-ad-reward/index.ts:1) deploy'u HTTP 410 ve `credit_created:false` davranisini korur; rollback sirasinda eski TL kredi kodu geri deploy edilmez.

### 3. Secret ve istemci build sozlesmesi

Gercek degerleri repoya, terminal gecmisine veya loglara yazma; guvenli CI/Supabase secret yonetimi kullan. Runtime'in gerektirdigi adlar:

- `SUPABASE_URL`
- `SUPABASE_SERVICE_ROLE_KEY`
- `ADMOB_SSV_MODE`
- `ADMOB_SSV_HASH_SECRET`
- `ADMOB_SSV_PUBLIC_KEY_URL`
- `ADMOB_SSV_KEY_CACHE_TTL_SECONDS`
- `ADMOB_SSV_MAX_AGE_SECONDS`
- `ADMOB_SSV_FUTURE_SKEW_SECONDS`
- `ADMOB_SSV_PRODUCTION_AD_UNITS`
- `ADMOB_SSV_TEST_AD_UNITS`
- `CRON_SECRET`

`SUPABASE_URL` ve `SUPABASE_SERVICE_ROLE_KEY` Supabase Edge runtime tarafindan saglanan sistem degiskenleridir; istemciye veya custom secret komutuna kopyalanmaz. `ADMOB_SSV_*` ve `CRON_SECRET` custom secret'larini deploy oncesi set et; custom adlarin varligini `supabase secrets list` ile teyit et. `ADMOB_SSV_HASH_SECRET` en az 32 karakterlik rastgele bir deger, key URL resmi HTTPS endpoint'i ve ad-unit listeleri ortama ozel allowlist olmalidir. Ayrintili anlamlar [`functions/README.md`](functions/README.md:34)'dedir.

Production Flutter build'leri rewarded unit ID'lerini kod deposundan degil CI secret'larindan su kesin Dart define adlariyla alir:

```powershell
flutter build appbundle --dart-define=ADMOB_REWARDED_UNIT_ID_ANDROID=<secure-android-rewarded-unit-id> --dart-define=ADMOB_REWARDED_UNIT_ID_IOS=<secure-ios-rewarded-unit-id>
# Yalniz macOS runner/CI üzerinde:
flutter build ipa --dart-define=ADMOB_REWARDED_UNIT_ID_ANDROID=<secure-android-rewarded-unit-id> --dart-define=ADMOB_REWARDED_UNIT_ID_IOS=<secure-ios-rewarded-unit-id>
```

Production define bos ise [`AdSettings`](../lib/core/models/ad_settings_model.dart:142) reklam servisini fail-closed birakir. Define adlari ad-unit kimligidir; AdMob App ID/native platform ayarinin yerini tutmaz.

### 4. Cutover

1. **Kapali taban:** Migration ve function deploy'undan sonra DB'de mode=`disabled`, earn/spend/eligible-products=false ve Edge'de `ADMOB_SSV_MODE=disabled` birak.
2. **Observe/test:** Kontrollu protokol testi icin audit gerekceli admin config ile DB mode=`observe`, earn=false, spend=false ve eligible-products=false yap; Edge'de `ADMOB_SSV_MODE=test` kullan. `observe`, JWT'li session endpoint'inin oturum acmasina izin verir; callback `test` modu tam imza protokolunu dogrular fakat grant RPC'sini cagirmadan 204 doner. Flutter UI earn=false/observe durumunda reklam akisini acmaz; test kontrollu yetkili istemciyle yapilir. Google callback URL'sini deploy edilen `admob-ssv-callback` URL'sine bagla; test ad-unit allowlist'i, ECDSA key fetch/cache, timestamp penceresi ve custom-data MAC senaryolarini dogrula. Test tamamlaninca tekrar kapali tabana don. Raw query, imza, custom data veya provider kimligini loglama.
3. **Production SSV:** Production allowlist hazir olmadan `ADMOB_SSV_MODE=production` yapma. DB tarafinda earn acmak icin [`admin_update_reward_points_config(...)`](migrations/20260730000002_admob_reward_points_system.sql:816) `ssv_enabled=true`, mode=`cohort|enabled` ve en az sekiz karakterlik audit gerekcesi zorunlu kilar.
4. **Sinirli earn:** Once spend ve global urun uygunlugunu kapali tutup SSV+earn'i kontrollu release kanalinda ac. `cohort` degeri kaynak kodda ayri bir uyelik tablosu/policy uygulamaz; gercek cohort siniri release/ad-unit dagitimiyla disaridan saglanmiyorsa `cohort` tum uygun istemciler icin `enabled` gibi davranir.
5. **Mutabakat:** Session→SSV event→ledger→account projection, UTC gunluk butce, duplicate transaction ve kullanici limit/cooldown sonuclarini incele. Ekonomik basari yalniz server session `credited` oldugunda kabul edilir.
6. **Spend:** Yalniz onayli dijital urunlerde `products.is_points_eligible=true` ayarla; sonra global eligible-products ve spend flag'lerini audit gerekcesiyle ac. Sunucu once puani, sonra kalan TL'yi hesaplar; istemci fiyat/composition beyanina guvenilmez.
7. **Genisletme:** Hata/butce/mutabakat metrikleri kabul edilince mode=`enabled` yap. Admin reporting ayri bir ayardir; yeni config RPC'si bu flag'i degistirmez.
8. **Retention:** Varsayilan fraud HMAC retention ayari 30 gundur. Service-role zamanlanmis is [`purge_expired_reward_fraud_hashes(integer)`](migrations/20260730000002_admob_reward_points_system.sql:865) RPC'sini kontrollu batch'lerle cagirmalidir; bu job'un zamanlandigi ayrica kanitlanmadan otomatik calisiyor varsayilmaz.

### 5. Kill-switch, rollback ve belirsiz provider sonucu

- **Birincil kill-switch:** Admin config RPC/UI ile `reward_feature_mode='disabled'`, earn=false, spend=false ve eligible-products=false yap. Ayar degisikligi gerekceli audit yazar.
- **Callback kill-switch:** `ADMOB_SSV_MODE=disabled` callback'i 503 ile fail-closed kapatir. DB kill-switch'i de kapali tutulur; tek katmana guvenilmez.
- **Legacy yolu acma:** `legacy_ad_tl_grant_disabled=true` kalir, eski SQL grant yetkileri geri verilmez ve HTTP 410 endpoint'i geri alinmaz.
- **Additive rollback:** Append-only ledger veya tarihsel TL kayitlarini silme/yeniden yazma; destructive down migration uygulama. Yeni kazanma/harcamayi kapat, semayi yerinde birak ve ileri duzeltme migration'i kullan.
- **Grandfather/no-backfill:** Cutover oncesi basarili TL reklam degeri kullanicida kalir; puana kopyalanmaz, geriye donuk dusulmez ve yeni puan yaratmaz.
- **Mevcut puan:** Earn kill-switch'i kazanmayi, spend kill-switch'i yeni harcamayi durdurur; mevcut ledger bakiyesi audit gercegi olarak korunur.
- **SMM belirsizligi:** Timeout, parse veya belirsiz provider sonucu otomatik iade degildir; siparis `reconciliation_pending` kalir. Sonuc kesinlesmeden manuel tam iade verme. Rollback sirasinda status/reconciliation function'larini acik tutup bekleyen kayitlari mutabik kil.
- **SMM cron gateway'i:** `smm-order-status-check` ic gateway JWT dogrulamasini korur. Cron istegi gecerli Supabase bearer ile birlikte `CRON_SECRET` tasimalidir; yalniz `x-cron-secret` gondermek gateway'i gecmez. Gateway JWT kapatilacaksa bu ayri bir guvenlik degisikligi olarak incelenmeli ve bu runbook'ta sessizce yapilmamalidir.
- **Iade kaynagi:** Kesin iptal/iade sonucunda puan puana, TL TL bakiyesine doner; composition snapshot'i veya kümülatif iade ust sinirlari degistirilmez.

### 6. Yayin sonrasi kanit

- `supabase migration list` ciktisini release kaydina ekle; bu belgeyi remote kaniti olarak kullanma.
- Function deploy surumleri, gateway JWT ayari ve secret **adlarinin** varligini kaydet; secret degerlerini kaydetme.
- Callback loglarinda kalici reddetme ile gecici key/DB hatalarini ayir; raw query/imza/provider kimligi loglanmadigini kontrol et.
- [`002_reward_points_security_invariants.test.sql`](tests/database/002_reward_points_security_invariants.test.sql:1) dahil pgTAP sonucunu ve Deno test sonucunu release artefaktina ekle.
- Grandfather audit sayilari, orphan baglanti sayilari, gunluk butce ve ledger/account projection mutabakatini kontrol et.

## Supabase CLI Kurulumu

```bash
npm install -g supabase
supabase login
supabase link --project-ref xsbukxkgtmdyickknqzf
```

**Dogrulama:**
```bash
supabase migration list     # Local vs remote migration karsilastirmasi
supabase db diff            # Canli sema farki (Docker gerekir)
```

## Faydali Linkler

- Proje: https://supabase.com/dashboard/project/xsbukxkgtmdyickknqzf
- SQL Editor: https://supabase.com/dashboard/project/xsbukxkgtmdyickknqzf/sql
- Logs: https://supabase.com/dashboard/project/xsbukxkgtmdyickknqzf/logs/explorer
- Edge Functions: https://supabase.com/dashboard/project/xsbukxkgtmdyickknqzf/functions
- API Docs: https://supabase.com/dashboard/project/xsbukxkgtmdyickknqzf/api
