-- Mevcut kayıtlı dükkanlar admin onay akışı hiç kullanılmadığı için
-- is_approved=false kalmış ve müşterilere hiç gösterilmiyordu.
-- Halihazırda aktif olan dükkanları toplu onaylıyoruz; yeni açılan
-- dükkanlar için onay akışı (seller_dashboard_screen "Admin onayı bekleyecek") aynen devam ediyor.

UPDATE public.shops
SET is_approved = TRUE
WHERE is_active = TRUE
  AND (is_approved = FALSE OR is_approved IS NULL);
