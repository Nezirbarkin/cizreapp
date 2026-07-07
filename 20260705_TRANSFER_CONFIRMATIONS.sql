-- ============================================================================
-- 20260705_TRANSFER_CONFIRMATIONS.sql
-- ============================================================================
-- Amaç: Havale/EFT ile yapılan bakiye yüklemeleri için ADMIN ONAY AKıŞı.
--       Müşteri "Sisteme Bildir" dediğinde yeni tabloya INSERT edilir;
--       admin "Havale Onayları" sekmesinden Onayla/Reddet eder.
--       Onaylanınca OTOMATİK bakiye eklenir + kullanıcıya push + uygulama
--       içi notification gider.
--
-- DİKKAT — idempotent. Varolan yapıya dokunmaz.
-- VAR OLAN _sendTransferNotification (notifications tablosuna yazan) korunur.
-- Yeni akış PARALEL çalışır; topup_screen.dart yeni servise geçirilir.
--
-- PROJE_HAVIZA_FUNCTIONS.md §1.3'teki add_to_balance RPC'si kullanılır
-- (FOR UPDATE lock + atomik).
-- ============================================================================

BEGIN;

-- 1. Yeni tablo
CREATE TABLE IF NOT EXISTS public.transfer_confirmations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  amount NUMERIC(10,2) NOT NULL CHECK (amount > 0),
  bank_account_id UUID REFERENCES public.bank_accounts(id) ON DELETE SET NULL,
  note TEXT,
  status TEXT NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending','approved','rejected')),
  admin_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  admin_note TEXT,
  user_notified BOOLEAN NOT NULL DEFAULT FALSE,
  balance_added BOOLEAN NOT NULL DEFAULT FALSE,
  receipt_url TEXT, -- opsiyonel: dekont fotoğrafı
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  resolved_at TIMESTAMPTZ
);

-- 2. Indexler
CREATE INDEX IF NOT EXISTS idx_transfer_confirmations_pending
  ON public.transfer_confirmations(status, created_at DESC)
  WHERE status = 'pending';

CREATE INDEX IF NOT EXISTS idx_transfer_confirmations_user
  ON public.transfer_confirmations(user_id, created_at DESC);

-- 3. RLS
ALTER TABLE public.transfer_confirmations ENABLE ROW LEVEL SECURITY;

-- 3a. Kullanıcı kendi kayıtlarını görebilir
DROP POLICY IF EXISTS transfer_confirmations_select_own ON public.transfer_confirmations;
CREATE POLICY transfer_confirmations_select_own
  ON public.transfer_confirmations
  FOR SELECT
  TO authenticated
  USING (user_id = auth.uid());

-- 3b. Admin tüm kayıtları görebilir
DROP POLICY IF EXISTS transfer_confirmations_select_admin ON public.transfer_confirmations;
CREATE POLICY transfer_confirmations_select_admin
  ON public.transfer_confirmations
  FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.profiles
      WHERE id = auth.uid() AND role = 'admin'
    )
  );

-- 3c. Kullanıcı kendi adına INSERT (user_id = auth.uid olmalı)
DROP POLICY IF EXISTS transfer_confirmations_insert_own ON public.transfer_confirmations;
CREATE POLICY transfer_confirmations_insert_own
  ON public.transfer_confirmations
  FOR INSERT
  TO authenticated
  WITH CHECK (user_id = auth.uid() AND status = 'pending');

-- 3d. Sadece admin UPDATE (status, admin_id, admin_note, balance_added, user_notified)
DROP POLICY IF EXISTS transfer_confirmations_update_admin ON public.transfer_confirmations;
CREATE POLICY transfer_confirmations_update_admin
  ON public.transfer_confirmations
  FOR UPDATE
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.profiles
      WHERE id = auth.uid() AND role = 'admin'
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.profiles
      WHERE id = auth.uid() AND role = 'admin'
    )
  );

-- 4. Yardımcı: admin kontrol fonksiyonu (güvenli, 42501 riski yok)
--    Mevcut is_admin() SECURITY DEFINER'dır; RPC içinde çağırırken
--    GRANT sorun çıkarabilir. Bu yüzden subquery kullanıyoruz.

-- 5. approve_transfer_confirmation RPC
--    NOT: SECURITY DEFINER değil → çağıranın auth.uid() kullanılır,
--    RLS bypass YAPMAZ. İçeride admin kontrolü yapılır.
CREATE OR REPLACE FUNCTION public.approve_transfer_confirmation(
  p_confirmation_id UUID,
  p_admin_note TEXT DEFAULT NULL
) RETURNS JSON
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  v_admin UUID;
  v_is_admin BOOLEAN;
  v_conf RECORD;
BEGIN
  v_admin := auth.uid();

  IF v_admin IS NULL THEN
    RAISE EXCEPTION 'Yetkisiz: giriş gerekli' USING ERRCODE = '42501';
  END IF;

  -- Admin kontrolü (subquery, RLS bypass yapmaz — auth.uid() bazlı)
  SELECT EXISTS (
    SELECT 1 FROM public.profiles WHERE id = v_admin AND role = 'admin'
  ) INTO v_is_admin;

  IF NOT v_is_admin THEN
    RAISE EXCEPTION 'Bu işlem sadece admin tarafından yapılabilir' USING ERRCODE = '42501';
  END IF;

  -- FOR UPDATE → aynı anda iki admin onaylayamaz
  SELECT * INTO v_conf FROM public.transfer_confirmations
   WHERE id = p_confirmation_id
   FOR UPDATE;

  IF v_conf IS NULL THEN
    RAISE EXCEPTION 'Onay kaydı bulunamadı';
  END IF;

  IF v_conf.status <> 'pending' THEN
    RAISE EXCEPTION 'Bu kayıt zaten %s olarak işlenmiş', v_conf.status;
  END IF;

  IF v_conf.balance_added THEN
    RAISE EXCEPTION 'Bu kayıt için bakiye zaten eklenmiş';
  END IF;

  -- add_to_balance RPC ile atomik bakiye ekleme
  -- PROJE_HAVIZA_FUNCTIONS §1.3: FOR UPDATE lock + balance_transactions insert
  -- p_reference_id UUID tipinde, v_conf.id de UUID.
  PERFORM public.add_to_balance(
    p_user_id := v_conf.user_id,
    p_amount := v_conf.amount,
    p_type := 'topup'::balance_transaction_type,
    p_reference_type := 'transfer_confirmation',
    p_reference_id := v_conf.id,
    p_description := COALESCE(p_admin_note, 'Havale onayı'),
    p_payment_method := 'transfer'
  );

  -- transfer_confirmations update
  UPDATE public.transfer_confirmations
  SET status = 'approved',
      admin_id = v_admin,
      admin_note = p_admin_note,
      balance_added = TRUE,
      resolved_at = NOW()
  WHERE id = p_confirmation_id;

  RETURN json_build_object(
    'status', 'approved',
    'confirmation_id', p_confirmation_id,
    'user_id', v_conf.user_id,
    'amount', v_conf.amount
  );
END;
$$;

-- 6. reject_transfer_confirmation RPC
CREATE OR REPLACE FUNCTION public.reject_transfer_confirmation(
  p_confirmation_id UUID,
  p_admin_note TEXT DEFAULT NULL
) RETURNS JSON
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  v_admin UUID;
  v_is_admin BOOLEAN;
  v_conf RECORD;
BEGIN
  v_admin := auth.uid();

  IF v_admin IS NULL THEN
    RAISE EXCEPTION 'Yetkisiz: giriş gerekli' USING ERRCODE = '42501';
  END IF;

  SELECT EXISTS (
    SELECT 1 FROM public.profiles WHERE id = v_admin AND role = 'admin'
  ) INTO v_is_admin;

  IF NOT v_is_admin THEN
    RAISE EXCEPTION 'Bu işlem sadece admin tarafından yapılabilir' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_conf FROM public.transfer_confirmations
   WHERE id = p_confirmation_id FOR UPDATE;

  IF v_conf IS NULL THEN
    RAISE EXCEPTION 'Onay kaydı bulunamadı';
  END IF;

  IF v_conf.status <> 'pending' THEN
    RAISE EXCEPTION 'Bu kayıt zaten %s olarak işlenmiş', v_conf.status;
  END IF;

  UPDATE public.transfer_confirmations
  SET status = 'rejected',
      admin_id = v_admin,
      admin_note = p_admin_note,
      balance_added = FALSE,
      resolved_at = NOW()
  WHERE id = p_confirmation_id;

  RETURN json_build_object(
    'status', 'rejected',
    'confirmation_id', p_confirmation_id,
    'user_id', v_conf.user_id,
    'amount', v_conf.amount
  );
END;
$$;

-- 7. GRANT — RPC'ler authenticated tarafından çağrılabilsin
--    (anon çağırmamalı)
GRANT EXECUTE ON FUNCTION public.approve_transfer_confirmation(UUID, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.reject_transfer_confirmation(UUID, TEXT) TO authenticated;

-- 8. Kullanıcıya bildirim trigger'ı (status değişince uygulama içi bildirim)
--    Push notification (FCM) için mevcut DM push trigger deseni kullanılır;
--    burada sadece notifications tablosuna insert ediyoruz (uygulama içi).
--    Push gönderimi Flutter admin tarafından sağlanır (admin_add_balance veya
--    notifications_content_v2.dart ile, daha sonra eklenebilir).
CREATE OR REPLACE FUNCTION public.notify_transfer_confirmation_resolved()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Sadece status değiştiyse (pending → approved/rejected)
  IF OLD.status = 'pending' AND NEW.status IN ('approved', 'rejected') THEN
    INSERT INTO public.notifications (
      user_id, type, title, content, entity_id
    ) VALUES (
      NEW.user_id,
      'admin_notification',
      CASE
        WHEN NEW.status = 'approved'
          THEN 'Havale Bildiriminiz Onaylandı'
        ELSE
          'Havale Bildiriminiz Reddedildi'
      END,
      CASE
        WHEN NEW.status = 'approved'
          THEN '₺' || NEW.amount::TEXT || ' bakiyenize yansıtıldı.'
        ELSE
          'Sebep: ' || COALESCE(NEW.admin_note, 'Belirtilmedi')
      END,
      NEW.id::TEXT
    );

    NEW.user_notified := TRUE;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_notify_transfer_confirmation_resolved
  ON public.transfer_confirmations;
CREATE TRIGGER trg_notify_transfer_confirmation_resolved
  BEFORE UPDATE ON public.transfer_confirmations
  FOR EACH ROW
  EXECUTE FUNCTION public.notify_transfer_confirmation_resolved();

-- 9. RLS: kullanıcı kendi kaydında UPDATE yapamasın (sadece admin)
--    (Zaten sadece admin policy var, ama ek olarak kullanıcı UPDATE'i tamamen engelle)
DROP POLICY IF EXISTS transfer_confirmations_update_block_users ON public.transfer_confirmations;
-- DELETE politikası yok → kullanıcı silemez (FK CASCADE zaten auth.users'a bağlı)

-- 10. PostgREST reload
NOTIFY pgrst, 'reload schema';

COMMIT;

-- ============================================================================
-- DOĞRULAMA
-- ============================================================================
-- SELECT column_name, data_type FROM information_schema.columns
-- WHERE table_schema = 'public' AND table_name = 'transfer_confirmations';
--
-- SELECT proname FROM pg_proc WHERE proname IN
--   ('approve_transfer_confirmation', 'reject_transfer_confirmation');
-- ============================================================================