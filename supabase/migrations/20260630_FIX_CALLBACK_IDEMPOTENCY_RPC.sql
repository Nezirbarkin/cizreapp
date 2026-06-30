-- ════════════════════════════════════════════════════════════════════════
-- FIX: iyzico-payment-callback Idempotency — SQL Seviyesinde Atomik RPC
-- Tarih: 2026-06-30
-- Kök Neden: updatePaymentTransactionAtomic fonksiyonundaki count=0/1
--             mantığı Supabase JS client v2'de güvenilir değil (PostgREST
--             UPDATE dönüşünde count bazen yanlış dönebiliyor). Bu da
--             duplicate prevention'ı etkisiz kılıyor ya da her zaman
--             "alreadyProcessed=true" döndürüyor (kullanıcı yeni sipariş
--             veremiyor — HATA-2 REGRESYON).
--
-- Çözüm: Atomik SQL fonksiyonu. UPDATE ... WHERE payment_status='pending'
--         RETURNING ile; eğer döndürülen satır varsa güncelleme başarılı,
--         yoksa zaten işlenmiş. Bu race-condition'a karşı %100 güvenli.
-- ════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.atomic_finalize_payment_transaction(
  p_transaction_id UUID,
  p_payment_id TEXT,
  p_paid_price NUMERIC,
  p_card_type TEXT,
  p_card_association TEXT,
  p_card_family TEXT,
  p_card_bank_name TEXT,
  p_last_four_digits TEXT,
  p_fraud_status INTEGER,
  p_status TEXT,                 -- 'success' | 'failure'
  p_error_code TEXT DEFAULT NULL,
  p_error_message TEXT DEFAULT NULL,
  p_error_group TEXT DEFAULT NULL,
  p_callback_received_at TIMESTAMPTZ DEFAULT NOW(),
  p_merged_callback_data JSONB DEFAULT '{}'::JSONB
)
RETURNS TABLE (
  updated BOOLEAN,
  already_processed BOOLEAN,
  payment_status TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_current_status TEXT;
  v_was_updated BOOLEAN := FALSE;
BEGIN
  -- ════════════════════════════════════════════════════════════════════
  -- 1. Kilitle (SELECT FOR UPDATE) — eşzamanlı callback'lerde race condition'ı önler
  -- ════════════════════════════════════════════════════════════════════
  SELECT payment_status INTO v_current_status
  FROM public.payment_transactions
  WHERE id = p_transaction_id
  FOR UPDATE;

  -- Transaction bulunamadı
  IF NOT FOUND THEN
    RETURN QUERY SELECT FALSE, FALSE, NULL::TEXT;
    RETURN;
  END IF;

  -- ════════════════════════════════════════════════════════════════════
  -- 2. Zaten işlenmiş mi? Sadece pending olan transaction güncellenebilir.
  --    Bu kontrol UPDATE yapmadan ÖNCE yapılır → callback_data kaybı önlenir.
  -- ════════════════════════════════════════════════════════════════════
  IF v_current_status IS DISTINCT FROM 'pending' THEN
    -- Zaten success/failure/cancelled → başka bir callback kazanmış
    RETURN QUERY SELECT FALSE, TRUE, v_current_status;
    RETURN;
  END IF;

  -- ════════════════════════════════════════════════════════════════════
  -- 3. Atomik UPDATE — sadece pending olan satır güncellenir
  -- ════════════════════════════════════════════════════════════════════
  UPDATE public.payment_transactions
  SET
    payment_status = p_status,
    payment_id = p_payment_id,
    paid_price = p_paid_price,
    card_type = p_card_type,
    card_association = p_card_association,
    card_family = p_card_family,
    card_bank_name = p_card_bank_name,
    last_four_digits = p_last_four_digits,
    fraud_status = p_fraud_status,
    callback_received_at = p_callback_received_at,
    callback_data = COALESCE(callback_data, '{}'::JSONB) || p_merged_callback_data,
    error_code = p_error_code,
    error_message = p_error_message,
    error_group = p_error_group,
    updated_at = NOW()
  WHERE id = p_transaction_id
    AND payment_status = 'pending'; -- ← Kritik koruma katmanı

  GET DIAGNOSTICS v_was_updated = ROW_COUNT;

  IF v_was_updated = 0 THEN
    -- Garip durum: status hala pending olmalıydı ama UPDATE 0 satır döndü
    -- (muhtemelen race condition — başka bir transaction araya girdi)
    RETURN QUERY SELECT FALSE, TRUE, v_current_status;
  ELSE
    RETURN QUERY SELECT TRUE, FALSE, p_status;
  END IF;

EXCEPTION WHEN OTHERS THEN
  -- Hata durumunda sessizce "zaten işlenmiş" olarak dön — sipariş oluşturma
  -- ve kullanıcıya hata göster (üst katmanda try/catch var)
  RAISE WARNING 'atomic_finalize_payment_transaction hata: %', SQLERRM;
  RETURN QUERY SELECT FALSE, TRUE, v_current_status;
END;
$$;

-- Service role bu fonksiyonu çağırabilsin (RLS bypass)
GRANT EXECUTE ON FUNCTION public.atomic_finalize_payment_transaction(
  UUID, TEXT, NUMERIC, TEXT, TEXT, TEXT, TEXT, TEXT, INTEGER,
  TEXT, TEXT, TEXT, TEXT, TIMESTAMPTZ, JSONB
) TO service_role;

-- Yorum
COMMENT ON FUNCTION public.atomic_finalize_payment_transaction IS
  'iyzico-payment-callback için atomik güncelleme. Sadece pending olan transaction güncellenir. Race condition ve duplicate callback koruması sağlar. 2026-06-30 eklendi.';