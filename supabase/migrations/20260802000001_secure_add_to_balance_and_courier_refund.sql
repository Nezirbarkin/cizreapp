-- =============================================================================
-- KRİTİK GÜVENLİK: add_to_balance kapısını kapat + atomik admin iptal RPC'si
-- ----------------------------------------------------------------------------
-- Tespit edilen açık (2026-08-02 canlı linter):
--   1) public.add_to_balance SECURITY DEFINER olarak çalışıyor ve istemci
--      tarafından doğrudan çağrılabiliyor. p_user_id/p_amount istemciden
--      geldiği için authenticated rolündeki herhangi bir kullanıcı kendi
--      istediği user_id'ye sınırsız bakiye ekleyebiliyor.
--   2) 20260727000008_harden_balance_rpc_permissions.sql bu yetkiyi kapatmayı
--      amaçlıyordu fakat canlı şemada REVOKE uygulanmamış (veya sonradan
--      yetki tekrar GRANT edilmiş) — security_definer_acl_after.json
--      {postgres=X/postgres,service_role=X/postgres,authenticated=X/postgres}
--      ACL'i ile doğrulanıyor.
--   3) admin_package_requests_tab.dart içindeki _cancel akışı atomik değildi:
--      önce status update, sonra istemciden doğrudan add_to_balance çağrısı,
--      hataları yutuyor ve kullanıcıya ücretin iade edildiğini bildiriyordu.
--
-- Düzeltme (ileriye dönük, idempotent):
--   A) public.add_to_balance'in TÜM overload'larında (pg_proc tabanlı):
--        - EXECUTE PUBLIC, anon, authenticated'dan kaldır
--        - Yalnız service_role'a bırak
--        - search_path'i sabitle (güvenli)
--   B) Atomik, server-side doğrulamalı yeni RPC:
--        admin_cancel_courier_request_with_refund(p_request_id uuid)
--      Bu RPC SECURITY DEFINER; admin kontrolü + courier_requests FOR UPDATE
--      kilidi + add_to_balance + notifications + audit tek transaction'da.
--      İstemciden user_id veya iade tutarı kabul etmez; bunları sunucu
--      tarafında doğrulanmış kayıtlardan çeker.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- A) add_to_balance: yalnız service_role
-- -----------------------------------------------------------------------------
DO $harden_add_to_balance$
DECLARE
  v_function regprocedure;
BEGIN
  FOR v_function IN
    SELECT p.oid::regprocedure
    FROM pg_proc AS p
    JOIN pg_namespace AS n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.proname = 'add_to_balance'
  LOOP
    EXECUTE format(
      'REVOKE EXECUTE ON FUNCTION %s FROM PUBLIC, anon, authenticated',
      v_function
    );
    EXECUTE format(
      'GRANT EXECUTE ON FUNCTION %s TO service_role',
      v_function
    );
    -- search_path güvenli değilse sabitle (güvenli default)
    EXECUTE format(
      'ALTER FUNCTION %s SET search_path = public, pg_temp',
      v_function
    );
  END LOOP;
END
$harden_add_to_balance$;

COMMENT ON FUNCTION public.add_to_balance IS
'Atomik bakiye ekleme. Sadece SECURITY DEFINER iç akışlar ve service_role
çağrıları için açıktır. İstemci rolleri (anon/authenticated) kapalıdır.';

-- -----------------------------------------------------------------------------
-- B) Atomik admin iptal + iade RPC'si
-- -----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.admin_cancel_courier_request_with_refund(UUID);

CREATE FUNCTION public.admin_cancel_courier_request_with_refund(
  p_request_id UUID
)
RETURNS TABLE(
  request_id UUID,
  sender_id UUID,
  refund_amount NUMERIC(12, 2),
  balance_transaction_id UUID,
  new_status TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_admin_id        CONSTANT UUID := auth.uid();
  v_caller_role     CONSTANT TEXT := COALESCE(auth.role(), '');
  v_request         public.courier_requests%ROWTYPE;
  v_existing_tx     UUID;
  v_refund_amount   NUMERIC(12, 2);
  v_payment_tx      public.balance_transactions%ROWTYPE;
  v_tx_id           UUID;
  v_new_status      TEXT := 'cancelled';
BEGIN
  ---------------------------------------------------------------------------
  -- 1) Kimlik doğrulama
  ---------------------------------------------------------------------------
  IF v_admin_id IS NULL THEN
    RAISE EXCEPTION 'Oturum açmanız gerekiyor' USING ERRCODE = '42501';
  END IF;

  IF v_caller_role <> 'service_role' AND NOT public.is_admin() THEN
    RAISE EXCEPTION 'Bu işlem için admin yetkisi gereklidir'
      USING ERRCODE = '42501';
  END IF;

  IF p_request_id IS NULL THEN
    RAISE EXCEPTION 'İptal edilecek talep kimliği zorunludur'
      USING ERRCODE = '22023';
  END IF;

  ---------------------------------------------------------------------------
  -- 2) courier_requests kaydını kilitle (FOR UPDATE)
  ---------------------------------------------------------------------------
  SELECT cr.*
    INTO v_request
    FROM public.courier_requests AS cr
   WHERE cr.id = p_request_id
   FOR UPDATE;

  IF v_request.id IS NULL THEN
    RAISE EXCEPTION 'Paket talebi bulunamadı' USING ERRCODE = 'P0002';
  END IF;

  ---------------------------------------------------------------------------
  -- 3) İptal edilebilir durum kontrolü
  ---------------------------------------------------------------------------
  IF v_request.status NOT IN ('pending', 'accepted') THEN
    RAISE EXCEPTION
      'Bu aşamadaki paket talebi (status: %) iptal edilemez',
      v_request.status
      USING ERRCODE = 'P0001';
  END IF;

  ---------------------------------------------------------------------------
  -- 4) Daha önce iade yapılmış mı? (idempotent guard)
  --    Eğer aynı talep için completed refund transaction varsa, ikinci kez
  --    bakiye eklememeli ve aynı transaction_id'yi döndürmeliyiz.
  ---------------------------------------------------------------------------
  SELECT bt.id
    INTO v_existing_tx
    FROM public.balance_transactions AS bt
   WHERE bt.reference_type = 'courier_request'
     AND bt.reference_id = p_request_id
     AND bt.type = 'refund'::public.balance_transaction_type
     AND bt.status = 'completed'
   LIMIT 1;

  IF v_existing_tx IS NOT NULL THEN
    UPDATE public.courier_requests AS cr
       SET status     = 'cancelled',
           updated_at = NOW()
     WHERE cr.id = p_request_id;

    RETURN QUERY
    SELECT p_request_id,
           v_request.sender_id,
           0::NUMERIC(12, 2),
           v_existing_tx,
           'cancelled'::TEXT;
    RETURN;
  END IF;

  ---------------------------------------------------------------------------
  -- 5) İade tutarını doğrulanmış ödeme kaydından çek.
  --    Mantık: paket gönderiminde deduct_from_balance tarafından
  --    courier_payment tipinde bir balance_transactions oluşturulmuş olmalı.
  --    Bu tutar tek doğru kaynaktır; istemciden ASLA gelmez.
  ---------------------------------------------------------------------------
  SELECT bt.*
    INTO v_payment_tx
    FROM public.balance_transactions AS bt
   WHERE bt.reference_type = 'courier_request'
     AND bt.reference_id = p_request_id
     AND bt.user_id = v_request.sender_id
     AND bt.type = 'courier_payment'::public.balance_transaction_type
     AND bt.status = 'completed'
   ORDER BY bt.created_at DESC
   LIMIT 1;

  -- Ödeme kaydı bulunamazsa total_fee'ye düş; o da yoksa 0 (iptal edilir,
  -- sadece bakiye iadesi yapılmaz).
  IF v_payment_tx.id IS NOT NULL THEN
    v_refund_amount := v_payment_tx.amount;
  ELSE
    v_refund_amount := COALESCE(v_request.total_fee, 0);
  END IF;

  IF v_refund_amount IS NULL OR v_refund_amount < 0 THEN
    v_refund_amount := 0;
  END IF;

  ---------------------------------------------------------------------------
  -- 6) Bakiyeye iade (varsa). add_to_balance SECURITY DEFINER olduğu için
  --    iç çağrıda yetki kontrolü devre dışı; service_role yerine fonksiyon
  --    sahibi olarak çalışır.
  ---------------------------------------------------------------------------
  IF v_refund_amount > 0 THEN
    v_tx_id := public.add_to_balance(
      p_user_id          := v_request.sender_id,
      p_amount           := v_refund_amount,
      p_type             := 'refund'::public.balance_transaction_type,
      p_reference_type   := 'courier_request',
      p_reference_id     := p_request_id,
      p_description      := 'Admin tarafından iptal edilen paket talebi iadesi',
      p_payment_method   := 'balance',
      p_payment_reference := NULL,
      p_metadata         := jsonb_build_object(
                              'source', 'admin_cancel_courier_request_with_refund',
                              'admin_id', v_admin_id,
                              'request_id', p_request_id,
                              'payment_transaction_id',
                                CASE WHEN v_payment_tx.id IS NULL
                                     THEN NULL ELSE v_payment_tx.id END
                           )
    );
  END IF;

  ---------------------------------------------------------------------------
  -- 7) Talep durumunu güncelle
  ---------------------------------------------------------------------------
  UPDATE public.courier_requests AS cr
     SET status     = 'cancelled',
         updated_at = NOW()
   WHERE cr.id = p_request_id;

  ---------------------------------------------------------------------------
  -- 8) Gönderene bildirim (tek bildirim — Flutter'da ikinci kez gönderilmez)
  ---------------------------------------------------------------------------
  IF v_request.sender_id IS NOT NULL THEN
    INSERT INTO public.notifications (
      user_id, type, title, content,
      entity_id, entity_type, metadata
    ) VALUES (
      v_request.sender_id,
      'cancellation_approved',
      CASE WHEN v_refund_amount > 0
           THEN 'Paket İptal Edildi - İade Yapıldı'
           ELSE 'Paket İptal Edildi' END,
      CASE WHEN v_refund_amount > 0
           THEN 'Gönderdiğiniz paket talebi admin tarafından iptal edildi. ₺' ||
                to_char(v_refund_amount, 'FM999999990.00') ||
                ' bakiyenize eklendi.'
           ELSE 'Gönderdiğiniz paket talebi admin tarafından iptal edildi.' END,
      p_request_id::text,
      'courier_request',
      jsonb_build_object(
        'request_id', p_request_id,
        'refund_amount', v_refund_amount,
        'balance_transaction_id', v_tx_id,
        'cancelled_by_admin', v_admin_id
      )
    );
  END IF;

  RETURN QUERY
  SELECT p_request_id,
         v_request.sender_id,
         v_refund_amount,
         v_tx_id,
         v_new_status;
END;
$$;

COMMENT ON FUNCTION public.admin_cancel_courier_request_with_refund(UUID) IS
'Admin tarafından paket talebini atomik olarak iptal eder: courier_requests
FOR UPDATE kilidi, admin kontrolü (auth.uid + public.is_admin), aynı talep
için daha önce refund yapılmadığını doğrular, doğrulanmış ödeme kaydından
iade tutarını çeker, add_to_balance + status update + notification kaydını
tek transaction içinde tamamlar. İstemciden user_id veya iade tutarı
kabul etmez. PUBLIC/anon kapalı; yalnız authenticated (admin kontrolü
ile) ve service_role.';

REVOKE EXECUTE ON FUNCTION public.admin_cancel_courier_request_with_refund(UUID)
  FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION public.admin_cancel_courier_request_with_refund(UUID)
  TO authenticated, service_role;
