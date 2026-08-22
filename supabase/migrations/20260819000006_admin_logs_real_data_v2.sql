-- Admin > Loglar ekranini gercek veri kaynaklarina baglar.
--
-- Tespit edilen sorunlar (canli DB uzerinde dogrulandi: app_analytics_events
-- icindeki 391 satirin tamami event_type='feed_load', hicbirinde entity_id
-- veya duration_ms yok):
--   1) "En Cok Goruntulenen Icerikler" kartı app_analytics_events icindeki
--      'post_view' eventlerini okuyordu ama o event hicbir zaman yazilmiyor.
--      Gercek goruntulemeler public.post_views tablosunda (241 satir).
--      Kart artik oradan beslenir ve UUID yerine gonderi onizlemesi gosterir.
--   2) Gun siniri UTC hesaplaniyordu; uygulama TR saatinde calistigi icin
--      "Gunluk Aktif Kullanici" ve "Bugun Yeni Kayit" her gun 03:00'te
--      sifirlaniyordu. Europe/Istanbul'a cevrildi.
--   3) Saatlik dagilim / hata dagilimi / ortalama sure tum tabloyu tariyordu:
--      hem "tum zamanlarin saatlik dagilimi" anlamsizdi hem de tablo buyudukce
--      sorgu yavasliyordu. p_window_days penceresi eklendi.

DROP FUNCTION IF EXISTS public.admin_logs_data(integer, integer, integer);

CREATE OR REPLACE FUNCTION public.admin_logs_data(
  p_recent_user_limit integer DEFAULT 20,
  p_error_limit integer DEFAULT 20,
  p_most_viewed_limit integer DEFAULT 5,
  p_window_days integer DEFAULT 30
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_now timestamptz := now();
  -- Gun siniri kullanicinin yasadigi saat diliminde olmali; saatlik dagilim da
  -- ayni dilimi kullaniyor, ikisi artik tutarli.
  v_today_start timestamptz :=
    date_trunc('day', v_now AT TIME ZONE 'Europe/Istanbul') AT TIME ZONE 'Europe/Istanbul';
  v_recent_user_limit integer := LEAST(GREATEST(COALESCE(p_recent_user_limit, 20), 1), 200);
  v_error_limit integer := LEAST(GREATEST(COALESCE(p_error_limit, 20), 1), 200);
  v_most_viewed_limit integer := LEAST(GREATEST(COALESCE(p_most_viewed_limit, 5), 1), 50);
  v_window_days integer := LEAST(GREATEST(COALESCE(p_window_days, 30), 1), 365);
  v_window_start timestamptz;
BEGIN
  IF NOT private.current_user_is_admin() THEN
    RAISE EXCEPTION 'admin_logs_data: not admin' USING ERRCODE = '42501';
  END IF;

  v_window_start := v_now - (v_window_days * interval '1 day');

  RETURN jsonb_build_object(
    'windowDays', v_window_days,
    'online', (SELECT count(*) FROM public.profiles WHERE last_seen >= v_now - interval '5 minutes'),
    'dau', (SELECT count(*) FROM public.profiles WHERE last_seen >= v_today_start),
    'wau', (SELECT count(*) FROM public.profiles WHERE last_seen >= v_now - interval '7 days'),
    'mau', (SELECT count(*) FROM public.profiles WHERE last_seen >= v_now - interval '30 days'),
    'totalUsers', (SELECT count(*) FROM public.profiles),
    'newToday', (SELECT count(*) FROM public.profiles WHERE created_at >= v_today_start),
    'inactive', (SELECT count(*) FROM public.profiles WHERE last_seen IS NULL OR last_seen < v_now - interval '30 days'),
    'totalEvents', (SELECT count(*) FROM public.app_analytics_events),
    'windowEvents', (
      SELECT count(*) FROM public.app_analytics_events WHERE created_at >= v_window_start
    ),
    -- Etkinlik tipi kirilimi: hangi olcumun gercekten toplandigini adminin
    -- gorebilmesi icin. Bos cikan bir kart ile hic yazilmayan bir event
    -- arasindaki farki ancak bu ayirt ettiriyor.
    'eventTypeCounts', COALESCE((
      SELECT jsonb_object_agg(event_type, event_count)
      FROM (
        SELECT event_type, count(*) AS event_count
        FROM public.app_analytics_events
        WHERE created_at >= v_window_start
        GROUP BY event_type
      ) AS type_counts
    ), '{}'::jsonb),
    'avgViewDuration', COALESCE((
      SELECT round(avg(duration_ms))::bigint
      FROM public.app_analytics_events
      WHERE event_type = 'post_view'
        AND duration_ms IS NOT NULL
        AND created_at >= v_window_start
    ), 0),
    'errorCount', (
      SELECT count(*) FROM public.app_analytics_events
      WHERE event_type = 'error' AND created_at >= v_window_start
    ),
    'recentUsers', COALESCE((
      SELECT jsonb_agg(to_jsonb(u) ORDER BY u.last_seen DESC NULLS LAST)
      FROM (
        SELECT id, username, full_name, avatar_url,
               (last_seen >= v_now - interval '5 minutes') AS is_online,
               last_seen
        FROM public.profiles
        ORDER BY last_seen DESC NULLS LAST
        LIMIT v_recent_user_limit
      ) AS u
    ), '[]'::jsonb),
    'errors', COALESCE((
      SELECT jsonb_agg(to_jsonb(e) ORDER BY e.created_at DESC)
      FROM (
        SELECT id, event_type, entity_id, metadata, duration_ms, created_at
        FROM public.app_analytics_events
        WHERE event_type = 'error' AND created_at >= v_window_start
        ORDER BY created_at DESC
        LIMIT v_error_limit
      ) AS e
    ), '[]'::jsonb),
    'errorTypeCounts', COALESCE((
      SELECT jsonb_object_agg(error_type, event_count)
      FROM (
        SELECT COALESCE(NULLIF(metadata ->> 'type', ''), 'Bilinmeyen') AS error_type,
               count(*) AS event_count
        FROM public.app_analytics_events
        WHERE event_type = 'error' AND created_at >= v_window_start
        GROUP BY 1
      ) AS error_counts
    ), '{}'::jsonb),
    'hourlyDistribution', COALESCE((
      SELECT jsonb_object_agg(event_hour::text, event_count)
      FROM (
        SELECT extract(hour FROM created_at AT TIME ZONE 'Europe/Istanbul')::integer AS event_hour,
               count(*) AS event_count
        FROM public.app_analytics_events
        WHERE created_at >= v_window_start
        GROUP BY 1
      ) AS hourly
    ), '{}'::jsonb),
    'postViewCount', (
      SELECT count(*) FROM public.post_views WHERE viewed_at >= v_window_start
    ),
    -- Gercek goruntuleme kaynagi post_views. UUID yerine okunabilir bir etiket
    -- dondurulur; ayni icerige sahip iki gonderi de ayri satir kalsin diye
    -- sonuc obje degil dizi.
    'mostViewedPosts', COALESCE((
      SELECT jsonb_agg(
               jsonb_build_object(
                 'post_id', v.post_id,
                 'label', v.label,
                 'view_count', v.view_count
               )
               ORDER BY v.view_count DESC, v.post_id
             )
      FROM (
        SELECT pv.post_id,
               COALESCE(
                 NULLIF(btrim(left(p.content, 60)), ''),
                 CASE WHEN p.id IS NULL THEN '(silinmis gonderi)' ELSE '(gorselli gonderi)' END
               ) AS label,
               count(*) AS view_count
        FROM public.post_views pv
        LEFT JOIN public.posts p ON p.id = pv.post_id
        WHERE pv.viewed_at >= v_window_start
        GROUP BY pv.post_id, p.id, p.content
        ORDER BY count(*) DESC, pv.post_id
        LIMIT v_most_viewed_limit
      ) AS v
    ), '[]'::jsonb)
  );
END;
$$;

REVOKE ALL ON FUNCTION public.admin_logs_data(integer, integer, integer, integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_logs_data(integer, integer, integer, integer)
  TO authenticated, service_role;

-- Admin panelindeki "Analitik Verilerini Temizle" dugmesi bugune kadar sadece
-- adminin kendi cihazindaki Hive kutusunu siliyordu; merkezi tabloya
-- dokunmuyordu. Sunucu tarafi karsiligi:
CREATE OR REPLACE FUNCTION public.admin_purge_analytics_events(
  p_older_than_days integer DEFAULT NULL
)
RETURNS bigint
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_deleted bigint;
BEGIN
  IF NOT private.current_user_is_admin() THEN
    RAISE EXCEPTION 'admin_purge_analytics_events: not admin' USING ERRCODE = '42501';
  END IF;

  IF p_older_than_days IS NULL THEN
    DELETE FROM public.app_analytics_events;
  ELSE
    DELETE FROM public.app_analytics_events
    WHERE created_at < now() - (GREATEST(p_older_than_days, 0) * interval '1 day');
  END IF;

  GET DIAGNOSTICS v_deleted = ROW_COUNT;
  RETURN v_deleted;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_purge_analytics_events(integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_purge_analytics_events(integer)
  TO authenticated, service_role;

-- Saklama politikasi: tablonun sinirsiz buyumesini engelle. Admin ekrani en
-- fazla 365 gunluk pencere sorabildigi icin 180 gun fazlasiyla yeterli.
CREATE OR REPLACE FUNCTION public.prune_app_analytics_events()
RETURNS bigint
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_deleted bigint;
BEGIN
  DELETE FROM public.app_analytics_events
  WHERE created_at < now() - interval '180 days';
  GET DIAGNOSTICS v_deleted = ROW_COUNT;
  RETURN v_deleted;
END;
$$;

REVOKE ALL ON FUNCTION public.prune_app_analytics_events() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.prune_app_analytics_events() TO service_role;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    PERFORM cron.unschedule('prune-app-analytics-events-daily')
    WHERE EXISTS (
      SELECT 1 FROM cron.job WHERE jobname = 'prune-app-analytics-events-daily'
    );
    PERFORM cron.schedule(
      'prune-app-analytics-events-daily',
      '17 3 * * *',
      $cron$SELECT public.prune_app_analytics_events();$cron$
    );
  END IF;
END;
$$;

NOTIFY pgrst, 'reload schema';
