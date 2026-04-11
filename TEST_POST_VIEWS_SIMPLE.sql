-- POST_VIEWS BASIT TEST

-- 1. Gerçek bir post al
SELECT '1. GERÇEK POST' as step;
SELECT id as post_id, user_id as post_owner 
FROM posts 
LIMIT 1;

-- 2. Auth.uid() kontrol
SELECT '2. AUTH.UID()' as step;
SELECT auth.uid() as current_user_id;

-- 3. RPC ile test et (gerçek post ID kullan)
SELECT '3. RPC TEST - GERÇEK POST ID İLE' as step;
DO $$
DECLARE
    v_post_id UUID;
    v_post_owner UUID;
BEGIN
    -- İlk postu al
    SELECT id, user_id INTO v_post_id, v_post_owner
    FROM posts
    LIMIT 1;
    
    IF v_post_id IS NULL THEN
        RAISE NOTICE 'HATA: Hiç post yok!';
        RETURN;
    END IF;
    
    RAISE NOTICE 'Post ID: %', v_post_id;
    RAISE NOTICE 'Post Owner: %', v_post_owner;
    RAISE NOTICE 'Current User: %', auth.uid();
    
    -- RPC çağır
    PERFORM track_post_view(v_post_id);
    RAISE NOTICE 'RPC çalıştırıldı';
END $$;

-- 4. post_views kontrol
SELECT '4. POST_VIEWS KONTROL' as step;
SELECT COUNT(*) as kayit_sayisi FROM post_views;

-- 5. post_views son 5 kayıt
SELECT '5. SON 5 KAYIT' as step;
SELECT * FROM post_views ORDER BY viewed_at DESC LIMIT 5;
