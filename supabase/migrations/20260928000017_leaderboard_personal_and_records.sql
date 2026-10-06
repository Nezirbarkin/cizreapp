-- =============================================================================
-- Görev 4.4 — Liderler Tablosu: "Rakamlarla Sen" + "Rekor Skorlar"
-- =============================================================================
--
-- 1) "Rakamlarla Sen" (`my_stats`): çağıranın KENDİ sayıları (üyelik günü,
--    gönderi, aldığı beğeni, gönderi görüntülenmesi, takipçi/takip, tamamlanan
--    sipariş, giriş, Okey maç/galibiyet). Yalnız kendisine döner; misafir
--    (anonim) hesaba dönmez. Sayaç kartı altyapısını kullanır: anahtarlar
--    `stats` haritasına `my_` önekiyle girer, admin anahtarları
--    `leaderboard_stat_my_*`.
-- 2) "Rekor Skorlar" (`records`): tüm zamanların rekorları — en kalabalık gün,
--    tek günde en çok yeni üye/sipariş/gönderi, en eski üye, en çok beğenilen
--    gönderi, en kalabalık canlı yayın, ilk gönderi. Admin anahtarları
--    `leaderboard_record_*`. Kişi/gönderi rekorları mevcut uygunluk kurallarını
--    (`leaderboard_eligible_users`: bot, gizli hesap, liderlikten gizlenen,
--    iki yönlü engel) uygular.
--
-- Kart anahtarları Dart'taki `LeaderboardBoard` enum sırasıyla AYNI olmalı
-- ('stats_today'dan sonra 'my_stats', 'records'). Admin kayıtlı bir sıra
-- belirlediyse yeni kartlar sona eklenir (`leaderboard_order`).

BEGIN;

INSERT INTO public.app_settings (key, value, description)
VALUES
  ('leaderboard_board_my_stats', '"true"', 'Kart: Rakamlarla Sen (kullanıcının kendi sayıları)'),
  ('leaderboard_board_records', '"true"', 'Kart: Rekor Skorlar'),
  ('leaderboard_stat_my_days', '"true"', 'Kişisel sayaç: gündür üye'),
  ('leaderboard_stat_my_posts', '"true"', 'Kişisel sayaç: gönderi'),
  ('leaderboard_stat_my_likes', '"true"', 'Kişisel sayaç: aldığı beğeni'),
  ('leaderboard_stat_my_post_views', '"true"', 'Kişisel sayaç: gönderi görüntülenmesi'),
  ('leaderboard_stat_my_followers', '"true"', 'Kişisel sayaç: takipçi'),
  ('leaderboard_stat_my_following', '"true"', 'Kişisel sayaç: takip ettiği'),
  ('leaderboard_stat_my_orders', '"true"', 'Kişisel sayaç: tamamlanan sipariş'),
  ('leaderboard_stat_my_logins', '"true"', 'Kişisel sayaç: giriş (günlük 90 gün saklanır)'),
  ('leaderboard_stat_my_okey_matches', '"true"', 'Kişisel sayaç: Okey maçı'),
  ('leaderboard_stat_my_okey_wins', '"true"', 'Kişisel sayaç: Okey galibiyeti'),
  ('leaderboard_record_busiest_day', '"true"', 'Rekor: en kalabalık gün'),
  ('leaderboard_record_signup_day', '"true"', 'Rekor: tek günde en çok yeni üye'),
  ('leaderboard_record_orders_day', '"true"', 'Rekor: tek günde en çok sipariş'),
  ('leaderboard_record_posts_day', '"true"', 'Rekor: tek günde en çok gönderi'),
  ('leaderboard_record_oldest_member', '"true"', 'Rekor: en eski üye'),
  ('leaderboard_record_top_post_likes', '"true"', 'Rekor: en çok beğenilen gönderi'),
  ('leaderboard_record_live_peak', '"true"', 'Rekor: en kalabalık canlı yayın'),
  ('leaderboard_record_first_post', '"true"', 'Rekor: ilk gönderi')
ON CONFLICT (key) DO NOTHING;

-- -----------------------------------------------------------------------------
-- 1) Kart ve anahtar listeleri
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.leaderboard_card_keys()
RETURNS text[]
LANGUAGE sql
IMMUTABLE
SET search_path = ''
AS $fn$
  SELECT ARRAY[
    'stats', 'stats_today', 'my_stats', 'records', 'new_members', 'top_followed',
    'top_liked_posts', 'top_viewed_posts', 'top_viewed_stories', 'top_sellers',
    'top_product_sellers', 'top_customers', 'top_rated_shops',
    'top_posters', 'most_liked', 'top_logins', 'top_couriers',
    'okey_most_played', 'okey_most_wins', 'okey_most_losses',
    'okey_win_rate', 'okey_richest', 'okey_points_won',
    'okey_hands_won', 'okey_best_score'
  ];
$fn$;

CREATE OR REPLACE FUNCTION public.leaderboard_personal_stat_keys()
RETURNS text[]
LANGUAGE sql
IMMUTABLE
SET search_path = ''
AS $fn$
  SELECT ARRAY[
    'my_days', 'my_posts', 'my_likes', 'my_post_views', 'my_followers',
    'my_following', 'my_orders', 'my_logins', 'my_okey_matches', 'my_okey_wins'
  ];
$fn$;

CREATE OR REPLACE FUNCTION public.leaderboard_record_keys()
RETURNS text[]
LANGUAGE sql
IMMUTABLE
SET search_path = ''
AS $fn$
  SELECT ARRAY[
    'busiest_day', 'signup_day', 'orders_day', 'posts_day',
    'oldest_member', 'top_post_likes', 'live_peak', 'first_post'
  ];
$fn$;

-- -----------------------------------------------------------------------------
-- 2) Rakamlarla Sen — yalnız çağıranın sayıları
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.leaderboard_my_stats()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $fn$
DECLARE
  v_uid uuid := (SELECT auth.uid());
  v_created timestamptz;
  v_okey public.okey_stats%ROWTYPE;
BEGIN
  IF v_uid IS NULL
     OR EXISTS (SELECT 1 FROM auth.users a WHERE a.id = v_uid AND a.is_anonymous) THEN
    RETURN '{}'::jsonb;
  END IF;
  SELECT p.created_at INTO v_created FROM public.profiles p WHERE p.id = v_uid;
  IF NOT FOUND THEN
    RETURN '{}'::jsonb;
  END IF;
  SELECT * INTO v_okey FROM public.okey_stats s WHERE s.user_id = v_uid;

  -- Kapalı sayaç NULL döner, jsonb_strip_nulls çıkarır; CASE tembel çalışır.
  RETURN jsonb_strip_nulls(jsonb_build_object(
    'my_days', CASE WHEN public.leaderboard_flag('leaderboard_stat_my_days', true) THEN
      GREATEST(0, (now() AT TIME ZONE 'Europe/Istanbul')::date
                  - (v_created AT TIME ZONE 'Europe/Istanbul')::date) END,
    'my_posts', CASE WHEN public.leaderboard_flag('leaderboard_stat_my_posts', true) THEN
      (SELECT count(*) FROM public.posts x WHERE x.user_id = v_uid AND x.is_active IS NOT FALSE) END,
    'my_likes', CASE WHEN public.leaderboard_flag('leaderboard_stat_my_likes', true) THEN
      (SELECT COALESCE(sum(COALESCE(x.likes_count, 0)), 0)::bigint
         FROM public.posts x WHERE x.user_id = v_uid AND x.is_active IS NOT FALSE) END,
    -- Kendi görüntülemeleri sayılmaz (top_viewed_posts ile aynı kural).
    'my_post_views', CASE WHEN public.leaderboard_flag('leaderboard_stat_my_post_views', true) THEN
      (SELECT count(*) FROM public.post_views v
         JOIN public.posts x ON x.id = v.post_id
        WHERE x.user_id = v_uid AND v.viewer_id IS DISTINCT FROM v_uid) END,
    'my_followers', CASE WHEN public.leaderboard_flag('leaderboard_stat_my_followers', true) THEN
      (SELECT count(*) FROM public.follows f WHERE f.following_id = v_uid) END,
    'my_following', CASE WHEN public.leaderboard_flag('leaderboard_stat_my_following', true) THEN
      (SELECT count(*) FROM public.follows f WHERE f.follower_id = v_uid) END,
    'my_orders', CASE WHEN public.leaderboard_flag('leaderboard_stat_my_orders', true) THEN
      (SELECT count(*) FROM public.leaderboard_completed_orders('-infinity'::timestamptz) o
        WHERE o.o_user_id = v_uid) END,
    'my_logins', CASE WHEN public.leaderboard_flag('leaderboard_stat_my_logins', true) THEN
      (SELECT count(*) FROM public.user_activity_logs l
        WHERE l.user_id = v_uid AND l.action = 'login') END,
    'my_okey_matches', CASE WHEN public.leaderboard_flag('leaderboard_stat_my_okey_matches', true) THEN
      COALESCE(v_okey.matches_played, 0) END,
    'my_okey_wins', CASE WHEN public.leaderboard_flag('leaderboard_stat_my_okey_wins', true) THEN
      COALESCE(v_okey.matches_won, 0) END
  ));
END;
$fn$;

-- -----------------------------------------------------------------------------
-- 3) Rekor Skorlar
--
-- Her rekor: {value, at, type ('day'|'user'|'post'|'shop'), id, name, handle,
-- avatar, owner, detail}. Kapalı ya da verisi olmayan rekor dönmez.
-- "Gün" İstanbul takvim günüdür. En kalabalık gün = o gün iz bırakan farklı
-- kişi sayısı (eylem günlüğü ∪ analitik olay ∪ son görülme; misafir dahil,
-- bot hariç) — "Bugün ziyaretçi" sayacıyla aynı tanım.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.leaderboard_records()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $fn$
DECLARE
  v_out jsonb := '{}'::jsonb;
  v_day date;
  v_n bigint;
  v_rec record;
BEGIN
  IF public.leaderboard_flag('leaderboard_record_busiest_day', true) THEN
    WITH seen AS (
      SELECT l.user_id AS uid, (l.created_at AT TIME ZONE 'Europe/Istanbul')::date AS d
        FROM public.user_activity_logs l WHERE l.user_id IS NOT NULL
      UNION
      SELECT e.user_id, (e.created_at AT TIME ZONE 'Europe/Istanbul')::date
        FROM public.app_analytics_events e WHERE e.user_id IS NOT NULL
      UNION
      SELECT p.id, (p.last_seen AT TIME ZONE 'Europe/Istanbul')::date
        FROM public.profiles p WHERE p.last_seen IS NOT NULL
    )
    SELECT s.d, count(*) INTO v_day, v_n
      FROM seen s
      JOIN public.profiles p ON p.id = s.uid
     WHERE NOT COALESCE(p.is_bot, false) AND p.status::text = 'active'
     GROUP BY s.d
     ORDER BY count(*) DESC, s.d DESC
     LIMIT 1;
    IF v_day IS NOT NULL THEN
      v_out := v_out || jsonb_build_object('busiest_day',
        jsonb_build_object('value', v_n, 'at', v_day, 'type', 'day'));
    END IF;
  END IF;

  IF public.leaderboard_flag('leaderboard_record_signup_day', true) THEN
    v_day := NULL;
    SELECT (p.created_at AT TIME ZONE 'Europe/Istanbul')::date, count(*) INTO v_day, v_n
      FROM public.profiles p
     WHERE NOT COALESCE(p.is_bot, false) AND p.status::text = 'active'
       AND NOT EXISTS (SELECT 1 FROM auth.users a WHERE a.id = p.id AND a.is_anonymous)
     GROUP BY 1
     ORDER BY count(*) DESC, 1 DESC
     LIMIT 1;
    IF v_day IS NOT NULL THEN
      v_out := v_out || jsonb_build_object('signup_day',
        jsonb_build_object('value', v_n, 'at', v_day, 'type', 'day'));
    END IF;
  END IF;

  -- Tamamlanan sipariş: fiziksel 'delivered' + dijital 'completed' (sayaçla aynı).
  IF public.leaderboard_flag('leaderboard_record_orders_day', true) THEN
    v_day := NULL;
    SELECT x.d, count(*) INTO v_day, v_n
      FROM (
        SELECT (o.created_at AT TIME ZONE 'Europe/Istanbul')::date AS d
          FROM public.orders o WHERE o.status::text = 'delivered'
        UNION ALL
        SELECT (d.created_at AT TIME ZONE 'Europe/Istanbul')::date
          FROM public.digital_orders d WHERE d.status::text = 'completed'
      ) x
     GROUP BY x.d
     ORDER BY count(*) DESC, x.d DESC
     LIMIT 1;
    IF v_day IS NOT NULL THEN
      v_out := v_out || jsonb_build_object('orders_day',
        jsonb_build_object('value', v_n, 'at', v_day, 'type', 'day'));
    END IF;
  END IF;

  IF public.leaderboard_flag('leaderboard_record_posts_day', true) THEN
    v_day := NULL;
    SELECT (x.created_at AT TIME ZONE 'Europe/Istanbul')::date, count(*) INTO v_day, v_n
      FROM public.posts x
      JOIN public.profiles p ON p.id = x.user_id
     WHERE x.is_active IS NOT FALSE AND NOT COALESCE(p.is_bot, false)
     GROUP BY 1
     ORDER BY count(*) DESC, 1 DESC
     LIMIT 1;
    IF v_day IS NOT NULL THEN
      v_out := v_out || jsonb_build_object('posts_day',
        jsonb_build_object('value', v_n, 'at', v_day, 'type', 'day'));
    END IF;
  END IF;

  -- Yönetici hesapları (uygulamanın kurucu hesabı) "üye" rekoru sayılmaz.
  IF public.leaderboard_flag('leaderboard_record_oldest_member', true) THEN
    SELECT e.e_id, e.e_created_at, e.e_name, e.e_handle, e.e_avatar INTO v_rec
      FROM public.leaderboard_eligible_users() e
      JOIN public.profiles p ON p.id = e.e_id
     WHERE p.role::text <> 'admin' AND NOT COALESCE(p.is_admin, false)
       AND NOT EXISTS (SELECT 1 FROM auth.users a WHERE a.id = e.e_id AND a.is_anonymous)
     ORDER BY e.e_created_at, e.e_id
     LIMIT 1;
    IF FOUND THEN
      v_out := v_out || jsonb_build_object('oldest_member', jsonb_build_object(
        'value', GREATEST(0, (now() AT TIME ZONE 'Europe/Istanbul')::date
                             - (v_rec.e_created_at AT TIME ZONE 'Europe/Istanbul')::date),
        'at', v_rec.e_created_at, 'type', 'user', 'id', v_rec.e_id,
        'name', v_rec.e_name, 'handle', v_rec.e_handle, 'avatar', v_rec.e_avatar));
    END IF;
  END IF;

  IF public.leaderboard_flag('leaderboard_record_top_post_likes', true) THEN
    SELECT po.id, po.created_at, po.likes_count, po.user_id,
           COALESCE(NULLIF(left(regexp_replace(btrim(COALESCE(po.content, '')), '\s+', ' ', 'g'), 80), ''),
                    'Fotoğraflı gönderi') AS preview,
           e.e_handle, COALESCE(po.images[1], po.image_url) AS image
      INTO v_rec
      FROM public.posts po
      JOIN public.leaderboard_eligible_users() e ON e.e_id = po.user_id
     WHERE po.is_active IS NOT FALSE AND COALESCE(po.likes_count, 0) > 0
     ORDER BY po.likes_count DESC, po.created_at DESC, po.id
     LIMIT 1;
    IF FOUND THEN
      v_out := v_out || jsonb_build_object('top_post_likes', jsonb_build_object(
        'value', v_rec.likes_count, 'at', v_rec.created_at, 'type', 'post', 'id', v_rec.id,
        'name', v_rec.preview, 'handle', v_rec.e_handle, 'avatar', v_rec.image, 'owner', v_rec.user_id));
    END IF;
  END IF;

  IF public.leaderboard_flag('leaderboard_record_live_peak', true) THEN
    SELECT ls.peak_viewer_count, ls.started_at, ls.title, s.id AS shop_id, s.name, s.logo_url INTO v_rec
      FROM public.live_sessions ls
      JOIN public.shops s ON s.id = ls.shop_id
     WHERE ls.started_at IS NOT NULL AND ls.peak_viewer_count > 0
       AND s.is_active AND COALESCE(s.is_approved, true)
       AND public.leaderboard_owner_ok(s.owner_id)
     ORDER BY ls.peak_viewer_count DESC, ls.started_at DESC, ls.id
     LIMIT 1;
    IF FOUND THEN
      v_out := v_out || jsonb_build_object('live_peak', jsonb_build_object(
        'value', v_rec.peak_viewer_count, 'at', v_rec.started_at, 'type', 'shop', 'id', v_rec.shop_id,
        'name', v_rec.name, 'avatar', v_rec.logo_url, 'detail', v_rec.title));
    END IF;
  END IF;

  IF public.leaderboard_flag('leaderboard_record_first_post', true) THEN
    SELECT po.id, po.created_at, po.user_id,
           COALESCE(NULLIF(left(regexp_replace(btrim(COALESCE(po.content, '')), '\s+', ' ', 'g'), 80), ''),
                    'Fotoğraflı gönderi') AS preview,
           e.e_handle, COALESCE(po.images[1], po.image_url) AS image
      INTO v_rec
      FROM public.posts po
      JOIN public.leaderboard_eligible_users() e ON e.e_id = po.user_id
     WHERE po.is_active IS NOT FALSE
     ORDER BY po.created_at, po.id
     LIMIT 1;
    IF FOUND THEN
      v_out := v_out || jsonb_build_object('first_post', jsonb_build_object(
        'at', v_rec.created_at, 'type', 'post', 'id', v_rec.id,
        'name', v_rec.preview, 'handle', v_rec.e_handle, 'avatar', v_rec.image, 'owner', v_rec.user_id));
    END IF;
  END IF;

  RETURN v_out;
END;
$fn$;

-- -----------------------------------------------------------------------------
-- 4) Ayarlar: kişisel sayaç ve rekor anahtarları
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.leaderboard_settings()
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $fn$
  SELECT jsonb_build_object(
    'enabled', public.leaderboard_flag('leaderboard_enabled', true),
    'period', CASE lower(public.leaderboard_setting('leaderboard_period'))
      WHEN 'week'  THEN 'week'
      WHEN 'month' THEN 'month'
      ELSE 'all'
    END,
    'limit', public.leaderboard_limit_value(),
    'order', to_jsonb(public.leaderboard_order()),
    'boards', (
      SELECT jsonb_object_agg(k, public.leaderboard_flag('leaderboard_board_' || k, true))
      FROM unnest(public.leaderboard_card_keys()) AS k
    ),
    'stats', (
      SELECT jsonb_object_agg(k, public.leaderboard_flag('leaderboard_stat_' || k, true))
      FROM unnest(ARRAY['members', 'guests', 'ghosts', 'orders', 'shops', 'products', 'posts',
                   'okey_matches', 'visitors_today', 'active_today', 'guests_today',
                   'online_now', 'new_today', 'posts_today', 'orders_today']
                  || public.leaderboard_personal_stat_keys()) AS k
    ),
    'records', (
      SELECT jsonb_object_agg(k, public.leaderboard_flag('leaderboard_record_' || k, true))
      FROM unnest(public.leaderboard_record_keys()) AS k
    )
  );
$fn$;

-- -----------------------------------------------------------------------------
-- 5) get_leaderboards — kişisel sayaçlar `stats`a, rekorlar `records`a
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_leaderboards()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $fn$
DECLARE
  v_settings jsonb := public.leaderboard_settings();
  v_boards   jsonb := '{}'::jsonb;
  v_stats    jsonb := '{}'::jsonb;
  v_records  jsonb := '{}'::jsonb;
  v_key      text;
  v_rows     jsonb;
BEGIN
  IF (SELECT auth.uid()) IS NULL OR NOT (v_settings ->> 'enabled')::boolean THEN
    RETURN jsonb_build_object(
      'settings', jsonb_set(v_settings, '{enabled}', 'false'::jsonb),
      'boards', v_boards, 'stats', v_stats, 'records', v_records);
  END IF;

  FOREACH v_key IN ARRAY public.leaderboard_card_keys() LOOP
    CONTINUE WHEN v_key IN ('stats', 'stats_today', 'my_stats', 'records');
    CONTINUE WHEN NOT COALESCE((v_settings -> 'boards' ->> v_key)::boolean, false);

    SELECT COALESCE(jsonb_agg(to_jsonb(r) ORDER BY r.r_rank), '[]'::jsonb)
      INTO v_rows
      FROM public.get_leaderboard(v_key) r;
    v_boards := v_boards || jsonb_build_object(v_key, v_rows);
  END LOOP;

  IF COALESCE((v_settings -> 'boards' ->> 'stats')::boolean, false)
     OR COALESCE((v_settings -> 'boards' ->> 'stats_today')::boolean, false) THEN
    v_stats := public.leaderboard_stats();
  END IF;
  IF COALESCE((v_settings -> 'boards' ->> 'my_stats')::boolean, false) THEN
    v_stats := v_stats || public.leaderboard_my_stats();
  END IF;
  IF COALESCE((v_settings -> 'boards' ->> 'records')::boolean, false) THEN
    v_records := public.leaderboard_records();
  END IF;

  RETURN jsonb_build_object('settings', v_settings, 'boards', v_boards, 'stats', v_stats, 'records', v_records);
END;
$fn$;

REVOKE ALL ON FUNCTION public.leaderboard_card_keys() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.leaderboard_personal_stat_keys() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.leaderboard_record_keys() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.leaderboard_my_stats() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.leaderboard_records() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.leaderboard_settings() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.leaderboard_settings() TO authenticated, service_role;
REVOKE ALL ON FUNCTION public.get_leaderboards() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_leaderboards() TO authenticated, service_role;

COMMIT;

NOTIFY pgrst, 'reload schema';
