# SQL Migration Dosyaları - Çalıştırma Rehberi

## 📂 Dosya Listesi

Tüm migration'lar `plans/sql_migrations/` dizininde:

| # | Dosya | Modül | Öncelik |
|---|-------|-------|---------|
| 01 | `20260728000001_auth_fixes.sql` | Auth (Login/Kayıt) | 🚨 Yüksek |
| 02 | `20260728000002_chat_rls_fixes.sql` | Chat (Mesajlaşma) | 🚨 Yüksek |
| 03 | `20260728000003_market_fixes.sql` | Market (E-ticaret) | 🚨 Yüksek |
| 04 | `20260728000004_order_fixes.sql` | Order (Sipariş) | 🚨 Yüksek |
| 05 | `20260728000005_payment_fixes.sql` | Payment/Wallet | ⚠️ Orta |
| 06 | `20260728000006_storage_fixes.sql` | Storage | ⚠️ Orta |
| 07 | `20260728000007_social_fixes.sql` | Social | ⚠️ Orta |
| 08 | `20260728000008_admin_fixes.sql` | Admin | ⚠️ Orta |
| 09 | `20260728000009_notification_fixes.sql` | Notification | 📋 Düşük |
| 10 | `20260728000010_smm_fixes.sql` | SMM (Dijital) | 📋 Düşük |
| 11 | `20260728000011_courier_fixes.sql` | Courier (Kurye) | 📋 Düşük |
| 12 | `20260728000012_news_fixes.sql` | News (Haber) | 📋 Düşük |

## 🚀 Çalıştırma Yöntemleri

### Yöntem 1: Supabase Dashboard (Önerilen)

1. https://supabase.com/dashboard adresine gidin
2. Projenizi seçin (`xsbukxkgtmdyickknqzf`)
3. Sol menüden **SQL Editor**'ı açın
4. **New query** tıklayın
5. Dosya içeriğini yapıştırın
6. **Run** tıklayın
7. Sonuçları kontrol edin (Success: ✓)

### Yöntem 2: Supabase CLI (Local Development)

```bash
# Proje dizininde
supabase db reset  # Opsiyonel: tüm verileri sıfırlar

# Migration'ları sırayla çalıştır
supabase db push

# Veya tek tek
psql -h db.xsbukxkgtmdyickknqzf.supabase.co -U postgres -d postgres -f plans/sql_migrations/20260728000001_auth_fixes.sql
psql -h db.xsbukxkgtmdyickknqzf.supabase.co -U postgres -d postgres -f plans/sql_migrations/20260728000002_chat_rls_fixes.sql
# ... devamı
```

### Yöntem 3: psql (Remote)

```bash
# .env dosyasından DATABASE_URL al
export DATABASE_URL="postgresql://postgres:[PASSWORD]@db.xsbukxkgtmdyickknqzf.supabase.co:5432/postgres"

# Migration'ları sırayla çalıştır
for f in plans/sql_migrations/*.sql; do
  echo "Running $f..."
  psql "$DATABASE_URL" -f "$f"
done
```

## ⚠️ ÖNEMLİ UYARILAR

### 1. Yedek Al
```bash
# Migration çalıştırmadan ÖNCE
pg_dump "$DATABASE_URL" > backup_$(date +%Y%m%d_%H%M%S).sql
```

### 2. Sırayla Çalıştır
Migration'lar birbirine bağlı. Sırayla çalıştırın (01 → 02 → 03 → ...).

### 3. Production'da Test Et
- Önce **staging** ortamında test edin
- Sonra production'a uygulayın
- Çalışma saatleri dışında uygulayın

### 4. Hata Durumunda
```sql
-- Eğer bir hata oluşursa:
-- 1. Transaction otomatik rollback olur
-- 2. pg_stat_activity'den kontrol et
SELECT pid, query, state FROM pg_stat_activity WHERE state = 'active';

-- 3. Lock varsa bekle veya kill et
SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE pid = <PID>;
```

## ✅ Doğrulama (Çalıştırdıktan Sonra)

```sql
-- 1. Yeni fonksiyonları kontrol et
SELECT routine_name FROM information_schema.routines
WHERE routine_schema = 'public'
  AND routine_name IN (
    'get_email_by_username',
    'mark_messages_as_read',
    'get_shops_delivery_info',
    'create_order_with_items',
    'use_balance_for_order',
    'check_withdrawal_limit',
    'check_storage_object',
    'increment_post_view',
    'is_admin',
    'log_admin_action',
    'dedup_notification',
    'upsert_courier_location',
    'check_smm_rate_limit'
  )
ORDER BY routine_name;

-- 2. Yeni tabloları kontrol et
SELECT table_name FROM information_schema.tables
WHERE table_schema = 'public'
  AND table_name IN (
    'login_attempts',
    'withdrawal_attempts',
    'smm_rate_limits',
    'admin_audit_log'
  )
ORDER BY table_name;

-- 3. RLS politikalarını kontrol et
SELECT schemaname, tablename, policyname
FROM pg_policies
WHERE schemaname = 'public'
ORDER BY tablename, policyname;
```

## 📊 Değişiklik Özeti

- **Yeni Fonksiyon:** 13 adet
- **Yeni Tablo:** 4 adet
- **Yeni Index:** 25+ adet
- **RLS Policy:** 25+ güncellendi
- **Trigger:** 5 yeni
- **Sequence:** 1 yeni (order_number_seq)

## 🔄 Rollback

Her dosyanın sonunda gerekirse rollback için DROP IF EXISTS kullanılmıştır. Ama tam geri alma için:

```sql
-- 01 rollback
DROP FUNCTION IF EXISTS get_email_by_username(TEXT);
DROP TABLE IF EXISTS login_attempts CASCADE;
DROP INDEX IF EXISTS idx_profiles_username_lower;

-- 04 rollback
DROP FUNCTION IF EXISTS create_order_with_items CASCADE;
DROP FUNCTION IF EXISTS generate_order_number CASCADE;
DROP TRIGGER IF EXISTS trg_generate_order_number ON orders;
ALTER TABLE orders DROP CONSTRAINT IF EXISTS orders_order_number_unique;
DROP SEQUENCE IF EXISTS order_number_seq;
```

---

**Tarih:** 2026-07-28
**Proje:** CizreApp
**Toplam Migration:** 12 dosya
**Çalıştırma Süresi:** ~2-5 dakika (her dosya için)
