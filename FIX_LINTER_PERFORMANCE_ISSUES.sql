-- ============================================
-- SUPABASE LINTER PERFORMANS DÜZELTMELERİ (Basitleştirilmiş)
-- ============================================

-- ============================================
-- 1. AUTH RLS INITPLAN DÜZELTMELERİ
-- ============================================
-- auth.uid() ve auth.jwt() fonksiyonlarını (select ...) ile sarmala

-- posts tablosu - DELETE policy
DROP POLICY IF EXISTS "Users can delete own posts or admins can delete any" ON posts;
CREATE POLICY "posts_delete_policy" ON posts
    FOR DELETE TO authenticated
    USING (
        user_id = (select auth.uid())
        OR (select auth.jwt() ->> 'role') = 'admin'
    );

-- messages tablosu - UPDATE policy
DROP POLICY IF EXISTS "messages_update_unified" ON messages;
CREATE POLICY "messages_update_unified" ON messages
    FOR UPDATE TO authenticated
    USING (
        sender_id = (select auth.uid())
    );

-- ============================================
-- 2. MULTIPLE PERMISSIVE POLICIES DÜZELTMELERİ
-- ============================================
-- post_reports - SELECT policy'lerini birleştir

-- Mevcut policy'leri temizle
DROP POLICY IF EXISTS "post_reports_select_admin" ON post_reports;
DROP POLICY IF EXISTS "post_reports_select_own" ON post_reports;
DROP POLICY IF EXISTS "post_reports_select_auth" ON post_reports;
DROP POLICY IF EXISTS "post_reports_select_anon" ON post_reports;

-- post_reports - anon rolü için
CREATE POLICY "post_reports_select_anon" ON post_reports
    FOR SELECT TO anon
    USING (true);

-- post_reports - authenticated rolü için (admin veya kendi)
CREATE POLICY "post_reports_select_auth" ON post_reports
    FOR SELECT TO authenticated
    USING (
        reporter_id = (select auth.uid())
        OR (select auth.jwt() ->> 'role') = 'admin'
    );

-- ============================================
-- 3. ANALYZE TABLES
-- ============================================
ANALYZE posts;
ANALYZE messages;
ANALYZE post_reports;

-- ============================================
-- NOT: Aşağıdaki tablolar için policy'ler zaten mevcut
-- ve Supabase Dashboard'dan yönetilmeli:
-- - addresses
-- - achievements  
-- - user_achievements
-- - user_unlocked_achievements
--
-- Bu tablolardaki policy'leri düzeltmek için:
-- 1. Supabase Dashboard > Table Editor > [tablo]
-- 2. Policies sekmesine git
-- 3. Mevcut policy'leri sil
-- 4. Yeni policy oluştur
--
-- Örnek: user_achievements
-- CREATE POLICY "user_achievements_select" ON user_achievements
--     FOR SELECT TO authenticated
--     USING (user_id = (select auth.uid()));

-- ============================================
-- SONUÇ
-- ============================================
-- Bu script çalıştırıldıktan sonra:
-- 1. posts ve messages tabloları için auth.uid() düzeltildi
-- 2. post_reports policy'leri birleştirildi
-- 3. ANALYZE çalıştırıldı
--
-- NOT: addresses, achievements ve user_achievements tabloları için
-- Supabase Dashboard üzerinden policy'leri manuel olarak güncelleyin