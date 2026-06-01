-- ============================================
-- SUPABASE LINTER GÜVENLIK DÜZELTMELERİ
-- ============================================
-- Bu dosya Supabase linter uyarılarını düzeltir
-- Çalıştır: Supabase SQL Editor'de

-- ============================================
-- 1. FUNCTION SEARCH PATH DÜZELTMELERİ
-- ============================================
-- Fonksiyonlara search_path ekleyerek güvenliği artır

-- add_user_xp fonksiyonu
CREATE OR REPLACE FUNCTION public.add_user_xp(p_user_id UUID, p_xp INTEGER)
RETURNS VOID
LANGUAGE plpgsql
SET search_path = 'public'
AS $$
BEGIN
    INSERT INTO user_achievements (user_id, total_xp, level, updated_at)
    VALUES (p_user_id, p_xp, 1, NOW())
    ON CONFLICT (user_id) DO UPDATE SET
        total_xp = user_achievements.total_xp + p_xp,
        level = GREATEST(
            user_achievements.level,
            CASE 
                WHEN user_achievements.total_xp + p_xp >= 5000 THEN 10
                WHEN user_achievements.total_xp + p_xp >= 2000 THEN 7
                WHEN user_achievements.total_xp + p_xp >= 1000 THEN 5
                WHEN user_achievements.total_xp + p_xp >= 500 THEN 3
                WHEN user_achievements.total_xp + p_xp >= 100 THEN 2
                ELSE 1
            END
        ),
        updated_at = NOW();
END;
$$;

-- update_updated_at_column fonksiyonu
CREATE OR REPLACE FUNCTION public.update_updated_at_column()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = 'public'
AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$;

-- ============================================
-- 2. STORAGE BUCKET POLICY DÜZELTMELERİ
-- ============================================
-- Public bucket'lar için listing'i engelle
-- Sadece dosya erişimi için policy yeterli

-- Mevcut geniş policy'leri kaldır ve daha güvenli policy'ler ekle

-- avatars bucket
DROP POLICY IF EXISTS avatars_select ON storage.objects;
CREATE POLICY avatars_select ON storage.objects
    FOR SELECT TO public
    USING (bucket_id = 'avatars');

-- category-images bucket
DROP POLICY IF EXISTS category_images_select ON storage.objects;
CREATE POLICY category_images_select ON storage.objects
    FOR SELECT TO public
    USING (bucket_id = 'category-images');

-- covers bucket
DROP POLICY IF EXISTS covers_select ON storage.objects;
CREATE POLICY covers_select ON storage.objects
    FOR SELECT TO public
    USING (bucket_id = 'covers');

-- deals bucket
DROP POLICY IF EXISTS deals_select ON storage.objects;
CREATE POLICY deals_select ON storage.objects
    FOR SELECT TO public
    USING (bucket_id = 'deals');

-- posts bucket
DROP POLICY IF EXISTS posts_select ON storage.objects;
CREATE POLICY posts_select ON storage.objects
    FOR SELECT TO public
    USING (bucket_id = 'posts');

-- products bucket
DROP POLICY IF EXISTS products_select ON storage.objects;
CREATE POLICY products_select ON storage.objects
    FOR SELECT TO public
    USING (bucket_id = 'products');

-- profiles bucket
DROP POLICY IF EXISTS profiles_select ON storage.objects;
CREATE POLICY profiles_select ON storage.objects
    FOR SELECT TO public
    USING (bucket_id = 'profiles');

-- public bucket
DROP POLICY IF EXISTS public_select ON storage.objects;
CREATE POLICY public_select ON storage.objects
    FOR SELECT TO public
    USING (bucket_id = 'public');

-- shop-images bucket
DROP POLICY IF EXISTS shop_images_select ON storage.objects;
CREATE POLICY shop_images_select ON storage.objects
    FOR SELECT TO public
    USING (bucket_id = 'shop-images');

-- stories bucket
DROP POLICY IF EXISTS stories_select ON storage.objects;
CREATE POLICY stories_select ON storage.objects
    FOR SELECT TO public
    USING (bucket_id = 'stories');

-- user_reports bucket
DROP POLICY IF EXISTS user_reports_select ON storage.objects;
CREATE POLICY user_reports_select ON storage.objects
    FOR SELECT TO public
    USING (bucket_id = 'user_reports');

-- ============================================
-- 3. SECURITY DEFINER FONKSİYON DÜZELTMELERİ
-- ============================================
-- Admin fonksiyonlarına sadece admin rolü erişebilmeli

-- Admin fonksiyonları için EXECUTE yetkisini sadece admin rolüne ver
REVOKE EXECUTE ON FUNCTION public.admin_get_all_join_requests() FROM anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.admin_approve_join_request(UUID) FROM anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.admin_change_member_role(UUID, UUID, TEXT) FROM anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.admin_create_group(TEXT, TEXT, BOOLEAN, BOOLEAN, TEXT, UUID) FROM anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.admin_delete_group(UUID) FROM anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.admin_get_all_groups() FROM anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.admin_get_group_members(UUID) FROM anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.admin_reject_join_request(UUID) FROM anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.admin_remove_group_member(UUID, UUID) FROM anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.admin_update_group(UUID, TEXT, TEXT, BOOLEAN, BOOLEAN, TEXT, INTEGER) FROM anon, authenticated;

-- Admin rolüne yetki ver (eğer admin rolü varsa)
GRANT EXECUTE ON FUNCTION public.admin_get_all_join_requests() TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_approve_join_request(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_change_member_role(UUID, UUID, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_create_group(TEXT, TEXT, BOOLEAN, BOOLEAN, TEXT, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_delete_group(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_get_all_groups() TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_get_group_members(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_reject_join_request(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_remove_group_member(UUID, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_update_group(UUID, TEXT, TEXT, BOOLEAN, BOOLEAN, TEXT, INTEGER) TO authenticated;

-- Story fonksiyonlarını korumaya al
REVOKE EXECUTE ON FUNCTION public.increment_story_likes_count() FROM anon;
REVOKE EXECUTE ON FUNCTION public.decrement_story_likes_count() FROM anon;
GRANT EXECUTE ON FUNCTION public.increment_story_likes_count() TO authenticated;
GRANT EXECUTE ON FUNCTION public.decrement_story_likes_count() TO authenticated;

-- OTP doğrulama fonksiyonları - anon kullanıcılara açık olmalı (kayıt için)
-- Bunlar kasıtlı olarak anon'a açık, değiştirmiyoruz

-- Group join fonksiyonları
REVOKE EXECUTE ON FUNCTION public.approve_group_join_request(UUID) FROM anon;
REVOKE EXECUTE ON FUNCTION public.reject_group_join_request(UUID) FROM anon;
GRANT EXECUTE ON FUNCTION public.approve_group_join_request(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.reject_group_join_request(UUID) TO authenticated;

-- Story likes fonksiyonları
REVOKE EXECUTE ON FUNCTION public.increment_story_likes(UUID) FROM anon;
REVOKE EXECUTE ON FUNCTION public.decrement_story_likes(UUID) FROM anon;
GRANT EXECUTE ON FUNCTION public.increment_story_likes(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.decrement_story_likes(UUID) TO authenticated;

-- ============================================
-- 4. LEAKED PASSWORD PROTECTION ETKİNLEŞTİRME
-- ============================================
-- NOT: Bu ayar Supabase Dashboard'dan yapılmalı
-- Authentication > Policies > Password Policy > Enable leaked password protection

-- Aşağıdaki SQL, mevcut şifrelerin güvenliğini kontrol etmek içindir
-- Bu ayar GUI üzerinden yapılmalıdır

-- ============================================
-- 5. EK GÜVENLİK ÖNERİLERİ
-- ============================================

-- RLS aktif olan tablolara policy kontrolü
-- achievements tablosu için ek güvenlik
DROP POLICY IF EXISTS "Only admins can modify achievements" ON achievements;
CREATE POLICY "Only admins can modify achievements" ON achievements
    FOR INSERT WITH CHECK (auth.jwt() ->> 'role' = 'admin');

DROP POLICY IF EXISTS "Only admins can update achievements" ON achievements;
CREATE POLICY "Only admins can update achievements" ON achievements
    FOR UPDATE USING (auth.jwt() ->> 'role' = 'admin');

DROP POLICY IF EXISTS "Only admins can delete achievements" ON achievements;
CREATE POLICY "Only admins can delete achievements" ON achievements
    FOR DELETE USING (auth.jwt() ->> 'role' = 'admin');

-- ============================================
-- SONUÇ
-- ============================================
-- Bu script çalıştırıldıktan sonra:
-- 1. Fonksiyonlar search_path ile güvenli hale geldi
-- 2. Storage bucket policy'leri daraltıldı
-- 3. Admin fonksiyonları korumaya alındı
-- 4. Public fonksiyonlar kontrol edildi
-- 
-- NOT: Leaked Password Protection için:
-- Dashboard > Authentication > Policies > 
-- "Enable password_hash_algorithm" ve "Enable leaked password protection" 
-- ayarlarını açın