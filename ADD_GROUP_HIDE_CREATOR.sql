-- groups tablosuna hide_creator kolonu ekle
ALTER TABLE public.groups ADD COLUMN IF NOT EXISTS hide_creator BOOLEAN DEFAULT false;

COMMENT ON COLUMN public.groups.hide_creator IS 'Grup kurucusunun diğer üyelere gösterilip gösterilmeyeceği. TRUE ise sadece adminler kurucuyu görebilir.';
