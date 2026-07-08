-- ============================================================================
-- 20260707_NOTIFICATIONS_AND_BALANCE_FIX.sql
-- ----------------------------------------------------------------------------
-- İki sorunu çözer:
--
-- PROBLEM A — Bakiye ile ödemede sipariş iptali:
--   use-balance-for-order Edge function, orders.payment_status ENUM'una
--   'completed'/'partial' yazmaya çalışıyordu. ENUM yalnızca
--   ('pending','paid','refunded') kabul ettiği için UPDATE patlıyor → bakiye
--   iade → sipariş iptal. Edge function tarafı 'paid' kullanacak şekilde
--   düzeltildi; burada ENUM'a bir şey eklenmesine GEREK YOK (paid zaten var).
--   Bu migration yalnızca güvenlik için enum'un idempotent olarak tutarlı
--   olmasını sağlar (herhangi bir etkisi yoksa zararsızdır).
--
-- PROBLEM B — Satıcıya "new_order" bildirimi eklenemiyor (RLS 42501):
--   Root cause: kullanıcı, KENDİ adına değil SATICI adına (user_id = satıcı)
--   notifications satırı insert etmeye çalışıyor. notifications_insert_policy
--   WITH CHECK (true) gibi görünse de, merged_notifications_insert_66363608
--   policy'si "auth.uid() IS NOT NULL" koşullu ve INSERT başkası adına
--   yapıldığında RLS ihlali (42501) veriyor.
--   Çözüm: SECURITY DEFINER bir RPC (add_notification) ekliyoruz; RPC service
--   role yetkisiyle (RLS bypass) herhangi bir kullanıcıya bildirim yazabilir.
--   Frontend/Edge functionlar doğrudan INSERT yerine bu RPC'yi çağırır.
-- ============================================================================

-- ============================================================================
-- BÖLÜM 1 — payment_status ENUM idempotent doğrulama
-- (paid zaten enum'da var; bu kısım yalnızca ekstra değer eklememizi
--  gerektirse diye bırakılmıştır — şu an 'paid' yeterli.)
-- ============================================================================
DO $$
BEGIN
  -- 'paid' enum'da mı? Yoksa ekle (ileride oluşabilecek schema sapmaları için).
  IF NOT EXISTS (
    SELECT 1 FROM pg_enum e
    JOIN pg_type t ON t.oid = e.enumtypid
    WHERE t.typname = 'payment_status' AND e.enumlabel = 'paid'
  ) THEN
    ALTER TYPE public.payment_status ADD VALUE IF NOT EXISTS 'paid';
    RAISE NOTICE 'payment_status enum''a ''paid'' eklendi';
  ELSE
    RAISE NOTICE 'payment_status enum''da ''paid'' zaten mevcut';
  END IF;
END $$;


-- ============================================================================
-- BÖLÜM 2 — add_notification RPC (SECURITY DEFINER)
-- Herhangi bir authenticated kullanıcı, BAŞKA bir kullanıcıya bildirim
-- yazabilir (örn. siparişte satıcıya 'new_order', kuryeye 'courier_new_order').
-- RLS bypass eder çünkü SECURITY DEFINER + tablo owner yetkisiyle çalışır.
-- ============================================================================
CREATE OR REPLACE FUNCTION public.add_notification(
  p_user_id      UUID,
  p_type         TEXT,
  p_title        TEXT,
  p_content      TEXT,
  p_actor_id     UUID DEFAULT NULL,
  p_actor_name   TEXT DEFAULT NULL,
  p_actor_avatar TEXT DEFAULT NULL,
  p_entity_id    TEXT DEFAULT NULL,
  p_entity_image TEXT DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_new_id UUID;
BEGIN
  INSERT INTO public.notifications (
    user_id, type, title, content,
    actor_id, actor_name, actor_avatar,
    entity_id, entity_image,
    is_read, created_at
  )
  VALUES (
    p_user_id, p_type, p_title, p_content,
    p_actor_id, p_actor_name, p_actor_avatar,
    p_entity_id, p_entity_image,
    FALSE, NOW()
  )
  RETURNING id INTO v_new_id;

  RETURN v_new_id;
END;
$$;

COMMENT ON FUNCTION public.add_notification IS
'Başka bir kullanıcıya bildirim eklemek için SECURITY DEFINER RPC. RLS bypass eder; sipariş/kurye/takip gibi çapraz kullanıcı bildirimleri frontend ve Edge functionlar tarafından doğrudan INSERT yerine bu RPC ile yazılır.';

-- RPC'yi authenticated rolüne aç (anon kapalı — anonymous bildirim olmasın).
REVOKE ALL ON FUNCTION public.add_notification(UUID, TEXT, TEXT, TEXT, UUID, TEXT, TEXT, TEXT, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.add_notification(UUID, TEXT, TEXT, TEXT, UUID, TEXT, TEXT, TEXT, TEXT) TO authenticated;


-- ============================================================================
-- BÖLÜM 3 — notifications INSERT RLS policy'lerini netleştir
-- Çakışan/duplike insert policy'lerini bırakıp tek bir net kural koyalım:
--   - Kullanıcı yalnızca KENDİ adına insert edebilir (user_id = auth.uid()).
--   - Başka kullanıcıya bildirim yazmak add_notification RPC ile yapılır.
-- Service role her zaman bypass eder (RLS'i atlar).
-- ============================================================================
DROP POLICY IF EXISTS "merged_notifications_insert_66363608" ON public.notifications;
DROP POLICY IF EXISTS "notifications_insert_policy" ON public.notifications;
DROP POLICY IF EXISTS "Service can create notifications" ON public.notifications;

-- Kullanıcı kendi adına bildirim ekleyebilir (örn. kendi hatırlatması).
CREATE POLICY "notifications_insert_own_policy"
ON public.notifications
FOR INSERT
TO authenticated
WITH CHECK (user_id = auth.uid());

-- ============================================================================
-- BÖLÜM 4 — verification
-- (Manuel test için yorum; otomatik çalışmaz.)
-- ============================================================================
-- SELECT id, user_id, type, title FROM public.notifications
--   ORDER BY created_at DESC LIMIT 5;