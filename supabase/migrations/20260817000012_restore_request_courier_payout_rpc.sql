-- =============================================================================
-- Kurye odeme istegi RPC'sini geri yukle ve PostgREST schema cache'ini yenile.
--
-- Duzeltilen hata:
--   PGRST202: Could not find public.request_courier_payout(p_idempotency_key)
--
-- Istemci sozlesmesi:
--   request_courier_payout(p_idempotency_key uuid)
-- =============================================================================

SET search_path = public, pg_temp;
SET LOCAL lock_timeout = '5s';

ALTER TABLE public.courier_payout_requests
  ADD COLUMN IF NOT EXISTS idempotency_key uuid;

-- Ayni kurye + anahtar icin tek sonuc garanti edilir. Index olusturmadan once
-- eski veride tekrar varsa migration'in sessizce yanlis davranmasi yerine net
-- bir hata vermesi daha guvenlidir.
DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM public.courier_payout_requests AS cpr
    WHERE cpr.idempotency_key IS NOT NULL
    GROUP BY cpr.courier_id, cpr.idempotency_key
    HAVING count(*) > 1
  ) THEN
    RAISE EXCEPTION
      'courier_payout_requests icinde tekrar eden (courier_id, idempotency_key) kaydi var';
  END IF;
END;
$$;

CREATE UNIQUE INDEX IF NOT EXISTS uq_courier_payout_courier_idempotency
  ON public.courier_payout_requests (courier_id, idempotency_key)
  WHERE idempotency_key IS NOT NULL;

-- Canli ortamda kalmis olabilecek eski/uyumsuz overload'u temizle. PostgREST,
-- ayni parametre adina sahip text ve uuid overload'lari birlikteyken cagrinin
-- hangi fonksiyona gidecegini belirleyemeyebilir.
DROP FUNCTION IF EXISTS public.request_courier_payout(text);
DROP FUNCTION IF EXISTS public.request_courier_payout(uuid);

CREATE FUNCTION public.request_courier_payout(p_idempotency_key uuid)
RETURNS TABLE(
  payout_id uuid,
  amount numeric,
  item_count integer
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_uid         CONSTANT uuid := (SELECT auth.uid());
  v_payout_id   uuid;
  v_amount      numeric(12, 2);
  v_count       integer;
  v_earning_ids uuid[];
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'APP:auth_required' USING ERRCODE = '42501';
  END IF;

  IF NOT public.is_courier_role() THEN
    RAISE EXCEPTION 'APP:forbidden' USING ERRCODE = '42501';
  END IF;

  IF p_idempotency_key IS NULL THEN
    RAISE EXCEPTION 'APP:idempotency_key_required' USING ERRCODE = '22023';
  END IF;

  -- Ayni kuryeden gelen es zamanli istekleri siraya al. Boylece iki istek de
  -- pending earnings listesini ayni anda okuyup iki payout olusturamaz.
  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(v_uid::text, 71005)
  );

  -- Idempotency kontrolu acik payout kontrolunden once yapilmalidir. Mobil
  -- istemci timeout sonrasi ayni anahtarla tekrar denerse mevcut sonucu alir.
  SELECT cpr.id, cpr.amount
    INTO v_payout_id, v_amount
  FROM public.courier_payout_requests AS cpr
  WHERE cpr.courier_id = v_uid
    AND cpr.idempotency_key = p_idempotency_key
  LIMIT 1;

  IF v_payout_id IS NOT NULL THEN
    SELECT count(*)::integer
      INTO v_count
    FROM public.courier_payout_items AS cpi
    WHERE cpi.payout_id = v_payout_id;

    RETURN QUERY SELECT v_payout_id, v_amount, v_count;
    RETURN;
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.courier_payout_requests AS cpr
    WHERE cpr.courier_id = v_uid
      AND cpr.status = 'pending'
  ) THEN
    RAISE EXCEPTION 'APP:open_payout_exists | zaten bekleyen bir payout var'
      USING ERRCODE = 'P0001';
  END IF;

  -- Odeme kapsamindaki kazanc satirlarini transaction sonuna kadar kilitle.
  SELECT
    pg_catalog.array_agg(locked.id),
    COALESCE(pg_catalog.sum(locked.amount)::numeric, 0::numeric),
    pg_catalog.count(*)::integer
  INTO v_earning_ids, v_amount, v_count
  FROM (
    SELECT ce.id, ce.amount
    FROM public.courier_earnings AS ce
    WHERE ce.courier_id = v_uid
      AND ce.status = 'pending'
    ORDER BY ce.id
    FOR UPDATE
  ) AS locked;

  IF v_count = 0 THEN
    RAISE EXCEPTION 'APP:no_pending_earnings' USING ERRCODE = 'P0001';
  END IF;

  INSERT INTO public.courier_payout_requests (
    courier_id,
    amount,
    status,
    requested_at,
    idempotency_key
  ) VALUES (
    v_uid,
    v_amount,
    'pending',
    pg_catalog.now(),
    p_idempotency_key
  )
  RETURNING id INTO v_payout_id;

  INSERT INTO public.courier_payout_items (
    payout_id,
    earning_id,
    amount_snapshot,
    status
  )
  SELECT
    v_payout_id,
    ce.id,
    ce.amount,
    'pending'
  FROM public.courier_earnings AS ce
  WHERE ce.id = ANY(v_earning_ids);

  UPDATE public.courier_earnings AS ce
  SET status = 'requested'
  WHERE ce.id = ANY(v_earning_ids);

  INSERT INTO public.notifications (
    user_id,
    type,
    title,
    content,
    metadata,
    is_read
  )
  SELECT
    p.id,
    'courier_payout_request',
    'Yeni kurye odeme istegi',
    'Bir kurye odeme istegi gonderdi.',
    pg_catalog.jsonb_build_object(
      'courier_id', v_uid,
      'amount', v_amount,
      'payout_id', v_payout_id
    ),
    false
  FROM public.profiles AS p
  WHERE p.role::text = 'admin';

  RETURN QUERY SELECT v_payout_id, v_amount, v_count;
END;
$$;

REVOKE ALL ON FUNCTION public.request_courier_payout(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.request_courier_payout(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.request_courier_payout(uuid) TO authenticated;

COMMENT ON FUNCTION public.request_courier_payout(uuid) IS
  'Kimligi dogrulanmis kuryenin pending kazanc satirlarindan atomik ve idempotent odeme istegi olusturur.';

-- NOTIFY transaction commit oldugunda PostgREST'e ulasir ve yeni RPC imzasinin
-- schema cache'e hemen alinmasini saglar.
NOTIFY pgrst, 'reload schema';

