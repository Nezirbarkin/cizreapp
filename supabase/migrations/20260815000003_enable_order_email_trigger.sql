-- =============================================================================
-- DOSYA: supabase/migrations/20260815000003_enable_order_email_trigger.sql
-- AMAÇ: Sipariş oluşturulduğunda satıcıya ve admine giden e-posta bildirimin
--       neden gitmediğini çözmek. Tetikleyici (trigger) elle devre dışı
--       bırakılmış durumdaydı (tgenabled = 'D'); bu yüzden sipariş INSERT'inde
--       notify_new_order_email() hiç çalışmıyor, pg_net -> Edge Function ->
--       Resend zinciri hiç başlamıyordu ve e-posta hiç gitmiyordu.
-- TARİH: 2026-08-13
--
-- TEŞHİS:
--   SELECT tgenabled FROM pg_trigger
--   WHERE tgname = 'on_order_created_send_email'
--   -> 'D' (disabled = devre dışı).
--
--   Hiçbir migration tetikleyiciyi kapatmıyor (20260204000000_order_email_
--   notification_trigger.sql içindeki DISABLE/ENABLE satırları yorum içinde).
--   Dolayısıyla devre dışı bırakma elle (Dashboard/SQL Editor) yapılmış.
--
-- ÇÖZÜM:
--   Tetikleyiciyi yeniden etkinleştir. Fonksiyon notify_new_order_email()
--   hâlâ mevcut ve migration 20260227000005'teki tanımı geçerli; bu nedenle
--   fonksiyonu yeniden tanımlamaya gerek yok, sadece ENABLE yeterli.
-- =============================================================================

-- 1) Tetikleyiciyi etkinleştir (idempotent; zaten etkinse hiçbir şey yapmaz)
ALTER TABLE public.orders ENABLE TRIGGER on_order_created_send_email;

-- 2) Doğrula: tetikleyici etkin (tgenabled = 'O') VE fonksiyon mevcut olmalı
DO $$
DECLARE
  v_en char;
  v_fn_exists boolean;
BEGIN
  SELECT tgenabled INTO v_en
  FROM pg_trigger
  WHERE tgname = 'on_order_created_send_email';

  SELECT EXISTS (
    SELECT 1
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.proname = 'notify_new_order_email'
  ) INTO v_fn_exists;

  RAISE NOTICE 'on_order_created_send_email tgenabled = % (O = aktif beklenir)', v_en;
  RAISE NOTICE 'notify_new_order_email() fonksiyonu mevcut = %', v_fn_exists;

  IF v_en IS NULL THEN
    RAISE EXCEPTION
      'Trigger on_order_created_send_email bulunamadı. Once 20260227000005 migration''ini calistirin.';
  END IF;

  IF NOT v_fn_exists THEN
    RAISE EXCEPTION
      'notify_new_order_email() fonksiyonu yok; trigger ateslenince hata verir. Once 20260227000005 migration''ini calistirin.';
  END IF;

  IF v_en <> 'O' THEN
    RAISE EXCEPTION 'Trigger hala devre disinda (tgenabled = %).', v_en;
  END IF;
END $$;

SELECT '✅ Sipariş e-posta tetikleyicisi etkinleştirildi (tgenabled = O)' AS result;
