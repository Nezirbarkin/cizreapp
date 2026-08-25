-- 2026-08-25 — sehirici_trip_locations_backup_20260819 için RLS açığını kapat
--
-- SORUN: Supabase linter "RLS Disabled in Public" uyarısı verdi. Kontrol
-- edilince tablo üzerinde RLS kapalıyken `anon` ve `authenticated` rollerine
-- SELECT/INSERT yetkisi verilmiş olduğu görüldü — yani şoför konum geçmişi
-- (lat/lng/heading/speed, 138 satır) PostgREST üzerinden herkese açıktı.
-- Bu tablo 19 Ağustos'taki temizlik öncesi alınmış geçici bir yedek, uygulama
-- tarafından kullanılmıyor.
--
-- ÇÖZÜM: anon/authenticated yetkilerini kaldır, RLS'yi politika eklemeden
-- aç (yalnız postgres/service_role erişebilsin).

REVOKE ALL ON TABLE public.sehirici_trip_locations_backup_20260819 FROM anon, authenticated;

ALTER TABLE public.sehirici_trip_locations_backup_20260819 ENABLE ROW LEVEL SECURITY;
