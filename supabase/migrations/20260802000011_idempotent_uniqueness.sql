-- 20260802000011_idempotent_uniqueness.sql
-- Tarih: 2026-08-02
-- Idempotency güçlendirmesi: orders / payment_transactions / server_checkout_sessions
-- üzerinde ek UNIQUE indeksler. Mevcut veriyle çakışırsa NULL geçilir.

SET search_path = public, private;

-- ════════════════════════════════════════════════════════════════════════
-- orders: aynı user + checkout_session ile iki sipariş olmasın
-- (commit_online_order idempotency kontrolü bu indekse dayanır)
-- ════════════════════════════════════════════════════════════════════════
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_indexes
    WHERE schemaname = 'public' AND indexname = 'orders_user_session_uniq'
  ) THEN
    CREATE UNIQUE INDEX orders_user_session_uniq
      ON public.orders (user_id, checkout_session_id)
      WHERE checkout_session_id IS NOT NULL;
  END IF;
END $$;

-- ════════════════════════════════════════════════════════════════════════
-- payment_transactions: (user_id, idempotency_key) benzersiz
-- ════════════════════════════════════════════════════════════════════════
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_indexes
    WHERE schemaname = 'public' AND indexname = 'payment_tx_user_idem_uniq'
  ) THEN
    CREATE UNIQUE INDEX payment_tx_user_idem_uniq
      ON public.payment_transactions (user_id, idempotency_key)
      WHERE idempotency_key IS NOT NULL;
  END IF;
END $$;

-- ════════════════════════════════════════════════════════════════════════
-- payment_transactions: token benzersiz (pending/finalized fark etmez)
-- Aynı token ile iki kez farklı kayıt oluşmasını engeller
-- ════════════════════════════════════════════════════════════════════════
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_indexes
    WHERE schemaname = 'public' AND indexname = 'payment_tx_token_uniq'
  ) THEN
    CREATE UNIQUE INDEX payment_tx_token_uniq
      ON public.payment_transactions (token)
      WHERE token IS NOT NULL;
  END IF;
END $$;

-- ════════════════════════════════════════════════════════════════════════
-- order_items: (order_id, product_id, variant_id) benzersiz
-- Aynı ürün+variant iki satır olamaz (miktarlar birleşir)
-- ════════════════════════════════════════════════════════════════════════
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_indexes
    WHERE schemaname = 'public' AND indexname = 'order_items_unique_line'
  ) THEN
    CREATE UNIQUE INDEX order_items_unique_line
      ON public.order_items (order_id, product_id, COALESCE(variant_id, '00000000-0000-0000-0000-000000000000'::UUID));
  END IF;
END $$;
