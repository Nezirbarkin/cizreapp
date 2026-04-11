-- ============================================================================
-- FIX: shops tablosuna paid_at kolonu ekle
-- ============================================================================
-- Hata: PostgrestException(message: column "paid_at" of relation "shops" does not exist)
-- Sebep: clear_shop_balance() trigger fonksiyonu paid_at kolonuna yazmaya çalışıyor
--        ama bu kolon shops tablosunda hiç oluşturulmamış.
-- Çözüm: Kolonu ekle
-- ============================================================================

-- Shops tablosuna paid_at kolonu ekle (eğer yoksa)
ALTER TABLE public.shops
  ADD COLUMN IF NOT EXISTS paid_at TIMESTAMPTZ;

-- Yorum ekle
COMMENT ON COLUMN public.shops.paid_at IS 'Son ödeme yapılma tarihi (admin ödeme yaptığında güncellenir)';

-- Başarı mesajı
DO $$
BEGIN
  RAISE NOTICE '✅ shops tablosuna paid_at kolonu eklendi';
  RAISE NOTICE 'Artık ödeme işlemi sorunsuz çalışacak';
END $$;

-- Kontrol: Kolonun eklendiğini doğrula
SELECT 
  column_name, 
  data_type, 
  is_nullable,
  column_default
FROM information_schema.columns
WHERE table_schema = 'public' 
  AND table_name = 'shops' 
  AND column_name = 'paid_at';
