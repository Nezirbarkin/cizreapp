# Plan: Supabase Güvenlik Linter Uyarıları

Tarih: 2026-07-05
Mod: Architect → Code

## 1) Tespit Edilen Uyarılar (Supabase Database Linter)

**4 kritik kategori, ~190 uyarı (WARN seviye). Hiçbiri ERROR değil ama prod için hepsi düzeltilmeli:**

### 1.1 `function_search_path_mutable` (8 fonksiyon)
`public.update_seller_earnings_timestamp`, `public.update_user_balances_timestamp`, `public.update_seller_withdrawals_timestamp`, `public.update_profile_fields`, `public.create_seller_earnings_on_delivery`, `public.add_to_balance`, `public.deduct_from_balance`, `public.create_user_balance_on_signup`

**Risk:** Fonksiyon `SET search_path` kullanmıyor → saldırgan `search_path`'e `pg_catalog.pg_user` gibi sahte şema ekleyip yetkisiz tablo erişimi sağlayabilir. **Düzeltme:** `ALTER FUNCTION ... SET search_path = public, pg_temp` (REPLACE gerekmez, basit ALTER).

### 1.2 `rls_policy_always_true` (3 politika) — EN KRİTİK
- `balance_transactions` INSERT `Service can insert transactions` → WITH CHECK (true) → RLS bypass
- `seller_earnings` ALL `Service can manage earnings` → USING + WITH CHECK (true) → RLS bypass
- `user_balances` UPDATE `Service can update balances` → USING + WITH CHECK (true) → RLS bypass

**Risk:** Anon kullanıcı bile bu tablolara INSERT/UPDATE yapabilir (RLS yok). Hassas finansal tablolar!
**Düzeltme:** Bu policy'ler "service role" için tasarlanmış (Supabase'in service_role key bypass eder RLS'yi). Doğru yaklaşım: `TO service_role` ile sınırla.

### 1.3 `public_bucket_allows_listing` (2 bucket)
- `storage.objects` policy: `avatars` ve `covers` SELECT → kullanıcı bucket'taki TÜM dosyaları listeleyebilir.

**Risk:** Bilgi sızıntısı (diğer kullanıcıların dosya isimleri/URL'leri görülebilir).
**Düzeltme:** Policy'yi `TO authenticated` ile sınırla veya daha spesifik path-based policy'ye çevir.

### 1.4 `anon_security_definer_function_executable` (~80 fonksiyon)
Çoğu `SECURITY DEFINER` fonksiyon (notify_*, update_*_timestamp, get_*, is_*, admin_*, vs.) anonim olarak çağrılabilir.

**Risk:** SECURITY DEFINER + anon çağrı = yetki yükseltme potansiyeli. Çoğu fonksiyon bunu tasarım olarak yapmıyor (`is_admin()` gibi kontrol fonksiyonları anon tarafından çağrılabilmeli).

**Ancak:** Bu fonksiyonları revoke etmek **mevcut Flutter uygulamasını kırabilir** — özellikle `is_admin()`, `update_*_timestamp`, `handle_new_user()`, `notify_*` gibi Flutter tarafından doğrudan çağrılanlar.

**Düzeltme stratejisi (DİKKATLİ, her birini test ederek):**
1. **Güvenli revoke listesi** (anon için kesinlikle gereksiz): `admin_*` (admin panel), `validate_payout_request`, `request_withdrawal`, `process_withdrawal`
2. **Bırakılacaklar** (anon/auth için gerekli): `is_admin`, `handle_new_user`, `notify_*` (trigger), `update_*_timestamp` (trigger), `send_email`, `check_app_version`, `get_categories_with_shop_count`, `get_online_users`
3. **Trigger fonksiyonları** (anon tarafından çağrılmaz, trigger context'inde çalışır): hepsi bırakılacak

### 1.5 `authenticated_security_definer_function_executable` (aynı set)
Authenticated için de aynı risk var. Burada `admin_*` fonksiyonları revoke edilebilir (kullanıcılar admin panele direkt RPC çağrısı yapmamalı).

### 1.6 `auth_leaked_password_protection` (1 uyarı)
HaveIBeenPwned.org entegrasyonu kapalı. **Dashboard'dan açılır, SQL değil.**

## 2) Plan — Katmanlı Uygulama (Riskli olanları kullanıcıya soracağım)

### Adım 1 — DÜŞÜK RİSK (hemen uygula)
1. **`function_search_path_mutable`** (8 fonksiyon): `ALTER FUNCTION ... SET search_path = public, pg_temp` — güvenli, geriye dönük uyumlu, kırılma riski yok
2. **CHANGELOG kaydı**

### Adım 2 — ORTA RİSK (Rapor'un analizi, kullanıcı onayı sonrası)
1. **`rls_policy_always_true`** (3 politika): `TO service_role` ile sınırla
   - **Test:** Bu policy'ler ile Flutter'ın ekleme/güncelleme işlemleri etkilenmemeli (Flutter anon/authenticated olarak bağlanır, service_role'ü çağırmaz).
   - **Güvenli:** `service_role` PostgREST'ten değil sadece Edge Functions / backend'ten çağrılır.
2. **`public_bucket_allows_listing`**: `storage.objects` policy'leri `TO authenticated` ile sınırla + path prefix ekle (ör. sadece `/userid/*`).

### Adım 3 — YÜKSEK RİSK (Kullanıcıya detaylı soru)
1. **`anon_security_definer_function_executable`**: Hangi fonksiyonları revoke edeceğim netleştirilmeli.
2. **`authenticated_security_definer_function_executable`**: Aynı şekilde.

### Adım 4 — Dashboard
1. `auth_leaked_password_protection`: Kullanıcıya Dashboard'dan açması için talimat ver.

## 3) Adım 1 Uygulama Planı (SQL — Düşük Risk)

```sql
-- 1.1 function_search_path_mutable düzeltmesi
ALTER FUNCTION public.update_seller_earnings_timestamp SET search_path = public, pg_temp;
ALTER FUNCTION public.update_user_balances_timestamp SET search_path = public, pg_temp;
ALTER FUNCTION public.update_seller_withdrawals_timestamp SET search_path = public, pg_temp;
ALTER FUNCTION public.update_profile_fields SET search_path = public, pg_temp;
ALTER FUNCTION public.create_seller_earnings_on_delivery SET search_path = public, pg_temp;
ALTER FUNCTION public.add_to_balance SET search_path = public, pg_temp;
ALTER FUNCTION public.deduct_from_balance SET search_path = public, pg_temp;
ALTER FUNCTION public.create_user_balance_on_signup SET search_path = public, pg_temp;
NOTIFY pgrst, 'reload schema';
```

**Güvenli:** Bu fonksiyonlar zaten `public` semasında çalışıyor, sadece arama yolunu sabitliyoruz. Mevcut davranış değişmez. Flutter tarafı etkilenmez.

## 4) Adım 2 Uygulama Planı (SQL — Orta Risk)

```sql
-- 2.1 balance_transactions: Service policy'yi sınırla
DROP POLICY IF EXISTS "Service can insert transactions" ON public.balance_transactions;
CREATE POLICY "Service can insert transactions"
  ON public.balance_transactions FOR INSERT
  TO service_role
  WITH CHECK (true);

-- 2.2 seller_earnings: Service policy'yi sınırla
DROP POLICY IF EXISTS "Service can manage earnings" ON public.seller_earnings;
CREATE POLICY "Service can manage earnings"
  ON public.seller_earnings FOR ALL
  TO service_role
  USING (true)
  WITH CHECK (true);

-- 2.3 user_balances: Service policy'yi sınırla
DROP POLICY IF EXISTS "Service can update balances" ON public.user_balances;
DROP POLICY IF EXISTS "Service can manage balances" ON public.user_balances; -- fallback
CREATE POLICY "Service can update balances"
  ON public.user_balances FOR UPDATE
  TO service_role
  USING (true)
  WITH CHECK (true);

-- 2.4 storage.objects avatars/covers: sadece authenticated
DROP POLICY IF EXISTS "Anyone can read avatars" ON storage.objects;
CREATE POLICY "Authenticated can read avatars"
  ON storage.objects FOR SELECT
  TO authenticated
  USING (bucket_id = 'avatars');

-- covers için benzer
```

**Risk:** Flutter'da storage URL'leri nasıl çalışıyor kontrol edilmeli. Eğer `public` olarak CDN cache'ine düşmüş URL'ler kullanılıyorsa, anon erişim için farklı çözüm gerekebilir (signed URL).

## 5) Risk Değerlendirmesi

| Adım | Risk | Etki |
|------|------|------|
| 1.1 search_path | **Yok** | Geriye dönük tam uyumlu |
| 2.1-2.3 RLS service_role | **Orta** | Edge functions doğrudan service_role ile çalışır, ancak bazı SQL trigger'lar da SECURITY DEFINER ile çalışıp RLS bypass eder. Bu fonksiyonlar etkilenmez. Flutter etkilenmez. |
| 2.4 storage SELECT | **Orta** | Profil fotoğrafı gibi public içerikler artık `authenticated` gerektirir; eğer uygulama public storage URL'i kullanıyorsa broken image. |
| 3 anon revoke | **Yüksek** | ~80 fonksiyonun her birini tek tek değerlendirmek gerek |
| 3 auth revoke | **Yüksek** | Admin_* hariç çoğu gerekli |

## 6) Önerilen Acil Aksiyon

**Sadece Adım 1'i (search_path) hemen uygulayalım** — riski yok, ~5 dk'da tamamlanır.

Adım 2 ve 3 için sırayla ilerleyelim — her birinden önce storage ve fonksiyon kullanım detaylarını Flutter kodundan teyit edip sana sunarım, onayınla uygulayacağım.

## 7) Sorulacak Sorular (Kullanıcıya)

1. **Adım 1 (search_path)** hemen uygulayalım mı? (Risk yok)
2. **Adım 2 (RLS service_role)** uygulayalım mı? (Orta risk, Edge Functions etkilenmez ama test etmemiz gerek)
3. **Adım 3 (anon/auth revoke)** için ayrı bir oturumda fonksiyon bazlı plan ister misin?
4. **`auth_leaked_password_protection`** için Dashboard'dan açma talimatı vereyim mi?