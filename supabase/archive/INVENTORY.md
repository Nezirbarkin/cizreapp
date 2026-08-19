# Supabase SQL Dosya Envanteri

**Tarih:** 2026-07-27
**Amaç:** `supabase/` kök dizinindeki ve `migrations/` içindeki düzensiz SQL dosyalarının envanteri.
**Toplam:** 54 root SQL + 277 migrations SQL = **331 SQL dosyası**

## Sınıflandırma Özeti

| Kategori | Root (54) | Migrations (277) | Toplam |
|---|---:|---:|---:|
| Aktif (tarih formatlı, prod'a uygulanmış/uygulanacak) | 25 | 253 | **278** |
| Tarih formatına uymayan (Supabase CLI skip ediyor) | 0 | 24 | **24** |
| Tarih formatında ama manuel SQL Editor'den uygulanmış | 29 | 0 | **29** |
| **Toplam işlenen** | **54** | **277** | **331** |

## Kategoriler

### ✅ KEEP_AS_MIGRATION (25 root + 24 migrations formatı yanlış = 49)
Prod'a uygulanmış veya uygulanacak geçerli migration'lar. Bunlar `migrations/` içinde sıralı tutulacak.

**Root'tan → migrations/'a taşınacak (25):**
- `20260719000001_task_earning_system.sql` (10.5K, 19 Tem)
- `20260719000002_task_earning_rls_rpc.sql` (28K, 19 Tem)
- `20260719000003_fix_get_active_tasks_signature.sql` (3.1K)
- `20260719000004_task_images.sql` (3.0K)
- `20260719000005_add_image_url_to_get_active_tasks.sql` (2.9K)
- `20260720000001_fix_screenshot_url_nullable.sql` (387B)
- `20260720000002_task_multi_images.sql` (2.9K)
- `20260720000003_fix_admin_get_task_submissions_ambiguous_id.sql` (2.5K)
- `20260720000004_grant_ad_reward_atomic_rpc.sql` (5.9K)
- `20260720000005_add_task_notification_types.sql` (1.8K)
- `20260720000006_suspicious_users.sql` (1.6K)
- `20260724000000_fix_linter_warnings.sql` (4.3K)
- `20260724000001_notify_admin_on_task_claim.sql` (3.4K)
- `20260724000002_show_paused_completed_tasks.sql` (3.1K)
- `20260724000003_add_courier_realtime_tracking.sql` (2.0K)
- `20260724000004_courier_service_notices.sql` (2.8K)
- `20260725000001_sehirici_services.sql` (33.7K)
- `20260725000002_add_driver_role.sql` (3.3K) ← name: "debug" görünüyor ama içerik migration
- `20260725000003_sehirici_admin_crud.sql` (9.9K)
- `20260725000004_sehirici_route_and_settings_fix.sql` (3.3K)
- `20260725000005_sehirici_road_route_cache.sql` (3.9K)
- `ADD_DELIVERED_COURIER_COLUMNS.sql` → yeni isim: `20260617000001_add_delivered_courier_columns.sql`
- `ADD_ONLINE_ENABLED_COLUMN.sql` → `20260617000002_add_online_enabled_column.sql`
- `ADD_POST_REPORT_NOTIFICATION_TYPE.sql` → `20260525000001_add_post_report_notification_type.sql`
- `FLASH_SALE_AND_PRICE_ALERT_SETUP.sql` (13.7K) → `20260725000006_flash_sale_and_price_alert_setup.sql`
- `GUEST_ACCESS_SUPPORT_ABOUT.sql` (1.5K) → `20260412000001_guest_access_support_about.sql`
- `LIVE_SHOPPING_SETUP.sql` (10.7K) → `20260725000007_live_shopping_setup.sql`
- `NEW_FEATURES.sql` (3.0K) → `20260412000002_new_features.sql`
- `push_notification_trigger.sql` (2.4K) → `20260412000003_push_notification_trigger.sql`
- `COURIER_STATUS_CHANGE.sql` (3.7K) → `20260412000004_courier_status_change.sql`
- `20260719000099_debug_task_earning.sql` (3.2K) → ⚠️ name: "debug" ama gerçek migration; içerik kontrol edilecek

### 📦 ARCHIVE_HISTORICAL (14 root)
Eski/tek seferlik fix'ler, "FINAL"/"COMPLETE" varyantları, adım adım kurulum scriptleri. Production'a uygulanmış olabilir ama artık referans olarak duruyorlar. `archive/2025-q1/`, `archive/2025-q2/`, `archive/2026-q2/` klasörlerine taşınacak.

**Commission sistemi eski fix'leri:**
- `COMMISSION_SYSTEM_COMPLETE_FIX.sql` (11.9K) → `archive/2025-q1/`
- `FINAL_COMMISSION_FIX.sql` (9.6K) → `archive/2025-q1/`
- `DEBUG_COMMISSION_SYSTEM.sql` (2.3K) → `archive/2025-q1/`
- `DEBUG_DUPLICATE_TRIGGERS.sql` (1.7K) → `archive/2025-q1/`

**RLS fix'leri:**
- `FIX_ADMIN_VIEW_SECURITY.sql` (1.8K, 10 Tem) → `archive/2026-q2/`
- `FIX_DUPLICATE_ORDER_NOTIFICATIONS_FINAL.sql` (3.0K) → `archive/2025-q1/`
- `FIX_MISSING_COLUMN.sql` (680B) → `archive/2025-q1/`
- `FIX_SHOP_VIEWS_RLS.sql` (3.3K) → `archive/2025-q1/`

**Product Reviews (adım adım, çoklu versiyon):**
- `PRODUCT_REVIEWS_CLEAN_INSTALL.sql` (7.0K) → `archive/2025-q1/`
- `PRODUCT_REVIEWS_COMPLETE.sql` (8.9K) → `archive/2025-q1/`
- `PRODUCT_REVIEWS_MINIMAL.sql` (5.9K) → `archive/2025-q1/`
- `PRODUCT_REVIEWS_SETUP.sql` (10.2K) → `archive/2025-q1/`
- `STEP1_CREATE_REVIEWS_TABLE.sql` (939B) → `archive/2025-q1/`
- `STEP2_CREATE_HELPFUL_TABLE.sql` (522B) → `archive/2025-q1/`
- `STEP3_ADD_RATING_COLUMNS.sql` (310B) → `archive/2025-q1/`
- `STEP4_TRIGGERS.sql` (3.8K) → `archive/2025-q1/`

### 🔍 DEBUG_OR_QUERY (15 root + 0 migrations = 15)
Production'a deploy edilmemiş analiz/yardım dosyaları. `archive/debug-queries/` altına taşınacak.

- `20260719000099_debug_task_earning.sql` (3.2K) → içerik SELECT kontrol edilecek
- `CHECK_NOTIFICATION_CONSTRAINTS.sql` (971B) → `archive/debug-queries/`
- `DEBUG_COMMISSION_SYSTEM.sql` (2.3K) → `archive/debug-queries/`
- `DEBUG_DUPLICATE_TRIGGERS.sql` (1.7K) → `archive/debug-queries/`
- `debug_admin_panel.sql` (189B) → `archive/debug-queries/`
- `debug_admin_panel_full.sql` (3.2K) → `archive/debug-queries/`
- `query1_orders_columns.sql` (368B) → `archive/debug-queries/`
- `query2_products_rls.sql` (410B) → `archive/debug-queries/`
- `query3_orders_rls.sql` (406B) → `archive/debug-queries/`
- `query4_auth_is_admin.sql` (464B) → `archive/debug-queries/`

## Migrations/ İçindeki Düzensiz Dosyalar (24)

Bu dosyalar tarih formatına uymadığı için Supabase CLI tarafından **skip** ediliyor. Production'a uygulanmamış olabilirler veya SQL Editor'den manuel uygulanmış olabilirler. **Mevcut halleriyle bırakılacak** ama `_README.txt` ile durumları belgelenecek. Yeni taşınan dosyalarla birlikte değerlendirilip gerekirse tarih formatına çevrilecek.

```
09_create_follows_table.sql
ADD_IMAGE_TO_AI_QUICK_PROMPTS.sql
CREATE_AI_PROMPT_IMAGES.sql
FIX_ADMIN_ORDER_COURIER_INFO.sql
FIX_ADMIN_ORDER_DELETE.sql
FIX_ALL_RLS_AND_DATA.sql
FIX_COMMISSION_TRIGGER.sql
FIX_COURIER_ORDER_ASSIGNMENT.sql
add_api_keys_manual.sql
add_api_keys_to_settings.sql
add_is_pinned_columns.sql
add_messages_enabled_column.sql
ai_chat_fix_permissions.sql
check_role_enum.sql
check_story_likes_status.sql
create_ai_chat_tables.sql
create_return_requests_table.sql
fix_ai_settings_rls.sql
fix_provider_constraint.sql
fix_story_likes_count.sql
fix_story_likes_security.sql
insert_ai_settings.sql
update_gemini.sql
update_gemini_api_key.sql
update_groq_api_key.sql
```

## Hareket Planı (Sıralı)

1. **Adım 1:** Tarihi belirsiz root dosyaların **dosya içeriklerinin ilk 20 satırı** okunarak doğru tarih tahmin edilecek (mtime dosya sisteminden).
2. **Adım 2:** `archive/` klasör yapısı oluşturulacak.
3. **Adım 3:** `git mv` ile taşımalar yapılacak.
4. **Adım 4:** Manifest dosyaları yazılacak.
5. **Adım 5:** `supabase migration list` ile doğrulama.

## Tarih Belirleme Kuralı

- Dosya zaten `YYYYMMDDhhmmss` formatındaysa → aynen korunur
- Değilse → `git log --diff-filter=A --follow --format="%ai" -- <file>` ile **ilk commit tarihi** alınır
- O da yoksa → `mtime` kullanılır
- Hiçbiri yoksa → `20260101000000` placeholder (not düşülür)
