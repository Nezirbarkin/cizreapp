-- =============================================================================
-- 1) Kullanıcı kendi kullanıcı adını değiştirebilir
-- 2) Admin > Kullanıcılar için sunucu tarafı sayfalama/arama, detay, askıya
--    alma ve kalıcı silme RPC'leri
--
-- Kullanıcı adı: eskiden "sonradan değiştirilemez"di (yalnızca claim_username
-- ile OAuth sonrası tek seferlik atama). Artık change_my_username ile
-- değiştirilebilir. Giriş `lookup_email_by_username` üzerinden profiles'a
-- baktığı için yeni ad hemen geçerlidir. Eski ad, kullanıcı eylem günlüğüne
-- (username_changed) yazılır — bkz. 20260920000001 profiles tetikleyicisi.
-- =============================================================================

BEGIN;

-- -----------------------------------------------------------------------------
-- change_my_username
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.change_my_username(p_username text)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_uid      uuid := auth.uid();
  v_username text := lower(btrim(COALESCE(p_username, '')));
  v_current  text;
  v_is_admin boolean;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'change_my_username: not authenticated' USING ERRCODE = '28000';
  END IF;

  IF v_username !~ '^[a-z0-9._-]{3,20}$' THEN
    RAISE EXCEPTION 'change_my_username: invalid format' USING ERRCODE = '22023';
  END IF;

  IF v_username LIKE 'misafir\_%' ESCAPE '\' OR v_username LIKE 'silinen\_%' ESCAPE '\' THEN
    RAISE EXCEPTION 'change_my_username: reserved prefix' USING ERRCODE = '22023';
  END IF;

  SELECT username, (role::text = 'admin')
    INTO v_current, v_is_admin
  FROM public.profiles
  WHERE id = v_uid
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'change_my_username: profile not found' USING ERRCODE = 'P0002';
  END IF;

  IF lower(COALESCE(v_current, '')) = v_username THEN
    RAISE EXCEPTION 'change_my_username: same username' USING ERRCODE = '22023';
  END IF;

  -- Resmi görünen adların taklidi: yalnızca admin bu adları alabilir.
  IF NOT COALESCE(v_is_admin, false)
     AND v_username = ANY (ARRAY['admin', 'administrator', 'cizreapp', 'destek', 'support', 'moderator', 'system', 'yonetici']) THEN
    RAISE EXCEPTION 'change_my_username: reserved name' USING ERRCODE = '22023';
  END IF;

  BEGIN
    UPDATE public.profiles
       SET username = v_username, needs_username = false, updated_at = now()
     WHERE id = v_uid;
  EXCEPTION WHEN unique_violation THEN
    RAISE EXCEPTION 'change_my_username: username taken' USING ERRCODE = '23505';
  END;

  -- Kayıt akışının okuduğu metadata da tutarlı kalsın.
  UPDATE auth.users
     SET raw_user_meta_data = COALESCE(raw_user_meta_data, '{}'::jsonb)
                              || jsonb_build_object('username', v_username)
   WHERE id = v_uid;

  RETURN v_username;
END;
$$;

REVOKE ALL ON FUNCTION public.change_my_username(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.change_my_username(text) TO authenticated;

COMMENT ON FUNCTION public.change_my_username(text) IS
  'Kullanıcının kendi kullanıcı adını değiştirmesi. Format ^[a-z0-9._-]{3,20}$, benzersiz (büyük/küçük harf duyarsız). Değişiklik user_activity_logs''a düşer.';

-- -----------------------------------------------------------------------------
-- admin_users_page — sunucu tarafı arama/filtre/sıralama/sayfalama
-- (eski admin_user_list_with_stats en fazla 100 satırdı ve arama yalnızca o
-- 100 satır üzerinde istemcide çalışıyordu)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_users_page(
  p_search text    DEFAULT NULL,
  p_role   text    DEFAULT NULL,
  p_filter text    DEFAULT NULL,  -- online | new | suspicious | suspended | verified
  p_sort   text    DEFAULT 'newest', -- newest | oldest | last_seen | name
  p_limit  integer DEFAULT 30,
  p_offset integer DEFAULT 0
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_limit  integer := LEAST(GREATEST(COALESCE(p_limit, 30), 1), 100);
  v_offset integer := GREATEST(COALESCE(p_offset, 0), 0);
  v_q      text := NULLIF(btrim(COALESCE(p_search, '')), '');
  v_sort   text := COALESCE(p_sort, 'newest');
  v_res    jsonb;
BEGIN
  IF NOT private.current_user_is_admin() THEN
    RAISE EXCEPTION 'admin_users_page: not admin' USING ERRCODE = '42501';
  END IF;

  WITH f AS (
    SELECT p.*
    FROM public.profiles AS p
    WHERE COALESCE(p.is_bot, false) = false
      AND (p_role IS NULL OR p.role::text = p_role)
      AND (v_q IS NULL
           OR p.username ILIKE '%' || v_q || '%'
           OR p.full_name ILIKE '%' || v_q || '%'
           OR p.email ILIKE '%' || v_q || '%'
           OR p.phone ILIKE '%' || v_q || '%')
      AND (p_filter IS NULL
           OR (p_filter = 'online'     AND p.last_seen >= now() - interval '5 minutes')
           OR (p_filter = 'new'        AND p.created_at >= now() - interval '7 days')
           OR (p_filter = 'suspicious' AND COALESCE(p.is_suspicious, false))
           OR (p_filter = 'suspended'  AND p.status::text IN ('suspended', 'deleted'))
           OR (p_filter = 'verified'   AND COALESCE(p.is_verified, false)))
  ),
  c AS (SELECT count(*) AS n FROM f),
  pg AS (
    SELECT f.id, f.username, f.full_name, f.avatar_url, f.role::text AS role,
           f.status::text AS status, f.email, f.phone,
           COALESCE(f.is_suspicious, false) AS is_suspicious,
           COALESCE(f.is_verified, false) AS is_verified,
           (f.last_seen >= now() - interval '5 minutes') AS is_online,
           f.platform, f.created_at, f.last_seen, f.delivered_count,
           row_number() OVER (
             ORDER BY
               CASE WHEN v_sort = 'oldest'    THEN f.created_at END ASC,
               CASE WHEN v_sort = 'name'      THEN lower(COALESCE(NULLIF(f.full_name, ''), f.username)) END ASC,
               CASE WHEN v_sort = 'last_seen' THEN f.last_seen END DESC NULLS LAST,
               f.created_at DESC
           ) AS rn
    FROM f
    ORDER BY rn
    LIMIT v_limit OFFSET v_offset
  )
  SELECT jsonb_build_object(
    'total', (SELECT n FROM c),
    'rows', COALESCE((
      SELECT jsonb_agg(
        (to_jsonb(pg) - 'rn') || jsonb_build_object(
          'posts_count',     (SELECT count(*) FROM public.posts   x WHERE x.user_id = pg.id),
          'followers_count', (SELECT count(*) FROM public.follows x WHERE x.following_id = pg.id),
          'following_count', (SELECT count(*) FROM public.follows x WHERE x.follower_id = pg.id)
        )
        ORDER BY pg.rn
      )
      FROM pg
    ), '[]'::jsonb)
  ) INTO v_res;

  RETURN v_res;
END;
$$;

-- -----------------------------------------------------------------------------
-- admin_user_detail — kullanıcı detay sayfası için tek çağrı
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_user_detail(p_target uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_res jsonb;
BEGIN
  IF NOT private.current_user_is_admin() THEN
    RAISE EXCEPTION 'admin_user_detail: not admin' USING ERRCODE = '42501';
  END IF;

  SELECT jsonb_build_object(
    'id', p.id,
    'username', p.username,
    'full_name', p.full_name,
    'avatar_url', p.avatar_url,
    'cover_url', p.cover_url,
    'bio', p.bio,
    'location', p.location,
    'website', p.website,
    'gender', p.gender,
    'role', p.role::text,
    'status', p.status::text,
    'email', p.email,
    'phone', p.phone,
    'is_suspicious', COALESCE(p.is_suspicious, false),
    'suspicious_reason', p.suspicious_reason,
    'is_verified', COALESCE(p.is_verified, false),
    'platform', p.platform,
    'created_at', p.created_at,
    'last_seen', p.last_seen,
    'is_online', (p.last_seen >= now() - interval '5 minutes'),
    'provider', u.raw_app_meta_data->>'provider',
    'last_sign_in_at', u.last_sign_in_at,
    'email_confirmed_at', u.email_confirmed_at,
    'banned_until', u.banned_until,
    'posts_count', (SELECT count(*) FROM public.posts x WHERE x.user_id = p.id),
    'followers_count', (SELECT count(*) FROM public.follows x WHERE x.following_id = p.id),
    'following_count', (SELECT count(*) FROM public.follows x WHERE x.follower_id = p.id),
    'orders_count', (SELECT count(*) FROM public.orders x WHERE x.user_id = p.id),
    'digital_orders_count', (SELECT count(*) FROM public.digital_orders x WHERE x.user_id = p.id),
    'activity_count', (SELECT count(*) FROM public.user_activity_logs x WHERE x.user_id = p.id),
    'balance', COALESCE((SELECT b.balance FROM public.user_balances b WHERE b.user_id = p.id), 0),
    'points', COALESCE((SELECT a.balance_points FROM public.user_point_accounts a WHERE a.user_id = p.id), 0),
    'shop_name', (SELECT s.name FROM public.shops s WHERE s.owner_id = p.id LIMIT 1)
  )
  INTO v_res
  FROM public.profiles AS p
  LEFT JOIN auth.users AS u ON u.id = p.id
  WHERE p.id = p_target;

  IF v_res IS NULL THEN
    RAISE EXCEPTION 'admin_user_detail: user not found' USING ERRCODE = 'P0002';
  END IF;
  RETURN v_res;
END;
$$;

-- -----------------------------------------------------------------------------
-- admin_set_user_status — askıya al / yeniden etkinleştir
--
-- profiles.status tek başına hiçbir şeyi engellemiyordu (istemcide de sunucuda
-- da okunmuyor). Gerçek engel auth.users.banned_until: GoTrue yeni girişi ve
-- token yenilemeyi reddeder. Açık oturumlar da düşürülür; mevcut erişim token'ı
-- en fazla süresi (≤1 saat) dolana dek geçerli kalır.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_set_user_status(
  p_target uuid,
  p_status text,
  p_reason text DEFAULT NULL
)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_admin uuid := auth.uid();
  v_role  text;
  v_old   text;
BEGIN
  IF NOT private.current_user_is_admin() THEN
    RAISE EXCEPTION 'admin_set_user_status: not admin' USING ERRCODE = '42501';
  END IF;
  IF p_status NOT IN ('active', 'suspended') THEN
    RAISE EXCEPTION 'admin_set_user_status: invalid status' USING ERRCODE = '22023';
  END IF;
  IF p_target IS NULL OR p_target = v_admin THEN
    RAISE EXCEPTION 'admin_set_user_status: cannot change own status' USING ERRCODE = '22023';
  END IF;

  SELECT role::text, status::text INTO v_role, v_old
  FROM public.profiles WHERE id = p_target FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'admin_set_user_status: user not found' USING ERRCODE = 'P0002';
  END IF;
  IF v_role = 'admin' THEN
    RAISE EXCEPTION 'admin_set_user_status: target is admin' USING ERRCODE = '22023';
  END IF;
  IF v_old = 'deleted' THEN
    RAISE EXCEPTION 'admin_set_user_status: user deleted' USING ERRCODE = '22023';
  END IF;

  UPDATE public.profiles
     SET status = p_status::public.user_status, updated_at = now()
   WHERE id = p_target;

  IF p_status = 'suspended' THEN
    UPDATE auth.users SET banned_until = 'infinity' WHERE id = p_target;
    DELETE FROM auth.sessions WHERE user_id = p_target;
  ELSE
    UPDATE auth.users SET banned_until = NULL WHERE id = p_target;
  END IF;

  INSERT INTO public.admin_audit_log (admin_id, action, target_table, target_id, old_data, new_data)
  VALUES (v_admin, 'set_user_status', 'profiles', p_target::text,
          jsonb_build_object('status', v_old),
          jsonb_build_object('status', p_status, 'reason', left(p_reason, 300)));

  RETURN p_status;
END;
$$;

-- -----------------------------------------------------------------------------
-- admin_delete_user — kalıcı silme
--
-- Önce KALICI (hard) silme denenir: profil + auth.users tamamen kalkar, ona
-- bağlı sosyal içerik kaskadla gider, "admin/onaylayan" gibi isteğe bağlı
-- referanslar NULL'lanır.
--
-- Kullanıcının silinemeyen finansal kaydı varsa (dijital sipariş, ödeme
-- işlemi, puan defteri...) o kayıtlar KORUNMALIDIR; bu durumda satır silinmez,
-- hesap ANONİMLEŞTİRİLİR (soft): kişisel veri temizlenir, sosyal içerik
-- silinir, giriş kalıcı olarak kapatılır. Sonuç jsonb `mode` alanında döner.
--
-- KESİN ENGELLER (silme yapılmaz, hata döner):
--   * kendi hesabın, admin hesapları,
--   * dükkan sahibi (profil silinince dükkan+ürünleri kaskadla giderdi),
--   * cüzdan bakiyesi > 0 (kullanıcının parası, kaskadla yok olurdu).
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_delete_user(
  p_target uuid,
  p_reason text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_admin     uuid := auth.uid();
  v_prof      record;
  v_short     text;
  v_ghost     text;
  v_balance   numeric;
  v_cnt       bigint;
  v_needs_soft boolean := false;
  v_blockers  text[] := ARRAY[]::text[];
  v_mode      text := 'hard';
  r           record;
  -- NOT NULL bir sütunla bağlı olsa da güvenle silinebilen geçici tablolar
  v_ephemeral constant text[] := ARRAY[
    'public.smm_rate_limits', 'public.withdrawal_attempts', 'public.task_submissions'
  ];
BEGIN
  IF NOT private.current_user_is_admin() THEN
    RAISE EXCEPTION 'admin_delete_user: not admin' USING ERRCODE = '42501';
  END IF;
  IF p_target IS NULL OR p_target = v_admin THEN
    RAISE EXCEPTION 'admin_delete_user: cannot delete self' USING ERRCODE = '22023';
  END IF;

  SELECT id, username, email, role::text AS role, status::text AS status
    INTO v_prof
  FROM public.profiles WHERE id = p_target FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'admin_delete_user: user not found' USING ERRCODE = 'P0002';
  END IF;
  IF v_prof.role = 'admin' THEN
    RAISE EXCEPTION 'admin_delete_user: target is admin' USING ERRCODE = '22023';
  END IF;
  IF v_prof.status = 'deleted' THEN
    RAISE EXCEPTION 'admin_delete_user: already deleted' USING ERRCODE = '22023';
  END IF;

  IF EXISTS (SELECT 1 FROM public.shops WHERE owner_id = p_target) THEN
    RAISE EXCEPTION 'admin_delete_user: owns shop' USING ERRCODE = '23503';
  END IF;

  SELECT COALESCE(balance, 0) INTO v_balance FROM public.user_balances WHERE user_id = p_target;
  IF COALESCE(v_balance, 0) > 0 THEN
    RAISE EXCEPTION 'admin_delete_user: has balance' USING ERRCODE = '23503';
  END IF;

  v_short := substr(replace(p_target::text, '-', ''), 1, 8);
  v_ghost := 'deleted+' || replace(p_target::text, '-', '') || '@cizreapp.invalid';

  -- Sınıflandırma: hangi referanslar silmeyi engelliyor?
  FOR r IN
    SELECT c.conrelid::regclass::text AS tbl, a.attname::text AS col, a.attnotnull AS notnull
    FROM pg_constraint AS c
    JOIN pg_attribute AS a ON a.attrelid = c.conrelid AND a.attnum = c.conkey[1]
    WHERE c.contype = 'f'
      AND c.confdeltype IN ('a', 'r')
      AND array_length(c.conkey, 1) = 1
      AND c.confrelid IN ('public.profiles'::regclass, 'auth.users'::regclass)
      AND c.conrelid <> 'public.profiles'::regclass
  LOOP
    EXECUTE format('SELECT count(*) FROM %s WHERE %I = $1', r.tbl, r.col) INTO v_cnt USING p_target;
    IF v_cnt > 0 AND r.notnull AND NOT (r.tbl = ANY (v_ephemeral)) THEN
      v_needs_soft := true;
      v_blockers := v_blockers || format('%s (%s)', r.tbl, v_cnt);
    END IF;
  END LOOP;

  IF NOT v_needs_soft THEN
    BEGIN
      FOR r IN
        SELECT c.conrelid::regclass::text AS tbl, a.attname::text AS col, a.attnotnull AS notnull
        FROM pg_constraint AS c
        JOIN pg_attribute AS a ON a.attrelid = c.conrelid AND a.attnum = c.conkey[1]
        WHERE c.contype = 'f'
          AND c.confdeltype IN ('a', 'r')
          AND array_length(c.conkey, 1) = 1
          AND c.confrelid IN ('public.profiles'::regclass, 'auth.users'::regclass)
          AND c.conrelid <> 'public.profiles'::regclass
      LOOP
        IF r.notnull THEN
          EXECUTE format('DELETE FROM %s WHERE %I = $1', r.tbl, r.col) USING p_target;
        ELSE
          EXECUTE format('UPDATE %s SET %I = NULL WHERE %I = $1', r.tbl, r.col, r.col) USING p_target;
        END IF;
      END LOOP;

      DELETE FROM public.user_activity_logs WHERE user_id = p_target;
      DELETE FROM public.profiles WHERE id = p_target;
      DELETE FROM auth.users WHERE id = p_target;
      v_mode := 'hard';
    EXCEPTION WHEN foreign_key_violation THEN
      -- Beklenmedik bir referans: alt işlem geri alınır, anonimleştirmeye düşülür.
      v_needs_soft := true;
      v_blockers := v_blockers || SQLERRM;
    END;
  END IF;

  IF v_needs_soft THEN
    v_mode := 'soft';

    DELETE FROM public.post_comments    WHERE user_id = p_target;
    DELETE FROM public.post_likes       WHERE user_id = p_target;
    DELETE FROM public.post_favorites   WHERE user_id = p_target;
    DELETE FROM public.product_favorites WHERE user_id = p_target;
    DELETE FROM public.stories          WHERE user_id = p_target;
    DELETE FROM public.posts            WHERE user_id = p_target;
    DELETE FROM public.follows          WHERE follower_id = p_target OR following_id = p_target;
    DELETE FROM public.user_activity_logs WHERE user_id = p_target;

    UPDATE public.profiles SET
      username = 'silinen_' || v_short,
      full_name = 'Silinmiş Kullanıcı',
      email = v_ghost,
      phone = NULL, avatar_url = NULL, banner_url = NULL, cover_url = NULL,
      bio = NULL, website = NULL, location = NULL, gender = NULL, fcm_token = NULL,
      is_online = false, profile_is_public = false, needs_username = false,
      status = 'deleted'::public.user_status, updated_at = now()
    WHERE id = p_target;

    UPDATE auth.users SET
      email = v_ghost,
      phone = NULL,
      raw_user_meta_data = '{}'::jsonb,
      banned_until = 'infinity'
    WHERE id = p_target;
    DELETE FROM auth.identities WHERE user_id = p_target;
    DELETE FROM auth.sessions   WHERE user_id = p_target;
  END IF;

  INSERT INTO public.admin_audit_log (admin_id, action, target_table, target_id, old_data, new_data)
  VALUES (v_admin, 'delete_user', 'profiles', p_target::text,
          jsonb_build_object('username', v_prof.username, 'email', v_prof.email, 'role', v_prof.role),
          jsonb_build_object('mode', v_mode, 'reason', left(p_reason, 300), 'blockers', to_jsonb(v_blockers)));

  RETURN jsonb_build_object('mode', v_mode, 'blockers', to_jsonb(v_blockers));
END;
$$;

REVOKE ALL ON FUNCTION public.admin_users_page(text, text, text, text, integer, integer) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.admin_user_detail(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.admin_set_user_status(uuid, text, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.admin_delete_user(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_users_page(text, text, text, text, integer, integer) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.admin_user_detail(uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.admin_set_user_status(uuid, text, text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.admin_delete_user(uuid, text) TO authenticated, service_role;

COMMIT;

NOTIFY pgrst, 'reload schema';
