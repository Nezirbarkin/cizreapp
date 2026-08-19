# PROJE_HAVIZA_RLS

Son güncelleme: 2026-07-30
Project Ref: `xsbukxkgtmdyickknqzf`

## 1) Genel RLS Durumu

Projede RLS yoğun kullanılıyor.  
Özellikle şu alanlarda politika seti kapsamlı:

- `profiles`
- `orders`, `order_items`
- `shops`, `products`
- `messages`, `conversations`
- `groups` ve `group_*`
- `notifications`
- `ai_*`
- `storage.objects`
- [`user_point_accounts`](supabase/migrations/20260730000002_admob_reward_points_system.sql:916), [`point_ledger_entries`](supabase/migrations/20260730000002_admob_reward_points_system.sql:917), [`ad_reward_sessions`](supabase/migrations/20260730000002_admob_reward_points_system.sql:918) ve ödül/iade audit tabloları

## 2) Sık Kullanılan Yetki Pattern'leri

- `auth.uid()` ile sahiplik kontrolü
- `auth_is_admin()` / `is_admin()` (bkz. Kritik Not 2.1)
- Profil rolü kontrolü (`profiles.role = 'admin'`)
- Grup fonksiyonları:
  - `is_group_member(group_id, auth.uid())`
  - `is_group_admin(group_id, auth.uid())`

## 3) Domain Bazlı Özet

### 3.1 Profil / Kullanıcı
- Kullanıcı kendi profilini update edebilir.
- Admin profiller üzerinde geniş yetkiye sahip.
- Bildirim ve tercih tablolarında çoğunlukla “kendi kaydını gör/güncelle” modeli var.
- **Profil özellikleri (kozmetik) — `profile_feature_catalog` / `user_profile_features`** (2026-08-17, `20260817000005` ve devamı): Katalog `anon`/`authenticated`'a yalnız `is_active=true` satırlarla `select` açık; `user_profile_features` tablosuna doğrudan hiçbir rol erişemez (`revoke all ... from public, anon, authenticated`), tüm okuma/yazma `SECURITY DEFINER` RPC'ler üzerinden yapılır (`get_user_profile_features`, `get_my_profile_feature_assignments`, admin_* RPC'leri — bkz. `PROJE_HAVIZA_RPCS.md` §11a). Rozet/tik (`kind='badge'`) kullanıcı tarafından hiçbir RPC ile değiştirilemez, yalnız admin atar. 2026-08-18'de eklenen sipariş-tamamlama kilidi (`unlock_after_orders` kolonu + `unlock_order_milestone_profile_features()` trigger'ı, `20260818000001`) tabloya doğrudan `INSERT` yapan tek trigger'dır; `SECURITY DEFINER` ve sabit `search_path` ile çalışır, hata durumunda sessizce yutulur (sipariş güncellemesini asla engellemez — `trigger_create_seller_earnings` ile aynı desen).

### 3.2 Ürün / Mağaza
- Satıcı kendi mağazasının ürünlerinde insert/update/delete yapabilir.
- Admin override yetkisi bulunan policy’ler mevcut.
- Public/anon için görünürlük politikalı alanlar var (özellikle select policy’leri).

### 3.3 Sipariş
- Müşteri kendi siparişlerini görür.
- Satıcı kendi mağazasına ait siparişleri görür.
- Admin daha geniş görünürlük ve bazı durumlarda update/delete yetkisi alır.

### 3.4 Mesajlaşma
- 1-1 mesajlarda konuşma katılımcılığına bağlı görünürlük.
- Grup mesajlarında üyelik/adminlik koşullarına bağlı işlem.

### 3.5 AI
- `ai_conversations`, `ai_messages`, `ai_daily_usage` için kullanıcı sahipliği merkezli policy’ler.
- Admin için full/manage policy’leri de mevcut.
- `ai_settings` tarafında admin ve/veya authenticated temelli yazma policy’leri bulunuyor (kritik kontrol noktası).

### 3.6 Storage
- Bucket bazlı policy yaklaşımı var (`avatars`, `products`, `posts`, `stories`, `ai-uploads`, `ai-generated` vb.).
- Bazı bucket’larda public select + geniş insert/update/delete policy’leri mevcut; düzenli audit edilmeli.

## 4) Risk / Audit Checklist

### 4.1 Kritik Güvenlik Notları (2026-07-02 güncelleme)

#### 4.1.1 `is_admin()` vs `auth_is_admin()` — Yetki Farkı
İki fonksiyon aynı mantığı taşır (`profiles.role = 'admin'` kontrolü) ama **EXECUTE yetkileri farklıdır**:

| Fonksiyon | `SECURITY DEFINER` | `authenticated` EXECUTE | `anon` EXECUTE | Kullanım |
|-----------|:---:|:---:|:---:|---|
| `is_admin()` | ✅ Evet | ⚠️ **Elle eklenmeli** | ⚠️ **Elle iptal edilmeli** | RLS policy'ler (profiles, ai_settings, vb.) |
| `auth_is_admin()` | ❌ Hayır (STABLE) | ✅ Varsayılan | ✅ Varsayılan | Bazı legacy policy'ler |

**Neden önemli:** `is_admin()` SECURITY DEFINER olduğu için postgres rolüne düşer ve profiller tablosunu RLS'siz okur — bu doğru davranış. Ancak `CREATE OR REPLACE FUNCTION` sonrası GRANT'ler KORUNMAZ. Migration'larda `DROP FUNCTION ... CASCADE` + `CREATE FUNCTION` yapıldığında `GRANT EXECUTE` ayrıca verilmezse `authenticated` rolü fonksiyonu çağıramaz → **42501 permission denied**. Çözüm: `GRANT EXECUTE ON FUNCTION public.is_admin() TO authenticated; REVOKE EXECUTE ON FUNCTION public.is_admin() FROM anon;`.

#### 4.1.2 `profiles_update_own` Policy — Admin Yetkisi
Admin panelden rol değiştirme (`admin_dashboard_screen.dart`) şu akışı izler: `profiles UPDATE` → `profiles_update_own` policy → `is_admin()` çağrısı → yetki kontrolü. Bu akışın çalışması için:
1. `is_admin()` fonksiyonuna `authenticated` EXECUTE yetkisi olmalı.
2. Policy'de `is_admin()` çağrısı olmalı (veya `auth_is_admin()` çağrılıyorsa o fonksiyonun yetkileri tam olmalı).

Mevcut durum (DIAG 2026-07-02 teyitli): `profiles_update_own` → `is_admin()` çağırıyor. `is_admin()` → authenticated EXECUTE **yoktu**, `FIX_IS_ADMIN_PERMISSION_42501.sql` ile eklendi.

#### 4.1.3 orders_policy'de `is_admin()` Kullanımı — Alternatif Yaklaşım
orders policy'lerde admin kontrolü için `is_admin()` helper fonksiyonu KULLANILMAMALIDIR (V3_2 öğrenme). Bunun yerine doğrudan `EXISTS(SELECT 1 FROM profiles WHERE id=(SELECT auth.uid()) AND role='admin')` subquery kullanılmalı. Çünkü helper fonksiyon → SECURITY DEFINER → `auth.uid()` → `is_admin()` zinciri → RLS recursion veya yetki hatası riski taşır.

#### 4.1.4 Courier Assignments — orders_policy Recursion Riski
`courier_assignments` tablosunun policy'si `orders` tablosunu sorguluyorsa ve orders policy'si `courier_assignments`'i sorguluyorsa sonsuz döngü (42P17) oluşur. Çözüm: orders policy'de doğrudan tablo sorgusu yerine `assigned_courier_id` denormalize kolonu kullanılır (V3_2 yaklaşımı).

#### 4.1.5 `group_members` — Rol Yükseltme Açığı (2026-07-04, KRİTİK)
`group_members` tablosu üzerinde birbirini geçersiz kılan çok sayıda geçmiş migration vardı (GROUP_CHAT_SETUP → GROUP_CHAT_LINTER_FIX → FIX_GROUP_MEMBERS_INFINITE_RECURSION → FIX_OPEN_GROUP_JOIN → FIX_GROUP_MEMBERS_RLS_FINAL → FIX_GROUP_RLS_CLEAN_POLICIES → **FIX_GROUP_MEMBERS_RLS_BYPASS** — bu son dosya RLS'yi tamamen `DISABLE` ediyordu). Bulunan iki gerçek açık:

1. **Rol kendi kendine yükseltme**: "kendi satırını güncelleyebilir" UPDATE politikası `role` kolonunu da kapsıyordu — normal bir üye `.update({'role':'admin'})` ile kendini admin yapabiliyordu. RLS `USING`/`WITH CHECK` kolon bazlı fark göremediği için bu **BEFORE UPDATE trigger** (`trg_prevent_group_member_role_self_escalation`) ile kapatıldı — admin olmayan biri `role`'ü değiştiremiyor artık.
2. **Private gruba doğrudan INSERT ile katılım**: bazı geçmiş politika sürümlerinde INSERT için tek şart `user_id = auth.uid()` idi, `is_private` kontrolü yoktu → join-request onay akışı tamamen atlanabiliyordu.

Kanonik/güncel durum: `20260704_GROUP_SYSTEM_SECURITY_FIX_FINAL.sql` — bu dosya idempotenttir, tekrar çalıştırılabilir, hangi eski migration sırayla uygulanmış olursa olsun tutarlı son durumu garanti eder. **Bu tabloda yeni bir politika değişikliği yapılacaksa önce bu dosya referans alınmalı**, eski dosyalardan biri tekrar çalıştırılmamalı.

Ayrıca RLS/trigger içi yardımcı fonksiyonlar (`is_group_admin`, `is_group_member`, trigger fonksiyonu) ve `admin_add_group_member` RPC'si `anon` rolüne gereksiz şekilde açıktı (linter uyarısı) — `20260704_GROUP_LINTER_SECURITY_FIX.sql` ile EXECUTE yetkisi kısıtlandı.

#### 4.1.6 SMM (`smm_providers` / `digital_orders`) — 2026-07-10/13
- `smm_providers`: RLS açık; `REVOKE ALL FROM authenticated, anon` sonra kolon bazlı `GRANT` — SELECT sadece gizli olmayan kolonlarda (`api_key` HARİÇ, hiçbir policy/grant client'a bu kolonu açmaz, sadece Edge Function service-role okur). `smm_providers_select`: admin hepsini görür; satıcı sadece `owner_type='seller'` ve `owner_id` kendi shop'u olan satırları görür. `smm_providers_insert`/`update`: admin her zaman; satıcı sadece kendi shop'una sahipse VE `shops.can_use_own_smm_api=true` ise. `smm_providers_delete`: sadece admin.
- Kendi kendine yetki yükseltme koruması (group_members §4.1.5 ile AYNI DESEN): `shops.can_use_own_smm_api` kolonunu satıcı kendi UPDATE'iyle açamaz — `prevent_seller_self_grant_smm()` BEFORE UPDATE trigger'ı (SECURITY DEFINER) değişikliği admin değilse geri alır.
- `digital_orders`: RLS açık, sadece SELECT policy'si var (`digital_orders_select` — kullanıcı kendi siparişini, admin hepsini, satıcı kendi provider'ına ait siparişleri görür). INSERT/UPDATE client policy'si YOK — yeni sipariş rezervasyonu [`create_digital_order_with_points(uuid,uuid,text,integer,text,boolean)`](supabase/migrations/20260730000002_admob_reward_points_system.sql:576) ile service-role Edge Function üzerinden yapılır. Eski [`create_digital_order(uuid,uuid,text,integer)`](supabase/migrations/20260730000002_admob_reward_points_system.sql:973) imzası cutover'da tüm rollerden kapatılmıştır.
- BUG (20260710000004 ile düzeltildi): `digital_orders`'ta RLS SELECT policy'si vardı ama `authenticated` rolüne tablo-seviyesi `GRANT SELECT` YOKTU — policy eşleşse de PostgREST erişimi reddediyordu, müşteriler kendi siparişlerini göremiyordu. `GRANT SELECT ON digital_orders TO authenticated;` + `GRANT ALL ... TO service_role` ile giderildi.

#### 4.1.7 Bakiye tabloları (`user_balances` / `balance_transactions`) — 2026-07-15 (GÜVENLİK DÜZELTMESİ)
- BUG (kritik/orta risk): `20260621000007_CREATE_BALANCE_SYSTEM.sql` içinde tanımlanan `"Service can update balances"` (user_balances, FOR UPDATE) ve `"Service can insert transactions"` (balance_transactions, FOR INSERT) policy'leri `TO service_role` kısıtlaması OLMADAN yazılmıştı — isim "Service can..." olsa da `TO` belirtilmeyince policy TÜM rollere (dolayısıyla `authenticated`'a) uygulanır. `USING (true)`/`WITH CHECK (true)` olduğundan, teorik olarak herhangi bir authenticated kullanıcı PostgREST üzerinden `PATCH /rest/v1/user_balances` ile kendi bakiyesini manipüle edebilirdi. Kod tabanında bu tablolara client'tan doğrudan `.update()`/`.insert()` çağrısı yoktu (sadece Edge Functions üzerinden erişim), yani aktif sömürülen bir yol yoktu, ama DB seviyesinde savunma katmanı eksikti.
- DÜZELTME: her iki policy `TO service_role` ile sınırlandı. Migration: `20260715000001_restrict_balance_rls_to_service_role.sql`. Uygulandı ve doğrulandı (`pg_policies.roles = {service_role}`).
- Genel mimari zaten sağlamdı ve değişmedi: tüm bakiye mutasyonları Edge Functions (`get-balance`, `create-balance-topup`, `use-balance-for-order`, `refund-to-balance`, `admin-add-balance`, `admin-deduct-balance`) + `deduct_from_balance`/`atomic_add_balance_topup_secure` RPC'leri (FOR UPDATE lock, replay/rate-limit koruması) üzerinden yürütülüyor.

#### 4.1.8 AdMob SSV / Puan Sistemi — 2026-07-30 güncel sözleşme

Eski 2026-07-15 erişim açıklaması artık geçerli değildir. Additive migration doğrudan [`ad_settings`](supabase/migrations/20260730000002_admob_reward_points_system.sql:943) ve [`ad_reward_views`](supabase/migrations/20260730000002_admob_reward_points_system.sql:943) erişimini `anon`/`authenticated` rollerinden kaldırır; eski admin/user policy'lerini de drop eder. İstemci yalnız daraltılmış [`reward_points_public_config`](supabase/migrations/20260730000002_admob_reward_points_system.sql:904) ve [`my_ad_reward_sessions`](supabase/migrations/20260730000002_admob_reward_points_system.sql:911) view'larını kullanır.

| Nesne | RLS / policy | Tablo ACL | Gerçek istemci yüzeyi |
|---|---|---|---|
| [`user_point_accounts`](supabase/migrations/20260730000002_admob_reward_points_system.sql:73) | [`user_point_accounts_select_own`](supabase/migrations/20260730000002_admob_reward_points_system.sql:925): yalnız `auth.uid() = user_id` SELECT | `authenticated`: SELECT; anon ve doğrudan service-role mutation yok | Kullanıcı kendi puan projection'ını okur |
| [`point_ledger_entries`](supabase/migrations/20260730000002_admob_reward_points_system.sql:84) | [`point_ledger_entries_select_own`](supabase/migrations/20260730000002_admob_reward_points_system.sql:927): yalnız kendi satırı SELECT | `authenticated`: SELECT; INSERT/UPDATE/DELETE yok | Kullanıcı kendi puan geçmişini okur; trigger UPDATE/DELETE/TRUNCATE'i ayrıca reddeder |
| [`ad_reward_sessions`](supabase/migrations/20260730000002_admob_reward_points_system.sql:148) | [`ad_reward_sessions_select_own`](supabase/migrations/20260730000002_admob_reward_points_system.sql:929): yalnız kendi satırı SELECT | `authenticated`: SELECT; yazma yok | Kullanıcı safe view üzerinden SSV sonucunu poll eder |
| [`digital_order_refunds`](supabase/migrations/20260730000002_admob_reward_points_system.sql:306) | [`digital_order_refunds_select_own`](supabase/migrations/20260730000002_admob_reward_points_system.sql:931): bağlı sipariş `auth.uid()` kullanıcısına aitse SELECT | `authenticated`: SELECT; yazma yok | Kullanıcı kendi kaynak-koruyan iadesini okur |
| [`ad_reward_ssv_events`](supabase/migrations/20260730000002_admob_reward_points_system.sql:173), [`ad_reward_daily_budgets`](supabase/migrations/20260730000002_admob_reward_points_system.sql:195), [`reward_points_config_audit`](supabase/migrations/20260730000002_admob_reward_points_system.sql:61), [`reward_points_migration_audits`](supabase/migrations/20260730000002_admob_reward_points_system.sql:202) | RLS açık, kullanıcı/admin SELECT policy'si yok | PUBLIC/anon/authenticated/service_role doğrudan tablo yetkileri REVOKE | Yalnız owner SECURITY DEFINER fonksiyonları |

Tüm sekiz yeni tabloda önce [`REVOKE ALL`](supabase/migrations/20260730000002_admob_reward_points_system.sql:937) uygulanır; `service_role` bile doğrudan ledger/tablo mutation yetkisi almaz. Dar RPC'ler `reward_points_owner` adlı `NOLOGIN NOINHERIT` owner ile çalışır:

- [`create_ad_reward_session(uuid,text,text,text,text)`](supabase/migrations/20260730000002_admob_reward_points_system.sql:408), [`grant_verified_ad_points(uuid,text,text,text,text,timestamptz,text,text)`](supabase/migrations/20260730000002_admob_reward_points_system.sql:446), [`create_digital_order_with_points(uuid,uuid,text,integer,text,boolean)`](supabase/migrations/20260730000002_admob_reward_points_system.sql:599), [`refund_digital_order_payment(uuid,numeric,text,text,boolean)`](supabase/migrations/20260730000002_admob_reward_points_system.sql), [`set_digital_order_reconciliation(uuid,text)`](supabase/migrations/20260730000002_admob_reward_points_system.sql) ve [`purge_expired_reward_fraud_hashes(integer)`](supabase/migrations/20260730000002_admob_reward_points_system.sql): PUBLIC/anon/authenticated REVOKE, yalnız `service_role` EXECUTE.
- [`admin_update_reward_points_config(integer,integer,bigint,integer,text,boolean,boolean,boolean,boolean,text)`](supabase/migrations/20260730000002_admob_reward_points_system.sql:961): PUBLIC/anon/service_role REVOKE, `authenticated` EXECUTE; fonksiyon içinde `profiles.role='admin'` doğrulaması ve gerekçeli audit zorunludur.
- İç [`reward_points_apply_entry(uuid,text,text,bigint,text,uuid,text,jsonb)`](supabase/migrations/20260730000002_admob_reward_points_system.sql:947) tüm dış rollere, `service_role` dahil kapalıdır.
- Legacy [`grant_ad_reward(uuid,text,text,integer)`](supabase/migrations/20260730000002_admob_reward_points_system.sql:964) kredi vermeyen gövdeye dönüştürülmüş ve PUBLIC/anon/authenticated/service_role'dan REVOKE edilmiştir.

**Fail-closed değişmezi:** Edge Function Google imzasını doğrulamadan kredi RPC'sini çağırmaz. SQL katmanı da `service_role` claim'i, callback zaman penceresi, izinli ad-unit ve aynı anda `reward_points_earn_enabled=true`, `reward_points_ssv_required=true`, `reward_points_ssv_enabled=true`, `legacy_ad_tl_grant_disabled=true`, mode=`cohort|enabled` koşulları sağlanmadan puan yazmaz. İstemci SDK callback'i hiçbir RPC yetkisi sağlamaz.

**Puan → nakit değişmezi:** Çekirdek point account/ledger tablolarından TL bakiye/işlem tablolarına FK yoktur ve puan RPC'lerinin çekim/IBAN/transfer/fiziksel sipariş yetkisi veya yolu bulunmaz. [`digital_order_refunds`](supabase/migrations/20260730000002_admob_reward_points_system.sql:306) yalnız kaynak-koruyan iade audit'i için puan ledger ile TL balance-transaction bağlantılarını ayrı FK kolonlarında taşır; bir kaynağı diğerine dönüştürmez. Çekirdek point-storage→cash-storage FK yokluğu, rol sınırları, legacy kapatma ve no-backfill dahil seçili katalog değişmezleri [`002_reward_points_security_invariants.test.sql`](supabase/tests/database/002_reward_points_security_invariants.test.sql:1) içindeki 26 pgTAP assertion'ı ile denetlenir; composition audit FK'lerinin kesin tanımı migration kaynağıdır.

#### 4.1.9 Görev Yaparak Kazan Sistemi (`task_categories` / `tasks` / `task_submissions`) — 2026-07-19
- `task_categories`: SELECT public (anon+authenticated dahil), INSERT/UPDATE/DELETE yalnızca `EXISTS(SELECT 1 FROM profiles WHERE id=auth.uid() AND role='admin')`. Doğrudan subquery kullanıldı (helper fonksiyon zinciri recursion/permission riskini önler, §4.1.3 öğrenimi).
- `tasks`: kullanıcı yalnız `status='active' AND starts_at<=NOW() AND (expires_at IS NULL OR expires_at>NOW())` görevleri görür; admin hepsini görür (admin override). INSERT/UPDATE/DELETE yalnız admin. Partial index `WHERE status='active'` okuma performansı için.
- `task_submissions`:
  - SELECT: kullanıcı kendi (`user_id=auth.uid()`) VEYA admin.
  - INSERT: kullanıcı yalnız kendi `user_id` ile, status='pending' (UPDATE-only-policy ile başvuru aşamasında `user_note/screenshot_url` güncelleyebilir).
  - UPDATE iki koldan:
    1. Kullanıcı kendi pending başvurusunu güncelleyebilir (yanlış yüklenen görseli değiştir).
    2. Admin tüm kayıtları güncelleyebilir (status değişimi, review bilgileri).
  - **KRİTİK partial unique index**: `(task_id, user_id) WHERE status IN ('pending','approved')` — aynı kullanıcı aynı göreve 1 kez katılabilir; rejected → tekrar başvurabilir. Bu, client-side kontrolden BAĞIMSIZ bir DB seviyesi race condition koruması.
- **Bakiye mutasyonu §4.1.7 prensibi**: tüm yazma client'tan YAPILAMAZ. `approve_task_submission` RPC SECURITY DEFINER + service_role; client hiçbir zaman `user_balances` veya `balance_transactions`'a INSERT/UPDATE yapamaz. `add_to_balance` RPC atomik (FOR UPDATE) çağrılır.
- **`task_screenshots` Storage bucket**: SELECT public (admin kolayca görüntüleyebilsin), INSERT/UPDATE yalnız kullanıcı kendi `user_id/` klasörüne (`(storage.foldername(name))[1] = auth.uid()`), DELETE sahibi veya admin.
- **Realtime**: `task_submissions` ve `tasks` `supabase_realtime` publication'a eklendi → admin panel canlı güncellenir, kullanıcı kendi durum değişikliğini push beklemeden UI'da görür.
- **Linter güvenliği**: Tüm RPC'lerde `REVOKE ALL ON FUNCTION ... FROM PUBLIC` (anon çağıramaz), auth-only olanlar GRANT EXECUTE TO authenticated; yetki gerektirenler authenticated + service_role. `grant-ad-reward` ile aynı desen.
- **Anti-pattern öğrenmeleri (PROJE_HAVIZA'dan)**:
  1. `is_admin()` helper'ı RPC İÇİNDE çağrıldı ama SECURITY DEFINER etkisine girmedi (function gövdesinde zaten postgres bağlamı). Yine de tutarlılık için profiles subquery kullanıldı — gelecekte role değişirse helper'a düşme riski azalır.
  2. trigger/functions'ta `auth.uid()` ASLA kullanılmadı — yalnızca client param ya da `NEW.user_id` gibi doğrudan değer (PROJE_HAVIZA §4.1.5 42501 hatası tekrarı önlenir).
  3. Storage policy'leri `TO authenticated` (anon RETAIN DEFAULT) — anonim kullanıcı yükleme yapamaz.
  4. Realtime publication `DO ... ON CONFLICT` ile idempotent eklendi (tekrar çalıştırılabilir).
- Test: bir kullanıcı aynı görev için 2 RPC parallel çağırdığında ikinci `claim_task` ya hata alır ya da no-op (partial unique index → INSERT çakışırsa transaction rollback). Onay + tekrar onay çağrısı → `status: 'already_approved'` (idempotent guard).

### 4.2 Standart Audit Checklist

- Çok geniş (`public` rolüne açık) write policy var mı?
- `WITH CHECK` sahiplik doğrulaması düzgün mü?
- Admin kontrolü sadece JWT role’a mı bağlı, yoksa `profiles` doğrulaması da var mı?
- Storage bucket policy’lerinde gereksiz anon write var mı?
- Aynı tabloda çakışan/duplicate policy var mı?

## 5) Önerilen Rutin

- Her migration sonrası RLS diff kontrolü
- Aylık policy audit
- Kritik tablolar için test senaryoları:
  - Owner erişimi
  - Non-owner erişim engeli
  - Admin override
  - Anon erişim sınırları
