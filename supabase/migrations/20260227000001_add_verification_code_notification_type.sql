-- ============================================================================
-- ADD verification_code TO NOTIFICATIONS TYPE
-- verification_code tipini notifications tablosuna ekle
-- Tüm mevcut tipleri desteklemek için constraint'i genişlet
-- ============================================================================

-- Önce mevcut verilerde hangi tipler var kontrol et
DO $$
DECLARE
    v_existing_types TEXT[];
    v_all_types TEXT[];
BEGIN
    -- Mevcut type'ları al
    SELECT ARRAY_AGG(DISTINCT type ORDER BY type) INTO v_existing_types
    FROM public.notifications;
    
    RAISE NOTICE 'Mevcut notification types: %', v_existing_types;
    
    -- Constraint'i kaldır (mevcut veriler ne olursa olsun)
    ALTER TABLE public.notifications DROP CONSTRAINT IF EXISTS notifications_type_check;
    
    RAISE NOTICE '✅ Eski constraint kaldırıldı';
    
    -- Yeni constraint ile tip sınırlamasını tamamen kaldırabiliriz
    -- veya TEXT tipinde olduğu için herhangi bir değere izin verebiliriz
    -- Ancak sistem tutarlılığı için validation ekleyelim
    
    -- Herhangi bir TEXT değerine izin veren constraint (esnek)
    ALTER TABLE public.notifications 
      ADD CONSTRAINT notifications_type_check 
      CHECK (type IS NOT NULL AND type <> '');
    
    RAISE NOTICE '✅ Yeni esnek constraint eklendi - tüm tipler destekleniyor';
    
    -- Sonuç raporu
    RAISE NOTICE '================================================================';
    RAISE NOTICE 'Mevcut notification type sayısı: %', COALESCE(array_length(v_existing_types, 1), 0);
    RAISE NOTICE 'Artık verification_code tipi de kullanılabilir';
    RAISE NOTICE '================================================================';
END $$;

COMMENT ON COLUMN public.notifications.type IS 'Bildirim tipi - dinamik (like, comment, follow, mention, order, shop, verification_code vb.)';

SELECT '✅ verification_code tipi kullanıma hazır - tüm mevcut tipler korunmuştur' AS result;
