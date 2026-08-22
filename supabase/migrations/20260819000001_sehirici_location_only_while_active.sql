-- =============================================================================
-- Şehiriçi: konum geçmişi yalnızca sefer AKTİF iken yazılsın
-- Tarih: 2026-08-19
-- =============================================================================
-- KÖK NEDEN
--   update_sehirici_trip_location (20260725000001_sehirici_services.sql, 5.5)
--   sefer satırını `WHERE id = p_trip_id AND status = 'active'` koşuluyla
--   güncelliyordu — yani "Mola"daki (paused) seferde araç konumu doğru şekilde
--   DONDURULUYORDU. Ancak hemen ardından gelen
--
--     INSERT INTO public.sehirici_trip_locations ...
--
--   KOŞULSUZDU. Sonuç: şoför molaya çıkıp konum paylaşımını duraklattığında
--   bile, cihaz arka planda konum yazmaya devam ettiği sürece konum GEÇMİŞİ
--   dolmaya devam ediyordu. Bunun iki somut etkisi var:
--
--     1) get_sehirici_trip_path (20260729000003) bu geçmişi döndürüyor ve
--        SehiriciLiveMap aracın arkasına "geçtiği yol" polyline'ı olarak
--        çiziyor. Molada park hâlindeki araç, GPS gezinmesi (drift) yüzünden
--        durduğu noktada bir yumak çiziyordu.
--     2) Şoför panelindeki "Rotamı gittiğim yerlerden oluştur" özelliği
--        (_checkAutoRoute -> matchDrivenPath -> cacheRoutePolyline) aynı
--        geçmişi girdi olarak alıyor; mola noktaları hattın kalıcı rotasına
--        karışıyordu.
--
-- ÇÖZÜM
--   Trip UPDATE'i ile INSERT'ü tek koşula bağla: satır gerçekten 'active'
--   iken güncellendiyse geçmişe de yaz, aksi hâlde sessizce yok say
--   (istemciye hata dönmez — tracker akışı bozulmasın).
--
-- KAPSAM: yalnız bu fonksiyonun gövdesi. İmza, yetki kontrolü, GRANT'lar ve
--   çağıran istemci kodu değişmiyor.
-- =============================================================================

BEGIN;

CREATE OR REPLACE FUNCTION public.update_sehirici_trip_location(
  p_trip_id UUID,
  p_lat DOUBLE PRECISION,
  p_lng DOUBLE PRECISION,
  p_heading REAL DEFAULT NULL,
  p_speed REAL DEFAULT NULL,
  p_passenger_count INTEGER DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_driver_profile UUID;
  v_updated        BOOLEAN := FALSE;
BEGIN
  -- Yetki kontrolü (değişmedi)
  SELECT d.profile_id INTO v_driver_profile
  FROM public.sehirici_trips t
  JOIN public.sehirici_drivers d ON t.driver_id = d.id
  WHERE t.id = p_trip_id;

  IF v_driver_profile IS NULL OR v_driver_profile != auth.uid() THEN
    RAISE EXCEPTION 'Bu sefer için yetkiniz yok';
  END IF;

  -- Trip güncelle — yalnız aktif seferde.
  UPDATE public.sehirici_trips
  SET current_lat = p_lat,
      current_lng = p_lng,
      current_heading = COALESCE(p_heading, current_heading),
      current_speed = COALESCE(p_speed, current_speed),
      passenger_count = COALESCE(p_passenger_count, passenger_count),
      updated_at = now()
  WHERE id = p_trip_id AND status = 'active'
  RETURNING TRUE INTO v_updated;

  -- Konum geçmişi: SADECE yukarıdaki güncelleme gerçekleştiyse.
  -- (Mola/bitmiş seferde geçmiş kirletilmez.)
  IF COALESCE(v_updated, FALSE) THEN
    INSERT INTO public.sehirici_trip_locations (trip_id, lat, lng, heading, speed)
    VALUES (p_trip_id, p_lat, p_lng, p_heading, p_speed);
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION public.update_sehirici_trip_location(
  UUID, DOUBLE PRECISION, DOUBLE PRECISION, REAL, REAL, INTEGER
) TO authenticated;

NOTIFY pgrst, 'reload schema';

COMMIT;
