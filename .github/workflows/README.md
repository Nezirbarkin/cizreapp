# GitHub Actions Workflows

Bu dizin CizreApp için CI/CD pipeline tanımlarını içerir.

## Workflow Listesi

| Dosya | Amaç | Tetiklenme |
|-------|------|------------|
| `test.yml` | Tüm Flutter testleri (klasik) | Her push/PR |
| `seller-tests.yml` | Sadece satıcı paneli testleri | Seller kodu değişince |
| `edge-functions.yml` | Deno type-check + lint | Edge function değişince |
| `security-database.yml` | pgTAP veritabanı testleri | DB şeması değişince |
| `ci-pipeline.yml` | Tüm aşamaları birleştiren ana pipeline | Her push/PR |
| `pr-checks.yml` | PR yorumu ve değişiklik tespiti | PR açılınca |
| `ios-build.yml` | iOS build (mevcut) | Manuel |

## Hızlı Başlangıç

### İlk Kurulum
1. GitHub repo → **Settings → Secrets and variables → Actions**
2. Şu secret'ları ekleyin:
   - `CODECOV_TOKEN` (opsiyonel, coverage için)
   - `SUPABASE_ACCESS_TOKEN` (edge function deploy için)

### Branch Koruması (Önerilen)
GitHub → Settings → Branches → main için:
- ✅ Require status checks to pass before merging
- ✅ Require branches to be up to date before merging
- Seçilecek check: **CI Pipeline / CI Summary**

## Lokal Çalıştırma

CI'da çalışan adımları lokalde de test edebilirsiniz:

```bash
# Tüm seller testleri
flutter test test/seller/

# Tüm testler
flutter test

# Lint
flutter analyze

# Format kontrolü
dart format --output=none --set-exit-if-changed lib test

# Edge function type-check
cd supabase/functions
deno check */index.ts

# Edge function lint
deno lint **/index.ts
```

## Workflow Davranışı

```
PR açılınca / push yapılınca
        │
        ├─→ static-analysis (format + lint)
        │     └─ FAIL → merge engellenir
        │
        ├─→ flutter-tests (tüm testler)
        │     └─ FAIL → merge engellenir
        │
        ├─→ edge-functions (Deno type-check)
        │     └─ FAIL → merge engellenir
        │
        └─→ summary (sonuç)
              └─ Tümü geçtiyse ✅
```

## Satıcı Paneli Özel Test

`seller-tests.yml` sadece şu durumlarda çalışır:
- `lib/features/seller/**` değişirse
- `test/seller/**` değişirse
- Satıcı ile ilgili edge function değişirse

Bu sayede gereksiz yere tüm testler çalışmaz, **dakikalarca beklemezsiniz**.

## Sorun Giderme

### "deno: command not found"
Edge function job'ı Deno kurulumu yapıyor, otomatik çözülür.

### "flutter: command not found"
`subosito/flutter-action@v2` otomatik kuruyor.

### "psql connection failed"
Database job'ı lokal Supabase ayağa kaldırıyor. Docker gerekli.

### "Coverage upload failed"
`CODECOV_TOKEN` secret'ı eksik. Opsiyonel, test yine de çalışır.
