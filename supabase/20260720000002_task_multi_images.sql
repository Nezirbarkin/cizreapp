-- =============================================================================
-- 20260720000002_task_multi_images.sql
-- Admin görev formu artık birden fazla görsel yükleyebilsin.
-- image_url (tekil, geriye uyumluluk) korunur; image_urls (dizi) eklenir.
-- =============================================================================

SET search_path = public, pg_temp;

ALTER TABLE public.tasks ADD COLUMN IF NOT EXISTS image_urls TEXT[] NOT NULL DEFAULT '{}';

-- Mevcut tekil image_url'leri diziye taşı
UPDATE public.tasks
SET image_urls = ARRAY[image_url]
WHERE image_url IS NOT NULL AND image_urls = '{}';

DROP FUNCTION IF EXISTS public.get_active_tasks(UUID, INTEGER, INTEGER);

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
  image_url TEXT,
  image_urls TEXT[],
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
    t.image_url,
    t.image_urls,
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

NOTIFY pgrst, 'reload schema';
