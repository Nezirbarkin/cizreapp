-- ============================================================================
-- BAKİYE BİLDİRİM TRIGGER DÜZELTMESİ
-- 20260621_ADD_BALANCE_NOTIFICATION.sql dosyasındaki trigger
-- notifications tablosuna 'body' ve 'data' kolonları ile INSERT yapmaya
-- çalışıyordu. Ancak gerçek tablo şemasında 'content' kolonu var, 'data'
-- kolonu ise hiç yok. Ayrıca 'balance_topup' tipi notifications_type_check
-- CHECK constraint listesinde bulunmuyor.
--
-- Bu dosya trigger fonksiyonunu gerçek şemaya uygun şekilde yeniden yazar.
-- ============================================================================

CREATE OR REPLACE FUNCTION notify_admin_balance_topup()
RETURNS TRIGGER AS $$
DECLARE
    v_user_name TEXT;
    v_content TEXT;
BEGIN
    -- Sadece yeni işlem eklendiğinde ve tipi 'topup' veya 'adjustment' ise
    IF TG_OP = 'INSERT' AND (NEW.type = 'topup' OR NEW.type = 'adjustment') THEN
        -- Kullanıcı adını al (bildirimde göstermek için)
        SELECT full_name INTO v_user_name
        FROM profiles
        WHERE id = NEW.user_id;

        v_content := COALESCE(v_user_name, 'Bir kullanıcı') ||
                    ' bakiye yükledi: ₺' || NEW.amount::text;

        -- Admin bildirimi oluştur
        -- 'admin_notification' tipi CHECK constraint listesinde var
        -- 'content' kolonu (body DEĞİL) kullanılıyor
        -- 'data' kolonu notifications tablosunda yok, entity_id kullanıyoruz
        INSERT INTO notifications (user_id, type, title, content, entity_id)
        SELECT
            p.id,
            'admin_notification',
            'Yeni Bakiye Yükleme',
            v_content,
            NEW.id::text
        FROM profiles p
        WHERE p.role = 'admin';

        -- Ayrıca e-posta gönderimi için log
        RAISE NOTICE 'Balance topup: user=%, amount=%, type=%', NEW.user_id, NEW.amount, NEW.type;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Trigger'ı yeniden oluştur (güncellenmiş fonksiyonla çalışması için)
DROP TRIGGER IF EXISTS trigger_notify_admin_balance_topup ON balance_transactions;
CREATE TRIGGER trigger_notify_admin_balance_topup
    AFTER INSERT ON balance_transactions
    FOR EACH ROW
    EXECUTE FUNCTION notify_admin_balance_topup();

-- ============================================================================
-- BAŞARILI
-- Artık balance_transactions'a INSERT yapıldığında tetiklenen trigger
-- doğru kolon adları ve izin verilen notification tipi ile çalışacak.
-- ============================================================================