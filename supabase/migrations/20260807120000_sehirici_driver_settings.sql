-- =============================================================================
-- 20260807120000_sehirici_driver_settings.sql
-- Şöför ayarları: çalışma saatleri + otomatik konum kapatma
-- =============================================================================
-- Bu migration sehirici_drivers tablosuna 3 sütun ekler:
--   - working_hours_start TEXT (HH:mm) — günlük çalışma başlangıç saati
--   - working_hours_end   TEXT (HH:mm) — günlük çalışma bitiş saati
--   - auto_location_enabled BOOLEAN     — çalışma saatleri dışında konum paylaşımını otomatik durdur
--
-- CHECK constraint'ler HH:mm formatını doğrular (24 saat).
-- Mevcut şoförler için tüm alanlar NULL/TRUE olur (geriye uyumlu).
-- =============================================================================

ALTER TABLE public.sehirici_drivers
  ADD COLUMN IF NOT EXISTS working_hours_start TEXT,
  ADD COLUMN IF NOT EXISTS working_hours_end   TEXT,
  ADD COLUMN IF NOT EXISTS auto_location_enabled BOOLEAN NOT NULL DEFAULT TRUE;

-- HH:mm format doğrulama (00:00 - 23:59). NULL değer kabul edilir (şoför ayar yapmamış olabilir).
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'sehirici_drivers_working_hours_start_format'
  ) THEN
    ALTER TABLE public.sehirici_drivers
      ADD CONSTRAINT sehirici_drivers_working_hours_start_format
      CHECK (working_hours_start IS NULL OR working_hours_start ~ '^[0-2][0-9]:[0-5][0-9]$');
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'sehirici_drivers_working_hours_end_format'
  ) THEN
    ALTER TABLE public.sehirici_drivers
      ADD CONSTRAINT sehirici_drivers_working_hours_end_format
      CHECK (working_hours_end IS NULL OR working_hours_end ~ '^[0-2][0-9]:[0-5][0-9]$');
  END IF;
END$$;

COMMENT ON COLUMN public.sehirici_drivers.working_hours_start
  IS 'Şoförün günlük çalışma başlangıç saati (HH:mm, 24 saat)';
COMMENT ON COLUMN public.sehirici_drivers.working_hours_end
  IS 'Şoförün günlük çalışma bitiş saati (HH:mm, 24 saat)';
COMMENT ON COLUMN public.sehirici_drivers.auto_location_enabled
  IS 'Çalışma saatleri dışında konum paylaşımını otomatik durdur';

-- RLS notu: Mevcut sehirici_drivers_update_self policy'si sadece kendi satırında
-- UPDATE yapabilir. Yeni sütunlar bu policy kapsamında otomatik olarak güncellenebilir.
-- Ek policy değişikliği gerekmez.
