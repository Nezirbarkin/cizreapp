-- =============================================================================
-- Görev 4.6 — Moderatör rolü ve RLS yetkilendirme altyapısı
-- =============================================================================
--
-- Moderatör, kullanıcının asıl rolünden (müşteri/satıcı/kurye…) BAĞIMSIZ bir
-- yetkidir: bir satıcı satıcılığını kaybetmeden moderatör olabilir. Bu yüzden
-- user_role enum'una değer eklenmedi; yetki `moderators` tablosunda kapsamlarla
-- (scopes) tutulur:
--   content  gönderi gizleme/açma, yorum silme, gizli içeriği görme
--   reports  kullanıcı ve gönderi şikayetlerini görme/sonuçlandırma
--   ilanlar  onay bekleyen ilanları onaylama/reddetme (retle ücret iadesi dahil)
--   live     canlı yayınları izleme ve kapatma
--
-- Yetki kontrolünün tek kaynağı `public.auth_is_moderator(scope)` (yönetici her
-- kapsama sahiptir; askıya alınan moderatör yetkisini kaybeder). RLS politikaları
-- ve moderasyon RPC'leri bunu kullanır. Tablo istemciye kapalıdır; yalnız
-- yönetici `admin_set_moderator` ile yazar (denetim günlüğü + bildirim).
--
-- Bu göç ayrıca şikayet tablolarındaki iki açığı kapatır:
--   * post_reports anonim kullanıcılara TAMAMEN açıktı (USING true) → kaldırıldı;
--   * user_reports her oturum açmış kullanıcıya TAMAMEN açıktı (USING true) →
--     yalnız şikayet eden + moderatör/yönetici.
-- ve post_reports'un yönetici politikalarındaki bozuk kontrolü düzeltir
-- (JWT'deki 'role' alanı herkes için 'authenticated' olduğundan yönetici
-- başkalarının şikayetlerini göremiyor/güncelleyemiyordu).

BEGIN;

-- -----------------------------------------------------------------------------
-- 1) Moderatörler
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.moderators (
  user_id    uuid PRIMARY KEY REFERENCES public.profiles(id) ON DELETE CASCADE,
  scopes     text[] NOT NULL,
  note       text CHECK (note IS NULL OR char_length(note) <= 300),
  granted_by uuid,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT moderators_scopes_valid CHECK (
    cardinality(scopes) > 0
    AND scopes <@ ARRAY['content', 'reports', 'ilanlar', 'live']::text[]
  )
);

COMMENT ON TABLE public.moderators IS
  'Görev 4.6: moderatör yetkileri (kapsamlar). Yalnız admin_set_moderator yazar; kişi kendi satırını okur.';

ALTER TABLE public.moderators ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.moderators FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.moderators TO authenticated;

DROP POLICY IF EXISTS moderators_read ON public.moderators;
CREATE POLICY moderators_read ON public.moderators
  FOR SELECT TO authenticated
  USING (user_id = (SELECT auth.uid()) OR (SELECT public.auth_is_admin()));

-- -----------------------------------------------------------------------------
-- 2) Yetki yardımcıları
-- -----------------------------------------------------------------------------
-- Yönetici ya da (aktif) moderatör mü? p_scope NULL = herhangi bir kapsam.
CREATE OR REPLACE FUNCTION public.auth_is_moderator(p_scope text DEFAULT NULL)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $fn$
  SELECT private.current_user_is_admin()
      OR EXISTS (
           SELECT 1
             FROM public.moderators m
             JOIN public.profiles p ON p.id = m.user_id
            WHERE m.user_id = (SELECT auth.uid())
              AND p.status::text = 'active'
              AND (p_scope IS NULL OR p_scope = ANY (m.scopes))
         );
$fn$;

-- Uygulamanın menü/panel kararı için: {is_admin, scopes[]}.
CREATE OR REPLACE FUNCTION public.my_moderation()
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $fn$
  SELECT jsonb_build_object(
    'is_admin', private.current_user_is_admin(),
    'scopes', CASE
      WHEN private.current_user_is_admin() THEN to_jsonb(ARRAY['content', 'reports', 'ilanlar', 'live'])
      ELSE COALESCE((
        SELECT to_jsonb(m.scopes)
          FROM public.moderators m
          JOIN public.profiles p ON p.id = m.user_id
         WHERE m.user_id = (SELECT auth.uid()) AND p.status::text = 'active'
      ), '[]'::jsonb)
    END
  );
$fn$;

CREATE OR REPLACE FUNCTION private.moderation_scope_label(p_scope text)
RETURNS text
LANGUAGE sql
IMMUTABLE
SET search_path = ''
AS $fn$
  SELECT CASE p_scope
    WHEN 'content' THEN 'İçerik'
    WHEN 'reports' THEN 'Şikayetler'
    WHEN 'ilanlar' THEN 'İlanlar'
    WHEN 'live' THEN 'Canlı yayınlar'
    ELSE p_scope
  END;
$fn$;

CREATE OR REPLACE FUNCTION private.moderation_notify(
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
         jsonb_build_object('source', 'moderation'), false, now()
   WHERE p_user_id IS NOT NULL;
$fn$;

-- -----------------------------------------------------------------------------
-- 3) Yönetici: moderatör listesi ve atama
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_moderators_list()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $fn$
BEGIN
  IF NOT public.auth_is_admin() THEN
    RAISE EXCEPTION 'Yönetici yetkisi gerekli' USING ERRCODE = '42501';
  END IF;
  RETURN (
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
      'user_id', m.user_id,
      'full_name', p.full_name,
      'username', p.username,
      'avatar_url', p.avatar_url,
      'role', p.role::text,
      'status', p.status::text,
      'scopes', to_jsonb(m.scopes),
      'note', m.note,
      'granted_by_name', COALESCE(NULLIF(btrim(g.full_name), ''), g.username),
      'created_at', m.created_at,
      'updated_at', m.updated_at,
      'actions_30d', (SELECT count(*) FROM public.admin_audit_log a
                       WHERE a.admin_id = m.user_id AND a.action LIKE 'mod\_%'
                         AND a.created_at > now() - interval '30 days')
    ) ORDER BY m.created_at, m.user_id), '[]'::jsonb)
      FROM public.moderators m
      JOIN public.profiles p ON p.id = m.user_id
      LEFT JOIN public.profiles g ON g.id = m.granted_by
  );
END;
$fn$;

-- Kapsamları yazar; boş dizi = moderatörlükten çıkar.
CREATE OR REPLACE FUNCTION public.admin_set_moderator(
  p_user_id uuid,
  p_scopes text[],
  p_note text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $fn$
DECLARE
  v_scopes text[];
  v_note text := NULLIF(btrim(left(COALESCE(p_note, ''), 300)), '');
  v_target record;
  v_old text[];
  v_labels text;
BEGIN
  IF NOT public.auth_is_admin() THEN
    RAISE EXCEPTION 'Yönetici yetkisi gerekli' USING ERRCODE = '42501';
  END IF;
  v_scopes := ARRAY(
    SELECT DISTINCT s FROM unnest(COALESCE(p_scopes, ARRAY[]::text[])) AS s
     WHERE s IS NOT NULL ORDER BY 1
  );
  IF NOT v_scopes <@ ARRAY['content', 'reports', 'ilanlar', 'live']::text[] THEN
    RAISE EXCEPTION 'Geçersiz moderatör kapsamı' USING ERRCODE = 'P0001', HINT = 'MOD_SCOPE_INVALID';
  END IF;

  SELECT p.id, p.role::text AS role, COALESCE(p.is_bot, false) AS is_bot, COALESCE(p.is_admin, false) AS is_admin,
         EXISTS (SELECT 1 FROM auth.users a WHERE a.id = p.id AND a.is_anonymous) AS is_guest
    INTO v_target
    FROM public.profiles p WHERE p.id = p_user_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Kullanıcı bulunamadı' USING ERRCODE = 'P0001', HINT = 'MOD_USER_NOT_FOUND';
  END IF;
  IF v_target.is_bot OR v_target.is_guest THEN
    RAISE EXCEPTION 'Bot ya da misafir hesap moderatör olamaz' USING ERRCODE = 'P0001', HINT = 'MOD_USER_INVALID';
  END IF;
  IF v_target.role = 'admin' OR v_target.is_admin THEN
    RAISE EXCEPTION 'Yöneticiler zaten tüm yetkilere sahip' USING ERRCODE = 'P0001', HINT = 'MOD_USER_IS_ADMIN';
  END IF;

  SELECT m.scopes INTO v_old FROM public.moderators m WHERE m.user_id = p_user_id;

  IF cardinality(v_scopes) = 0 THEN
    DELETE FROM public.moderators WHERE user_id = p_user_id;
  ELSE
    INSERT INTO public.moderators (user_id, scopes, note, granted_by, created_at, updated_at)
    VALUES (p_user_id, v_scopes, v_note, auth.uid(), now(), now())
    ON CONFLICT (user_id) DO UPDATE
      SET scopes = EXCLUDED.scopes, note = EXCLUDED.note,
          granted_by = EXCLUDED.granted_by, updated_at = now();
  END IF;

  INSERT INTO public.admin_audit_log (admin_id, action, target_table, target_id, old_data, new_data)
  VALUES (auth.uid(), 'set_moderator', 'moderators', p_user_id::text,
          jsonb_build_object('scopes', to_jsonb(v_old)),
          jsonb_build_object('scopes', to_jsonb(v_scopes), 'note', v_note));

  IF v_old IS DISTINCT FROM v_scopes THEN
    SELECT string_agg(private.moderation_scope_label(s), ', ' ORDER BY s) INTO v_labels FROM unnest(v_scopes) s;
    IF cardinality(v_scopes) = 0 THEN
      PERFORM private.moderation_notify(p_user_id, 'Moderatörlük yetkin kaldırıldı',
        'Moderatör yetkin yönetim tarafından kaldırıldı.', p_user_id::text, 'moderator');
    ELSE
      PERFORM private.moderation_notify(p_user_id,
        CASE WHEN v_old IS NULL THEN 'Moderatör oldun' ELSE 'Moderatör yetkilerin güncellendi' END,
        format('Moderasyon alanların: %s. Ayarlar menüsündeki "Moderasyon Paneli"nden ulaşabilirsin.', v_labels),
        p_user_id::text, 'moderator');
    END IF;
  END IF;

  RETURN jsonb_build_object('user_id', p_user_id, 'scopes', to_jsonb(v_scopes), 'removed', cardinality(v_scopes) = 0);
END;
$fn$;

-- -----------------------------------------------------------------------------
-- 4) RLS: şikayet açıkları + moderatör erişimi
-- -----------------------------------------------------------------------------
-- Gönderi şikayetleri: anonim okuma kaldırıldı; şikayet eden kendi kaydını,
-- moderatör/yönetici hepsini görür; sonuçlandırma moderatör, silme yönetici.
DROP POLICY IF EXISTS post_reports_select_anon ON public.post_reports;
ALTER POLICY post_reports_select_auth ON public.post_reports
  USING (reporter_id = (SELECT auth.uid()) OR (SELECT public.auth_is_moderator('reports')));
ALTER POLICY post_reports_update_admin ON public.post_reports
  USING ((SELECT public.auth_is_moderator('reports')))
  WITH CHECK ((SELECT public.auth_is_moderator('reports')));
ALTER POLICY post_reports_delete_admin ON public.post_reports
  USING ((SELECT public.auth_is_admin()));

-- Kullanıcı şikayetleri: artık herkese açık değil.
ALTER POLICY user_reports_select_unified ON public.user_reports
  USING (reporter_id = (SELECT auth.uid()) OR (SELECT public.auth_is_moderator('reports')));
ALTER POLICY user_reports_update ON public.user_reports
  USING ((SELECT public.auth_is_moderator('reports')))
  WITH CHECK ((SELECT public.auth_is_moderator('reports')));

-- Gizlenmiş gönderi/hikaye: 'content' moderatörü de görür (moderasyon için).
ALTER POLICY posts_select_visible ON public.posts
  USING (((is_active = true) OR (user_id = (SELECT auth.uid())) OR social_is_admin()
          OR (SELECT public.auth_is_moderator('content')))
         AND can_view_social_author(user_id));
ALTER POLICY stories_select_visible ON public.stories
  USING (((expires_at > now()) OR (user_id = (SELECT auth.uid())) OR social_is_admin()
          OR (SELECT public.auth_is_moderator('content')))
         AND can_view_social_author(user_id));

-- Yorum silme: 'content' moderatörü de silebilir.
ALTER POLICY post_comments_delete_allowed ON public.post_comments
  USING ((user_id = (SELECT auth.uid()))
         OR (EXISTS (SELECT 1 FROM public.posts p
                      WHERE p.id = post_comments.post_id AND p.user_id = (SELECT auth.uid())))
         OR social_is_admin()
         OR (SELECT public.auth_is_moderator('content')));

-- -----------------------------------------------------------------------------
-- 5) Moderasyon RPC'leri (her biri kapsam kontrollü, denetim günlüğüne yazar)
-- -----------------------------------------------------------------------------

-- Gönderi gizle/aç (iç yardımcı). Değiştiyse true; gizlendiyse yazara bildirim.
CREATE OR REPLACE FUNCTION private.mod_set_post_active(p_post_id uuid, p_active boolean, p_reason text)
RETURNS boolean
LANGUAGE plpgsql
SET search_path = ''
AS $fn$
DECLARE
  v_author uuid;
BEGIN
  UPDATE public.posts
     SET is_active = p_active
   WHERE id = p_post_id AND is_active IS DISTINCT FROM p_active
  RETURNING user_id INTO v_author;
  IF NOT FOUND THEN
    RETURN false;
  END IF;

  INSERT INTO public.admin_audit_log (admin_id, action, target_table, target_id, new_data)
  VALUES (auth.uid(), CASE WHEN p_active THEN 'mod_unhide_post' ELSE 'mod_hide_post' END,
          'posts', p_post_id::text, jsonb_build_object('reason', p_reason));

  IF NOT p_active THEN
    PERFORM private.moderation_notify(v_author, 'Gönderin gizlendi',
      format('Gönderin topluluk kurallarına aykırı bulunduğu için gizlendi%s.', COALESCE(': ' || p_reason, '')),
      p_post_id::text, 'post');
  END IF;
  RETURN true;
END;
$fn$;

CREATE OR REPLACE FUNCTION public.mod_set_post_active(p_post_id uuid, p_active boolean, p_reason text DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $fn$
DECLARE
  v_reason text := NULLIF(btrim(left(COALESCE(p_reason, ''), 300)), '');
  v_changed boolean;
BEGIN
  IF NOT public.auth_is_moderator('content') THEN
    RAISE EXCEPTION 'Moderatör yetkisi gerekli' USING ERRCODE = '42501';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.posts WHERE id = p_post_id) THEN
    RAISE EXCEPTION 'Gönderi bulunamadı' USING ERRCODE = 'P0001', HINT = 'MOD_POST_NOT_FOUND';
  END IF;
  v_changed := private.mod_set_post_active(p_post_id, COALESCE(p_active, true), v_reason);
  RETURN jsonb_build_object('post_id', p_post_id, 'is_active', COALESCE(p_active, true), 'changed', v_changed);
END;
$fn$;

-- Gönderi listesi: 'recent' (hepsi), 'hidden' (gizlenenler), 'reported' (açık şikayetli).
CREATE OR REPLACE FUNCTION public.mod_posts(
  p_filter text DEFAULT 'recent',
  p_search text DEFAULT NULL,
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
  v_filter text := CASE WHEN p_filter IN ('recent', 'hidden', 'reported') THEN p_filter ELSE 'recent' END;
  v_search text := NULLIF(btrim(COALESCE(p_search, '')), '');
  v_pattern text;
  v_limit integer := LEAST(GREATEST(COALESCE(p_limit, 30), 1), 100);
  v_offset integer := GREATEST(COALESCE(p_offset, 0), 0);
  v_total integer;
  v_rows jsonb;
BEGIN
  IF NOT public.auth_is_moderator('content') THEN
    RAISE EXCEPTION 'Moderatör yetkisi gerekli' USING ERRCODE = '42501';
  END IF;
  IF v_search IS NOT NULL THEN
    v_pattern := '%' || replace(replace(replace(v_search, '\', '\\'), '%', '\%'), '_', '\_') || '%';
  END IF;

  WITH base AS (
    SELECT po.id, po.created_at,
           (SELECT count(*) FROM public.post_reports r
             WHERE r.reported_post_id = po.id AND r.status IN ('pending', 'reviewing')) AS open_reports
      FROM public.posts po
      JOIN public.profiles au ON au.id = po.user_id
     WHERE (v_pattern IS NULL OR po.content ILIKE v_pattern OR au.username ILIKE v_pattern OR au.full_name ILIKE v_pattern)
       AND CASE v_filter
             WHEN 'hidden' THEN po.is_active IS FALSE
             WHEN 'reported' THEN EXISTS (SELECT 1 FROM public.post_reports r
                                           WHERE r.reported_post_id = po.id AND r.status IN ('pending', 'reviewing'))
             ELSE true
           END
  ),
  page AS (
    SELECT b.*, row_number() OVER (ORDER BY b.created_at DESC, b.id) AS rn
      FROM base b
     ORDER BY rn
     LIMIT v_limit OFFSET v_offset
  )
  SELECT (SELECT count(*) FROM base),
         COALESCE(jsonb_agg(jsonb_build_object(
           'id', po.id,
           'content', left(COALESCE(po.content, ''), 400),
           'image_url', COALESCE(po.images[1], po.image_url),
           'is_active', COALESCE(po.is_active, true),
           'likes_count', COALESCE(po.likes_count, 0),
           'created_at', po.created_at,
           'open_reports', pg.open_reports,
           'author', jsonb_build_object(
             'id', au.id,
             'name', COALESCE(NULLIF(btrim(au.full_name), ''), au.username),
             'username', au.username,
             'avatar_url', au.avatar_url)
         ) ORDER BY pg.rn), '[]'::jsonb)
    INTO v_total, v_rows
    FROM page pg
    JOIN public.posts po ON po.id = pg.id
    JOIN public.profiles au ON au.id = po.user_id;

  RETURN jsonb_build_object('total', COALESCE(v_total, 0), 'rows', v_rows);
END;
$fn$;

-- Şikayetler (gönderi + kullanıcı): 'open' (bekleyen/incelenen), 'closed', 'all'.
CREATE OR REPLACE FUNCTION public.mod_reports(
  p_status text DEFAULT 'open',
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
  v_status text := CASE WHEN p_status IN ('open', 'closed', 'all') THEN p_status ELSE 'open' END;
  v_limit integer := LEAST(GREATEST(COALESCE(p_limit, 30), 1), 100);
  v_offset integer := GREATEST(COALESCE(p_offset, 0), 0);
  v_total integer;
  v_rows jsonb;
BEGIN
  IF NOT public.auth_is_moderator('reports') THEN
    RAISE EXCEPTION 'Moderatör yetkisi gerekli' USING ERRCODE = '42501';
  END IF;

  WITH r AS (
    SELECT 'post'::text AS kind, pr.id, pr.reporter_id, pr.reason, pr.description, pr.status,
           pr.admin_response, pr.created_at, pr.reported_post_id AS post_id, NULL::uuid AS target_user_id,
           NULL::text[] AS images
      FROM public.post_reports pr
    UNION ALL
    SELECT 'user'::text, ur.id, ur.reporter_id, ur.reason, ur.description, ur.status,
           ur.admin_response, ur.created_at, NULL::uuid, ur.reported_user_id, ur.images
      FROM public.user_reports ur
  ),
  f AS (
    SELECT * FROM r
     WHERE CASE v_status
             WHEN 'open' THEN r.status IN ('pending', 'reviewing')
             WHEN 'closed' THEN r.status IN ('resolved', 'rejected')
             ELSE true
           END
  ),
  page AS (
    SELECT f.*, row_number() OVER (ORDER BY f.created_at DESC, f.id) AS rn
      FROM f
     ORDER BY rn
     LIMIT v_limit OFFSET v_offset
  )
  SELECT (SELECT count(*) FROM f),
         COALESCE(jsonb_agg(jsonb_build_object(
           'kind', pg.kind,
           'id', pg.id,
           'reason', pg.reason,
           'description', pg.description,
           'status', pg.status,
           'admin_response', pg.admin_response,
           'created_at', pg.created_at,
           'images', to_jsonb(pg.images),
           'reporter', CASE WHEN rp.id IS NULL THEN NULL ELSE jsonb_build_object(
             'id', rp.id, 'name', COALESCE(NULLIF(btrim(rp.full_name), ''), rp.username),
             'username', rp.username, 'avatar_url', rp.avatar_url) END,
           'post', CASE WHEN pg.kind = 'post' AND po.id IS NOT NULL THEN jsonb_build_object(
             'id', po.id, 'content', left(COALESCE(po.content, ''), 300),
             'image_url', COALESCE(po.images[1], po.image_url),
             'is_active', COALESCE(po.is_active, true), 'user_id', po.user_id,
             'author_name', COALESCE(NULLIF(btrim(pa.full_name), ''), pa.username)) END,
           'user', CASE WHEN pg.kind = 'user' AND ru.id IS NOT NULL THEN jsonb_build_object(
             'id', ru.id, 'name', COALESCE(NULLIF(btrim(ru.full_name), ''), ru.username),
             'username', ru.username, 'avatar_url', ru.avatar_url, 'status', ru.status::text) END
         ) ORDER BY pg.rn), '[]'::jsonb)
    INTO v_total, v_rows
    FROM page pg
    LEFT JOIN public.profiles rp ON rp.id = pg.reporter_id
    LEFT JOIN public.posts po ON po.id = pg.post_id
    LEFT JOIN public.profiles pa ON pa.id = po.user_id
    LEFT JOIN public.profiles ru ON ru.id = pg.target_user_id;

  RETURN jsonb_build_object(
    'total', COALESCE(v_total, 0),
    'rows', v_rows,
    'counts', jsonb_build_object(
      'open', (SELECT count(*) FROM public.post_reports WHERE status IN ('pending', 'reviewing'))
              + (SELECT count(*) FROM public.user_reports WHERE status IN ('pending', 'reviewing')),
      'post_open', (SELECT count(*) FROM public.post_reports WHERE status IN ('pending', 'reviewing')),
      'user_open', (SELECT count(*) FROM public.user_reports WHERE status IN ('pending', 'reviewing'))
    )
  );
END;
$fn$;

-- Şikayeti sonuçlandır; gönderi şikayetinde isteğe bağlı gönderiyi gizle
-- ('content' kapsamı da gerekir). Sonuçlanınca şikayet edene bildirim.
CREATE OR REPLACE FUNCTION public.mod_resolve_report(
  p_kind text,
  p_id uuid,
  p_status text,
  p_response text DEFAULT NULL,
  p_hide_post boolean DEFAULT false
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $fn$
DECLARE
  v_response text := NULLIF(btrim(left(COALESCE(p_response, ''), 500)), '');
  v_reporter uuid;
  v_post uuid;
  v_hidden boolean := false;
BEGIN
  IF NOT public.auth_is_moderator('reports') THEN
    RAISE EXCEPTION 'Moderatör yetkisi gerekli' USING ERRCODE = '42501';
  END IF;
  IF p_kind IS NULL OR p_kind NOT IN ('post', 'user')
     OR p_status IS NULL OR p_status NOT IN ('reviewing', 'resolved', 'rejected') THEN
    RAISE EXCEPTION 'Geçersiz işlem' USING ERRCODE = 'P0001', HINT = 'MOD_INVALID';
  END IF;
  IF COALESCE(p_hide_post, false) AND (p_kind <> 'post' OR NOT public.auth_is_moderator('content')) THEN
    RAISE EXCEPTION 'Gönderi gizlemek için içerik yetkisi gerekli' USING ERRCODE = 'P0001', HINT = 'MOD_SCOPE_MISSING';
  END IF;

  IF p_kind = 'post' THEN
    UPDATE public.post_reports
       SET status = p_status, admin_response = COALESCE(v_response, admin_response), updated_at = now()
     WHERE id = p_id
    RETURNING reporter_id, reported_post_id INTO v_reporter, v_post;
  ELSE
    UPDATE public.user_reports
       SET status = p_status, admin_response = COALESCE(v_response, admin_response),
           admin_id = auth.uid(), updated_at = now()
     WHERE id = p_id
    RETURNING reporter_id INTO v_reporter;
  END IF;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Şikayet bulunamadı' USING ERRCODE = 'P0001', HINT = 'MOD_REPORT_NOT_FOUND';
  END IF;

  IF COALESCE(p_hide_post, false) AND v_post IS NOT NULL THEN
    v_hidden := private.mod_set_post_active(v_post, false, COALESCE(v_response, 'Şikayet üzerine'));
  END IF;

  INSERT INTO public.admin_audit_log (admin_id, action, target_table, target_id, new_data)
  VALUES (auth.uid(), 'mod_resolve_report', CASE WHEN p_kind = 'post' THEN 'post_reports' ELSE 'user_reports' END,
          p_id::text, jsonb_build_object('status', p_status, 'response', v_response, 'hidden_post', v_hidden));

  IF p_status IN ('resolved', 'rejected') THEN
    PERFORM private.moderation_notify(v_reporter, 'Şikayetin sonuçlandı',
      CASE WHEN p_status = 'resolved'
           THEN 'Şikayetin incelendi ve gerekli işlem yapıldı. Teşekkürler!'
           ELSE 'Şikayetin incelendi; kurallara aykırı bir durum bulunmadı.'
      END || COALESCE(' Not: ' || v_response, ''),
      p_id::text, 'report');
  END IF;

  RETURN jsonb_build_object('id', p_id, 'kind', p_kind, 'status', p_status, 'hidden_post', v_hidden);
END;
$fn$;

-- Onay bekleyen ilanlar (en eskiden).
CREATE OR REPLACE FUNCTION public.mod_pending_ilanlar(p_limit integer DEFAULT 30, p_offset integer DEFAULT 0)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $fn$
DECLARE
  v_limit integer := LEAST(GREATEST(COALESCE(p_limit, 30), 1), 100);
  v_offset integer := GREATEST(COALESCE(p_offset, 0), 0);
BEGIN
  IF NOT public.auth_is_moderator('ilanlar') THEN
    RAISE EXCEPTION 'Moderatör yetkisi gerekli' USING ERRCODE = '42501';
  END IF;
  RETURN jsonb_build_object(
    'total', (SELECT count(*) FROM public.ilanlar WHERE status = 'pending'),
    'rows', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
               'id', x.id,
               'title', x.title,
               'description', left(COALESCE(x.description, ''), 600),
               'price', x.price,
               'currency', x.currency,
               'city', x.city,
               'district', x.district,
               'cover_image_url', x.cover_image_url,
               'category_name', c.name,
               'paid_fee', x.paid_fee,
               'created_at', x.created_at,
               'owner', jsonb_build_object(
                 'id', o.id,
                 'name', COALESCE(NULLIF(btrim(o.full_name), ''), o.username),
                 'username', o.username,
                 'avatar_url', o.avatar_url)
             ) ORDER BY x.created_at, x.id)
        FROM (SELECT i.* FROM public.ilanlar i WHERE i.status = 'pending'
               ORDER BY i.created_at, i.id LIMIT v_limit OFFSET v_offset) x
        LEFT JOIN public.ilan_categories c ON c.id = x.category_id
        LEFT JOIN public.profiles o ON o.id = x.owner_id
    ), '[]'::jsonb)
  );
END;
$fn$;

-- İlanı onayla/reddet. Karar ilan doğrulayıcısının YÖNETİCİ dalından geçer
-- (işlem-içi işaret + kapsam): onay alanları ve retle ücret iadesi aynı kod.
CREATE OR REPLACE FUNCTION public.mod_review_ilan(p_ilan_id uuid, p_approve boolean, p_reason text DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $fn$
DECLARE
  v_reason text := NULLIF(btrim(left(COALESCE(p_reason, ''), 300)), '');
  v record;
  v_status text;
BEGIN
  IF NOT public.auth_is_moderator('ilanlar') THEN
    RAISE EXCEPTION 'Moderatör yetkisi gerekli' USING ERRCODE = '42501';
  END IF;
  SELECT i.id, i.status, i.owner_id, i.title INTO v FROM public.ilanlar i WHERE i.id = p_ilan_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'İlan bulunamadı' USING ERRCODE = 'P0001', HINT = 'ILAN_NOT_FOUND';
  END IF;
  IF v.status <> 'pending' THEN
    RAISE EXCEPTION 'Bu ilan onay beklemiyor' USING ERRCODE = 'P0001', HINT = 'MOD_ILAN_NOT_PENDING';
  END IF;
  IF NOT COALESCE(p_approve, false) AND v_reason IS NULL THEN
    RAISE EXCEPTION 'Ret nedeni yazın' USING ERRCODE = 'P0001', HINT = 'MOD_REASON_REQUIRED';
  END IF;

  v_status := CASE WHEN p_approve THEN 'published' ELSE 'rejected' END;
  PERFORM set_config('cizre.ilan_moderation', 'on', true);
  UPDATE public.ilanlar
     SET status = v_status,
         rejection_reason = CASE WHEN p_approve THEN NULL ELSE v_reason END
   WHERE id = p_ilan_id;
  PERFORM set_config('cizre.ilan_moderation', 'off', true);

  INSERT INTO public.admin_audit_log (admin_id, action, target_table, target_id, new_data)
  VALUES (auth.uid(), CASE WHEN p_approve THEN 'mod_approve_ilan' ELSE 'mod_reject_ilan' END,
          'ilanlar', p_ilan_id::text, jsonb_build_object('reason', v_reason));

  PERFORM private.moderation_notify(v.owner_id,
    CASE WHEN p_approve THEN 'İlanın yayında' ELSE 'İlanın onaylanmadı' END,
    CASE WHEN p_approve
         THEN format('"%s" ilanın onaylandı ve yayına alındı.', left(v.title, 80))
         ELSE format('"%s" ilanın onaylanmadı: %s', left(v.title, 80), v_reason)
    END,
    p_ilan_id::text, 'ilan');

  RETURN jsonb_build_object('id', p_ilan_id, 'status', v_status);
END;
$fn$;

-- -----------------------------------------------------------------------------
-- 6) İlan doğrulayıcı (3.9 tanımı; yalnız v_is_admin satırı genişledi)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.validate_ilan_write()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_settings public.ilan_settings%ROWTYPE;
  v_pricing_mode text;
  v_allowed_conditions text[];
  v_publish_fee numeric(10,2);
  -- Görev 4.6: 'ilanlar' kapsamlı moderatörün onay/ret kararı (yalnız
  -- mod_review_ilan'ın işlem-içi işaretiyle) yönetici kararı gibi işlenir:
  -- onay alanları, retle ücret iadesi aynı kodla yürür.
  v_is_admin boolean := public.ilan_is_admin()
    OR (current_setting('cizre.ilan_moderation', true) = 'on'
        AND public.auth_is_moderator('ilanlar'));
  v_active_count integer;
  v_balance_id uuid;
  v_current_balance numeric(12,2);
BEGIN
  -- Görev 3.9: süre bitirme işi (cron, oturumsuz) ve süre uzatma RPC'si
  -- yalnız durum/süre alanlarını yazar; kullanıcı doğrulaması atlanır.
  IF TG_OP = 'UPDATE' AND current_setting('cizre.ilan_system_write', true) = 'on' THEN
    NEW.updated_at := now();
    RETURN NEW;
  END IF;

  SELECT * INTO v_settings FROM public.ilan_settings WHERE id = 1;

  IF NOT v_is_admin THEN
    IF NOT v_settings.is_enabled THEN
      RAISE EXCEPTION 'İlan sistemi şu anda kapalı' USING ERRCODE = 'P0001';
    END IF;
    IF TG_OP = 'INSERT' AND NOT v_settings.allow_user_create THEN
      RAISE EXCEPTION 'Kullanıcı ilan paylaşımı şu anda kapalı' USING ERRCODE = '42501';
    END IF;
    IF NEW.owner_id IS DISTINCT FROM (SELECT auth.uid()) THEN
      RAISE EXCEPTION 'Başka bir kullanıcı adına ilan oluşturulamaz' USING ERRCODE = '42501';
    END IF;
  END IF;

  SELECT c.pricing_mode, c.allowed_conditions, c.publish_fee
    INTO v_pricing_mode, v_allowed_conditions, v_publish_fee
  FROM public.ilan_categories c
  WHERE c.id = NEW.category_id
    AND (c.is_active OR v_is_admin);

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Geçersiz veya pasif ilan kategorisi' USING ERRCODE = '23514';
  END IF;

  IF v_pricing_mode = 'forbidden' THEN
    NEW.price := NULL;
    NEW.currency := NULL;
    NEW.is_negotiable := false;
  ELSIF v_pricing_mode = 'required' AND (NEW.price IS NULL OR NEW.price <= 0) THEN
    RAISE EXCEPTION 'Bu kategori için sıfırdan büyük fiyat zorunludur' USING ERRCODE = '23514';
  ELSIF NEW.price IS NOT NULL THEN
    NEW.currency := COALESCE(NEW.currency, 'TRY');
  ELSE
    NEW.currency := NULL;
    NEW.is_negotiable := false;
  END IF;

  IF cardinality(v_allowed_conditions) > 0
     AND (NEW.item_condition IS NULL OR NOT (NEW.item_condition = ANY(v_allowed_conditions))) THEN
    RAISE EXCEPTION 'Bu kategori için geçersiz ürün durumu' USING ERRCODE = '23514';
  END IF;

  NEW.title := btrim(NEW.title);
  NEW.description := btrim(NEW.description);
  NEW.updated_at := now();

  IF TG_OP = 'INSERT' THEN
    IF NOT v_is_admin THEN
      SELECT count(*) INTO v_active_count
      FROM public.ilanlar i
      WHERE i.owner_id = NEW.owner_id
        AND i.status IN ('draft', 'pending', 'published');
      IF v_active_count >= v_settings.max_active_per_user THEN
        RAISE EXCEPTION 'Aktif ilan limitine ulaştınız' USING ERRCODE = 'P0001';
      END IF;
      NEW.status := CASE WHEN v_settings.require_approval THEN 'pending' ELSE 'published' END;

      -- Kategori yayınlama ücreti: onay durumundan bağımsız olarak ilan
      -- gönderilirken hemen tahsil edilir. Reddedilirse aşağıdaki UPDATE
      -- dalında otomatik iade edilir.
      IF v_publish_fee > 0 THEN
        SELECT ub.id, ub.balance INTO v_balance_id, v_current_balance
        FROM public.user_balances ub
        WHERE ub.user_id = NEW.owner_id
        FOR UPDATE;

        IF v_balance_id IS NULL OR v_current_balance < v_publish_fee THEN
          RAISE EXCEPTION 'Yetersiz bakiye: bu kategoride ilan yayınlamak % TL ücretlidir',
            v_publish_fee
            USING ERRCODE = 'P0001';
        END IF;

        UPDATE public.user_balances
        SET balance = v_current_balance - v_publish_fee,
            total_spent = total_spent + v_publish_fee,
            updated_at = now()
        WHERE id = v_balance_id;

        INSERT INTO public.balance_transactions (
          user_id, type, amount, net_amount, balance_before, balance_after,
          reference_type, reference_id, status, description
        ) VALUES (
          NEW.owner_id, 'ilan_publish_fee'::public.balance_transaction_type,
          v_publish_fee, v_publish_fee,
          v_current_balance, v_current_balance - v_publish_fee,
          'ilan', NEW.id, 'completed',
          format('İlan yayınlama ücreti: %s', left(NEW.title, 120))
        );

        NEW.paid_fee := v_publish_fee;
      END IF;
    END IF;
    IF NEW.status = 'published' THEN
      NEW.published_at := COALESCE(NEW.published_at, now());
      NEW.expires_at := COALESCE(NEW.expires_at, now() + make_interval(days => v_settings.default_expiry_days));
    END IF;
  ELSE
    IF NOT v_is_admin THEN
      NEW.moderated_by := OLD.moderated_by;
      NEW.moderated_at := OLD.moderated_at;
      NEW.rejection_reason := OLD.rejection_reason;
      NEW.paid_fee := OLD.paid_fee;
      NEW.fee_refunded := OLD.fee_refunded;
      -- Kullanıcı içerik/kategori/fiyat değiştirdiyse tekrar moderasyona gönder.
      IF ROW(NEW.category_id, NEW.title, NEW.description, NEW.price, NEW.attributes)
         IS DISTINCT FROM ROW(OLD.category_id, OLD.title, OLD.description, OLD.price, OLD.attributes) THEN
        NEW.status := CASE WHEN v_settings.require_approval THEN 'pending' ELSE 'published' END;
      ELSIF NEW.status NOT IN ('sold', 'rented', 'found', 'archived', 'expired', OLD.status) THEN
        NEW.status := OLD.status;
      END IF;
    END IF;
    IF NEW.status = 'published' AND OLD.status IS DISTINCT FROM 'published' THEN
      NEW.published_at := now();
      NEW.expires_at := COALESCE(NEW.expires_at, now() + make_interval(days => v_settings.default_expiry_days));
      IF v_is_admin THEN
        NEW.moderated_by := (SELECT auth.uid());
        NEW.moderated_at := now();
      END IF;
    ELSIF v_is_admin AND NEW.status IN ('rejected', 'archived') AND NEW.status IS DISTINCT FROM OLD.status THEN
      NEW.moderated_by := (SELECT auth.uid());
      NEW.moderated_at := now();

      -- Admin reddederse ve daha önce ücret tahsil edildiyse otomatik iade et.
      -- (archived tetiklemez — sadece açık bir "reddet" kararı iade doğurur.)
      IF NEW.status = 'rejected' AND OLD.paid_fee > 0 AND NOT COALESCE(OLD.fee_refunded, false) THEN
        SELECT ub.id, ub.balance INTO v_balance_id, v_current_balance
        FROM public.user_balances ub
        WHERE ub.user_id = OLD.owner_id
        FOR UPDATE;

        IF v_balance_id IS NOT NULL THEN
          UPDATE public.user_balances
          SET balance = v_current_balance + OLD.paid_fee,
              total_refunds = total_refunds + OLD.paid_fee,
              updated_at = now()
          WHERE id = v_balance_id;

          INSERT INTO public.balance_transactions (
            user_id, type, amount, net_amount, balance_before, balance_after,
            reference_type, reference_id, status, description
          ) VALUES (
            OLD.owner_id, 'ilan_publish_refund'::public.balance_transaction_type,
            OLD.paid_fee, OLD.paid_fee,
            v_current_balance, v_current_balance + OLD.paid_fee,
            'ilan', OLD.id, 'completed',
            format('İlan reddedildi, yayınlama ücreti iade edildi: %s', left(OLD.title, 120))
          );
        END IF;

        NEW.fee_refunded := true;
      END IF;
    END IF;
  END IF;

  RETURN NEW;
END;
$function$;

-- -----------------------------------------------------------------------------
-- 7) Canlı yayın listesi ve kapatma: 'live' kapsamlı moderatöre açık (4.3 tanımı)
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
BEGIN
  -- Görev 4.6: yönetici ya da 'live' kapsamlı moderatör.
  IF NOT public.auth_is_moderator('live') THEN
    RAISE EXCEPTION 'Yönetici ya da moderatör yetkisi gerekli' USING ERRCODE = '42501';
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
  -- Görev 4.6: yönetici ya da 'live' kapsamlı moderatör.
  IF NOT public.auth_is_moderator('live') THEN
    RAISE EXCEPTION 'Yönetici ya da moderatör yetkisi gerekli' USING ERRCODE = '42501';
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

-- -----------------------------------------------------------------------------
-- 8) Yetkiler
-- -----------------------------------------------------------------------------
REVOKE ALL ON FUNCTION public.auth_is_moderator(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.auth_is_moderator(text) TO anon, authenticated, service_role;
REVOKE ALL ON FUNCTION public.my_moderation() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.my_moderation() TO authenticated;

REVOKE ALL ON FUNCTION private.moderation_scope_label(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION private.moderation_notify(uuid, text, text, text, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION private.mod_set_post_active(uuid, boolean, text) FROM PUBLIC;

REVOKE ALL ON FUNCTION public.admin_moderators_list() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.admin_set_moderator(uuid, text[], text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.mod_set_post_active(uuid, boolean, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.mod_posts(text, text, integer, integer) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.mod_reports(text, integer, integer) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.mod_resolve_report(text, uuid, text, text, boolean) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.mod_pending_ilanlar(integer, integer) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.mod_review_ilan(uuid, boolean, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_moderators_list() TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_set_moderator(uuid, text[], text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.mod_set_post_active(uuid, boolean, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.mod_posts(text, text, integer, integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.mod_reports(text, integer, integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.mod_resolve_report(text, uuid, text, text, boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.mod_pending_ilanlar(integer, integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.mod_review_ilan(uuid, boolean, text) TO authenticated;

COMMIT;

NOTIFY pgrst, 'reload schema';
