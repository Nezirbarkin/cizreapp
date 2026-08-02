-- ════════════════════════════════════════════════════════════════════════
-- Kupon RPC'leri - Server-Authoritative Sıkılaştırma
-- Tarih: 2026-08-02
-- ════════════════════════════════════════════════════════════════════════
-- SORUN:
--   Mevcut validate_coupon(p_user_id UUID) parametresiyle istemci
--   tarafından çağrılabiliyor; istemci farklı user_id gönderebilir.
--   use_coupon(p_user_id UUID, p_discount_amount NUMERIC) istemcinin
--   istediği discount tutarıyla çağrılabilir; sınır aşılabilir.
--
-- ÇÖZÜM:
--   1) Eski imzalar (p_user_id, p_discount_amount) DROP edilir.
--   2) Yeni RPC'ler sadece SECURITY DEFINER baglamda, yani
--      commit_*_order ve prepare_checkout_session icinden cagrilabilir.
--   3) authenticated EXECUTE kaldirilir.
-- ════════════════════════════════════════════════════════════════════════

-- ════════════════════════════════════════════════════════════════════════
-- 1) validate_coupon — sadece private baglamda, SECURITY DEFINER
-- ════════════════════════════════════════════════════════════════════════
-- ESKİ: validate_coupon(p_shop_id UUID, p_code TEXT, p_subtotal NUMERIC, p_user_id UUID)
-- YENİ: validate_coupon(p_coupon_id UUID, p_subtotal NUMERIC, p_user_id UUID)
--       (artik code yerine UUID; user_id SECURITY DEFINER icinden)
DROP FUNCTION IF EXISTS public.validate_coupon(UUID, TEXT, NUMERIC, UUID);

CREATE OR REPLACE FUNCTION private.validate_coupon(
  p_coupon_id UUID,
  p_subtotal NUMERIC,
  p_user_id UUID
)
RETURNS TABLE (
  id UUID,
  code TEXT,
  discount_type TEXT,
  discount_value NUMERIC,
  maximum_discount_amount NUMERIC,
  minimum_order_amount NUMERIC,
  computed_discount NUMERIC
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_coupon RECORD;
  v_user_usage_count INT;
  v_computed NUMERIC;
BEGIN
  -- p_user_id null olamaz (defensive)
  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'user_id gerekli' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_coupon
  FROM public.shop_coupons
  WHERE id = p_coupon_id
  FOR UPDATE;  -- ayni anda iki commit ayni kupona erisemesin

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Kupon bulunamadi' USING ERRCODE = 'P0002';
  END IF;

  IF NOT v_coupon.is_active THEN
    RAISE EXCEPTION 'Kupon aktif degil' USING ERRCODE = 'P0001';
  END IF;

  IF v_coupon.start_date IS NOT NULL AND v_coupon.start_date > NOW() THEN
    RAISE EXCEPTION 'Kupon henuz baslamadi' USING ERRCODE = 'P0001';
  END IF;

  IF v_coupon.end_date IS NOT NULL AND v_coupon.end_date < NOW() THEN
    RAISE EXCEPTION 'Kuponun suresi dolmus' USING ERRCODE = 'P0001';
  END IF;

  IF v_coupon.minimum_order_amount IS NOT NULL AND p_subtotal < v_coupon.minimum_order_amount THEN
    RAISE EXCEPTION 'Minimum siparis tutari asilmadi' USING ERRCODE = 'P0001';
  END IF;

  IF v_coupon.usage_limit IS NOT NULL AND v_coupon.usage_count >= v_coupon.usage_limit THEN
    RAISE EXCEPTION 'Kupon kullanım limiti doldu' USING ERRCODE = 'P0001';
  END IF;

  IF v_coupon.usage_per_user IS NOT NULL THEN
    SELECT COUNT(*) INTO v_user_usage_count
    FROM public.coupon_usages
    WHERE coupon_id = v_coupon.id AND user_id = p_user_id;

    IF v_user_usage_count >= v_coupon.usage_per_user THEN
      RAISE EXCEPTION 'Kullanici basina kupon limiti doldu' USING ERRCODE = 'P0001';
    END IF;
  END IF;

  -- Indirim hesapla (server authoritative, istemci gondermez)
  IF v_coupon.discount_type = 'percentage' THEN
    v_computed := p_subtotal * (v_coupon.discount_value / 100.0);
  ELSIF v_coupon.discount_type = 'fixed' THEN
    v_computed := v_coupon.discount_value;
  ELSE
    RAISE EXCEPTION 'Bilinmeyen kupon tipi: %', v_coupon.discount_type USING ERRCODE = 'P0001';
  END IF;

  IF v_coupon.maximum_discount_amount IS NOT NULL AND v_computed > v_coupon.maximum_discount_amount THEN
    v_computed := v_coupon.maximum_discount_amount;
  END IF;
  IF v_computed < 0 THEN v_computed := 0; END IF;
  IF v_computed > p_subtotal THEN v_computed := p_subtotal; END IF;

  RETURN QUERY SELECT
    v_coupon.id, v_coupon.code, v_coupon.discount_type::TEXT, v_coupon.discount_value,
    v_coupon.maximum_discount_amount, v_coupon.minimum_order_amount, v_computed;
END;
$$;

REVOKE ALL ON FUNCTION private.validate_coupon(UUID, NUMERIC, UUID) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION private.validate_coupon(UUID, NUMERIC, UUID) TO service_role;

COMMENT ON FUNCTION private.validate_coupon IS
  'Server-internal kupon dogrulama. authenticated/anon EXECUTE YOK. Sadece SECURITY DEFINER commit_*_order / prepare_checkout_session icinden.';

-- ════════════════════════════════════════════════════════════════════════
-- 2) use_coupon — sadece server-authoritative commit context
-- ════════════════════════════════════════════════════════════════════════
-- ESKİ: use_coupon(p_coupon_id UUID, p_order_id UUID, p_user_id UUID, p_discount_amount NUMERIC)
--       (client p_discount_amount gonderebiliyordu; manipule edilebilirdi)
-- YENİ: use_coupon(p_coupon_id UUID, p_order_id UUID)
--       (user_id order'dan, discount server tarafindan hesaplanmis session'dan)
DROP FUNCTION IF EXISTS public.use_coupon(UUID, UUID, UUID, NUMERIC);

CREATE OR REPLACE FUNCTION private.use_coupon(
  p_coupon_id UUID,
  p_order_id UUID
)
RETURNS NUMERIC  -- gercek uygulanan indirim (server hesaplar)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_order RECORD;
  v_coupon RECORD;
  v_user_usage_count INT;
  v_subtotal NUMERIC := 0;
  v_discount NUMERIC := 0;
BEGIN
  -- Order'i user_id ile birlikte al
  SELECT user_id, subtotal, coupon_discount, checkout_session_id
    INTO v_order
  FROM public.orders
  WHERE id = p_order_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Siparis bulunamadi' USING ERRCODE = 'P0002';
  END IF;

  -- Coupon FOR UPDATE kilitle
  SELECT * INTO v_coupon
  FROM public.shop_coupons
  WHERE id = p_coupon_id
  FOR UPDATE;

  IF NOT FOUND OR NOT v_coupon.is_active THEN
    RAISE EXCEPTION 'Kupon gecerli degil' USING ERRCODE = 'P0001';
  END IF;

  -- Idempotency: ayni (coupon, order) zaten kullanilmis mi?
  IF EXISTS (
    SELECT 1 FROM public.coupon_usages
    WHERE coupon_id = p_coupon_id AND order_id = p_order_id
  ) THEN
    -- Idempotent: mevcut discount'i don
    SELECT discount_amount INTO v_discount
    FROM public.coupon_usages
    WHERE coupon_id = p_coupon_id AND order_id = p_order_id;
    RETURN COALESCE(v_discount, 0);
  END IF;

  -- Kullanici basina limit (commit aninda yeniden kontrol)
  IF v_coupon.usage_per_user IS NOT NULL THEN
    SELECT COUNT(*) INTO v_user_usage_count
    FROM public.coupon_usages
    WHERE coupon_id = p_coupon_id AND user_id = v_order.user_id;
    IF v_user_usage_count >= v_coupon.usage_per_user THEN
      RAISE EXCEPTION 'Kullanici basina kupon limiti doldu' USING ERRCODE = 'P0001';
    END IF;
  END IF;

  -- Server-authoritative indirim: order.coupon_discount zaten
  -- prepare_checkout_session tarafindan hesaplanmis server degeri.
  -- Burada KESINLIKLE yeniden hesaplanmaz, client'a da guvenilmez.
  v_discount := COALESCE(v_order.coupon_discount, 0);

  IF v_discount < 0 THEN v_discount := 0; END IF;
  IF v_discount > v_order.subtotal THEN v_discount := v_order.subtotal; END IF;

  -- Coupon usage kaydi
  INSERT INTO public.coupon_usages (coupon_id, order_id, user_id, discount_amount)
  VALUES (p_coupon_id, p_order_id, v_order.user_id, v_discount);

  -- Kullanım sayaci artir
  UPDATE public.shop_coupons
  SET usage_count = usage_count + 1
  WHERE id = p_coupon_id;

  RETURN v_discount;
END;
$$;

REVOKE ALL ON FUNCTION private.use_coupon(UUID, UUID) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION private.use_coupon(UUID, UUID) TO service_role;

COMMENT ON FUNCTION private.use_coupon IS
  'Server-internal kupon kullanım kaydı. authenticated/anon EXECUTE YOK. Discount server-authoritative; client ASLA gonderemez.';

DO $$
BEGIN
  RAISE NOTICE '✅ Kupon RPC''leri sıkılaştırıldı';
  RAISE NOTICE '   - public.validate_coupon (eski imza) DROP edildi';
  RAISE NOTICE '   - public.use_coupon (eski imza) DROP edildi';
  RAISE NOTICE '   - private.validate_coupon + private.use_coupon olusturuldu';
  RAISE NOTICE '   - authenticated EXECUTE revoke edildi';
  RAISE NOTICE '   - service_role EXECUTE (sadece SECURITY DEFINER commit akışı)';
END $$;
