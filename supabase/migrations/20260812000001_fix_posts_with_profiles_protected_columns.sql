-- ============================================================================
-- 20260812000001_fix_posts_with_profiles_protected_columns.sql
-- ----------------------------------------------------------------------------
-- AMAÇ: Feed açılışında "permission denied for table profiles" (42501) hatası.
--
-- KÖK NEDEN:
--   posts_with_profiles view'ı (v2, 20260805000001) security_invoker=true.
--   Bu yüzden view'ı sorgulayan anon/authenticated rolünün, view'ın dokunduğu
--   profiles sütunlarının HEPSİNDE sütun-bazlı SELECT yetkisi olmalı.
--   20260803000006_secure_profiles_privileges_and_pii.sql yalnızca 15 güvenli
--   sütuna GRANT verdi (id, username, full_name, avatar_url, cover_url, bio,
--   website, location, gender, profile_is_public, created_at, updated_at,
--   last_seen, status, is_ghost_mode). Ama view şunları DA seçiyordu:
--     pr.role      AS author_role      -- yetkisi YOK (güvenlik sütunu)
--     pr.is_admin   AS author_is_admin  -- yetkisi YOK (güvenlik sütunu)
--   → security_invoker bu sütunları okumaya çalışınca 42501 fırlıyordu.
--
-- ÖNCEKI DENEME YETERSİZDI:
--   20260806000001 yalnızca bir RLS *policy* ekledi (satır görünürlüğü için).
--   Ama policy, sütun yetkisi (GRANT) vermez. Sütun-bazlı yetki eksikliği
--   devam ettiği için hata çözülmedi.
--
-- COZUM:
--   View'ı, profiles'tan yalnızca yetkili (15) sütunları seçecek şekilde
--   yeniden oluştur. role/is_admin artık NULL::text / NULL::boolean olarak
--   gelir (tutumlu-kompozisyon: sütun şekli korunur, değer null). Dart tarafı
--   author_role=null → AuthorRole.unknown ile zarif başa çıkar (rozet göstermez).
--
-- GÜVENLİK NOTU:
--   role/is_admin bilinçli olarak gizleniyor (20260803000006 + test 005).
--   Bu migration o kararı bozmaz; tam tersine feed'i o güvenlik sözleşmesiyle
--   uyumlu hale getirir. "Staff rozeti" feed'de artık gösterilmez (zaten
--   hardened şemada hiç çalışmıyordu — view 42501 veriyordu).
-- ============================================================================

DROP VIEW IF EXISTS public.posts_with_profiles;

CREATE VIEW public.posts_with_profiles
WITH (security_invoker = true) AS
SELECT
  -- Posts tablosunun TÜM kolonları (şema değişikliklerine dayanıklı)
  p.*,

  -- Profiles: yalnızca GRANT verilmiş 15 güvenli sütun (20260803000006).
  -- Bu sütunların hiçbiri PII/role/enum hassasiyeti taşımaz.
  pr.username,
  pr.full_name,
  pr.avatar_url,
  pr.is_ghost_mode   AS author_is_ghost_mode,
  pr.profile_is_public AS author_profile_public,
  pr.status          AS author_status,

  -- profiles'ta is_verified sütunu yok: NULL (Dart tarafı false işler).
  NULL::BOOLEAN AS author_is_verified,

  -- role ve is_admin KASITLI NULL: sütun-bazlı SELECT yetkileri yok
  -- (güvenlik sütunları). Değer göndermek 42501'e yol açar. Dart tarafı
  -- author_role=null → AuthorRole.unknown ile başa çıkar.
  NULL::TEXT    AS author_role,
  NULL::BOOLEAN AS author_is_admin,

  -- Yardımcı boolean: profil kaydı var mı? (orphan post fallback)
  (pr.id IS NOT NULL) AS author_profile_exists
FROM posts p
LEFT JOIN profiles pr ON pr.id = p.user_id
WHERE p.is_active = true;

-- View yeniden oluşturulduğunda eski GRANT'lar düşer; sadece SELECT veriyoruz.
GRANT SELECT ON public.posts_with_profiles TO authenticated, anon;

COMMENT ON VIEW public.posts_with_profiles IS
  'Posts + profiles LEFT JOIN. security_invoker=true olduğu için viewer''ın '
  'profiles sütun-bazlı yetkilerine bağlıdır (20260803000006: 15 güvenli sütun). '
  '2026-08-12 fix: role/is_admin artık NULL olarak geliyor — bu sütunların GRANT''ı '
  'yok ve security_invoker 42501 fırlatıyordu. author_role=null → Dart AuthorRole.unknown.';

-- PostgREST şema cache'ini tazele ki yeni view tanımı hemen görünsün.
NOTIFY pgrst, 'reload schema';

-- -----------------------------------------------------------------------------
-- DOĞRULAMA — view'ın profiles'tan okuduğu sütunlar yalnızca yetkili olanlar.
-- -----------------------------------------------------------------------------
-- Bilgi amaçlı: view tanımında artık pr.role / pr.is_admin referansı olmamalı.
SELECT pg_get_viewdef('public.posts_with_profiles'::regclass, true) AS view_definition;
