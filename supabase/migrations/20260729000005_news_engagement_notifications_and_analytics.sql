-- Haber etkileşim bildirimleri ve haberci paneli analitiği.
-- Bildirimler SECURITY DEFINER trigger ile oluşturulur; istemcinin başka kullanıcı
-- adına notifications satırı eklemesine gerek kalmaz.

-- Projede notification türleri farklı modüllerce genişletildiği için sabit enum
-- listesi yeni özellikleri kırıyor. Boş olmayan dinamik türlere izin ver.
ALTER TABLE public.notifications
  DROP CONSTRAINT IF EXISTS notifications_type_check;
ALTER TABLE public.notifications
  ADD CONSTRAINT notifications_type_check
  CHECK (type IS NOT NULL AND BTRIM(type) <> '');

CREATE OR REPLACE FUNCTION public.notify_news_like()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_author_id UUID;
  v_news_title TEXT;
  v_actor_name TEXT;
  v_actor_avatar TEXT;
BEGIN
  SELECT n.author_id, n.title
    INTO v_author_id, v_news_title
  FROM public.news n
  WHERE n.id = NEW.news_id;

  IF v_author_id IS NULL OR v_author_id = NEW.user_id THEN
    RETURN NEW;
  END IF;

  SELECT COALESCE(NULLIF(p.full_name, ''), 'Bir kullanıcı'), p.avatar_url
    INTO v_actor_name, v_actor_avatar
  FROM public.profiles p
  WHERE p.id = NEW.user_id;

  INSERT INTO public.notifications (
    user_id, type, title, content, actor_id, actor_name, actor_avatar,
    entity_id, entity_type, is_read, metadata
  ) VALUES (
    v_author_id,
    'news_like',
    'Haberiniz beğenildi',
    COALESCE(v_actor_name, 'Bir kullanıcı') || ' “' || LEFT(v_news_title, 80) || '” haberinizi beğendi.',
    NEW.user_id,
    COALESCE(v_actor_name, 'Bir kullanıcı'),
    v_actor_avatar,
    NEW.news_id::TEXT,
    'news',
    FALSE,
    jsonb_build_object('news_id', NEW.news_id, 'like_id', NEW.id)
  );

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS notify_news_like_trigger ON public.news_likes;
CREATE TRIGGER notify_news_like_trigger
AFTER INSERT ON public.news_likes
FOR EACH ROW EXECUTE FUNCTION public.notify_news_like();

CREATE OR REPLACE FUNCTION public.notify_news_comment()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_recipient_id UUID;
  v_news_title TEXT;
  v_actor_name TEXT;
  v_actor_avatar TEXT;
  v_notification_type TEXT;
  v_title TEXT;
BEGIN
  SELECT n.title,
         CASE
           WHEN NEW.parent_id IS NULL THEN n.author_id
           ELSE parent_comment.user_id
         END
    INTO v_news_title, v_recipient_id
  FROM public.news n
  LEFT JOIN public.news_comments parent_comment ON parent_comment.id = NEW.parent_id
  WHERE n.id = NEW.news_id;

  IF v_recipient_id IS NULL OR v_recipient_id = NEW.user_id THEN
    RETURN NEW;
  END IF;

  SELECT COALESCE(NULLIF(p.full_name, ''), NEW.user_name, 'Bir kullanıcı'), p.avatar_url
    INTO v_actor_name, v_actor_avatar
  FROM public.profiles p
  WHERE p.id = NEW.user_id;

  v_actor_name := COALESCE(v_actor_name, NULLIF(NEW.user_name, ''), 'Bir kullanıcı');
  v_notification_type := CASE WHEN NEW.parent_id IS NULL THEN 'news_comment' ELSE 'news_comment_reply' END;
  v_title := CASE WHEN NEW.parent_id IS NULL THEN 'Haberinize yorum yapıldı' ELSE 'Yorumunuza yanıt geldi' END;

  INSERT INTO public.notifications (
    user_id, type, title, content, actor_id, actor_name, actor_avatar,
    entity_id, entity_type, is_read, metadata
  ) VALUES (
    v_recipient_id,
    v_notification_type,
    v_title,
    v_actor_name || CASE WHEN NEW.parent_id IS NULL THEN ' haberinize yorum yaptı: ' ELSE ' yorumunuza yanıt verdi: ' END ||
      '“' || LEFT(NEW.content, 120) || '”',
    NEW.user_id,
    v_actor_name,
    v_actor_avatar,
    NEW.news_id::TEXT,
    'news',
    FALSE,
    jsonb_build_object(
      'news_id', NEW.news_id,
      'news_title', v_news_title,
      'comment_id', NEW.id,
      'parent_comment_id', NEW.parent_id
    )
  );

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS notify_news_comment_trigger ON public.news_comments;
CREATE TRIGGER notify_news_comment_trigger
AFTER INSERT ON public.news_comments
FOR EACH ROW EXECUTE FUNCTION public.notify_news_comment();

CREATE OR REPLACE FUNCTION public.notify_news_comment_like()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_recipient_id UUID;
  v_news_id UUID;
  v_comment_content TEXT;
  v_actor_name TEXT;
  v_actor_avatar TEXT;
BEGIN
  SELECT c.user_id, c.news_id, c.content
    INTO v_recipient_id, v_news_id, v_comment_content
  FROM public.news_comments c
  WHERE c.id = NEW.comment_id;

  IF v_recipient_id IS NULL OR v_recipient_id = NEW.user_id THEN
    RETURN NEW;
  END IF;

  SELECT COALESCE(NULLIF(p.full_name, ''), 'Bir kullanıcı'), p.avatar_url
    INTO v_actor_name, v_actor_avatar
  FROM public.profiles p
  WHERE p.id = NEW.user_id;

  INSERT INTO public.notifications (
    user_id, type, title, content, actor_id, actor_name, actor_avatar,
    entity_id, entity_type, is_read, metadata
  ) VALUES (
    v_recipient_id,
    'news_comment_like',
    'Yorumunuz beğenildi',
    COALESCE(v_actor_name, 'Bir kullanıcı') || ' yorumunuzu beğendi: “' || LEFT(v_comment_content, 120) || '”',
    NEW.user_id,
    COALESCE(v_actor_name, 'Bir kullanıcı'),
    v_actor_avatar,
    v_news_id::TEXT,
    'news',
    FALSE,
    jsonb_build_object('news_id', v_news_id, 'comment_id', NEW.comment_id, 'comment_like_id', NEW.id)
  );

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS notify_news_comment_like_trigger ON public.news_comment_likes;
CREATE TRIGGER notify_news_comment_like_trigger
AFTER INSERT ON public.news_comment_likes
FOR EACH ROW EXECUTE FUNCTION public.notify_news_comment_like();

-- Haber yazarı/admin dışında kişisel etkileşim detaylarını açmaz.
CREATE OR REPLACE FUNCTION public.get_news_engagement_details(p_news_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_caller_id UUID := auth.uid();
  v_author_id UUID;
  v_result JSONB;
BEGIN
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Oturum açmanız gerekli';
  END IF;

  SELECT n.author_id INTO v_author_id
  FROM public.news n
  WHERE n.id = p_news_id;

  IF v_author_id IS NULL THEN
    RAISE EXCEPTION 'Haber bulunamadı';
  END IF;

  IF v_author_id <> v_caller_id
     AND NOT EXISTS (
       SELECT 1 FROM public.profiles p
       WHERE p.id = v_caller_id AND p.role = 'admin'
     ) THEN
    RAISE EXCEPTION 'Bu haber için etkileşim detaylarını görme yetkiniz yok';
  END IF;

  SELECT jsonb_build_object(
    'viewers', COALESCE((
      SELECT jsonb_agg(to_jsonb(v) ORDER BY v.last_viewed_at DESC)
      FROM (
        SELECT
          nv.user_id,
          COALESCE(NULLIF(p.full_name, ''), CASE WHEN nv.user_id IS NULL THEN 'Anonim ziyaretçi' ELSE 'Kullanıcı' END) AS user_name,
          p.avatar_url,
          COUNT(*)::INTEGER AS interaction_count,
          MAX(nv.created_at) AS last_viewed_at
        FROM public.news_views nv
        LEFT JOIN public.profiles p ON p.id = nv.user_id
        WHERE nv.news_id = p_news_id
        GROUP BY nv.user_id, p.full_name, p.avatar_url
      ) v
    ), '[]'::jsonb),
    'likes', COALESCE((
      SELECT jsonb_agg(to_jsonb(l) ORDER BY l.created_at DESC)
      FROM (
        SELECT nl.user_id,
               COALESCE(NULLIF(p.full_name, ''), 'Kullanıcı') AS user_name,
               p.avatar_url,
               nl.created_at
        FROM public.news_likes nl
        LEFT JOIN public.profiles p ON p.id = nl.user_id
        WHERE nl.news_id = p_news_id
      ) l
    ), '[]'::jsonb),
    'comments', COALESCE((
      SELECT jsonb_agg(to_jsonb(c) ORDER BY c.created_at DESC)
      FROM (
        SELECT nc.id, nc.user_id, nc.user_name, nc.user_avatar_url AS avatar_url,
               nc.content, nc.parent_id, nc.like_count, nc.created_at
        FROM public.news_comments nc
        WHERE nc.news_id = p_news_id AND nc.is_hidden = FALSE
      ) c
    ), '[]'::jsonb)
  ) INTO v_result;

  RETURN v_result;
END;
$$;

REVOKE ALL ON FUNCTION public.get_news_engagement_details(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_news_engagement_details(UUID) TO authenticated;

COMMENT ON FUNCTION public.get_news_engagement_details(UUID) IS
  'Haber yazarı veya admin için görüntüleyen, beğenen ve yorum yapan kullanıcı detaylarını döndürür.';
