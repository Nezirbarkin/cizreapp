-- =============================================================================
-- 20260928000007_cart_price_drop_notifications.sql
-- -----------------------------------------------------------------------------
-- Görev 3.3 — Sepet takibi ve indirim bildirimi (retargeting).
--
-- 1) Satıcı, ürünlerini sepetine ekleyen müşterilerin İSTATİSTİĞİNİ görür
--    (`get_shop_cart_stats`). Yalnız sayılar döner — kim olduğu değil: müşteri
--    kimliği satıcıya açılmaz.
-- 2) Satıcı bir ürünün fiyatını gerçekten düşürdüğünde (indirimli fiyat ya da
--    fiyat), o ürünü sepetinde tutan müşterilere otomatik bildirim gider
--    (`notify_cart_price_drop` tetikleyicisi → notifications → outbox → push).
--    Aynı müşteriye aynı ürün için 24 saatte en fazla bir kez; kuruşluk
--    oynamalar bildirim sayılmaz; müşteri ayarlardan kapatabilir
--    (`notification_preferences.cart_price_drop_enabled`, varsayılan açık).
--
-- 3) HATA DÜZELTMESİ: mevcut `notify_price_drops` (fiyat alarmı) `format('%.2f')`
--    kullanıyordu; PostgreSQL format() bunu tanımaz (22023). Eşleşen aktif bir
--    fiyat alarmı varken satıcının fiyat düşürmesi HATAYLA GERİ ALINIYORDU.
--    Biçimlendirme düzeltildi ve iki tetikleyici de artık ürün güncellemesini
--    hiçbir koşulda geri almaz (bildirim hatası günlüğe yazılır).
-- =============================================================================

BEGIN;

SET LOCAL lock_timeout = '10s';

-- -----------------------------------------------------------------------------
-- 1) Müşteri tercihi (varsayılan AÇIK: müşteri ürünü kendisi sepetine ekledi)
-- -----------------------------------------------------------------------------
ALTER TABLE public.notification_preferences
  ADD COLUMN IF NOT EXISTS cart_price_drop_enabled boolean NOT NULL DEFAULT true;

COMMENT ON COLUMN public.notification_preferences.cart_price_drop_enabled IS
  'Sepetimdeki ürün indirime girince bildirim (Görev 3.3). false ise bildirim hiç oluşturulmaz.';

-- -----------------------------------------------------------------------------
-- 2) Bildirim günlüğü: müşteri × ürün başına son bildirim (24 saat sınırı ve
--    satıcı istatistiği için). İstemciye tamamen kapalı.
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.cart_price_drop_notifications (
  user_id     uuid NOT NULL,
  product_id  uuid NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
  shop_id     uuid NOT NULL REFERENCES public.shops(id) ON DELETE CASCADE,
  old_price   numeric(12,2),
  new_price   numeric(12,2),
  notified_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, product_id)
);

CREATE INDEX IF NOT EXISTS cart_price_drop_notifications_shop_idx
  ON public.cart_price_drop_notifications (shop_id, notified_at DESC);

ALTER TABLE public.cart_price_drop_notifications ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.cart_price_drop_notifications FROM PUBLIC, anon, authenticated;

-- -----------------------------------------------------------------------------
-- 3) Para biçimi (uygulamadaki formatShopMoney ile aynı: ₺150 / ₺129,90)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION private.format_try(p_value numeric)
RETURNS text
LANGUAGE sql
IMMUTABLE
SET search_path = ''
AS $fn$
  SELECT CASE
    WHEN p_value IS NULL THEN ''
    WHEN p_value = trunc(p_value) THEN '₺' || to_char(p_value, 'FM999999999990')
    ELSE '₺' || replace(to_char(p_value, 'FM999999999990.00'), '.', ',')
  END;
$fn$;

REVOKE ALL ON FUNCTION private.format_try(numeric) FROM PUBLIC;

-- -----------------------------------------------------------------------------
-- 4) Fiyat alarmı tetikleyicisi — biçim hatası düzeltildi
--    (davranış aynı: hedefin altına inen fiyat, 24 saat tekrar yok, alarm kapanır)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.notify_price_drops()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_alert       RECORD;
  v_old_price   NUMERIC(10, 2);
  v_new_price   NUMERIC(10, 2);
  v_existing_id UUID;
BEGIN
  -- Geçerli (müşterinin ödeyeceği) fiyat: fiyattan düşük pozitif indirimli
  -- fiyat, yoksa fiyat.
  v_old_price := CASE WHEN OLD.discount_price > 0 AND OLD.discount_price < OLD.price
                      THEN OLD.discount_price ELSE OLD.price END;
  v_new_price := CASE WHEN NEW.discount_price > 0 AND NEW.discount_price < NEW.price
                      THEN NEW.discount_price ELSE NEW.price END;

  IF v_new_price IS NULL OR v_old_price IS NULL OR v_new_price >= v_old_price THEN
    RETURN NEW;
  END IF;

  BEGIN
    FOR v_alert IN
      SELECT pa.id AS alert_id, pa.user_id, pa.target_price
        FROM public.price_alerts pa
        WHERE pa.product_id = NEW.id
          AND pa.is_active = true
          AND pa.target_price >= v_new_price
    LOOP
      SELECT n.id INTO v_existing_id
        FROM public.notifications n
       WHERE n.user_id = v_alert.user_id
         AND n.type = 'price_drop'
         AND n.entity_id = NEW.id::text
         AND n.created_at > NOW() - INTERVAL '24 hours'
       LIMIT 1;

      IF v_existing_id IS NOT NULL THEN
        UPDATE public.price_alerts
           SET is_active = false, triggered_at = NOW()
         WHERE id = v_alert.alert_id;
        CONTINUE;
      END IF;

      INSERT INTO public.notifications (
        user_id, type, title, content, actor_id, entity_id, is_read, created_at
      ) VALUES (
        v_alert.user_id,
        'price_drop',
        '📉 Fiyat Düştü!',
        format('%s ürünü %s oldu. Hedefiniz %s',
               NEW.name, private.format_try(v_new_price), private.format_try(v_alert.target_price)),
        NULL,
        NEW.id,
        false,
        NOW()
      );

      UPDATE public.price_alerts
         SET is_active = false, triggered_at = NOW()
       WHERE id = v_alert.alert_id;
    END LOOP;
  EXCEPTION WHEN OTHERS THEN
    -- Bildirim hatası satıcının fiyat güncellemesini ASLA geri almasın.
    RAISE LOG 'notify_price_drops (%): %', NEW.id, SQLERRM;
  END;

  RETURN NEW;
END;
$function$;

-- -----------------------------------------------------------------------------
-- 5) Sepetteki ürün indirime girince müşteriye bildirim
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.notify_cart_price_drop()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $fn$
DECLARE
  v_old numeric(12,2);
  v_new numeric(12,2);
  v_shop record;
  v_image text;
  v_user uuid;
BEGIN
  v_old := CASE WHEN OLD.discount_price > 0 AND OLD.discount_price < OLD.price
                THEN OLD.discount_price ELSE OLD.price END;
  v_new := CASE WHEN NEW.discount_price > 0 AND NEW.discount_price < NEW.price
                THEN NEW.discount_price ELSE NEW.price END;

  -- Yalnız GERÇEK düşüş: kuruşluk oynamalar (fiyatın %1'i ve 1 TL'den az)
  -- bildirim yağdırmasın.
  IF v_new IS NULL OR v_old IS NULL OR v_new <= 0 OR v_new >= v_old
     OR (v_old - v_new) < LEAST(1, v_old * 0.01) THEN
    RETURN NEW;
  END IF;
  IF NOT COALESCE(NEW.is_available, false) THEN
    RETURN NEW;
  END IF;

  BEGIN
    SELECT s.id, s.name, s.owner_id INTO v_shop
      FROM public.shops s
     WHERE s.id = NEW.shop_id AND COALESCE(s.is_active, false);
    IF NOT FOUND THEN
      RETURN NEW;
    END IF;

    v_image := COALESCE(NULLIF(NEW.image_url, ''), NULLIF(NEW.images[1], ''));

    FOR v_user IN
      SELECT DISTINCT c.user_id
        FROM public.cart c
       WHERE c.product_id = NEW.id
         AND c.user_id IS NOT NULL
         AND c.user_id IS DISTINCT FROM v_shop.owner_id
         AND NOT EXISTS (
           SELECT 1 FROM public.notification_preferences np
            WHERE np.user_id = c.user_id AND np.cart_price_drop_enabled = false
         )
         AND NOT EXISTS (
           SELECT 1 FROM public.cart_price_drop_notifications l
            WHERE l.user_id = c.user_id AND l.product_id = NEW.id
              AND l.notified_at > now() - interval '24 hours'
         )
    LOOP
      INSERT INTO public.notifications (
        user_id, type, title, content, entity_id, entity_type, entity_image, data, is_read
      ) VALUES (
        v_user,
        'cart_price_drop',
        '🛒 Sepetindeki ürün indirimde!',
        format('%s şimdi %s (önce %s) · %s',
               NEW.name, private.format_try(v_new), private.format_try(v_old), v_shop.name),
        NEW.id::text,
        'product',
        v_image,
        jsonb_build_object(
          'product_id', NEW.id,
          'shop_id', NEW.shop_id,
          'old_price', v_old,
          'new_price', v_new
        ),
        false
      );

      INSERT INTO public.cart_price_drop_notifications (user_id, product_id, shop_id, old_price, new_price, notified_at)
      VALUES (v_user, NEW.id, NEW.shop_id, v_old, v_new, now())
      ON CONFLICT (user_id, product_id) DO UPDATE
        SET shop_id = EXCLUDED.shop_id,
            old_price = EXCLUDED.old_price,
            new_price = EXCLUDED.new_price,
            notified_at = EXCLUDED.notified_at;
    END LOOP;
  EXCEPTION WHEN OTHERS THEN
    -- Bildirim hatası satıcının fiyat güncellemesini ASLA geri almasın.
    RAISE LOG 'notify_cart_price_drop (%): %', NEW.id, SQLERRM;
  END;

  RETURN NEW;
END;
$fn$;

DROP TRIGGER IF EXISTS products_cart_price_drop_notify ON public.products;
CREATE TRIGGER products_cart_price_drop_notify
  AFTER UPDATE ON public.products
  FOR EACH ROW
  WHEN (OLD.price IS DISTINCT FROM NEW.price OR OLD.discount_price IS DISTINCT FROM NEW.discount_price)
  EXECUTE FUNCTION public.notify_cart_price_drop();

-- -----------------------------------------------------------------------------
-- 6) Satıcının sepet istatistiği (yalnız sayılar; müşteri kimliği yok)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_shop_cart_stats(p_shop_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $fn$
DECLARE
  v_uid uuid := auth.uid();
  v_owner uuid;
  v_result jsonb;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Oturum gerekli' USING ERRCODE = '42501';
  END IF;

  SELECT s.owner_id INTO v_owner FROM public.shops s WHERE s.id = p_shop_id;
  IF v_owner IS NULL OR (v_owner <> v_uid AND NOT public.auth_is_admin()) THEN
    RAISE EXCEPTION 'Bu mağazanın istatistiğini görme yetkiniz yok' USING ERRCODE = '42501';
  END IF;

  WITH items AS (
    SELECT c.user_id, c.product_id, COALESCE(c.quantity, 1) AS quantity,
           c.created_at, COALESCE(c.updated_at, c.created_at) AS touched_at
      FROM public.cart c
      JOIN public.products p ON p.id = c.product_id
     WHERE p.shop_id = p_shop_id
       AND c.user_id IS DISTINCT FROM v_owner
  ),
  per_product AS (
    SELECT i.product_id,
           count(DISTINCT i.user_id) AS users,
           sum(i.quantity) AS quantity,
           min(i.created_at) AS first_added_at,
           max(i.touched_at) AS last_added_at
      FROM items i
     GROUP BY i.product_id
  ),
  notified AS (
    SELECT l.product_id, count(*) AS users, max(l.notified_at) AS last_at
      FROM public.cart_price_drop_notifications l
     WHERE l.shop_id = p_shop_id AND l.notified_at > now() - interval '30 days'
     GROUP BY l.product_id
  ),
  rows AS (
    SELECT pp.*, p.name, p.price, p.discount_price, p.old_price,
           COALESCE(p.is_available, false) AS is_available,
           COALESCE(p.product_type, 'normal') AS product_type,
           COALESCE(NULLIF(p.image_url, ''), NULLIF(p.images[1], '')) AS image,
           CASE WHEN p.discount_price > 0 AND p.discount_price < p.price
                THEN p.discount_price ELSE p.price END AS effective_price,
           COALESCE(n.users, 0) AS notified_users,
           n.last_at AS last_notified_at
      FROM per_product pp
      JOIN public.products p ON p.id = pp.product_id
      LEFT JOIN notified n ON n.product_id = pp.product_id
  )
  SELECT jsonb_build_object(
    'summary', jsonb_build_object(
      'users',    (SELECT count(DISTINCT user_id) FROM items),
      'products', (SELECT count(*) FROM rows),
      'quantity', COALESCE((SELECT sum(quantity) FROM items), 0),
      'value',    COALESCE((SELECT sum(r.quantity * r.effective_price) FROM rows r), 0)
    ),
    'products', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
               'product_id', r.product_id,
               'name', r.name,
               'image', r.image,
               'price', r.price,
               'discount_price', r.discount_price,
               'old_price', r.old_price,
               'effective_price', r.effective_price,
               'is_available', r.is_available,
               'is_digital', r.product_type = 'digital',
               'users', r.users,
               'quantity', r.quantity,
               'first_added_at', r.first_added_at,
               'last_added_at', r.last_added_at,
               'notified_users', r.notified_users,
               'last_notified_at', r.last_notified_at
             ) ORDER BY r.users DESC, r.quantity DESC, r.last_added_at DESC)
        FROM rows r
    ), '[]'::jsonb)
  ) INTO v_result;

  RETURN v_result;
END;
$fn$;

REVOKE ALL ON FUNCTION public.get_shop_cart_stats(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_shop_cart_stats(uuid) TO authenticated;

NOTIFY pgrst, 'reload schema';

COMMIT;
