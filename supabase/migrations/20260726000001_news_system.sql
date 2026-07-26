-- ============================================
-- HABER SİSTEMİ MIGRATION
-- ============================================

-- 1. Kullanıcı rollerine "news" ekle
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'user_role') THEN
        CREATE TYPE user_role AS ENUM ('customer', 'seller', 'admin', 'courier', 'driver', 'news');
    ELSE
        ALTER TYPE user_role ADD VALUE IF NOT EXISTS 'news';
    END IF;
EXCEPTION
    WHEN duplicate_object THEN
        ALTER TYPE user_role ADD VALUE IF NOT EXISTS 'news';
END $$;

-- 2. Haber kategorileri tablosu
CREATE TABLE IF NOT EXISTS news_categories (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL UNIQUE,
    slug TEXT NOT NULL UNIQUE,
    description TEXT,
    icon TEXT,
    color TEXT,
    sort_order INTEGER DEFAULT 0,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Varsayılan kategorileri ekle
INSERT INTO news_categories (name, slug, icon, color, sort_order) VALUES
    ('Genel', 'genel', 'newspaper', '#2196F3', 1),
    ('Duyuru', 'duyuru', 'campaign', '#FF9800', 2),
    ('Etkinlik', 'etkinlik', 'event', '#4CAF50', 3),
    ('Uyarı', 'uyari', 'warning', '#F44336', 4),
    ('Spor', 'spor', 'sports', '#9C27B0', 5),
    ('Eğitim', 'egitim', 'school', '#00BCD4', 6),
    ('Sağlık', 'saglik', 'local_hospital', '#E91E63', 7),
    ('Belediye', 'belediye', 'location_city', '#795548', 8)
ON CONFLICT (slug) DO NOTHING;

-- 3. Kurumlar tablosu
CREATE TABLE IF NOT EXISTS institutions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    slug TEXT NOT NULL UNIQUE,
    logo_url TEXT,
    description TEXT,
    contact_info JSONB DEFAULT '{}',
    website TEXT,
    phone TEXT,
    address TEXT,
    is_verified BOOLEAN DEFAULT false,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Varsayılan kurumları ekle
INSERT INTO institutions (name, slug, logo_url, description, is_verified) VALUES
    ('Cizre Belediyesi', 'cizre-belediyesi', NULL, 'Cizre ilçe belediyesi resmi hesabı', true),
    ('Cizre Kaymakamlığı', 'cizre-kaymakamligi', NULL, 'Cizre ilçe kaymakamlığı resmi hesabı', true),
    ('Cizre İlçe Milli Eğitim', 'cizre-milligretim', NULL, 'Cizre ilçe milli eğitim müdürlüğü', true),
    ('Cizre Devlet Hastanesi', 'cizre-devlet-hastanesi', NULL, 'Cizre devlet hastanesi', true),
    ('Cizre Gençlik ve Spor', 'cizre-genclik-spor', NULL, 'Cizre gençlik ve spor ilçe müdürlüğü', true)
ON CONFLICT (slug) DO NOTHING;

-- 4. Ana haberler tablosu
CREATE TABLE IF NOT EXISTS news (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    title TEXT NOT NULL,
    slug TEXT NOT NULL UNIQUE,
    content TEXT NOT NULL,
    summary TEXT,
    thumbnail_url TEXT,
    category_id UUID REFERENCES news_categories(id) ON DELETE SET NULL,
    institution_id UUID REFERENCES institutions(id) ON DELETE SET NULL,
    author_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    author_name TEXT,
    author_avatar_url TEXT,
    is_featured BOOLEAN DEFAULT false,
    is_published BOOLEAN DEFAULT false,
    is_breaking BOOLEAN DEFAULT false,
    view_count INTEGER DEFAULT 0,
    like_count INTEGER DEFAULT 0,
    comment_count INTEGER DEFAULT 0,
    share_count INTEGER DEFAULT 0,
    location_name TEXT,
    latitude DOUBLE PRECISION,
    longitude DOUBLE PRECISION,
    published_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 5. Haber görselleri tablosu (çoklu görsel desteği)
CREATE TABLE IF NOT EXISTS news_images (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    news_id UUID NOT NULL REFERENCES news(id) ON DELETE CASCADE,
    image_url TEXT NOT NULL,
    thumbnail_url TEXT,
    caption TEXT,
    sort_order INTEGER DEFAULT 0,
    width INTEGER,
    height INTEGER,
    file_size INTEGER,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 6. Haber yorumları tablosu
CREATE TABLE IF NOT EXISTS news_comments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    news_id UUID NOT NULL REFERENCES news(id) ON DELETE CASCADE,
    parent_id UUID REFERENCES news_comments(id) ON DELETE CASCADE,
    user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    user_name TEXT NOT NULL,
    user_avatar_url TEXT,
    content TEXT NOT NULL,
    is_edited BOOLEAN DEFAULT false,
    like_count INTEGER DEFAULT 0,
    report_count INTEGER DEFAULT 0,
    is_hidden BOOLEAN DEFAULT false,
    is_pinned BOOLEAN DEFAULT false,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 7. Haber beğenileri
CREATE TABLE IF NOT EXISTS news_likes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    news_id UUID NOT NULL REFERENCES news(id) ON DELETE CASCADE,
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(news_id, user_id)
);

-- 8. Yorum beğenileri
CREATE TABLE IF NOT EXISTS news_comment_likes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    comment_id UUID NOT NULL REFERENCES news_comments(id) ON DELETE CASCADE,
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(comment_id, user_id)
);

-- 9. Haber paylaşımları (hangi haberin kimin tarafından paylaşıldığı)
CREATE TABLE IF NOT EXISTS news_shares (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    news_id UUID NOT NULL REFERENCES news(id) ON DELETE CASCADE,
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
    platform TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 10. Haber görüntülenme kayıtları
CREATE TABLE IF NOT EXISTS news_views (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    news_id UUID NOT NULL REFERENCES news(id) ON DELETE CASCADE,
    user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    device_info JSONB DEFAULT '{}',
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================
-- İNDEKSLER
-- ============================================
CREATE INDEX IF NOT EXISTS idx_news_published_at ON news(published_at DESC);
CREATE INDEX IF NOT EXISTS idx_news_category_id ON news(category_id);
CREATE INDEX IF NOT EXISTS idx_news_institution_id ON news(institution_id);
CREATE INDEX IF NOT EXISTS idx_news_author_id ON news(author_id);
CREATE INDEX IF NOT EXISTS idx_news_is_published ON news(is_published) WHERE is_published = true;
CREATE INDEX IF NOT EXISTS idx_news_is_featured ON news(is_featured) WHERE is_featured = true;
CREATE INDEX IF NOT EXISTS idx_news_is_breaking ON news(is_breaking) WHERE is_breaking = true;
CREATE INDEX IF NOT EXISTS idx_news_slug ON news(slug);
CREATE INDEX IF NOT EXISTS idx_news_images_news_id ON news_images(news_id);
CREATE INDEX IF NOT EXISTS idx_news_comments_news_id ON news_comments(news_id);
CREATE INDEX IF NOT EXISTS idx_news_comments_user_id ON news_comments(user_id);
CREATE INDEX IF NOT EXISTS idx_news_likes_news_id ON news_likes(news_id);
CREATE INDEX IF NOT EXISTS idx_news_likes_user_id ON news_likes(user_id);
CREATE INDEX IF NOT EXISTS idx_news_views_news_id ON news_views(news_id);

-- ============================================
-- OTOMATİK GÜNCELLEME TRIGGER
-- ============================================
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'update_news_updated_at') THEN
        CREATE TRIGGER update_news_updated_at BEFORE UPDATE ON news
            FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'update_news_categories_updated_at') THEN
        CREATE TRIGGER update_news_categories_updated_at BEFORE UPDATE ON news_categories
            FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'update_institutions_updated_at') THEN
        CREATE TRIGGER update_institutions_updated_at BEFORE UPDATE ON institutions
            FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
    END IF;
    
    IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'update_news_comments_updated_at') THEN
        CREATE TRIGGER update_news_comments_updated_at BEFORE UPDATE ON news_comments
            FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
    END IF;
END $$;

-- ============================================
-- SAYIM TRIGGERLERİ
-- ============================================
-- Yorum sayısı güncelleme
CREATE OR REPLACE FUNCTION update_news_comment_count()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        UPDATE news SET comment_count = comment_count + 1 WHERE id = NEW.news_id;
    ELSIF TG_OP = 'DELETE' THEN
        UPDATE news SET comment_count = comment_count - 1 WHERE id = OLD.news_id;
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'news_comment_count_trigger') THEN
        CREATE TRIGGER news_comment_count_trigger
        AFTER INSERT OR DELETE ON news_comments
        FOR EACH ROW EXECUTE FUNCTION update_news_comment_count();
    END IF;
END $$;

-- Yorum beğeni sayısı güncelleme
CREATE OR REPLACE FUNCTION update_comment_like_count()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        UPDATE news_comments SET like_count = like_count + 1 WHERE id = NEW.comment_id;
    ELSIF TG_OP = 'DELETE' THEN
        UPDATE news_comments SET like_count = like_count - 1 WHERE id = OLD.comment_id;
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'comment_like_count_trigger') THEN
        CREATE TRIGGER comment_like_count_trigger
        AFTER INSERT OR DELETE ON news_comment_likes
        FOR EACH ROW EXECUTE FUNCTION update_comment_like_count();
    END IF;
END $$;

-- Haber beğeni sayısı güncelleme
CREATE OR REPLACE FUNCTION update_news_like_count()
RETURNS TRIGGER AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        UPDATE news SET like_count = like_count + 1 WHERE id = NEW.news_id;
    ELSIF TG_OP = 'DELETE' THEN
        UPDATE news SET like_count = like_count - 1 WHERE id = OLD.news_id;
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'news_like_count_trigger') THEN
        CREATE TRIGGER news_like_count_trigger
        AFTER INSERT OR DELETE ON news_likes
        FOR EACH ROW EXECUTE FUNCTION update_news_like_count();
    END IF;
END $$;

-- Görüntülenme sayısı güncelleme
CREATE OR REPLACE FUNCTION update_news_view_count()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE news SET view_count = view_count + 1 WHERE id = NEW.news_id;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'news_view_count_trigger') THEN
        CREATE TRIGGER news_view_count_trigger
        AFTER INSERT ON news_views
        FOR EACH ROW EXECUTE FUNCTION update_news_view_count();
    END IF;
END $$;

-- ============================================
-- RLS (ROW LEVEL SECURITY)
-- ============================================

-- news tablosu
ALTER TABLE news ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Public can view published news" ON news;
CREATE POLICY "Public can view published news" ON news
    FOR SELECT USING (is_published = true);

DROP POLICY IF EXISTS "Admins and news role can insert news" ON news;
CREATE POLICY "Admins and news role can insert news" ON news
    FOR INSERT WITH CHECK (
        EXISTS (
            SELECT 1 FROM auth.users 
            WHERE id = auth.uid() 
            AND (raw_user_meta_data->>'role' IN ('admin', 'news'))
        )
    );

DROP POLICY IF EXISTS "Authors and admins can update news" ON news;
CREATE POLICY "Authors and admins can update news" ON news
    FOR UPDATE USING (
        author_id = auth.uid() 
        OR EXISTS (
            SELECT 1 FROM auth.users 
            WHERE id = auth.uid() 
            AND (raw_user_meta_data->>'role' = 'admin')
        )
    );

DROP POLICY IF EXISTS "Only admins can delete news" ON news;
CREATE POLICY "Only admins can delete news" ON news
    FOR DELETE USING (
        EXISTS (
            SELECT 1 FROM auth.users 
            WHERE id = auth.uid() 
            AND (raw_user_meta_data->>'role' = 'admin')
        )
    );

-- news_comments tablosu
ALTER TABLE news_comments ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Public can view news comments" ON news_comments;
CREATE POLICY "Public can view news comments" ON news_comments
    FOR SELECT USING (is_hidden = false);

DROP POLICY IF EXISTS "Authenticated users can insert comments" ON news_comments;
CREATE POLICY "Authenticated users can insert comments" ON news_comments
    FOR INSERT WITH CHECK (auth.role() = 'authenticated');

DROP POLICY IF EXISTS "Comment owners can update their comments" ON news_comments;
CREATE POLICY "Comment owners can update their comments" ON news_comments
    FOR UPDATE USING (user_id = auth.uid());

DROP POLICY IF EXISTS "Users can delete own comments" ON news_comments;
CREATE POLICY "Users can delete own comments" ON news_comments
    FOR DELETE USING (user_id = auth.uid());

-- news_images tablosu
ALTER TABLE news_images ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Public can view news images" ON news_images;
CREATE POLICY "Public can view news images" ON news_images
    FOR SELECT USING (true);

DROP POLICY IF EXISTS "News authors can manage images" ON news_images;
CREATE POLICY "News authors can manage images" ON news_images
    FOR ALL USING (
        EXISTS (
            SELECT 1 FROM news 
            WHERE news.id = news_images.news_id 
            AND (news.author_id = auth.uid() 
                 OR EXISTS (
                    SELECT 1 FROM auth.users 
                    WHERE id = auth.uid() 
                    AND (raw_user_meta_data->>'role' IN ('admin', 'news'))
                 ))
        )
    );

-- news_likes tablosu
ALTER TABLE news_likes ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view their own likes" ON news_likes;
CREATE POLICY "Users can view their own likes" ON news_likes
    FOR SELECT USING (user_id = auth.uid());

DROP POLICY IF EXISTS "Authenticated users can like" ON news_likes;
CREATE POLICY "Authenticated users can like" ON news_likes
    FOR INSERT WITH CHECK (auth.role() = 'authenticated' AND user_id = auth.uid());

DROP POLICY IF EXISTS "Users can unlike" ON news_likes;
CREATE POLICY "Users can unlike" ON news_likes
    FOR DELETE USING (user_id = auth.uid());

-- news_comment_likes tablosu
ALTER TABLE news_comment_likes ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view their own comment likes" ON news_comment_likes;
CREATE POLICY "Users can view their own comment likes" ON news_comment_likes
    FOR SELECT USING (user_id = auth.uid());

DROP POLICY IF EXISTS "Authenticated users can like comments" ON news_comment_likes;
CREATE POLICY "Authenticated users can like comments" ON news_comment_likes
    FOR INSERT WITH CHECK (auth.role() = 'authenticated');

DROP POLICY IF EXISTS "Users can unlike comments" ON news_comment_likes;
CREATE POLICY "Users can unlike comments" ON news_comment_likes
    FOR DELETE USING (user_id = auth.uid());

-- news_shares tablosu
ALTER TABLE news_shares ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Public can view shares" ON news_shares;
CREATE POLICY "Public can view shares" ON news_shares
    FOR SELECT USING (true);

DROP POLICY IF EXISTS "Authenticated users can share" ON news_shares;
CREATE POLICY "Authenticated users can share" ON news_shares
    FOR INSERT WITH CHECK (auth.role() = 'authenticated');

-- news_views tablosu
ALTER TABLE news_views ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "System can insert views" ON news_views;
CREATE POLICY "System can insert views" ON news_views
    FOR INSERT WITH CHECK (true);

-- institutions tablosu (herkes görebilir)
ALTER TABLE institutions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Public can view institutions" ON institutions;
CREATE POLICY "Public can view institutions" ON institutions
    FOR SELECT USING (is_active = true);

-- news_categories tablosu (herkes görebilir)
ALTER TABLE news_categories ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Public can view categories" ON news_categories;
CREATE POLICY "Public can view categories" ON news_categories
    FOR SELECT USING (is_active = true);

-- ============================================
-- FONKSİYONLAR
-- ============================================

-- Haber görüntüleme fonksiyonu
CREATE OR REPLACE FUNCTION record_news_view(
    p_news_id UUID,
    p_user_id UUID,
    p_device_info JSONB DEFAULT '{}'
) RETURNS VOID AS $$
BEGIN
    INSERT INTO news_views (news_id, user_id, device_info)
    VALUES (p_news_id, p_user_id, p_device_info)
    ON CONFLICT DO NOTHING;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- Haber beğeni toggle fonksiyonu
CREATE OR REPLACE FUNCTION toggle_news_like(p_news_id UUID)
RETURNS BOOLEAN AS $$
DECLARE
    v_exists BOOLEAN;
    v_user_id UUID := auth.uid();
BEGIN
    IF v_user_id IS NULL THEN
        RETURN FALSE;
    END IF;
    
    SELECT EXISTS(SELECT 1 FROM news_likes WHERE news_id = p_news_id AND user_id = v_user_id)
    INTO v_exists;
    
    IF v_exists THEN
        DELETE FROM news_likes WHERE news_id = p_news_id AND user_id = v_user_id;
        RETURN FALSE;
    ELSE
        INSERT INTO news_likes (news_id, user_id) VALUES (p_news_id, v_user_id);
        RETURN TRUE;
    END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- Yorum beğeni toggle fonksiyonu
CREATE OR REPLACE FUNCTION toggle_comment_like(p_comment_id UUID)
RETURNS BOOLEAN AS $$
DECLARE
    v_exists BOOLEAN;
    v_user_id UUID := auth.uid();
BEGIN
    IF v_user_id IS NULL THEN
        RETURN FALSE;
    END IF;
    
    SELECT EXISTS(SELECT 1 FROM news_comment_likes WHERE comment_id = p_comment_id AND user_id = v_user_id)
    INTO v_exists;
    
    IF v_exists THEN
        DELETE FROM news_comment_likes WHERE comment_id = p_comment_id AND user_id = v_user_id;
        RETURN FALSE;
    ELSE
        INSERT INTO news_comment_likes (comment_id, user_id) VALUES (p_comment_id, v_user_id);
        RETURN TRUE;
    END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- ============================================
-- STORAGE BUCKET
-- ============================================
INSERT INTO storage.buckets (id, name, public)
VALUES ('news-images', 'news-images', true)
ON CONFLICT (id) DO NOTHING;

-- Storage policies
DROP POLICY IF EXISTS "Public can access news images by name" ON storage.objects;
CREATE POLICY "Public can access news images by name" ON storage.objects
    FOR SELECT USING (bucket_id = 'news-images');

DROP POLICY IF EXISTS "Authenticated users can upload news images" ON storage.objects;
CREATE POLICY "Authenticated users can upload news images" ON storage.objects
    FOR INSERT WITH CHECK (bucket_id = 'news-images' AND auth.role() = 'authenticated');

DROP POLICY IF EXISTS "News authors can update images" ON storage.objects;
CREATE POLICY "News authors can update images" ON storage.objects
    FOR UPDATE USING (bucket_id = 'news-images');

DROP POLICY IF EXISTS "Only admins can delete images" ON storage.objects;
CREATE POLICY "Only admins can delete images" ON storage.objects
    FOR DELETE USING (bucket_id = 'news-images' AND
        EXISTS (
            SELECT 1 FROM auth.users
            WHERE id = auth.uid()
            AND (raw_user_meta_data->>'role' = 'admin')
        ));

-- ============================================
-- ANALYTİK VIEW
-- ============================================
SELECT
    n.id,
    n.title,
    n.author_name,
    n.category_id,
    nc.name as category_name,
    n.institution_id,
    i.name as institution_name,
    n.view_count,
    n.like_count,
    n.comment_count,
    n.share_count,
    n.is_published,
    n.is_featured,
    n.is_breaking,
    n.published_at,
    n.created_at,
    COUNT(DISTINCT ni.id) as image_count
FROM news n
LEFT JOIN news_categories nc ON n.category_id = nc.id
LEFT JOIN institutions i ON n.institution_id = i.id
LEFT JOIN news_images ni ON n.id = ni.news_id
GROUP BY n.id, nc.name, i.name;
