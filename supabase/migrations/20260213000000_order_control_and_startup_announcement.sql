-- ============================================================================
-- Sipariş Kontrolü ve Açılış Duyurusu Sistemi
-- Tarih: 2026-02-13
-- 
-- 1. Satıcı sipariş alma kontrolü (shops.is_accepting_orders)
-- 2. Admin global sipariş kontrolü (app_about_settings.global_orders_enabled)
-- 3. Uygulama açılışta duyuru sistemi (app_about_settings.startup_announcement_*)
-- ============================================================================

-- 1. SHOPS TABLOSUNA is_accepting_orders KOLONU EKLE
-- Satıcılar kendi mağazaları için sipariş almayı açıp kapatabilir
ALTER TABLE public.shops
  ADD COLUMN IF NOT EXISTS is_accepting_orders BOOLEAN DEFAULT true;

COMMENT ON COLUMN public.shops.is_accepting_orders IS
  'Mağazanın sipariş kabul edip etmediği (satıcı tarafından kontrol edilir)';

-- 2. APP_ABOUT_SETTINGS TABLOSUNA GLOBAL SİPARİŞ KONTROLÜ EKLE
-- Admin tüm satıcılar için sipariş almayı kapatabilir
ALTER TABLE public.app_about_settings
  ADD COLUMN IF NOT EXISTS global_orders_enabled BOOLEAN DEFAULT true;

COMMENT ON COLUMN public.app_about_settings.global_orders_enabled IS
  'Admin tarafından kontrol edilen global sipariş alma durumu (tüm satıcılar için geçerli)';

-- 3. APP_ABOUT_SETTINGS TABLOSUNA AÇILIŞ DUYURUSU ALANLARI EKLE
-- Admin uygulama açılışında kullanıcılara duyuru/bilgilendirme gösterebilir
ALTER TABLE public.app_about_settings
  ADD COLUMN IF NOT EXISTS startup_announcement_enabled BOOLEAN DEFAULT false,
  ADD COLUMN IF NOT EXISTS startup_announcement_title TEXT,
  ADD COLUMN IF NOT EXISTS startup_announcement_message TEXT,
  ADD COLUMN IF NOT EXISTS startup_announcement_type TEXT DEFAULT 'info' CHECK (startup_announcement_type IN ('info', 'warning', 'success', 'error')),
  ADD COLUMN IF NOT EXISTS startup_announcement_button_text TEXT DEFAULT 'Tamam',
  ADD COLUMN IF NOT EXISTS startup_announcement_updated_at TIMESTAMPTZ;

COMMENT ON COLUMN public.app_about_settings.startup_announcement_enabled IS
  'Açılış duyurusunun aktif olup olmadığı';
COMMENT ON COLUMN public.app_about_settings.startup_announcement_title IS
  'Açılış duyurusu başlığı';
COMMENT ON COLUMN public.app_about_settings.startup_announcement_message IS
  'Açılış duyurusu mesajı';
COMMENT ON COLUMN public.app_about_settings.startup_announcement_type IS
  'Duyuru tipi (info, warning, success, error)';
COMMENT ON COLUMN public.app_about_settings.startup_announcement_button_text IS
  'Duyuru kapatma butonu metni';
COMMENT ON COLUMN public.app_about_settings.startup_announcement_updated_at IS
  'Duyurunun son güncellenme tarihi (kullanıcılar tekrar görmesi için)';

-- Varsayılan değerleri ayarla
UPDATE public.app_about_settings
SET
  global_orders_enabled = true,
  startup_announcement_enabled = false
WHERE id = 1;

-- İndeks ekle (performans için)
CREATE INDEX IF NOT EXISTS idx_shops_is_accepting_orders ON public.shops(is_accepting_orders);

-- ============================================================================
-- BAŞARILI MESAJI
-- ============================================================================
DO $$
BEGIN
    RAISE NOTICE '✅ Sipariş kontrolü ve açılış duyurusu sistemi eklendi';
    RAISE NOTICE '   - shops.is_accepting_orders (satıcı sipariş kontrolü)';
    RAISE NOTICE '   - app_about_settings.global_orders_enabled (admin global kontrol)';
    RAISE NOTICE '   - app_about_settings.startup_announcement_* (açılış duyurusu)';
END $$;
