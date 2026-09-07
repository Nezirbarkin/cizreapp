-- ============================================================================
-- YORUM POLİTİKALARI: gönderi sahibi kendi gönderisindeki yorumu silebilsin
-- ============================================================================
-- * post_comments DELETE yalnızca yorumu yazana açıktı; gönderi sahibi kendi
--   gönderisindeki bir yorumu (spam/hakaret) kaldıramıyordu.
-- * post_comments SELECT "true" idi: gizli hesabın gönderisi artık görünmese
--   bile o gönderiye yazılmış yorumlar okunabiliyordu. Artık yorum, ancak
--   gönderi görülebiliyorsa okunabilir (posts RLS'i üzerinden).

begin;

DROP POLICY IF EXISTS "Post comments are viewable by everyone" ON public.post_comments;
DROP POLICY IF EXISTS post_comments_select_visible ON public.post_comments;

CREATE POLICY post_comments_select_visible
ON public.post_comments
FOR SELECT
USING (
  post_id IS NULL
  OR EXISTS (SELECT 1 FROM public.posts p WHERE p.id = post_comments.post_id)
);

DROP POLICY IF EXISTS post_comments_delete_own ON public.post_comments;
DROP POLICY IF EXISTS post_comments_delete_allowed ON public.post_comments;

CREATE POLICY post_comments_delete_allowed
ON public.post_comments
FOR DELETE
USING (
  user_id = (SELECT auth.uid())
  OR EXISTS (
    SELECT 1 FROM public.posts p
    WHERE p.id = post_comments.post_id
      AND p.user_id = (SELECT auth.uid())
  )
  OR public.auth_is_admin()
);

CREATE INDEX IF NOT EXISTS idx_post_comments_post_created
  ON public.post_comments(post_id, created_at DESC);

commit;
