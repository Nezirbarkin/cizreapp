-- =====================================================
-- DOSYA: supabase/migrations/20260728000012_news_fixes.sql
-- AMAÇ: News RLS + views tracking
-- TARİH: 2026-07-28
-- UYGULAMA: Supabase Dashboard > SQL Editor
-- =====================================================

-- 1. News RLS
DROP POLICY IF EXISTS "Anyone can view published news" ON news;
CREATE POLICY "Anyone can view published news" ON news
  FOR SELECT TO anon, authenticated
  USING (is_published = TRUE AND published_at <= NOW());

DROP POLICY IF EXISTS "Admins manage all news" ON news;
CREATE POLICY "Admins manage all news" ON news
  FOR ALL TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM profiles
      WHERE id = auth.uid() AND role = 'admin'
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM profiles
      WHERE id = auth.uid() AND role = 'admin'
    )
  );

-- 2. News comments RLS (is_deleted yok, is_hidden var)
DROP POLICY IF EXISTS "Anyone can view news comments" ON news_comments;
CREATE POLICY "Anyone can view news comments" ON news_comments
  FOR SELECT TO anon, authenticated
  USING (is_hidden = FALSE);

DROP POLICY IF EXISTS "Authenticated users can comment" ON news_comments;
CREATE POLICY "Authenticated users can comment" ON news_comments
  FOR INSERT TO authenticated
  WITH CHECK (user_id = auth.uid());

-- 3. News views tracking
CREATE TABLE IF NOT EXISTS news_views (
  news_id UUID NOT NULL REFERENCES news(id) ON DELETE CASCADE,
  user_id UUID REFERENCES auth.users(id),
  ip_address INET,
  viewed_at TIMESTAMPTZ DEFAULT NOW(),
  PRIMARY KEY (news_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_news_views_news ON news_views (news_id);

-- 4. News categories
CREATE TABLE IF NOT EXISTS news_categories (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL UNIQUE,
  slug TEXT NOT NULL UNIQUE,
  icon_url TEXT,
  sort_order INTEGER DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE news_categories ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Anyone can view news categories" ON news_categories;
CREATE POLICY "Anyone can view news categories" ON news_categories
  FOR SELECT TO anon, authenticated
  USING (TRUE);

-- 5. News indexes
CREATE INDEX IF NOT EXISTS idx_news_published
  ON news (published_at DESC) WHERE is_published = TRUE;
CREATE INDEX IF NOT EXISTS idx_news_category
  ON news (category_id, published_at DESC) WHERE is_published = TRUE;
