-- Satıcı duyuru kartları: admin yazar, satıcının panelindeki "Genel Bakış"
-- sekmesinin en üstünde görünür.
--
-- Tasarım kararları:
--   * Satıcılar tabloyu DOĞRUDAN okumaz. Hedef kitle (tüm satıcılar / kuryesi
--     olan-olmayan / seçili mağazalar) ve "kapattı" bilgisi sunucuda
--     süzülür; istemciye sadece kendine ait kartlar RPC ile gelir.
--   * "Görüldü" ve "kapattı" kullanıcı (mağaza sahibi) bazında tutulur, yani
--     satıcı kartı bir cihazda kapatınca başka cihazda da kapalı kalır.
--   * Acil (urgent) kartlar kapatılamaz; bu, CHECK ile de zorlanır.
--   * Admin yazma işlemleri RLS (auth_is_admin) ile, istatistikli liste RPC ile.

-- ---------------------------------------------------------------------------
-- Tablolar
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.seller_announcements (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  type TEXT NOT NULL DEFAULT 'info'
    CHECK (type IN ('urgent', 'warn', 'promo', 'info', 'ok')),
  title TEXT NOT NULL CHECK (char_length(btrim(title)) BETWEEN 1 AND 80),
  message TEXT NOT NULL CHECK (char_length(btrim(message)) BETWEEN 1 AND 300),
  -- Eylem butonu (isteğe bağlı): etiket + hedef ekran.
  action_label TEXT CHECK (action_label IS NULL OR char_length(btrim(action_label)) BETWEEN 1 AND 30),
  action_target TEXT
    CHECK (action_target IS NULL OR action_target IN
      ('products', 'orders', 'payments', 'coupons', 'reviews', 'shop_settings', 'url')),
  action_url TEXT,
  audience TEXT NOT NULL DEFAULT 'all'
    CHECK (audience IN ('all', 'no_courier', 'own_courier', 'shops')),
  shop_ids UUID[] NOT NULL DEFAULT '{}',
  is_dismissible BOOLEAN NOT NULL DEFAULT true,
  is_pinned BOOLEAN NOT NULL DEFAULT false,
  -- false = taslak. Yayın penceresi starts_at/ends_at ile belirlenir.
  is_published BOOLEAN NOT NULL DEFAULT false,
  starts_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  ends_at TIMESTAMPTZ,
  created_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT seller_announcements_action_pair
    CHECK ((action_label IS NULL) = (action_target IS NULL)),
  CONSTRAINT seller_announcements_url_https
    CHECK (action_target IS DISTINCT FROM 'url'
           OR (action_url IS NOT NULL AND action_url ~* '^https://[^[:space:]]+$')),
  CONSTRAINT seller_announcements_shops_audience
    CHECK (audience <> 'shops' OR cardinality(shop_ids) > 0),
  CONSTRAINT seller_announcements_window
    CHECK (ends_at IS NULL OR ends_at > starts_at),
  CONSTRAINT seller_announcements_urgent_not_dismissible
    CHECK (type <> 'urgent' OR NOT is_dismissible)
);

CREATE INDEX IF NOT EXISTS idx_seller_announcements_live
  ON public.seller_announcements (is_published, starts_at, ends_at);

CREATE TABLE IF NOT EXISTS public.seller_announcement_receipts (
  announcement_id UUID NOT NULL
    REFERENCES public.seller_announcements(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  first_seen_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  dismissed_at TIMESTAMPTZ,
  PRIMARY KEY (announcement_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_seller_announcement_receipts_user
  ON public.seller_announcement_receipts (user_id);

CREATE OR REPLACE FUNCTION public.seller_announcements_touch()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_seller_announcements_touch ON public.seller_announcements;
CREATE TRIGGER trg_seller_announcements_touch
  BEFORE UPDATE ON public.seller_announcements
  FOR EACH ROW EXECUTE FUNCTION public.seller_announcements_touch();

-- ---------------------------------------------------------------------------
-- RLS: duyuru tablosu sadece admin; makbuz tablosu hiç istemciye açık değil
-- ---------------------------------------------------------------------------

ALTER TABLE public.seller_announcements ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.seller_announcement_receipts ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "seller_announcements_admin_all" ON public.seller_announcements;
CREATE POLICY "seller_announcements_admin_all"
ON public.seller_announcements FOR ALL
TO authenticated
USING (public.auth_is_admin())
WITH CHECK (public.auth_is_admin());

REVOKE ALL ON public.seller_announcements FROM anon;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.seller_announcements TO authenticated;

REVOKE ALL ON public.seller_announcement_receipts FROM anon, authenticated;

-- ---------------------------------------------------------------------------
-- Satıcı tarafı RPC'leri
-- ---------------------------------------------------------------------------

-- Çağıran satıcıya gösterilecek kartlar: yayında, pencere içinde, hedef
-- kitleye uyan ve kapatılmamış olanlar. Sıra: acil, sabitlenen, en yeni.
CREATE OR REPLACE FUNCTION public.get_my_seller_announcements()
RETURNS TABLE (
  id UUID,
  type TEXT,
  title TEXT,
  message TEXT,
  action_label TEXT,
  action_target TEXT,
  action_url TEXT,
  is_dismissible BOOLEAN,
  is_pinned BOOLEAN,
  is_new BOOLEAN,
  created_at TIMESTAMPTZ
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT a.id, a.type, a.title, a.message, a.action_label, a.action_target,
         a.action_url, a.is_dismissible, a.is_pinned,
         NOT EXISTS (
           SELECT 1 FROM public.seller_announcement_receipts r
           WHERE r.announcement_id = a.id AND r.user_id = auth.uid()
         ) AS is_new,
         a.created_at
  FROM public.seller_announcements a
  WHERE auth.uid() IS NOT NULL
    AND a.is_published
    AND a.starts_at <= now()
    AND (a.ends_at IS NULL OR a.ends_at > now())
    AND EXISTS (
      SELECT 1 FROM public.shops s
      WHERE s.owner_id = auth.uid()
        AND (
          a.audience = 'all'
          OR (a.audience = 'no_courier' AND NOT COALESCE(s.has_own_courier, false))
          OR (a.audience = 'own_courier' AND COALESCE(s.has_own_courier, false))
          OR (a.audience = 'shops' AND s.id = ANY (a.shop_ids))
        )
    )
    AND NOT EXISTS (
      SELECT 1 FROM public.seller_announcement_receipts r
      WHERE r.announcement_id = a.id
        AND r.user_id = auth.uid()
        AND r.dismissed_at IS NOT NULL
    )
  ORDER BY (a.type = 'urgent') DESC, a.is_pinned DESC, a.created_at DESC;
$$;

-- İstemci kartları çizdikten sonra "görüldü" işaretler (yeni noktası söner,
-- admin görüntüleme sayısı artar). Sadece kullanıcının zaten görebildiği
-- kartlar için kayıt açılır.
CREATE OR REPLACE FUNCTION public.mark_seller_announcements_seen(p_ids UUID[])
RETURNS VOID
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  INSERT INTO public.seller_announcement_receipts (announcement_id, user_id)
  SELECT m.id, auth.uid()
  FROM public.get_my_seller_announcements() m
  WHERE auth.uid() IS NOT NULL
    AND m.id = ANY (p_ids)
  ON CONFLICT (announcement_id, user_id) DO NOTHING;
$$;

CREATE OR REPLACE FUNCTION public.dismiss_seller_announcement(p_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_dismissible BOOLEAN;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Oturum gerekli' USING ERRCODE = '42501';
  END IF;

  SELECT m.is_dismissible INTO v_dismissible
  FROM public.get_my_seller_announcements() m
  WHERE m.id = p_id;

  IF v_dismissible IS NULL THEN
    RAISE EXCEPTION 'Duyuru bulunamadı' USING ERRCODE = 'P0002';
  END IF;
  IF NOT v_dismissible THEN
    RAISE EXCEPTION 'Bu duyuru kapatılamaz' USING ERRCODE = '42501';
  END IF;

  INSERT INTO public.seller_announcement_receipts (announcement_id, user_id, dismissed_at)
  VALUES (p_id, v_uid, now())
  ON CONFLICT (announcement_id, user_id)
  DO UPDATE SET dismissed_at = COALESCE(seller_announcement_receipts.dismissed_at, now());
END;
$$;

-- ---------------------------------------------------------------------------
-- Admin tarafı: istatistikli liste
-- ---------------------------------------------------------------------------

-- Tüm duyurular + görüntüleme/kapatma sayısı + hedef kitlenin büyüklüğü.
-- Hedef sayısı bot vitrin mağazalarını saymaz.
CREATE OR REPLACE FUNCTION public.admin_list_seller_announcements()
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.auth_is_admin() THEN
    RAISE EXCEPTION 'Yetkisiz' USING ERRCODE = '42501';
  END IF;

  RETURN COALESCE((
    SELECT jsonb_agg(
      to_jsonb(a) || jsonb_build_object(
        'seen_count', (
          SELECT count(*) FROM public.seller_announcement_receipts r
          WHERE r.announcement_id = a.id
        ),
        'dismissed_count', (
          SELECT count(*) FROM public.seller_announcement_receipts r
          WHERE r.announcement_id = a.id AND r.dismissed_at IS NOT NULL
        ),
        'target_count', (
          SELECT count(*)
          FROM public.shops s
          JOIN public.profiles p ON p.id = s.owner_id
          WHERE NOT COALESCE(p.is_bot, false)
            AND (
              a.audience = 'all'
              OR (a.audience = 'no_courier' AND NOT COALESCE(s.has_own_courier, false))
              OR (a.audience = 'own_courier' AND COALESCE(s.has_own_courier, false))
              OR (a.audience = 'shops' AND s.id = ANY (a.shop_ids))
            )
        )
      )
      ORDER BY a.created_at DESC
    )
    FROM public.seller_announcements a
  ), '[]'::jsonb);
END;
$$;

-- ---------------------------------------------------------------------------
-- Yetkiler: sadece giriş yapmış kullanıcılar çağırabilir
-- ---------------------------------------------------------------------------

REVOKE ALL ON FUNCTION public.get_my_seller_announcements() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.mark_seller_announcements_seen(UUID[]) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.dismiss_seller_announcement(UUID) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.admin_list_seller_announcements() FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION public.get_my_seller_announcements() TO authenticated;
GRANT EXECUTE ON FUNCTION public.mark_seller_announcements_seen(UUID[]) TO authenticated;
GRANT EXECUTE ON FUNCTION public.dismiss_seller_announcement(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_list_seller_announcements() TO authenticated;

COMMENT ON TABLE public.seller_announcements IS
  'Admin''in satıcı panelinin Genel Bakış sekmesine koyduğu duyuru kartları. Satıcılar yalnızca get_my_seller_announcements() ile okur.';
