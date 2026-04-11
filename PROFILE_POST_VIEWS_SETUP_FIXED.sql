-- ================================================
-- PROFILE & POST VIEWS TRACKING SYSTEM - FIXED
-- ================================================
-- Önceki fonksiyonları kaldır ve düzeltilmiş versiyonları yükle

-- ================================================
-- DROP OLD FUNCTIONS
-- ================================================

DROP FUNCTION IF EXISTS track_profile_view(UUID, UUID) CASCADE;
DROP FUNCTION IF EXISTS track_post_view(UUID, UUID) CASCADE;

-- ================================================
-- CREATE CORRECTED FUNCTIONS
-- ================================================

-- Profil ziyareti kaydet (günde 1 kez)
-- DÜZELTME: viewer_id parametresiz, otomatik auth.uid() kullan
CREATE OR REPLACE FUNCTION track_profile_view(
  p_profile_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_viewer_id UUID := auth.uid();
  v_view_date DATE := CURRENT_DATE;
BEGIN
  -- Sadece giriş yapmış kullanıcılar için kaydet
  IF v_viewer_id IS NULL THEN
    RETURN;
  END IF;
  
  -- Kendi profilini ziyaret ediyorsa kaydetme
  IF v_viewer_id = p_profile_id THEN
    RETURN;
  END IF;

  INSERT INTO profile_views (profile_id, viewer_id, viewed_at, view_date)
  VALUES (p_profile_id, v_viewer_id, NOW(), v_view_date)
  ON CONFLICT (profile_id, viewer_id, view_date)
  WHERE viewer_id IS NOT NULL
  DO NOTHING;
END;
$$;

-- Post görüntülemesini kaydet (günde 1 kez)
-- DÜZELTME: viewer_id parametresiz, otomatik auth.uid() kullan
CREATE OR REPLACE FUNCTION track_post_view(
  p_post_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_viewer_id UUID := auth.uid();
  v_view_date DATE := CURRENT_DATE;
BEGIN
  -- Sadece giriş yapmış kullanıcılar için kaydet
  IF v_viewer_id IS NULL THEN
    RETURN;
  END IF;

  INSERT INTO post_views (post_id, viewer_id, viewed_at, view_date)
  VALUES (p_post_id, v_viewer_id, NOW(), v_view_date)
  ON CONFLICT (post_id, viewer_id, view_date)
  WHERE viewer_id IS NOT NULL
  DO NOTHING;
END;
$$;
