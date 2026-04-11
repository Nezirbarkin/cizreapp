-- ============================================================================
-- ZORUNLU GÜNCELLEME SİSTEMİ
-- ============================================================================
-- Eski versiyonların çalışmasını engellemek için minimum versiyon kontrolü
-- ============================================================================

-- app_about_settings tablosuna minimum versiyon alanları ekle
ALTER TABLE public.app_about_settings
  ADD COLUMN IF NOT EXISTS min_version TEXT DEFAULT '1.1.0',
  ADD COLUMN IF NOT EXISTS min_build_code INT DEFAULT 2,
  ADD COLUMN IF NOT EXISTS force_update_enabled BOOLEAN DEFAULT true,
  ADD COLUMN IF NOT EXISTS current_version TEXT DEFAULT '1.1.0',
  ADD COLUMN IF NOT EXISTS current_build_code INT DEFAULT 2;

COMMENT ON COLUMN public.app_about_settings.min_version IS 
  'Minimum gerekli uygulama versiyonu (örn: 1.1.0)';
COMMENT ON COLUMN public.app_about_settings.min_build_code IS 
  'Minimum gerekli build kodu';
COMMENT ON COLUMN public.app_about_settings.force_update_enabled IS 
  'Zorunlu güncelleme sistemi aktif mi?';
COMMENT ON COLUMN public.app_about_settings.current_version IS 
  'Şu anki uygulama versiyonu';
COMMENT ON COLUMN public.app_about_settings.current_build_code IS 
  'Şu anki build kodu';

-- Varsayılan değerleri güncelle (1.1.0'dan önceki versiyonlar çalışmayacak)
UPDATE public.app_about_settings
SET
  min_version = '1.1.0',
  min_build_code = 2,
  force_update_enabled = true,
  current_version = '1.1.0',
  current_build_code = 2
WHERE id = 1;

-- Mevcut kayıt yoksa oluştur
INSERT INTO public.app_about_settings (
  app_name,
  min_version,
  min_build_code,
  force_update_enabled,
  current_version,
  current_build_code
)
SELECT
  'CizreApp',
  '1.1.0',
  2,
  true,
  '1.1.0',
  2
WHERE NOT EXISTS (SELECT 1 FROM public.app_about_settings);

-- Versiyon karşılaştırma fonksiyonu
CREATE OR REPLACE FUNCTION check_app_version(
  p_current_version TEXT,
  p_current_build_code INT DEFAULT 0
)
RETURNS JSONB AS $$
DECLARE
  v_settings RECORD;
  v_needs_update BOOLEAN := false;
  v_is_forced BOOLEAN := false;
  v_min_version TEXT;
  v_current_version TEXT;
BEGIN
  -- Ayarları al
  SELECT * INTO v_settings
  FROM public.app_about_settings
  LIMIT 1;
  
  IF NOT FOUND THEN
    -- Ayar yoksa varsayılan olarak geçti say
    RETURN jsonb_build_object(
      'needs_update', false,
      'is_forced', false,
      'message', 'Versiyon kontrolü başarılı'
    );
  END IF;
  
  -- Zorunlu güncelleme kapalıysa geç
  IF NOT COALESCE(v_settings.force_update_enabled, false) THEN
    RETURN jsonb_build_object(
      'needs_update', false,
      'is_forced', false,
      'message', 'Zorunlu güncelleme pasif'
    );
  END IF;
  
  -- Minimum versiyon kontrolü
  v_min_version := COALESCE(v_settings.min_version, '0.0.0');
  v_current_version := COALESCE(v_settings.current_version, '1.0.0');
  
  -- Basit versiyon karşılaştırma (major.minor.patch)
  -- Eski versiyon daha küçükse güncelleme gerekli
  IF p_current_version < v_min_version THEN
    v_needs_update := true;
    v_is_forced := true;
  ELSIF p_current_version = v_min_version AND p_current_build_code < COALESCE(v_settings.min_build_code, 0) THEN
    v_needs_update := true;
    v_is_forced := true;
  END IF;
  
  RETURN jsonb_build_object(
    'needs_update', v_needs_update,
    'is_forced', v_is_forced,
    'min_version', v_min_version,
    'current_version', v_current_version,
    'message', CASE 
      WHEN v_needs_update AND v_is_forced THEN 
        'Uygulamanızı güncellemeniz gerekiyor. Yeni sürüm kullanıma sunulmuştur.'
      ELSE 'Versiyon güncel'
    END
  );
END;
$$ LANGUAGE plpgsql;

DO $$
BEGIN
    RAISE NOTICE '================================================================';
    RAISE NOTICE 'ZORUNLU GÜNCELLEME SİSTEMİ EKLENDİ!';
    RAISE NOTICE '================================================================';
    RAISE NOTICE 'app_about_settings tablosuna eklendi:';
    RAISE NOTICE '   - min_version (minimum versiyon)';
    RAISE NOTICE '   - min_build_code (minimum build kodu)';
    RAISE NOTICE '   - force_update_enabled (zorunlu güncelleme açık/kapalı)';
    RAISE NOTICE '   - current_version (şu anki versiyon)';
    RAISE NOTICE '   - current_build_code (şu anki build kodu)';
    RAISE NOTICE '================================================================';
    RAISE NOTICE 'check_app_version() fonksiyonu eklendi';
    RAISE NOTICE 'Minimum versiyon: 1.1.0 (build 2)';
    RAISE NOTICE '1.0.0 ve önceki versiyonlar çalışmayacak!';
    RAISE NOTICE '================================================================';
END $$;
