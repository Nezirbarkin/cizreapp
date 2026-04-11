-- ============================================================================
-- FIX: shops tablosuna paid_at kolonu ekle
-- ============================================================================
-- Hata: PostgrestException(message: column "paid_at" of relation "shops" does not exist)
-- Sebep: clear_shop_balance() trigger fonksiyonu paid_at kolonuna yazmaya çalışıyor
--        ama bu kolon shops tablosunda hiç oluşturulmamış.
-- Çözüm: Kolonu ekle
-- ============================================================================

ALTER TABLE public.shops
  ADD COLUMN IF NOT EXISTS paid_at TIMESTAMPTZ;

COMMENT ON COLUMN public.shops.paid_at IS 'Son ödeme yapılma tarihi (admin ödeme yaptığında güncellenir)';

DO $$
BEGIN
  RAISE NOTICE '✅ shops tablosuna paid_at kolonu eklendi';
END $$;
