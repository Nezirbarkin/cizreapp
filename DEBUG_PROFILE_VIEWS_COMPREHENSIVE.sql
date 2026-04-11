-- ============================================
-- COMPREHENSIVE PROFILE VIEWS DEBUG SCRIPT
-- Bu scripti Supabase SQL Editor'da çalıştırın
-- ============================================

-- 1. TABLO YAPILARI KONTROL
SELECT '=== 1. TABLO YAPILARI ===' as debug_step;

SELECT 
    table_name,
    column_name,
    data_type,
    is_nullable
FROM information_schema.columns
WHERE table_name IN ('profile_views', 'post_views')
ORDER BY table_name, ordinal_position;

-- 2. MEVCUT VERİLER
SELECT '=== 2. MEVCUT VERİLER ===' as debug_step;

SELECT 'profile_views tablosundaki kayıt sayısı:' as info, COUNT(*) as count FROM profile_views;
SELECT 'post_views tablosundaki kayıt sayısı:' as info, COUNT(*) as count FROM post_views;

-- Son 10 profil görüntüleme
SELECT 
    'Son 10 profil görüntüleme:' as info,
    pv.id,
    pv.profile_id,
    pv.viewer_id,
    pv.viewed_at,
    pv.view_date,
    p1.username as profile_username,
    p2.username as viewer_username
FROM profile_views pv
LEFT JOIN profiles p1 ON p1.id = pv.profile_id
LEFT JOIN profiles p2 ON p2.id = pv.viewer_id
ORDER BY pv.viewed_at DESC
LIMIT 10;

-- 3. FONKSİYONLARIN VARLIĞI
SELECT '=== 3. FONKSİYONLARIN VARLIĞI ===' as debug_step;

SELECT 
    routine_name,
    routine_type,
    security_type
FROM information_schema.routines
WHERE routine_name IN (
    'track_profile_view',
    'track_post_view',
    'get_profile_current_month_views',
    'get_post_current_month_views'
)
ORDER BY routine_name;

-- 4. RLS POLİTİKALARI KONTROL
SELECT '=== 4. RLS POLİTİKALARI ===' as debug_step;

SELECT 
    schemaname,
    tablename,
    policyname,
    permissive,
    roles,
    cmd,
    qual,
    with_check
FROM pg_policies
WHERE tablename IN ('profile_views', 'post_views')
ORDER BY tablename, policyname;

-- 5. MANUEL TEST - TRACK_PROFILE_VIEW FONKSİYONU
SELECT '=== 5. MANUEL TEST - TRACK_PROFILE_VIEW ===' as debug_step;

-- Önce auth.uid() kontrolü
SELECT 'Mevcut kullanıcı (auth.uid()):' as info, auth.uid() as current_user_id;

-- Test için bir profil ID seçelim (ilk profil)
DO $$
DECLARE
    test_profile_id UUID;
    test_viewer_id UUID;
BEGIN
    -- İlk profili al
    SELECT id INTO test_profile_id FROM profiles LIMIT 1;
    
    -- Mevcut kullanıcı ID'sini al
    test_viewer_id := auth.uid();
    
    RAISE NOTICE 'Test profil ID: %', test_profile_id;
    RAISE NOTICE 'Test görüntüleyen ID: %', test_viewer_id;
    
    IF test_viewer_id IS NULL THEN
        RAISE NOTICE 'UYARI: auth.uid() NULL döndü! Kullanıcı girişi yapılmamış olabilir.';
    ELSIF test_viewer_id = test_profile_id THEN
        RAISE NOTICE 'UYARI: Kendi profilini görüntülemeye çalışıyorsun. Fonksiyon bunu kaydedmez.';
    ELSE
        -- Fonksiyonu çağır
        PERFORM track_profile_view(test_profile_id);
        RAISE NOTICE 'track_profile_view() fonksiyonu çalıştırıldı.';
    END IF;
END $$;

-- 6. MANUEL INSERT TESTİ
SELECT '=== 6. MANUEL INSERT TESTİ ===' as debug_step;

DO $$
DECLARE
    test_profile_id UUID;
    test_viewer_id UUID;
BEGIN
    -- İlk iki farklı profili al
    SELECT id INTO test_profile_id FROM profiles ORDER BY created_at LIMIT 1;
    SELECT id INTO test_viewer_id FROM profiles ORDER BY created_at LIMIT 1 OFFSET 1;
    
    -- Manuel insert dene
    BEGIN
        INSERT INTO profile_views (profile_id, viewer_id, viewed_at, view_date)
        VALUES (test_profile_id, test_viewer_id, NOW(), CURRENT_DATE)
        ON CONFLICT (profile_id, viewer_id, view_date) WHERE viewer_id IS NOT NULL
        DO NOTHING;
        
        RAISE NOTICE 'Manuel insert başarılı!';
        RAISE NOTICE 'Profil ID: %', test_profile_id;
        RAISE NOTICE 'Görüntüleyen ID: %', test_viewer_id;
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE 'Manuel insert HATA: %', SQLERRM;
    END;
END $$;

-- 7. GET_PROFILE_CURRENT_MONTH_VIEWS FONKSİYON TESTİ
SELECT '=== 7. GET_PROFILE_CURRENT_MONTH_VIEWS TESTİ ===' as debug_step;

DO $$
DECLARE
    test_profile_id UUID;
    result RECORD;
BEGIN
    -- İlk profili al
    SELECT id INTO test_profile_id FROM profiles LIMIT 1;
    
    -- Fonksiyonu çağır
    SELECT * INTO result FROM get_profile_current_month_views(test_profile_id);
    
    RAISE NOTICE 'Profil ID: %', test_profile_id;
    RAISE NOTICE 'Total views: %', result.total_views;
    RAISE NOTICE 'Unique viewers: %', result.unique_viewers;
END $$;

-- 8. CONSTRAINT KONTROL
SELECT '=== 8. CONSTRAINT KONTROL ===' as debug_step;

SELECT
    tc.constraint_name,
    tc.table_name,
    kcu.column_name,
    tc.constraint_type
FROM information_schema.table_constraints tc
JOIN information_schema.key_column_usage kcu
    ON tc.constraint_name = kcu.constraint_name
WHERE tc.table_name IN ('profile_views', 'post_views')
ORDER BY tc.table_name, tc.constraint_type;

-- 9. SON KONTROL - VERİ EKLENDİ Mİ?
SELECT '=== 9. SON KONTROL ===' as debug_step;

SELECT 
    'Test sonrası profile_views sayısı:' as info,
    COUNT(*) as count
FROM profile_views;

SELECT 
    'Bugünkü görüntülemeler:' as info,
    COUNT(*) as count
FROM profile_views
WHERE view_date = CURRENT_DATE;

-- 10. TÜM PROFİLLER LİSTESİ
SELECT '=== 10. MEVCUT PROFİLLER ===' as debug_step;

SELECT 
    id,
    username,
    full_name,
    created_at
FROM profiles
ORDER BY created_at
LIMIT 5;

-- ============================================
-- SONUÇ YORUMU
-- ============================================
SELECT '
=== DEBUG SONUÇLARI YORUMLAMA ===

1. Eğer auth.uid() NULL dönüyorsa:
   - Supabase SQL Editor''da çalıştırırken normal
   - Flutter''dan çağrıldığında auth.uid() otomatik dolmalı
   - Flutter client''ın authentication token''ı göndermesi gerekiyor

2. Eğer tablolar boşsa:
   - RLS politikaları insert''i engelliyor olabilir
   - Flutter service error handling silent olabilir

3. Eğer manuel insert başarılı ama fonksiyon çalışmıyorsa:
   - Fonksiyon definition''ında sorun var
   - SECURITY DEFINER ayarı eksik olabilir

4. Eğer get_profile_current_month_views 0 dönüyorsa:
   - Veri var ama query yanlış
   - Tarih filtreleri çalışmıyor

5. Flutter tarafında kontrol edilecekler:
   - await _supabase.rpc() hata fırlatıyor mu?
   - profileId doğru mu?
   - User authenticated mi?
' as yorum;
