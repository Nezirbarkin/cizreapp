-- ================================================
-- PROFILE & POST VIEWS TRACKING SYSTEM
-- ================================================
-- Bu sistem profil ziyaretlerini ve post görüntülemelerini takip eder
-- Aylık istatistikler için optimize edilmiştir

-- ================================================
-- 1. PROFILE VIEWS TABLE (Profil Ziyaretleri)
-- ================================================

CREATE TABLE IF NOT EXISTS profile_views (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  profile_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  viewer_id UUID REFERENCES profiles(id) ON DELETE CASCADE, -- NULL ise anonim ziyaret
  viewed_at TIMESTAMPTZ DEFAULT NOW(),
  view_date DATE -- Trigger ile doldurulacak
);

-- Indexes for performance
CREATE INDEX IF NOT EXISTS idx_profile_views_profile_id ON profile_views(profile_id);
CREATE INDEX IF NOT EXISTS idx_profile_views_viewer_id ON profile_views(viewer_id);
CREATE INDEX IF NOT EXISTS idx_profile_views_viewed_at ON profile_views(viewed_at);
CREATE INDEX IF NOT EXISTS idx_profile_views_view_date ON profile_views(view_date);

-- Unique constraint for daily tracking (günde 1 kez sayma)
CREATE UNIQUE INDEX IF NOT EXISTS idx_profile_views_unique_daily 
ON profile_views(profile_id, viewer_id, view_date)
WHERE viewer_id IS NOT NULL;

COMMENT ON TABLE profile_views IS 'Profil ziyaretlerini takip eder. Her kullanıcı günde 1 kez sayılır.';

-- ================================================
-- 2. POST VIEWS TABLE (Post Görüntülemeleri)
-- ================================================

CREATE TABLE IF NOT EXISTS post_views (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  post_id UUID NOT NULL REFERENCES posts(id) ON DELETE CASCADE,
  viewer_id UUID REFERENCES profiles(id) ON DELETE CASCADE, -- NULL ise anonim görüntüleme
  viewed_at TIMESTAMPTZ DEFAULT NOW(),
  view_date DATE -- Trigger ile doldurulacak
);

-- Indexes for performance
CREATE INDEX IF NOT EXISTS idx_post_views_post_id ON post_views(post_id);
CREATE INDEX IF NOT EXISTS idx_post_views_viewer_id ON post_views(viewer_id);
CREATE INDEX IF NOT EXISTS idx_post_views_viewed_at ON post_views(viewed_at);
CREATE INDEX IF NOT EXISTS idx_post_views_view_date ON post_views(view_date);

-- Unique constraint for daily tracking (günde 1 kez sayma)
CREATE UNIQUE INDEX IF NOT EXISTS idx_post_views_unique_daily 
ON post_views(post_id, viewer_id, view_date)
WHERE viewer_id IS NOT NULL;

COMMENT ON TABLE post_views IS 'Post görüntülemelerini takip eder. Her kullanıcı günde 1 kez sayılır.';

-- ================================================
-- 3. TRIGGERS - view_date otomatik doldurma
-- ================================================

-- Profile views için trigger function
CREATE OR REPLACE FUNCTION set_profile_view_date()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.view_date := DATE(NEW.viewed_at);
  RETURN NEW;
END;
$$;

-- Post views için trigger function
CREATE OR REPLACE FUNCTION set_post_view_date()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.view_date := DATE(NEW.viewed_at);
  RETURN NEW;
END;
$$;

-- Triggers
DROP TRIGGER IF EXISTS set_profile_view_date_trigger ON profile_views;
CREATE TRIGGER set_profile_view_date_trigger
  BEFORE INSERT ON profile_views
  FOR EACH ROW
  EXECUTE FUNCTION set_profile_view_date();

DROP TRIGGER IF EXISTS set_post_view_date_trigger ON post_views;
CREATE TRIGGER set_post_view_date_trigger
  BEFORE INSERT ON post_views
  FOR EACH ROW
  EXECUTE FUNCTION set_post_view_date();

-- ================================================
-- 4. UPSERT FUNCTIONS (Teke düşüm sağlamak için)
-- ================================================

-- Profil ziyareti kaydet (günde 1 kez)
CREATE OR REPLACE FUNCTION track_profile_view(
  p_profile_id UUID,
  p_viewer_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_view_date DATE := CURRENT_DATE;
BEGIN
  INSERT INTO profile_views (profile_id, viewer_id, viewed_at, view_date)
  VALUES (p_profile_id, p_viewer_id, NOW(), v_view_date)
  ON CONFLICT (profile_id, viewer_id, view_date)
  WHERE viewer_id IS NOT NULL
  DO NOTHING;
END;
$$;

-- Post görüntülemesini kaydet (günde 1 kez)
CREATE OR REPLACE FUNCTION track_post_view(
  p_post_id UUID,
  p_viewer_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_view_date DATE := CURRENT_DATE;
BEGIN
  INSERT INTO post_views (post_id, viewer_id, viewed_at, view_date)
  VALUES (p_post_id, p_viewer_id, NOW(), v_view_date)
  ON CONFLICT (post_id, viewer_id, view_date)
  WHERE viewer_id IS NOT NULL
  DO NOTHING;
END;
$$;

-- ================================================
-- 5. ROW LEVEL SECURITY (RLS) POLICIES
-- ================================================

-- Enable RLS
ALTER TABLE profile_views ENABLE ROW LEVEL SECURITY;
ALTER TABLE post_views ENABLE ROW LEVEL SECURITY;

-- Profile Views Policies
DROP POLICY IF EXISTS "Anyone can insert profile views" ON profile_views;
CREATE POLICY "Anyone can insert profile views"
  ON profile_views
  FOR INSERT
  TO authenticated
  WITH CHECK (true);

DROP POLICY IF EXISTS "Users can view their profile views" ON profile_views;
CREATE POLICY "Users can view their profile views"
  ON profile_views
  FOR SELECT
  TO authenticated
  USING (profile_id = auth.uid());

DROP POLICY IF EXISTS "Users can view their own viewing history" ON profile_views;
CREATE POLICY "Users can view their own viewing history"
  ON profile_views
  FOR SELECT
  TO authenticated
  USING (viewer_id = auth.uid());

-- Post Views Policies
DROP POLICY IF EXISTS "Anyone can insert post views" ON post_views;
CREATE POLICY "Anyone can insert post views"
  ON post_views
  FOR INSERT
  TO authenticated
  WITH CHECK (true);

DROP POLICY IF EXISTS "Post owners can view their post views" ON post_views;
CREATE POLICY "Post owners can view their post views"
  ON post_views
  FOR SELECT
  TO authenticated
  USING (
    post_id IN (
      SELECT id FROM posts WHERE user_id = auth.uid()
    )
  );

DROP POLICY IF EXISTS "Users can view their own viewing history" ON post_views;
CREATE POLICY "Users can view their own viewing history"
  ON post_views
  FOR SELECT
  TO authenticated
  USING (viewer_id = auth.uid());

-- ================================================
-- 6. HELPER FUNCTIONS (Yardımcı Fonksiyonlar)
-- ================================================

-- Get monthly profile view stats
CREATE OR REPLACE FUNCTION get_profile_monthly_stats(
  p_profile_id UUID,
  p_months INT DEFAULT 6
)
RETURNS TABLE (
  month TEXT,
  view_count BIGINT,
  unique_viewers BIGINT
) 
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  SELECT 
    TO_CHAR(DATE_TRUNC('month', viewed_at), 'YYYY-MM') as month,
    COUNT(*)::BIGINT as view_count,
    COUNT(DISTINCT viewer_id)::BIGINT as unique_viewers
  FROM profile_views
  WHERE profile_id = p_profile_id
    AND viewed_at >= NOW() - INTERVAL '1 month' * p_months
  GROUP BY DATE_TRUNC('month', viewed_at)
  ORDER BY month DESC;
END;
$$;

-- Get current month profile views
CREATE OR REPLACE FUNCTION get_profile_current_month_views(
  p_profile_id UUID
)
RETURNS TABLE (
  total_views BIGINT,
  unique_viewers BIGINT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  SELECT 
    COUNT(*)::BIGINT as total_views,
    COUNT(DISTINCT viewer_id)::BIGINT as unique_viewers
  FROM profile_views
  WHERE profile_id = p_profile_id
    AND DATE_TRUNC('month', viewed_at) = DATE_TRUNC('month', NOW());
END;
$$;

-- Get monthly post view stats
CREATE OR REPLACE FUNCTION get_post_monthly_stats(
  p_user_id UUID,
  p_months INT DEFAULT 6
)
RETURNS TABLE (
  month TEXT,
  view_count BIGINT,
  unique_viewers BIGINT,
  post_count BIGINT
) 
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  SELECT 
    TO_CHAR(DATE_TRUNC('month', pv.viewed_at), 'YYYY-MM') as month,
    COUNT(*)::BIGINT as view_count,
    COUNT(DISTINCT pv.viewer_id)::BIGINT as unique_viewers,
    COUNT(DISTINCT pv.post_id)::BIGINT as post_count
  FROM post_views pv
  INNER JOIN posts p ON p.id = pv.post_id
  WHERE p.user_id = p_user_id
    AND pv.viewed_at >= NOW() - INTERVAL '1 month' * p_months
  GROUP BY DATE_TRUNC('month', pv.viewed_at)
  ORDER BY month DESC;
END;
$$;

-- Get current month post views for user
CREATE OR REPLACE FUNCTION get_user_current_month_post_views(
  p_user_id UUID
)
RETURNS TABLE (
  total_views BIGINT,
  unique_viewers BIGINT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  SELECT 
    COUNT(*)::BIGINT as total_views,
    COUNT(DISTINCT pv.viewer_id)::BIGINT as unique_viewers
  FROM post_views pv
  INNER JOIN posts p ON p.id = pv.post_id
  WHERE p.user_id = p_user_id
    AND DATE_TRUNC('month', pv.viewed_at) = DATE_TRUNC('month', NOW());
END;
$$;

-- ================================================
-- KURULUM TAMAMLANDI!
-- ================================================

-- Kullanım:
-- 1. Bu SQL'i Supabase SQL Editor'da çalıştırın
-- 2. ProfileViewService ve PostViewService'i oluşturun
-- 3. UserProfileScreen'de visit kaydedın
-- 4. PostDetailScreen'de view kaydedın
-- 5. İstatistikleri get_profile_monthly_stats() ve get_post_monthly_stats() ile çekin
