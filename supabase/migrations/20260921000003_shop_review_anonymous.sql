-- Satıcı değerlendirmesinde kullanıcı kendini gizleyebilsin (ör. "n******b").
--
-- profiles ve shop_reviews herkese okunur olduğu için maskeleme istemcide
-- yapılamaz: yorumlar artık get_shop_reviews() RPC'siyle okunur; gizli yorumlarda
-- ad maskelenir, avatar / user_id / order_id hiç dönmez.

ALTER TABLE public.shop_reviews
  ADD COLUMN IF NOT EXISTS is_anonymous boolean NOT NULL DEFAULT false;

-- "Nezir Barkın" -> "N*********n"  (boşluklar atılır, ilk + son harf kalır)
CREATE OR REPLACE FUNCTION public.mask_display_name(p_name text)
RETURNS text
LANGUAGE sql
IMMUTABLE
SET search_path = public, pg_temp
AS $$
  SELECT CASE
    WHEN s.n = '' THEN 'Gizli Kullanıcı'
    WHEN char_length(s.n) = 1 THEN s.n || '***'
    ELSE left(s.n, 1)
         || repeat('*', least(greatest(char_length(s.n) - 2, 3), 10))
         || right(s.n, 1)
  END
  FROM (SELECT regexp_replace(coalesce(p_name, ''), '\s+', '', 'g') AS n) s
$$;

CREATE OR REPLACE FUNCTION public.get_shop_reviews(p_shop_id uuid)
RETURNS TABLE (
  id uuid,
  shop_id uuid,
  user_id uuid,
  rating integer,
  comment text,
  created_at timestamptz,
  updated_at timestamptz,
  seller_reply text,
  seller_replied_at timestamptz,
  order_id uuid,
  is_anonymous boolean,
  user_name text,
  user_avatar text
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT
    r.id,
    r.shop_id,
    CASE WHEN r.is_anonymous AND r.user_id IS DISTINCT FROM auth.uid()
         THEN NULL ELSE r.user_id END,
    r.rating,
    r.comment,
    r.created_at,
    r.updated_at,
    r.seller_reply,
    r.seller_replied_at,
    CASE WHEN r.is_anonymous THEN NULL ELSE r.order_id END,
    r.is_anonymous,
    CASE WHEN r.is_anonymous THEN public.mask_display_name(p.full_name)
         ELSE p.full_name END,
    CASE WHEN r.is_anonymous THEN NULL ELSE p.avatar_url END
  FROM public.shop_reviews r
  LEFT JOIN public.profiles p ON p.id = r.user_id
  WHERE r.shop_id = p_shop_id
  ORDER BY r.created_at DESC
$$;

REVOKE ALL ON FUNCTION public.get_shop_reviews(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_shop_reviews(uuid) TO anon, authenticated;

-- Satıcı, update politikası sayesinde yorum satırını güncelleyebiliyor; gizliliği
-- yalnızca yorumun sahibi değiştirebilsin.
CREATE OR REPLACE FUNCTION public.guard_shop_review_anonymity()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NEW.is_anonymous IS DISTINCT FROM OLD.is_anonymous
     AND auth.uid() IS NOT NULL
     AND auth.uid() IS DISTINCT FROM OLD.user_id THEN
    NEW.is_anonymous := OLD.is_anonymous;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS guard_shop_review_anonymity ON public.shop_reviews;
CREATE TRIGGER guard_shop_review_anonymity
  BEFORE UPDATE OF is_anonymous ON public.shop_reviews
  FOR EACH ROW EXECUTE FUNCTION public.guard_shop_review_anonymity();

-- Satıcıya giden "yeni yorum" bildirimi gizli yorumda kimliği açık etmesin
-- (ad maskeli, actor_id boş -> bildirim profil bağlantısı taşımaz).
CREATE OR REPLACE FUNCTION public.notify_seller_on_new_review()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_seller_id UUID;
    v_user_name TEXT;
BEGIN
    SELECT owner_id INTO v_seller_id FROM shops WHERE id = NEW.shop_id;

    SELECT full_name INTO v_user_name FROM profiles WHERE id = NEW.user_id;

    IF NEW.is_anonymous THEN
        v_user_name := public.mask_display_name(v_user_name);
    END IF;

    INSERT INTO notifications (
        user_id, type, title, content, entity_id, actor_id, created_at
    ) VALUES (
        v_seller_id,
        'shop_review',
        'Yeni Mağaza Yorumu',
        COALESCE(v_user_name, 'Bir kullanıcı') || ' mağazanıza ' || NEW.rating || ' yıldız verdi',
        NEW.id,
        CASE WHEN NEW.is_anonymous THEN NULL ELSE NEW.user_id END,
        NOW()
    );

    RETURN NEW;
END;
$$;
