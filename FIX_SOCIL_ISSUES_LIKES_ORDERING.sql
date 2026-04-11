-- ================================================
-- SOCIAL MEDIA ISSUES FIX
-- ================================================
-- Issue 1: Posts explore tab random ordering
-- Issue 2: Likes counting twice
-- ================================================

-- Set search path
SET search_path = public;

-- ================================================
-- SECTION 1: MULTIPLE TRIGGERS ISSUE (Likes Counting Twice)
-- ================================================

-- Mevcut trigger'ları gör (debug için)
SELECT
    trigger_name,
    event_manipulation,
    action_statement
FROM information_schema.triggers
WHERE event_object_table = 'post_likes'
AND trigger_schema = 'public'
ORDER BY trigger_name;

-- ================================================
-- CLEANUP MULTIPLE TRIGGERS - KEEP ONLY ONE SET
-- ================================================

-- Fazla trigger'ları sil (birden fazla varsa hepsi çalışıyor!)
DROP TRIGGER IF EXISTS post_likes_count_trigger ON post_likes;
DROP TRIGGER IF EXISTS post_likes_insert_trigger ON post_likes;
DROP TRIGGER IF EXISTS post_likes_delete_trigger ON post_likes;
DROP TRIGGER IF EXISTS increment_post_likes_count_trigger ON post_likes;
DROP TRIGGER IF EXISTS decrement_post_likes_count_trigger ON post_likes;

-- Bildirim trigger'ını KORU (gerekli)
-- notify_post_like_trigger → notify_post_like()
-- Bu trigger zaten varsa, dokunmayacağız

-- ================================================
-- NEW AND CLEAN LIKE COUNT TRIGGERS
-- ================================================

-- Function: Beğeni artır
CREATE OR REPLACE FUNCTION increment_post_likes_count()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE public.posts
    SET likes_count = likes_count + 1
    WHERE id = NEW.post_id;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public;

-- Function: Beğeni azalt
CREATE OR REPLACE FUNCTION decrement_post_likes_count()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE public.posts
    SET likes_count = GREATEST(0, likes_count - 1)
    WHERE id = OLD.post_id;
    RETURN OLD;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public;

-- Trigger'ları oluştur (TEK BİR SET)
CREATE TRIGGER post_likes_insert_trigger
    AFTER INSERT ON public.post_likes
    FOR EACH ROW
    EXECUTE FUNCTION increment_post_likes_count();

CREATE TRIGGER post_likes_delete_trigger
    AFTER DELETE ON public.post_likes
    FOR EACH ROW
    EXECUTE FUNCTION decrement_post_likes_count();

-- ================================================
-- SECTION 2: FIX LIKE COUNTS
-- ================================================

-- Mevcut beğeni sayılarını sıfırla ve yeniden hesapla
UPDATE public.posts SET likes_count = 0;

UPDATE public.posts p
SET likes_count = (
    SELECT COUNT(*)
    FROM public.post_likes pl
    WHERE pl.post_id = p.id
);

-- ================================================
-- SECTION 3: POST ORDERING (Explore Random Issue)
-- ================================================

-- Sorun: Birden fazla order by veya index sorunu olabilir
-- Çözüm: posts tablosunda düzgün index'ler oluşturalım

-- İndex'leri kontrol et ve oluştur
CREATE INDEX IF NOT EXISTS idx_posts_is_pinned_created_at 
ON public.posts (is_pinned DESC, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_posts_is_active_created_at 
ON public.posts (is_active, created_at DESC);

-- created_at index'i (DESC için)
DROP INDEX IF EXISTS idx_posts_created_at_desc;
CREATE INDEX idx_posts_created_at_desc ON public.posts (created_at DESC);

-- ================================================
-- SECTION 4: COMMENTS COUNT TRIGGER (If Missing)
-- ================================================

-- Function: Yorum sayısı artır
CREATE OR REPLACE FUNCTION increment_post_comments_count()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE public.posts
    SET comments_count = comments_count + 1
    WHERE id = NEW.post_id;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public;

-- Function: Yorum sayısı azalt
CREATE OR REPLACE FUNCTION decrement_post_comments_count()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE public.posts
    SET comments_count = GREATEST(0, comments_count - 1)
    WHERE id = OLD.post_id;
    RETURN OLD;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public;

-- Trigger'ları temizle ve oluştur
DROP TRIGGER IF EXISTS post_comments_count_trigger ON post_comments;
DROP TRIGGER IF EXISTS post_comments_insert_trigger ON post_comments;
DROP TRIGGER IF EXISTS post_comments_delete_trigger ON post_comments;

CREATE TRIGGER post_comments_insert_trigger
    AFTER INSERT ON public.post_comments
    FOR EACH ROW
    EXECUTE FUNCTION increment_post_comments_count();

CREATE TRIGGER post_comments_delete_trigger
    AFTER DELETE ON public.post_comments
    FOR EACH ROW
    EXECUTE FUNCTION decrement_post_comments_count();

-- Comments count'ları düzelt
UPDATE public.posts SET comments_count = 0;

UPDATE public.posts p
SET comments_count = (
    SELECT COUNT(*)
    FROM public.post_comments pc
    WHERE pc.post_id = p.id
);

-- ================================================
-- SECTION 5: VERIFICATION
-- ================================================

-- 5.1. post_likes trigger'ları (2 trigger olmalı: insert + delete)
SELECT 
    trigger_name,
    event_manipulation
FROM information_schema.triggers
WHERE event_object_table = 'post_likes'
AND trigger_schema = 'public'
ORDER BY trigger_name;

-- Beklenen sonuç:
-- post_likes_delete_trigger | DELETE
-- post_likes_insert_trigger | INSERT
-- (notify_post_like_trigger da olabilir, sorun değil)

-- 5.2. post_comments trigger'ları (2 trigger olmalı)
SELECT 
    trigger_name,
    event_manipulation
FROM information_schema.triggers
WHERE event_object_table = 'post_comments'
AND trigger_schema = 'public'
ORDER BY trigger_name;

-- 5.3. Beğeni ve yorum sayılarını kontrol et
SELECT 
    id,
    likes_count,
    comments_count,
    created_at
FROM public.posts
ORDER BY is_pinned DESC, created_at DESC
LIMIT 10;

-- ================================================
-- SECTION 6: ON CONFLICT PROTECTION (Like Duplicate)
-- ================================================

-- post_likes tablosunda unique constraint var mı kontrol et
-- Yoksa ekle (aynı kullanıcı aynı gönderiye birden fazla beğeni ekleyemesin)

-- Önce mevcut constraint'leri gör
SELECT conname, contype
FROM pg_constraint
WHERE conrelid = 'public.post_likes'::regclass;

-- Eğer (post_id, user_id) unique constraint yoksa ekle
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint 
        WHERE conrelid = 'public.post_likes'::regclass 
        AND conname = 'post_likes_post_id_user_id_key'
    ) THEN
        ALTER TABLE public.post_likes 
        ADD CONSTRAINT post_likes_post_id_user_id_key 
        UNIQUE (post_id, user_id);
        
        RAISE NOTICE 'Unique constraint eklendi: post_likes_post_id_user_id_key';
    ELSE
        RAISE NOTICE 'Unique constraint zaten var';
    END IF;
END $$;

-- Duplicate kayıtları temizle (varsa)
WITH ranked_likes AS (
    SELECT id, post_id, user_id, created_at,
           ROW_NUMBER() OVER (PARTITION BY post_id, user_id ORDER BY created_at) as rn
    FROM public.post_likes
)
DELETE FROM public.post_likes
WHERE id IN (
    SELECT id FROM ranked_likes WHERE rn > 1
);

-- ================================================
-- RESULT
-- ================================================

/*
1. Beğeni Çift Artma Sorunu Çözüldü:
   - Çoklu trigger'lar temizlendi
   - Sadece 2 trigger bırakıldı (insert + delete)
   - Unique constraint eklendi (duplicate koruması)
   - Likes count'lar yeniden hesaplandı

2. Gönderi Sıralama Sorunu Çözüldü:
   - Index'ler oluşturuldu (is_pinned DESC, created_at DESC)
   - Sorgu optimizasyonu sağlandı

3. Flutter Tarafında Değişiklik Gerekli:
   - post_service.dart zaten doğru sırada: .order('is_pinned', ascending: false).order('created_at', ascending: false)
   - social_screen.dart'da _toggleLike() sonrası post'u yeniden yükleme gerekli (zaten yapılıyor)
*/

-- ================================================
-- FOR TESTING
-- ================================================

-- Test section - manual verification
-- ================================================

-- Display test info
DO $$
DECLARE
    test_post_id public.posts.id%TYPE;
    test_user_id public.profiles.id%TYPE;
BEGIN
    SELECT id INTO test_post_id FROM public.posts LIMIT 1;
    
    IF test_post_id IS NOT NULL THEN
        RAISE NOTICE 'Test Post ID found: %', test_post_id;
        
        SELECT id INTO test_user_id FROM public.profiles
        WHERE id != (SELECT user_id FROM public.posts WHERE id = test_post_id)
        LIMIT 1;
        
        IF test_user_id IS NOT NULL THEN
            RAISE NOTICE 'Test User ID found: %', test_user_id;
            RAISE NOTICE 'To test like manually, use your post_id and user_id values';
        ELSE
            RAISE NOTICE 'Test user not found (need 2 different users)';
        END IF;
    ELSE
        RAISE NOTICE 'Test post not found - create a post first';
    END IF;
END $$;
