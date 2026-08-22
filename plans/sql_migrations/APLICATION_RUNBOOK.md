# Uygulama Kontratı Düzeltmesi — Çalıştırma Kılavuzu

Bu kılavuz, `CIZREAPP_TESHIS.sql` raporunun işaret ettiği eksik nesneleri
tek bir dosyada toplayan **konsolide migration**'ı üretmeyi, uygulamayı ve
doğrulamayı açıklar.

## 1. Sorun

Teşhis raporu 7 eksik RPC, bir dizi eksik tablo/view, eksik RLS policy ve
eksik yetkiler bildirdi. Bunların kök nedeni, ilgili kaynak migration'ların
ya hiç oluşturulmaması, ya `private` şemasında kalıp PostgREST'e açılmaması,
ya da yanlış kolon/tabloya referans vermesidir.

İlgili eksiklikler:

- **7 eksik RPC:** `admin_reward_points_overview`, `cancel_order`,
  `commit_balance_order`, `commit_cod_order`, `ensure_my_profile`,
  `prepare_checkout_session`, `set_my_presence`
- **Eksik tablo/view:** `user_point_accounts`,
  `reward_points_public_config`, `my_point_ledger_entries`,
  `my_ad_reward_sessions`, `public_profiles_safe`,
  `v_admin_commission_dashboard`, `v_debt_orders`, `api_keys`
- **Eksik RLS SELECT policy:** `news_views`
- **Eksik yetki:** `smm_providers` (kolon-bazlı SELECT grant)

## 2. Çözüm Yaklaşımı

Tek bir konsolide dosya, **daha önce test edilmiş** kaynak migration'ları
**verbatim** (birebir) birleştirir ve üzerine **3 cerrahi düzeltme** uygular.
Bu yaklaşım, hataya açık manuel yeniden yazım yerine, bilinen-iyi SQL'i
yeniden kullanmayı tercih eder.

### Kaynak dosyalar (dependency sırasıyla)

| Sıra | Dosya | Sağladığı |
|---|---|---|
| 1 | `20260730000002_admob_reward_points_system.sql` | puan tabloları + RPC'ler |
| 2 | `20260801000001_admin_reward_points_overview.sql` | `admin_reward_points_overview` |
| 3 | `20260802000006_server_authoritative_checkout_schema.sql` | checkout `private` şeması |
| 4 | `20260802000007_prepare_checkout_session_rpc.sql` | `prepare_checkout_session` |
| 5 | `20260802000008_commit_cod_and_balance_orders.sql` | `commit_cod_order` / `commit_balance_order` |
| 6 | `20260802000010_order_state_machine_rpc.sql` | `cancel_order` + durum makinesi |
| 7 | `_part_consolidated_commission_views.sql` | `v_debt_orders`, `v_admin_commission_dashboard` |
| 8 | `_part_consolidated_profile_objects.sql` | `public_profiles_safe`, `ensure_my_profile`, `set_my_presence` |
| 9 | `_part_consolidated_new_objects.sql` | `api_keys`, `news_views` policy, `smm_providers` grant |

### 3 cerrahi düzeltme

Birleştirme sonrası dosyaya uygulanan `sed` komutları:

1. **Şema taşıma:** `prepare_checkout_session`, `commit_cod_order`,
   `commit_balance_order` fonksiyonları `private.` → `public.` şemasına
   taşınır (CREATE/REVOKE/GRANT/COMMENT satırlarının tamamı). PostgREST
   yalnız `public` şemasını expose ettiği için bu gerekli.
2. **`cancel_order` audit INSERT düzeltmesi:** Olmayan kolonlara
   (`order_id`, `payload`) yazan INSERT, gerçek kolona (`detail`)
   çevrilir.
3. **Geçersiz GRANT temizliği:** Var olmayan
   `private.server_checkout_session_items` tablosuna yapılan GRANT
   satırı silinir.

## 3. Üretim (Build)

Gereksinimler: bash (Git Bash / WSL / macOS / Linux) ve dosya erişimi.

```bash
cd c:/Users/lenovo/cizreapp
bash build_consolidated_migration.sh
```

Script çalışınca:

- 9 kaynak dosyanın varlığını doğrular; biri eksikse durur.
- `supabase/migrations/20260804000002_fill_app_contract_gaps.sql`
  dosyasını oluşturur (header + BOLUM 0 sequence + 9 verbatim kaynak).
- 3 cerrahi `sed` düzeltmesini uygular.
- Satır sayısını raporlar (~3500 satır beklenir).

> **Not:** `set -euo pipefail` ile çalışır; herhangi bir adımda hata
> olursa durur ve hiçbir çıktı üretmez.

## 4. Uygulama (Apply)

Konsolide dosya `idempotent` olacak şekilde yazıldı (`CREATE TABLE IF NOT
EXISTS`, `CREATE OR REPLACE`, `DROP POLICY IF EXISTS` vb.), bu yüzden
güvenle çalıştırılabilir.

1. Supabase Dashboard → **SQL Editor**.
2. `20260804000002_fill_app_contract_gaps.sql` dosyasının **tamamını**
   yapıştır.
3. **Run**.
4. Başarılı çalıştıktan sonra, son bölümdeki `RAISE NOTICE` mesajlarını
   gör: `Konsolide uygulama kontrati düzeltmesi tamamlandi.`

## 5. Doğrulama (Verify)

`plans/sql_migrations/VERIFY_fill_app_contract_gaps.sql` dosyasını SQL
Editor'de çalıştır. Bu sorgu, 7 RPC'nin `public` şemasında varlığını,
tabloların/views'ların varlığını ve `cancel_order`'un artık `detail`
kolonuna yazdığını kontrol eder ve her satır için `OK` / `EKSIK` döner.

Alternatif olarak, kök teşhis raporu `CIZREAPP_TESHIS.sql`'i tekrar
çalıştırıp tüm eksikliklerin giderildiğini görebilirsin.

## 6. Bilinçli Olarak Hariç Tutulanlar

Bu konsolide dosya **sadece** teşhis raporundaki eksiklikleri doldurur.
Şu kapsamlı sertleştirmeler **bilinçli olarak hariç** tutuldu (kaynak
`20260803000006_secure_profiles_privileges_and_pii.sql`'in invasive
parçaları):

- `profiles` tablosundan `authenticated` SELECT'in geri alınması (REVOKE)
- Guard trigger'ı
- Admin profil RPC'leri
- `handle_new_user` tetikleyici fonksiyonunun yeniden yazımı

Bunlar, `profiles`'ı do��rudan okuyan diğer uygulama akışlarını
bozmamak için ayrı bir migration olarak değerlendirilmelidir.

## 7. Bilinen Yan Etkiler / Risk

- **Storage bucket'lar:** Teşhis raporu "eksik tablo" olarak listelenen
  `avatars`, `covers`, `deals`, `public`, `task_images`, `task_screenshots`
  aslında **storage bucket**'tır; bu dosya tablo oluşturmaz. Storage
  bucket'ları Supabase Dashboard → Storage üzerinden yönetilir.
- **`order_number_seq`:** `commit_*_order` RPC'leri `nextval` kullandığ��
  için, BOLUM 0'da `CREATE SEQUENCE IF NOT EXISTS public.order_number_seq`
  ile guarantee edilir.
- **Şema değişimi:** `private` → `public` taşıma yalnızca fonksiyon
  tanımlarını etkiler; bu fonksiyonların eriştiği `private.*` tabloları
  (örn. `private.server_checkout_sessions`) yerinde kalır, fonksiyonlar
  `SECURITY DEFINER` oldukları için içten erişmeye devam eder.
