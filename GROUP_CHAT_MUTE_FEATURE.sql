-- Grup sessize alma özelliği için group_members tablosuna is_muted alanı ekle
ALTER TABLE public.group_members 
ADD COLUMN IF NOT EXISTS is_muted BOOLEAN DEFAULT false;

-- İndeks ekle
CREATE INDEX IF NOT EXISTS idx_group_members_is_muted 
ON public.group_members(user_id, is_muted) 
WHERE is_muted = true;

COMMENT ON COLUMN public.group_members.is_muted IS 'Kullanıcı bu grubun bildirimlerini sessize aldı mı?';
