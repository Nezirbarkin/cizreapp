-- ════════════════════════════════════════════════════════════════════════
-- FIX: payment_transactions tablosunda aynı token ile birden fazla
--       aktif (pending) kayıt oluşmasını engelle
-- Tarih: 2026-06-30
--
-- Kök Neden: iyzico-payment-init'te token NULL olarak insert ediliyor,
-- sonra iyzico'dan gelen token ile UPDATE yapılıyor. Eğer aynı anda
-- iki init çağrısı olursa (cold start, network retry) veya sandbox'ta
-- token reuse yapılırsa, aynı token ile birden fazla pending transaction
-- oluşabiliyor. Callback geldiğinde getPaymentTransaction bunlardan
-- yanlış olanı buluyor → "Bu sipariş zaten oluşturulmuştur" hatası.
--
-- Çözüm: Pending transaction'larda token unique olmalı. Success/failure/
-- cancelled transaction'lar için unique constraint yok (iyzico token reuse
-- yapabilir, bu normal).
-- ════════════════════════════════════════════════════════════════════════

-- Önce mevcut duplicate'leri temizle (varsa)
-- Aynı token'a sahip birden fazla PENDING kayıt varsa en eskisini tut
-- (diğerlerini cancelled yap)
DO $$
DECLARE
  v_dup_count INTEGER := 0;
BEGIN
  -- Aynı token'a sahip pending kayıtlardan en eski olmayanları cancelled yap
  UPDATE payment_transactions pt1
  SET payment_status = 'cancelled',
      updated_at = NOW(),
      callback_data = jsonb_build_object(
        'auto_cancelled_reason', 'duplicate_pending_token_cleanup',
        'cancelled_at', NOW()
      ) || COALESCE(callback_data, '{}'::jsonb)
  WHERE pt1.payment_status = 'pending'
    AND EXISTS (
      SELECT 1 FROM payment_transactions pt2
      WHERE pt2.token = pt1.token
        AND pt2.payment_status = 'pending'
        AND pt2.created_at < pt1.created_at
    );

  GET DIAGNOSTICS v_dup_count = ROW_COUNT;

  IF v_dup_count > 0 THEN
    RAISE NOTICE '% adet duplicate pending transaction cancelled edildi', v_dup_count;
  END IF;
END $$;

-- Partial unique index: sadece PENDING kayıtlar için token unique olmalı
CREATE UNIQUE INDEX IF NOT EXISTS idx_payment_transactions_pending_token_unique
ON public.payment_transactions (token)
WHERE payment_status = 'pending'
  AND token IS NOT NULL;

-- Mevcut token index'i de ekleyelim (lookup performansı)
CREATE INDEX IF NOT EXISTS idx_payment_transactions_token_status
ON public.payment_transactions (token, payment_status);

-- Yorum
COMMENT ON INDEX idx_payment_transactions_pending_token_unique IS
  'Aynı token ile sadece 1 pending transaction olabilir. Duplicate callback/init prevention. 2026-06-30 eklendi.';