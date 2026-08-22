-- =============================================================================
-- Şehiriçi: konum GEÇMİŞİNE yalnızca gerçek hareket yazılsın
-- Tarih: 2026-08-19
-- =============================================================================
-- KÖK NEDEN
--   update_sehirici_trip_location, sefer 'active' olduğu sürece gelen HER
--   konumu sehirici_trip_locations'a yazıyor (10 sn'de bir). Araç durakta,
--   kırmızı ışıkta veya son yolcusunu beklerken hareket etmiyor ama GPS
--   gezinmesi (drift) devam ediyor: aynı 20-50 m'lik alanda dakikada 6, saatte
--   360 nokta birikiyor.
--
--   Bu geçmiş SehiriciLiveMap'te aracın arkasındaki "geçtiği yol" polyline'ı
--   olarak çizildiği için, harita üzerinde durduğu noktada birbirine dolanmış
--   yüzlerce kısa çizgiden oluşan bir yumak ("karalama") oluşuyordu.
--
--   20260819000001 molada yazmayı kesmişti; bu migration aktif seferdeki
--   duruşları da kapsıyor — şoför her duruşta molaya çıkmıyor.
--
-- ÇÖZÜM
--   Geçmişe yazmadan önce seferin SON kayıtlı noktasına olan mesafeye bak;
--   15 m'den yakınsa yazma. Eşik, tipik şehir içi GPS gezinmesinin (5-15 m)
--   hemen üstünde, en yavaş gerçek hareketin altında.
--
--   Mesafe equirectangular yaklaşımıyla hesaplanır: şehir içi ölçekte (< 10 km)
--   haversine'den sapması santimetre mertebesinde, maliyeti ise çok daha düşük.
--
-- KAPSAM
--   Yalnız geçmiş INSERT'i. sehirici_trips satırının UPDATE'i DEĞİŞMEDİ: araç
--   dururken de current_lat/current_lng/updated_at tazelenmeye devam eder,
--   yani haritadaki araç marker'ı ve "canlı" durumu etkilenmez. İmza, yetki
--   kontrolü, GRANT'lar ve çağıran istemci kodu da değişmiyor.
--
--   Okuma tarafı zaten idx_sehirici_trip_locations_trip (trip_id, recorded_at
--   DESC) indeksinden karşılanıyor — ek indeks gerekmiyor.
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
  v_last_lat       DOUBLE PRECISION;
  v_last_lng       DOUBLE PRECISION;
  v_meters         DOUBLE PRECISION;
  -- Duruş gezinmesi ile gerçek hareketi ayıran eşik (metre).
  c_min_move       CONSTANT DOUBLE PRECISION := 15.0;
BEGIN
  -- Yetki kontrolü (değişmedi)
  SELECT d.profile_id INTO v_driver_profile
  FROM public.sehirici_trips t
  JOIN public.sehirici_drivers d ON t.driver_id = d.id
  WHERE t.id = p_trip_id;

  IF v_driver_profile IS NULL OR v_driver_profile != auth.uid() THEN
    RAISE EXCEPTION 'Bu sefer için yetkiniz yok';
  END IF;

  -- Geçersiz koordinat: sessizce yok say (istemci akışı bozulmasın).
  IF p_lat IS NULL OR p_lng IS NULL
     OR p_lat < -90 OR p_lat > 90
     OR p_lng < -180 OR p_lng > 180 THEN
    RETURN;
  END IF;

  -- Trip güncelle — yalnız aktif seferde. (Araç dursa da tazelenir.)
  UPDATE public.sehirici_trips
  SET current_lat = p_lat,
      current_lng = p_lng,
      current_heading = COALESCE(p_heading, current_heading),
      current_speed = COALESCE(p_speed, current_speed),
      passenger_count = COALESCE(p_passenger_count, passenger_count),
      updated_at = now()
  WHERE id = p_trip_id AND status = 'active'
  RETURNING TRUE INTO v_updated;

  IF NOT COALESCE(v_updated, FALSE) THEN
    -- Mola/bitmiş sefer: geçmiş kirletilmez (20260819000001).
    RETURN;
  END IF;

  -- Bu seferin son kayıtlı noktası.
  SELECT lat, lng INTO v_last_lat, v_last_lng
  FROM public.sehirici_trip_locations
  WHERE trip_id = p_trip_id
  ORDER BY recorded_at DESC, id DESC
  LIMIT 1;

  IF v_last_lat IS NOT NULL THEN
    v_meters := 111320.0 * sqrt(
      power(p_lat - v_last_lat, 2) +
      power((p_lng - v_last_lng) * cos(radians(p_lat)), 2)
    );
    IF v_meters < c_min_move THEN
      RETURN; -- duruş gezinmesi: geçmişe yazma
    END IF;
  END IF;

  INSERT INTO public.sehirici_trip_locations (trip_id, lat, lng, heading, speed)
  VALUES (p_trip_id, p_lat, p_lng, p_heading, p_speed);
END;
$$;

GRANT EXECUTE ON FUNCTION public.update_sehirici_trip_location(
  UUID, DOUBLE PRECISION, DOUBLE PRECISION, REAL, REAL, INTEGER
) TO authenticated;

NOTIFY pgrst, 'reload schema';

COMMIT;
