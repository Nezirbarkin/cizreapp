-- post_views tablosunda RLS'i etkinleştir
-- Linter hatası: "Table public.post_views has RLS policies but RLS is not enabled on the table"

-- RLS'i etkinleştir
ALTER TABLE public.post_views ENABLE ROW LEVEL SECURITY;

-- Mevcut policy'leri kontrol et
-- 1. "Anyone can insert post views" - Post görüntüleme kayıtları oluşturma
-- 2. "Post owners can view their post views" - Post sahibi kendi post'unun görüntülenmelerini görebilir
-- 3. "Users can view their own viewing history" - Kullanıcı kendi görüntüleme geçmişini görebilir

-- Policy'ler zaten mevcut, sadece RLS'i aktifleştirmemiz yeterliydi
-- Ancak emin olmak için policy'leri de kontrol edelim:

-- 1. INSERT policy - Herkes post görüntüleme kaydedebilir
DO $$ 
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies 
        WHERE schemaname = 'public' 
        AND tablename = 'post_views' 
        AND policyname = 'Anyone can insert post views'
    ) THEN
        CREATE POLICY "Anyone can insert post views"
        ON public.post_views
        FOR INSERT
        TO authenticated
        WITH CHECK (true);
    END IF;
END $$;

-- 2. SELECT policy - Post sahipleri kendi postlarının görüntülenmelerini görebilir
DO $$ 
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies 
        WHERE schemaname = 'public' 
        AND tablename = 'post_views' 
        AND policyname = 'Post owners can view their post views'
    ) THEN
        CREATE POLICY "Post owners can view their post views"
        ON public.post_views
        FOR SELECT
        TO authenticated
        USING (
            EXISTS (
                SELECT 1 FROM posts 
                WHERE posts.id = post_views.post_id 
                AND posts.user_id = auth.uid()
            )
        );
    END IF;
END $$;

-- 3. SELECT policy - Kullanıcılar kendi görüntüleme geçmişlerini görebilir
DO $$ 
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies 
        WHERE schemaname = 'public' 
        AND tablename = 'post_views' 
        AND policyname = 'Users can view their own viewing history'
    ) THEN
        CREATE POLICY "Users can view their own viewing history"
        ON public.post_views
        FOR SELECT
        TO authenticated
        USING (viewer_id = auth.uid());
    END IF;
END $$;

-- Profil görüntülemeleri için de aynı kontrolü yapalım
ALTER TABLE public.profile_views ENABLE ROW LEVEL SECURITY;

-- Profile views policy'leri
DO $$ 
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies 
        WHERE schemaname = 'public' 
        AND tablename = 'profile_views' 
        AND policyname = 'Anyone can insert profile views'
    ) THEN
        CREATE POLICY "Anyone can insert profile views"
        ON public.profile_views
        FOR INSERT
        TO authenticated
        WITH CHECK (true);
    END IF;
END $$;

DO $$ 
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies 
        WHERE schemaname = 'public' 
        AND tablename = 'profile_views' 
        AND policyname = 'Profile owners can view their profile views'
    ) THEN
        CREATE POLICY "Profile owners can view their profile views"
        ON public.profile_views
        FOR SELECT
        TO authenticated
        USING (profile_id = auth.uid());
    END IF;
END $$;

DO $$ 
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies 
        WHERE schemaname = 'public' 
        AND tablename = 'profile_views' 
        AND policyname = 'Users can view their own viewing history'
    ) THEN
        CREATE POLICY "Users can view their own viewing history"
        ON public.profile_views
        FOR SELECT
        TO authenticated
        USING (viewer_id = auth.uid());
    END IF;
END $$;
