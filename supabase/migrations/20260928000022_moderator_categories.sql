-- =============================================================================
-- Moderatör kategorileri: yönetici, moderatörün hangi kategorilerde yetkili
-- olduğunu belirler
-- =============================================================================
--
-- * İlan moderatörü ('ilanlar'): yalnız seçilen İLAN kategorilerindeki onay
--   bekleyen ilanları görür ve karara bağlar.
-- * Canlı yayın moderatörü ('live'): yalnız seçilen MAĞAZA kategorilerindeki
--   mağazaların yayınlarını görür ve kapatır; özet sayılar da aynı süzgeçle.
-- * NULL = tüm kategoriler (varsayılan; mevcut moderatörler değişmez).
--   Kategorisiz mağazanın yayını yalnız sınırsız moderatöre ve yöneticiye görünür.
-- * admin_set_moderator'a iki parametre eklendi. NULL = "değiştirme" (eski
--   uygulama sürümü kategorileri sıfırlamasın), boş dizi = tüm kategoriler,
--   dolu dizi = yalnız bunlar. Kapsam kaldırılınca o kapsamın sınırı silinir.
-- * Yöneticinin kategori sınırı yoktur.
--
-- mod_pending_ilanlar, mod_review_ilan, admin_live_sessions,
-- admin_end_live_session ve admin_moderators_list 20260928000019'dan birebir
-- kopyalanır; yalnız kategori satırları eklenir (sözleşme testi doğrular).

BEGIN;

-- -----------------------------------------------------------------------------
-- 1) Şema
-- -----------------------------------------------------------------------------
ALTER TABLE public.moderators
  ADD COLUMN IF NOT EXISTS ilan_category_ids uuid[],
  ADD COLUMN IF NOT EXISTS shop_category_ids uuid[];

ALTER TABLE public.moderators DROP CONSTRAINT IF EXISTS moderators_category_ids_valid;
ALTER TABLE public.moderators ADD CONSTRAINT moderators_category_ids_valid CHECK (
  (ilan_category_ids IS NULL OR cardinality(ilan_category_ids) BETWEEN 1 AND 100)
  AND (shop_category_ids IS NULL OR cardinality(shop_category_ids) BETWEEN 1 AND 100)
);

COMMENT ON COLUMN public.moderators.ilan_category_ids IS
  'İlan moderatörünün yetkili olduğu ilan kategorileri (ilan_categories.id). NULL = hepsi.';
COMMENT ON COLUMN public.moderators.shop_category_ids IS
  'Canlı yayın moderatörünün yetkili olduğu mağaza kategorileri (categories.id). NULL = hepsi.';

-- -----------------------------------------------------------------------------
-- 2) Yardımcılar
-- -----------------------------------------------------------------------------
-- Oturumdaki kişinin kategori sınırı: NULL = hepsi (yönetici ya da sınırsız).
-- p_kind: 'ilan' | 'shop'. Yalnız kapsam kontrolünden geçmiş RPC'lerde kullanılır.
CREATE OR REPLACE FUNCTION private.moderator_category_ids(p_kind text)
RETURNS uuid[]
LANGUAGE plpgsql
STABLE
SET search_path = ''
AS $fn$
DECLARE
  v_ids uuid[];
BEGIN
  IF p_kind IS NULL OR p_kind NOT IN ('ilan', 'shop') THEN
    RAISE EXCEPTION 'Geçersiz kategori türü: %', p_kind;
  END IF;
  IF private.current_user_is_admin() THEN
    RETURN NULL;
  END IF;
  SELECT CASE p_kind WHEN 'ilan' THEN m.ilan_category_ids ELSE m.shop_category_ids END
    INTO v_ids
    FROM public.moderators m
   WHERE m.user_id = (SELECT auth.uid());
  RETURN v_ids;
END;
$fn$;

-- Kategori kimliklerini adlarıyla döner (NULL = hepsi → NULL). Silinmiş
-- kategori listede görünmez.
CREATE OR REPLACE FUNCTION private.moderator_category_list(p_kind text, p_ids uuid[])
RETURNS jsonb
LANGUAGE sql
STABLE
SET search_path = ''
AS $fn$
  SELECT CASE
    WHEN p_ids IS NULL THEN NULL
    WHEN p_kind = 'ilan' THEN COALESCE((
      SELECT jsonb_agg(jsonb_build_object('id', c.id, 'name', c.name) ORDER BY c.sort_order, c.name, c.id)
        FROM public.ilan_categories c
       WHERE c.id = ANY (p_ids)), '[]'::jsonb)
    ELSE COALESCE((
      SELECT jsonb_agg(jsonb_build_object('id', c.id, 'name', c.name) ORDER BY c.display_order NULLS LAST, c.name, c.id)
        FROM public.categories c
       WHERE c.id = ANY (p_ids)), '[]'::jsonb)
  END;
$fn$;

REVOKE ALL ON FUNCTION private.moderator_category_ids(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION private.moderator_category_list(text, uuid[]) FROM PUBLIC;

-- -----------------------------------------------------------------------------
-- 3) Uygulamanın menü/panel kararı: {is_admin, scopes[], ilan_categories, shop_categories}
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.my_moderation()
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $fn$
  SELECT CASE
    WHEN private.current_user_is_admin() THEN jsonb_build_object(
      'is_admin', true,
      'scopes', to_jsonb(ARRAY['content', 'reports', 'ilanlar', 'live']),
      'ilan_categories', NULL,
      'shop_categories', NULL)
    ELSE jsonb_build_object(
      'is_admin', false,
      'scopes', COALESCE(to_jsonb(m.scopes), '[]'::jsonb),
      'ilan_categories', private.moderator_category_list('ilan', m.ilan_category_ids),
      'shop_categories', private.moderator_category_list('shop', m.shop_category_ids))
  END
  FROM (SELECT 1) AS one
  LEFT JOIN (public.moderators m JOIN public.profiles p ON p.id = m.user_id AND p.status::text = 'active')
    ON m.user_id = (SELECT auth.uid());
$fn$;

-- -----------------------------------------------------------------------------
-- 4) Yönetici: liste, atama, kategori seçenekleri
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
      'ilan_categories', private.moderator_category_list('ilan', m.ilan_category_ids),
      'shop_categories', private.moderator_category_list('shop', m.shop_category_ids),
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


-- İmza değişti (iki kategori parametresi): eski 3 parametreli sürüm kaldırılır;
-- adlı 3 parametreli çağrı (eski uygulama) varsayılanlarla yenisine düşer.
DROP FUNCTION IF EXISTS public.admin_set_moderator(uuid, text[], text);

-- Kapsamları ve kategori sınırlarını yazar; boş kapsam = moderatörlükten çıkar.
-- Kategori parametresi: NULL = değiştirme, boş dizi = tüm kategoriler,
-- dolu dizi = yalnız bunlar.
CREATE OR REPLACE FUNCTION public.admin_set_moderator(
  p_user_id uuid,
  p_scopes text[],
  p_note text DEFAULT NULL,
  p_ilan_category_ids uuid[] DEFAULT NULL,
  p_shop_category_ids uuid[] DEFAULT NULL
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
  v_had_old boolean;
  v_old_scopes text[];
  v_old_ilan uuid[];
  v_old_shop uuid[];
  v_ilan uuid[];
  v_shop uuid[];
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

  SELECT m.scopes, m.ilan_category_ids, m.shop_category_ids
    INTO v_old_scopes, v_old_ilan, v_old_shop
    FROM public.moderators m WHERE m.user_id = p_user_id;
  v_had_old := FOUND;

  -- Kategori sınırları: kapsam yoksa sınır da yok; NULL = eskisi; boş = hepsi.
  v_ilan := CASE
    WHEN NOT ('ilanlar' = ANY (v_scopes)) THEN NULL
    WHEN p_ilan_category_ids IS NULL THEN v_old_ilan
    ELSE NULLIF(ARRAY(SELECT DISTINCT c FROM unnest(p_ilan_category_ids) AS c WHERE c IS NOT NULL ORDER BY 1), '{}'::uuid[])
  END;
  v_shop := CASE
    WHEN NOT ('live' = ANY (v_scopes)) THEN NULL
    WHEN p_shop_category_ids IS NULL THEN v_old_shop
    ELSE NULLIF(ARRAY(SELECT DISTINCT c FROM unnest(p_shop_category_ids) AS c WHERE c IS NOT NULL ORDER BY 1), '{}'::uuid[])
  END;
  IF v_ilan IS NOT NULL AND (
       cardinality(v_ilan) > 100
       OR EXISTS (SELECT 1 FROM unnest(v_ilan) AS c
                   WHERE NOT EXISTS (SELECT 1 FROM public.ilan_categories ic WHERE ic.id = c))) THEN
    RAISE EXCEPTION 'Geçersiz ilan kategorisi' USING ERRCODE = 'P0001', HINT = 'MOD_CATEGORY_INVALID';
  END IF;
  IF v_shop IS NOT NULL AND (
       cardinality(v_shop) > 100
       OR EXISTS (SELECT 1 FROM unnest(v_shop) AS c
                   WHERE NOT EXISTS (SELECT 1 FROM public.categories sc WHERE sc.id = c))) THEN
    RAISE EXCEPTION 'Geçersiz mağaza kategorisi' USING ERRCODE = 'P0001', HINT = 'MOD_CATEGORY_INVALID';
  END IF;

  IF cardinality(v_scopes) = 0 THEN
    DELETE FROM public.moderators WHERE user_id = p_user_id;
    v_ilan := NULL;
    v_shop := NULL;
  ELSE
    INSERT INTO public.moderators (user_id, scopes, note, granted_by, ilan_category_ids, shop_category_ids, created_at, updated_at)
    VALUES (p_user_id, v_scopes, v_note, auth.uid(), v_ilan, v_shop, now(), now())
    ON CONFLICT (user_id) DO UPDATE
      SET scopes = EXCLUDED.scopes, note = EXCLUDED.note,
          granted_by = EXCLUDED.granted_by,
          ilan_category_ids = EXCLUDED.ilan_category_ids,
          shop_category_ids = EXCLUDED.shop_category_ids,
          updated_at = now();
  END IF;

  INSERT INTO public.admin_audit_log (admin_id, action, target_table, target_id, old_data, new_data)
  VALUES (auth.uid(), 'set_moderator', 'moderators', p_user_id::text,
          jsonb_build_object('scopes', to_jsonb(v_old_scopes),
                             'ilan_category_ids', to_jsonb(v_old_ilan),
                             'shop_category_ids', to_jsonb(v_old_shop)),
          jsonb_build_object('scopes', to_jsonb(v_scopes), 'note', v_note,
                             'ilan_category_ids', to_jsonb(v_ilan),
                             'shop_category_ids', to_jsonb(v_shop)));

  IF (v_had_old OR cardinality(v_scopes) > 0)
     AND (v_old_scopes IS DISTINCT FROM v_scopes
          OR v_old_ilan IS DISTINCT FROM v_ilan
          OR v_old_shop IS DISTINCT FROM v_shop) THEN
    SELECT string_agg(
             private.moderation_scope_label(s) || CASE
               WHEN s = 'ilanlar' AND v_ilan IS NOT NULL THEN
                 ' (' || COALESCE((SELECT string_agg(c.name, ', ' ORDER BY c.sort_order, c.name)
                                     FROM public.ilan_categories c WHERE c.id = ANY (v_ilan)), '-') || ')'
               WHEN s = 'live' AND v_shop IS NOT NULL THEN
                 ' (' || COALESCE((SELECT string_agg(c.name, ', ' ORDER BY c.display_order NULLS LAST, c.name)
                                     FROM public.categories c WHERE c.id = ANY (v_shop)), '-') || ')'
               ELSE ''
             END,
             ', ' ORDER BY s)
      INTO v_labels
      FROM unnest(v_scopes) AS s;
    IF cardinality(v_scopes) = 0 THEN
      PERFORM private.moderation_notify(p_user_id, 'Moderatörlük yetkin kaldırıldı',
        'Moderatör yetkin yönetim tarafından kaldırıldı.', p_user_id::text, 'moderator');
    ELSE
      PERFORM private.moderation_notify(p_user_id,
        CASE WHEN NOT v_had_old THEN 'Moderatör oldun' ELSE 'Moderatör yetkilerin güncellendi' END,
        format('Moderasyon alanların: %s. Ayarlar menüsündeki "Moderasyon Paneli"nden ulaşabilirsin.', v_labels),
        p_user_id::text, 'moderator');
    END IF;
  END IF;

  RETURN jsonb_build_object(
    'user_id', p_user_id,
    'scopes', to_jsonb(v_scopes),
    'removed', cardinality(v_scopes) = 0,
    'ilan_category_ids', to_jsonb(v_ilan),
    'shop_category_ids', to_jsonb(v_shop)
  );
END;
$fn$;

-- Kategori seçicisi için iki liste (pasifler de; mevcut atamalar görünsün).
CREATE OR REPLACE FUNCTION public.admin_moderation_categories()
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
  RETURN jsonb_build_object(
    'ilan', COALESCE((
      SELECT jsonb_agg(jsonb_build_object('id', c.id, 'name', c.name, 'is_active', COALESCE(c.is_active, false))
                       ORDER BY c.sort_order, c.name, c.id)
        FROM public.ilan_categories c), '[]'::jsonb),
    'shop', COALESCE((
      SELECT jsonb_agg(jsonb_build_object('id', c.id, 'name', c.name, 'is_active', COALESCE(c.is_active, true))
                       ORDER BY c.display_order NULLS LAST, c.name, c.id)
        FROM public.categories c), '[]'::jsonb)
  );
END;
$fn$;

-- -----------------------------------------------------------------------------
-- 5) İlan moderasyonu: kategori süzgeci (4.6 tanımları)
-- -----------------------------------------------------------------------------
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
  -- Kategori sınırı (NULL = hepsi).
  v_cats uuid[] := private.moderator_category_ids('ilan');
BEGIN
  IF NOT public.auth_is_moderator('ilanlar') THEN
    RAISE EXCEPTION 'Moderatör yetkisi gerekli' USING ERRCODE = '42501';
  END IF;
  RETURN jsonb_build_object(
    'total', (SELECT count(*) FROM public.ilanlar i
               WHERE i.status = 'pending' AND (v_cats IS NULL OR i.category_id = ANY (v_cats))),
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
               'category_id', x.category_id,
               'category_name', c.name,
               'paid_fee', x.paid_fee,
               'created_at', x.created_at,
               'owner', jsonb_build_object(
                 'id', o.id,
                 'name', COALESCE(NULLIF(btrim(o.full_name), ''), o.username),
                 'username', o.username,
                 'avatar_url', o.avatar_url)
             ) ORDER BY x.created_at, x.id)
        FROM (SELECT i.* FROM public.ilanlar i
               WHERE i.status = 'pending' AND (v_cats IS NULL OR i.category_id = ANY (v_cats))
               ORDER BY i.created_at, i.id LIMIT v_limit OFFSET v_offset) x
        LEFT JOIN public.ilan_categories c ON c.id = x.category_id
        LEFT JOIN public.profiles o ON o.id = x.owner_id
    ), '[]'::jsonb)
  );
END;
$fn$;

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
  v_cats uuid[] := private.moderator_category_ids('ilan');
BEGIN
  IF NOT public.auth_is_moderator('ilanlar') THEN
    RAISE EXCEPTION 'Moderatör yetkisi gerekli' USING ERRCODE = '42501';
  END IF;
  SELECT i.id, i.status, i.owner_id, i.title, i.category_id INTO v FROM public.ilanlar i WHERE i.id = p_ilan_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'İlan bulunamadı' USING ERRCODE = 'P0001', HINT = 'ILAN_NOT_FOUND';
  END IF;
  -- Kategori sınırı: moderatör yalnız kendi kategorilerindeki ilanı karara bağlar.
  IF v_cats IS NOT NULL AND NOT COALESCE(v.category_id = ANY (v_cats), false) THEN
    RAISE EXCEPTION 'Bu ilanın kategorisi moderasyon alanınızda değil' USING ERRCODE = '42501', HINT = 'MOD_CATEGORY_FORBIDDEN';
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
-- 6) Canlı yayın moderasyonu: mağaza kategorisi süzgeci (4.6 tanımları)
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
  -- Kategori sınırı (NULL = hepsi) ve ona giren mağazalar.
  v_cats uuid[] := private.moderator_category_ids('shop');
  v_shops uuid[];
BEGIN
  -- Görev 4.6: yönetici ya da 'live' kapsamlı moderatör.
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
  v_cats uuid[] := private.moderator_category_ids('shop');
  v_shop_category uuid;
BEGIN
  -- Görev 4.6: yönetici ya da 'live' kapsamlı moderatör.
  IF NOT public.auth_is_moderator('live') THEN
    RAISE EXCEPTION 'Yönetici ya da moderatör yetkisi gerekli' USING ERRCODE = '42501';
  END IF;
  SELECT ls.status, s.category_id INTO v_status, v_shop_category
    FROM public.live_sessions ls
    JOIN public.shops s ON s.id = ls.shop_id
   WHERE ls.id = p_session_id
     FOR UPDATE OF ls;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Yayın bulunamadı' USING ERRCODE = 'P0001', HINT = 'LIVE_NOT_FOUND';
  END IF;
  -- Kategori sınırı: moderatör yalnız kendi kategorilerindeki mağazanın yayınını kapatır.
  IF v_cats IS NOT NULL AND NOT COALESCE(v_shop_category = ANY (v_cats), false) THEN
    RAISE EXCEPTION 'Bu mağazanın kategorisi moderasyon alanınızda değil' USING ERRCODE = '42501', HINT = 'MOD_CATEGORY_FORBIDDEN';
  END IF;
  IF v_status = 'ended' THEN
    RAISE EXCEPTION 'Bu yayın zaten sona erdi' USING ERRCODE = 'P0001', HINT = 'LIVE_ENDED';
  END IF;
  RETURN private.live_admin_close(p_session_id, v_note);
END;
$fn$;

-- -----------------------------------------------------------------------------
-- 7) Yetkiler
-- -----------------------------------------------------------------------------
REVOKE ALL ON FUNCTION public.admin_set_moderator(uuid, text[], text, uuid[], uuid[]) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_set_moderator(uuid, text[], text, uuid[], uuid[]) TO authenticated;
REVOKE ALL ON FUNCTION public.admin_moderation_categories() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_moderation_categories() TO authenticated;

-- Yeniden tanımlananların yetkileri korunur (CREATE OR REPLACE); yine de açıkça:
REVOKE ALL ON FUNCTION public.my_moderation() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.my_moderation() TO authenticated;
REVOKE ALL ON FUNCTION public.admin_moderators_list() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_moderators_list() TO authenticated;
REVOKE ALL ON FUNCTION public.mod_pending_ilanlar(integer, integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.mod_pending_ilanlar(integer, integer) TO authenticated;
REVOKE ALL ON FUNCTION public.mod_review_ilan(uuid, boolean, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.mod_review_ilan(uuid, boolean, text) TO authenticated;
REVOKE ALL ON FUNCTION public.admin_live_sessions(text, integer, integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_live_sessions(text, integer, integer) TO authenticated;
REVOKE ALL ON FUNCTION public.admin_end_live_session(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_end_live_session(uuid, text) TO authenticated;

COMMIT;

NOTIFY pgrst, 'reload schema';
