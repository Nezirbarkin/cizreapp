-- =============================================================================
-- Kullanıcı eylem günlüğü (Admin > Loglar > Kullanıcı Eylemleri)
--
-- Amaç: kullanıcının uygulamadaki eylemlerini (gönderi, yorum, beğeni, takip,
-- sipariş, mesaj, giriş, müzik, günün fırsatı tıklaması...) tek bir yerde
-- toplamak ve adminin filtreleyip SİLEBİLMESİ.
--
-- İki kaynaktan beslenir:
--   1) SUNUCU TETİKLEYİCİLERİ — kritik tablolara bağlı, istemciden bağımsız ve
--      taklit edilemez. Tetikleyici hiçbir koşulda asıl işlemi bozmaz (tüm gövde
--      EXCEPTION ile sarılı).
--   2) log_user_action RPC'si — tablosu olmayan eylemler için (giriş/çıkış,
--      ürün/dükkan görüntüleme, müzik...). İzinli eylem listesi vardır; istemci
--      keyfi bir eylem adı yazamaz.
--
-- Bot hesapları (profiles.is_bot) günlüğe YAZILMAZ: cron ile yüzlerce sahte
-- eylem üretiyorlar ve gerçek kullanıcı davranışını boğarlar.
--
-- Tabloya istemci doğrudan erişemez (RLS açık, politika yok, GRANT yok);
-- okuma/silme yalnızca admin RPC'leri üzerinden.
-- =============================================================================

BEGIN;

-- -----------------------------------------------------------------------------
-- 1) Tablo
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.user_activity_logs (
  id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  -- Bilerek FK YOK: profil silinirken (kaskad) tetikleyicilerin yazdığı satır
  -- FK ihlaliyle düşmesin. Silinen kullanıcının satırlarını admin_delete_user
  -- kendisi temizler.
  user_id     uuid,
  action      text NOT NULL,
  category    text NOT NULL DEFAULT 'app',
  entity_type text,
  entity_id   text,
  summary     text,
  metadata    jsonb NOT NULL DEFAULT '{}'::jsonb,
  platform    text,
  created_at  timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_user_activity_logs_user_time
  ON public.user_activity_logs (user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_user_activity_logs_time
  ON public.user_activity_logs (created_at DESC);
CREATE INDEX IF NOT EXISTS idx_user_activity_logs_category_time
  ON public.user_activity_logs (category, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_user_activity_logs_action_time
  ON public.user_activity_logs (action, created_at DESC);

ALTER TABLE public.user_activity_logs ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.user_activity_logs FROM PUBLIC, anon, authenticated;
GRANT ALL ON public.user_activity_logs TO service_role;

COMMENT ON TABLE public.user_activity_logs IS
  'Kullanıcı eylem günlüğü. Yalnız admin RPC''leri okur/siler; 90 gün sonra prune_user_activity_logs siler.';

-- -----------------------------------------------------------------------------
-- 2) Yazma yardımcısı — asla hata fırlatmaz, bot/silinmiş kullanıcıyı atlar
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION private.log_user_activity(
  p_user        uuid,
  p_action      text,
  p_category    text,
  p_entity_type text DEFAULT NULL,
  p_entity_id   text DEFAULT NULL,
  p_summary     text DEFAULT NULL,
  p_metadata    jsonb DEFAULT '{}'::jsonb,
  p_platform    text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_is_bot boolean;
BEGIN
  IF p_user IS NULL THEN
    RETURN;
  END IF;

  -- Profil satırı yoksa (silinmekte olan hesap) ya da bot ise yazma.
  SELECT is_bot INTO v_is_bot FROM public.profiles WHERE id = p_user;
  IF NOT FOUND OR COALESCE(v_is_bot, false) THEN
    RETURN;
  END IF;

  INSERT INTO public.user_activity_logs
    (user_id, action, category, entity_type, entity_id, summary, metadata, platform)
  VALUES (
    p_user,
    left(p_action, 60),
    left(COALESCE(NULLIF(p_category, ''), 'app'), 30),
    left(p_entity_type, 40),
    left(p_entity_id, 80),
    left(p_summary, 200),
    COALESCE(p_metadata, '{}'::jsonb),
    left(p_platform, 20)
  );
EXCEPTION WHEN OTHERS THEN
  NULL; -- günlük, asıl işlemi hiçbir koşulda bozmamalı
END;
$$;

REVOKE ALL ON FUNCTION private.log_user_activity(uuid, text, text, text, text, text, jsonb, text)
  FROM PUBLIC, anon, authenticated;

-- -----------------------------------------------------------------------------
-- 3) Genel tetikleyici — tabloya göre eylemi çözer
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION private.trg_user_activity()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  r         jsonb;
  o         jsonb;
  v_user    uuid;
  v_action  text;
  v_cat     text;
  v_etype   text;
  v_eid     text;
  v_summary text;
  v_meta    jsonb := '{}'::jsonb;
  v_actor   uuid := auth.uid();
  v_label   text;
BEGIN
  BEGIN
    IF TG_OP = 'DELETE' THEN
      r := to_jsonb(OLD);
    ELSE
      r := to_jsonb(NEW);
    END IF;
    IF TG_OP = 'UPDATE' THEN
      o := to_jsonb(OLD);
    END IF;

    CASE TG_TABLE_NAME
      WHEN 'profiles' THEN
        v_user := (r->>'id')::uuid;
        v_eid  := r->>'id';
        v_etype := 'profile';
        v_cat := 'account';
        IF TG_OP = 'INSERT' THEN
          v_action := 'signup';
          v_cat := 'auth';
          v_summary := 'Hesap oluşturdu';
        ELSIF TG_OP = 'UPDATE' THEN
          -- Yalnızca ilgili sütunlar değişince çalışır (bkz. UPDATE OF listesi).
          IF (r->>'username') IS DISTINCT FROM (o->>'username') THEN
            v_action := 'username_changed';
            v_summary := 'Kullanıcı adını değiştirdi';
            v_meta := jsonb_build_object('from', o->>'username', 'to', r->>'username');
          ELSIF (r->>'avatar_url') IS DISTINCT FROM (o->>'avatar_url') THEN
            v_action := 'avatar_changed';
            v_summary := 'Profil fotoğrafını değiştirdi';
          ELSIF (r->>'full_name') IS DISTINCT FROM (o->>'full_name') THEN
            v_action := 'name_changed';
            v_summary := 'Adını değiştirdi';
          ELSIF (r->>'status') IS DISTINCT FROM (o->>'status') THEN
            v_action := 'status_changed';
            v_summary := 'Hesap durumu değişti: ' || COALESCE(o->>'status', '?') || ' → ' || COALESCE(r->>'status', '?');
            v_meta := jsonb_build_object('from', o->>'status', 'to', r->>'status');
          ELSIF (r->>'role') IS DISTINCT FROM (o->>'role') THEN
            v_action := 'role_changed';
            v_summary := 'Rolü değişti: ' || COALESCE(o->>'role', '?') || ' → ' || COALESCE(r->>'role', '?');
            v_meta := jsonb_build_object('from', o->>'role', 'to', r->>'role');
          END IF;
          IF v_actor IS NOT NULL AND v_actor <> v_user THEN
            v_meta := v_meta || jsonb_build_object('by_admin', true);
          END IF;
        END IF;

      WHEN 'posts' THEN
        v_user := (r->>'user_id')::uuid; v_cat := 'social'; v_etype := 'post'; v_eid := r->>'id';
        IF TG_OP = 'INSERT' THEN
          v_action := 'post_created'; v_summary := 'Gönderi paylaştı';
          v_meta := jsonb_build_object('preview', left(COALESCE(r->>'content', ''), 80));
        ELSIF TG_OP = 'DELETE' AND v_actor = v_user THEN
          v_action := 'post_deleted'; v_summary := 'Gönderisini sildi';
        END IF;

      WHEN 'post_comments' THEN
        v_user := (r->>'user_id')::uuid; v_cat := 'social'; v_etype := 'post'; v_eid := r->>'post_id';
        IF TG_OP = 'INSERT' THEN
          v_action := 'comment_created'; v_summary := 'Yorum yaptı';
          v_meta := jsonb_build_object('preview', left(COALESCE(r->>'content', ''), 80));
        END IF;

      WHEN 'post_likes' THEN
        v_user := (r->>'user_id')::uuid; v_cat := 'social'; v_etype := 'post'; v_eid := r->>'post_id';
        IF TG_OP = 'INSERT' THEN
          v_action := 'post_liked'; v_summary := 'Gönderi beğendi';
        END IF;

      WHEN 'post_favorites' THEN
        v_user := (r->>'user_id')::uuid; v_cat := 'social'; v_etype := 'post'; v_eid := r->>'post_id';
        IF TG_OP = 'INSERT' THEN
          v_action := 'post_saved'; v_summary := 'Gönderi kaydetti';
        END IF;

      WHEN 'product_favorites' THEN
        v_user := (r->>'user_id')::uuid; v_cat := 'shop'; v_etype := 'product'; v_eid := r->>'product_id';
        IF TG_OP = 'INSERT' THEN
          v_action := 'product_favorited'; v_summary := 'Ürünü favorilere ekledi';
        END IF;

      WHEN 'follows' THEN
        v_user := (r->>'follower_id')::uuid; v_cat := 'social'; v_etype := 'user'; v_eid := r->>'following_id';
        SELECT '@' || username INTO v_label FROM public.profiles WHERE id = (r->>'following_id')::uuid;
        IF TG_OP = 'INSERT' THEN
          v_action := 'followed'; v_summary := 'Takip etti: ' || COALESCE(v_label, 'bir kullanıcı');
        ELSIF TG_OP = 'DELETE' AND v_actor = v_user THEN
          v_action := 'unfollowed'; v_summary := 'Takibi bıraktı: ' || COALESCE(v_label, 'bir kullanıcı');
        END IF;

      WHEN 'product_views' THEN
        v_user := (r->>'user_id')::uuid; v_cat := 'shop'; v_etype := 'product'; v_eid := r->>'product_id';
        SELECT name INTO v_label FROM public.products WHERE id = (r->>'product_id')::uuid;
        IF TG_OP = 'INSERT' THEN
          v_action := 'product_viewed'; v_summary := 'Ürüne baktı: ' || COALESCE(v_label, '?');
        END IF;

      WHEN 'shop_views' THEN
        v_user := (r->>'user_id')::uuid; v_cat := 'shop'; v_etype := 'shop'; v_eid := r->>'shop_id';
        SELECT name INTO v_label FROM public.shops WHERE id = (r->>'shop_id')::uuid;
        IF TG_OP = 'INSERT' THEN
          v_action := 'shop_viewed'; v_summary := 'Dükkana baktı: ' || COALESCE(v_label, '?');
        END IF;

      WHEN 'stories' THEN
        v_user := (r->>'user_id')::uuid; v_cat := 'social'; v_etype := 'story'; v_eid := r->>'id';
        IF TG_OP = 'INSERT' THEN
          v_action := 'story_created'; v_summary := 'Hikaye paylaştı';
        END IF;

      WHEN 'messages' THEN
        -- İÇERİK KAYDEDİLMEZ (gizlilik): yalnızca "mesaj gönderdi" ve konuşma id'si.
        v_user := (r->>'sender_id')::uuid; v_cat := 'message'; v_etype := 'conversation'; v_eid := r->>'conversation_id';
        IF TG_OP = 'INSERT' THEN
          v_action := 'message_sent'; v_summary := 'Mesaj gönderdi';
        END IF;

      WHEN 'orders' THEN
        v_user := (r->>'user_id')::uuid; v_cat := 'shop'; v_etype := 'order'; v_eid := r->>'id';
        IF TG_OP = 'INSERT' THEN
          v_action := 'order_created'; v_summary := 'Sipariş verdi';
          v_meta := jsonb_build_object('order_number', r->>'order_number', 'total', COALESCE(r->>'total_amount', r->>'total'));
        ELSIF TG_OP = 'UPDATE' AND (r->>'status') IS DISTINCT FROM (o->>'status') THEN
          v_action := 'order_status_changed';
          v_summary := 'Sipariş durumu: ' || COALESCE(o->>'status', '?') || ' → ' || COALESCE(r->>'status', '?');
          v_meta := jsonb_build_object('order_number', r->>'order_number', 'from', o->>'status', 'to', r->>'status');
        END IF;

      WHEN 'digital_orders' THEN
        v_user := (r->>'user_id')::uuid; v_cat := 'shop'; v_etype := 'digital_order'; v_eid := r->>'id';
        IF TG_OP = 'INSERT' THEN
          v_action := 'digital_order_created'; v_summary := 'Dijital ürün siparişi verdi';
          v_meta := jsonb_build_object('quantity', r->>'quantity', 'total', r->>'total_price');
        END IF;

      WHEN 'product_reviews' THEN
        v_user := (r->>'user_id')::uuid; v_cat := 'shop'; v_etype := 'product'; v_eid := r->>'product_id';
        IF TG_OP = 'INSERT' THEN
          v_action := 'product_reviewed'; v_summary := 'Ürünü değerlendirdi';
          v_meta := jsonb_build_object('rating', r->>'rating');
        END IF;

      WHEN 'shop_reviews' THEN
        v_user := (r->>'user_id')::uuid; v_cat := 'shop'; v_etype := 'shop'; v_eid := r->>'shop_id';
        IF TG_OP = 'INSERT' THEN
          v_action := 'shop_reviewed'; v_summary := 'Dükkanı değerlendirdi';
          v_meta := jsonb_build_object('rating', r->>'rating');
        END IF;

      WHEN 'coupon_usages' THEN
        v_user := (r->>'user_id')::uuid; v_cat := 'shop'; v_etype := 'coupon'; v_eid := r->>'coupon_id';
        IF TG_OP = 'INSERT' THEN
          v_action := 'coupon_used'; v_summary := 'Kupon kullandı';
        END IF;

      WHEN 'balance_transactions' THEN
        v_user := (r->>'user_id')::uuid; v_cat := 'finance'; v_etype := 'balance_transaction'; v_eid := r->>'id';
        IF TG_OP = 'INSERT' THEN
          v_action := 'balance_' || COALESCE(r->>'type', 'transaction');
          v_summary := 'Bakiye hareketi: ' || COALESCE(r->>'type', '?');
          v_meta := jsonb_build_object('amount', r->>'amount', 'status', r->>'status');
        END IF;

      WHEN 'user_reports' THEN
        v_user := (r->>'reporter_id')::uuid; v_cat := 'safety'; v_etype := 'user'; v_eid := r->>'reported_user_id';
        IF TG_OP = 'INSERT' THEN
          v_action := 'report_sent'; v_summary := 'Bir kullanıcıyı şikayet etti';
          v_meta := jsonb_build_object('reason', left(COALESCE(r->>'reason', ''), 80));
        END IF;

      WHEN 'support_tickets' THEN
        v_user := (r->>'user_id')::uuid; v_cat := 'support'; v_etype := 'ticket'; v_eid := r->>'id';
        IF TG_OP = 'INSERT' THEN
          v_action := 'ticket_created'; v_summary := 'Destek talebi açtı';
          v_meta := jsonb_build_object('subject', left(COALESCE(r->>'subject', ''), 80));
        END IF;

      WHEN 'ilanlar' THEN
        v_user := (r->>'owner_id')::uuid; v_cat := 'listing'; v_etype := 'ilan'; v_eid := r->>'id';
        IF TG_OP = 'INSERT' THEN
          v_action := 'ilan_created'; v_summary := 'İlan verdi';
          v_meta := jsonb_build_object('title', left(COALESCE(r->>'title', ''), 80));
        END IF;

      WHEN 'group_members' THEN
        v_user := (r->>'user_id')::uuid; v_cat := 'social'; v_etype := 'group'; v_eid := r->>'group_id';
        IF TG_OP = 'INSERT' THEN
          v_action := 'group_joined'; v_summary := 'Bir gruba katıldı';
        END IF;

      ELSE
        v_action := NULL;
    END CASE;

    IF v_action IS NOT NULL AND v_user IS NOT NULL THEN
      PERFORM private.log_user_activity(v_user, v_action, v_cat, v_etype, v_eid, v_summary, v_meta);
    END IF;
  EXCEPTION WHEN OTHERS THEN
    NULL; -- tetikleyici asıl işlemi hiçbir koşulda bozmaz
  END;

  RETURN NULL; -- AFTER tetikleyici; dönüş değeri yok sayılır
END;
$$;

REVOKE ALL ON FUNCTION private.trg_user_activity() FROM PUBLIC, anon, authenticated;

-- Tablo bu ortamda yoksa (eski/yeni şema farkı) sessizce atlayan bağlayıcı.
CREATE OR REPLACE FUNCTION private.attach_activity_trigger(p_table text, p_events text)
RETURNS void
LANGUAGE plpgsql
SET search_path = ''
AS $$
BEGIN
  IF to_regclass('public.' || p_table) IS NULL THEN
    RAISE NOTICE 'attach_activity_trigger: public.% yok, atlandı', p_table;
    RETURN;
  END IF;
  EXECUTE format('DROP TRIGGER IF EXISTS trg_user_activity_%I ON public.%I', p_table, p_table);
  EXECUTE format(
    'CREATE TRIGGER trg_user_activity_%I AFTER %s ON public.%I FOR EACH ROW EXECUTE FUNCTION private.trg_user_activity()',
    p_table, p_events, p_table
  );
END;
$$;

REVOKE ALL ON FUNCTION private.attach_activity_trigger(text, text) FROM PUBLIC, anon, authenticated;

SELECT private.attach_activity_trigger('profiles',
  'INSERT OR UPDATE OF username, avatar_url, full_name, status, role');
SELECT private.attach_activity_trigger('posts', 'INSERT OR DELETE');
SELECT private.attach_activity_trigger('post_comments', 'INSERT');
SELECT private.attach_activity_trigger('post_likes', 'INSERT');
SELECT private.attach_activity_trigger('post_favorites', 'INSERT');
SELECT private.attach_activity_trigger('product_favorites', 'INSERT');
SELECT private.attach_activity_trigger('follows', 'INSERT OR DELETE');
SELECT private.attach_activity_trigger('stories', 'INSERT');
SELECT private.attach_activity_trigger('messages', 'INSERT');
SELECT private.attach_activity_trigger('orders', 'INSERT OR UPDATE OF status');
SELECT private.attach_activity_trigger('digital_orders', 'INSERT');
SELECT private.attach_activity_trigger('product_reviews', 'INSERT');
SELECT private.attach_activity_trigger('shop_reviews', 'INSERT');
SELECT private.attach_activity_trigger('coupon_usages', 'INSERT');
SELECT private.attach_activity_trigger('balance_transactions', 'INSERT');
SELECT private.attach_activity_trigger('user_reports', 'INSERT');
SELECT private.attach_activity_trigger('support_tickets', 'INSERT');
SELECT private.attach_activity_trigger('ilanlar', 'INSERT');
SELECT private.attach_activity_trigger('group_members', 'INSERT');
SELECT private.attach_activity_trigger('product_views', 'INSERT');
SELECT private.attach_activity_trigger('shop_views', 'INSERT');

-- -----------------------------------------------------------------------------
-- 4) İstemci RPC'si — izinli eylemler
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.log_user_action(
  p_action      text,
  p_category    text DEFAULT 'app',
  p_entity_type text DEFAULT NULL,
  p_entity_id   text DEFAULT NULL,
  p_summary     text DEFAULT NULL,
  p_metadata    jsonb DEFAULT '{}'::jsonb,
  p_platform    text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_uid uuid := auth.uid();
  -- Tablosu olan eylemler (gönderi, sipariş, ürün/dükkan görüntüleme...) tetikleyicilerle,
  -- müzik ve günün fırsatı tıklaması kendi RPC'leriyle yazılır; buraya yalnızca
  -- başka türlü yakalanamayanlar girer.
  v_allowed constant text[] := ARRAY[
    'app_open', 'login', 'logout', 'profile_viewed', 'search_performed', 'share_clicked'
  ];
BEGIN
  IF v_uid IS NULL THEN
    RETURN; -- misafir eylemleri kaydedilmez
  END IF;
  IF p_action IS NULL OR NOT (p_action = ANY (v_allowed)) THEN
    RETURN; -- izinli olmayan eylem sessizce yok sayılır
  END IF;

  -- Dakikada en fazla 60 satır: hatalı bir istemci döngüsü tabloyu şişirmesin.
  IF (SELECT count(*) FROM public.user_activity_logs
       WHERE user_id = v_uid AND created_at > now() - interval '1 minute') >= 60 THEN
    RETURN;
  END IF;

  -- Metadata boyut sınırı (2 KB).
  IF p_metadata IS NULL OR pg_column_size(p_metadata) > 2048 THEN
    p_metadata := '{}'::jsonb;
  END IF;

  PERFORM private.log_user_activity(
    v_uid, p_action, p_category, p_entity_type, p_entity_id, p_summary, p_metadata, p_platform
  );
END;
$$;

REVOKE ALL ON FUNCTION public.log_user_action(text, text, text, text, text, jsonb, text)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.log_user_action(text, text, text, text, text, jsonb, text)
  TO authenticated, service_role;

-- -----------------------------------------------------------------------------
-- 5) Admin RPC'leri
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_activity_logs_list(
  p_user_id  uuid        DEFAULT NULL,
  p_category text        DEFAULT NULL,
  p_action   text        DEFAULT NULL,
  p_search   text        DEFAULT NULL,
  p_from     timestamptz DEFAULT NULL,
  p_to       timestamptz DEFAULT NULL,
  p_limit    integer     DEFAULT 50,
  p_offset   integer     DEFAULT 0
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_limit  integer := LEAST(GREATEST(COALESCE(p_limit, 50), 1), 200);
  v_offset integer := GREATEST(COALESCE(p_offset, 0), 0);
  v_q      text := NULLIF(btrim(COALESCE(p_search, '')), '');
  v_res    jsonb;
BEGIN
  IF NOT private.current_user_is_admin() THEN
    RAISE EXCEPTION 'admin_activity_logs_list: not admin' USING ERRCODE = '42501';
  END IF;

  WITH f AS (
    SELECT l.id, l.user_id, p.username, p.full_name, p.avatar_url,
           l.action, l.category, l.entity_type, l.entity_id, l.summary,
           l.metadata, l.platform, l.created_at
    FROM public.user_activity_logs AS l
    LEFT JOIN public.profiles AS p ON p.id = l.user_id
    WHERE (p_user_id IS NULL OR l.user_id = p_user_id)
      AND (p_category IS NULL OR l.category = p_category)
      AND (p_action IS NULL OR l.action = p_action)
      AND (p_from IS NULL OR l.created_at >= p_from)
      AND (p_to IS NULL OR l.created_at < p_to)
      AND (
        v_q IS NULL
        OR l.summary ILIKE '%' || v_q || '%'
        OR l.action ILIKE '%' || v_q || '%'
        OR p.username ILIKE '%' || v_q || '%'
        OR p.full_name ILIKE '%' || v_q || '%'
      )
  ),
  c AS (SELECT count(*) AS n FROM f),
  pg AS (
    SELECT * FROM f ORDER BY created_at DESC, id DESC LIMIT v_limit OFFSET v_offset
  )
  SELECT jsonb_build_object(
    'total', (SELECT n FROM c),
    'rows', COALESCE(
      (SELECT jsonb_agg(to_jsonb(pg) ORDER BY pg.created_at DESC, pg.id DESC) FROM pg),
      '[]'::jsonb
    )
  ) INTO v_res;

  RETURN v_res;
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_activity_logs_stats(p_days integer DEFAULT 7)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_days  integer := LEAST(GREATEST(COALESCE(p_days, 7), 1), 90);
  v_start timestamptz := now() - (LEAST(GREATEST(COALESCE(p_days, 7), 1), 90) * interval '1 day');
  v_today timestamptz := date_trunc('day', now() AT TIME ZONE 'Europe/Istanbul') AT TIME ZONE 'Europe/Istanbul';
BEGIN
  IF NOT private.current_user_is_admin() THEN
    RAISE EXCEPTION 'admin_activity_logs_stats: not admin' USING ERRCODE = '42501';
  END IF;

  RETURN jsonb_build_object(
    'windowDays', v_days,
    'totalAll', (SELECT count(*) FROM public.user_activity_logs),
    'total', (SELECT count(*) FROM public.user_activity_logs WHERE created_at >= v_start),
    'today', (SELECT count(*) FROM public.user_activity_logs WHERE created_at >= v_today),
    'activeUsers', (
      SELECT count(DISTINCT user_id) FROM public.user_activity_logs WHERE created_at >= v_start
    ),
    'byCategory', COALESCE((
      SELECT jsonb_object_agg(category, n)
      FROM (
        SELECT category, count(*) AS n FROM public.user_activity_logs
        WHERE created_at >= v_start GROUP BY category
      ) AS x
    ), '{}'::jsonb),
    'topActions', COALESCE((
      SELECT jsonb_agg(jsonb_build_object('action', action, 'count', n) ORDER BY n DESC)
      FROM (
        SELECT action, count(*) AS n FROM public.user_activity_logs
        WHERE created_at >= v_start GROUP BY action ORDER BY n DESC LIMIT 12
      ) AS x
    ), '[]'::jsonb),
    'daily', COALESCE((
      SELECT jsonb_agg(jsonb_build_object('day', d, 'count', n) ORDER BY d)
      FROM (
        SELECT to_char(created_at AT TIME ZONE 'Europe/Istanbul', 'YYYY-MM-DD') AS d, count(*) AS n
        FROM public.user_activity_logs
        WHERE created_at >= v_start GROUP BY 1
      ) AS x
    ), '[]'::jsonb),
    'topUsers', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
               'user_id', u.user_id, 'username', p.username, 'full_name', p.full_name,
               'avatar_url', p.avatar_url, 'count', u.n
             ) ORDER BY u.n DESC)
      FROM (
        SELECT user_id, count(*) AS n FROM public.user_activity_logs
        WHERE created_at >= v_start AND user_id IS NOT NULL
        GROUP BY user_id ORDER BY n DESC LIMIT 10
      ) AS u
      LEFT JOIN public.profiles AS p ON p.id = u.user_id
    ), '[]'::jsonb)
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_delete_activity_logs(p_ids bigint[])
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_deleted integer;
BEGIN
  IF NOT private.current_user_is_admin() THEN
    RAISE EXCEPTION 'admin_delete_activity_logs: not admin' USING ERRCODE = '42501';
  END IF;
  IF p_ids IS NULL OR array_length(p_ids, 1) IS NULL THEN
    RETURN 0;
  END IF;

  DELETE FROM public.user_activity_logs WHERE id = ANY (p_ids);
  GET DIAGNOSTICS v_deleted = ROW_COUNT;

  INSERT INTO public.admin_audit_log (admin_id, action, target_table, target_id, new_data)
  VALUES (auth.uid(), 'delete_activity_logs', 'user_activity_logs', NULL,
          jsonb_build_object('deleted', v_deleted));

  RETURN v_deleted;
END;
$$;

-- Filtreye uyan TÜM satırları siler. Hiç filtre verilmezse tablo boşaltılır
-- (arayüz bunu ayrıca onaylatır).
CREATE OR REPLACE FUNCTION public.admin_clear_activity_logs(
  p_user_id         uuid    DEFAULT NULL,
  p_category        text    DEFAULT NULL,
  p_older_than_days integer DEFAULT NULL
)
RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_deleted bigint;
BEGIN
  IF NOT private.current_user_is_admin() THEN
    RAISE EXCEPTION 'admin_clear_activity_logs: not admin' USING ERRCODE = '42501';
  END IF;

  DELETE FROM public.user_activity_logs
  WHERE (p_user_id IS NULL OR user_id = p_user_id)
    AND (p_category IS NULL OR category = p_category)
    AND (p_older_than_days IS NULL
         OR created_at < now() - (GREATEST(p_older_than_days, 0) * interval '1 day'));
  GET DIAGNOSTICS v_deleted = ROW_COUNT;

  INSERT INTO public.admin_audit_log (admin_id, action, target_table, target_id, new_data)
  VALUES (auth.uid(), 'clear_activity_logs', 'user_activity_logs', p_user_id::text,
          jsonb_build_object('deleted', v_deleted, 'category', p_category,
                             'older_than_days', p_older_than_days));

  RETURN v_deleted;
END;
$$;

-- Yönetici işlemleri (admin_audit_log) — "kim, neyi, ne zaman" görünümü.
CREATE OR REPLACE FUNCTION public.admin_audit_log_list(
  p_limit  integer DEFAULT 50,
  p_offset integer DEFAULT 0
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_limit  integer := LEAST(GREATEST(COALESCE(p_limit, 50), 1), 200);
  v_offset integer := GREATEST(COALESCE(p_offset, 0), 0);
BEGIN
  IF NOT private.current_user_is_admin() THEN
    RAISE EXCEPTION 'admin_audit_log_list: not admin' USING ERRCODE = '42501';
  END IF;

  RETURN jsonb_build_object(
    'total', (SELECT count(*) FROM public.admin_audit_log),
    'rows', COALESCE((
      SELECT jsonb_agg(to_jsonb(x) ORDER BY x.created_at DESC)
      FROM (
        SELECT a.id, a.admin_id, p.username AS admin_username, p.full_name AS admin_name,
               a.action, a.target_table, a.target_id, a.new_data, a.created_at
        FROM public.admin_audit_log AS a
        LEFT JOIN public.profiles AS p ON p.id = a.admin_id
        ORDER BY a.created_at DESC
        LIMIT v_limit OFFSET v_offset
      ) AS x
    ), '[]'::jsonb)
  );
END;
$$;

REVOKE ALL ON FUNCTION public.admin_activity_logs_list(uuid, text, text, text, timestamptz, timestamptz, integer, integer) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.admin_activity_logs_stats(integer) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.admin_delete_activity_logs(bigint[]) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.admin_clear_activity_logs(uuid, text, integer) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.admin_audit_log_list(integer, integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_activity_logs_list(uuid, text, text, text, timestamptz, timestamptz, integer, integer) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.admin_activity_logs_stats(integer) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.admin_delete_activity_logs(bigint[]) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.admin_clear_activity_logs(uuid, text, integer) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.admin_audit_log_list(integer, integer) TO authenticated, service_role;

-- -----------------------------------------------------------------------------
-- 6) Saklama: 90 gün (admin isterse elle daha erken siler)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.prune_user_activity_logs()
RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_deleted bigint;
BEGIN
  DELETE FROM public.user_activity_logs WHERE created_at < now() - interval '90 days';
  GET DIAGNOSTICS v_deleted = ROW_COUNT;
  RETURN v_deleted;
END;
$$;

REVOKE ALL ON FUNCTION public.prune_user_activity_logs() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.prune_user_activity_logs() TO service_role;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    PERFORM cron.unschedule('prune-user-activity-logs-daily')
    WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'prune-user-activity-logs-daily');
    PERFORM cron.schedule(
      'prune-user-activity-logs-daily',
      '27 3 * * *',
      $cron$SELECT public.prune_user_activity_logs();$cron$
    );
  END IF;
END;
$$;

COMMIT;

NOTIFY pgrst, 'reload schema';
