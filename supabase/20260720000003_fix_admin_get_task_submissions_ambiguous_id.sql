-- =============================================================================
-- 20260720000003_fix_admin_get_task_submissions_ambiguous_id.sql
--
-- admin_get_task_submissions RPC hatası: 42702 column reference "id" is ambiguous
-- Sebep: RETURNS TABLE(id UUID, ...) OUT parametresi, admin kontrolündeki
-- "WHERE id = auth.uid()" ifadesindeki niteliksiz "id" ile çakışıyor
-- (plpgsql variable_conflict=error). Çözüm: profiles.id şeklinde nitelemek.
-- =============================================================================

SET search_path = public, pg_temp;

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
  -- Admin kontrolü ("id" yerine "profiles.id" — OUT parametresiyle çakışmasın)
  IF NOT EXISTS(SELECT 1 FROM public.profiles WHERE profiles.id = auth.uid() AND profiles.role = 'admin') THEN
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

NOTIFY pgrst, 'reload schema';

DO $$ BEGIN
  RAISE NOTICE '✅ 20260720000003 — admin_get_task_submissions ambiguous id düzeltildi';
END $$;
