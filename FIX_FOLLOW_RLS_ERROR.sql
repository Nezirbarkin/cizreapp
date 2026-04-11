-- =====================================================
-- GİZLİ HESAP TAKİP SİSTEMİ RLS HATASI DÜZELTMESİ
-- =====================================================
-- Hata: new row violates row-level security policy for table "follows"
-- Neden: acceptFollowRequest Flutter'da follows'a insert yapıyor
--        ama auth.uid() = follower_id şartı sağlanmıyor
--        (kabul eden following_id, insert edilen follower_id değil)
-- Çözüm:
--   1. Trigger'ı SECURITY DEFINER yap (RLS bypass)
--   2. follows INSERT RLS policy'yi güncelle
--   3. Flutter kodunu düzelt (follows insert'i kaldır, trigger halledecek)
-- =====================================================

-- =====================================================
-- 1. TRIGGER FONKSİYONUNU SECURITY DEFINER OLARAK YENİDEN OLUŞTUR
-- =====================================================

DROP TRIGGER IF EXISTS trigger_follow_request_status_change ON follow_requests;

CREATE OR REPLACE FUNCTION handle_follow_request_status_change()
RETURNS TRIGGER
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    -- Eğer status 'accepted' ise follows'a ekle
    IF NEW.status = 'accepted' AND (OLD.status IS NULL OR OLD.status != 'accepted') THEN
        INSERT INTO follows (follower_id, following_id, created_at)
        VALUES (NEW.follower_id, NEW.following_id, COALESCE(NEW.created_at, NOW()))
        ON CONFLICT (follower_id, following_id) DO NOTHING;
    END IF;
    
    -- Eğer status 'pending' veya 'rejected' ise follows'tan sil
    IF NEW.status IN ('pending', 'rejected') AND OLD.status = 'accepted' THEN
        DELETE FROM follows
        WHERE follower_id = NEW.follower_id
        AND following_id = NEW.following_id;
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_follow_request_status_change
    AFTER UPDATE OF status ON follow_requests
    FOR EACH ROW
    EXECUTE FUNCTION handle_follow_request_status_change();

-- =====================================================
-- 2. CLEANUP TRIGGER'INI DA GÜNCELLE
-- =====================================================

DROP TRIGGER IF EXISTS trigger_cleanup_follow_request ON follows;

CREATE OR REPLACE FUNCTION cleanup_follow_request_on_unfollow()
RETURNS TRIGGER
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    DELETE FROM follow_requests
    WHERE follower_id = OLD.follower_id
    AND following_id = OLD.following_id;
    
    RETURN OLD;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_cleanup_follow_request
    AFTER DELETE ON follows
    FOR EACH ROW
    EXECUTE FUNCTION cleanup_follow_request_on_unfollow();

-- =====================================================
-- 3. FOLLOWS TABLOSU RLS POLİCY'LERİNİ DÜZELT
-- =====================================================

-- 3.1 Mevcut policy'leri listele
SELECT
    policyname, cmd, qual, with_check
FROM pg_policies
WHERE tablename = 'follows'
ORDER BY policyname;

-- 3.2 Eski INSERT policy'lerini kaldır ve yeniden oluştur
-- Hem follower_id hem following_id eşleşmesine izin ver
DROP POLICY IF EXISTS "Users can follow others" ON follows;
DROP POLICY IF EXISTS "users_can_insert_follows" ON follows;
DROP POLICY IF EXISTS "insert_follows_policy" ON follows;

CREATE POLICY "Users can follow others"
ON follows FOR INSERT
WITH CHECK (
    auth.uid() = follower_id
    OR auth.uid() = following_id
    -- following_id: takip isteği kabul eden kullanıcı (gizli hesap sahibi)
    -- follower_id: normal takip eden kullanıcı
);

-- 3.3 UPDATE/DELETE policy'leri de kontrol et
DROP POLICY IF EXISTS "Users can unfollow" ON follows;
DROP POLICY IF EXISTS "users_can_delete_follows" ON follows;
DROP POLICY IF EXISTS "delete_follows_policy" ON follows;

CREATE POLICY "Users can unfollow"
ON follows FOR DELETE
USING (
    auth.uid() = follower_id
    OR auth.uid() = following_id
    -- Her iki taraf da takibi kaldırabilsin
);

-- =====================================================
-- 4. DOĞRULAMA
-- =====================================================

-- 4.1 Yeni policy'leri listele
SELECT
    policyname, cmd,
    qual as using_expr,
    with_check as check_expr
FROM pg_policies
WHERE tablename = 'follows'
ORDER BY policyname;

-- 4.2 Trigger durumunu kontrol et
SELECT
    event_object_table,
    trigger_name,
    event_manipulation,
    action_timing
FROM information_schema.triggers
WHERE event_object_table IN ('follow_requests', 'follows')
AND trigger_schema = 'public'
ORDER BY event_object_table, trigger_name;

-- =====================================================
-- KULLANIM:
-- 1. Bu SQL dosyasını Supabase SQL Editor'da ÇALIŞTIR
-- 2. Sonra Flutter uygulamasını test et
-- 3. Artık hem trigger (SECURITY DEFINER) hem de
--    Flutter direkt insert (yeni RLS policy) çalışacak
-- =====================================================
