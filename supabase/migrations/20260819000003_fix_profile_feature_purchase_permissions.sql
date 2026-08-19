-- =============================================================================
-- DÜZELTME: puanla satın alma hiç çalışmıyordu (permission denied)
-- =============================================================================
-- BULGU (2026-08-19, uçtan uca test sırasında):
--   select public.purchase_my_profile_feature_with_points(...) çağrısı
--   ŞU HATAYLA düşüyor:
--     ERROR: 42501: permission denied for table profile_feature_catalog
--     CONTEXT: PL/pgSQL function purchase_my_profile_feature_with_points line 30
--
--   Sebep: 20260818000006 bu fonksiyonu SECURITY DEFINER yapıp sahipliğini
--   reward_points_owner'a devretti. Gerekçe olarak "reward_points_apply_entry
--   yalnız reward_points_owner sahipli fonksiyonlarca çağrılabiliyor"
--   yazılmıştı — ancak bu doğru değil:
--     has_function_privilege('service_role', 'public.reward_points_apply_entry(...)', 'execute') = true
--     has_function_privilege('postgres',     ... ) = true
--   Yani devir hiç gerekli değildi. Devrin YAN ETKİSİ ise ölümcül:
--   reward_points_owner rolünün profile_feature_catalog ve
--   user_profile_features tablolarında HİÇBİR yetkisi yok
--     (has_table_privilege(...) = false, false, false)
--   ve her iki tabloda RLS açık. SECURITY DEFINER fonksiyon artık o rolün
--   kimliğiyle çalıştığı için katalog satırını okuyamıyor.
--
--   Sonuç: puanla satın alma özelliği 20260818000006'dan beri hiç çalışmadı.
--   Kimsenin puanı olmadığı için (user_point_accounts'ta tek hesap, 0 puan)
--   üretimde fark edilmemişti.
--
-- ÇÖZÜM: fonksiyonun sahipliği postgres'e geri alınır.
--   * postgres her iki tablonun da sahibi ve RLS "force" değil -> katalog
--     okuma / atama yazma sorunsuz çalışır.
--   * postgres reward_points_apply_entry'yi zaten çağırabiliyor -> puan
--     düşme yolu korunur.
--   * Fonksiyonun içindeki service_role guard'ı (request.jwt.claims ->> 'role'
--     kontrolü) ve yalnız service_role'e verilen EXECUTE grant'i AYNEN kalır;
--     yani dışarıya açılan yüzey genişlemez. Tek meşru çağıran hâlâ
--     purchase-profile-feature Edge Function'ı.
--
-- Alternatif olarak reward_points_owner'a bu iki tabloda GRANT + RLS policy
-- verilebilirdi; o yol rolün yetki alanını gereksiz yere genişlettiği için
-- tercih edilmedi (rol yalnız puan defterine erişmeli).
-- =============================================================================

begin;

alter function public.purchase_my_profile_feature_with_points(uuid, uuid, text, text)
  owner to postgres;

-- Yetki yüzeyi değişmesin: yalnız service_role çağırabilir.
revoke all on function public.purchase_my_profile_feature_with_points(uuid, uuid, text, text)
  from public, anon, authenticated;
grant execute on function public.purchase_my_profile_feature_with_points(uuid, uuid, text, text)
  to service_role;

commit;

-- =============================================================================
-- Kontrol:
--   select pg_get_userbyid(proowner) from pg_proc
--   where proname = 'purchase_my_profile_feature_with_points';
--   -- Beklenen: postgres
--
--   select has_function_privilege('authenticated',
--     'public.purchase_my_profile_feature_with_points(uuid,uuid,text,text)', 'execute');
--   -- Beklenen: false
-- =============================================================================
