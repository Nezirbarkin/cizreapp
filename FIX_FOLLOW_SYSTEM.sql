-- =====================================================
-- GİZLİ HESAP TAKİP SİSTEMİ DÜZELTMELERİ
-- =====================================================
-- Bu SQL dosyası şu sorunları düzeltir:
-- 1. accepted follow_requests'ları follows tablosuna ekleyen trigger
-- 2. Mevcut accepted ama follows'ta olmayan kayıtları düzeltir
-- 3. Duplicate kayıtları temizler
-- 4. Unique constraint ekler
-- =====================================================

-- =====================================================
-- 1. MEVCUT DURUMU DÜZELT (Veri Onarımı)
-- =====================================================

-- 1.1 accepted ama follows'ta olmayan kayıtları follows'a ekle
INSERT INTO follows (follower_id, following_id, created_at)
SELECT 
    fr.follower_id,
    fr.following_id,
    fr.created_at
FROM follow_requests fr
LEFT JOIN follows f ON 
    f.follower_id = fr.follower_id AND 
    f.following_id = fr.following_id
WHERE fr.status = 'accepted'
AND f.id IS NULL
ON CONFLICT (follower_id, following_id) DO NOTHING;

-- 1.2 Sonuç kontrolü
SELECT 
    COUNT(*) as fixed_records
FROM follow_requests fr
LEFT JOIN follows f ON 
    f.follower_id = fr.follower_id AND 
    f.following_id = fr.following_id
WHERE fr.status = 'accepted'
AND f.id IS NULL;

-- Eğer 0 ise tüm accepted kayıtlar follows'ta var demektir ✅

-- =====================================================
-- 2. UNIQUE CONSTRAINT'LERİ EKLE
-- =====================================================

-- 2.1 follows tablosuna unique constraint ekle
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint 
        WHERE conname = 'follows_follower_following_unique'
    ) THEN
        ALTER TABLE follows 
        ADD CONSTRAINT follows_follower_following_unique 
        UNIQUE (follower_id, following_id);
        RAISE NOTICE '✅ follows unique constraint eklendi';
    ELSE
        RAISE NOTICE '⚠️ follows unique constraint zaten var';
    END IF;
END $$;

-- 2.2 follow_requests tablosuna unique constraint ekle
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint 
        WHERE conname = 'follow_requests_follower_following_unique'
    ) THEN
        ALTER TABLE follow_requests 
        ADD CONSTRAINT follow_requests_follower_following_unique 
        UNIQUE (follower_id, following_id);
        RAISE NOTICE '✅ follow_requests unique constraint eklendi';
    ELSE
        RAISE NOTICE '⚠️ follow_requests unique constraint zaten var';
    END IF;
END $$;

-- =====================================================
-- 3. FOLLOW REQUESTS TRIGGER'I (Auto-move to follows)
-- =====================================================

-- 3.1 follow_requests status değiştiğinde follows'ı güncelle
CREATE OR REPLACE FUNCTION handle_follow_request_status_change()
RETURNS TRIGGER AS $$
BEGIN
    -- Eğer status 'accepted' ise follows'a ekle
    IF NEW.status = 'accepted' AND OLD.status != 'accepted' THEN
        INSERT INTO follows (follower_id, following_id, created_at)
        VALUES (NEW.follower_id, NEW.following_id, NEW.created_at)
        ON CONFLICT (follower_id, following_id) DO NOTHING;
        
        RAISE NOTICE 'Takip isteği kabul edildi, follows tablosuna eklendi: % -> %', 
            NEW.follower_id, NEW.following_id;
    END IF;
    
    -- Eğer status 'pending' veya 'rejected' ise follows'tan sil
    IF NEW.status IN ('pending', 'rejected') AND OLD.status = 'accepted' THEN
        DELETE FROM follows 
        WHERE follower_id = NEW.follower_id 
        AND following_id = NEW.following_id;
        
        RAISE NOTICE 'Takipten çıkarıldı: % -> %', 
            NEW.follower_id, NEW.following_id;
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 3.2 Trigger'ı oluştur/güncelle
DROP TRIGGER IF EXISTS trigger_follow_request_status_change ON follow_requests;

CREATE TRIGGER trigger_follow_request_status_change
    AFTER UPDATE OF status ON follow_requests
    FOR EACH ROW
    EXECUTE FUNCTION handle_follow_request_status_change();

-- =====================================================
-- 4. upsert_follow_request FONKSİYONUNU GÜNCELLE
-- =====================================================

CREATE OR REPLACE FUNCTION upsert_follow_request(
    p_follower_id uuid,
    p_following_id uuid
)
RETURNS jsonb AS $$
DECLARE
    v_existing_request follow_requests%ROWTYPE;
    v_existing_follow follows%ROWTYPE;
BEGIN
    -- Kendini takip etmeyi engelle
    IF p_follower_id = p_following_id THEN
        RETURN jsonb_build_object(
            'success', false,
            'message', 'Kendinizi takip edemezsiniz'
        );
    END IF;
    
    -- Önce follows'ta var mı kontrol et
    SELECT * INTO v_existing_follow
    FROM follows
    WHERE follower_id = p_follower_id
    AND following_id = p_following_id
    LIMIT 1;
    
    IF v_existing_follow IS NOT NULL THEN
        RETURN jsonb_build_object(
            'success', false,
            'message', 'Zaten takip ediyorsunuz'
        );
    END IF;
    
    -- follow_requests'ta mevcut kaydı kontrol et
    SELECT * INTO v_existing_request
    FROM follow_requests
    WHERE follower_id = p_follower_id
    AND following_id = p_following_id
    FOR UPDATE;
    
    IF v_existing_request IS NOT NULL THEN
        -- Mevcut kayıt varsa
        CASE v_existing_request.status
            WHEN 'pending' THEN
                -- Zaten bekleyen istek var
                RETURN jsonb_build_object(
                    'success', false,
                    'message', 'Zaten bekleyen bir istek var',
                    'status', 'pending'
                );
            WHEN 'accepted' THEN
                -- Kabul edilmiş ama follows'ta yoksa (hata durumu)
                IF NOT EXISTS (
                    SELECT 1 FROM follows 
                    WHERE follower_id = p_follower_id 
                    AND following_id = p_following_id
                ) THEN
                    -- follows'a ekle
                    INSERT INTO follows (follower_id, following_id, created_at)
                    VALUES (p_follower_id, p_following_id, v_existing_request.created_at)
                    ON CONFLICT (follower_id, following_id) DO NOTHING;
                END IF;
                
                RETURN jsonb_build_object(
                    'success', false,
                    'message', 'Zaten takip ediyorsunuz (kabul edilmiş)',
                    'status', 'accepted'
                );
            WHEN 'rejected' THEN
                -- Reddedilmişse yeniden gönder
                UPDATE follow_requests
                SET status = 'pending', created_at = NOW(), updated_at = NOW()
                WHERE id = v_existing_request.id;
                
                RETURN jsonb_build_object(
                    'success', true,
                    'message', 'Takip isteği tekrar gönderildi',
                    'status', 'pending'
                );
        END CASE;
    ELSE
        -- Yeni istek oluştur
        INSERT INTO follow_requests (follower_id, following_id, status)
        VALUES (p_follower_id, p_following_id, 'pending');
        
        RETURN jsonb_build_object(
            'success', true,
            'message', 'Takip isteği gönderildi',
            'status', 'pending'
        );
    END IF;
    
    RETURN jsonb_build_object(
        'success', false,
        'message', 'Beklenmeyen hata'
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- =====================================================
-- 5. FOLLOW_DELETE İÇİN TEMİZLİK
-- =====================================================

-- 5.1 follow silindiğinde follow_requests'i de güncelle
CREATE OR REPLACE FUNCTION cleanup_follow_request_on_unfollow()
RETURNS TRIGGER AS $$
BEGIN
    -- follows'tan silinen kayıt için follow_requests'i de sil
    DELETE FROM follow_requests
    WHERE follower_id = OLD.follower_id
    AND following_id = OLD.following_id;
    
    RETURN OLD;
END;
$$ LANGUAGE plpgsql;

-- 5.2 Trigger'ı oluştur
DROP TRIGGER IF EXISTS trigger_cleanup_follow_request ON follows;

CREATE TRIGGER trigger_cleanup_follow_request
    AFTER DELETE ON follows
    FOR EACH ROW
    EXECUTE FUNCTION cleanup_follow_request_on_unfollow();

-- =====================================================
-- 6. VERİ DOĞRULAMA SAĞLAMA FONKSİYONU
-- =====================================================

CREATE OR REPLACE FUNCTION validate_follow_data_integrity()
RETURNS TABLE(
    issue_type text,
    count bigint,
    details jsonb
) AS $$
BEGIN
    -- 1. accepted ama follows'ta olmayanlar
    RETURN QUERY
    SELECT 
        'accepted_not_in_follows' as issue_type,
        COUNT(*) as count,
        jsonb_agg(jsonb_build_object(
            'request_id', fr.id,
            'follower_id', fr.follower_id,
            'following_id', fr.following_id
        )) as details
    FROM follow_requests fr
    LEFT JOIN follows f ON 
        f.follower_id = fr.follower_id AND 
        f.following_id = fr.following_id
    WHERE fr.status = 'accepted'
    AND f.id IS NULL;
    
    -- 2. follows'ta var ama follow_requests accepted değil
    RETURN QUERY
    SELECT 
        'follow_without_accepted_request' as issue_type,
        COUNT(*) as count,
        jsonb_agg(jsonb_build_object(
            'follower_id', f.follower_id,
            'following_id', f.following_id
        )) as details
    FROM follows f
    LEFT JOIN follow_requests fr ON 
        fr.follower_id = f.follower_id AND 
        fr.following_id = f.following_id
    WHERE fr.id IS NULL OR fr.status != 'accepted';
    
END;
$$ LANGUAGE plpgsql;

-- =====================================================
-- 7. TEST VE DOĞRULAMA
-- =====================================================

-- 7.1 Veri bütünlüğünü kontrol et
SELECT * FROM validate_follow_data_integrity();

-- 7.2 Mevcut durumu özetle
SELECT 
    'follow_requests' as table_name,
    COUNT(*) as total,
    COUNT(*) FILTER (WHERE status = 'pending') as pending,
    COUNT(*) FILTER (WHERE status = 'accepted') as accepted,
    COUNT(*) FILTER (WHERE status = 'rejected') as rejected
FROM follow_requests

UNION ALL

SELECT 
    'follows' as table_name,
    COUNT(*) as total,
    0, 0, 0
FROM follows;

-- 7.3 Trigger kontrolü
SELECT 
    trigger_name,
    event_manipulation,
    action_timing
FROM information_schema.triggers
WHERE event_object_table IN ('follow_requests', 'follows')
AND trigger_schema = 'public'
ORDER BY event_object_table, trigger_name;

-- =====================================================
-- 8. TEMİZLİK İŞLEMLERİ (Opsiyonel)
-- =====================================================

-- Eğer duplicate kayıtlar varsa bunları temizlemek için:
-- ⚠️ DİKKAT: Bu işlem veri kaybına yol açabilir, yedek alın!

-- 8.1 Duplicate follow_requests'ları temizle
-- WITH ranked_requests AS (
--     SELECT 
--         id,
--         follower_id,
--         following_id,
--         status,
--         ROW_NUMBER() OVER (
--             PARTITION BY follower_id, following_id 
--             ORDER BY created_at DESC
--         ) as rn
--     FROM follow_requests
-- )
-- DELETE FROM follow_requests
-- WHERE id IN (
--     SELECT id FROM ranked_requests WHERE rn > 1
-- );

-- 8.2 Duplicate follows'ları temizle
-- WITH ranked_follows AS (
--     SELECT 
--         id,
--         follower_id,
--         following_id,
--         ROW_NUMBER() OVER (
--             PARTITION BY follower_id, following_id 
--             ORDER BY created_at DESC
--         ) as rn
--     FROM follows
-- )
-- DELETE FROM follows
-- WHERE id IN (
--     SELECT id FROM ranked_follows WHERE rn > 1
-- );

-- =====================================================
-- KULLANIM TALİMATLARI:
-- =====================================================
-- 
-- 1. Önce DEBUG_FOLLOW_SYSTEM.sql dosyasını çalıştırın
-- 2. Sonuçları inceleyin
-- 3. Bu dosyayı (FIX_FOLLOW_SYSTEM.sql) çalıştırın
-- 4. Sonuçları doğrulamak için tekrar DEBUG_FOLLOW_SYSTEM.sql çalıştırın
-- 
-- ⚠️ ÖNEMLİ:
-- - Bu değişiklikleri yapmadan önce veritabanı yedeği alın
-- - Test ortamında önce deneyin
-- - Production'da çalıştırmadan önce tüm sorguları inceleyin
-- =====================================================
