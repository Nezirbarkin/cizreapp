-- =============================================================================
-- Kullanıcı canlı yayını: mağazası olmayan kullanıcılar da yayın açabilir
-- =============================================================================
--
-- 1) live_sessions.shop_id artık boş olabilir: shop_id NULL = kullanıcı
--    yayını (yayıncı = host_user_id). Kullanıcı başına tek açık yayın.
--    Ürün sabitleme kullanıcı yayınında zaten çalışmaz (ürün mağazaya bağlı).
-- 2) Erişim: genel anahtar (live_stream_enabled) her iki türe uygulanır;
--    kullanıcılar için ayrıca `live_user_streams` = 'open' (her aktif hesap,
--    izni kaldırılmadıkça) | 'invite' (yalnız izin verilenler) | 'off'.
--    Kişi bazında izin `user_live_permissions` (istemciye tamamen kapalı).
--    Kontrol 3 kapıda: live_create_user_session, start_live_session
--    (hazırlıktayken), live_token_grant (host + hazırlık).
-- 3) Gizlilik: gizli hesabın yayınını yalnız takipçileri, engelleşen
--    kişiler hiç göremez (akış, ayrıntı, geçmiş, ana sayfa kartı, izleyici
--    anahtarı, sohbet ve live_sessions/live_messages satırları). Yönetici ve
--    'live' moderatörü her yayını görür.
-- 4) "Yayın başladı" bildirimi kullanıcı yayınında yayıncının takipçilerine
--    gider (ayar: live_notify_user_followers); bekleme süresi yayıncı bazında.
-- 5) Yönetim: admin_live_users, admin_set_user_live_permission,
--    admin_set_user_live_mode; admin_live_sessions / admin_end_live_session /
--    admin_set_live_settings kullanıcı yayınlarını da kapsar. Kategori sınırlı
--    moderatör kullanıcı yayınını görmez (kategorisiz mağaza kuralıyla aynı).
--
-- Mağaza yayınının davranışı DEĞİŞMEZ; yalnız JOIN shops → LEFT JOIN ve izin
-- kontrolü türe göre dağıtılır.

BEGIN;

-- -----------------------------------------------------------------------------
-- 1) Şema
-- -----------------------------------------------------------------------------
ALTER TABLE public.live_sessions ALTER COLUMN shop_id DROP NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS live_sessions_one_open_per_user
  ON public.live_sessions (host_user_id)
  WHERE shop_id IS NULL AND status IN ('scheduled', 'live');

ALTER TABLE public.live_notify_log ALTER COLUMN shop_id DROP NOT NULL;
ALTER TABLE public.live_notify_log
  ADD COLUMN IF NOT EXISTS host_user_id uuid REFERENCES public.profiles(id) ON DELETE CASCADE;
CREATE INDEX IF NOT EXISTS idx_live_notify_log_host_sent
  ON public.live_notify_log (host_user_id, notified_at DESC)
  WHERE skipped IS NULL AND shop_id IS NULL;

INSERT INTO public.app_settings (key, value, description)
VALUES
  ('live_user_streams', '"open"',
   'Kullanıcı (mağazasız) canlı yayını: "open" = her aktif hesap, "invite" = yalnız izin verilenler, "off" = kapalı.'),
  ('live_notify_user_followers', '"true"',
   'Kullanıcı canlı yayına başlayınca takipçilerine bildirim.')
ON CONFLICT (key) DO NOTHING;

CREATE TABLE IF NOT EXISTS public.user_live_permissions (
  user_id    uuid PRIMARY KEY REFERENCES public.profiles(id) ON DELETE CASCADE,
  permission text NOT NULL CHECK (permission IN ('granted', 'revoked')),
  note       text CHECK (note IS NULL OR char_length(note) <= 300),
  updated_by uuid,
  updated_at timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.user_live_permissions IS
  'Kullanıcının canlı yayın izni (satır yok = live_user_streams moduna göre). Yalnız yönetim RPC''leri yazar/okur.';

ALTER TABLE public.user_live_permissions ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.user_live_permissions FROM PUBLIC, anon, authenticated;

-- -----------------------------------------------------------------------------
-- 2) Yardımcılar
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION private.live_user_mode()
RETURNS text
LANGUAGE sql
STABLE
SET search_path = ''
AS $fn$
  SELECT CASE private.live_setting('live_user_streams')
    WHEN 'off' THEN 'off'
    WHEN 'invite' THEN 'invite'
    ELSE 'open'
  END;
$fn$;

-- 'ok' | LIVE_DISABLED | LIVE_ACCOUNT_INACTIVE | LIVE_USERS_OFF |
-- LIVE_USER_REVOKED | LIVE_USER_NOT_PERMITTED.
-- p_ignore_global: genel anahtarı yok say (bildirim kararı için).
CREATE OR REPLACE FUNCTION private.live_user_access(p_user_id uuid, p_ignore_global boolean DEFAULT false)
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
  IF NOT EXISTS (
    SELECT 1 FROM public.profiles p
     WHERE p.id = p_user_id AND p.status::text = 'active' AND NOT COALESCE(p.is_bot, false)
  ) THEN
    RETURN 'LIVE_ACCOUNT_INACTIVE';
  END IF;
  IF private.live_user_mode() = 'off' THEN
    RETURN 'LIVE_USERS_OFF';
  END IF;
  SELECT permission INTO v_permission FROM public.user_live_permissions WHERE user_id = p_user_id;
  IF v_permission = 'revoked' THEN
    RETURN 'LIVE_USER_REVOKED';
  END IF;
  IF v_permission = 'granted' OR private.live_user_mode() = 'open' THEN
    RETURN 'ok';
  END IF;
  RETURN 'LIVE_USER_NOT_PERMITTED';
END;
$fn$;

-- Yayının türüne göre erişim (mağaza: 4.3 kuralı; kullanıcı: yukarısı).
CREATE OR REPLACE FUNCTION private.live_session_access(p_shop_id uuid, p_host_user_id uuid)
RETURNS text
LANGUAGE sql
STABLE
SET search_path = ''
AS $fn$
  SELECT CASE WHEN p_shop_id IS NOT NULL
    THEN private.live_shop_access(p_shop_id)
    ELSE private.live_user_access(p_host_user_id)
  END;
$fn$;

CREATE OR REPLACE FUNCTION private.live_assert_session_access(p_shop_id uuid, p_host_user_id uuid)
RETURNS void
LANGUAGE plpgsql
STABLE
SET search_path = ''
AS $fn$
DECLARE
  v_access text;
  v_note text;
BEGIN
  IF p_shop_id IS NOT NULL THEN
    PERFORM private.live_assert_access(p_shop_id);
    RETURN;
  END IF;
  v_access := private.live_user_access(p_host_user_id);
  IF v_access = 'ok' THEN
    RETURN;
  END IF;
  IF v_access = 'LIVE_USER_REVOKED' THEN
    SELECT note INTO v_note FROM public.user_live_permissions WHERE user_id = p_host_user_id;
  END IF;
  RAISE EXCEPTION USING
    MESSAGE = CASE v_access
      WHEN 'LIVE_DISABLED' THEN 'Canlı yayın şu anda kapalı'
      WHEN 'LIVE_ACCOUNT_INACTIVE' THEN 'Hesabın canlı yayın açmaya uygun değil'
      WHEN 'LIVE_USERS_OFF' THEN 'Kullanıcı canlı yayınları şu anda kapalı'
      WHEN 'LIVE_USER_REVOKED' THEN 'Canlı yayın iznin yönetim tarafından kaldırıldı'
      ELSE 'Canlı yayın şu an yalnız izin verilen kullanıcılara açık'
    END,
    ERRCODE = 'P0001',
    HINT = v_access,
    DETAIL = COALESCE(v_note, '');
END;
$fn$;

-- Yönetici ya da aktif 'live' moderatörü (oturumsuz bağlamda da: uid ile).
CREATE OR REPLACE FUNCTION private.live_is_staff(p_user_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SET search_path = ''
AS $fn$
  SELECT p_user_id IS NOT NULL AND (
    EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = p_user_id AND p.role = 'admin'::public.user_role)
    OR EXISTS (
      SELECT 1 FROM public.moderators m
      JOIN public.profiles p ON p.id = m.user_id
      WHERE m.user_id = p_user_id AND p.status::text = 'active' AND 'live' = ANY (m.scopes)
    )
  );
$fn$;

-- Kullanıcı yayınını görebilir mi: engelleşme yok VE (hesap herkese açık YA
-- DA izleyici takipçi). Misafir gizli hesabı göremez.
CREATE OR REPLACE FUNCTION private.live_viewer_can_see_host(p_host_user_id uuid, p_viewer uuid)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SET search_path = ''
AS $fn$
BEGIN
  IF p_viewer IS NOT NULL AND p_viewer = p_host_user_id THEN
    RETURN true;
  END IF;
  IF private.live_is_staff(p_viewer) THEN
    RETURN true;
  END IF;
  IF p_viewer IS NOT NULL AND EXISTS (
    SELECT 1 FROM public.blocked_users b
     WHERE (b.blocker_id = p_viewer AND b.blocked_id = p_host_user_id)
        OR (b.blocker_id = p_host_user_id AND b.blocked_id = p_viewer)
  ) THEN
    RETURN false;
  END IF;
  IF COALESCE((SELECT pr.profile_is_public FROM public.profiles pr WHERE pr.id = p_host_user_id), true) THEN
    RETURN true;
  END IF;
  RETURN p_viewer IS NOT NULL AND EXISTS (
    SELECT 1 FROM public.follows f WHERE f.follower_id = p_viewer AND f.following_id = p_host_user_id
  );
END;
$fn$;

-- Herkese açık listelerde (akış, geçmiş, kart) gösterilir mi.
-- Mağaza: aktif ve onaylı. Kullanıcı: hesap aktif ve izleyici görebilir.
CREATE OR REPLACE FUNCTION private.live_session_listable(p_shop_id uuid, p_host_user_id uuid, p_viewer uuid)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SET search_path = ''
AS $fn$
BEGIN
  IF p_shop_id IS NOT NULL THEN
    RETURN EXISTS (
      SELECT 1 FROM public.shops s
       WHERE s.id = p_shop_id AND COALESCE(s.is_active, false) AND COALESCE(s.is_approved, false)
    );
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.profiles p
     WHERE p.id = p_host_user_id AND p.status::text = 'active' AND NOT COALESCE(p.is_bot, false)
  ) THEN
    RETURN private.live_is_staff(p_viewer);
  END IF;
  RETURN private.live_viewer_can_see_host(p_host_user_id, p_viewer);
END;
$fn$;

REVOKE ALL ON FUNCTION private.live_user_mode() FROM PUBLIC;
REVOKE ALL ON FUNCTION private.live_user_access(uuid, boolean) FROM PUBLIC;
REVOKE ALL ON FUNCTION private.live_session_access(uuid, uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION private.live_assert_session_access(uuid, uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION private.live_is_staff(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION private.live_viewer_can_see_host(uuid, uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION private.live_session_listable(uuid, uuid, uuid) FROM PUBLIC;

-- Politika yardımcıları (satır başına çağrılır → plpgsql; mağaza yayını
-- hemen true döner, eski "herkes okur" davranışı korunur).
CREATE OR REPLACE FUNCTION public.live_session_row_visible(p_shop_id uuid, p_host_user_id uuid)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $fn$
BEGIN
  IF p_shop_id IS NOT NULL THEN
    RETURN true;
  END IF;
  RETURN private.live_viewer_can_see_host(p_host_user_id, auth.uid());
END;
$fn$;

CREATE OR REPLACE FUNCTION public.live_message_visible(p_session_id uuid)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $fn$
DECLARE
  v_shop uuid;
  v_host uuid;
BEGIN
  SELECT shop_id, host_user_id INTO v_shop, v_host FROM public.live_sessions WHERE id = p_session_id;
  IF NOT FOUND THEN
    RETURN false;
  END IF;
  IF v_shop IS NOT NULL THEN
    RETURN true;
  END IF;
  RETURN private.live_viewer_can_see_host(v_host, auth.uid());
END;
$fn$;

REVOKE ALL ON FUNCTION public.live_session_row_visible(uuid, uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.live_message_visible(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.live_session_row_visible(uuid, uuid) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.live_message_visible(uuid) TO anon, authenticated;

DROP POLICY IF EXISTS "live_sessions_select_all" ON public.live_sessions;
DROP POLICY IF EXISTS "live_sessions_select_visible" ON public.live_sessions;
CREATE POLICY "live_sessions_select_visible" ON public.live_sessions
  FOR SELECT
  USING (public.live_session_row_visible(shop_id, host_user_id));

DROP POLICY IF EXISTS "live_messages_select_all" ON public.live_messages;
DROP POLICY IF EXISTS "live_messages_select_visible" ON public.live_messages;
CREATE POLICY "live_messages_select_visible" ON public.live_messages
  FOR SELECT
  USING (public.live_message_visible(session_id));

-- -----------------------------------------------------------------------------
-- 3) Yayın JSON'u: mağaza ya da yayıncı kimliği
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION private.live_session_json(p_session_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SET search_path = ''
AS $fn$
DECLARE
  v_json jsonb;
BEGIN
  SELECT jsonb_build_object(
    'id', ls.id,
    'kind', CASE WHEN ls.shop_id IS NULL THEN 'user' ELSE 'shop' END,
    'shop_id', ls.shop_id,
    'host_user_id', ls.host_user_id,
    'title', ls.title,
    'description', ls.description,
    'cover_image_url', ls.cover_image_url,
    'channel_name', ls.channel_name,
    'status', ls.status,
    'is_live', (ls.status = 'live' AND ls.last_heartbeat_at > now() - interval '2 minutes'),
    'started_at', ls.started_at,
    'ended_at', ls.ended_at,
    'ended_reason', ls.ended_reason,
    'viewer_count', ls.viewer_count,
    'peak_viewer_count', ls.peak_viewer_count,
    'last_heartbeat_at', ls.last_heartbeat_at,
    'created_at', ls.created_at,
    'updated_at', ls.updated_at,
    'shop_name', s.name,
    'shop_logo_url', s.logo_url,
    -- Yayıncı kimliği yalnız kullanıcı yayınında (satıcının kişisel hesabı
    -- mağaza yayınında gösterilmez). Önce kullanıcı adı, yoksa ad.
    'host_display_name', CASE WHEN ls.shop_id IS NULL THEN
      COALESCE(NULLIF(btrim(h.username), ''), NULLIF(btrim(h.full_name), ''), 'Kullanıcı') END,
    'host_username', CASE WHEN ls.shop_id IS NULL THEN NULLIF(btrim(h.username), '') END,
    'host_avatar_url', CASE WHEN ls.shop_id IS NULL THEN h.avatar_url END,
    'pinned_product', CASE WHEN p.id IS NULL THEN NULL ELSE jsonb_build_object(
      'id', p.id,
      'name', p.name,
      'image_url', p.image_url,
      'price', p.price,
      'discount_price', p.discount_price,
      'effective_price', CASE
        WHEN p.discount_price IS NOT NULL AND p.discount_price > 0 AND p.discount_price < p.price
          THEN p.discount_price
        ELSE p.price
      END,
      'is_available', COALESCE(p.is_available, false)
    ) END
  )
  INTO v_json
  FROM public.live_sessions ls
  LEFT JOIN public.shops s ON s.id = ls.shop_id
  LEFT JOIN public.profiles h ON h.id = ls.host_user_id
  LEFT JOIN public.products p ON p.id = ls.pinned_product_id
  WHERE ls.id = p_session_id;

  RETURN v_json;
END;
$fn$;

-- -----------------------------------------------------------------------------
-- 4) Mesaj tetikleyicisi: yayıncı kullanıcıysa kendi adıyla; gizli yayına
--    göremeyen kişi yazamaz.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION private.live_messages_before_insert()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $fn$
DECLARE
  v_session public.live_sessions%ROWTYPE;
  v_text text;
  v_recent integer;
BEGIN
  SELECT * INTO v_session FROM public.live_sessions WHERE id = NEW.session_id;
  IF NOT FOUND
     OR (v_session.shop_id IS NULL AND NOT private.live_viewer_can_see_host(v_session.host_user_id, NEW.user_id)) THEN
    RAISE EXCEPTION 'Yayın bulunamadı' USING ERRCODE = 'P0001', HINT = 'LIVE_NOT_FOUND';
  END IF;
  IF v_session.status <> 'live' THEN
    RAISE EXCEPTION 'Yayın şu an canlı değil' USING ERRCODE = 'P0001', HINT = 'LIVE_NOT_LIVE';
  END IF;

  v_text := btrim(regexp_replace(COALESCE(NEW.message, ''), '\s+', ' ', 'g'));
  IF char_length(v_text) = 0 THEN
    RAISE EXCEPTION 'Mesaj boş olamaz' USING ERRCODE = 'P0001', HINT = 'LIVE_MESSAGE_EMPTY';
  END IF;
  IF char_length(v_text) > 300 THEN
    RAISE EXCEPTION 'Mesaj en fazla 300 karakter olabilir' USING ERRCODE = 'P0001', HINT = 'LIVE_MESSAGE_TOO_LONG';
  END IF;

  SELECT count(*) INTO v_recent
    FROM public.live_messages m
   WHERE m.session_id = NEW.session_id
     AND m.user_id = NEW.user_id
     AND m.created_at > now() - interval '10 seconds';
  IF v_recent >= 5 THEN
    RAISE EXCEPTION 'Çok hızlı mesaj gönderiyorsun; biraz bekle' USING ERRCODE = 'P0001', HINT = 'LIVE_MESSAGE_RATE';
  END IF;

  NEW.message := v_text;
  NEW.created_at := now();
  NEW.is_host := (NEW.user_id = v_session.host_user_id);
  NEW.author_name := NULL;
  NEW.author_avatar := NULL;

  IF NEW.is_host AND v_session.shop_id IS NOT NULL THEN
    -- Satıcının mesajı mağaza adıyla görünür.
    SELECT s.name, s.logo_url INTO NEW.author_name, NEW.author_avatar
      FROM public.shops s WHERE s.id = v_session.shop_id;
  ELSE
    -- Herkese açık sohbet (ve kullanıcı yayıncı): önce kullanıcı adı, yoksa ad.
    SELECT COALESCE(NULLIF(btrim(p.username), ''), NULLIF(btrim(p.full_name), '')), p.avatar_url
      INTO NEW.author_name, NEW.author_avatar
      FROM public.profiles p WHERE p.id = NEW.user_id;
  END IF;
  NEW.author_name := COALESCE(NULLIF(btrim(NEW.author_name), ''), 'Kullanıcı');

  RETURN NEW;
END;
$fn$;

-- -----------------------------------------------------------------------------
-- 5) Kullanıcı yayını hazırla (ya da açık yayınını sürdür)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.live_create_user_session(
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
  v_title text := btrim(regexp_replace(COALESCE(p_title, ''), '\s+', ' ', 'g'));
  v_desc text := NULLIF(btrim(COALESCE(p_description, '')), '');
  v_open public.live_sessions%ROWTYPE;
  v_has_open boolean;
  v_id uuid;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Oturum açmanız gerekli' USING ERRCODE = '42501', HINT = 'AUTH_REQUIRED';
  END IF;
  IF char_length(v_title) < 3 OR char_length(v_title) > 80 THEN
    RAISE EXCEPTION 'Yayın başlığı 3–80 karakter olmalı' USING ERRCODE = 'P0001', HINT = 'LIVE_TITLE_INVALID';
  END IF;
  v_desc := left(v_desc, 300);

  SELECT * INTO v_open
    FROM public.live_sessions
   WHERE host_user_id = v_uid AND shop_id IS NULL AND status IN ('scheduled', 'live')
   FOR UPDATE;
  v_has_open := FOUND;

  -- Süren (taze) yayın sürdürülür: uygulama kapanıp açıldı.
  IF v_has_open AND v_open.status = 'live' AND v_open.last_heartbeat_at > now() - interval '2 minutes' THEN
    RETURN private.live_session_json(v_open.id) || jsonb_build_object('resumed', true);
  END IF;

  PERFORM private.live_assert_session_access(NULL, v_uid);

  IF v_has_open THEN
    IF v_open.status = 'scheduled' THEN
      UPDATE public.live_sessions SET title = v_title, description = v_desc WHERE id = v_open.id;
      RETURN private.live_session_json(v_open.id) || jsonb_build_object('resumed', false);
    END IF;
    PERFORM private.live_close_session(v_open.id, 'timeout');
  END IF;

  BEGIN
    INSERT INTO public.live_sessions (host_user_id, shop_id, title, description, channel_name, status)
    VALUES (v_uid, NULL, v_title, v_desc, 'cz_' || replace(gen_random_uuid()::text, '-', ''), 'scheduled')
    RETURNING id INTO v_id;
  EXCEPTION WHEN unique_violation THEN
    -- Aynı anda ikinci cihazdan açıldı: açık olanı dön.
    SELECT id INTO v_id FROM public.live_sessions
     WHERE host_user_id = v_uid AND shop_id IS NULL AND status IN ('scheduled', 'live');
  END;

  RETURN private.live_session_json(v_id) || jsonb_build_object('resumed', false);
END;
$fn$;

-- Uygulamanın "Yayın aç" düğmesi için: kişinin şu anki erişimi.
CREATE OR REPLACE FUNCTION public.live_my_stream_access()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $fn$
DECLARE
  v_uid uuid := auth.uid();
  v_access text;
  v_note text;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('access', 'AUTH_REQUIRED', 'mode', private.live_user_mode());
  END IF;
  v_access := private.live_user_access(v_uid);
  IF v_access = 'LIVE_USER_REVOKED' THEN
    SELECT note INTO v_note FROM public.user_live_permissions WHERE user_id = v_uid;
  END IF;
  RETURN jsonb_build_object('access', v_access, 'mode', private.live_user_mode(), 'note', v_note);
END;
$fn$;

-- -----------------------------------------------------------------------------
-- 6) Yayını başlat: 20260928000021 tanımı; mağaza kontrolü yalnız mağaza
--    yayınında, izin kontrolü türe göre.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.start_live_session(p_session_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $fn$
DECLARE
  v public.live_sessions%ROWTYPE;
  v_active boolean;
  v_notified integer;
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
  IF v.shop_id IS NOT NULL THEN
    SELECT COALESCE(s.is_active, false) AND COALESCE(s.is_approved, false) INTO v_active
      FROM public.shops s WHERE s.id = v.shop_id;
    IF NOT COALESCE(v_active, false) THEN
      RAISE EXCEPTION 'Yayın için mağazanız aktif ve onaylı olmalı' USING ERRCODE = 'P0001', HINT = 'LIVE_SHOP_INACTIVE';
    END IF;
  END IF;
  -- Hazırlıktan canlıya geçiş izin ister (canlıyken tekrar çağrı = sinyal).
  IF v.status = 'scheduled' THEN
    PERFORM private.live_assert_session_access(v.shop_id, v.host_user_id);
  END IF;

  UPDATE public.live_sessions
     SET status = 'live',
         started_at = COALESCE(started_at, now()),
         last_heartbeat_at = now()
   WHERE id = p_session_id;

  -- Hazırlıktan canlıya ilk geçiş: "yayın başladı" bildirimi. Hata yayını
  -- engellemez (alt işlem geri alınır, yayın başlar).
  IF v.status = 'scheduled' THEN
    BEGIN
      v_notified := private.live_notify_started(p_session_id);
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'live_notify_started(%): % (%)', p_session_id, SQLERRM, SQLSTATE;
    END;
  END IF;

  RETURN private.live_session_json(p_session_id) || jsonb_build_object('notified', v_notified);
END;
$fn$;

-- -----------------------------------------------------------------------------
-- 7) Agora anahtarı yetkisi: mağaza kontrolü türe göre; izleyici gizliliği
-- -----------------------------------------------------------------------------
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
  IF v.shop_id IS NOT NULL THEN
    SELECT COALESCE(s.is_active, false) AND COALESCE(s.is_approved, false) INTO v_active
      FROM public.shops s WHERE s.id = v.shop_id;
    IF NOT COALESCE(v_active, false) THEN
      RETURN jsonb_build_object('ok', false, 'error', 'SHOP_INACTIVE');
    END IF;
  END IF;

  IF p_role = 'host' THEN
    IF p_user_id IS NULL THEN
      RETURN jsonb_build_object('ok', false, 'error', 'AUTH_REQUIRED');
    END IF;
    IF p_user_id <> v.host_user_id THEN
      RETURN jsonb_build_object('ok', false, 'error', 'FORBIDDEN');
    END IF;
    -- Henüz başlamamış yayına anahtar izin ister; süren yayının anahtar
    -- yenilemesi yönetici kapatana dek sürer.
    IF v.status = 'scheduled' THEN
      v_access := private.live_session_access(v.shop_id, v.host_user_id);
      IF v_access <> 'ok' THEN
        RETURN jsonb_build_object('ok', false, 'error', v_access);
      END IF;
    END IF;
  ELSE
    -- Kullanıcı yayını: gizli hesap / engel / pasif hesap → yok say.
    IF v.shop_id IS NULL AND NOT private.live_session_listable(NULL, v.host_user_id, p_user_id) THEN
      RETURN jsonb_build_object('ok', false, 'error', 'NOT_FOUND');
    END IF;
    IF v.status <> 'live' OR v.last_heartbeat_at IS NULL
       OR v.last_heartbeat_at < now() - interval '2 minutes' THEN
      RETURN jsonb_build_object('ok', false, 'error', 'NOT_LIVE');
    END IF;
  END IF;

  RETURN jsonb_build_object('ok', true, 'channel', v.channel_name, 'host_uid', 1, 'role', p_role);
END;
$fn$;

-- -----------------------------------------------------------------------------
-- 8) "Yayın başladı" bildirimi: kullanıcı yayınında yayıncının takipçileri
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION private.live_notify_started(p_session_id uuid)
RETURNS integer
LANGUAGE plpgsql
SET search_path = ''
AS $fn$
DECLARE
  v record;
  v_cooldown integer;
  v_max integer;
  v_followers boolean;
  v_fans boolean;
  v_customers boolean;
  v_n integer := 0;
BEGIN
  -- Kullanıcı yayınında "sahip" = yayıncı; ad/görsel profilden.
  SELECT ls.id, ls.shop_id, ls.title, ls.host_user_id,
         COALESCE(s.name, NULLIF(btrim(h.username), ''), NULLIF(btrim(h.full_name), ''), 'Bir kullanıcı') AS shop_name,
         COALESCE(s.owner_id, ls.host_user_id) AS owner_id,
         CASE WHEN ls.shop_id IS NULL THEN h.avatar_url ELSE s.logo_url END AS logo_url
    INTO v
    FROM public.live_sessions ls
    LEFT JOIN public.shops s ON s.id = ls.shop_id
    LEFT JOIN public.profiles h ON h.id = ls.host_user_id
   WHERE ls.id = p_session_id;
  IF NOT FOUND OR EXISTS (SELECT 1 FROM public.live_notify_log l WHERE l.session_id = p_session_id) THEN
    RETURN 0;
  END IF;

  IF NOT private.live_setting_bool('live_notify_enabled', true) THEN
    INSERT INTO public.live_notify_log (session_id, shop_id, host_user_id, recipients, skipped)
    VALUES (v.id, v.shop_id, v.host_user_id, 0, 'disabled');
    RETURN 0;
  END IF;

  v_cooldown := private.live_setting_int('live_notify_cooldown_hours', 3, 0, 72);
  IF EXISTS (SELECT 1 FROM public.live_notify_log l
              WHERE l.skipped IS NULL
                AND (l.shop_id = v.shop_id
                     OR (v.shop_id IS NULL AND l.shop_id IS NULL AND l.host_user_id = v.host_user_id))
                AND l.notified_at > now() - make_interval(hours => v_cooldown)) THEN
    INSERT INTO public.live_notify_log (session_id, shop_id, host_user_id, recipients, skipped)
    VALUES (v.id, v.shop_id, v.host_user_id, 0, 'cooldown');
    RETURN 0;
  END IF;

  v_max := private.live_setting_int('live_notify_max_recipients', 2000, 0, 20000);
  v_followers := CASE WHEN v.shop_id IS NULL
    THEN private.live_setting_bool('live_notify_user_followers', true)
    ELSE private.live_setting_bool('live_notify_followers', true) END;
  v_fans := private.live_setting_bool('live_notify_product_fans', true);
  v_customers := private.live_setting_bool('live_notify_customers', false);

  -- Kullanıcı yayınında shop_id NULL: abone/ürün/müşteri dalları boş kalır.
  WITH audience AS (
    SELECT sub.user_id, 1 AS prio
      FROM public.live_subscriptions sub
     WHERE sub.shop_id = v.shop_id
    UNION ALL
    SELECT f.follower_id, 2
      FROM public.follows f
     WHERE v_followers AND f.following_id = v.owner_id
    UNION ALL
    SELECT pf.user_id, 3
      FROM public.product_favorites pf
      JOIN public.products pr ON pr.id = pf.product_id
     WHERE v_fans AND pr.shop_id = v.shop_id
    UNION ALL
    SELECT o.user_id, 4
      FROM public.orders o
     WHERE v_customers AND o.shop_id = v.shop_id AND o.created_at > now() - interval '90 days'
  ),
  ranked AS (
    SELECT a.user_id, min(a.prio) AS prio
      FROM audience a
     WHERE a.user_id IS NOT NULL
     GROUP BY a.user_id
  ),
  eligible AS (
    SELECT r.user_id
      FROM ranked r
      JOIN public.profiles p ON p.id = r.user_id
     WHERE r.user_id IS DISTINCT FROM v.owner_id
       AND r.user_id IS DISTINCT FROM v.host_user_id
       AND NOT COALESCE(p.is_bot, false)
       AND p.status::text = 'active'
       AND NOT EXISTS (SELECT 1 FROM public.notification_preferences np
                        WHERE np.user_id = r.user_id AND np.live_streams_enabled = false)
       AND NOT EXISTS (SELECT 1 FROM public.blocked_users b
                        WHERE (b.blocker_id = r.user_id AND b.blocked_id = v.owner_id)
                           OR (b.blocker_id = v.owner_id AND b.blocked_id = r.user_id))
     ORDER BY r.prio, r.user_id
     LIMIT v_max
  )
  INSERT INTO public.notifications (
    user_id, type, title, content, actor_id, actor_name, actor_avatar,
    entity_id, entity_type, entity_image, metadata, is_read, created_at
  )
  SELECT e.user_id, 'live_started',
         format('🔴 %s canlı yayında', v.shop_name),
         left(v.title, 120),
         v.owner_id, v.shop_name, v.logo_url,
         v.id::text, 'live_session', v.logo_url,
         jsonb_build_object('route', '/live/' || v.id::text, 'shop_id', v.shop_id::text, 'source', 'live_started'),
         false, now()
    FROM eligible e;
  GET DIAGNOSTICS v_n = ROW_COUNT;

  INSERT INTO public.live_notify_log (session_id, shop_id, host_user_id, recipients, skipped)
  VALUES (v.id, v.shop_id, v.host_user_id, v_n, NULL);
  RETURN v_n;
END;
$fn$;

-- -----------------------------------------------------------------------------
-- 9) Herkese açık okumalar: JOIN shops → live_session_listable
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.live_sessions_feed(p_limit integer DEFAULT 30)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $fn$
DECLARE
  v_limit integer := LEAST(GREATEST(COALESCE(p_limit, 30), 1), 100);
  v_uid uuid := auth.uid();
  v_live jsonb;
  v_recent jsonb;
BEGIN
  SELECT COALESCE(jsonb_agg(private.live_session_json(x.id) ORDER BY x.viewer_count DESC, x.started_at DESC), '[]'::jsonb)
    INTO v_live
    FROM (
      SELECT ls.id, ls.viewer_count, ls.started_at
        FROM public.live_sessions ls
       WHERE ls.status = 'live'
         AND ls.last_heartbeat_at > now() - interval '2 minutes'
         AND private.live_session_listable(ls.shop_id, ls.host_user_id, v_uid)
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
         AND private.live_session_listable(ls.shop_id, ls.host_user_id, v_uid)
       ORDER BY ls.ended_at DESC
       LIMIT 20
    ) y;

  RETURN jsonb_build_object(
    'live', v_live,
    'recent', v_recent,
    'enabled', private.live_module_enabled(),
    'user_mode', private.live_user_mode(),
    -- "Yayın aç" düğmesi: misafirde AUTH_REQUIRED.
    'my_access', CASE WHEN v_uid IS NULL THEN 'AUTH_REQUIRED' ELSE private.live_user_access(v_uid) END
  );
END;
$fn$;

CREATE OR REPLACE FUNCTION public.live_session_detail(p_session_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $fn$
DECLARE
  v_shop uuid;
  v_host uuid;
BEGIN
  SELECT shop_id, host_user_id INTO v_shop, v_host FROM public.live_sessions WHERE id = p_session_id;
  IF NOT FOUND THEN
    RETURN NULL;
  END IF;
  -- Gizli/engelli kullanıcı yayını yok sayılır (mağaza yayını eskisi gibi).
  IF v_shop IS NULL AND NOT private.live_session_listable(NULL, v_host, auth.uid()) THEN
    RETURN NULL;
  END IF;
  RETURN private.live_history_json(p_session_id);
END;
$fn$;

CREATE OR REPLACE FUNCTION public.live_history(
  p_limit integer DEFAULT 20,
  p_offset integer DEFAULT 0,
  p_shop_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $fn$
DECLARE
  v_limit integer := LEAST(GREATEST(COALESCE(p_limit, 20), 1), 50);
  v_offset integer := GREATEST(COALESCE(p_offset, 0), 0);
  v_days integer := private.live_history_days();
  v_uid uuid := auth.uid();
  v_total integer;
  v_rows jsonb;
BEGIN
  WITH filtered AS (
    SELECT ls.id, ls.ended_at
      FROM public.live_sessions ls
     WHERE ls.status = 'ended'
       AND ls.started_at IS NOT NULL
       AND ls.ended_at > now() - make_interval(days => v_days)
       AND (p_shop_id IS NULL OR ls.shop_id = p_shop_id)
       AND private.live_session_listable(ls.shop_id, ls.host_user_id, v_uid)
  ),
  page AS (
    -- Sayfa kesimi ile sayfa içi sıra aynı ifade (sayfalar birleşince bozulmaz).
    SELECT f.id, row_number() OVER (ORDER BY f.ended_at DESC, f.id) AS rn
      FROM filtered f
     ORDER BY rn
     LIMIT v_limit OFFSET v_offset
  )
  SELECT (SELECT count(*) FROM filtered),
         COALESCE(jsonb_agg(private.live_history_json(p.id) ORDER BY p.rn), '[]'::jsonb)
    INTO v_total, v_rows
    FROM page p;

  RETURN jsonb_build_object('total', COALESCE(v_total, 0), 'days', v_days, 'rows', v_rows);
END;
$fn$;

CREATE OR REPLACE FUNCTION public.live_home_card()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $fn$
DECLARE
  v_uid uuid := auth.uid();
  v_live uuid;
  v_last uuid;
  v_count integer;
BEGIN
  IF NOT private.live_setting_bool('live_home_card_enabled', true) OR NOT private.live_module_enabled() THEN
    RETURN jsonb_build_object('enabled', false);
  END IF;

  SELECT count(*) INTO v_count
    FROM public.live_sessions ls
   WHERE ls.status = 'live'
     AND ls.last_heartbeat_at > now() - interval '2 minutes'
     AND private.live_session_listable(ls.shop_id, ls.host_user_id, v_uid);

  SELECT ls.id INTO v_live
    FROM public.live_sessions ls
   WHERE ls.status = 'live'
     AND ls.last_heartbeat_at > now() - interval '2 minutes'
     AND private.live_session_listable(ls.shop_id, ls.host_user_id, v_uid)
   ORDER BY ls.viewer_count DESC, ls.started_at DESC, ls.id
   LIMIT 1;

  SELECT ls.id INTO v_last
    FROM public.live_sessions ls
   WHERE ls.status = 'ended'
     AND ls.started_at IS NOT NULL
     AND ls.ended_at > now() - make_interval(days => private.live_history_days())
     AND private.live_session_listable(ls.shop_id, ls.host_user_id, v_uid)
   ORDER BY ls.ended_at DESC, ls.id
   LIMIT 1;

  RETURN jsonb_build_object(
    'enabled', true,
    'live_count', COALESCE(v_count, 0),
    'live', CASE WHEN v_live IS NULL THEN NULL ELSE private.live_session_json(v_live) END,
    'last', CASE WHEN v_last IS NULL THEN NULL ELSE private.live_history_json(v_last) END
  );
END;
$fn$;

-- -----------------------------------------------------------------------------
-- 10) Yönetim: 20260928000022 tanımları + kullanıcı yayınları
-- -----------------------------------------------------------------------------
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
  -- Kategori sınırı (NULL = hepsi) ve ona giren mağazalar. Sınırlı moderatör
  -- kullanıcı yayınını görmez (shop_id NULL hiçbir diziye girmez).
  v_cats uuid[] := private.moderator_category_ids('shop');
  v_shops uuid[];
BEGIN
  IF NOT public.auth_is_moderator('live') THEN
    RAISE EXCEPTION 'Yönetici ya da moderatör yetkisi gerekli' USING ERRCODE = '42501';
  END IF;
  IF v_cats IS NOT NULL THEN
    v_shops := ARRAY(SELECT s.id FROM public.shops s WHERE s.category_id = ANY (v_cats));
  END IF;

  WITH filtered AS (
    SELECT ls.id, ls.status, ls.viewer_count,
           COALESCE(ls.ended_at, ls.started_at, ls.created_at) AS sort_at
      FROM public.live_sessions ls
     WHERE (v_shops IS NULL OR ls.shop_id = ANY (v_shops))
       AND CASE v_status
             WHEN 'live' THEN ls.status = 'live'
             WHEN 'ended' THEN ls.status = 'ended' AND ls.started_at IS NOT NULL
             ELSE ls.status <> 'scheduled'
           END
  ),
  page AS (
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
             'shop_access', private.live_session_access(ls.shop_id, ls.host_user_id)
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
                    WHERE status = 'live' AND last_heartbeat_at > now() - interval '2 minutes'
                      AND (v_shops IS NULL OR shop_id = ANY (v_shops))),
      'preparing', (SELECT count(*) FROM public.live_sessions WHERE status = 'scheduled'
                       AND (v_shops IS NULL OR shop_id = ANY (v_shops))),
      'today', (SELECT count(*) FROM public.live_sessions WHERE started_at >= v_day_start
                   AND (v_shops IS NULL OR shop_id = ANY (v_shops))),
      'minutes_7d', (SELECT COALESCE(round(sum(extract(epoch FROM (COALESCE(ended_at, now()) - started_at))) / 60), 0)::integer
                       FROM public.live_sessions WHERE started_at > now() - interval '7 days'
                        AND (v_shops IS NULL OR shop_id = ANY (v_shops))),
      'admin_closed_30d', (SELECT count(*) FROM public.live_sessions
                            WHERE ended_reason = 'admin' AND ended_at > now() - interval '30 days'
                              AND (v_shops IS NULL OR shop_id = ANY (v_shops))),
      'granted_shops', (SELECT count(*) FROM public.shop_live_permissions WHERE permission = 'granted'),
      'revoked_shops', (SELECT count(*) FROM public.shop_live_permissions WHERE permission = 'revoked'),
      'user_live_now', CASE WHEN v_shops IS NULL THEN (SELECT count(*) FROM public.live_sessions
                         WHERE shop_id IS NULL AND status = 'live'
                           AND last_heartbeat_at > now() - interval '2 minutes') ELSE 0 END,
      'granted_users', (SELECT count(*) FROM public.user_live_permissions WHERE permission = 'granted'),
      'revoked_users', (SELECT count(*) FROM public.user_live_permissions WHERE permission = 'revoked')
    ),
    'settings', jsonb_build_object(
      'enabled', private.live_module_enabled(),
      'access', private.live_access_mode(),
      'user_mode', private.live_user_mode()
    )
  );
END;
$fn$;

CREATE OR REPLACE FUNCTION public.admin_end_live_session(p_session_id uuid, p_note text DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $fn$
DECLARE
  v_status text;
  v_note text := NULLIF(btrim(left(COALESCE(p_note, ''), 300)), '');
  v_cats uuid[] := private.moderator_category_ids('shop');
  v_shop_category uuid;
BEGIN
  IF NOT public.auth_is_moderator('live') THEN
    RAISE EXCEPTION 'Yönetici ya da moderatör yetkisi gerekli' USING ERRCODE = '42501';
  END IF;
  SELECT ls.status, s.category_id INTO v_status, v_shop_category
    FROM public.live_sessions ls
    LEFT JOIN public.shops s ON s.id = ls.shop_id
   WHERE ls.id = p_session_id
     FOR UPDATE OF ls;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Yayın bulunamadı' USING ERRCODE = 'P0001', HINT = 'LIVE_NOT_FOUND';
  END IF;
  -- Kategori sınırı: kullanıcı yayını (kategorisiz) yalnız sınırsız moderatöre.
  IF v_cats IS NOT NULL AND NOT COALESCE(v_shop_category = ANY (v_cats), false) THEN
    RAISE EXCEPTION 'Bu mağazanın kategorisi moderasyon alanınızda değil' USING ERRCODE = '42501', HINT = 'MOD_CATEGORY_FORBIDDEN';
  END IF;
  IF v_status = 'ended' THEN
    RAISE EXCEPTION 'Bu yayın zaten sona erdi' USING ERRCODE = 'P0001', HINT = 'LIVE_ENDED';
  END IF;
  RETURN private.live_admin_close(p_session_id, v_note);
END;
$fn$;

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
      SELECT id, shop_id, host_user_id FROM public.live_sessions WHERE status IN ('scheduled', 'live')
    LOOP
      IF private.live_session_access(v_row.shop_id, v_row.host_user_id) <> 'ok' THEN
        PERFORM private.live_admin_close(v_row.id, NULL);
        v_closed := v_closed + 1;
      END IF;
    END LOOP;
  END IF;

  RETURN jsonb_build_object(
    'enabled', private.live_module_enabled(),
    'access', private.live_access_mode(),
    'user_mode', private.live_user_mode(),
    'closed', v_closed
  );
END;
$fn$;

-- Kullanıcı yayını modu: 'open' | 'invite' | 'off'. p_close_running: yeni
-- modda artık izinli olmayan süren/hazırlıktaki kullanıcı yayınlarını kapat.
CREATE OR REPLACE FUNCTION public.admin_set_user_live_mode(p_mode text, p_close_running boolean DEFAULT false)
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
  IF p_mode IS NULL OR p_mode NOT IN ('open', 'invite', 'off') THEN
    RAISE EXCEPTION 'Geçersiz mod' USING ERRCODE = 'P0001', HINT = 'LIVE_ACCESS_INVALID';
  END IF;
  INSERT INTO public.app_settings (key, value, updated_at)
  VALUES ('live_user_streams', to_jsonb(p_mode), now())
  ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value, updated_at = EXCLUDED.updated_at;

  IF COALESCE(p_close_running, false) THEN
    FOR v_row IN
      SELECT id, host_user_id FROM public.live_sessions
       WHERE shop_id IS NULL AND status IN ('scheduled', 'live')
    LOOP
      IF private.live_user_access(v_row.host_user_id) <> 'ok' THEN
        PERFORM private.live_admin_close(v_row.id, NULL);
        v_closed := v_closed + 1;
      END IF;
    END LOOP;
  END IF;

  RETURN jsonb_build_object('user_mode', private.live_user_mode(), 'closed', v_closed);
END;
$fn$;

-- p_filter: 'all' (aramasız: izin satırı olan ya da yayın açmış olanlar;
-- aramayla: eşleşen tüm hesaplar) | 'granted' | 'revoked' | 'streamed'.
CREATE OR REPLACE FUNCTION public.admin_live_users(
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
    SELECT pr.id, pr.username, pr.full_name, pr.avatar_url, pr.status::text AS status,
           perm.permission, perm.note, perm.updated_at AS permission_updated_at, perm.updated_by,
           st.session_count, st.last_live_at, st.live_id
      FROM public.profiles pr
      LEFT JOIN public.user_live_permissions perm ON perm.user_id = pr.id
      LEFT JOIN LATERAL (
        SELECT count(*) FILTER (WHERE ls.started_at IS NOT NULL) AS session_count,
               max(ls.started_at) AS last_live_at,
               (array_agg(ls.id) FILTER (WHERE ls.status = 'live'))[1] AS live_id
          FROM public.live_sessions ls
         WHERE ls.host_user_id = pr.id AND ls.shop_id IS NULL
      ) st ON true
     WHERE NOT COALESCE(pr.is_bot, false)
       AND (CASE WHEN v_pattern IS NULL
              THEN perm.user_id IS NOT NULL OR st.session_count > 0 OR st.live_id IS NOT NULL
              ELSE pr.username ILIKE v_pattern OR pr.full_name ILIKE v_pattern
            END)
       AND CASE v_filter
             WHEN 'granted' THEN perm.permission IS NOT DISTINCT FROM 'granted'
             WHEN 'revoked' THEN perm.permission IS NOT DISTINCT FROM 'revoked'
             WHEN 'streamed' THEN st.session_count > 0
             ELSE true
           END
  ),
  page AS (
    SELECT b.*,
           row_number() OVER (ORDER BY (b.live_id IS NOT NULL) DESC, b.last_live_at DESC NULLS LAST,
                                       lower(COALESCE(b.username, b.full_name, '')), b.id) AS rn
      FROM base b
     ORDER BY rn
     LIMIT v_limit OFFSET v_offset
  )
  SELECT (SELECT count(*) FROM base),
         COALESCE(jsonb_agg(jsonb_build_object(
           'user_id', p.id,
           'username', p.username,
           'full_name', p.full_name,
           'avatar_url', p.avatar_url,
           'status', p.status,
           'permission', p.permission,
           'note', p.note,
           'permission_updated_at', p.permission_updated_at,
           'updated_by_name', COALESCE(NULLIF(btrim(u.full_name), ''), u.username),
           'effective', private.live_user_access(p.id),
           'session_count', COALESCE(p.session_count, 0),
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
      'granted', (SELECT count(*) FROM public.user_live_permissions WHERE permission = 'granted'),
      'revoked', (SELECT count(*) FROM public.user_live_permissions WHERE permission = 'revoked')
    ),
    'settings', jsonb_build_object(
      'enabled', private.live_module_enabled(),
      'user_mode', private.live_user_mode()
    )
  );
END;
$fn$;

-- p_permission: 'granted' | 'revoked' | 'default'. İzin kalkınca kişinin açık
-- kullanıcı yayını kapatılır; erişimi değişen kişiye bildirim.
CREATE OR REPLACE FUNCTION public.admin_set_user_live_permission(
  p_user_id uuid,
  p_permission text,
  p_note text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $fn$
DECLARE
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
  PERFORM 1 FROM public.profiles WHERE id = p_user_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Kullanıcı bulunamadı' USING ERRCODE = 'P0001', HINT = 'LIVE_USER_NOT_FOUND';
  END IF;

  v_before := private.live_user_access(p_user_id, true);
  IF p_permission = 'default' THEN
    DELETE FROM public.user_live_permissions WHERE user_id = p_user_id;
  ELSE
    INSERT INTO public.user_live_permissions (user_id, permission, note, updated_by, updated_at)
    VALUES (p_user_id, p_permission, v_note, auth.uid(), now())
    ON CONFLICT (user_id) DO UPDATE
      SET permission = EXCLUDED.permission,
          note = EXCLUDED.note,
          updated_by = EXCLUDED.updated_by,
          updated_at = EXCLUDED.updated_at;
  END IF;
  v_after := private.live_user_access(p_user_id, true);

  IF v_after <> 'ok' THEN
    FOR v_session IN
      SELECT id FROM public.live_sessions
       WHERE host_user_id = p_user_id AND shop_id IS NULL AND status IN ('scheduled', 'live')
    LOOP
      PERFORM private.live_admin_close(v_session, v_note);
      v_closed := v_closed + 1;
    END LOOP;
  END IF;

  IF v_before IS DISTINCT FROM v_after THEN
    IF v_after = 'ok' THEN
      PERFORM private.live_notify(p_user_id, 'Canlı yayın iznin açıldı',
        'Artık canlı yayın açabilirsin: Canlı Yayınlar › Yayın aç.', p_user_id::text, 'user');
    ELSIF v_after = 'LIVE_USER_REVOKED' THEN
      PERFORM private.live_notify(p_user_id, 'Canlı yayın iznin kaldırıldı',
        format('Canlı yayın iznin yönetim tarafından kaldırıldı%s.', COALESCE(': ' || v_note, '')),
        p_user_id::text, 'user');
    END IF;
  END IF;

  RETURN jsonb_build_object(
    'permission', CASE WHEN p_permission = 'default' THEN NULL ELSE p_permission END,
    'effective', private.live_user_access(p_user_id),
    'closed', v_closed
  );
END;
$fn$;

-- -----------------------------------------------------------------------------
-- 11) Yetkiler
-- -----------------------------------------------------------------------------
REVOKE ALL ON FUNCTION public.live_create_user_session(text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.live_create_user_session(text, text) TO authenticated;
REVOKE ALL ON FUNCTION public.live_my_stream_access() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.live_my_stream_access() TO anon, authenticated;
REVOKE ALL ON FUNCTION public.admin_set_user_live_mode(text, boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_set_user_live_mode(text, boolean) TO authenticated;
REVOKE ALL ON FUNCTION public.admin_live_users(text, text, integer, integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_live_users(text, text, integer, integer) TO authenticated;
REVOKE ALL ON FUNCTION public.admin_set_user_live_permission(uuid, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_set_user_live_permission(uuid, text, text) TO authenticated;

-- Yeniden tanımlananların yetkileri korunur (CREATE OR REPLACE); yine de açıkça:
REVOKE ALL ON FUNCTION public.start_live_session(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.start_live_session(uuid) TO authenticated;
REVOKE ALL ON FUNCTION public.live_token_grant(uuid, text, uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.live_token_grant(uuid, text, uuid) TO service_role;
REVOKE ALL ON FUNCTION public.live_sessions_feed(integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.live_sessions_feed(integer) TO anon, authenticated;
REVOKE ALL ON FUNCTION public.live_session_detail(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.live_session_detail(uuid) TO anon, authenticated;
REVOKE ALL ON FUNCTION public.live_history(integer, integer, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.live_history(integer, integer, uuid) TO anon, authenticated;
REVOKE ALL ON FUNCTION public.live_home_card() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.live_home_card() TO anon, authenticated;
REVOKE ALL ON FUNCTION public.admin_live_sessions(text, integer, integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_live_sessions(text, integer, integer) TO authenticated;
REVOKE ALL ON FUNCTION public.admin_end_live_session(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_end_live_session(uuid, text) TO authenticated;
REVOKE ALL ON FUNCTION public.admin_set_live_settings(boolean, text, boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_set_live_settings(boolean, text, boolean) TO authenticated;

COMMIT;

NOTIFY pgrst, 'reload schema';
