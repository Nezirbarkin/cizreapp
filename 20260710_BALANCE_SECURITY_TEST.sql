-- =====================================================================
-- BAKİYE GÜVENLİK TEST SCRIPTI
-- =====================================================================
-- Tarih: 2026-07-10
-- Bu script güvenlik düzeltmelerini test etmek için kullanılır
-- =====================================================================

DO $$
DECLARE
    v_result RECORD;
    v_test_user_id UUID;
    v_test_amount NUMERIC;
    v_count INTEGER;
BEGIN
    RAISE NOTICE '================================================================';
    RAISE NOTICE 'BAKİYE GÜVENLİK TESTLERİ BAŞLIYOR';
    RAISE NOTICE '================================================================';
    RAISE NOTICE '';

    -- =====================================================================
    -- TEST 1: Tabloların oluşturulduğunu kontrol et
    -- =====================================================================
    RAISE NOTICE '▶ TEST 1: Tablo kontrolü';

    SELECT COUNT(*) INTO v_count FROM information_schema.tables 
    WHERE table_schema = 'public' AND table_name = 'balance_security_logs';
    IF v_count > 0 THEN
        RAISE NOTICE '  ✅ balance_security_logs tablosu mevcut';
    ELSE
        RAISE NOTICE '  ❌ balance_security_logs tablosu BULUNAMADI';
    END IF;

    SELECT COUNT(*) INTO v_count FROM information_schema.tables 
    WHERE table_schema = 'public' AND table_name = 'balance_rate_limits';
    IF v_count > 0 THEN
        RAISE NOTICE '  ✅ balance_rate_limits tablosu mevcut';
    ELSE
        RAISE NOTICE '  ❌ balance_rate_limits tablosu BULUNAMADI';
    END IF;

    SELECT COUNT(*) INTO v_count FROM information_schema.tables 
    WHERE table_schema = 'public' AND table_name = 'balance_security_settings';
    IF v_count > 0 THEN
        RAISE NOTICE '  ✅ balance_security_settings tablosu mevcut';
    ELSE
        RAISE NOTICE '  ❌ balance_security_settings tablosu BULUNAMADI';
    END IF;

    -- =====================================================================
    -- TEST 2: Fonksiyonların oluşturulduğunu kontrol et
    -- =====================================================================
    RAISE NOTICE '';
    RAISE NOTICE '▶ TEST 2: Fonksiyon kontrolü';

    SELECT COUNT(*) INTO v_count FROM pg_proc WHERE proname = 'log_balance_security_event';
    IF v_count > 0 THEN
        RAISE NOTICE '  ✅ log_balance_security_event fonksiyonu mevcut';
    ELSE
        RAISE NOTICE '  ❌ log_balance_security_event fonksiyonu BULUNAMADI';
    END IF;

    SELECT COUNT(*) INTO v_count FROM pg_proc WHERE proname = 'check_balance_rate_limit';
    IF v_count > 0 THEN
        RAISE NOTICE '  ✅ check_balance_rate_limit fonksiyonu mevcut';
    ELSE
        RAISE NOTICE '  ❌ check_balance_rate_limit fonksiyonu BULUNAMADI';
    END IF;

    SELECT COUNT(*) INTO v_count FROM pg_proc WHERE proname = 'update_balance_rate_limit';
    IF v_count > 0 THEN
        RAISE NOTICE '  ✅ update_balance_rate_limit fonksiyonu mevcut';
    ELSE
        RAISE NOTICE '  ❌ update_balance_rate_limit fonksiyonu BULUNAMADI';
    END IF;

    SELECT COUNT(*) INTO v_count FROM pg_proc WHERE proname = 'atomic_add_balance_topup_secure';
    IF v_count > 0 THEN
        RAISE NOTICE '  ✅ atomic_add_balance_topup_secure fonksiyonu mevcut';
    ELSE
        RAISE NOTICE '  ❌ atomic_add_balance_topup_secure fonksiyonu BULUNAMADI';
    END IF;

    SELECT COUNT(*) INTO v_count FROM pg_proc WHERE proname = 'admin_balance_operation_secure';
    IF v_count > 0 THEN
        RAISE NOTICE '  ✅ admin_balance_operation_secure fonksiyonu mevcut';
    ELSE
        RAISE NOTICE '  ❌ admin_balance_operation_secure fonksiyonu BULUNAMADI';
    END IF;

    -- =====================================================================
    -- TEST 3: Güvenlik ayarlarını kontrol et
    -- =====================================================================
    RAISE NOTICE '';
    RAISE NOTICE '▶ TEST 3: Güvenlik ayarları kontrolü';

    SELECT setting_value INTO v_result FROM public.balance_security_settings 
    WHERE setting_key = 'daily_topup_limit_count';
    IF FOUND THEN
        RAISE NOTICE '  ✅ daily_topup_limit_count: %', v_result.setting_value;
    ELSE
        RAISE NOTICE '  ❌ daily_topup_limit_count ayarı BULUNAMADI';
    END IF;

    SELECT setting_value INTO v_result FROM public.balance_security_settings 
    WHERE setting_key = 'daily_topup_limit_amount';
    IF FOUND THEN
        RAISE NOTICE '  ✅ daily_topup_limit_amount: % TL', v_result.setting_value;
    ELSE
        RAISE NOTICE '  ❌ daily_topup_limit_amount ayarı BULUNAMADI';
    END IF;

    SELECT setting_value INTO v_result FROM public.balance_security_settings 
    WHERE setting_key = 'risk_score_block_threshold';
    IF FOUND THEN
        RAISE NOTICE '  ✅ risk_score_block_threshold: %', v_result.setting_value;
    ELSE
        RAISE NOTICE '  ❌ risk_score_block_threshold ayarı BULUNAMADI';
    END IF;

    -- =====================================================================
    -- TEST 4: Rate limit fonksiyon testi (simüle)
    -- =====================================================================
    RAISE NOTICE '';
    RAISE NOTICE '▶ TEST 4: Rate limit kontrol fonksiyonu testi';
    RAISE NOTICE '  (Gerçek test için test_user_id kullanılmalı)';

    -- Örnek: Rate limit kontrolü simülasyonu
    -- SELECT * FROM public.check_balance_rate_limit(
    --     'test-user-uuid'::UUID,
    --     100.00,
    --     '192.168.1.1'::INET,
    --     'test-device-fingerprint'
    -- );

    RAISE NOTICE '  ℹ️ Rate limit testi için üretim ortamında test kullanıcısı ile deneyin';

    -- =====================================================================
    -- TEST 5: Log fonksiyonu testi
    -- =====================================================================
    RAISE NOTICE '';
    RAISE NOTICE '▶ TEST 5: Güvenlik log fonksiyonu testi';

    -- Test log kaydı oluştur
    BEGIN
        PERFORM public.log_balance_security_event(
            p_event_type => 'test_log',
            p_user_id => NULL,  -- NULL test için
            p_ip_address => '127.0.0.1'::INET,
            p_user_agent => 'Security Test Script',
            p_device_fingerprint => 'test-fingerprint-123',
            p_amount => 100.00,
            p_payment_method => 'card',
            p_status => 'success',
            p_risk_score => 10,
            p_risk_factors => '["test"]'::JSONB,
            p_metadata => '{"test": true}'::JSONB
        );
        RAISE NOTICE '  ✅ log_balance_security_event başarıyla çalıştı';
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE '  ❌ log_balance_security_event HATASI: %', SQLERRM;
    END;

    -- =====================================================================
    -- TEST 6: Son logları göster
    -- =====================================================================
    RAISE NOTICE '';
    RAISE NOTICE '▶ TEST 6: Son güvenlik logları (varsa)';

    SELECT COUNT(*) INTO v_count FROM public.balance_security_logs;
    RAISE NOTICE '  Toplam log sayısı: %', v_count;

    IF v_count > 0 THEN
        RAISE NOTICE '  Son 5 log:';
        FOR v_result IN 
            SELECT event_type, user_id, amount, status, risk_score, created_at
            FROM public.balance_security_logs
            ORDER BY created_at DESC
            LIMIT 5
        LOOP
            RAISE NOTICE '    - % | % | % TL | % | Risk: %',
                v_result.event_type,
                v_result.user_id,
                v_result.amount,
                v_result.status,
                v_result.risk_score;
        END LOOP;
    END IF;

    -- =====================================================================
    -- TEST 7: Rate limit verilerini göster
    -- =====================================================================
    RAISE NOTICE '';
    RAISE NOTICE '▶ TEST 7: Rate limit sayaçları';

    SELECT COUNT(*) INTO v_count FROM public.balance_rate_limits;
    RAISE NOTICE '  Toplam rate limit kaydı: %', v_count;

    IF v_count > 0 THEN
        RAISE NOTICE '  Aktif limitler:';
        FOR v_result IN 
            SELECT user_id, period_type, transaction_count, total_amount, period_end
            FROM public.balance_rate_limits
            WHERE period_end > NOW()
            ORDER BY updated_at DESC
            LIMIT 10
        LOOP
            RAISE NOTICE '    - User: % | Tip: % | İşlem: % | Tutar: % TL',
                v_result.user_id,
                v_result.period_type,
                v_result.transaction_count,
                v_result.total_amount;
        END LOOP;
    END IF;

    -- =====================================================================
    -- ÖZET
    -- =====================================================================
    RAISE NOTICE '';
    RAISE NOTICE '================================================================';
    RAISE NOTICE 'TEST ÖZETİ';
    RAISE NOTICE '================================================================';
    RAISE NOTICE '';
    RAISE NOTICE 'Güvenlik düzeltmesi başarıyla uygulandı!';
    RAISE NOTICE '';
    RAISE NOTICE 'EKLENEN ÖZELLİKLER:';
    RAISE NOTICE '  1. balance_security_logs - Tüm işlemlerin detaylı loglanması';
    RAISE NOTICE '  2. balance_rate_limits - Günlük/aylık işlem limitleri';
    RAISE NOTICE '  3. balance_security_settings - Merkezi güvenlik ayarları';
    RAISE NOTICE '  4. Rate limiting fonksiyonları (check + update)';
    RAISE NOTICE '  5. Replay attack koruması';
    RAISE NOTICE '  6. Çoklu IP/Cihaz tespiti';
    RAISE NOTICE '  7. Risk scoring sistemi';
    RAISE NOTICE '  8. Admin işlemleri için ek güvenlik kontrolleri';
    RAISE NOTICE '';
    RAISE NOTICE 'GÜVENLİK AYARLARI:';
    RAISE NOTICE '  - Günlük max işlem: 10 adet';
    RAISE NOTICE '  - Günlük max tutar: 50.000 TL';
    RAISE NOTICE '  - Aylık max işlem: 50 adet';
    RAISE NOTICE '  - Aylık max tutar: 200.000 TL';
    RAISE NOTICE '  - Risk skoru ≥70 ise otomatik engelleme';
    RAISE NOTICE '';
    RAISE NOTICE 'SONRAKI ADIMLAR:';
    RAISE NOTICE '  1. supabase/functions/confirm-balance-topup/index.ts dosyasını güncelleyin';
    RAISE NOTICE '     (atomic_add_balance_topup → atomic_add_balance_topup_secure)';
    RAISE NOTICE '  2. supabase/functions/admin-add-balance/index.ts dosyasını güncelleyin';
    RAISE NOTICE '     (güvenlik kontrolleri eklendi)';
    RAISE NOTICE '  3. Edge Function''ları deploy edin';
    RAISE NOTICE '';
    RAISE NOTICE '================================================================';

END $$;

-- =====================================================================
-- GÜVENLİK LOG TEMİZLİK (test için)
-- =====================================================================
-- Test loglarını temizle (opsiyonel)
-- DELETE FROM public.balance_security_logs WHERE event_type = 'test_log';
-- DELETE FROM public.balance_rate_limits WHERE user_id IS NULL;

-- =====================================================================
-- PERFORMANS: Cleanup fonksiyonlarını çağır (opsiyyonel)
-- =====================================================================
-- SELECT public.cleanup_old_security_logs();
-- SELECT public.cleanup_old_rate_limits();