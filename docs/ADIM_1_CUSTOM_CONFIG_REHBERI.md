# ADIM 1 — Custom Postgres Config Ayarı (Resimli Yol Haritası)

Bu ayar Supabase Dashboard'da **farklı projelerde farklı yerlerde** olabilir. İşte olası konumlar ve nasıl bulunacağı:

---

## 🔍 Yöntem 1: Yeni Dashboard (Postgres Config sayfası) — ÖNERİLEN

Bu en kolay yoldur. Aşağıdaki adımları takip et:

1. https://supabase.com/dashboard adresine git, projeyi seç.
2. Sol menüden **"Database"** tıkla.
3. Açılan sayfada **"Configuration"** veya **"Settings"** sekmesine tıkla.
4. Sayfayı aşağı kaydır → **"Custom Postgres Config"** veya **"Customized Postgres Config"** bölümünü bul.
5. Sağ üstte **"Add variable"** veya **"+ Add new"** butonuna bas.
6. **Name** alanına: `app.settings.internal_worker_secret`
7. **Value** alanına: güçlü bir random secret (ör. `openssl rand -hex 32` çıktısı)
   - Örnek: `a3f5e9c1b2d4e6f8a3f5e9c1b2d4e6f8a3f5e9c1b2d4e6f8a3f5e9c1b2d4e6f8`
8. **Save** veya **Apply** tıkla.
9. Değişikliğin aktif olması için Supabase birkaç saniye içinde DB'yi restart eder; otomatik olur.

---

## 🔍 Yöntem 2: SQL Editor ile Kalıcı Ayar (Custom Config'e gerek kalmadan)

Eğer **Custom Postgres Config** alanını bulamıyorsan veya erişemiyorsan, **doğrudan SQL Editor'den `ALTER DATABASE` ile** ayarlayabilirsin. Bu daha kolay ve yeterli:

### 1) Secret üret (terminalde bir kez çalıştır)
```bash
openssl rand -hex 32
```
Çıkan değeri kopyala (ör. `a3f5e9c1b2d4e6f8...`). Bir yere de not al.

### 2) SQL Editor'de şu sorguyu çalıştır
**`BURAYA_SECRET_YAPISTIR`** kısmını kendi secret'ınla değiştir:

```sql
ALTER DATABASE postgres SET app.settings.internal_worker_secret = 'BURAYA_SECRET_YAPISTIR';
```

### 3) Doğrula
```sql
SELECT current_setting('app.settings.internal_worker_secret', true) AS secret_ayar;
```
Secret dönmeli (Supabase SQL Editor gizleyebilir, ama `length(...) > 0` kontrolü yapabilirsin):
```sql
SELECT length(current_setting('app.settings.internal_worker_secret', true)) AS secret_length;
```
`secret_length > 30` olmalı.

⚠️ **Önemli:** Bu yöntemle secret veritabanında **şifrelenmiş olmadan düz metin olarak** durur. ADIM 5'te Edge Function env'inde de aynı secret'ı kullanacaksın. Production için Yöntem 1 önerilir.

---

## 🔍 Yöntem 3: psql ile

Terminalde proje dizinindeyken:
```bash
supabase db psql --project-ref <PROJECT_REF>
```
ardından:
```sql
ALTER DATABASE postgres SET app.settings.internal_worker_secret = 'BURAYA_SECRET_YAPISTIR';
\q
```

---

## ✅ Ayardan Sonra Kontrol

`supabase/diagnostics/20260807_setup_cron_safe.sql` dosyasını SQL Editor'de çalıştır. Şu mesajı görmelisin:

```
NOTICE: ✅ app.settings.internal_worker_secret custom config'e yazıldı.
NOTICE: ✅ Cron job kuruldu.
```

En altta:
```
jobname                                       | schedule  | active | sonraki_calisma
process-notification-outbox-every-minute      | * * * * * | t      | 2026-08-07 ...
```

`active = t` ve `sonraki_calisma` gelecekte bir zaman olmalı.

---

## 🆘 Hâlâ Bulamıyorsan

**Yöntem 2 (ALTER DATABASE)** en garantili yol. Custom Config UI bazen pro plan'a bağlı olabilir, ALTER DATABASE ise tüm planlarda çalışır.

Custom Config ekranını bulmak için:
- Sol menü → **Database** → **Settings** (dişli ikonu) → aşağı kaydır
- VEYA: Sol menü → **Project Settings** (en altta) → **Database** → **Custom Postgres Config**

---

**Secret'ı ayarladıktan sonra ADIM 2'ye (migration) geçebiliriz.**
