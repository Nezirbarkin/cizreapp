-- ============================================================================
-- Sosyal bütünlük düzeltmeleri (2026-10-23)
-- ----------------------------------------------------------------------------
-- Canlı denetimde (politika + tetikleyici okuması) bulunan açıklar:
--
-- 1) posts / stories: UPDATE/INSERT politikaları yalnız sahipliğe bakıyor ve
--    sütun koruması yoktu. Sahip kendi gönderisinde admin_pinned = true
--    yazarak herkesin akışının en tepesine çıkabiliyor (akış önce
--    admin_pinned'e göre sıralanır), likes/comments/shares sayılarını
--    şişirebiliyordu. Hikâyede is_pinned/admin_pinned şeridin başına
--    taşıyor, expires_at yıllar sonrasına yazılabiliyordu. Ayrıca istemci
--    created_at/expires_at'i cihaz saatinden yolluyordu: saati yanlış
--    telefonda hikâye başkaları için daha baştan "süresi dolmuş" oluyordu.
--    → INVOKER koruma tetikleyicileri (20261017000001 kalıbı): istemci
--      (authenticated/anon) ve admin değilse bu sütunlar sessizce eski
--      değere (INSERT'te varsayılana) döner. Sayaç tetikleyicileri
--      SECURITY DEFINER olduğundan current_user sahip olur, etkilenmez.
--
-- 2) blocked_users: tetikleyici yoktu. Engellenen kişi takipçi listesinde
--    ve sayısında kalıyor, engel kalkınca takip sessizce geri geliyordu
--    (gizli hesapta erişim de geri geliyordu); bekleyen istekler duruyordu.
--    → engelde iki yönde follows + follow_requests silinir.
--
-- 3) post_likes SELECT USING (true): gizli hesabın gönderisini kimin
--    beğendiği herkese okunuyordu. post_likes / post_comments INSERT yalnız
--    user_id'ye bakıyordu: engellenen ya da gizli hesabı görmeyen biri
--    gönderi kimliğiyle beğeni/yorum ekleyip bildirim üretebiliyordu.
--    Engellenen kişinin yorumları gönderi altında görünmeye devam ediyordu.
--    → beğeni/yorum, gönderi çağırana görünüyorsa okunur/eklenir (posts
--      RLS'i can_view_social_author ile engeli ve gizli hesabı zaten süzer);
--      yorum SELECT'i ayrıca yorum yazarıyla engeli süzer.
--
-- 4) Bildirim tekrarı: dedup_notification aynı (alıcı, gönderi, tip) için
--    eski satırı silip yenisini yazar; beğen-geri al-beğen döngüsü her
--    seferinde yeniden okunmamış bildirim + push üretiyordu. Gönderi
--    sahibinin yorumuna yanıt hem post_comment hem comment_reply veriyordu.
--    → aynı kişinin aynı gönderiyi 24 saat içinde yeniden beğenmesi
--      bildirim üretmez; üst yorum gönderi sahibininse post_comment atlanır.
--
-- 5) posts_with_profiles: author_is_verified NULL sabitti → doğrulanmış rozeti
--    akışta hiç görünmüyordu. is_verified herkese açık bir rozettir; anon da
--    görünümü okuduğu için anon'a yalnız bu sütunun SELECT hakkı verilir.
--    Görünüm tanımı canlıdan (pg_get_viewdef) birebir alındı.
-- ============================================================================
BEGIN;

-- ---------------------------------------------------------------- 1) posts
CREATE OR REPLACE FUNCTION public.guard_posts_client_write()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $fn$
BEGIN
  -- INVOKER: DEFINER sayaç tetikleyicilerinde current_user sahip olur.
  IF current_user NOT IN ('authenticated', 'anon') OR public.social_is_admin() THEN
    RETURN NEW;
  END IF;

  IF TG_OP = 'INSERT' THEN
    NEW.admin_pinned   := false;
    NEW.likes_count    := 0;
    NEW.comments_count := 0;
    NEW.shares_count   := 0;
    NEW.created_at     := now();
  ELSE
    NEW.admin_pinned   := OLD.admin_pinned;
    NEW.likes_count    := OLD.likes_count;
    NEW.comments_count := OLD.comments_count;
    NEW.shares_count   := OLD.shares_count;
    NEW.created_at     := OLD.created_at;
  END IF;

  RETURN NEW;
END;
$fn$;

DROP TRIGGER IF EXISTS a_posts_guard_client_write ON public.posts;
CREATE TRIGGER a_posts_guard_client_write
  BEFORE INSERT OR UPDATE ON public.posts
  FOR EACH ROW EXECUTE FUNCTION public.guard_posts_client_write();

-- -------------------------------------------------------------- 1) stories
CREATE OR REPLACE FUNCTION public.guard_stories_client_write()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $fn$
BEGIN
  IF current_user NOT IN ('authenticated', 'anon') OR public.social_is_admin() THEN
    RETURN NEW;
  END IF;

  IF TG_OP = 'INSERT' THEN
    NEW.admin_pinned := false;
    NEW.is_pinned    := false;
    NEW.views_count  := 0;
    NEW.likes_count  := 0;
    NEW.created_at   := now();
    NEW.expires_at   := now() + interval '24 hours';
  ELSE
    NEW.admin_pinned := OLD.admin_pinned;
    NEW.is_pinned    := OLD.is_pinned;
    NEW.views_count  := OLD.views_count;
    NEW.likes_count  := OLD.likes_count;
    NEW.created_at   := OLD.created_at;
    NEW.expires_at   := OLD.expires_at;
  END IF;

  RETURN NEW;
END;
$fn$;

DROP TRIGGER IF EXISTS a_stories_guard_client_write ON public.stories;
CREATE TRIGGER a_stories_guard_client_write
  BEFORE INSERT OR UPDATE ON public.stories
  FOR EACH ROW EXECUTE FUNCTION public.guard_stories_client_write();

-- ------------------------------------------------- 2) engelde takip temizliği
CREATE OR REPLACE FUNCTION public.social_cleanup_follows_on_block()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $fn$
BEGIN
  DELETE FROM public.follows
  WHERE (follower_id = NEW.blocker_id AND following_id = NEW.blocked_id)
     OR (follower_id = NEW.blocked_id AND following_id = NEW.blocker_id);

  DELETE FROM public.follow_requests
  WHERE (follower_id = NEW.blocker_id AND following_id = NEW.blocked_id)
     OR (follower_id = NEW.blocked_id AND following_id = NEW.blocker_id);

  RETURN NULL;
END;
$fn$;

REVOKE ALL ON FUNCTION public.social_cleanup_follows_on_block() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS social_cleanup_follows_on_block ON public.blocked_users;
CREATE TRIGGER social_cleanup_follows_on_block
  AFTER INSERT ON public.blocked_users
  FOR EACH ROW EXECUTE FUNCTION public.social_cleanup_follows_on_block();

-- --------------------------------------------------- 3) beğeni / yorum RLS'i
DROP POLICY IF EXISTS "Post likes are viewable by everyone" ON public.post_likes;
DROP POLICY IF EXISTS post_likes_select_visible ON public.post_likes;
CREATE POLICY post_likes_select_visible ON public.post_likes
  FOR SELECT TO public
  USING (EXISTS (SELECT 1 FROM public.posts p WHERE p.id = post_likes.post_id));

DROP POLICY IF EXISTS post_likes_insert_own ON public.post_likes;
CREATE POLICY post_likes_insert_own ON public.post_likes
  FOR INSERT TO authenticated
  WITH CHECK (
    user_id = (SELECT auth.uid())
    AND EXISTS (SELECT 1 FROM public.posts p WHERE p.id = post_likes.post_id)
  );

DROP POLICY IF EXISTS post_comments_insert_own ON public.post_comments;
CREATE POLICY post_comments_insert_own ON public.post_comments
  FOR INSERT TO authenticated
  WITH CHECK (
    user_id = (SELECT auth.uid())
    AND (
      post_id IS NULL
      OR EXISTS (SELECT 1 FROM public.posts p WHERE p.id = post_comments.post_id)
    )
  );

DROP POLICY IF EXISTS post_comments_select_visible ON public.post_comments;
CREATE POLICY post_comments_select_visible ON public.post_comments
  FOR SELECT TO public
  USING (
    (
      post_id IS NULL
      OR EXISTS (SELECT 1 FROM public.posts p WHERE p.id = post_comments.post_id)
    )
    AND (
      user_id IS NULL
      OR user_id = (SELECT auth.uid())
      OR NOT public.social_block_exists(user_id)
    )
  );

-- ------------------------------------------------------- 4) bildirim tekrarı
CREATE OR REPLACE FUNCTION public.notify_post_like()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
    post_owner_id UUID;
    liker_info JSONB;
BEGIN
    SELECT user_id INTO post_owner_id
    FROM public.posts WHERE id = NEW.post_id;

    IF post_owner_id IS NULL OR post_owner_id = NEW.user_id THEN
        RETURN NEW;
    END IF;

    -- Gönderi sahibi bir bot ise bildirim üretme.
    IF EXISTS (
        SELECT 1 FROM public.profiles p
        WHERE p.id = post_owner_id AND p.is_bot = true
    ) THEN
        RETURN NEW;
    END IF;

    -- Beğen → geri al → beğen döngüsü: aynı kişi aynı gönderiyi son 24 saatte
    -- zaten beğendiyse (bildirimi duruyorsa) yeni bildirim + push üretme.
    IF EXISTS (
        SELECT 1 FROM public.notifications n
        WHERE n.user_id = post_owner_id
          AND n.entity_id = NEW.post_id::text
          AND n.type = 'post_like'
          AND n.actor_id = NEW.user_id
          AND n.created_at > now() - interval '24 hours'
    ) THEN
        RETURN NEW;
    END IF;

    SELECT jsonb_build_object(
        'id', p.id, 'username', p.username,
        'full_name', COALESCE(p.full_name, p.username),
        'avatar_url', p.avatar_url
    ) INTO liker_info
    FROM public.profiles p WHERE p.id = NEW.user_id;

    INSERT INTO public.notifications (
        user_id, type, title, content, actor_id, actor_name, actor_avatar,
        entity_id, is_read, created_at
    ) VALUES (
        post_owner_id, 'post_like',
        (liker_info->>'full_name') || ' senin gönderini beğendi',
        'Beğeni', NEW.user_id,
        liker_info->>'full_name', liker_info->>'avatar_url',
        NEW.post_id, false, NOW()
    );

    RETURN NEW;
END;
$function$;

CREATE OR REPLACE FUNCTION public.notify_post_comment()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
    post_owner_id UUID;
    commenter_info JSONB;
BEGIN
    SELECT user_id INTO post_owner_id
    FROM public.posts WHERE id = NEW.post_id;

    IF post_owner_id IS NULL OR post_owner_id = NEW.user_id THEN
        RETURN NEW;
    END IF;

    -- Görev 4.7: alıcı bot ise bildirim yok (bot-bot yorumları tabloyu şişirmesin).
    IF EXISTS (SELECT 1 FROM public.profiles WHERE id = post_owner_id AND COALESCE(is_bot, false)) THEN
        RETURN NEW;
    END IF;

    -- Gönderi sahibinin kendi yorumuna gelen yanıt: notify_comment_reply
    -- zaten "yorumuna yanıt verdi" bildirimi yolluyor; ikincisini üretme.
    IF NEW.parent_comment_id IS NOT NULL AND EXISTS (
        SELECT 1 FROM public.post_comments parent
        WHERE parent.id = NEW.parent_comment_id
          AND parent.user_id = post_owner_id
    ) THEN
        RETURN NEW;
    END IF;

    SELECT jsonb_build_object(
        'id', p.id, 'username', p.username,
        'full_name', COALESCE(p.full_name, p.username),
        'avatar_url', p.avatar_url
    ) INTO commenter_info
    FROM public.profiles p WHERE p.id = NEW.user_id;

    INSERT INTO public.notifications (
        user_id, type, title, content, actor_id, actor_name, actor_avatar,
        entity_id, is_read, created_at
    ) VALUES (
        post_owner_id, 'post_comment',
        (commenter_info->>'full_name') || ' gönderine yorum yaptı',
        SUBSTRING(NEW.content FROM 1 FOR 100), NEW.user_id,
        commenter_info->>'full_name', commenter_info->>'avatar_url',
        NEW.post_id, false, NOW()
    );

    RETURN NEW;
END;
$function$;

-- ------------------------------------------- 5) doğrulanmış rozeti görünümde
GRANT SELECT (is_verified) ON public.profiles TO anon;

CREATE OR REPLACE VIEW public.posts_with_profiles
WITH (security_invoker = true) AS
 SELECT p.id,
    p.user_id,
    p.content,
    p.images,
    p.location,
    p.latitude,
    p.longitude,
    p.likes_count,
    p.comments_count,
    p.shares_count,
    p.is_active,
    p.created_at,
    p.updated_at,
    p.image_url,
    p.is_pinned,
    p.admin_pinned,
    p.background,
    p.music,
    p.image_aspect_ratio,
    pr.username,
    pr.full_name,
    pr.avatar_url,
    pr.is_ghost_mode AS author_is_ghost_mode,
    pr.profile_is_public AS author_profile_public,
    pr.status AS author_status,
    pr.is_verified AS author_is_verified,
    NULL::text AS author_role,
    NULL::boolean AS author_is_admin,
    pr.id IS NOT NULL AS author_profile_exists
   FROM posts p
     LEFT JOIN profiles pr ON pr.id = p.user_id
  WHERE p.is_active = true;

COMMIT;

NOTIFY pgrst, 'reload schema';
