-- =============================================================================
-- Müzik çalar: kim, ne zaman, hangi şarkıyı, ne kadar dinledi
--
-- İstemci (OkeySoundService) çalarken her ~30 sn'de bir `music_report` çağırır:
--   start     şarkı başladı        -> plays +1, "şu an dinleyen" güncellenir
--   heartbeat çalmaya devam ediyor -> seconds += delta
--   resume    devam ettirildi
--   pause     duraklatıldı         -> "şu an dinleyen"den düşer
--   stop      müzik kapatıldı
--
-- Depolama bilerek ÖZET düzeyindedir (kullanıcı x şarkı x gün): heartbeat başına
-- satır yazmak dakikada iki satır/dinleyici demek olurdu.
--
-- Tablolara istemci doğrudan erişemez; yalnızca aşağıdaki RPC'ler.
-- =============================================================================

BEGIN;

CREATE TABLE IF NOT EXISTS public.music_listening_stats (
  user_id        uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  track_key      text NOT NULL,   -- şarkının URL'si (yeniden adlandırmadan etkilenmez)
  track_name     text NOT NULL,
  day            date NOT NULL DEFAULT ((now() AT TIME ZONE 'Europe/Istanbul')::date),
  plays          integer NOT NULL DEFAULT 0,
  seconds        integer NOT NULL DEFAULT 0,
  last_played_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, track_key, day)
);

CREATE INDEX IF NOT EXISTS idx_music_listening_stats_day ON public.music_listening_stats (day DESC);
CREATE INDEX IF NOT EXISTS idx_music_listening_stats_track ON public.music_listening_stats (track_key, day DESC);

CREATE TABLE IF NOT EXISTS public.music_now_playing (
  user_id    uuid PRIMARY KEY REFERENCES public.profiles(id) ON DELETE CASCADE,
  track_key  text,
  track_name text,
  is_playing boolean NOT NULL DEFAULT false,
  updated_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.music_listening_stats ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.music_now_playing ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.music_listening_stats FROM PUBLIC, anon, authenticated;
REVOKE ALL ON public.music_now_playing FROM PUBLIC, anon, authenticated;
GRANT ALL ON public.music_listening_stats TO service_role;
GRANT ALL ON public.music_now_playing TO service_role;

-- -----------------------------------------------------------------------------
-- music_report — istemci çağrısı
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.music_report(
  p_track_key  text,
  p_track_name text,
  p_event      text,
  p_delta      integer DEFAULT 0
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_uid   uuid := auth.uid();
  v_delta integer := LEAST(GREATEST(COALESCE(p_delta, 0), 0), 120);
  v_day   date := ((now() AT TIME ZONE 'Europe/Istanbul')::date);
  v_key   text := left(btrim(COALESCE(p_track_key, '')), 500);
  v_name  text := left(COALESCE(NULLIF(btrim(COALESCE(p_track_name, '')), ''), 'Şarkı'), 120);
BEGIN
  IF v_uid IS NULL OR v_key = '' THEN
    RETURN; -- misafir dinlemeleri kaydedilmez
  END IF;
  IF p_event IS NULL OR p_event NOT IN ('start', 'heartbeat', 'resume', 'pause', 'stop') THEN
    RETURN;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.profiles WHERE id = v_uid) THEN
    RETURN;
  END IF;

  INSERT INTO public.music_now_playing AS np (user_id, track_key, track_name, is_playing, updated_at)
  VALUES (v_uid, v_key, v_name, p_event IN ('start', 'heartbeat', 'resume'), now())
  ON CONFLICT (user_id) DO UPDATE
    SET track_key = EXCLUDED.track_key,
        track_name = EXCLUDED.track_name,
        is_playing = EXCLUDED.is_playing,
        updated_at = now();

  IF p_event = 'start' OR (p_event = 'heartbeat' AND v_delta > 0) THEN
    INSERT INTO public.music_listening_stats AS s
      (user_id, track_key, track_name, day, plays, seconds, last_played_at)
    VALUES (v_uid, v_key, v_name, v_day,
            CASE WHEN p_event = 'start' THEN 1 ELSE 0 END,
            CASE WHEN p_event = 'heartbeat' THEN v_delta ELSE 0 END,
            now())
    ON CONFLICT (user_id, track_key, day) DO UPDATE
      SET plays = s.plays + EXCLUDED.plays,
          seconds = s.seconds + EXCLUDED.seconds,
          track_name = EXCLUDED.track_name,
          last_played_at = now();
  END IF;

  IF p_event = 'start' THEN
    PERFORM private.log_user_activity(
      v_uid, 'music_play', 'music', 'track', NULL,
      'Şarkı dinlemeye başladı: ' || v_name, jsonb_build_object('track', v_name)
    );
  ELSIF p_event = 'stop' THEN
    PERFORM private.log_user_activity(
      v_uid, 'music_stopped', 'music', 'track', NULL,
      'Müziği kapattı', '{}'::jsonb
    );
  END IF;
EXCEPTION WHEN OTHERS THEN
  NULL; -- istatistik, müzik çalmayı hiçbir koşulda bozmamalı
END;
$$;

-- Herkese açık sayı: "N kişi dinliyor" rozeti için.
CREATE OR REPLACE FUNCTION public.music_listener_count()
RETURNS integer
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT count(*)::integer
  FROM public.music_now_playing
  WHERE is_playing AND updated_at >= now() - interval '90 seconds';
$$;

-- -----------------------------------------------------------------------------
-- Admin RPC'leri
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_music_stats(p_days integer DEFAULT 30)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_days integer := LEAST(GREATEST(COALESCE(p_days, 30), 1), 365);
  v_from date := ((now() AT TIME ZONE 'Europe/Istanbul')::date) - (LEAST(GREATEST(COALESCE(p_days, 30), 1), 365) - 1);
  v_today date := ((now() AT TIME ZONE 'Europe/Istanbul')::date);
BEGIN
  IF NOT private.current_user_is_admin() THEN
    RAISE EXCEPTION 'admin_music_stats: not admin' USING ERRCODE = '42501';
  END IF;

  RETURN jsonb_build_object(
    'windowDays', v_days,
    'listeningNow', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
               'user_id', n.user_id, 'username', p.username, 'full_name', p.full_name,
               'avatar_url', p.avatar_url, 'track_name', n.track_name, 'updated_at', n.updated_at
             ) ORDER BY n.updated_at DESC)
      FROM public.music_now_playing n
      JOIN public.profiles p ON p.id = n.user_id
      WHERE n.is_playing AND n.updated_at >= now() - interval '90 seconds'
    ), '[]'::jsonb),
    'totalSeconds', COALESCE((SELECT sum(seconds) FROM public.music_listening_stats WHERE day >= v_from), 0),
    'totalPlays', COALESCE((SELECT sum(plays) FROM public.music_listening_stats WHERE day >= v_from), 0),
    'uniqueListeners', (SELECT count(DISTINCT user_id) FROM public.music_listening_stats WHERE day >= v_from),
    'listenersToday', (SELECT count(DISTINCT user_id) FROM public.music_listening_stats WHERE day = v_today),
    'tracks', COALESCE((
      SELECT jsonb_agg(to_jsonb(t) ORDER BY t.seconds DESC, t.plays DESC)
      FROM (
        SELECT track_key,
               (array_agg(track_name ORDER BY last_played_at DESC))[1] AS track_name,
               sum(plays)::bigint AS plays,
               sum(seconds)::bigint AS seconds,
               count(DISTINCT user_id) AS listeners,
               max(last_played_at) AS last_played_at
        FROM public.music_listening_stats
        WHERE day >= v_from
        GROUP BY track_key
        ORDER BY sum(seconds) DESC, sum(plays) DESC
        LIMIT 30
      ) t
    ), '[]'::jsonb),
    'listeners', COALESCE((
      SELECT jsonb_agg(to_jsonb(l) ORDER BY l.seconds DESC)
      FROM (
        SELECT s.user_id, p.username, p.full_name, p.avatar_url,
               sum(s.plays)::bigint AS plays,
               sum(s.seconds)::bigint AS seconds,
               max(s.last_played_at) AS last_played_at,
               (array_agg(s.track_name ORDER BY s.seconds DESC))[1] AS top_track
        FROM public.music_listening_stats s
        JOIN public.profiles p ON p.id = s.user_id
        WHERE s.day >= v_from
        GROUP BY s.user_id, p.username, p.full_name, p.avatar_url
        ORDER BY sum(s.seconds) DESC
        LIMIT 40
      ) l
    ), '[]'::jsonb),
    'daily', COALESCE((
      SELECT jsonb_agg(jsonb_build_object('day', d.day, 'listeners', d.listeners, 'seconds', d.seconds) ORDER BY d.day)
      FROM (
        SELECT day::text AS day, count(DISTINCT user_id) AS listeners, sum(seconds)::bigint AS seconds
        FROM public.music_listening_stats
        WHERE day >= v_from
        GROUP BY day
      ) d
    ), '[]'::jsonb)
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_music_track_listeners(
  p_track_key text,
  p_days      integer DEFAULT 30
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_from date := ((now() AT TIME ZONE 'Europe/Istanbul')::date) - (LEAST(GREATEST(COALESCE(p_days, 30), 1), 365) - 1);
BEGIN
  IF NOT private.current_user_is_admin() THEN
    RAISE EXCEPTION 'admin_music_track_listeners: not admin' USING ERRCODE = '42501';
  END IF;

  RETURN COALESCE((
    SELECT jsonb_agg(to_jsonb(x) ORDER BY x.seconds DESC)
    FROM (
      SELECT s.user_id, p.username, p.full_name, p.avatar_url,
             sum(s.plays)::bigint AS plays,
             sum(s.seconds)::bigint AS seconds,
             max(s.last_played_at) AS last_played_at
      FROM public.music_listening_stats s
      JOIN public.profiles p ON p.id = s.user_id
      WHERE s.track_key = p_track_key AND s.day >= v_from
      GROUP BY s.user_id, p.username, p.full_name, p.avatar_url
      ORDER BY sum(s.seconds) DESC
      LIMIT 100
    ) x
  ), '[]'::jsonb);
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_clear_music_stats()
RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_deleted bigint;
BEGIN
  IF NOT private.current_user_is_admin() THEN
    RAISE EXCEPTION 'admin_clear_music_stats: not admin' USING ERRCODE = '42501';
  END IF;
  DELETE FROM public.music_listening_stats;
  GET DIAGNOSTICS v_deleted = ROW_COUNT;
  DELETE FROM public.music_now_playing;

  INSERT INTO public.admin_audit_log (admin_id, action, target_table, target_id, new_data)
  VALUES (auth.uid(), 'clear_music_stats', 'music_listening_stats', NULL,
          jsonb_build_object('deleted', v_deleted));
  RETURN v_deleted;
END;
$$;

-- Saklama: 180 gün
CREATE OR REPLACE FUNCTION public.prune_music_listening_stats()
RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_deleted bigint;
BEGIN
  DELETE FROM public.music_listening_stats WHERE day < ((now() AT TIME ZONE 'Europe/Istanbul')::date) - 180;
  GET DIAGNOSTICS v_deleted = ROW_COUNT;
  DELETE FROM public.music_now_playing WHERE updated_at < now() - interval '2 days';
  RETURN v_deleted;
END;
$$;

REVOKE ALL ON FUNCTION public.music_report(text, text, text, integer) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.music_listener_count() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.admin_music_stats(integer) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.admin_music_track_listeners(text, integer) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.admin_clear_music_stats() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.prune_music_listening_stats() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.music_report(text, text, text, integer) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.music_listener_count() TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.admin_music_stats(integer) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.admin_music_track_listeners(text, integer) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.admin_clear_music_stats() TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.prune_music_listening_stats() TO service_role;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    PERFORM cron.unschedule('prune-music-listening-stats-daily')
    WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'prune-music-listening-stats-daily');
    PERFORM cron.schedule(
      'prune-music-listening-stats-daily',
      '37 3 * * *',
      $cron$SELECT public.prune_music_listening_stats();$cron$
    );
  END IF;
END;
$$;

COMMIT;

NOTIFY pgrst, 'reload schema';
