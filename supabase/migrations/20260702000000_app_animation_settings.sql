-- ============================================================
-- App Animation Settings Migration
-- Tarih: 2026-07-02
-- Açıklama: app_about_settings tablosuna animasyon süresi
--           ayarları için yeni kolonlar eklenir.
-- "Her an her kapıda" sloganı + animasyon süreleri admin
-- panelden saniyesine kadar özelleştirilebilir olur.
-- ============================================================

-- Animasyon süre ayarları (milisaniye cinsinden)
ALTER TABLE public.app_about_settings
  ADD COLUMN IF NOT EXISTS animation_primary_duration_ms INTEGER NOT NULL DEFAULT 6000,
  ADD COLUMN IF NOT EXISTS animation_secondary_duration_ms INTEGER NOT NULL DEFAULT 3000,
  ADD COLUMN IF NOT EXISTS animation_transition_duration_ms INTEGER NOT NULL DEFAULT 700;

-- Kolon kısıtlamaları: negatif veya absürt değerlere karşı koruma
ALTER TABLE public.app_about_settings
  ADD CONSTRAINT app_about_settings_animation_primary_duration_range
    CHECK (animation_primary_duration_ms BETWEEN 1000 AND 30000),
  ADD CONSTRAINT app_about_settings_animation_secondary_duration_range
    CHECK (animation_secondary_duration_ms BETWEEN 500 AND 15000),
  ADD CONSTRAINT app_about_settings_animation_transition_duration_range
    CHECK (animation_transition_duration_ms BETWEEN 100 AND 3000);

-- Kolon açıklamaları
COMMENT ON COLUMN public.app_about_settings.animation_primary_duration_ms IS
  'Birincil metnin (CizreApp) ekranda görünür kalma süresi (ms). Varsayılan: 6000';
COMMENT ON COLUMN public.app_about_settings.animation_secondary_duration_ms IS
  'İkincil metnin (slogan) ekranda görünür kalma süresi (ms). Varsayılan: 3000';
COMMENT ON COLUMN public.app_about_settings.animation_transition_duration_ms IS
  'Geçiş animasyonunun süresi (ms). Varsayılan: 700';
