-- ============================================
-- GÖNDERİ SİLME FONKSİYONU DÜZELTME
-- Sorun: Yanlış tablo isimleri yüzünden 42P01 hatası (relation "comments" does not exist)
-- Çözüm: PROJE_HAVIZA_SCHEMA.md §2.2'ye uygun tablo isimleri kullan
-- Tarih: 2026-07-09
-- ============================================

-- Önce eski admin_delete_post fonksiyonunu sil
DROP FUNCTION IF EXISTS admin_delete_post(UUID) CASCADE;

-- Admin gönderi silme fonksiyonunu oluştur
-- PROJE_HAVIZA_SCHEMA.md §2.2'deki doğru tablo isimleri kullanılıyor
CREATE OR REPLACE FUNCTION admin_delete_post(post_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_current_user_id UUID;
    v_is_admin BOOLEAN;
    v_deleted_post RECORD;
BEGIN
    v_current_user_id := auth.uid();
    
    -- Admin kontrolü
    SELECT EXISTS (
        SELECT 1 FROM profiles AS pr
        WHERE pr.id = v_current_user_id
        AND (pr.role = 'admin' OR pr.is_admin = true)
    ) INTO v_is_admin;
    
    IF NOT v_is_admin THEN
        RAISE EXCEPTION 'Yetkisiz erisim: Sadece adminler gonderi silebilir';
    END IF;
    
    -- ✅ post_likes (doğru isim)
    DELETE FROM post_likes AS pl WHERE pl.post_id = admin_delete_post.post_id;
    
    -- ✅ post_views (doğru isim)
    DELETE FROM post_views AS pv WHERE pv.post_id = admin_delete_post.post_id;
    
    -- ❌ ÖNCEKİ HATA: 'comments' YOKTU → 'post_comments' OLMALI
    DELETE FROM post_comments AS c WHERE c.post_id = admin_delete_post.post_id;
    
    -- ❌ ÖNCEKİ HATA: 'saved_posts' YOKTU → 'post_saves' OLMALI
    DELETE FROM post_saves AS sp WHERE sp.post_id = admin_delete_post.post_id;
    
    -- ✅ post_favorites da silinmeli (orphan kalmaması için)
    DELETE FROM post_favorites AS pf WHERE pf.post_id = admin_delete_post.post_id;
    
    -- ✅ post_reports da silinmeli (orphan kalmaması için)
    DELETE FROM post_reports AS pr WHERE pr.post_id = admin_delete_post.post_id;
    
    -- Son olarak posts tablosunu sil
    DELETE FROM posts AS p WHERE p.id = admin_delete_post.post_id RETURNING * INTO v_deleted_post;
    
    -- Sonucu döndür
    RETURN jsonb_build_object(
        'success', true,
        'message', 'Gonderi basariyla silindi',
        'post_id', admin_delete_post.post_id
    );
END;
$$;

-- Yetkilendirme
GRANT EXECUTE ON FUNCTION admin_delete_post(UUID) TO authenticated;

-- Başarı mesajı
DO $$
BEGIN
    RAISE NOTICE '========================================';
    RAISE NOTICE 'Gonderi silme fonksiyonu duzeltildi!';
    RAISE NOTICE '  - comments -> post_comments';
    RAISE NOTICE '  - saved_posts -> post_saves';
    RAISE NOTICE '  - post_favorites eklendi';
    RAISE NOTICE '  - post_reports eklendi';
    RAISE NOTICE '========================================';
END $$;
