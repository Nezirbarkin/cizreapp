-- =============================================================================
-- FIX-HATA-1: Bakiye Yükleme Race Condition Düzeltmesi
-- -----------------------------------------------------------------------------
-- SORUN:
--   confirm-balance-topup Edge Function JS tarafında ayrı SELECT→UPDATE yapıyordu.
--   Aynı token ile iki eşzamanlı iyzico callback geldiğinde her iki istek de
--   aynı `balance_before` değerini okuyup üzerine yazıyordu:
--
--     Callback A: okur balance=100, yazar balance=150
--     Callback B: okur balance=100, yazar balance=150  ← 50 TL kayıp!
--
--   Dahası, pending status'lü balance_transactions kaydı (create-balance-topup
--   tarafından oluşturuluyor) "completed" status'lü yeni kayıt oluşturulunca
--   kullanıcı geçmişinde çift kayıt görüyordu (bir pending, bir completed).
--
-- ÇÖZÜM:
--   Tek PostgreSQL transaction'ında:
--     1. user_balances satırına FOR UPDATE lock koy (race condition önle)
--     2. Mevcut pending balance_transactions kaydını SİL (çift kayıt önle)
--     3. Yeni balance_transactions kaydı OLUŞTUR (status=completed)
--     4. user_balances.balance + total_earned güncelle
--     Tüm adımlar aynı transaction içinde atomik olarak çalışır.
--
-- GÜVENLİK:
--   - SECURITY DEFINER: service_role yetkisiyle çalışır (RLS bypass)
--   - sıradışıl kayıt yoksa fonksiyon hata vermez, sessizce başarısız olur
--   - Idempotent değil: aynı p_pending_txn_id ile iki kez çağrılmamalı
--     (bu kontrol Edge Function tarafında yapılmalı, zaten var)
-- =============================================================================

CREATE OR REPLACE FUNCTION public.atomic_add_balance_topup(
    p_user_id         UUID,
    p_amount          DECIMAL(12, 2),
    p_pending_txn_id UUID,
    p_payment_id      VARCHAR(100),
    p_paid_price     DECIMAL(10, 2)
)
RETURNS TABLE(
    balance_before NUMERIC,
    balance_after  NUMERIC
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_balance_id       UUID;
    v_current_balance DECIMAL(12, 2) := 0;
    v_balance_before   DECIMAL(12, 2);
    v_balance_after    DECIMAL(12, 2);
    v_new_total_earned DECIMAL(12, 2);
    v_pending_exists  BOOLEAN;
BEGIN
    -- 1) Kullanıcının bakiyesini bul ve satırı KİLİTLE
    --    FOR UPDATE: ikinci callback bu satırın kilidini bekler,
    --    böylece sıralı okuma-yazma garanti altında olur.
    SELECT id, balance, total_earned
      INTO v_balance_id, v_current_balance, v_new_total_earned
      FROM public.user_balances
     WHERE user_id = p_user_id
    FOR UPDATE;

    v_balance_before := v_current_balance;
    v_balance_after  := v_current_balance + p_amount;
    v_new_total_earned := COALESCE(v_new_total_earned, 0) + p_amount;

    IF v_balance_id IS NULL THEN
        -- Bakiye kaydı yoksa oluştur (INSERT ... ON CONFLICT ile güvenli)
        INSERT INTO public.user_balances (user_id, balance, total_earned)
        VALUES (p_user_id, p_amount, p_amount)
        ON CONFLICT (user_id) DO UPDATE
          SET balance     = EXCLUDED.balance,
              total_earned = EXCLUDED.total_earned
        RETURNING balance INTO v_balance_after;

        -- INSERT ... ON CONFLICT DO UPDATE döndürdüğünde
        -- v_balance_after değerini kullan (ON CONFLICT yoksa zaten 1 satır INSERT olmuştur)
        v_balance_before := 0;

    ELSE
        -- Mevcut bakiyeyi güncelle
        UPDATE public.user_balances
           SET balance     = v_balance_after,
               total_earned = v_new_total_earned,
               updated_at   = NOW()
         WHERE id = v_balance_id;
    END IF;

    -- 2) Pending status'lü eski kaydı SİL (çift kayıt önleme)
    --    Eğer kayıt zaten silindiyse veya yoksa hata verme (sessizce atla)
    DELETE FROM public.balance_transactions
     WHERE id = p_pending_txn_id
       AND status = 'pending';

    -- 3) Yeni balance_transactions kaydı oluştur (status=completed)
    --    Artık kullanıcının transaction geçmişinde sadece tek kayıt olacak.
    INSERT INTO public.balance_transactions (
        user_id,
        type,
        amount,
        net_amount,
        balance_before,
        balance_after,
        reference_type,
        reference_id,
        status,
        description,
        payment_method,
        payment_reference,
        metadata
    ) VALUES (
        p_user_id,
        'topup',
        p_amount,
        p_amount,
        v_balance_before,
        v_balance_after,
        'topup',
        p_pending_txn_id,
        'completed',
        'Bakiye yükleme - ' || p_amount || ' TL',
        'card',
        p_payment_id,
        jsonb_build_object(
            'payment_id',   p_payment_id,
            'paid_price',   p_paid_price,
            'confirmed_at', NOW()::text
        )
    );

    -- 4) Sonucu döndür
    RETURN QUERY SELECT v_balance_before, v_balance_after;

END;
$$;

COMMENT ON FUNCTION public.atomic_add_balance_topup IS
'Atomik bakiye yükleme: FOR UPDATE lock + pending kayıt silme + completed kayıt oluşturma. Race condition koruması sağlar.';

-- =============================================================================
-- GRANT (mevcut grant'lar zaten var ama yeniden verelim)
-- =============================================================================
GRANT EXECUTE ON FUNCTION public.atomic_add_balance_topup TO authenticated;
GRANT EXECUTE ON FUNCTION public.atomic_add_balance_topup TO service_role;

DO $$
BEGIN
    RAISE NOTICE '✅ atomic_add_balance_topup fonksiyonu oluşturuldu';
    RAISE NOTICE '   - FOR UPDATE lock: race condition koruması';
    RAISE NOTICE '   - Pending kayıt silme: çift kayıt önleme';
    RAISE NOTICE '   - balance_before/balance_after döndürme: push notification için';
END $$;
