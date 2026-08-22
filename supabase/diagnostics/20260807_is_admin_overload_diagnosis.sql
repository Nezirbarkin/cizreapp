-- ============================================================================
-- 20260807_is_admin_overload_diagnosis.sql
-- ----------------------------------------------------------------------------
-- AMAÇ: 'is_admin() is not unique' (42725) hatasının kök nedenini bulmak.
--       create_package_request HOTFIX'i uygularken ortaya çıkan
--       "function public.is_admin() is not unique" hatası, canlı DB'de
--       birden fazla is_admin() overload'ı olduğuna işaret eder.
--
-- Bu tanılama 4 kritik soruyu yanıtlar:
--   1) Canlıda kaç farklı is_admin() fonksiyonu var?
--   2) Her birinin argüman imzaları (parametre listesi) ne?
--   3) Her birinin gövdesi hangi role tablosuna bakıyor?
--   4) auth.uid() NULL iken argümansız is_admin() hangi varyant çalışıyor?
--
-- ÇALIŞTIRMA: Supabase Dashboard > SQL Editor'de BLOK 1-4'ü sırayla çalıştır.
-- GÜVENLİK: Sadece SELECT/pg_catalog sorguları. HİÇBİR DDL/DML yok.
-- ============================================================================


-- ============================================================================
-- BLOK 1 — TÜM is_admin() OVERLOAD'LARI (imza + tanım başlangıcı)
-- ============================================================================
-- 'amppsbofwawvbcvftncqd' canlı projesinde beklenen: birden fazla satır.
-- Her satır bir overload. Hangi satır kanonik? Hangisi duplicate?
-- ============================================================================
SELECT
  p.oid,
  n.nspname AS sema,
  p.proname AS fonksiyon,
  pg_get_function_identity_arguments(p.oid) AS imza,
  pg_get_function_result(p.oid) AS donus_tipi,
  p.prosecdef AS security_definer,
  CASE
    WHEN p.prosecdef THEN 'SECURITY DEFINER'
    ELSE 'SECURITY INVOKER'
  END AS guvenlik_modu,
  -- Tanımın ilk 200 karakteri (gövde içeriği)
  LEFT(p.prosrc::text, 200) AS govde_ilk_200,
  obj_description(p.oid, 'pg_proc') AS yorum
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname IN ('public', 'private')
  AND p.proname = 'is_admin'
ORDER BY n.nspname, p.oid;


-- ============================================================================
-- BLOK 2 — SADECE ARGÜMANSIZ is_admin() (kanonik kontrol)
-- ============================================================================
-- 'is_admin()' çağrısı argümansız. Birden fazla overload varsa 42725 alırız.
-- Eğer burada 1'den fazla satır çıkıyorsa → KÖK NEDEN.
-- ============================================================================
SELECT
  p.oid,
  pg_get_function_identity_arguments(p.oid) AS imza,
  -- Sadece parametre yoksa bu satır 'argümansız' varyanttır
  CASE
    WHEN proargnames IS NULL OR array_length(proargnames, 1) = 0
    THEN 'argümansız (sorun burada)'
    ELSE proargnames::text
  END AS parametreler,
  p.prosrc::text AS tam_govde
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname = 'is_admin'
  AND proargnames IS NULL OR array_length(proargnames, 1) = 0
ORDER BY p.oid;


-- ============================================================================
-- BLOK 3 — KANONIK HELPER private.current_user_is_admin() VAR MI?
-- ============================================================================
-- 20260803000006 migration'ı bu helper'ı tanımladı. Yoksa is_admin() delegasyonu
-- zinciri kırık. Buradan kontrol edeceğiz.
-- ============================================================================
SELECT
  p.oid,
  pg_get_function_identity_arguments(p.oid) AS imza,
  p.prosrc::text AS govde
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'private'
  AND p.proname = 'current_user_is_admin';


-- ============================================================================
-- BLOK 4 — BAĞIMLI FONKSİYONLAR
-- ============================================================================
-- Hangi RPC'ler is_admin() çağırıyor? Bunlar 42725'ten etkilenir.
-- ============================================================================
SELECT DISTINCT
  caller.n.nspname AS cagiran_sema,
  caller.p.proname AS cagiran_fonksiyon
FROM pg_proc caller
JOIN pg_namespace caller_n ON caller_n.oid = caller.pronamespace
-- prosrc içinde 'is_admin' geçen fonksiyonları bul
WHERE caller_n.nspname = 'public'
  AND caller.p.prosrc::text ILIKE '%is_admin%'
  AND caller.p.proname NOT IN ('is_admin')  -- kendisi hariç
ORDER BY cagiran_sema, cagiran_fonksiyon;


-- ============================================================================
-- BLOK 5 — HIZLI ÇÖZÜM TESTİ (DRY-RUN, hiçbir şey değiştirmez)
-- ============================================================================
-- Aşağıdaki fonksiyon çağrıları DOĞRUDAN argümansız is_admin()'i kullanır.
-- Eğer 42725 alıyorsan → SORUN KESİN.
-- ============================================================================

-- 5a) public.is_admin() argümansız çağrı
DO $$
BEGIN
  BEGIN
    PERFORM public.is_admin();
    RAISE NOTICE '5a) public.is_admin() → BAŞARILI (overload çakışması yok)';
  EXCEPTION WHEN ambiguous_function THEN
    RAISE NOTICE '5a) public.is_admin() → AMBIGUOUS: function not unique (42725)';
  WHEN OTHERS THEN
    RAISE NOTICE '5a) public.is_admin() → HATA: % %', SQLSTATE, SQLERRM;
  END;
END $$;

-- 5b) private.current_user_is_admin() çağrısı (kanonik helper)
DO $$
BEGIN
  BEGIN
    PERFORM private.current_user_is_admin();
    RAISE NOTICE '5b) private.current_user_is_admin() → BAŞARILI';
  EXCEPTION WHEN undefined_function THEN
    RAISE NOTICE '5b) private.current_user_is_admin() → TANIMLI DEĞİL: 20260803000006 migration uygulanmamış!';
  WHEN OTHERS THEN
    RAISE NOTICE '5b) private.current_user_is_admin() → HATA: % %', SQLSTATE, SQLERRM;
  END;
END $$;


-- ============================================================================
-- BLOK 6 — ÖNERİLEN DÜZELTME (BİLGİLENDİRME — ÇALIŞTIRMA!)
-- ----------------------------------------------------------------------------
-- Aşağıdaki kodu çalıştırmadan önce 5a ve 5b çıktılarını bana gönder.
-- Kök neden onaylanırsa ayrı bir "fix_is_admin_overload.sql" üreteceğim.
-- ============================================================================
SELECT
  'BLOK 1 çıktısı: kaç satır? (2+ ise çakışma var)' AS bilgi,
  (SELECT count(*) FROM pg_proc p
   JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'is_admin') AS public_is_admin_sayisi,
  (SELECT count(*) FROM pg_proc p
   JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'private' AND p.proname = 'is_admin') AS private_is_admin_sayisi,
  (SELECT count(*) FROM pg_proc p
   JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'private' AND p.proname = 'current_user_is_admin') AS private_current_user_is_admin_sayisi;
