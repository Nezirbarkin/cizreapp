-- Destek ve şikayet bildirim tipleri ekle
-- Bu migration, notifications tablosuna yeni tipler ekler

-- Önce mevcut constraint'i kaldır
ALTER TABLE public.notifications DROP CONSTRAINT IF EXISTS notifications_type_check;

-- Yeni constraint'i ekle (destek ve şikayet tipleri dahil)
ALTER TABLE public.notifications 
ADD CONSTRAINT notifications_type_check 
CHECK (type IN ('like', 'comment', 'follow', 'mention', 'order', 'shop', 'support_response', 'support_status', 'complaint_response', 'report'));

-- Yeni tipler için comment
COMMENT ON COLUMN public.notifications.type IS 'Bildirim tipi: like, comment, follow, mention, order, shop, support_response, support_status, complaint_response, report';
