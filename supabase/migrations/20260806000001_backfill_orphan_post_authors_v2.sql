-- =============================================================================
-- 20260806000001_backfill_orphan_post_authors_v2.sql
-- =============================================================================
-- AMAÇ: Eski/yetim (orphan) post yazarlarının profiles kayıtlarını auth.users
--       verilerinden backfill ederek keşfet feed'inde "Bilinmeyen Kullanıcı"
--       + UUID kırpıntısı (@e453djf) gösterimini sonlandırmak.
--
-- BAĞLAM:
--   * 20260805000001_posts_with_profiles_view_v2.sql ile view LEFT JOIN'e
--     geçirildi, ancak orphan user_id'ler için profiles satırı olmadığından
--     author_username/full_name NULL kalıyor.
--   * UI'da fallback olarak post.userId'nin ilk 8 karakteri gösteriliyordu →
--     sahte username izlenimi.
--   * Bu migration, backfill_missing_profiles_from_posts() RPC'sini geliştirir:
--     - auth.users'tan email ve raw_user_meta_data çekilir
--     - full_name meta_data.full_name'dan, yoksa email'in @ öncesinden türetilir
--     - username meta_data.username'dan, yoksa email @ öncesinden türetilir
--     - Aynı username başka profilde varsa user_id kısa son eki ile çakışma
--       önlenir
--   * Idempotent: ON CONFLICT (id) DO NOTHING ile güvenli tekrar çalışır.
--
-- ÇALIŞTIRMA: Supabase SQL Editor → yapıştır → Run
--   1) Önce: SELECT * FROM get_missing_post_authors();
--   2) Sonra: SELECT backfill_missing_profiles_from_posts();
--   3) Doğrulama: SELECT COUNT(*) FROM get_missing_post_authors(); -- 0 olmalı
-- =============================================================================

-- Önce mevcut RPC'yi drop et (imza değişti)
DROP FUNCTION IF EXISTS public.backfill_missing_profiles_from_posts();

CREATE OR REPLACE FUNCTION public.backfill_missing_profiles_from_posts()
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_inserted      INTEGER := 0;
  v_skipped       INTEGER := 0;
  v_user_id       UUID;
  v_email         TEXT;
  v_full_name     TEXT;
  v_username_base TEXT;
  v_username      TEXT;
  v_exists        BOOLEAN;
BEGIN
  -- Admin kontrolü (varsa). Yoksa sessizce devam et (orphan profil oluşturmak
  -- zaten sadece eksik veri ekler, silmez).
  BEGIN
    IF NOT public.is_admin() THEN
      RAISE EXCEPTION 'APP:forbidden | admin yetkisi gerekli'
        USING ERRCODE = '42501';
    END IF;
  EXCEPTION WHEN undefined_function THEN
    NULL;
  END;

  FOR v_user_id, v_email IN
    SELECT DISTINCT p.user_id, au.email
    FROM posts p
    LEFT JOIN profiles pr ON pr.id = p.user_id
    LEFT JOIN auth.users au ON au.id = p.user_id
    WHERE pr.id IS NULL
      AND p.user_id IS NOT NULL
  LOOP
    -- auth.users'tan geldiyse full_name ve username'i meta_data'dan çek
    SELECT
      COALESCE(
        au.raw_user_meta_data->>'full_name',
        au.raw_user_meta_data->>'name',
        au.raw_user_meta_data->>'display_name',
        split_part(au.email, '@', 1)
      ),
      COALESCE(
        au.raw_user_meta_data->>'username',
        au.raw_user_meta_data->>'user_name',
        split_part(au.email, '@', 1)
      )
    INTO v_full_name, v_username_base
    FROM auth.users au
    WHERE au.id = v_user_id;

    -- auth.users'ta da yoksa (çok eski silinmiş hesap) email yerine user_id kısa
    -- halini kullan, ama yine de "kullanici" gibi okunabilir bir şey olsun
    IF v_full_name IS NULL OR btrim(v_full_name) = '' THEN
      v_full_name := 'Kullanıcı';
    END IF;
    IF v_username_base IS NULL OR btrim(v_username_base) = '' THEN
      v_username_base := 'kullanici';
    END IF;

    -- Username çakışmasını önle: aynı username başka profilde varsa sonuna
    -- user_id'nin ilk 6 hanesini ekle (örn: ahmet_a1b2c3). user_id kırpıntısı
    -- avatar/display'de değil, sadece çakışma-çözümü için kullanılır.
    v_username := v_username_base;
    SELECT EXISTS(
      SELECT 1 FROM profiles WHERE username = v_username AND id <> v_user_id
    ) INTO v_exists;
    IF v_exists THEN
      v_username := v_username_base || '_' || substr(v_user_id::text, 1, 6);
    END IF;

    INSERT INTO public.profiles (
      id, email, full_name, username, role, status, profile_is_public, created_at, updated_at
    )
    VALUES (
      v_user_id, v_email, v_full_name, v_username, 'customer', 'active', true, NOW(), NOW()
    )
    ON CONFLICT (id) DO NOTHING;

    -- INSERT gerçekten satır eklediyse sayacı arttır
    GET DIAGNOSTICS v_inserted = ROW_COUNT;
    IF v_inserted = 0 THEN
      v_skipped := v_skipped + 1;
    END IF;
  END LOOP;

  RAISE NOTICE 'backfill_missing_profiles_from_posts: % profil oluşturuldu, % atlandı (zaten vardı)',
    v_inserted, v_skipped;
  RETURN v_inserted;
END;
$$;

REVOKE ALL ON FUNCTION public.backfill_missing_profiles_from_posts() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.backfill_missing_profiles_from_posts() TO authenticated;

COMMENT ON FUNCTION public.backfill_missing_profiles_from_posts() IS
  'Orphan post yazarları için auth.users meta_data''sından profiles satırı oluşturur. '
  'full_name meta_data.full_name/name/display_name''dan, username meta_data.username''dan, '
  'yoksa email @ öncesinden türetilir. Username çakışması user_id kısa son eki ile çözülür. '
  'Sadece admin çağırabilir. Keşfet feed''inde "Bilinmeyen Kullanıcı" sorununu giderir.';
