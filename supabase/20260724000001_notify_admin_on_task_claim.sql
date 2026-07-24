-- =============================================================================
-- 20260724000001_notify_admin_on_task_claim.sql
--
-- Kullanıcı bir göreve katıldığında (claim_task RPC) admin'e bildirim
-- gönderilmiyordu. Bu migration claim_task fonksiyonunu, submission
-- oluşturulduktan sonra tüm adminlere 'admin_notification' tipinde bir
-- bildirim ekleyecek şekilde günceller (bkz. notify_admin_balance_topup ile
-- aynı desen).
-- =============================================================================

CREATE OR REPLACE FUNCTION public.claim_task(p_task_id UUID)
RETURNS UUID  -- submission_id döner
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_user_id     UUID := auth.uid();
  v_task        RECORD;
  v_submission_id UUID;
  v_user_name   TEXT;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Oturum açmanız gerekli';
  END IF;

  -- Görevi kilitle (satır yoksa NO_DATA_FOUND)
  SELECT * INTO v_task FROM public.tasks WHERE id = p_task_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Görev bulunamadı';
  END IF;

  -- Aktif mi?
  IF v_task.status != 'active' THEN
    RAISE EXCEPTION 'Bu görev şu anda aktif değil';
  END IF;

  -- Süresi geçmiş mi?
  IF v_task.expires_at IS NOT NULL AND v_task.expires_at <= NOW() THEN
    RAISE EXCEPTION 'Bu görevin süresi dolmuş';
  END IF;

  -- Henüz başlamamış mı?
  IF v_task.starts_at > NOW() THEN
    RAISE EXCEPTION 'Bu görev henüz başlamadı';
  END IF;

  -- Kullanıcı daha önce pending/approved başvuru yapmış mı?
  IF EXISTS (
    SELECT 1 FROM public.task_submissions
    WHERE task_id = p_task_id
      AND user_id = v_user_id
      AND status IN ('pending', 'approved')
  ) THEN
    RAISE EXCEPTION 'Bu göreve zaten katıldınız';
  END IF;

  -- Limit doldu mu?
  IF v_task.current_participants >= v_task.max_participants THEN
    RAISE EXCEPTION 'Bu görev için katılımcı limiti dolmuş';
  END IF;

  -- current_participants++
  UPDATE public.tasks
     SET current_participants = current_participants + 1,
         -- Limit dolduysa otomatik tamamlandı
         status = CASE
                    WHEN current_participants + 1 >= max_participants
                    THEN 'completed'::task_status
                    ELSE status
                  END
   WHERE id = p_task_id
   RETURNING current_participants, status INTO v_task.current_participants, v_task.status;

  -- Pending submission oluştur
  INSERT INTO public.task_submissions (task_id, user_id, status)
  VALUES (p_task_id, v_user_id, 'pending')
  RETURNING id INTO v_submission_id;

  -- Admin(ler)e katılım bildirimi gönder
  SELECT full_name INTO v_user_name FROM public.profiles WHERE id = v_user_id;

  INSERT INTO public.notifications (user_id, type, title, content, entity_id)
  SELECT
    p.id,
    'admin_notification',
    'Göreve Katılım',
    COALESCE(v_user_name, 'Bir kullanıcı') || ' "' || v_task.title || '" görevine katıldı.',
    v_submission_id::text
  FROM public.profiles p
  WHERE p.role = 'admin';

  RETURN v_submission_id;
END;
$$;

-- Anonymous çağıramamalı
REVOKE ALL ON FUNCTION public.claim_task(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.claim_task(UUID) TO authenticated;

NOTIFY pgrst, 'reload schema';

DO $$ BEGIN
  RAISE NOTICE '✅ 20260724000001 — claim_task admin bildirimi eklendi';
END $$;
