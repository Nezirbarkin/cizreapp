-- ============================================================================
-- GÜVENLİ DÜZELTME: Önce mevcut durumu kontrol eder, sonra düzeltir
-- ============================================================================
-- Trigger silme yerine güncelleme yapılır - daha güvenli

-- 1. MEVCUT DURUMU KONTROL ET
DO $$
DECLARE
    v_trigger_count INTEGER;
    v_function_count INTEGER;
BEGIN
    -- Kaç trigger var?
    SELECT COUNT(*) INTO v_trigger_count
    FROM pg_trigger
    WHERE tgname IN ('message_insert_trigger', 'on_new_message_notify');

    -- Kaç fonksiyon var?
    SELECT COUNT(*) INTO v_function_count
    FROM pg_proc
    WHERE proname = 'update_conversation_on_message';

    RAISE NOTICE '============================================================================';
    RAISE NOTICE 'MEVCUT DURUM KONTROLÜ:';
    RAISE NOTICE '  Trigger sayısı: %', v_trigger_count;
    RAISE NOTICE '  Fonksiyon sayısı: %', v_function_count;
    RAISE NOTICE '============================================================================';
END $$;

-- 2. ESKİ FONKSİYONU GÜNCELLE (DROP yerine CREATE OR REPLACE)
-- Bu sayede mevcut trigger'lar korunur, sadece fonksiyon güncellenir
CREATE OR REPLACE FUNCTION update_conversation_on_message()
RETURNS TRIGGER AS $$
DECLARE
    v_user_id UUID;
    v_other_user_id UUID;
    v_other_conv_id UUID;
BEGIN
    -- Mevcut conversation bilgilerini al
    SELECT user_id, other_user_id INTO v_user_id, v_other_user_id
    FROM conversations
    WHERE id = NEW.conversation_id;
    
    -- Mevcut conversation'ı güncelle
    UPDATE conversations
    SET
        last_message = NEW.content,
        last_message_time = NEW.created_at,
        updated_at = NOW(),
        unread_count = CASE
            WHEN user_id != NEW.sender_id THEN unread_count + 1
            ELSE unread_count
        END
    WHERE id = NEW.conversation_id;
    
    -- Karşı taraf için conversation var mı kontrol et
    SELECT id INTO v_other_conv_id
    FROM conversations
    WHERE user_id = v_other_user_id
      AND other_user_id = v_user_id;
    
    -- Karşı taraf için conversation yoksa oluştur
    IF v_other_conv_id IS NULL THEN
        INSERT INTO conversations (user_id, other_user_id, last_message, last_message_time, unread_count)
        VALUES (v_other_user_id, v_user_id, NEW.content, NEW.created_at, 1);
    ELSE
        -- Karşı taraf için conversation varsa güncelle
        UPDATE conversations
        SET
            last_message = NEW.content,
            last_message_time = NEW.created_at,
            updated_at = NOW(),
            unread_count = unread_count + 1
        WHERE id = v_other_conv_id;
    END IF;
    
    -- HER ZAMAN BAŞARILI DÖN
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public;

-- 3. Trigger'ların doğru fonksiyonu kullandığından emin ol
-- (DROP yapmıyoruz, sadece CREATE OR REPLACE yaptık)

-- Sonuç
DO $$
BEGIN
    RAISE NOTICE '============================================================================';
    RAISE NOTICE '✅ GÜVENLİ DÜZELTME TAMAMLANDI';
    RAISE NOTICE '✅ Fonksiyon güncellendi (CREATE OR REPLACE kullanıldı)';
    RAISE NOTICE 'Triggerlar korunuyor (DROP yapilmadi)';
    RAISE NOTICE '✅ Mesaj gönderimi çalışmalı';
    RAISE NOTICE '============================================================================';
END $$;
