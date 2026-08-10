-- =============================================================================
-- Şehiriçi: Şoför ayarı — "Rotamı gittiğim yerlerden oluştur"
-- Tarih: 2026-08-07
-- Amaç: Bir hattın admin tarafından çizilmiş `route_polyline` rotası yoksa
-- ve şoför bu ayarı açtıysa, ilk sefer başlangıcından ~1 km sonra GPS
-- noktalarından otomatik rota oluşturup `route_polyline` olarak kaydeder.
-- DEFAULT FALSE: geriye dönük uyumluluk, mevcut şoförler etkilenmez.
-- =============================================================================

ALTER TABLE public.sehirici_drivers
  ADD COLUMN IF NOT EXISTS auto_route_from_traveled_path BOOLEAN
  NOT NULL DEFAULT FALSE;

COMMENT ON COLUMN public.sehirici_drivers.auto_route_from_traveled_path IS
  'true ise ve hattın admin tarafından kayıtlı route_polyline rotası yoksa, '
  'şoförün sefer başlangıcından itibaren toplanan GPS noktalarından otomatik '
  'olarak rota oluşturulur (Douglas-Peucker sadeleştirilir) ve hat için '
  'route_polyline olarak kaydedilir.';
