-- ============================================================================
-- Paylaşım & Profil özellikleri — sunucu tarafı (2026-10-23)
-- ----------------------------------------------------------------------------
-- 1) post_shares + record_post_share(): gönderi dışarı/sohbete paylaşılınca
--    kişi başına bir kez kaydedilir, posts.shares_count bir artar. Sayaç
--    eskiden HİÇ artmıyordu. Tablo istemciye kapalı (yalnız RPC); sayaç
--    DEFINER yazdığı için a_posts_guard_client_write korumasına takılmaz.
-- 2) public_post_by_id(): paylaşılan /post/<id> linkini GİRİŞ YAPMAMIŞ biri
--    açınca salt-okunur önizleme. public_explore_feed ile aynı dönüş tipi ve
--    aynı misafir kuralları (explore_public_access anahtarı kapalıysa boş,
--    gizli/hayalet/silinmiş yazar kapalı).
-- 3) public_profile_by_username(): /u/@kullanici linki. Misafir profiles'ı
--    okuyamadığı için eskiden web'de "Bir hata oluştu" görünüyordu. Yalnız
--    zaten herkese açık yüzey (ad, kullanıcı adı, avatar, biyografi, rozet,
--    gizli mi) + sayılar; hayalet/silinmiş hesapta boş.
-- 4) get_mutual_followers(): "X, Y ve N kişi daha takip ediyor" — benim
--    takip ettiklerimden hedefi takip edenler. Engelli/hayalet/silinmiş
--    hariç; yalnız oturum açmış kullanıcı.
-- ============================================================================
BEGIN;

-- ------------------------------------------------------------ 1) paylaşımlar
CREATE TABLE IF NOT EXISTS public.post_shares (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  post_id uuid NOT NULL REFERENCES public.posts(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  channel text NOT NULL DEFAULT 'external'
    CHECK (channel IN ('external', 'chat', 'link')),
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT post_shares_post_user_key UNIQUE (post_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_post_shares_user_id ON public.post_shares (user_id);

ALTER TABLE public.post_shares ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.post_shares FROM anon, authenticated;

CREATE OR REPLACE FUNCTION public.record_post_share(
  p_post_id uuid,
  p_channel text DEFAULT 'external'
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $fn$
DECLARE
  v_uid uuid := auth.uid();
  v_author uuid;
  v_count integer;
  v_inserted integer;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Giriş gerekli' USING ERRCODE = '42501', HINT = 'AUTH_REQUIRED';
  END IF;

  SELECT p.user_id, COALESCE(p.shares_count, 0) INTO v_author, v_count
  FROM public.posts p
  WHERE p.id = p_post_id AND p.is_active = true;

  -- Görmediği gönderiyi paylaşamaz (gizli hesap / engel).
  IF NOT FOUND OR NOT public.can_view_social_author(v_author) THEN
    RETURN NULL;
  END IF;

  INSERT INTO public.post_shares (post_id, user_id, channel)
  VALUES (
    p_post_id,
    v_uid,
    CASE WHEN p_channel IN ('external', 'chat', 'link') THEN p_channel ELSE 'external' END
  )
  ON CONFLICT ON CONSTRAINT post_shares_post_user_key DO NOTHING;
  GET DIAGNOSTICS v_inserted = ROW_COUNT;

  -- Kişi başına bir kez sayılır (aynı kişinin tekrar paylaşımı sayacı şişirmez).
  IF v_inserted > 0 THEN
    UPDATE public.posts
       SET shares_count = COALESCE(shares_count, 0) + 1
     WHERE id = p_post_id
    RETURNING shares_count INTO v_count;
  END IF;

  RETURN v_count;
END;
$fn$;

REVOKE ALL ON FUNCTION public.record_post_share(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.record_post_share(uuid, text) TO authenticated, service_role;

-- -------------------------------------------- 2) misafir gönderi önizlemesi
DROP FUNCTION IF EXISTS public.public_post_by_id(uuid);

CREATE FUNCTION public.public_post_by_id(p_post_id uuid)
RETURNS TABLE (
  id uuid,
  user_id uuid,
  content text,
  images text[],
  image_aspect_ratio real,
  background text,
  music jsonb,
  location text,
  latitude numeric,
  longitude numeric,
  likes_count integer,
  comments_count integer,
  shares_count integer,
  is_active boolean,
  created_at timestamptz,
  updated_at timestamptz,
  image_url text,
  is_pinned boolean,
  admin_pinned boolean,
  username text,
  full_name text,
  avatar_url text,
  author_profile_exists boolean
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $fn$
DECLARE
  v_music boolean := public.music_flag('music_feature_enabled', true)
                 AND public.music_flag('music_attach_enabled', true);
BEGIN
  -- Keşfet misafire kapalıysa paylaşılan gönderi de kapalı (aynı kapı).
  IF NOT COALESCE(
       (SELECT NULLIF(btrim(s.value #>> '{}'), '')::boolean
          FROM public.app_settings s WHERE s.key = 'explore_public_access'),
       false
     ) THEN
    RETURN;
  END IF;

  RETURN QUERY
  SELECT
    po.id, po.user_id, po.content, po.images, po.image_aspect_ratio,
    po.background,
    CASE WHEN v_music THEN po.music ELSE NULL::jsonb END,
    po.location,
    po.latitude, po.longitude,
    COALESCE(po.likes_count, 0), COALESCE(po.comments_count, 0),
    COALESCE(po.shares_count, 0),
    COALESCE(po.is_active, true), po.created_at, po.updated_at,
    po.image_url, COALESCE(po.is_pinned, false), COALESCE(po.admin_pinned, false),
    pr.username, pr.full_name, pr.avatar_url,
    (pr.id IS NOT NULL)
  FROM public.posts po
  LEFT JOIN public.profiles pr ON pr.id = po.user_id
  WHERE po.id = p_post_id
    AND po.is_active = true
    AND COALESCE(pr.profile_is_public, true) = true
    AND COALESCE(pr.is_ghost_mode, false) = false
    AND COALESCE(pr.status, 'active'::public.user_status)
        <> 'deleted'::public.user_status;
END;
$fn$;

REVOKE ALL ON FUNCTION public.public_post_by_id(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.public_post_by_id(uuid) TO anon, authenticated, service_role;

-- ------------------------------------------- 3) kullanıcı adıyla profil kartı
CREATE OR REPLACE FUNCTION public.public_profile_by_username(p_username text)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $fn$
DECLARE
  v_row record;
  v_followers integer;
  v_following integer;
  v_posts integer;
BEGIN
  IF p_username IS NULL OR btrim(p_username) = '' THEN
    RETURN NULL;
  END IF;

  SELECT pr.id, pr.username, pr.full_name, pr.avatar_url, pr.bio,
         COALESCE(pr.is_verified, false) AS is_verified,
         COALESCE(pr.profile_is_public, true) AS profile_is_public
    INTO v_row
  FROM public.profiles pr
  WHERE lower(pr.username) = lower(btrim(ltrim(btrim(p_username), '@')))
    AND COALESCE(pr.is_ghost_mode, false) = false
    AND COALESCE(pr.status, 'active'::public.user_status)
        <> 'deleted'::public.user_status
  LIMIT 1;

  IF NOT FOUND THEN
    RETURN NULL;
  END IF;

  -- Engellediğim ya da beni engelleyen hesap (oturum açıkken) bulunamamış sayılır.
  IF auth.uid() IS NOT NULL AND public.social_block_exists(v_row.id) THEN
    RETURN NULL;
  END IF;

  SELECT count(*) INTO v_followers FROM public.follows WHERE following_id = v_row.id;
  SELECT count(*) INTO v_following FROM public.follows WHERE follower_id = v_row.id;
  SELECT count(*) INTO v_posts FROM public.posts WHERE user_id = v_row.id AND is_active = true;

  RETURN jsonb_build_object(
    'id', v_row.id,
    'username', v_row.username,
    'full_name', v_row.full_name,
    'avatar_url', v_row.avatar_url,
    'bio', v_row.bio,
    'is_verified', v_row.is_verified,
    'profile_is_public', v_row.profile_is_public,
    'followers', v_followers,
    'following', v_following,
    'posts', v_posts
  );
END;
$fn$;

REVOKE ALL ON FUNCTION public.public_profile_by_username(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.public_profile_by_username(text) TO anon, authenticated, service_role;

-- -------------------------------------------------------- 4) ortak takipçiler
CREATE OR REPLACE FUNCTION public.get_mutual_followers(
  p_target uuid,
  p_limit integer DEFAULT 3
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $fn$
DECLARE
  v_uid uuid := auth.uid();
  v_limit integer := LEAST(GREATEST(COALESCE(p_limit, 3), 1), 50);
  v_count integer;
  v_users jsonb;
BEGIN
  IF v_uid IS NULL OR p_target IS NULL OR p_target = v_uid THEN
    RETURN jsonb_build_object('count', 0, 'users', '[]'::jsonb);
  END IF;

  WITH mutual AS (
    SELECT pr.id, pr.username, pr.full_name, pr.avatar_url, mine.created_at
    FROM public.follows mine                       -- benim takip ettiklerim
    JOIN public.follows theirs                     -- ...hedefi takip edenler
      ON theirs.follower_id = mine.following_id
     AND theirs.following_id = p_target
    JOIN public.profiles pr ON pr.id = mine.following_id
    WHERE mine.follower_id = v_uid
      AND mine.following_id <> p_target
      AND COALESCE(pr.is_ghost_mode, false) = false
      AND COALESCE(pr.status, 'active'::public.user_status)
          <> 'deleted'::public.user_status
      AND NOT public.social_block_exists(pr.id)
  )
  SELECT
    (SELECT count(*) FROM mutual),
    COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
               'id', m.id,
               'username', m.username,
               'full_name', m.full_name,
               'avatar_url', m.avatar_url
             ) ORDER BY m.created_at DESC)
      FROM (SELECT * FROM mutual ORDER BY created_at DESC LIMIT v_limit) m
    ), '[]'::jsonb)
  INTO v_count, v_users;

  RETURN jsonb_build_object('count', v_count, 'users', v_users);
END;
$fn$;

REVOKE ALL ON FUNCTION public.get_mutual_followers(uuid, integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_mutual_followers(uuid, integer) TO authenticated, service_role;

COMMIT;

NOTIFY pgrst, 'reload schema';
