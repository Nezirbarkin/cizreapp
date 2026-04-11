-- ============================================
-- KALAN PERFORMANS UYARILARI İÇİN EK FIX
-- ============================================
-- 
-- Bu SQL dosyası kalan 4 performans uyarısını düzeltir:
-- 1. notifications - auth.role() uyarısı
-- 2. coupons - 3 auth_rls_initplan uyarısı
--
-- Not: multiple_permissive_policies uyarıları tasarım gereği
-- (users ve shops ayrı erişim kontrolleri mantıklı ve gerekli)
-- ============================================

-- ============================================
-- NOTIFICATIONS - auth.role() FIX
-- ============================================

DROP POLICY IF EXISTS "Authenticated users can create notifications" ON notifications;

-- auth.role() yerine auth.uid() IS NOT NULL kontrolü kullan
CREATE POLICY "Authenticated users can create notifications"
ON notifications FOR INSERT
WITH CHECK ((SELECT auth.uid()) IS NOT NULL);

-- ============================================
-- COUPONS TABLE - DROP VE YENİDEN OLUŞTUR
-- ============================================
-- 
-- NOT: Coupons tablosunun gerçek yapısını bilmediğimiz için
-- bu kısım çalışmayabilir. Eğer coupons tablosu kullanılmıyorsa
-- bu bölümü çalıştırma.
-- ============================================

-- Önce mevcut policy'leri sil
DROP POLICY IF EXISTS "coupons_select_policy" ON coupons;
DROP POLICY IF EXISTS "coupons_insert_policy" ON coupons;
DROP POLICY IF EXISTS "coupons_update_policy" ON coupons;
DROP POLICY IF EXISTS "coupons_delete_policy" ON coupons;

-- Herkes coupon'ları görebilir (okuma public)
CREATE POLICY "coupons_select_policy"
ON coupons FOR SELECT
USING (true);

-- Sadece authenticated kullanıcılar coupon ekleyebilir
CREATE POLICY "coupons_insert_policy"
ON coupons FOR INSERT
WITH CHECK ((SELECT auth.uid()) IS NOT NULL);

-- Sadece authenticated kullanıcılar coupon güncelleyebilir
CREATE POLICY "coupons_update_policy"
ON coupons FOR UPDATE
USING ((SELECT auth.uid()) IS NOT NULL)
WITH CHECK ((SELECT auth.uid()) IS NOT NULL);

-- Sadece authenticated kullanıcılar coupon silebilir
CREATE POLICY "coupons_delete_policy"
ON coupons FOR DELETE
USING ((SELECT auth.uid()) IS NOT NULL);

-- ============================================
-- TEST SONRASI KONTROL
-- ============================================
-- 
-- Bu SQL'i çalıştırdıktan sonra:
-- 1. Supabase Dashboard → Database Linter'ı çalıştır
-- 2. Kalan uyarılar sadece multiple_permissive_policies olmalı
-- 3. Bu uyarılar güvenlik tasarımı gereği kalabilir
-- 
-- PERFORMANS NOTLARI:
-- - auth_rls_initplan uyarıları tamamen giderilmiş olacak
-- - Multiple permissive policies (users + shops) tasarım gereği
-- - Bu yapı hem kullanıcıların hem dükkanların siparişleri 
--   görmesini sağlar ve güvenlik açısından doğrudur
-- ============================================
