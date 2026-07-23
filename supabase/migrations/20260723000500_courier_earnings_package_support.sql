-- Paket teslimatlarında da courier_earnings kaydı oluşturulabilmesi için
-- gerekli kolonu ekler. courier_earnings tablosu daha önce sadece sipariş
-- teslimatları (assignment_id/order_id) için kullanılıyordu; paket teslimatları
-- (courier_requests) hiç kayıt eklemiyordu, bu yüzden kuryenin bekleyen alacağı
-- ve teslimat sayısı paket teslimatlarını yansıtmıyordu.

ALTER TABLE public.courier_earnings
  ADD COLUMN IF NOT EXISTS package_request_id uuid REFERENCES public.courier_requests(id);

CREATE INDEX IF NOT EXISTS idx_courier_earnings_package_request_id
  ON public.courier_earnings(package_request_id);
