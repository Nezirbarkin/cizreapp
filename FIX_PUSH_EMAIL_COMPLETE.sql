-- =====================================================
-- PUSH BİLDİRİM VE EMAIL SİSTEMİ TAMAMI - ÇÖZÜM SQL
-- =====================================================
-- Tarih: 2024
-- Açıklama: Push bildirim ve email gönderimini aktif hale getiren SQL
-- =====================================================

-- =====================================================
-- BÖLÜM 1: EMAIL GÖNDERİM FONKSİYONU
-- =====================================================

CREATE OR REPLACE FUNCTION send_email(
    p_to_email text,
    p_subject text,
    p_html_body text,
    p_text_body text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_settings record;
    v_response jsonb;
    v_request_id bigint;
    v_from_email text;
    v_from_name text;
BEGIN
    -- Email ayarlarını al
    SELECT * INTO v_settings
    FROM email_settings
    WHERE is_active = true
    LIMIT 1;
    
    -- Ayar yoksa hata döndür
    IF v_settings IS NULL THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'Email ayarları bulunamadı'
        );
    END IF;
    
    v_from_email := v_settings.from_email;
    v_from_name := v_settings.from_name;
    
    -- Provider'a göre email gönder
    IF v_settings.provider = 'resend' AND v_settings.resend_api_key IS NOT NULL THEN
        -- Resend ile email gönder
        SELECT net.http_post(
            url := 'https://api.resend.com/emails',
            headers := jsonb_build_object(
                'Authorization', 'Bearer ' || v_settings.resend_api_key,
                'Content-Type', 'application/json'
            ),
            body := jsonb_build_object(
                'from', v_from_name || ' <' || v_from_email || '>',
                'to', ARRAY[p_to_email],
                'subject', p_subject,
                'html', p_html_body,
                'text', COALESCE(p_text_body, '')
            )
        ) INTO v_request_id;
        
        RETURN jsonb_build_object(
            'success', true,
            'provider', 'resend',
            'request_id', v_request_id
        );
        
    ELSIF v_settings.provider = 'sendgrid' AND v_settings.sendgrid_api_key IS NOT NULL THEN
        -- SendGrid ile email gönder
        SELECT net.http_post(
            url := 'https://api.sendgrid.com/v3/mail/send',
            headers := jsonb_build_object(
                'Authorization', 'Bearer ' || v_settings.sendgrid_api_key,
                'Content-Type', 'application/json'
            ),
            body := jsonb_build_object(
                'personalizations', jsonb_build_array(
                    jsonb_build_object('to', jsonb_build_array(
                        jsonb_build_object('email', p_to_email)
                    ))
                ),
                'from', jsonb_build_object(
                    'email', v_from_email,
                    'name', v_from_name
                ),
                'subject', p_subject,
                'content', jsonb_build_array(
                    jsonb_build_object(
                        'type', 'text/html',
                        'value', p_html_body
                    )
                )
            )
        ) INTO v_request_id;
        
        RETURN jsonb_build_object(
            'success', true,
            'provider', 'sendgrid',
            'request_id', v_request_id
        );
        
    ELSIF v_settings.provider = 'mailgun' AND v_settings.mailgun_api_key IS NOT NULL THEN
        -- Mailgun ile email gönder
        SELECT net.http_post(
            url := 'https://api.mailgun.net/v3/' || v_settings.mailgun_domain || '/messages',
            headers := jsonb_build_object(
                'Authorization', 'Basic ' || encode(('api:' || v_settings.mailgun_api_key)::bytea, 'base64'),
                'Content-Type', 'application/x-www-form-urlencoded'
            ),
            body := jsonb_build_object(
                'from', v_from_name || ' <' || v_from_email || '>',
                'to', p_to_email,
                'subject', p_subject,
                'html', p_html_body,
                'text', COALESCE(p_text_body, '')
            )
        ) INTO v_request_id;
        
        RETURN jsonb_build_object(
            'success', true,
            'provider', 'mailgun',
            'request_id', v_request_id
        );
        
    ELSE
        -- SMTP desteği şu an yok (pg_net ile SMTP gönderim desteklenmez)
        RETURN jsonb_build_object(
            'success', false,
            'error', 'SMTP provider desteklenmiyor. Lütfen Resend, SendGrid veya Mailgun kullanın.'
        );
    END IF;
    
EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object(
        'success', false,
        'error', SQLERRM
    );
END;
$$;

-- =====================================================
-- BÖLÜM 2: PUSH NOTIFICATION GÖNDERİM FONKSİYONU
-- =====================================================

CREATE OR REPLACE FUNCTION send_fcm_push_notification(
    p_user_id uuid,
    p_title text,
    p_body text,
    p_data jsonb DEFAULT '{}'::jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_token record;
    v_response jsonb;
    v_request_id bigint;
    v_success_count int := 0;
    v_error_count int := 0;
    v_firebase_key text;
    v_project_id text;
    v_access_token text;
BEGIN
    -- Firebase service account key'i vault'tan al
    SELECT decrypted_secret INTO v_firebase_key
    FROM vault.decrypted_secrets
    WHERE name = 'firebase_service_account'
    LIMIT 1;
    
    IF v_firebase_key IS NULL THEN
        RETURN jsonb_build_object(
            'success', false,
            'error', 'Firebase service account key bulunamadı'
        );
    END IF;
    
    -- Project ID'yi al (service account JSON'dan)
    v_project_id := (v_firebase_key::jsonb)->>'project_id';
    
    -- NOT: Firebase HTTP v1 API, OAuth2 access token gerektirir
    -- Bu token'ı almak için service account ile kimlik doğrulama yapılmalı
    -- Basitleştirilmiş versiyon için legacy FCM API kullanıyoruz
    
    -- Kullanıcının tüm aktif token'larını al
    FOR v_token IN 
        SELECT token, device_type 
        FROM notification_tokens 
        WHERE user_id = p_user_id
    LOOP
        BEGIN
            -- FCM Legacy API ile push gönder (FCM Server Key gerekir)
            -- NOT: Production için HTTP v1 API kullanılmalı
            SELECT net.http_post(
                url := 'https://fcm.googleapis.com/fcm/send',
                headers := jsonb_build_object(
                    'Authorization', 'key=' || (v_firebase_key::jsonb)->>'server_key',
                    'Content-Type', 'application/json'
                ),
                body := jsonb_build_object(
                    'to', v_token.token,
                    'notification', jsonb_build_object(
                        'title', p_title,
                        'body', p_body,
                        'sound', 'default'
                    ),
                    'data', p_data,
                    'priority', 'high'
                )
            ) INTO v_request_id;
            
            v_success_count := v_success_count + 1;
            
        EXCEPTION WHEN OTHERS THEN
            v_error_count := v_error_count + 1;
            RAISE WARNING 'Push notification error for token %: %', v_token.token, SQLERRM;
        END;
    END LOOP;
    
    RETURN jsonb_build_object(
        'success', true,
        'sent_count', v_success_count,
        'error_count', v_error_count
    );
    
EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object(
        'success', false,
        'error', SQLERRM
    );
END;
$$;

-- =====================================================
-- BÖLÜM 3: YENİ SİPARİŞ EMAIL GÖNDERİM FONKSİYONU
-- =====================================================

CREATE OR REPLACE FUNCTION send_new_order_emails(
    p_order_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_order record;
    v_shop record;
    v_user record;
    v_settings record;
    v_result jsonb;
    v_html_body text;
    v_order_items text;
    v_item record;
BEGIN
    -- Sipariş bilgilerini al
    SELECT 
        o.*,
        p.email as customer_email,
        p.full_name as customer_name
    INTO v_order
    FROM orders o
    LEFT JOIN profiles p ON p.id = o.user_id
    WHERE o.id = p_order_id;
    
    IF v_order IS NULL THEN
        RETURN jsonb_build_object('success', false, 'error', 'Sipariş bulunamadı');
    END IF;
    
    -- Mağaza bilgilerini al
    SELECT 
        s.*,
        p.email as owner_email,
        p.full_name as owner_name
    INTO v_shop
    FROM shops s
    LEFT JOIN profiles p ON p.id = s.owner_id
    WHERE s.id = v_order.shop_id;
    
    -- Email ayarlarını al
    SELECT * INTO v_settings
    FROM email_settings
    WHERE is_active = true
    LIMIT 1;
    
    IF v_settings IS NULL THEN
        RETURN jsonb_build_object('success', false, 'error', 'Email ayarları bulunamadı');
    END IF;
    
    -- Sipariş ürünlerini HTML olarak hazırla
    v_order_items := '<ul>';
    FOR v_item IN
        SELECT 
            p.name,
            oi.quantity,
            oi.price,
            (oi.quantity * oi.price) as total
        FROM order_items oi
        LEFT JOIN products p ON p.id = oi.product_id
        WHERE oi.order_id = p_order_id
    LOOP
        v_order_items := v_order_items || '<li>' || 
            v_item.name || ' x ' || v_item.quantity || 
            ' = ' || v_item.total || ' TL</li>';
    END LOOP;
    v_order_items := v_order_items || '</ul>';
    
    -- 1. MAĞAZAYA EMAIL GÖNDER
    IF v_settings.notify_seller_new_order = true AND v_shop.owner_email IS NOT NULL THEN
        v_html_body := '<h2>🛍️ Yeni Sipariş Aldınız!</h2>' ||
            '<p>Sayın ' || COALESCE(v_shop.owner_name, 'Mağaza Sahibi') || ',</p>' ||
            '<p>Mağazanıza yeni bir sipariş geldi:</p>' ||
            '<hr>' ||
            '<p><strong>Sipariş No:</strong> ' || v_order.order_number || '</p>' ||
            '<p><strong>Müşteri:</strong> ' || COALESCE(v_order.customer_name, 'Misafir') || '</p>' ||
            '<p><strong>Telefon:</strong> ' || COALESCE(v_order.customer_phone, '-') || '</p>' ||
            '<p><strong>Teslimat Adresi:</strong><br>' || v_order.delivery_address_text || '</p>' ||
            '<p><strong>Ödeme Yöntemi:</strong> ' || v_order.payment_method || '</p>' ||
            '<hr>' ||
            '<p><strong>Sipariş Detayları:</strong></p>' ||
            v_order_items ||
            '<p><strong>Ara Toplam:</strong> ' || v_order.subtotal || ' TL</p>' ||
            '<p><strong>Teslimat Ücreti:</strong> ' || COALESCE(v_order.delivery_fee::text, '0') || ' TL</p>' ||
            '<p><strong>Toplam:</strong> ' || v_order.total || ' TL</p>' ||
            '<hr>' ||
            '<p>Siparişi hemen işleme alabilirsiniz.</p>' ||
            '<p>İyi satışlar!</p>';
        
        v_result := send_email(
            v_shop.owner_email,
            '🛍️ Yeni Sipariş: #' || v_order.order_number,
            v_html_body
        );
    END IF;
    
    -- 2. ADMIN'E EMAIL GÖNDER
    IF v_settings.notify_admin_new_order = true AND v_settings.admin_email IS NOT NULL THEN
        v_html_body := '<h2>🔔 Yeni Sipariş Bildirimi</h2>' ||
            '<p>Sisteme yeni bir sipariş geldi:</p>' ||
            '<hr>' ||
            '<p><strong>Sipariş No:</strong> ' || v_order.order_number || '</p>' ||
            '<p><strong>Mağaza:</strong> ' || v_shop.name || '</p>' ||
            '<p><strong>Müşteri:</strong> ' || COALESCE(v_order.customer_name, 'Misafir') || '</p>' ||
            '<p><strong>Toplam Tutar:</strong> ' || v_order.total || ' TL</p>' ||
            '<p><strong>Ödeme Yöntemi:</strong> ' || v_order.payment_method || '</p>' ||
            '<hr>' ||
            '<p>Detayları admin panelinden görebilirsiniz.</p>';
        
        v_result := send_email(
            v_settings.admin_email,
            '🔔 Yeni Sipariş: #' || v_order.order_number,
            v_html_body
        );
    END IF;
    
    RETURN jsonb_build_object('success', true, 'message', 'Emailler gönderildi');
    
EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object('success', false, 'error', SQLERRM);
END;
$$;

-- =====================================================
-- BÖLÜM 4: MEVCUT TRIGGER FONKSİYONLARINI GÜNCELLE
-- =====================================================

-- 4.1. Push Notification Trigger Fonksiyonunu Güncelle
CREATE OR REPLACE FUNCTION send_push_on_notification()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_result jsonb;
    v_prefs record;
BEGIN
    -- Kullanıcının bildirim tercihlerini kontrol et
    SELECT * INTO v_prefs
    FROM notification_preferences
    WHERE user_id = NEW.user_id;
    
    -- Eğer tercih yoksa veya push bildirimleri açıksa gönder
    IF v_prefs IS NULL OR v_prefs.push_enabled = true THEN
        -- Async olarak push gönder
        PERFORM send_fcm_push_notification(
            NEW.user_id,
            COALESCE(NEW.title, 'Yeni Bildirim'),
            COALESCE(NEW.body, ''),
            jsonb_build_object(
                'notification_id', NEW.id,
                'type', NEW.type,
                'data', COALESCE(NEW.data, '{}'::jsonb)
            )
        );
    END IF;
    
    RETURN NEW;
END;
$$;

-- 4.2. Email Trigger Fonksiyonunu Güncelle
CREATE OR REPLACE FUNCTION notify_new_order_email()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_result jsonb;
BEGIN
    -- Async olarak email gönder
    PERFORM send_new_order_emails(NEW.id);
    
    RETURN NEW;
END;
$$;

-- =====================================================
-- BÖLÜM 5: YENİ SİPARİŞ PUSH BİLDİRİM FONKSİYONU
-- =====================================================

CREATE OR REPLACE FUNCTION send_new_order_push_notifications(
    p_order_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_order record;
    v_shop record;
    v_result jsonb;
BEGIN
    -- Sipariş bilgilerini al
    SELECT * INTO v_order
    FROM orders
    WHERE id = p_order_id;
    
    IF v_order IS NULL THEN
        RETURN jsonb_build_object('success', false, 'error', 'Sipariş bulunamadı');
    END IF;
    
    -- Mağaza bilgilerini al
    SELECT * INTO v_shop
    FROM shops
    WHERE id = v_order.shop_id;
    
    -- Mağaza sahibine push bildirimi gönder
    IF v_shop.owner_id IS NOT NULL THEN
        v_result := send_fcm_push_notification(
            v_shop.owner_id,
            '🛍️ Yeni Sipariş!',
            'Sipariş #' || v_order.order_number || ' - Tutar: ' || v_order.total || ' TL',
            jsonb_build_object(
                'order_id', v_order.id,
                'order_number', v_order.order_number,
                'type', 'new_order'
            )
        );
    END IF;
    
    -- Admin'lere push bildirimi gönder
    FOR v_result IN
        SELECT id FROM profiles WHERE role = 'admin'
    LOOP
        PERFORM send_fcm_push_notification(
            (v_result->>'id')::uuid,
            '🔔 Yeni Sipariş',
            v_shop.name || ' - Sipariş #' || v_order.order_number,
            jsonb_build_object(
                'order_id', v_order.id,
                'order_number', v_order.order_number,
                'shop_id', v_shop.id,
                'type', 'new_order_admin'
            )
        );
    END LOOP;
    
    RETURN jsonb_build_object('success', true, 'message', 'Push bildirimleri gönderildi');
    
EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object('success', false, 'error', SQLERRM);
END;
$$;

-- =====================================================
-- BÖLÜM 6: YENİ SİPARİŞ TRIGGER'LARINA PUSH EKLE
-- =====================================================

-- Mevcut trigger'ı güncelle veya yeni trigger ekle
CREATE OR REPLACE FUNCTION notify_new_order_complete()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    -- Email gönder (async)
    PERFORM send_new_order_emails(NEW.id);
    
    -- Push bildirimi gönder (async)
    PERFORM send_new_order_push_notifications(NEW.id);
    
    RETURN NEW;
END;
$$;

-- Eski trigger'ı kaldır ve yeni trigger oluştur
DROP TRIGGER IF EXISTS on_order_created_send_email ON orders;
CREATE TRIGGER on_order_created_notify
    AFTER INSERT ON orders
    FOR EACH ROW
    EXECUTE FUNCTION notify_new_order_complete();

-- =====================================================
-- BÖLÜM 7: SİPARİŞ DURUMU DEĞİŞİKLİĞİ BİLDİRİMLERİ
-- =====================================================

CREATE OR REPLACE FUNCTION notify_order_status_change()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_settings record;
    v_user record;
    v_shop record;
    v_status_tr text;
    v_html_body text;
BEGIN
    -- Sadece status değiştiğinde çalış
    IF OLD.status = NEW.status THEN
        RETURN NEW;
    END IF;
    
    -- Email ayarlarını al
    SELECT * INTO v_settings
    FROM email_settings
    WHERE is_active = true
    LIMIT 1;
    
    -- Müşteri bilgilerini al
    SELECT email, full_name INTO v_user
    FROM profiles
    WHERE id = NEW.user_id;
    
    -- Mağaza bilgilerini al
    SELECT name INTO v_shop
    FROM shops
    WHERE id = NEW.shop_id;
    
    -- Status'ü Türkçe'ye çevir
    v_status_tr := CASE NEW.status
        WHEN 'pending' THEN 'Beklemede'
        WHEN 'confirmed' THEN 'Onaylandı'
        WHEN 'preparing' THEN 'Hazırlanıyor'
        WHEN 'ready' THEN 'Hazır'
        WHEN 'shipped' THEN 'Kargoda'
        WHEN 'delivered' THEN 'Teslim Edildi'
        WHEN 'cancelled' THEN 'İptal Edildi'
        ELSE NEW.status
    END;
    
    -- Müşteriye email gönder
    IF v_settings.notify_customer_order_status = true AND v_user.email IS NOT NULL THEN
        v_html_body := '<h2>📦 Sipariş Durumu Güncellendi</h2>' ||
            '<p>Sayın ' || COALESCE(v_user.full_name, 'Müşteri') || ',</p>' ||
            '<p>Sipariş durumunuz güncellendi:</p>' ||
            '<hr>' ||
            '<p><strong>Sipariş No:</strong> ' || NEW.order_number || '</p>' ||
            '<p><strong>Mağaza:</strong> ' || v_shop.name || '</p>' ||
            '<p><strong>Yeni Durum:</strong> ' || v_status_tr || '</p>' ||
            '<p><strong>Toplam Tutar:</strong> ' || NEW.total || ' TL</p>' ||
            '<hr>' ||
            '<p>Siparişinizi takip edebilirsiniz.</p>' ||
            '<p>Teşekkürler!</p>';
        
        PERFORM send_email(
            v_user.email,
            '📦 Sipariş Durumu: ' || v_status_tr,
            v_html_body
        );
    END IF;
    
    -- Müşteriye push bildirimi gönder
    PERFORM send_fcm_push_notification(
        NEW.user_id,
        '📦 Sipariş Durumu Güncellendi',
        'Sipariş #' || NEW.order_number || ' - ' || v_status_tr,
        jsonb_build_object(
            'order_id', NEW.id,
            'order_number', NEW.order_number,
            'status', NEW.status,
            'type', 'order_status_changed'
        )
    );
    
    RETURN NEW;
END;
$$;

-- Sipariş durumu değişikliği trigger'ı
DROP TRIGGER IF EXISTS on_order_status_changed ON orders;
CREATE TRIGGER on_order_status_changed
    AFTER UPDATE OF status ON orders
    FOR EACH ROW
    EXECUTE FUNCTION notify_order_status_change();

-- =====================================================
-- BÖLÜM 8: GÜVENLİK VE İZİNLER
-- =====================================================

-- Fonksiyonlara public erişim ver (RLS ile kontrol edilecek)
GRANT EXECUTE ON FUNCTION send_email TO authenticated;
GRANT EXECUTE ON FUNCTION send_fcm_push_notification TO authenticated;
GRANT EXECUTE ON FUNCTION send_new_order_emails TO authenticated;
GRANT EXECUTE ON FUNCTION send_new_order_push_notifications TO authenticated;

-- =====================================================
-- BÖLÜM 9: TEST VERİLERİ (OPSİYONEL)
-- =====================================================

-- Email ayarlarını kontrol et/oluştur
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM email_settings WHERE is_active = true) THEN
        INSERT INTO email_settings (
            provider,
            from_email,
            from_name,
            notify_admin_new_order,
            notify_seller_new_order,
            notify_customer_order_status,
            is_active
        ) VALUES (
            'resend',
            'noreply@cizreapp.com',
            'CizreApp',
            true,
            true,
            true,
            true
        );
        
        RAISE NOTICE 'Email ayarları oluşturuldu. Lütfen API key''leri güncelleyin!';
    END IF;
END $$;

-- =====================================================
-- TAMAMLANDI!
-- =====================================================

-- Kurulum sonrası yapılması gerekenler:
-- 1. Firebase service account key'i vault'a ekle:
--    INSERT INTO vault.decrypted_secrets (name, secret, description)
--    VALUES ('firebase_service_account', '{"server_key":"YOUR_FCM_SERVER_KEY","project_id":"YOUR_PROJECT_ID"}', 'Firebase FCM Key');
--
-- 2. Email ayarlarını güncelle:
--    UPDATE email_settings SET 
--      resend_api_key = 'YOUR_RESEND_API_KEY',
--      admin_email = 'admin@cizreapp.com'
--    WHERE id = ...;
--
-- 3. Test et:
--    SELECT send_email('test@example.com', 'Test', '<p>Test email</p>');
--    SELECT send_fcm_push_notification('USER_UUID', 'Test', 'Test push notification');
