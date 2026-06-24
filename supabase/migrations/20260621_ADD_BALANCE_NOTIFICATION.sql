-- ============================================
-- BAKİYE YÜKLEME / HAVALE BİLDİRİM TRIGGER
-- Bakiye yüklendiğinde admin'e bildirim gönderir
-- ============================================

-- Bildirim fonksiyonu
CREATE OR REPLACE FUNCTION notify_admin_balance_topup()
RETURNS TRIGGER AS $$
BEGIN
    -- Sadece yeni işlem eklendiğinde ve tipi 'topup' veya 'adjustment' ise
    IF TG_OP = 'INSERT' AND (NEW.type = 'topup' OR NEW.type = 'adjustment') THEN
        -- Admin bildirimi oluştur
        INSERT INTO notifications (user_id, type, title, body, data)
        SELECT 
            p.id,
            'balance_topup',
            'Yeni Bakiye Yükleme',
            'Kullanıcı bakiye yükledi: ₺' || NEW.amount::text,
            jsonb_build(
                'transaction_id', NEW.id,
                'user_id', NEW.user_id,
                'amount', NEW.amount,
                'type', NEW.type,
                'payment_method', COALESCE(NEW.payment_method, 'unknown'),
                'created_at', NEW.created_at
            )
        FROM profiles p
        WHERE p.role = 'admin';
        
        -- Ayrıca e-posta gönderimi için log
        RAISE NOTICE 'Balance topup: user=%, amount=%, type=%', NEW.user_id, NEW.amount, NEW.type;
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Trigger'ı oluştur
DROP TRIGGER IF EXISTS trigger_notify_admin_balance_topup ON balance_transactions;
CREATE TRIGGER trigger_notify_admin_balance_topup
    AFTER INSERT ON balance_transactions
    FOR EACH ROW
    EXECUTE FUNCTION notify_admin_balance_topup();