-- =============================================================================
-- Günün fırsatları: kaç kişi, kimler tıkladı
--
-- Ana sayfadaki fırsat kartına dokunulunca istemci `log_daily_deal_click`
-- çağırır. Giriş yapmış kullanıcı user_id ile, misafir ise oturum anahtarıyla
-- (session_key) sayılır; böylece "benzersiz kişi" misafirler için de anlamlı.
-- Admin ekranı kart başına toplam tık, benzersiz kişi ve tıklayanların listesini
-- gösterir; tıklamalar silinebilir.
-- =============================================================================

BEGIN;

CREATE TABLE IF NOT EXISTS public.daily_deal_clicks (
  id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  deal_id     uuid NOT NULL REFERENCES public.daily_deals(id) ON DELETE CASCADE,
  user_id     uuid REFERENCES public.profiles(id) ON DELETE CASCADE, -- NULL = misafir
  session_key text,                                                  -- misafir tekilleştirme
  platform    text,
  clicked_at  timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_daily_deal_clicks_deal_time ON public.daily_deal_clicks (deal_id, clicked_at DESC);
CREATE INDEX IF NOT EXISTS idx_daily_deal_clicks_user ON public.daily_deal_clicks (user_id, clicked_at DESC);

ALTER TABLE public.daily_deal_clicks ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.daily_deal_clicks FROM PUBLIC, anon, authenticated;
GRANT ALL ON public.daily_deal_clicks TO service_role;

CREATE OR REPLACE FUNCTION public.log_daily_deal_click(
  p_deal_id     uuid,
  p_platform    text DEFAULT NULL,
  p_session_key text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_key text := left(NULLIF(btrim(COALESCE(p_session_key, '')), ''), 64);
  v_title text;
BEGIN
  IF p_deal_id IS NULL THEN
    RETURN;
  END IF;

  SELECT title INTO v_title FROM public.daily_deals WHERE id = p_deal_id;
  IF NOT FOUND THEN
    RETURN;
  END IF;

  -- Aynı kişinin aynı karta 5 sn içindeki tekrar dokunuşunu (çift tık) sayma.
  IF EXISTS (
    SELECT 1 FROM public.daily_deal_clicks
    WHERE deal_id = p_deal_id
      AND clicked_at > now() - interval '5 seconds'
      AND ((v_uid IS NOT NULL AND user_id = v_uid)
        OR (v_uid IS NULL AND v_key IS NOT NULL AND session_key = v_key))
  ) THEN
    RETURN;
  END IF;

  INSERT INTO public.daily_deal_clicks (deal_id, user_id, session_key, platform)
  VALUES (p_deal_id, v_uid, CASE WHEN v_uid IS NULL THEN v_key END, left(p_platform, 20));

  IF v_uid IS NOT NULL THEN
    PERFORM private.log_user_activity(
      v_uid, 'daily_deal_clicked', 'engagement', 'daily_deal', p_deal_id::text,
      'Günün fırsatına tıkladı: ' || COALESCE(v_title, '?'),
      jsonb_build_object('title', v_title), p_platform
    );
  END IF;
EXCEPTION WHEN OTHERS THEN
  NULL; -- sayaç, kart navigasyonunu hiçbir koşulda bozmamalı
END;
$$;

-- Kart başına özet
CREATE OR REPLACE FUNCTION public.admin_daily_deal_click_stats(p_days integer DEFAULT 30)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_days  integer := LEAST(GREATEST(COALESCE(p_days, 30), 1), 365);
  v_start timestamptz := now() - (LEAST(GREATEST(COALESCE(p_days, 30), 1), 365) * interval '1 day');
  v_today timestamptz := date_trunc('day', now() AT TIME ZONE 'Europe/Istanbul') AT TIME ZONE 'Europe/Istanbul';
BEGIN
  IF NOT private.current_user_is_admin() THEN
    RAISE EXCEPTION 'admin_daily_deal_click_stats: not admin' USING ERRCODE = '42501';
  END IF;

  RETURN jsonb_build_object(
    'windowDays', v_days,
    'totalClicks', (SELECT count(*) FROM public.daily_deal_clicks WHERE clicked_at >= v_start),
    'uniqueUsers', (SELECT count(DISTINCT user_id) FROM public.daily_deal_clicks WHERE clicked_at >= v_start AND user_id IS NOT NULL),
    'guestClicks', (SELECT count(*) FROM public.daily_deal_clicks WHERE clicked_at >= v_start AND user_id IS NULL),
    'clicksToday', (SELECT count(*) FROM public.daily_deal_clicks WHERE clicked_at >= v_today),
    'deals', COALESCE((
      SELECT jsonb_agg(to_jsonb(x) ORDER BY x.total_clicks DESC, x.sort_order)
      FROM (
        SELECT d.id AS deal_id, d.title, d.image_url, d.is_active, d.sort_order,
               count(c.id) AS total_clicks,
               count(DISTINCT c.user_id) AS unique_users,
               count(c.id) FILTER (WHERE c.user_id IS NULL) AS guest_clicks,
               count(DISTINCT c.session_key) FILTER (WHERE c.user_id IS NULL) AS unique_guests,
               count(c.id) FILTER (WHERE c.clicked_at >= v_today) AS clicks_today,
               max(c.clicked_at) AS last_click_at
        FROM public.daily_deals d
        LEFT JOIN public.daily_deal_clicks c ON c.deal_id = d.id AND c.clicked_at >= v_start
        GROUP BY d.id
      ) x
    ), '[]'::jsonb),
    'daily', COALESCE((
      SELECT jsonb_agg(jsonb_build_object('day', s.day, 'count', s.n) ORDER BY s.day)
      FROM (
        SELECT to_char(clicked_at AT TIME ZONE 'Europe/Istanbul', 'YYYY-MM-DD') AS day, count(*) AS n
        FROM public.daily_deal_clicks
        WHERE clicked_at >= v_start
        GROUP BY 1
      ) s
    ), '[]'::jsonb)
  );
END;
$$;

-- Bir karta tıklayanlar (kişi başına toplam + son tık) ve misafir toplamı
CREATE OR REPLACE FUNCTION public.admin_daily_deal_clickers(
  p_deal_id uuid,
  p_days    integer DEFAULT 30,
  p_limit   integer DEFAULT 100
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_start timestamptz := now() - (LEAST(GREATEST(COALESCE(p_days, 30), 1), 365) * interval '1 day');
  v_limit integer := LEAST(GREATEST(COALESCE(p_limit, 100), 1), 500);
BEGIN
  IF NOT private.current_user_is_admin() THEN
    RAISE EXCEPTION 'admin_daily_deal_clickers: not admin' USING ERRCODE = '42501';
  END IF;

  RETURN jsonb_build_object(
    'guestClicks', (SELECT count(*) FROM public.daily_deal_clicks
                    WHERE deal_id = p_deal_id AND user_id IS NULL AND clicked_at >= v_start),
    'guestPeople', (SELECT count(DISTINCT session_key) FROM public.daily_deal_clicks
                    WHERE deal_id = p_deal_id AND user_id IS NULL AND clicked_at >= v_start),
    'users', COALESCE((
      SELECT jsonb_agg(to_jsonb(x) ORDER BY x.last_click_at DESC)
      FROM (
        SELECT c.user_id, p.username, p.full_name, p.avatar_url,
               count(*) AS clicks,
               min(c.clicked_at) AS first_click_at,
               max(c.clicked_at) AS last_click_at
        FROM public.daily_deal_clicks c
        JOIN public.profiles p ON p.id = c.user_id
        WHERE c.deal_id = p_deal_id AND c.clicked_at >= v_start
        GROUP BY c.user_id, p.username, p.full_name, p.avatar_url
        ORDER BY max(c.clicked_at) DESC
        LIMIT v_limit
      ) x
    ), '[]'::jsonb)
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_clear_daily_deal_clicks(p_deal_id uuid DEFAULT NULL)
RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_deleted bigint;
BEGIN
  IF NOT private.current_user_is_admin() THEN
    RAISE EXCEPTION 'admin_clear_daily_deal_clicks: not admin' USING ERRCODE = '42501';
  END IF;
  DELETE FROM public.daily_deal_clicks WHERE p_deal_id IS NULL OR deal_id = p_deal_id;
  GET DIAGNOSTICS v_deleted = ROW_COUNT;

  INSERT INTO public.admin_audit_log (admin_id, action, target_table, target_id, new_data)
  VALUES (auth.uid(), 'clear_daily_deal_clicks', 'daily_deal_clicks', p_deal_id::text,
          jsonb_build_object('deleted', v_deleted));
  RETURN v_deleted;
END;
$$;

REVOKE ALL ON FUNCTION public.log_daily_deal_click(uuid, text, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.admin_daily_deal_click_stats(integer) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.admin_daily_deal_clickers(uuid, integer, integer) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.admin_clear_daily_deal_clicks(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.log_daily_deal_click(uuid, text, text) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.admin_daily_deal_click_stats(integer) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.admin_daily_deal_clickers(uuid, integer, integer) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.admin_clear_daily_deal_clicks(uuid) TO authenticated, service_role;

COMMIT;

NOTIFY pgrst, 'reload schema';
