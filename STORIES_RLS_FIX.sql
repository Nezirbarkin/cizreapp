-- Stories tablosu için RLS Policy Fix
-- Kullanıcıların kendi hikayelerini oluşturabilmesi için

-- 1. Mevcut policy'leri temizle (varsa)
DROP POLICY IF EXISTS "stories_insert_policy" ON stories;
DROP POLICY IF EXISTS "stories_select_policy" ON stories;
DROP POLICY IF EXISTS "stories_update_policy" ON stories;
DROP POLICY IF EXISTS "stories_delete_policy" ON stories;

-- 2. ENABLE RLS (zaten enable olmalı, emin olmak için)
ALTER TABLE stories ENABLE ROW LEVEL SECURITY;

-- 3. SELECT Policy - Herkes aktif hikayeleri görebilir
CREATE POLICY "stories_select_policy" ON stories
    FOR SELECT
    USING (expires_at > NOW());

-- 4. INSERT Policy - Kullanıcılar sadece kendi hikayelerini oluşturabilir
CREATE POLICY "stories_insert_policy" ON stories
    FOR INSERT
    WITH CHECK (auth.uid() = user_id);

-- 5. UPDATE Policy - Kullanıcılar sadece kendi hikayelerini güncelleyebilir
CREATE POLICY "stories_update_policy" ON stories
    FOR UPDATE
    USING (auth.uid() = user_id)
    WITH CHECK (auth.uid() = user_id);

-- 6. DELETE Policy - Kullanıcılar sadece kendi hikayelerini silebilir
CREATE POLICY "stories_delete_policy" ON stories
    FOR DELETE
    USING (auth.uid() = user_id);

-- 7. story_views tablosu için RLS policies
DROP POLICY IF EXISTS "story_views_insert_policy" ON story_views;
DROP POLICY IF EXISTS "story_views_select_policy" ON story_views;

ALTER TABLE story_views ENABLE ROW LEVEL SECURITY;

-- Herkes görüntüleme kaydı oluşturabilir
CREATE POLICY "story_views_insert_policy" ON story_views
    FOR INSERT
    WITH CHECK (auth.uid() IS NOT NULL);

-- Görüntüleyenler listesi için - story sahibi veya görüntüleyen kişi görebilir
CREATE POLICY "story_views_select_policy" ON story_views
    FOR SELECT
    USING (
        auth.uid() IN (
            SELECT user_id FROM stories WHERE stories.id = story_views.story_id
        )
        OR auth.uid() = story_views.user_id
    );

-- Verification
SELECT 
    schemaname, 
    tablename, 
    policyname, 
    cmd,
    qual,
    with_check
FROM pg_policies 
WHERE tablename IN ('stories', 'story_views')
ORDER BY tablename, policyname;
