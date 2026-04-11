-- Grup görünürlük ayarı: admin grupları keşfet listesinden gizleyebilir
ALTER TABLE public.groups ADD COLUMN IF NOT EXISTS is_discoverable BOOLEAN DEFAULT TRUE;

-- Yorum ekle
COMMENT ON COLUMN public.groups.is_discoverable IS 'Grubun tüm kullanıcılara görünür olup olmadığı. FALSE ise sadece üyeler görebilir.';
