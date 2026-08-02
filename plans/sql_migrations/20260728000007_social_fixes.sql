-- =====================================================
-- DOSYA: supabase/migrations/20260728000007_social_fixes.sql
-- AMAÇ: Posts RLS + realtime performance
-- TARİH: 2026-07-28
-- UYGULAMA: Supabase Dashboard > SQL Editor
-- =====================================================

-- 1. Posts RLS
DROP POLICY IF EXISTS "Users can view active posts" ON posts;
CREATE POLICY "Users can view active posts" ON posts
  FOR SELECT TO authenticated, anon
  USING (is_active = TRUE);

DROP POLICY IF EXISTS "Users can insert own posts" ON posts;
CREATE POLICY "Users can insert own posts" ON posts
  FOR INSERT TO authenticated
  WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS "Users can update own posts" ON posts;
CREATE POLICY "Users can update own posts" ON posts
  FOR UPDATE TO authenticated
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS "Admins can manage all posts" ON posts;
CREATE POLICY "Admins can manage all posts" ON posts
  FOR ALL TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM profiles
      WHERE id = auth.uid() AND role = 'admin'
    )
  );

-- 2. Post views counter trigger
CREATE OR REPLACE FUNCTION increment_post_view(p_post_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE posts
  SET views_count = COALESCE(views_count, 0) + 1
  WHERE id = p_post_id;
END;
$$;

REVOKE ALL ON FUNCTION increment_post_view(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION increment_post_view(UUID) TO authenticated, anon;

-- 3. Post likes unique constraint
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'post_likes_post_user_unique'
  ) THEN
    ALTER TABLE post_likes ADD CONSTRAINT post_likes_post_user_unique UNIQUE (post_id, user_id);
  END IF;
END $$;

-- 4. Post likes count trigger
CREATE OR REPLACE FUNCTION update_post_likes_count()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    UPDATE posts SET likes_count = COALESCE(likes_count, 0) + 1 WHERE id = NEW.post_id;
  ELSIF TG_OP = 'DELETE' THEN
    UPDATE posts SET likes_count = GREATEST(COALESCE(likes_count, 0) - 1, 0) WHERE id = OLD.post_id;
  END IF;
  RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS trg_post_likes_count ON post_likes;
CREATE TRIGGER trg_post_likes_count
  AFTER INSERT OR DELETE ON post_likes
  FOR EACH ROW
  EXECUTE FUNCTION update_post_likes_count();

-- 5. Story expire index (stories tablosunda is_active yok, expires_at var)
CREATE INDEX IF NOT EXISTS idx_stories_expire_at
  ON stories (expires_at);

-- 6. Comment mentions index
CREATE INDEX IF NOT EXISTS idx_comment_mentions_user
  ON comment_mentions (mentioned_user_id);

-- 7. Posts indexes (performance)
CREATE INDEX IF NOT EXISTS idx_posts_user_created
  ON posts (user_id, created_at DESC) WHERE is_active = TRUE;

CREATE INDEX IF NOT EXISTS idx_posts_created
  ON posts (created_at DESC) WHERE is_active = TRUE;

-- 8. Test query
-- SELECT increment_post_view('00000000-0000-0000-0000-000000000000'::UUID);
