-- Kuryesi olmayan satıcıların siparişlerinde müşteri bilgilerini gizleme
-- Admin panelinden toggle edilebilir

-- shops tablosuna hide_customer_info sütunu ekle
ALTER TABLE public.shops
ADD COLUMN IF NOT EXISTS hide_customer_info BOOLEAN DEFAULT false;

-- Yeni satıcılar için varsayılan değer: kuryesi olmayanlarda true
UPDATE public.shops 
SET hide_customer_info = true 
WHERE (has_own_courier = false OR has_own_courier IS NULL) 
AND hide_customer_info IS NULL;

-- RLS policy güncelle (opsiyonel - doğrudan sorgularda zaten görünür)
-- Satıcı kendi dükkanının hide_customer_info değerini görebilsin
