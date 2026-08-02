-- ============================================================================
-- SİPARİŞ TABLOSUNA TESLİM EDEN KURYE BİLGİSİ SÜTUNLARI EKLE
-- ============================================================================
-- Amaç: Kurye bir siparişi teslim ettiğinde, kim tarafından teslim edildiği
-- bilgisini orders tablosunda da saklamak. Böylece satıcı/admin panelleri
-- courier_assignments join'ine bağımlı kalmadan (RLS/sorgu sorunlarına düşmeden)
-- doğrudan orders kaydından kurye bilgisini gösterebilir.
--
-- Çalıştırma: Supabase Dashboard > SQL Editor > bu dosyayı yapıştır > Run
-- ============================================================================

-- 1) orders tablosuna teslim kurye adı ve telefonu ekle
ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS delivered_courier_name TEXT;

ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS delivered_courier_phone TEXT;

ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS delivered_courier_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL;

-- 2) Mevcut teslim edilmiş siparişler için geriye dönük doldurma
-- courier_assignments kaydı varsa orders'a kopyala
UPDATE public.orders o
SET
  delivered_courier_id = ca.courier_id,
  delivered_courier_name = p.full_name,
  delivered_courier_phone = p.phone
FROM public.courier_assignments ca
LEFT JOIN public.profiles p ON p.id = ca.courier_id
WHERE ca.order_id = o.id
  AND ca.status = 'delivered'
  AND o.status = 'delivered';

-- 3) RLS: Kurye bilgisi orders ile aynı erişim politikalarına tabi (ekstra gerek yok)

DO $$
BEGIN
    RAISE NOTICE '✅ orders tablosuna delivered_courier_name/phone/id sütunları eklendi.';
    RAISE NOTICE '✅ Mevcut delivered siparişler için kurye bilgisi geriye dönük dolduruldu.';
END $$;