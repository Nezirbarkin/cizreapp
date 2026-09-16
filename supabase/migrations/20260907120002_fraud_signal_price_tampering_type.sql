-- =============================================================================
-- fraud_signals: 'price_tampering' sinyal türünü tanımla
-- =============================================================================
-- 20260907120001 fiyat manipülasyonunu sunucuda düzeltiyor ve her düzeltmeyi
-- fraud_signals'a yazmayı deniyordu. Ancak tablodaki
--   fraud_signals_signal_type_check
-- yalnız şu 4 değere izin veriyor:
--   multiple_accounts, unusual_returns, coupon_abuse, fake_reviews
--
-- Bu yüzden kayıt CHECK ihlaliyle düşüyordu. Trigger içindeki EXCEPTION
-- bloğu hatayı yuttuğu için sipariş akışı bozulmadı (tasarım gereği), ama
-- admin paneli manipülasyon denemelerini göremiyordu — kanıtlandı:
-- saldırı simülasyonunda fiyat düzeltildi, fraud kaydı 0 kaldı.
--
-- Burada tür listesine 'price_tampering' ekleniyor ve trigger bu türü
-- kullanacak şekilde güncelleniyor.
-- =============================================================================

BEGIN;

ALTER TABLE public.fraud_signals
  DROP CONSTRAINT IF EXISTS fraud_signals_signal_type_check;

ALTER TABLE public.fraud_signals
  ADD CONSTRAINT fraud_signals_signal_type_check
  CHECK (signal_type = ANY (ARRAY[
    'multiple_accounts'::text,
    'unusual_returns'::text,
    'coupon_abuse'::text,
    'fake_reviews'::text,
    'price_tampering'::text
  ]));

-- -----------------------------------------------------------------------------
-- Trigger'ı geçerli sinyal türüyle güncelle
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

  IF v_expected IS NOT NULL AND v_claimed < v_expected - 0.01 THEN
    BEGIN
      SELECT o.user_id INTO v_user FROM public.orders o WHERE o.id = NEW.order_id;

      IF v_user IS NOT NULL THEN
        INSERT INTO public.fraud_signals (
          user_id, signal_type, severity, risk_score, title, description,
          evidence, fingerprint
        ) VALUES (
          v_user, 'price_tampering', 'critical', 95,
          'Siparis kalemi fiyati sunucu fiyatinin altinda',
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
          'price_tampering:' || COALESCE(NEW.product_id::text, '-')
        )
        -- Ayni kullanici + ayni urun icin tekrar denerse yeni satir yerine
        -- sayaci artir (UNIQUE(user_id, signal_type, fingerprint)).
        ON CONFLICT (user_id, signal_type, fingerprint) DO UPDATE
          SET occurrence_count  = public.fraud_signals.occurrence_count + 1,
              last_detected_at  = NOW(),
              status            = CASE WHEN public.fraud_signals.status = 'dismissed'
                                       THEN 'open' ELSE public.fraud_signals.status END,
              evidence          = EXCLUDED.evidence,
              updated_at        = NOW();
      END IF;
    EXCEPTION WHEN OTHERS THEN
      -- Kayit tutulamazsa siparis akisi ASLA durmasin.
      NULL;
    END;

    NEW.price := v_expected;
  END IF;

  NEW.product_price := NEW.price;
  NEW.subtotal      := ROUND(COALESCE(NEW.price, 0) * NEW.quantity, 2);

  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION private.enforce_order_item_price() FROM PUBLIC;

COMMIT;

NOTIFY pgrst, 'reload schema';
