-- =====================================================
-- STORIES TABLOSU İÇİN MİSAFİR KULLANICI ERİŞİMİ
-- Misafir kullanıcıların da hikayeleri görebilmesi için
-- =====================================================

-- Önce mevcut politikaları kontrol et
SELECT schemaname, tablename, policyname, permissive, roles, cmd, qual, with_check
FROM pg_policies
WHERE tablename = 'stories';

-- stories tablosu için SELECT politikasını tüm kullanıcılara (authenticated + anon) aç
DROP POLICY IF EXISTS "stories_select_policy" ON stories;
DROP POLICY IF EXISTS "stories_select_authenticated" ON stories;
DROP POLICY IF EXISTS "stories_select_public" ON stories;

-- Yeni SELECT politikası - tüm aktif hikayeleri herkes görebilir
CREATE POLICY "stories_select_public" ON stories
  FOR SELECT TO anon, authenticated
  USING (expires_at > NOW());

-- Gerekirse diğer politikaları da kontrol et
-- INSERT sadece auth kullanıcılar
DROP POLICY IF EXISTS "stories_insert_policy" ON stories;
CREATE POLICY "stories_insert_policy" ON stories
  FOR INSERT TO authenticated
  WITH CHECK (auth.uid() = user_id);

-- UPDATE sadece kendi hikayesi
DROP POLICY IF EXISTS "stories_update_policy" ON stories;
CREATE POLICY "stories_update_policy" ON stories
  FOR UPDATE TO authenticated
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

-- DELETE sadece kendi hikayesi
DROP POLICY IF EXISTS "stories_delete_policy" ON stories;
CREATE POLICY "stories_delete_policy" ON stories
  FOR DELETE TO authenticated
  USING (auth.uid() = user_id);

-- Profil bilgilerini JOIN ile çekebilmek için profiles tablosunu da anon kullanıcıya aç
DROP POLICY IF EXISTS "profiles_select_public_stories" ON profiles;
CREATE POLICY "profiles_select_public_stories" ON profiles
  FOR SELECT TO anon, authenticated
  USING (true);

-- Politikaları doğrula
SELECT schemaname, tablename, policyname, permissive, roles, cmd
FROM pg_policies
WHERE tablename IN ('stories', 'profiles')
ORDER BY tablename, policyname;
