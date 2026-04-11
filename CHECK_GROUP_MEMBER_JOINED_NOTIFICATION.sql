-- =====================================================
-- GRUP KATILIM BİLDİRİMİ SORUNU KONTROLÜ
-- =====================================================

-- 1. group_member_joined notification type var mı?
SELECT * FROM notification_types WHERE type = 'group_member_joined';

-- 2. Kullanıcıların notification_preferences'ında group_member_joined var mı?
SELECT 
    user_id, 
    type, 
    is_enabled,
    created_at
FROM notification_preferences
WHERE type = 'group_member_joined'
LIMIT 10;

-- 3. Eğer yoksa, ekleyelim
-- Not: notification_types tablosunda olmalı ki preferences oluşturulabilsin

-- 4. Notification types'a ekle (eğer yoksa)
INSERT INTO notification_types (type, name_tr, description_tr, category, default_enabled, icon)
VALUES (
    'group_member_joined',
    'Grup Katılımı',
    'Birileri grubunuza katıldığında bildirim alın',
    'groups',
    true,
    'group_add'
)
ON CONFLICT (type) DO NOTHING;

-- 5. Schema cache yenile
NOTIFY pgrst, 'reload schema';

-- 6. Kontrol: Tüm kullanıcılara default notification_preferences eklenecek mi?
-- (Bu genellikle otomatik yapılır trigger ile ama kontrol edelim)
SELECT COUNT(*) AS total_users FROM profiles;
SELECT COUNT(*) AS prefs_count FROM notification_preferences WHERE type = 'group_member_joined';
