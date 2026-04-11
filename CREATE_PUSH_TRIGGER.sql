-- =====================================================
-- PUSH NOTIFICATION TRIGGER KONTROL VE OLUŞTURMA
-- =====================================================

-- 1. Mevcut notifications trigger'ları göster
SELECT 
    trigger_name,
    event_manipulation,
    action_timing,
    action_statement
FROM information_schema.triggers
WHERE event_object_table = 'notifications'
AND trigger_schema = 'public'
ORDER BY trigger_name;

-- 2. send_push_on_notification fonksiyonu var mı?
SELECT 
    routine_name,
    routine_type
FROM information_schema.routines
WHERE routine_schema = 'public'
AND routine_name = 'send_push_on_notification';

-- 3. Trigger'ı oluştur (eğer yoksa)
DROP TRIGGER IF EXISTS push_notification_trigger ON notifications;

CREATE TRIGGER push_notification_trigger
    AFTER INSERT ON notifications
    FOR EACH ROW
    EXECUTE FUNCTION send_push_on_notification();

-- 4. Kontrol: Trigger oluştu mu?
SELECT 
    trigger_name,
    event_manipulation,
    action_timing
FROM information_schema.triggers
WHERE event_object_table = 'notifications'
AND trigger_name = 'push_notification_trigger';

-- =====================================================
-- SONUÇ
-- =====================================================
-- push_notification_trigger artık var
-- Her yeni notification eklendiğinde otomatik push gönderilir
