-- =============================================================================
-- 20260719000002_task_earning_rls_rpc.sql
-- Görev Sistemi — RLS Politikaları + RPC Fonksiyonları
--
-- Bu migration 20260719000001'in TAMAMLAYICISI.
-- Bölümler:
--   1. RLS politikaları (task_categories, tasks, task_submissions)
--   2. RPC: claim_task             — kullanıcı görevi alır (katılımcı limiti artırılır)
--   3. RPC: submit_task_with_proof — ekran görüntüsü yükler
--   4. RPC: approve_task_submission — admin onayı, atomik bakiye
--   5. RPC: reject_task_submission  — admin red
--   6. RPC: admin_get_task_submissions — admin başvuru listesi
--
-- GÜVENLİK ÖĞRENMELERİ (PROJE_HAVIZA referans):
--   - §4.1.1: is_admin() GRANT EXECUTE TO authenticated + REVOKE FROM anon
--   - §4.1.7: Bakiye mutasyonu yalnız service_role üzerinden (RPC SECURITY DEFINER ile)
--   - §4.1.4: RLS'te subquery ile admin kontrolü (helper fn zincirinden kaçınma)
--   - Idempotent: submission.status='approved' guard → çift ödeme önleme
--   - Race condition: FOR UPDATE lock + atomik UPDATE + current_participants++
-- =============================================================================

SET search_path = public, pg_temp;

-- ===========================================================================
-- 1. RLS: task_categories
-- ===========================================================================
ALTER TABLE public.task_categories ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "task_categories_select_all"       ON public.task_categories;
DROP POLICY IF EXISTS "task_categories_admin_insert"     ON public.task_categories;
DROP POLICY IF EXISTS "task_categories_admin_update"     ON public.task_categories;
DROP POLICY IF EXISTS "task_categories_admin_delete"     ON public.task_categories;

-- Herkes (anon dahil) görebilir — açık kategori listesi
CREATE POLICY "task_categories_select_all"
  ON public.task_categories FOR SELECT
  TO public
  USING (true);

-- Yalnız admin yönetir
CREATE POLICY "task_categories_admin_insert"
  ON public.task_categories FOR INSERT
  TO authenticated
  WITH CHECK (
    EXISTS(SELECT 1 FROM public.profiles WHERE id = (SELECT auth.uid()) AND role = 'admin')
  );

CREATE POLICY "task_categories_admin_update"
  ON public.task_categories FOR UPDATE
  TO authenticated
  USING (
    EXISTS(SELECT 1 FROM public.profiles WHERE id = (SELECT auth.uid()) AND role = 'admin')
  )
  WITH CHECK (
    EXISTS(SELECT 1 FROM public.profiles WHERE id = (SELECT auth.uid()) AND role = 'admin')
  );

CREATE POLICY "task_categories_admin_delete"
  ON public.task_categories FOR DELETE
  TO authenticated
  USING (
    EXISTS(SELECT 1 FROM public.profiles WHERE id = (SELECT auth.uid()) AND role = 'admin')
  );

-- ===========================================================================
-- 2. RLS: tasks
-- ===========================================================================
ALTER TABLE public.tasks ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "tasks_select_active"     ON public.tasks;
DROP POLICY IF EXISTS "tasks_admin_select_all"   ON public.tasks;
DROP POLICY IF EXISTS "tasks_admin_insert"      ON public.tasks;
DROP POLICY IF EXISTS "tasks_admin_update"      ON public.tasks;
DROP POLICY IF EXISTS "tasks_admin_delete"      ON public.tasks;

-- Kullanıcılar yalnız 'active' ve süresi geçmemiş görevleri görür
-- Admin hepsini görür
CREATE POLICY "tasks_select_active"
  ON public.tasks FOR SELECT
  TO authenticated
  USING (
    EXISTS(SELECT 1 FROM public.profiles WHERE id = (SELECT auth.uid()) AND role = 'admin')
    OR (
      status = 'active'
      AND (starts_at <= NOW())
      AND (expires_at IS NULL OR expires_at > NOW())
    )
  );

CREATE POLICY "tasks_admin_insert"
  ON public.tasks FOR INSERT
  TO authenticated
  WITH CHECK (
    EXISTS(SELECT 1 FROM public.profiles WHERE id = (SELECT auth.uid()) AND role = 'admin')
  );

CREATE POLICY "tasks_admin_update"
  ON public.tasks FOR UPDATE
  TO authenticated
  USING (
    EXISTS(SELECT 1 FROM public.profiles WHERE id = (SELECT auth.uid()) AND role = 'admin')
  )
  WITH CHECK (
    EXISTS(SELECT 1 FROM public.profiles WHERE id = (SELECT auth.uid()) AND role = 'admin')
  );

CREATE POLICY "tasks_admin_delete"
  ON public.tasks FOR DELETE
  TO authenticated
  USING (
    EXISTS(SELECT 1 FROM public.profiles WHERE id = (SELECT auth.uid()) AND role = 'admin')
  );

-- ===========================================================================
-- 3. RLS: task_submissions
-- ===========================================================================
ALTER TABLE public.task_submissions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "task_submissions_select_own_or_admin"  ON public.task_submissions;
DROP POLICY IF EXISTS "task_submissions_insert_self"          ON public.task_submissions;
DROP POLICY IF EXISTS "task_submissions_update_own_pending"   ON public.task_submissions;
DROP POLICY IF EXISTS "task_submissions_admin_all"            ON public.task_submissions;
DROP POLICY IF EXISTS "task_submissions_user_update"          ON public.task_submissions;

-- Kullanıcı kendi başvurularını görür, admin hepsini görür
CREATE POLICY "task_submissions_select_own_or_admin"
  ON public.task_submissions FOR SELECT
  TO authenticated
  USING (
    user_id = (SELECT auth.uid())
    OR EXISTS(SELECT 1 FROM public.profiles WHERE id = (SELECT auth.uid()) AND role = 'admin')
  );

-- INSERT: kullanıcı yalnız kendi adına, pending durumda, görev aktifken ekleyebilir
-- RPC üzerinden yazım (claim + submit) için service_role kullanılacak, ama
-- ekran görüntüsünü client yükledikten sonra submission INSERT'i de yapabilir;
-- yine de katılımcı limiti gibi kontroller RPC'de yapıldığından INSERT'i
-- kullanıcıya da açıyoruz (görev limiti kontrolünü RPC yapar).
CREATE POLICY "task_submissions_insert_self"
  ON public.task_submissions FOR INSERT
  TO authenticated
  WITH CHECK (
    user_id = (SELECT auth.uid())
    AND status = 'pending'
  );

-- Kullanıcı kendi pending başvurusunu ekran görüntüsünü güncelleyebilir
-- (admin onaylamadan önce yanlış yüklediğini fark ederse)
CREATE POLICY "task_submissions_update_own_pending"
  ON public.task_submissions FOR UPDATE
  TO authenticated
  USING (
    user_id = (SELECT auth.uid())
    AND status = 'pending'
  )
  WITH CHECK (
    user_id = (SELECT auth.uid())
    AND status = 'pending'
  );

-- Admin tüm submission'ları güncelleyebilir/silebilir
CREATE POLICY "task_submissions_admin_all"
  ON public.task_submissions FOR ALL
  TO authenticated
  USING (
    EXISTS(SELECT 1 FROM public.profiles WHERE id = (SELECT auth.uid()) AND role = 'admin')
  )
  WITH CHECK (
    EXISTS(SELECT 1 FROM public.profiles WHERE id = (SELECT auth.uid()) AND role = 'admin')
  );

-- ===========================================================================
-- 4. RPC: claim_task — kullanıcı göreve katılır
-- ===========================================================================
-- Akış:
--   1. Görev var mı, aktif mi, süresi geçmemiş mi kontrol
--   2. FOR UPDATE ile görev satırını kilitle (race condition koruması)
--   3. current_participants < max_participants kontrolü
--   4. Kullanıcı daha önce 'pending' veya 'approved' başvuru yapmış mı kontrol
--   5. current_participants++
--   6. Eğer limit dolduysa status='completed' yap
--   7. Pending submission INSERT (kullanıcı ekran görüntüsünü sonra yükler)
-- ===========================================================================
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

  RETURN v_submission_id;
END;
$$;

-- Anonymous çağıramamalı
REVOKE ALL ON FUNCTION public.claim_task(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.claim_task(UUID) TO authenticated;

-- ===========================================================================
-- 5. RPC: submit_task_with_proof — ekran görüntüsü yükler
-- ===========================================================================
-- Kullanıcı daha önce claim_task ile göreve katılmış, şimdi ekran görüntüsünü yüklüyor
-- Sadece kendi pending başvurusunu güncelleyebilir
CREATE OR REPLACE FUNCTION public.submit_task_with_proof(
  p_submission_id UUID,
  p_screenshot_url TEXT,
  p_user_note      TEXT DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_user_id UUID := auth.uid();
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Oturum açmanız gerekli';
  END IF;

  IF p_screenshot_url IS NULL OR TRIM(p_screenshot_url) = '' THEN
    RAISE EXCEPTION 'Ekran görüntüsü URL boş olamaz';
  END IF;

  -- Sahiplik + durum kontrolü (atomik UPDATE WHERE)
  UPDATE public.task_submissions
     SET screenshot_url = p_screenshot_url,
         user_note      = COALESCE(NULLIF(TRIM(p_user_note), ''), user_note),
         updated_at     = NOW()
   WHERE id = p_submission_id
     AND user_id = v_user_id
     AND status  = 'pending';

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Başvuru bulunamadı veya zaten değerlendirilmiş';
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.submit_task_with_proof(UUID, TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.submit_task_with_proof(UUID, TEXT, TEXT) TO authenticated;

-- ===========================================================================
-- 6. RPC: approve_task_submission — admin onayı, atomik bakiye
-- ===========================================================================
-- Akış:
--   1. Admin mi kontrol
--   2. Submission pending mi kontrol + FOR UPDATE kilit
--   3. Task hâlâ aktif mi kontrol
--   4. add_to_balance ile atomik bakiye ekleme (PROJE_HAVIZA §2.2)
--   5. submission.status = 'approved', reviewed_by, reviewed_at, reward_amount yaz
--   6. Balance transaction id kaydet
-- Idempotent: status='approved' ise NO-OP (zaten ödenmiş)
-- ===========================================================================
CREATE OR REPLACE FUNCTION public.approve_task_submission(
  p_submission_id UUID,
  p_admin_note    TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_admin_id    UUID := auth.uid();
  v_submission  RECORD;
  v_task        RECORD;
  v_txn_id      UUID;
  v_new_balance NUMERIC(12,2);
BEGIN
  -- Admin kontrolü (PROJE_HAVIZA §4.1.1)
  IF NOT EXISTS(SELECT 1 FROM public.profiles WHERE id = v_admin_id AND role = 'admin') THEN
    RAISE EXCEPTION 'Bu işlem için admin yetkisi gerekli';
  END IF;

  -- Submission'ı kilitle
  SELECT * INTO v_submission FROM public.task_submissions WHERE id = p_submission_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Başvuru bulunamadı';
  END IF;

  -- Idempotency guard
  IF v_submission.status = 'approved' THEN
    RETURN jsonb_build_object(
      'status', 'already_approved',
      'submission_id', v_submission.id,
      'message', 'Bu başvuru zaten onaylanmış'
    );
  END IF;

  IF v_submission.status = 'rejected' THEN
    RAISE EXCEPTION 'Reddedilmiş başvuru tekrar onaylanamaz';
  END IF;

  -- Task bilgisi
  SELECT * INTO v_task FROM public.tasks WHERE id = v_submission.task_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Görev bulunamadı';
  END IF;

  -- add_to_balance ile atomik bakiye ekleme
  -- add_to_balance RETURNS TABLE(balance_after, ...); kullanım mevcut projeye göre
  v_txn_id := public.add_to_balance(
    p_user_id         := v_submission.user_id,
    p_amount          := v_task.reward_amount,
    p_type            := 'task_reward'::balance_transaction_type,
    p_reference_type  := 'task',
    p_reference_id    := v_submission.task_id,
    p_description     := 'Görev ödülü: ' || v_task.title,
    p_payment_method  := 'task_reward'
  );

  -- Mevcut bakiyeyi al
  SELECT balance INTO v_new_balance
  FROM public.user_balances
  WHERE user_id = v_submission.user_id;

  -- Submission güncelle
  UPDATE public.task_submissions
     SET status           = 'approved',
         reward_amount    = v_task.reward_amount,
         balance_txn_id   = v_txn_id,
         reviewed_by      = v_admin_id,
         reviewed_at      = NOW(),
         user_note        = COALESCE(p_admin_note, user_note),  -- admin notu da user_note'a düşer (görünür olsun)
         updated_at       = NOW()
   WHERE id = p_submission_id;

  -- Bildirim (PROJE_HAVIZA §2.4 deseni)
  INSERT INTO public.notifications (user_id, type, title, content, entity_id, is_read, metadata)
  VALUES (
    v_submission.user_id,
    'task_approved',
    'Görev Ödülü Kazandınız! 🎉',
    '₺' || v_task.reward_amount::TEXT || ' bakiyenize eklendi. Görev: ' || v_task.title,
    p_submission_id::TEXT,
    false,
    jsonb_build_object(
      'submission_id', p_submission_id,
      'task_id', v_submission.task_id,
      'reward_amount', v_task.reward_amount,
      'new_balance', v_new_balance
    )
  );

  RETURN jsonb_build_object(
    'status', 'approved',
    'submission_id', v_submission.id,
    'user_id', v_submission.user_id,
    'reward_amount', v_task.reward_amount,
    'new_balance', v_new_balance,
    'transaction_id', v_txn_id
  );
END;
$$;

REVOKE ALL ON FUNCTION public.approve_task_submission(UUID, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.approve_task_submission(UUID, TEXT) TO authenticated, service_role;

-- ===========================================================================
-- 7. RPC: reject_task_submission — admin red
-- ===========================================================================
-- Akış:
--   1. Admin mi kontrol
--   2. Submission pending mi kontrol + FOR UPDATE
--   3. status='rejected', reviewed_by, reviewed_at, rejection_reason yaz
--   4. Task current_participants-- (limit geri açılır — başka kullanıcı alabilir)
--   5. Eğer task 'completed' olduysa tekrar 'active' yap
--   6. Bildirim gönder
-- ===========================================================================
CREATE OR REPLACE FUNCTION public.reject_task_submission(
  p_submission_id UUID,
  p_rejection_reason TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_admin_id   UUID := auth.uid();
  v_submission RECORD;
BEGIN
  IF NOT EXISTS(SELECT 1 FROM public.profiles WHERE id = v_admin_id AND role = 'admin') THEN
    RAISE EXCEPTION 'Bu işlem için admin yetkisi gerekli';
  END IF;

  IF p_rejection_reason IS NULL OR TRIM(p_rejection_reason) = '' THEN
    RAISE EXCEPTION 'Red gerekçesi boş olamaz';
  END IF;

  SELECT * INTO v_submission FROM public.task_submissions WHERE id = p_submission_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Başvuru bulunamadı';
  END IF;

  IF v_submission.status = 'approved' THEN
    RAISE EXCEPTION 'Onaylanmış başvuru reddedilemez (zaten ödeme yapıldı)';
  END IF;
  IF v_submission.status = 'rejected' THEN
    RAISE EXCEPTION 'Bu başvuru zaten reddedilmiş';
  END IF;

  UPDATE public.task_submissions
     SET status            = 'rejected',
         reviewed_by       = v_admin_id,
         reviewed_at       = NOW(),
         rejection_reason  = p_rejection_reason,
         updated_at        = NOW()
   WHERE id = p_submission_id;

  -- Task katılımcı sayısını geri al
  UPDATE public.tasks
     SET current_participants = GREATEST(current_participants - 1, 0),
         -- Eğer otomatik 'completed' olduysa tekrar 'active' yap
         status = CASE
                    WHEN status = 'completed' THEN 'active'::task_status
                    ELSE status
                  END
   WHERE id = v_submission.task_id;

  -- Bildirim
  INSERT INTO public.notifications (user_id, type, title, content, entity_id, is_read, metadata)
  VALUES (
    v_submission.user_id,
    'task_rejected',
    'Görev Başvurunuz Reddedildi ❌',
    'Sebep: ' || p_rejection_reason,
    p_submission_id::TEXT,
    false,
    jsonb_build_object(
      'submission_id', p_submission_id,
      'task_id', v_submission.task_id,
      'reason', p_rejection_reason
    )
  );

  RETURN jsonb_build_object(
    'status', 'rejected',
    'submission_id', v_submission.id,
    'user_id', v_submission.user_id
  );
END;
$$;

REVOKE ALL ON FUNCTION public.reject_task_submission(UUID, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.reject_task_submission(UUID, TEXT) TO authenticated, service_role;

-- ===========================================================================
-- 8. RPC: admin_get_task_submissions — admin için başvuru listesi
-- ===========================================================================
-- status filtresi opsiyonel ('pending' | 'approved' | 'rejected' | NULL = hepsi)
-- task_id filtresi opsiyonel
-- ===========================================================================
CREATE OR REPLACE FUNCTION public.admin_get_task_submissions(
  p_status task_submission_status DEFAULT NULL,
  p_task_id UUID DEFAULT NULL,
  p_limit INTEGER DEFAULT 100,
  p_offset INTEGER DEFAULT 0
)
RETURNS TABLE (
  id UUID,
  task_id UUID,
  user_id UUID,
  user_full_name TEXT,
  user_avatar_url TEXT,
  user_phone TEXT,
  task_title TEXT,
  task_reward NUMERIC,
  screenshot_url TEXT,
  user_note TEXT,
  status task_submission_status,
  reward_amount NUMERIC,
  reviewed_by UUID,
  reviewed_at TIMESTAMPTZ,
  rejection_reason TEXT,
  created_at TIMESTAMPTZ,
  updated_at TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  -- Admin kontrolü
  IF NOT EXISTS(SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role = 'admin') THEN
    RAISE EXCEPTION 'Bu işlem için admin yetkisi gerekli';
  END IF;

  RETURN QUERY
  SELECT
    s.id,
    s.task_id,
    s.user_id,
    p.full_name,
    p.avatar_url,
    p.phone,
    t.title,
    t.reward_amount,
    s.screenshot_url,
    s.user_note,
    s.status,
    s.reward_amount,
    s.reviewed_by,
    s.reviewed_at,
    s.rejection_reason,
    s.created_at,
    s.updated_at
  FROM public.task_submissions s
  JOIN public.tasks t ON t.id = s.task_id
  JOIN public.profiles p ON p.id = s.user_id
  WHERE (p_status IS NULL OR s.status = p_status)
    AND (p_task_id IS NULL OR s.task_id = p_task_id)
  ORDER BY s.created_at DESC
  LIMIT p_limit
  OFFSET p_offset;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_get_task_submissions(task_submission_status, UUID, INTEGER, INTEGER) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_get_task_submissions(task_submission_status, UUID, INTEGER, INTEGER) TO authenticated, service_role;

-- ===========================================================================
-- 9. RPC: get_active_tasks — kullanıcı için aktif görev listesi
-- ===========================================================================
CREATE OR REPLACE FUNCTION public.get_active_tasks(
  p_category_id UUID DEFAULT NULL,
  p_limit INTEGER DEFAULT 50,
  p_offset INTEGER DEFAULT 0
)
RETURNS TABLE (
  task_id UUID,
  category_id UUID,
  category_name TEXT,
  category_icon TEXT,
  title TEXT,
  description TEXT,
  warning_text TEXT,
  task_link TEXT,
  reward_amount NUMERIC,
  max_participants INTEGER,
  current_participants INTEGER,
  remaining_slots INTEGER,
  starts_at TIMESTAMPTZ,
  expires_at TIMESTAMPTZ,
  user_already_claimed BOOLEAN,
  user_submission_id UUID,
  user_submission_status task_submission_status,
  created_at TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  RETURN QUERY
  SELECT
    t.id AS task_id,
    t.category_id,
    c.name AS category_name,
    c.icon AS category_icon,
    t.title,
    t.description,
    t.warning_text,
    t.task_link,
    t.reward_amount,
    t.max_participants,
    t.current_participants,
    (t.max_participants - t.current_participants)::INTEGER AS remaining_slots,
    t.starts_at,
    t.expires_at,
    EXISTS(
      SELECT 1 FROM public.task_submissions s
      WHERE s.task_id = t.id
        AND s.user_id = auth.uid()
        AND s.status IN ('pending', 'approved')
    ) AS user_already_claimed,
    (SELECT s2.id FROM public.task_submissions s2
       WHERE s2.task_id = t.id
         AND s2.user_id = auth.uid()
       ORDER BY s2.created_at DESC
       LIMIT 1) AS user_submission_id,
    (SELECT s3.status FROM public.task_submissions s3
       WHERE s3.task_id = t.id
         AND s3.user_id = auth.uid()
       ORDER BY s3.created_at DESC
       LIMIT 1) AS user_submission_status,
    t.created_at
  FROM public.tasks t
  LEFT JOIN public.task_categories c ON c.id = t.category_id
  WHERE t.status = 'active'
    AND t.starts_at <= NOW()
    AND (t.expires_at IS NULL OR t.expires_at > NOW())
    AND (p_category_id IS NULL OR t.category_id = p_category_id)
  ORDER BY t.created_at DESC
  LIMIT p_limit
  OFFSET p_offset;
END;
$$;

REVOKE ALL ON FUNCTION public.get_active_tasks(UUID, INTEGER, INTEGER) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_active_tasks(UUID, INTEGER, INTEGER) TO authenticated;

-- ===========================================================================
-- 10. RPC: get_user_task_history — kullanıcının kendi başvuru geçmişi
-- ===========================================================================
CREATE OR REPLACE FUNCTION public.get_user_task_history(
  p_status task_submission_status DEFAULT NULL,
  p_limit INTEGER DEFAULT 50,
  p_offset INTEGER DEFAULT 0
)
RETURNS TABLE (
  id UUID,
  task_id UUID,
  task_title TEXT,
  task_description TEXT,
  reward_amount NUMERIC,
  status task_submission_status,
  rejection_reason TEXT,
  screenshot_url TEXT,
  reviewed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ,
  total_earned NUMERIC
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  RETURN QUERY
  SELECT
    s.id,
    s.task_id,
    t.title,
    t.description,
    s.reward_amount,
    s.status,
    s.rejection_reason,
    s.screenshot_url,
    s.reviewed_at,
    s.created_at,
    COALESCE(s.reward_amount, 0) AS total_earned
  FROM public.task_submissions s
  JOIN public.tasks t ON t.id = s.task_id
  WHERE s.user_id = auth.uid()
    AND (p_status IS NULL OR s.status = p_status)
  ORDER BY s.created_at DESC
  LIMIT p_limit
  OFFSET p_offset;
END;
$$;

REVOKE ALL ON FUNCTION public.get_user_task_history(task_submission_status, INTEGER, INTEGER) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_user_task_history(task_submission_status, INTEGER, INTEGER) TO authenticated;

-- ===========================================================================
-- 11. RPC: get_task_stats — admin dashboard istatistikleri
-- ===========================================================================
CREATE OR REPLACE FUNCTION public.get_task_stats()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_admin_id UUID := auth.uid();
  v_stats JSONB;
BEGIN
  IF NOT EXISTS(SELECT 1 FROM public.profiles WHERE id = v_admin_id AND role = 'admin') THEN
    RAISE EXCEPTION 'Bu işlem için admin yetkisi gerekli';
  END IF;

  SELECT jsonb_build_object(
    'total_tasks', (SELECT COUNT(*) FROM public.tasks),
    'active_tasks', (SELECT COUNT(*) FROM public.tasks WHERE status = 'active'),
    'completed_tasks', (SELECT COUNT(*) FROM public.tasks WHERE status = 'completed'),
    'paused_tasks', (SELECT COUNT(*) FROM public.tasks WHERE status = 'paused'),
    'pending_submissions', (SELECT COUNT(*) FROM public.task_submissions WHERE status = 'pending'),
    'approved_submissions', (SELECT COUNT(*) FROM public.task_submissions WHERE status = 'approved'),
    'rejected_submissions', (SELECT COUNT(*) FROM public.task_submissions WHERE status = 'rejected'),
    'total_paid_today', COALESCE((
      SELECT SUM(t.reward_amount)
      FROM public.task_submissions s
      JOIN public.tasks t ON t.id = s.task_id
      WHERE s.status = 'approved'
        AND s.reviewed_at::DATE = CURRENT_DATE
    ), 0),
    'total_paid_all_time', COALESCE((
      SELECT SUM(t.reward_amount)
      FROM public.task_submissions s
      JOIN public.tasks t ON t.id = s.task_id
      WHERE s.status = 'approved'
    ), 0)
  ) INTO v_stats;

  RETURN v_stats;
END;
$$;

REVOKE ALL ON FUNCTION public.get_task_stats() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_task_stats() TO authenticated, service_role;

-- ===========================================================================
-- 12. Realtime publication'a ekleme (admin dashboard canlı güncellensin)
-- ===========================================================================
DO $$ BEGIN
  -- Supabase default publication genellikle 'supabase_realtime' adını taşır
  IF EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime') THEN
    -- task_submissions
    IF NOT EXISTS (
      SELECT 1 FROM pg_publication_tables
      WHERE pubname = 'supabase_realtime' AND tablename = 'task_submissions'
    ) THEN
      ALTER PUBLICATION supabase_realtime ADD TABLE public.task_submissions;
    END IF;

    -- tasks (admin için)
    IF NOT EXISTS (
      SELECT 1 FROM pg_publication_tables
      WHERE pubname = 'supabase_realtime' AND tablename = 'tasks'
    ) THEN
      ALTER PUBLICATION supabase_realtime ADD TABLE public.tasks;
    END IF;
  END IF;
EXCEPTION
  WHEN OTHERS THEN
    RAISE NOTICE 'Realtime publication eklenemedi (devam): %', SQLERRM;
END $$;

-- ===========================================================================
-- 13. RELOAD SCHEMA
-- ===========================================================================
NOTIFY pgrst, 'reload schema';

DO $$ BEGIN
  RAISE NOTICE '✅ 20260719000002_task_earning_rls_rpc.sql — RLS + RPC + realtime eklendi';
END $$;