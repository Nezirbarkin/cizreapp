-- =============================================================================
-- 20260810120000_sehirici_auto_trip_setting.sql
-- Şoför paneli tam otomasyonu: "Otomatik Sefer" ayarı
-- =============================================================================
-- sehirici_drivers tablosuna 1 sütun ekler:
--   - auto_trip_enabled BOOLEAN NOT NULL DEFAULT FALSE
--
-- Açıksa: uygulama GPS'i arka planda izler ve
--   (çalışma saati + hareket + hat bölgesi) koşulları sağlanınca
--   seferi OTOMATİK başlatır; çalışma saati bitince OTOMATİK bitirir.
-- Şoför manuel "Başlat"/"Bitir" ile her zaman override edebilir.
--
-- RLS: mevcut sehirici_drivers_update_self policy'si (profile_id = auth.uid())
-- bu sütunu da kapsar — ek policy gerekmez. 20260807120000 ile aynı desen.
-- =============================================================================

ALTER TABLE public.sehirici_drivers
  ADD COLUMN IF NOT EXISTS auto_trip_enabled BOOLEAN NOT NULL DEFAULT FALSE;

COMMENT ON COLUMN public.sehirici_drivers.auto_trip_enabled
  IS 'Açıksa seferler GPS/çalışma saati/hat bölgesi sinyallerine göre otomatik başlar ve biter';
