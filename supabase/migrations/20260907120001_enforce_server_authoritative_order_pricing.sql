-- =============================================================================
-- Sipariş fiyatlarını sunucu otoritesine bağla (fiyat manipülasyonu kapatma)
-- =============================================================================
-- SORUN
-- -----
-- İstemci `orders` ve `order_items` satırlarını DOĞRUDAN yazıyor
-- (lib/features/shop/services/order_service.dart:88 ve :725) ve tüm
-- finansal alanları kendisi belirliyor:
--     orders.subtotal / total / discount / delivery_fee
--     order_items.price / product_price / subtotal
--
-- Canlı RLS bunları hiç doğrulamıyor:
--     orders_insert_policy      WITH CHECK (user_id = auth.uid())
--     order_items_insert        WITH CHECK (siparişin sahibi mi)
--
-- `orders` üzerindeki 16 trigger'ın hiçbiri tutar doğrulaması yapmıyor;
-- `calculate_order_commission` ise BEFORE INSERT olduğu için komisyonu
-- İSTEMCİNİN verdiği tutardan hesaplıyor. Sonuç: anon key APK içinde
-- gömülü olduğundan (lib/core/constants/app_constants.dart:12) herkes
-- REST ile 10.000 TL'lik ürüne 0,01 TL'lik gerçek sipariş açabiliyor;
-- satıcı hakedişi ve dükkan bakiyesi de bu sahte tutardan besleniyor.
--
-- Bu üç ödeme yolunun üçünü birden etkiliyor: kapıda ödeme, bakiye
-- (use_balance_for_order tutarı orders.total'dan okuyor) ve iyzico.
--
-- ÇÖZÜM
-- -----
-- Kalıcı çözüm, hazır ama bağlanmamış olan sunucu-otoriter checkout
-- akışıdır (private.prepare_checkout_session + commit_*). O akış istemci
-- sürümü gerektiriyor. Bu migration ARADAKİ boşluğu SUNUCU TARAFINDA,
-- istemci güncellemesi gerektirmeden kapatır:
--
--   1. order_items.price sunucudaki gerçek fiyatın ALTINA düşemez.
--   2. order_items.subtotal her zaman price * quantity olarak yazılır.
--   3. orders.subtotal/total kalemlerden yeniden hesaplanır.
--   4. Komisyon alanları düzeltilmiş tutarla yeniden hesaplanır.
--   5. Her düzeltme fraud_signals'a kaydedilir.
--
-- YANLIŞ POZİTİF RİSKİ: YOK (canlı veriyle ölçüldü, 2026-09-07)
--   son 60 gün / 11 sipariş kalemi:  price < beklenen  -> 0 kayıt
--   son 90 gün / 12 sipariş:         total formülü sapması -> 0 kayıt
--   yani kural, uygulamanın hâlihazırda ürettiği değerlerle birebir örtüşüyor.
-- =============================================================================

BEGIN;

-- -----------------------------------------------------------------------------
-- 1) Otoriter birim fiyat
-- -----------------------------------------------------------------------------
-- flash_sale_id verilmişse fiyat flash_sales tablosundan okunur. Kampanya
-- penceresi BİLEREK kontrol edilmez: flash_price zaten sunucu verisidir
-- (istemci belirleyemez) ve pencere kontrolü claim_flash_sale'de yapılır.
-- Burada pencere kontrolü yapmak, kampanya sipariş anında biterse müşteriyi
-- yüksek fiyata çıkarma riski doğururdu.
CREATE OR REPLACE FUNCTION private.authoritative_item_price(
  p_product_id    uuid,
  p_flash_sale_id uuid
)
RETURNS numeric
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_price numeric;
BEGIN
  IF p_flash_sale_id IS NOT NULL THEN
    SELECT fs.flash_price
      INTO v_price
      FROM public.flash_sales fs
     WHERE fs.id = p_flash_sale_id
       AND fs.product_id = p_product_id
       AND fs.flash_price IS NOT NULL
       AND fs.flash_price >= 0;
    IF v_price IS NOT NULL THEN
      RETURN v_price;
    END IF;
  END IF;

  -- SMM ürünleri (price_per_1000) farklı fiyat modeline sahip; onlara
  -- dokunmuyoruz -> NULL dönersek çağıran clamp uygulamaz.
  SELECT CASE
           WHEN p.price_per_1000 IS NOT NULL THEN NULL
           WHEN p.discount_price IS NOT NULL
                AND p.discount_price > 0
                AND p.discount_price < p.price
             THEN p.discount_price
           ELSE p.price
         END
    INTO v_price
    FROM public.products p
   WHERE p.id = p_product_id;

  RETURN v_price;  -- ürün yoksa NULL -> clamp yok
END;
$$;

REVOKE ALL ON FUNCTION private.authoritative_item_price(uuid, uuid) FROM PUBLIC;

-- -----------------------------------------------------------------------------
-- 2) order_items: fiyat tabanı + subtotal zorlaması
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION private.enforce_order_item_price()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_expected numeric;
  v_claimed  numeric := COALESCE(NEW.price, 0);
  v_user     uuid;
BEGIN
  IF NEW.quantity IS NULL OR NEW.quantity < 1 THEN
    RAISE EXCEPTION 'order_items.quantity gecersiz: %', NEW.quantity
      USING ERRCODE = '22023';
  END IF;

  v_expected := private.authoritative_item_price(NEW.product_id, NEW.flash_sale_id);

  -- Yalnız İSTEMCİ FİYATI SUNUCUDAKİNDEN DÜŞÜKSE müdahale ediyoruz.
  -- Yüksek fiyat serbest bırakılıyor: geçmiş veride ürün fiyatı sipariş
  -- sonrası düşürüldüğü için 8/11 kalem "beklenenin üstünde" görünüyor;
  -- bunlara dokunmak meşru siparişleri bozardı.
  IF v_expected IS NOT NULL AND v_claimed < v_expected - 0.01 THEN
    BEGIN
      SELECT o.user_id INTO v_user FROM public.orders o WHERE o.id = NEW.order_id;
      INSERT INTO public.fraud_signals (
        user_id, signal_type, severity, risk_score, title, description,
        evidence, fingerprint
      ) VALUES (
        COALESCE(v_user, '00000000-0000-0000-0000-000000000000'::uuid),
        'order_item_price_tampering', 'high', 90,
        'Sipariş kalemi fiyatı sunucu fiyatının altında',
        format('Istemci %s TL bildirdi, sunucu fiyati %s TL. Fiyat sunucu degerine yukseltildi.',
               v_claimed, v_expected),
        jsonb_build_object(
          'order_id',      NEW.order_id,
          'product_id',    NEW.product_id,
          'flash_sale_id', NEW.flash_sale_id,
          'claimed_price', v_claimed,
          'server_price',  v_expected,
          'quantity',      NEW.quantity
        ),
        'order_item_price_tampering:' || COALESCE(NEW.order_id::text, '-')
          || ':' || COALESCE(NEW.product_id::text, '-')
      );
    EXCEPTION WHEN OTHERS THEN
      -- Kayıt tutulamazsa sipariş akışı ASLA durmasın.
      NULL;
    END;

    NEW.price := v_expected;
  END IF;

  -- product_price ve subtotal her zaman türetilir; istemci bunlarda
  -- bagimsiz bir deger tasiyamaz.
  NEW.product_price := NEW.price;
  NEW.subtotal      := ROUND(COALESCE(NEW.price, 0) * NEW.quantity, 2);

  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION private.enforce_order_item_price() FROM PUBLIC;

DROP TRIGGER IF EXISTS trg_enforce_order_item_price ON public.order_items;
CREATE TRIGGER trg_enforce_order_item_price
  BEFORE INSERT OR UPDATE ON public.order_items
  FOR EACH ROW
  EXECUTE FUNCTION private.enforce_order_item_price();

-- -----------------------------------------------------------------------------
-- 3) orders toplamlarını kalemlerden yeniden hesapla
-- -----------------------------------------------------------------------------
-- Yalnız status='pending' siparişlerde çalışır: onaylanmış/teslim edilmiş
-- siparişlerin tutarları geriye dönük değişmemeli.
--
-- Formül, canlı veriyle doğrulandı: son 90 günün 12 siparişinin TAMAMINDA
--   total = subtotal + delivery_fee - discount - coupon_discount
-- birebir tutuyor. Yani bu yeniden hesaplama meşru siparişlerde no-op'tur.
CREATE OR REPLACE FUNCTION private.resync_order_totals()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_order_id  uuid := COALESCE(NEW.order_id, OLD.order_id);
  v_subtotal  numeric;
  v_order     record;
  v_discount  numeric;
  v_coupon    numeric;
  v_total     numeric;
BEGIN
  SELECT o.* INTO v_order FROM public.orders o WHERE o.id = v_order_id;
  IF NOT FOUND OR v_order.status IS DISTINCT FROM 'pending'::public.order_status THEN
    RETURN COALESCE(NEW, OLD);
  END IF;

  SELECT COALESCE(SUM(oi.subtotal), 0)
    INTO v_subtotal
    FROM public.order_items oi
   WHERE oi.order_id = v_order_id;

  -- İndirimler ara toplamı aşamaz (negatif toplam üretmesin).
  v_discount := LEAST(GREATEST(COALESCE(v_order.discount, 0), 0), v_subtotal);
  v_coupon   := LEAST(GREATEST(COALESCE(v_order.coupon_discount, 0), 0),
                      GREATEST(v_subtotal - v_discount, 0));
  v_total    := ROUND(GREATEST(
                  v_subtotal + GREATEST(COALESCE(v_order.delivery_fee, 0), 0)
                  - v_discount - v_coupon, 0), 2);

  IF ABS(COALESCE(v_order.subtotal, 0) - v_subtotal) > 0.01
     OR ABS(COALESCE(v_order.total, 0) - v_total) > 0.01
     OR COALESCE(v_order.discount, 0) <> v_discount
     OR COALESCE(v_order.coupon_discount, 0) <> v_coupon
  THEN
    UPDATE public.orders
       SET subtotal        = v_subtotal,
           discount        = v_discount,
           coupon_discount = v_coupon,
           total           = v_total,
           updated_at      = NOW()
     WHERE id = v_order_id;
  END IF;

  RETURN COALESCE(NEW, OLD);
END;
$$;

REVOKE ALL ON FUNCTION private.resync_order_totals() FROM PUBLIC;

DROP TRIGGER IF EXISTS trg_resync_order_totals ON public.order_items;
CREATE TRIGGER trg_resync_order_totals
  AFTER INSERT OR UPDATE OR DELETE ON public.order_items
  FOR EACH ROW
  EXECUTE FUNCTION private.resync_order_totals();

-- -----------------------------------------------------------------------------
-- 4) Komisyonu düzeltilmiş tutarla yeniden hesapla
-- -----------------------------------------------------------------------------
-- calculate_order_commission şu an SADECE BEFORE INSERT. Sipariş kalemleri
-- ayrı bir HTTP isteğiyle (ayrı transaction) sonradan geldiği için, adım
-- 3'teki düzeltme komisyonu güncel bırakmıyordu. Aynı fonksiyonu pending
-- siparişlerde tutar değişiminde de çalıştırıyoruz — fonksiyon yalnız NEW
-- okuyup NEW yazdığı için UPDATE bağlamında da güvenli/idempotent.
DROP TRIGGER IF EXISTS calculate_order_commission_on_total_change ON public.orders;
CREATE TRIGGER calculate_order_commission_on_total_change
  BEFORE UPDATE OF subtotal, total, delivery_fee ON public.orders
  FOR EACH ROW
  WHEN (NEW.status = 'pending'::public.order_status)
  EXECUTE FUNCTION public.calculate_order_commission();

COMMIT;

NOTIFY pgrst, 'reload schema';
