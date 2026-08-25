-- 2026-08-24 — Şehiriçi sefer konum geçmişi için temizlik cron'u
--
-- SORUN: `cleanup_sehirici_old_locations` fonksiyonu 20260725000001'de
-- "(cron çağırır)" notuyla oluşturulmuş, ancak hiçbir migration onu pg_cron'a
-- BAĞLAMAMIŞ. Sonuç: `sehirici_trip_locations` tablosundaki şoför konum
-- geçmişi 25 Temmuz'dan beri hiç temizlenmedi; tablo yorumu ve gizlilik
-- taahhüdü "max 1 saat" derken kayıtlar süresiz birikiyordu.
--
-- Bu yalnız bir depolama sorunu değil: konum, Google Play ve KVKK açısından
-- hassas kişisel veridir ve gizlilik politikasında beyan edilen saklama
-- süresinin gerçekte uygulanıyor olması gerekir.
--
-- ÇÖZÜM: fonksiyonu saatlik cron'a bağla. Varsayılan p_keep_minutes=60,
-- yani canlı takip için gereken son 1 saatlik iz tutulur, gerisi silinir.
-- Sefer özeti (`sehirici_trips`) bu temizlikten etkilenmez; silinen yalnız
-- 10 saniyelik ham konum örnekleridir.

DO $$
BEGIN
  -- Eski job varsa kaldır (idempotent).
  PERFORM cron.unschedule('cleanup-sehirici-locations-hourly')
  WHERE EXISTS (
    SELECT 1 FROM cron.job WHERE jobname = 'cleanup-sehirici-locations-hourly'
  );

  PERFORM cron.schedule(
    'cleanup-sehirici-locations-hourly',
    '7 * * * *',
    $cron$ SELECT public.cleanup_sehirici_old_locations(60); $cron$
  );
END;
$$;

COMMENT ON FUNCTION public.cleanup_sehirici_old_locations(INTEGER) IS
  '1 saatten eski ham sefer konum örneklerini siler; cleanup-sehirici-locations-hourly pg_cron job''ı saat başı 7. dakikada çağırır.';

-- Cron kurulmadan önce birikmiş geçmişi bir kez şimdi temizle.
SELECT public.cleanup_sehirici_old_locations(60) AS silinen_eski_kayit;

SELECT jobname, schedule, active
FROM cron.job
WHERE jobname = 'cleanup-sehirici-locations-hourly';
