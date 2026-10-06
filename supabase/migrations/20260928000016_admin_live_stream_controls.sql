-- =============================================================================
-- Görev 4.3 — Admin: canlı yayın kontrolü
-- =============================================================================
--
-- 1) Genel anahtar `live_stream_enabled` (varsayılan açık) ve erişim modu
--    `live_stream_access`: 'open' = her aktif/onaylı mağaza (izni
--    kaldırılmadıkça), 'invite' = yalnız izin verilen mağazalar.
-- 2) Mağaza bazında izin: `shop_live_permissions` (satır yok = moda göre).
--    Tabloya istemci hiç erişemez; yönetim RPC ile yazar/okur. (İzin shops
--    satırına konmadı: satıcı kendi mağaza satırını RLS ile güncelleyebiliyor.)
-- 3) İzin kontrolü YENİ ya da hazırlıktaki yayında uygulanır
--    (`live_create_session`, `start_live_session`, satıcı anahtarı
--    `live_token_grant`). Süren yayın ancak yönetici kapatırsa biter:
--    tek yayın, mağazanın iznini kaldırma ya da ayar değişikliğinde "süren
--    yayınları da kapat".
-- 4) Yönetici kapatması `private.live_close_session(id, 'admin')` ile yapılır
--    (izleyici ve satıcı ekranı 'admin' nedenini zaten gösterir); satıcıya
--    'admin_notification' bildirimi gider.
--
-- Hatalar HINT ile: LIVE_DISABLED / LIVE_REVOKED (DETAIL = yönetici notu) /
-- LIVE_NOT_PERMITTED. `live-token` Edge Function grant hatasını olduğu gibi
-- istemciye geçirir; yeniden dağıtım gerekmez.

BEGIN;

-- -----------------------------------------------------------------------------
-- 1) Ayarlar ve tablolar
-- -----------------------------------------------------------------------------
INSERT INTO public.app_settings (key, value, description)
VALUES
  ('live_stream_enabled', '"true"',
   'Canlı yayın modülü açık mı (Görev 4.3). Kapalıyken yeni yayın açılamaz; süren yayını yönetici kapatır.'),
  ('live_stream_access', '"open"',
   'Canlı yayın erişimi: "open" = her aktif mağaza (izni kaldırılmadıkça), "invite" = yalnız izin verilen mağazalar.')
ON CONFLICT (key) DO NOTHING;

CREATE TABLE IF NOT EXISTS public.shop_live_permissions (
  shop_id    uuid PRIMARY KEY REFERENCES public.shops(id) ON DELETE CASCADE,
  permission text NOT NULL CHECK (permission IN ('granted', 'revoked')),
  note       text CHECK (note IS NULL OR char_length(note) <= 300),
  updated_by uuid,
  updated_at timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.shop_live_permissions IS
  'Görev 4.3: mağazanın canlı yayın izni (satır yok = live_stream_access moduna göre). Yalnız yönetim RPC''leri yazar/okur.';

ALTER TABLE public.shop_live_permissions ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.shop_live_permissions FROM PUBLIC, anon, authenticated;

ALTER TABLE public.live_sessions ADD COLUMN IF NOT EXISTS ended_by uuid;
ALTER TABLE public.live_sessions ADD COLUMN IF NOT EXISTS ended_note text;
ALTER TABLE public.live_sessions DROP CONSTRAINT IF EXISTS live_sessions_ended_note_check;
ALTER TABLE public.live_sessions ADD CONSTRAINT live_sessions_ended_note_check
  CHECK (ended_note IS NULL OR char_length(ended_note) <= 300);

-- -----------------------------------------------------------------------------
-- 2) Yardımcılar
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION private.live_setting(p_key text)
RETURNS text
LANGUAGE sql
STABLE
SET search_path = ''
AS $fn$
  SELECT lower(NULLIF(btrim(a.value #>> '{}', E'" \t\r\n'), ''))
    FROM public.app_settings a
   WHERE a.key = p_key;
$fn$;

-- Okunamayan/bozuk değer açık sayılır (modül yanlışlıkla kaybolmasın).
CREATE OR REPLACE FUNCTION private.live_module_enabled()
RETURNS boolean
LANGUAGE sql
STABLE
SET search_path = ''
AS $fn$
  SELECT COALESCE(private.live_setting('live_stream_enabled') NOT IN ('false', 'f', '0', 'no', 'off'), true);
$fn$;

CREATE OR REPLACE FUNCTION private.live_access_mode()
RETURNS text
LANGUAGE sql
STABLE
SET search_path = ''
AS $fn$
  SELECT CASE WHEN private.live_setting('live_stream_access') = 'invite' THEN 'invite' ELSE 'open' END;
$fn$;

-- 'ok' | 'LIVE_DISABLED' | 'LIVE_REVOKED' | 'LIVE_NOT_PERMITTED'.
-- p_ignore_global: yalnız mağazanın kendi durumu (bildirim kararı için).
CREATE OR REPLACE FUNCTION private.live_shop_access(p_shop_id uuid, p_ignore_global boolean DEFAULT false)
RETURNS text
LANGUAGE plpgsql
STABLE
SET search_path = ''
AS $fn$
DECLARE
  v_permission text;
BEGIN
  IF NOT p_ignore_global AND NOT private.live_module_enabled() THEN
    RETURN 'LIVE_DISABLED';
  END IF;
  SELECT permission INTO v_permission FROM public.shop_live_permissions WHERE shop_id = p_shop_id;
  IF v_permission = 'revoked' THEN
    RETURN 'LIVE_REVOKED';
  END IF;
  IF v_permission = 'granted' OR private.live_access_mode() = 'open' THEN
    RETURN 'ok';
  END IF;
  RETURN 'LIVE_NOT_PERMITTED';
END;
$fn$;

CREATE OR REPLACE FUNCTION private.live_assert_access(p_shop_id uuid)
RETURNS void
LANGUAGE plpgsql
STABLE
SET search_path = ''
AS $fn$
DECLARE
  v_access text := private.live_shop_access(p_shop_id);
  v_note text;
BEGIN
  IF v_access = 'ok' THEN
    RETURN;
  END IF;
  IF v_access = 'LIVE_REVOKED' THEN
    SELECT note INTO v_note FROM public.shop_live_permissions WHERE shop_id = p_shop_id;
  END IF;
  RAISE EXCEPTION USING
    MESSAGE = CASE v_access
      WHEN 'LIVE_DISABLED' THEN 'Canlı yayın şu anda kapalı'
      WHEN 'LIVE_REVOKED' THEN 'Mağazanın canlı yayın izni yönetim tarafından kaldırıldı'
      ELSE 'Canlı yayın şu an yalnız izin verilen mağazalara açık'
    END,
    ERRCODE = 'P0001',
    HINT = v_access,
    DETAIL = COALESCE(v_note, '');
END;
$fn$;

CREATE OR REPLACE FUNCTION private.live_notify(
  p_user_id uuid,
  p_title text,
  p_content text,
  p_entity_id text,
  p_entity_type text
)
RETURNS void
LANGUAGE sql
SET search_path = ''
AS $fn$
  INSERT INTO public.notifications (user_id, type, title, content, entity_id, entity_type, metadata, is_read, created_at)
  SELECT p_user_id, 'admin_notification', p_title, p_content, p_entity_id, p_entity_type,
         jsonb_build_object('source', 'live_admin'), false, now()
   WHERE p_user_id IS NOT NULL;
$fn$;

-- Yönetici kapatması: kapatır, kapatanı/notu yazar, satıcıya bildirir.
CREATE OR REPLACE FUNCTION private.live_admin_close(p_session_id uuid, p_note text)
RETURNS jsonb
LANGUAGE plpgsql
SET search_path = ''
AS $fn$
DECLARE
  v public.live_sessions%ROWTYPE;
  v_summary jsonb;
BEGIN
  SELECT * INTO v FROM public.live_sessions WHERE id = p_session_id FOR UPDATE;
  IF NOT FOUND OR v.status = 'ended' THEN
    RETURN NULL;
  END IF;
  v_summary := private.live_close_session(p_session_id, 'admin');
  UPDATE public.live_sessions
     SET ended_by = auth.uid(), ended_note = p_note
   WHERE id = p_session_id;
  IF v.status = 'live' THEN
    PERFORM private.live_notify(
      v.host_user_id,
      'Canlı yayının kapatıldı',
      format('"%s" yayının yönetim tarafından kapatıldı%s.', v.title, COALESCE(': ' || p_note, '')),
      p_session_id::text,
      'live_session');
  END IF;
  RETURN v_summary;
END;
$fn$;

REVOKE ALL ON FUNCTION private.live_setting(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION private.live_module_enabled() FROM PUBLIC;
REVOKE ALL ON FUNCTION private.live_access_mode() FROM PUBLIC;
REVOKE ALL ON FUNCTION private.live_shop_access(uuid, boolean) FROM PUBLIC;
REVOKE ALL ON FUNCTION private.live_assert_access(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION private.live_notify(uuid, text, text, text, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION private.live_admin_close(uuid, text) FROM PUBLIC;

-- -----------------------------------------------------------------------------
-- 3) Satıcı RPC'lerinde izin kontrolü (3.4 tanımları + kontrol)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.live_create_session(
  p_shop_id uuid,
  p_title text,
  p_description text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $fn$
DECLARE
  v_uid uuid := auth.uid();
  v_owner uuid;
  v_active boolean;
  v_title text := btrim(regexp_replace(COALESCE(p_title, ''), '\s+', ' ', 'g'));
  v_desc text := NULLIF(btrim(COALESCE(p_description, '')), '');
  v_open public.live_sessions%ROWTYPE;
  v_has_open boolean;
  v_id uuid;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Oturum açmanız gerekli' USING ERRCODE = '42501', HINT = 'AUTH_REQUIRED';
  END IF;

  SELECT s.owner_id, COALESCE(s.is_active, false) AND COALESCE(s.is_approved, false)
    INTO v_owner, v_active
    FROM public.shops s WHERE s.id = p_shop_id;
  IF v_owner IS NULL OR v_owner <> v_uid THEN
    RAISE EXCEPTION 'Bu mağaza adına yayın açamazsınız' USING ERRCODE = '42501', HINT = 'LIVE_NOT_SHOP_OWNER';
  END IF;
  IF NOT v_active THEN
    RAISE EXCEPTION 'Yayın için mağazanız aktif ve onaylı olmalı' USING ERRCODE = 'P0001', HINT = 'LIVE_SHOP_INACTIVE';
  END IF;
  IF char_length(v_title) < 3 OR char_length(v_title) > 80 THEN
    RAISE EXCEPTION 'Yayın başlığı 3–80 karakter olmalı' USING ERRCODE = 'P0001', HINT = 'LIVE_TITLE_INVALID';
  END IF;
  v_desc := left(v_desc, 300);

  SELECT * INTO v_open
    FROM public.live_sessions
   WHERE shop_id = p_shop_id AND status IN ('scheduled', 'live')
   FOR UPDATE;
  v_has_open := FOUND;

  -- Süren (taze) yayın sürdürülür: uygulama kapanıp açıldı.
  IF v_has_open AND v_open.status = 'live' AND v_open.last_heartbeat_at > now() - interval '2 minutes' THEN
    RETURN private.live_session_json(v_open.id) || jsonb_build_object('resumed', true);
  END IF;

  -- Görev 4.3: yeni ya da hazırlıktaki yayın için izin.
  PERFORM private.live_assert_access(p_shop_id);

  IF v_has_open THEN
    IF v_open.status = 'scheduled' THEN
      UPDATE public.live_sessions
         SET title = v_title, description = v_desc, host_user_id = v_uid
       WHERE id = v_open.id;
      RETURN private.live_session_json(v_open.id) || jsonb_build_object('resumed', false);
    END IF;
    PERFORM private.live_close_session(v_open.id, 'timeout');
  END IF;

  BEGIN
    INSERT INTO public.live_sessions (host_user_id, shop_id, title, description, channel_name, status)
    VALUES (v_uid, p_shop_id, v_title, v_desc, 'cz_' || replace(gen_random_uuid()::text, '-', ''), 'scheduled')
    RETURNING id INTO v_id;
  EXCEPTION WHEN unique_violation THEN
    -- Aynı anda ikinci cihazdan açıldı: açık olanı dön.
    SELECT id INTO v_id FROM public.live_sessions
     WHERE shop_id = p_shop_id AND status IN ('scheduled', 'live');
  END;

  RETURN private.live_session_json(v_id) || jsonb_build_object('resumed', false);
END;
$fn$;

CREATE OR REPLACE FUNCTION public.start_live_session(p_session_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $fn$
DECLARE
  v public.live_sessions%ROWTYPE;
  v_active boolean;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Oturum açmanız gerekli' USING ERRCODE = '42501', HINT = 'AUTH_REQUIRED';
  END IF;
  SELECT * INTO v FROM public.live_sessions WHERE id = p_session_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Yayın bulunamadı' USING ERRCODE = 'P0001', HINT = 'LIVE_NOT_FOUND';
  END IF;
  IF v.host_user_id <> auth.uid() THEN
    RAISE EXCEPTION 'Bu yayın size ait değil' USING ERRCODE = '42501', HINT = 'LIVE_NOT_HOST';
  END IF;
  IF v.status = 'ended' THEN
    RAISE EXCEPTION 'Bu yayın sona erdi' USING ERRCODE = 'P0001', HINT = 'LIVE_ENDED';
  END IF;
  SELECT COALESCE(s.is_active, false) AND COALESCE(s.is_approved, false) INTO v_active
    FROM public.shops s WHERE s.id = v.shop_id;
  IF NOT COALESCE(v_active, false) THEN
    RAISE EXCEPTION 'Yayın için mağazanız aktif ve onaylı olmalı' USING ERRCODE = 'P0001', HINT = 'LIVE_SHOP_INACTIVE';
  END IF;
  -- Görev 4.3: hazırlıktan canlıya geçiş izin ister (canlıyken tekrar çağrı = sinyal).
  IF v.status = 'scheduled' THEN
    PERFORM private.live_assert_access(v.shop_id);
  END IF;

  UPDATE public.live_sessions
     SET status = 'live',
         started_at = COALESCE(started_at, now()),
         last_heartbeat_at = now()
   WHERE id = p_session_id;

  RETURN private.live_session_json(p_session_id);
END;
$fn$;

CREATE OR REPLACE FUNCTION public.live_token_grant(
  p_session_id uuid,
  p_role text,
  p_user_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $fn$
DECLARE
  v public.live_sessions%ROWTYPE;
  v_active boolean;
  v_access text;
BEGIN
  IF p_role IS NULL OR p_role NOT IN ('host', 'viewer') THEN
    RETURN jsonb_build_object('ok', false, 'error', 'BAD_ROLE');
  END IF;
  SELECT * INTO v FROM public.live_sessions WHERE id = p_session_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'error', 'NOT_FOUND');
  END IF;
  IF v.status = 'ended' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'ENDED');
  END IF;
  SELECT COALESCE(s.is_active, false) AND COALESCE(s.is_approved, false) INTO v_active
    FROM public.shops s WHERE s.id = v.shop_id;
  IF NOT COALESCE(v_active, false) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'SHOP_INACTIVE');
  END IF;

  IF p_role = 'host' THEN
    IF p_user_id IS NULL THEN
      RETURN jsonb_build_object('ok', false, 'error', 'AUTH_REQUIRED');
    END IF;
    IF p_user_id <> v.host_user_id THEN
      RETURN jsonb_build_object('ok', false, 'error', 'FORBIDDEN');
    END IF;
    -- Görev 4.3: henüz başlamamış yayına anahtar izin ister; süren yayının
    -- anahtar yenilemesi yönetici kapatana dek sürer.
    IF v.status = 'scheduled' THEN
      v_access := private.live_shop_access(v.shop_id);
      IF v_access <> 'ok' THEN
        RETURN jsonb_build_object('ok', false, 'error', v_access);
      END IF;
    END IF;
  ELSIF v.status <> 'live' OR v.last_heartbeat_at IS NULL
        OR v.last_heartbeat_at < now() - interval '2 minutes' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'NOT_LIVE');
  END IF;

  RETURN jsonb_build_object('ok', true, 'channel', v.channel_name, 'host_uid', 1, 'role', p_role);
END;
$fn$;

-- Keşfet akışı + modül açık mı (istemci kapalıyken bilgi gösterir).
CREATE OR REPLACE FUNCTION public.live_sessions_feed(p_limit integer DEFAULT 30)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $fn$
DECLARE
  v_limit integer := LEAST(GREATEST(COALESCE(p_limit, 30), 1), 100);
  v_live jsonb;
  v_recent jsonb;
BEGIN
  SELECT COALESCE(jsonb_agg(private.live_session_json(x.id) ORDER BY x.viewer_count DESC, x.started_at DESC), '[]'::jsonb)
    INTO v_live
    FROM (
      SELECT ls.id, ls.viewer_count, ls.started_at
        FROM public.live_sessions ls
        JOIN public.shops s ON s.id = ls.shop_id
       WHERE ls.status = 'live'
         AND ls.last_heartbeat_at > now() - interval '2 minutes'
         AND COALESCE(s.is_active, false)
         AND COALESCE(s.is_approved, false)
       ORDER BY ls.viewer_count DESC, ls.started_at DESC
       LIMIT v_limit
    ) x;

  SELECT COALESCE(jsonb_agg(private.live_session_json(y.id) ORDER BY y.ended_at DESC), '[]'::jsonb)
    INTO v_recent
    FROM (
      SELECT ls.id, ls.ended_at
        FROM public.live_sessions ls
       WHERE ls.status = 'ended'
         AND ls.started_at IS NOT NULL
         AND ls.ended_at > now() - interval '7 days'
       ORDER BY ls.ended_at DESC
       LIMIT 20
    ) y;

  RETURN jsonb_build_object('live', v_live, 'recent', v_recent, 'enabled', private.live_module_enabled());
END;
$fn$;

-- -----------------------------------------------------------------------------
-- 4) Yönetim RPC'leri
-- -----------------------------------------------------------------------------

-- p_status: 'live' (şu an canlı) | 'ended' (geçmiş) | 'all'
CREATE OR REPLACE FUNCTION public.admin_live_sessions(
  p_status text DEFAULT 'live',
  p_limit integer DEFAULT 30,
  p_offset integer DEFAULT 0
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $fn$
DECLARE
  v_status text := CASE WHEN p_status IN ('live', 'ended', 'all') THEN p_status ELSE 'live' END;
  v_limit integer := LEAST(GREATEST(COALESCE(p_limit, 30), 1), 100);
  v_offset integer := GREATEST(COALESCE(p_offset, 0), 0);
  v_day_start timestamptz := date_trunc('day', now() AT TIME ZONE 'Europe/Istanbul') AT TIME ZONE 'Europe/Istanbul';
  v_total integer;
  v_rows jsonb;
BEGIN
  IF NOT public.auth_is_admin() THEN
    RAISE EXCEPTION 'Yönetici yetkisi gerekli' USING ERRCODE = '42501';
  END IF;

  WITH filtered AS (
    SELECT ls.id, ls.status, ls.viewer_count,
           COALESCE(ls.ended_at, ls.started_at, ls.created_at) AS sort_at
      FROM public.live_sessions ls
     WHERE CASE v_status
             WHEN 'live' THEN ls.status = 'live'
             WHEN 'ended' THEN ls.status = 'ended' AND ls.started_at IS NOT NULL
             ELSE ls.status <> 'scheduled'
           END
  ),
  page AS (
    -- Sayfa kesimi ile sayfa içi sıra aynı ifade (sayfalar birleşince bozulmaz).
    SELECT f.id,
           row_number() OVER (ORDER BY (f.status = 'live') DESC, f.viewer_count DESC, f.sort_at DESC, f.id) AS rn
      FROM filtered f
     ORDER BY rn
     LIMIT v_limit OFFSET v_offset
  )
  SELECT (SELECT count(*) FROM filtered),
         COALESCE(jsonb_agg(
           private.live_session_json(p.id) || jsonb_build_object(
             'host_name', COALESCE(NULLIF(btrim(h.full_name), ''), h.username),
             'host_username', h.username,
             'message_count', (SELECT count(*) FROM public.live_messages m WHERE m.session_id = p.id),
             'duration_seconds', CASE WHEN ls.started_at IS NULL THEN 0 ELSE
               GREATEST(0, floor(extract(epoch FROM (COALESCE(ls.ended_at, now()) - ls.started_at))))::integer END,
             'ended_note', ls.ended_note,
             'ended_by_name', COALESCE(NULLIF(btrim(e.full_name), ''), e.username),
             'shop_access', private.live_shop_access(ls.shop_id)
           ) ORDER BY p.rn), '[]'::jsonb)
    INTO v_total, v_rows
    FROM page p
    JOIN public.live_sessions ls ON ls.id = p.id
    LEFT JOIN public.profiles h ON h.id = ls.host_user_id
    LEFT JOIN public.profiles e ON e.id = ls.ended_by;

  RETURN jsonb_build_object(
    'total', COALESCE(v_total, 0),
    'rows', v_rows,
    'summary', jsonb_build_object(
      'live_now', (SELECT count(*) FROM public.live_sessions
                    WHERE status = 'live' AND last_heartbeat_at > now() - interval '2 minutes'),
      'preparing', (SELECT count(*) FROM public.live_sessions WHERE status = 'scheduled'),
      'today', (SELECT count(*) FROM public.live_sessions WHERE started_at >= v_day_start),
      'minutes_7d', (SELECT COALESCE(round(sum(extract(epoch FROM (COALESCE(ended_at, now()) - started_at))) / 60), 0)::integer
                       FROM public.live_sessions WHERE started_at > now() - interval '7 days'),
      'admin_closed_30d', (SELECT count(*) FROM public.live_sessions
                            WHERE ended_reason = 'admin' AND ended_at > now() - interval '30 days'),
      'granted_shops', (SELECT count(*) FROM public.shop_live_permissions WHERE permission = 'granted'),
      'revoked_shops', (SELECT count(*) FROM public.shop_live_permissions WHERE permission = 'revoked')
    ),
    'settings', jsonb_build_object(
      'enabled', private.live_module_enabled(),
      'access', private.live_access_mode()
    )
  );
END;
$fn$;

-- p_filter: 'all' | 'granted' | 'revoked' | 'streamed' (en az bir kez yayın açmış)
CREATE OR REPLACE FUNCTION public.admin_live_shops(
  p_search text DEFAULT NULL,
  p_filter text DEFAULT 'all',
  p_limit integer DEFAULT 30,
  p_offset integer DEFAULT 0
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $fn$
DECLARE
  v_search text := NULLIF(btrim(COALESCE(p_search, '')), '');
  v_pattern text;
  v_filter text := CASE WHEN p_filter IN ('all', 'granted', 'revoked', 'streamed') THEN p_filter ELSE 'all' END;
  v_limit integer := LEAST(GREATEST(COALESCE(p_limit, 30), 1), 100);
  v_offset integer := GREATEST(COALESCE(p_offset, 0), 0);
  v_total integer;
  v_rows jsonb;
BEGIN
  IF NOT public.auth_is_admin() THEN
    RAISE EXCEPTION 'Yönetici yetkisi gerekli' USING ERRCODE = '42501';
  END IF;
  IF v_search IS NOT NULL THEN
    v_pattern := '%' || replace(replace(replace(v_search, '\', '\\'), '%', '\%'), '_', '\_') || '%';
  END IF;

  WITH base AS (
    SELECT s.id, s.name, s.logo_url,
           COALESCE(s.is_active, false) AS is_active,
           COALESCE(s.is_approved, false) AS is_approved,
           s.owner_id,
           COALESCE(NULLIF(btrim(o.full_name), ''), o.username) AS owner_name,
           o.username AS owner_username,
           perm.permission, perm.note, perm.updated_at AS permission_updated_at, perm.updated_by,
           st.session_count, st.last_live_at, st.live_id
      FROM public.shops s
      LEFT JOIN public.profiles o ON o.id = s.owner_id
      LEFT JOIN public.shop_live_permissions perm ON perm.shop_id = s.id
      LEFT JOIN LATERAL (
        SELECT count(*) FILTER (WHERE ls.started_at IS NOT NULL) AS session_count,
               max(ls.started_at) AS last_live_at,
               (array_agg(ls.id) FILTER (WHERE ls.status = 'live'))[1] AS live_id
          FROM public.live_sessions ls
         WHERE ls.shop_id = s.id
      ) st ON true
     WHERE (v_pattern IS NULL OR s.name ILIKE v_pattern OR o.full_name ILIKE v_pattern OR o.username ILIKE v_pattern)
       AND CASE v_filter
             WHEN 'granted' THEN perm.permission IS NOT DISTINCT FROM 'granted'
             WHEN 'revoked' THEN perm.permission IS NOT DISTINCT FROM 'revoked'
             WHEN 'streamed' THEN st.session_count > 0
             ELSE true
           END
  ),
  page AS (
    SELECT b.*,
           row_number() OVER (ORDER BY (b.live_id IS NOT NULL) DESC, b.last_live_at DESC NULLS LAST, lower(b.name), b.id) AS rn
      FROM base b
     ORDER BY rn
     LIMIT v_limit OFFSET v_offset
  )
  SELECT (SELECT count(*) FROM base),
         COALESCE(jsonb_agg(jsonb_build_object(
           'shop_id', p.id,
           'shop_name', p.name,
           'logo_url', p.logo_url,
           'is_active', p.is_active,
           'is_approved', p.is_approved,
           'owner_id', p.owner_id,
           'owner_name', p.owner_name,
           'owner_username', p.owner_username,
           'permission', p.permission,
           'note', p.note,
           'permission_updated_at', p.permission_updated_at,
           'updated_by_name', COALESCE(NULLIF(btrim(u.full_name), ''), u.username),
           'effective', private.live_shop_access(p.id),
           'session_count', p.session_count,
           'last_live_at', p.last_live_at,
           'live_session_id', p.live_id
         ) ORDER BY p.rn), '[]'::jsonb)
    INTO v_total, v_rows
    FROM page p
    LEFT JOIN public.profiles u ON u.id = p.updated_by;

  RETURN jsonb_build_object(
    'total', COALESCE(v_total, 0),
    'rows', v_rows,
    'summary', jsonb_build_object(
      'granted', (SELECT count(*) FROM public.shop_live_permissions WHERE permission = 'granted'),
      'revoked', (SELECT count(*) FROM public.shop_live_permissions WHERE permission = 'revoked')
    ),
    'settings', jsonb_build_object(
      'enabled', private.live_module_enabled(),
      'access', private.live_access_mode()
    )
  );
END;
$fn$;

-- Tek yayını kapat (hazırlıktaysa kayıt silinir). Özet döner.
CREATE OR REPLACE FUNCTION public.admin_end_live_session(p_session_id uuid, p_note text DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $fn$
DECLARE
  v_status text;
  v_note text := NULLIF(btrim(left(COALESCE(p_note, ''), 300)), '');
BEGIN
  IF NOT public.auth_is_admin() THEN
    RAISE EXCEPTION 'Yönetici yetkisi gerekli' USING ERRCODE = '42501';
  END IF;
  SELECT status INTO v_status FROM public.live_sessions WHERE id = p_session_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Yayın bulunamadı' USING ERRCODE = 'P0001', HINT = 'LIVE_NOT_FOUND';
  END IF;
  IF v_status = 'ended' THEN
    RAISE EXCEPTION 'Bu yayın zaten sona erdi' USING ERRCODE = 'P0001', HINT = 'LIVE_ENDED';
  END IF;
  RETURN private.live_admin_close(p_session_id, v_note);
END;
$fn$;

-- p_permission: 'granted' | 'revoked' | 'default' (kaydı sil → moda göre).
-- İzin kalkınca mağazanın açık yayını kapatılır; erişimi değişen satıcıya bildirim.
CREATE OR REPLACE FUNCTION public.admin_set_shop_live_permission(
  p_shop_id uuid,
  p_permission text,
  p_note text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $fn$
DECLARE
  v_owner uuid;
  v_name text;
  v_note text := NULLIF(btrim(left(COALESCE(p_note, ''), 300)), '');
  v_before text;
  v_after text;
  v_session uuid;
  v_closed integer := 0;
BEGIN
  IF NOT public.auth_is_admin() THEN
    RAISE EXCEPTION 'Yönetici yetkisi gerekli' USING ERRCODE = '42501';
  END IF;
  IF p_permission IS NULL OR p_permission NOT IN ('granted', 'revoked', 'default') THEN
    RAISE EXCEPTION 'Geçersiz izin' USING ERRCODE = 'P0001', HINT = 'LIVE_PERMISSION_INVALID';
  END IF;
  SELECT s.owner_id, s.name INTO v_owner, v_name FROM public.shops s WHERE s.id = p_shop_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Mağaza bulunamadı' USING ERRCODE = 'P0001', HINT = 'LIVE_SHOP_NOT_FOUND';
  END IF;

  v_before := private.live_shop_access(p_shop_id, true);
  IF p_permission = 'default' THEN
    DELETE FROM public.shop_live_permissions WHERE shop_id = p_shop_id;
  ELSE
    INSERT INTO public.shop_live_permissions (shop_id, permission, note, updated_by, updated_at)
    VALUES (p_shop_id, p_permission, v_note, auth.uid(), now())
    ON CONFLICT (shop_id) DO UPDATE
      SET permission = EXCLUDED.permission,
          note = EXCLUDED.note,
          updated_by = EXCLUDED.updated_by,
          updated_at = EXCLUDED.updated_at;
  END IF;
  v_after := private.live_shop_access(p_shop_id, true);

  IF v_after <> 'ok' THEN
    FOR v_session IN
      SELECT id FROM public.live_sessions
       WHERE shop_id = p_shop_id AND status IN ('scheduled', 'live')
    LOOP
      PERFORM private.live_admin_close(v_session, v_note);
      v_closed := v_closed + 1;
    END LOOP;
  END IF;

  IF v_before IS DISTINCT FROM v_after THEN
    IF v_after = 'ok' THEN
      PERFORM private.live_notify(v_owner, 'Canlı yayın iznin açıldı',
        format('%s mağazası artık canlı yayın açabilir. Satıcı paneli › Canlı Yayın.', v_name),
        p_shop_id::text, 'shop');
    ELSE
      PERFORM private.live_notify(v_owner, 'Canlı yayın iznin kaldırıldı',
        format('%s mağazasının canlı yayın izni yönetim tarafından kaldırıldı%s.', v_name, COALESCE(': ' || v_note, '')),
        p_shop_id::text, 'shop');
    END IF;
  END IF;

  RETURN jsonb_build_object(
    'permission', CASE WHEN p_permission = 'default' THEN NULL ELSE p_permission END,
    'effective', private.live_shop_access(p_shop_id),
    'closed', v_closed
  );
END;
$fn$;

-- Genel anahtar ve erişim modu (NULL = değiştirme). p_close_running: yeni
-- ayarlarda artık izinli olmayan süren/hazırlıktaki yayınları da kapat.
CREATE OR REPLACE FUNCTION public.admin_set_live_settings(
  p_enabled boolean DEFAULT NULL,
  p_access text DEFAULT NULL,
  p_close_running boolean DEFAULT false
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $fn$
DECLARE
  v_row record;
  v_closed integer := 0;
BEGIN
  IF NOT public.auth_is_admin() THEN
    RAISE EXCEPTION 'Yönetici yetkisi gerekli' USING ERRCODE = '42501';
  END IF;
  IF p_access IS NOT NULL AND p_access NOT IN ('open', 'invite') THEN
    RAISE EXCEPTION 'Geçersiz erişim modu' USING ERRCODE = 'P0001', HINT = 'LIVE_ACCESS_INVALID';
  END IF;

  IF p_enabled IS NOT NULL THEN
    INSERT INTO public.app_settings (key, value, updated_at)
    VALUES ('live_stream_enabled', to_jsonb(CASE WHEN p_enabled THEN 'true' ELSE 'false' END), now())
    ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value, updated_at = EXCLUDED.updated_at;
  END IF;
  IF p_access IS NOT NULL THEN
    INSERT INTO public.app_settings (key, value, updated_at)
    VALUES ('live_stream_access', to_jsonb(p_access), now())
    ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value, updated_at = EXCLUDED.updated_at;
  END IF;

  IF COALESCE(p_close_running, false) THEN
    FOR v_row IN
      SELECT id, shop_id FROM public.live_sessions WHERE status IN ('scheduled', 'live')
    LOOP
      IF private.live_shop_access(v_row.shop_id) <> 'ok' THEN
        PERFORM private.live_admin_close(v_row.id, NULL);
        v_closed := v_closed + 1;
      END IF;
    END LOOP;
  END IF;

  RETURN jsonb_build_object(
    'enabled', private.live_module_enabled(),
    'access', private.live_access_mode(),
    'closed', v_closed
  );
END;
$fn$;

-- -----------------------------------------------------------------------------
-- 5) Yetkiler
-- -----------------------------------------------------------------------------
REVOKE ALL ON FUNCTION public.admin_live_sessions(text, integer, integer) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.admin_live_shops(text, text, integer, integer) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.admin_end_live_session(uuid, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.admin_set_shop_live_permission(uuid, text, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.admin_set_live_settings(boolean, text, boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_live_sessions(text, integer, integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_live_shops(text, text, integer, integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_end_live_session(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_set_shop_live_permission(uuid, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_set_live_settings(boolean, text, boolean) TO authenticated;

-- Yeniden tanımlananların yetkileri korunur (CREATE OR REPLACE); yine de açıkça:
REVOKE ALL ON FUNCTION public.live_create_session(uuid, text, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.start_live_session(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.live_create_session(uuid, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.start_live_session(uuid) TO authenticated;
REVOKE ALL ON FUNCTION public.live_sessions_feed(integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.live_sessions_feed(integer) TO anon, authenticated;
REVOKE ALL ON FUNCTION public.live_token_grant(uuid, text, uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.live_token_grant(uuid, text, uuid) TO service_role;

COMMIT;

NOTIFY pgrst, 'reload schema';
