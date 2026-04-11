-- =====================================================
-- DUPLICATE INDEX ve UYARI TEMİZLİĞİ
-- =====================================================
-- Supabase linter uyarılarını temizle:
-- 1. Duplicate index'leri kaldır
-- 2. Fonksiyon search_path uyarılarını düzelt
-- =====================================================

-- 1. DUPLICATE INDEX TEMİZLİĞİ

-- follows tablosundaki duplicate constraint'i kaldır
ALTER TABLE follows DROP CONSTRAINT IF EXISTS follows_follower_following_unique;
-- follows_follower_id_following_id_key zaten unique constraint ile aynı işi yapıyor

-- follow_requests tablosundaki duplicate constraint'i kaldır
ALTER TABLE follow_requests DROP CONSTRAINT IF EXISTS follow_requests_follower_following_unique;
-- follow_requests_follower_id_following_id_key zaten unique constraint ile aynı işi yapıyor

-- 2. SEARCH_PATH UYARILARINI DÜZELT

CREATE OR REPLACE FUNCTION upsert_follow_request(
    p_follower_id uuid,
    p_following_id uuid
)
RETURNS jsonb
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_existing_request follow_requests%ROWTYPE;
    v_existing_follow follows%ROWTYPE;
BEGIN
    IF p_follower_id = p_following_id THEN
        RETURN jsonb_build_object('success', false, 'message', 'Kendinizi takip edemezsiniz');
    END IF;
    
    SELECT * INTO v_existing_follow
    FROM follows
    WHERE follower_id = p_follower_id AND following_id = p_following_id
    LIMIT 1;
    
    IF v_existing_follow IS NOT NULL THEN
        RETURN jsonb_build_object('success', false, 'message', 'Zaten takip ediyorsunuz');
    END IF;
    
    SELECT * INTO v_existing_request
    FROM follow_requests
    WHERE follower_id = p_follower_id AND following_id = p_following_id
    FOR UPDATE;
    
    IF v_existing_request IS NOT NULL THEN
        CASE v_existing_request.status
            WHEN 'pending' THEN
                RETURN jsonb_build_object('success', false, 'message', 'Zaten bekleyen bir istek var', 'status', 'pending');
            WHEN 'accepted' THEN
                IF NOT EXISTS (SELECT 1 FROM follows WHERE follower_id = p_follower_id AND following_id = p_following_id) THEN
                    INSERT INTO follows (follower_id, following_id, created_at)
                    VALUES (p_follower_id, p_following_id, v_existing_request.created_at)
                    ON CONFLICT (follower_id, following_id) DO NOTHING;
                END IF;
                RETURN jsonb_build_object('success', false, 'message', 'Zaten takip ediyorsunuz', 'status', 'accepted');
            WHEN 'rejected' THEN
                UPDATE follow_requests SET status = 'pending', created_at = NOW(), updated_at = NOW()
                WHERE id = v_existing_request.id;
                RETURN jsonb_build_object('success', true, 'message', 'Takip isteği tekrar gönderildi', 'status', 'pending');
        END CASE;
    ELSE
        INSERT INTO follow_requests (follower_id, following_id, status)
        VALUES (p_follower_id, p_following_id, 'pending');
        RETURN jsonb_build_object('success', true, 'message', 'Takip isteği gönderildi', 'status', 'pending');
    END IF;
    
    RETURN jsonb_build_object('success', false, 'message', 'Beklenmeyen hata');
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION validate_follow_data_integrity()
RETURNS TABLE(issue_type text, count bigint, details jsonb)
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    RETURN QUERY
    SELECT 'accepted_not_in_follows'::text, COUNT(*)::bigint,
        COALESCE(jsonb_agg(jsonb_build_object('request_id', fr.id, 'follower_id', fr.follower_id, 'following_id', fr.following_id)), '[]'::jsonb)
    FROM follow_requests fr
    LEFT JOIN follows f ON f.follower_id = fr.follower_id AND f.following_id = fr.following_id
    WHERE fr.status = 'accepted' AND f.id IS NULL;
END;
$$ LANGUAGE plpgsql;
