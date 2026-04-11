-- =====================================================
-- DESTEK MERKEZİ VE HAKKINDA - MİSAFİR ERİŞİMİ
-- Misafir kullanıcılar için SSS ve hakkında bilgilerini görüntüleme
-- =====================================================

-- 1) FAQs (Sıkça Sorulan Sorular) - Misafir erişimi
-- Mevcut politikayı kaldır
DROP POLICY IF EXISTS "Herkes aktif SSS'leri görebilir" ON public.faqs;

-- Yeni politika: authenticated yerine anon (misafir)
CREATE POLICY "Herkes aktif SSS'leri görebilir (misafir dahil)"
  ON public.faqs FOR SELECT
  USING (is_active = true);

-- 2) app_about_settings (Hakkında Ayarları) - Misafir erişimi
-- Mevcut politikayı kaldır
DROP POLICY IF EXISTS "app_about_settings_select_policy" ON public.app_about_settings;
DROP POLICY IF EXISTS "Herkes okuyabilir" ON public.app_about_settings;

-- Yeni politika: Herkes (misafir dahil) okuyabilir
CREATE POLICY "Herkes hakkında bilgilerini okuyabilir (misafir dahil)"
  ON public.app_about_settings FOR SELECT
  USING (true);

-- 3) support_tickets - Sadece authenticated kullanıcılar talep oluşturabilir (değişiklik yok)
-- Misafirler destek talebi oluşturamaz, sadece SSS görebilir

-- =====================================================
-- SONUÇ
-- =====================================================
-- ✅ Misafir kullanıcılar SSS'leri görebilir
-- ✅ Misafir kullanıcılar hakkında bilgilerini görebilir
-- ❌ Misafir kullanıcılar destek talebi oluşturamaz (giriş yapmaları gerekir)
