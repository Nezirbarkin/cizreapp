-- Dijital sipariş bildirimleri tüm teslim şekillerinde DB tetikleyicisinden
-- (2026-10-16).
--
-- Canlıdaki eski (07-13) smm-order-manual-status / smm-order-status-check
-- alıcıya `digital_order_status`, yöneticilere `digital_order_commission`
-- bildirimini kendisi ekliyordu. Depodaki puan uyumlu sürümler (iade
-- refund_digital_order_payment, satıcı kazancı credit_digital_order_seller ile)
-- bu bildirimleri atmıyor. Bildirim fonksiyon yerine tetikleyiciden gelir:
--
--   * notify_digital_order_status: durum gerçekten değişip completed /
--     partial / canceled / refunded / failed olduğunda alıcıya tek bildirim.
--     Edge Function'lar ekonomik adımı (iade/kazanç) durum yazımından ÖNCE
--     yaptığından NEW.refund_* bu geçişin iadesini içerir → metin puan/TL
--     dağılımını doğru gösterir. Aynı durumun tekrar yazılması (ağ tekrarı,
--     status-check'in her turda durumu yeniden yazması) bildirim üretmez.
--   * notify_digital_order_seller_credit: seller_credited false → true
--     olduğunda yöneticilere kazanç bildirimi (credit_digital_order_seller
--     duplicate dönüşünde satırı güncellemez → tekrar bildirim yok).
--   * notify_manual_digital_order artık yalnız yeni paket siparişinde
--     satıcıya "teslim bekliyor" der; paket teslim/iptal metinleri aynen
--     notify_digital_order_status'a taşındı.
--
-- SIRALAMA: Bu göç, iki Edge Function'ın depodaki sürümü deploy edildikten
-- HEMEN SONRA uygulanmalı. Eski sürümler canlıdayken uygulanırsa SMM
-- siparişlerinde alıcı ve yönetici bildirimi ikişer kez gider.

BEGIN;

-- ── 1) Yeni paket siparişi → satıcı (yalnız INSERT) ────────────────────────
CREATE OR REPLACE FUNCTION public.notify_manual_digital_order()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $$
DECLARE
  v_seller_id uuid;
  v_product_name text;
  v_customer_name text;
BEGIN
  SELECT s.owner_id, p.name INTO v_seller_id, v_product_name
    FROM public.products p
    JOIN public.shops s ON s.id = p.shop_id
   WHERE p.id = NEW.product_id;
  IF v_seller_id IS NULL THEN RETURN NEW; END IF;
  SELECT COALESCE(NULLIF(pr.full_name, ''), pr.username, 'Bir müşteri')
    INTO v_customer_name
    FROM public.profiles pr WHERE pr.id = NEW.user_id;
  INSERT INTO public.notifications (user_id, type, title, content, entity_id)
  VALUES (
    v_seller_id,
    'seller_new_digital_order',
    'Yeni paket siparişi — teslim bekliyor',
    COALESCE(v_customer_name, 'Bir müşteri') || ', ' ||
      COALESCE(v_product_name, 'dijital paket') || ' paketini satın aldı (₺' ||
      to_char(NEW.gross_total_try, 'FM999999990.00') ||
      '). Teslim edince Dijital Siparişler''den "Tamamlandı" olarak işaretleyin.',
    NEW.id::text
  );
  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  RAISE LOG 'notify_manual_digital_order failed for digital_order %: %', NEW.id, SQLERRM;
  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.notify_manual_digital_order() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trg_digital_orders_manual_notify ON public.digital_orders;
CREATE TRIGGER trg_digital_orders_manual_notify
  AFTER INSERT ON public.digital_orders
  FOR EACH ROW
  WHEN (NEW.delivery_mode = 'manual')
  EXECUTE FUNCTION public.notify_manual_digital_order();

-- ── 2) Durum değişimi → alıcı (tüm teslim şekilleri) ───────────────────────
CREATE OR REPLACE FUNCTION public.notify_digital_order_status()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $$
DECLARE
  v_status text := NEW.status::text;
  v_product text;
  v_refund text;
  v_title text;
  v_content text;
BEGIN
  IF v_status NOT IN ('completed', 'partial', 'canceled', 'refunded', 'failed') THEN
    RETURN NEW;
  END IF;
  SELECT NULLIF(p.name, '') INTO v_product
    FROM public.products p WHERE p.id = NEW.product_id;

  IF NEW.delivery_mode = 'manual' THEN
    v_product := COALESCE(v_product, 'Dijital paket');
    IF v_status = 'completed' THEN
      v_title := 'Paketiniz teslim edildi';
      v_content := v_product || ' siparişiniz satıcı tarafından teslim edildi.';
    ELSIF v_status = 'partial' THEN
      RETURN NEW; -- pakette kısmi teslim yok
    ELSE
      v_title := 'Paket siparişiniz iptal edildi';
      v_content := v_product || ' siparişiniz iptal edildi; ödemeniz puan/TL kaynağına iade edildi.';
    END IF;
  ELSE
    v_product := COALESCE(v_product, 'Dijital');
    -- Kümülatif iade; puan puana, TL bakiyeye döner.
    v_refund := concat_ws(' + ',
      CASE WHEN COALESCE(NEW.refund_cash_total_try, 0) > 0
           THEN '₺' || to_char(NEW.refund_cash_total_try, 'FM999999990.00') || ' bakiye' END,
      CASE WHEN COALESCE(NEW.refund_points_total, 0) > 0
           THEN NEW.refund_points_total::text || ' puan' END);
    IF v_status = 'completed' THEN
      v_title := 'Dijital Siparişiniz Tamamlandı';
      v_content := v_product || ' siparişiniz tamamlandı.';
    ELSIF v_status = 'partial' THEN
      v_title := 'Dijital Siparişiniz Kısmi Tamamlandı';
      v_content := v_product || ' siparişinizin bir kısmı teslim edildi.' ||
        CASE WHEN v_refund <> '' THEN ' Teslim edilmeyen kısmın iadesi: ' || v_refund || '.' ELSE '' END;
    ELSE
      v_title := 'Dijital Siparişiniz İade Edildi';
      v_content := v_product || ' siparişiniz ' ||
        CASE v_status WHEN 'canceled' THEN 'iptal edildi'
                      WHEN 'failed' THEN 'gerçekleştirilemedi'
                      ELSE 'iade edildi' END ||
        CASE WHEN v_refund <> '' THEN '. İade: ' || v_refund || '.'
             ELSE '; ödemeniz puan/TL kaynağına iade edildi.' END;
    END IF;
  END IF;

  INSERT INTO public.notifications (user_id, type, title, content, entity_id, data)
  VALUES (
    NEW.user_id,
    'digital_order_status',
    v_title,
    v_content,
    NEW.id::text,
    jsonb_build_object('digital_order_id', NEW.id, 'status', v_status)
  );
  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  RAISE LOG 'notify_digital_order_status failed for digital_order %: %', NEW.id, SQLERRM;
  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.notify_digital_order_status() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trg_digital_orders_status_notify ON public.digital_orders;
CREATE TRIGGER trg_digital_orders_status_notify
  AFTER UPDATE OF status ON public.digital_orders
  FOR EACH ROW
  WHEN (OLD.status IS DISTINCT FROM NEW.status)
  EXECUTE FUNCTION public.notify_digital_order_status();

-- ── 3) Satıcıya kazanç aktarıldı → yöneticiler ─────────────────────────────
CREATE OR REPLACE FUNCTION public.notify_digital_order_seller_credit()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $$
DECLARE
  v_shop_id uuid;
  v_shop_name text;
  v_product_name text;
BEGIN
  SELECT p.shop_id, s.name, p.name INTO v_shop_id, v_shop_name, v_product_name
    FROM public.products p
    JOIN public.shops s ON s.id = p.shop_id
   WHERE p.id = NEW.product_id;
  INSERT INTO public.notifications (user_id, type, title, content, entity_id, data)
  SELECT pr.id,
         'digital_order_commission',
         'Dijital Sipariş Kazancı',
         COALESCE(v_shop_name, 'Bir') || ' mağazasına ' ||
           COALESCE(v_product_name, 'dijital ürün') || ' satışından ₺' ||
           to_char(COALESCE(NEW.net_seller_amount, 0), 'FM999999990.00') ||
           ' kazanç eklendi (komisyon: ₺' ||
           to_char(COALESCE(NEW.commission_amount, 0), 'FM999999990.00') || ').',
         NEW.id::text,
         jsonb_build_object('digital_order_id', NEW.id, 'shop_id', v_shop_id)
    FROM public.profiles pr
   WHERE pr.role = 'admin';
  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  RAISE LOG 'notify_digital_order_seller_credit failed for digital_order %: %', NEW.id, SQLERRM;
  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.notify_digital_order_seller_credit() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trg_digital_orders_seller_credit_notify ON public.digital_orders;
CREATE TRIGGER trg_digital_orders_seller_credit_notify
  AFTER UPDATE OF seller_credited ON public.digital_orders
  FOR EACH ROW
  WHEN (NEW.seller_credited AND OLD.seller_credited IS DISTINCT FROM NEW.seller_credited)
  EXECUTE FUNCTION public.notify_digital_order_seller_credit();

COMMIT;
