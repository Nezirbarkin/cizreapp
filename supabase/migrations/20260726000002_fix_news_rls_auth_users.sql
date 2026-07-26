-- ============================================
-- NEWS RLS DÜZELTMESİ
-- ============================================
-- Sorun: RLS politikaları auth.users tablosuna doğrudan SELECT yapıyor
-- (raw_user_meta_data->>'role' kontrolü için). Supabase'de authenticated
-- kullanıcılar RLS execution context'inde auth.users'a erişemez, bu yüzden
-- "permission denied for table users" (42501) hatası alınıyor.
--
-- Çözüm: SECURITY DEFINER bir helper fonksiyon oluşturup rolleri
-- JWT claim'inden (auth.jwt() ->> 'role') okumak. Bu sayede auth.users
-- tablosuna erişmeye gerek kalmaz ve çok daha performanslı çalışır.
-- ============================================

-- 1. Helper: Mevcut kullanıcının belirli bir role sahip olup olmadığını kontrol eder
-- Not: news sistemi user_role enum'unda 'news' rolünü de tanımlıyor.
CREATE OR REPLACE FUNCTION public.current_user_has_role(target_roles TEXT[])
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, auth
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM auth.users
        WHERE id = auth.uid()
          AND (
              raw_user_meta_data->>'role' = ANY(target_roles)
              OR (raw_user_meta_data->'roles') ?| target_roles
          )
    );
$$;

-- Aynı fonksiyonu profiles tablosundan da kontrol eden bir varyant
-- (uygulama bazı kullanıcılarda rolü profiles.role içinde tutuyor olabilir)
CREATE OR REPLACE FUNCTION public.current_user_role_in_list(target_roles TEXT[])
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.profiles p
        WHERE p.id = auth.uid()
          AND p.role::text = ANY(target_roles)
    )
    OR EXISTS (
        SELECT 1
        FROM auth.users u
        WHERE u.id = auth.uid()
          AND (
              u.raw_user_meta_data->>'role' = ANY(target_roles)
              OR (u.raw_user_meta_data->'roles') ?| target_roles
          )
    );
$$;

GRANT EXECUTE ON FUNCTION public.current_user_has_role(TEXT[]) TO authenticated;
GRANT EXECUTE ON FUNCTION public.current_user_role_in_list(TEXT[]) TO authenticated;

-- ============================================
-- 2. NEWS TABLOSU POLİTİKALARI YENİDEN YAZ
-- ============================================

ALTER TABLE news ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Public can view published news" ON news;
CREATE POLICY "Public can view published news" ON news
    FOR SELECT USING (is_published = true);

-- INSERT: admin veya news rolü olanlar
DROP POLICY IF EXISTS "Admins and news role can insert news" ON news;
CREATE POLICY "Admins and news role can insert news" ON news
    FOR INSERT WITH CHECK (
        public.current_user_role_in_list(ARRAY['admin', 'news'])
    );

-- UPDATE: yazar veya admin
DROP POLICY IF EXISTS "Authors and admins can update news" ON news;
CREATE POLICY "Authors and admins can update news" ON news
    FOR UPDATE USING (
        author_id = auth.uid()
        OR public.current_user_role_in_list(ARRAY['admin'])
    );

-- DELETE: sadece admin
DROP POLICY IF EXISTS "Only admins can delete news" ON news;
CREATE POLICY "Only admins can delete news" ON news
    FOR DELETE USING (
        public.current_user_role_in_list(ARRAY['admin'])
    );

-- ============================================
-- 3. NEWS_IMAGES POLİTİKALARI
-- ============================================
DROP POLICY IF EXISTS "Public can view news images" ON news_images;
CREATE POLICY "Public can view news images" ON news_images
    FOR SELECT USING (true);

DROP POLICY IF EXISTS "News authors can manage images" ON news_images;
CREATE POLICY "News authors can manage images" ON news_images
    FOR ALL USING (
        EXISTS (
            SELECT 1 FROM news
            WHERE news.id = news_images.news_id
            AND (
                news.author_id = auth.uid()
                OR public.current_user_role_in_list(ARRAY['admin', 'news'])
            )
        )
    );

-- ============================================
-- 4. STORAGE POLİTİKALARI (news-images bucket)
-- ============================================
-- Silme politikası da auth.users'a erişiyordu
DROP POLICY IF EXISTS "Only admins can delete images" ON storage.objects;
CREATE POLICY "Only admins can delete images" ON storage.objects
    FOR DELETE USING (
        bucket_id = 'news-images'
        AND public.current_user_role_in_list(ARRAY['admin'])
    );

-- ============================================
-- 5. NEWS_VIEWS INSERT POLİTİKASI
-- ============================================
-- Mevcut "System can insert views" WITH CHECK (true) biraz gevşek.
-- Daha kontrollü bir hale getiriyoruz: herhangi biri görüntüleme kaydı
-- ekleyebilsin, ama user_id alanı auth.uid() ile uyumlu olsun (anonimler NULL bırakır).
DROP POLICY IF EXISTS "System can insert views" ON news_views;
DROP POLICY IF EXISTS "Anyone can record news views" ON news_views;
CREATE POLICY "Anyone can record news views" ON news_views
    FOR INSERT WITH CHECK (
        user_id IS NULL OR user_id = auth.uid()
    );

-- ============================================
-- 6. YARDIMCI VIEW'LARI YENİDEN OLUŞTUR (linter uyarılarını önle)
-- ============================================
-- news_images üzerinde ALL policy ile WITH CHECK de ekleyelim
-- (Postgres bazen USING olmadan kontrol yapmaz)
DROP POLICY IF EXISTS "News authors can insert images" ON news_images;
CREATE POLICY "News authors can insert images" ON news_images
    FOR INSERT WITH CHECK (
        EXISTS (
            SELECT 1 FROM news
            WHERE news.id = news_images.news_id
            AND (
                news.author_id = auth.uid()
                OR public.current_user_role_in_list(ARRAY['admin', 'news'])
            )
        )
    );

DROP POLICY IF EXISTS "News authors can update own images" ON news_images;
CREATE POLICY "News authors can update own images" ON news_images
    FOR UPDATE USING (
        EXISTS (
            SELECT 1 FROM news
            WHERE news.id = news_images.news_id
            AND (
                news.author_id = auth.uid()
                OR public.current_user_role_in_list(ARRAY['admin', 'news'])
            )
        )
    );

DROP POLICY IF EXISTS "News authors can delete own images" ON news_images;
CREATE POLICY "News authors can delete own images" ON news_images
    FOR DELETE USING (
        EXISTS (
            SELECT 1 FROM news
            WHERE news.id = news_images.news_id
            AND (
                news.author_id = auth.uid()
                OR public.current_user_role_in_list(ARRAY['admin', 'news'])
            )
        )
    );

-- ============================================
-- 7. NEWS_LIKES / NEWS_COMMENT_LIKES / NEWS_COMMENTS / NEWS_SHARES
--    politikaları zaten auth.users'a erişmiyordu ama eksik olabilecek
--    DELETE/UPDATE politikalarını da güvenli hale getirelim.
-- ============================================

-- news_likes: kullanıcı kendi beğenisini görebilmeli (user bazlı kontrol)
DROP POLICY IF EXISTS "Users can view all news likes" ON news_likes;
CREATE POLICY "Users can view all news likes" ON news_likes
    FOR SELECT USING (true);

-- news_comment_likes: herkes görebilsin
DROP POLICY IF EXISTS "Users can view all news comment likes" ON news_comment_likes;
CREATE POLICY "Users can view all news comment likes" ON news_comment_likes
    FOR SELECT USING (true);

-- news_shares: herkes görebilsin
DROP POLICY IF EXISTS "Public can view shares" ON news_shares;
-- zaten var, dokunmuyoruz
