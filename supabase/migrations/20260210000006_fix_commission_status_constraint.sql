-- Sipariş commission_status hatası düzeltmesi
-- Yeni status değerlerini ekle

-- 1. Önce mevcut verileri güncelle (constraint ihlali olmasın diye)
UPDATE public.orders
SET commission_status =
  CASE
    -- Kuryesi varsa ve kapıda ödeme ise
    WHEN seller_has_own_courier = true AND payment_method IN ('cash', 'card_on_delivery') THEN 'cash_collected'
    -- Diğer durumlar
    ELSE 'admin_collects'
  END
WHERE commission_status IS NULL
   OR commission_status NOT IN ('pending', 'debt', 'credit', 'cash_collected', 'admin_collects');

-- 2. Mevcut constraint'i kaldır
ALTER TABLE public.orders DROP CONSTRAINT IF EXISTS orders_commission_status_check;

-- 3. Yeni constraint ekle (yeni status değerleriyle)
ALTER TABLE public.orders
  ADD CONSTRAINT orders_commission_status_check
  CHECK (commission_status IN ('pending', 'debt', 'credit', 'cash_collected', 'admin_collects'));

-- 4. Kontrol
-- SELECT DISTINCT commission_status FROM orders;
