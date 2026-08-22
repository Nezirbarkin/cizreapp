-- Admin > Loglar ekranindaki "Son Aktif Kullanicilar" bugune kadar hicbir
-- platform bilgisi tasimiyordu (iOS/Android/Web ayrimi istemci tarafinda da
-- sunucu tarafinda da yoktu). set_my_presence heartbeat'te zaten cagriliyor;
-- platformu da orada gonderip profiles'a yazdiriyoruz.

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS platform text;

ALTER TABLE public.profiles
  DROP CONSTRAINT IF EXISTS profiles_platform_check;
ALTER TABLE public.profiles
  ADD CONSTRAINT profiles_platform_check
  CHECK (platform IS NULL OR platform IN ('ios', 'android', 'web', 'unknown'));

-- set_my_presence: p_platform parametresi eklendi. Eski istemciler (veya
-- platform tespit edilemediginde) NULL gonderir; NULL gelirse mevcut deger
-- korunur, ilk hic yazilmadiysa NULL kalir (admin tarafinda 'unknown' olarak
-- gosterilir).
DROP FUNCTION IF EXISTS public.set_my_presence(boolean);

CREATE OR REPLACE FUNCTION public.set_my_presence(
  p_is_online boolean,
  p_platform text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_ghost boolean;
  v_enabled boolean;
  v_platform text := p_platform;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'set_my_presence: not authenticated'
      USING ERRCODE = '28000';
  END IF;

  IF v_platform IS NOT NULL AND v_platform NOT IN ('ios', 'android', 'web', 'unknown') THEN
    v_platform := 'unknown';
  END IF;

  SELECT is_ghost_mode, is_online_enabled
    INTO v_ghost, v_enabled
  FROM public.profiles
  WHERE id = v_uid;

  UPDATE public.profiles
    SET
      is_online = CASE
        WHEN v_ghost = true THEN false
        WHEN COALESCE(v_enabled, true) = false THEN false
        ELSE p_is_online
      END,
      last_seen = NOW(),
      platform = COALESCE(v_platform, platform)
  WHERE id = v_uid;
END;
$$;

REVOKE ALL ON FUNCTION public.set_my_presence(boolean, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.set_my_presence(boolean, text) TO authenticated, service_role;

-- admin_logs_data: platform kirilimi (aktif/toplam) ve recentUsers icin
-- platform alani eklendi.
DROP FUNCTION IF EXISTS public.admin_logs_data(integer, integer, integer, integer);

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
    -- Platform bilgisi set_my_presence uzerinden yazilir (bkz. migration
    -- 20260821000001). Hic heartbeat gondermemis / eski istemcideki
    -- kullanicilar icin platform NULL -> 'unknown' kovasina duser.
    'platformCounts', COALESCE((
      SELECT jsonb_object_agg(platform_key, jsonb_build_object('online', online_count, 'total', total_count))
      FROM (
        SELECT COALESCE(platform, 'unknown') AS platform_key,
               count(*) FILTER (WHERE last_seen >= v_now - interval '5 minutes') AS online_count,
               count(*) AS total_count
        FROM public.profiles
        GROUP BY 1
      ) AS pc
    ), '{}'::jsonb),
    'recentUsers', COALESCE((
      SELECT jsonb_agg(to_jsonb(u) ORDER BY u.last_seen DESC NULLS LAST)
      FROM (
        SELECT id, username, full_name, avatar_url,
               COALESCE(platform, 'unknown') AS platform,
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

NOTIFY pgrst, 'reload schema';
