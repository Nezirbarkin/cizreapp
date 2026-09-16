-- =============================================================================
-- 20260908140004_bot_like_schedule_spread_backlog.sql
-- -----------------------------------------------------------------------------
-- DÜZELTME: `schedule_bot_likes()` beğeni vadesini gönderinin YAYIN anına göre
-- hesaplıyordu ve geçmişte kalan vadeleri `now() - 5 dakika`ya sabitliyordu.
-- Sonuç: birikmiş (örneğin 8 gün önce paylaşılmış) gönderilerin tüm beğenileri
-- BİR SONRAKİ cron turunda aynı anda düşerdi — kullanıcı tek seferde onlarca
-- bildirim alır ve bunun otomatik olduğu anında anlaşılırdı.
--
-- Yeni davranış: hesaplanan vade geçmişte kalıyorsa beğeni, şu andan itibaren
-- `bot_like_max_hours` içine RASTGELE dağıtılır. Böylece hem ilk kurulumdaki
-- birikmiş gönderiler hem de sonradan gelenler doğal bir tempoda beğenilir.
-- =============================================================================

begin;

CREATE OR REPLACE FUNCTION public.schedule_bot_likes(p_max_posts integer DEFAULT 100)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_post record;
  v_min_hours integer;
  v_max_hours integer;
  v_min_count integer;
  v_max_count integer;
  v_lookback integer;
  v_count integer;
  v_total integer := 0;
BEGIN
  IF NOT private.bot_setting_bool('bot_auto_like_enabled', true) THEN
    RETURN 0;
  END IF;

  v_min_hours := GREATEST(private.bot_setting_int('bot_like_min_hours', 1), 0);
  v_max_hours := GREATEST(private.bot_setting_int('bot_like_max_hours', 48), v_min_hours);
  v_min_count := GREATEST(private.bot_setting_int('bot_like_min_count', 1), 0);
  v_max_count := GREATEST(private.bot_setting_int('bot_like_max_count', 7), v_min_count);
  v_lookback  := GREATEST(private.bot_setting_int('bot_like_lookback_days', 10), 1);

  FOR v_post IN
    SELECT po.id, po.user_id, po.created_at
    FROM public.posts po
    JOIN public.profiles author ON author.id = po.user_id
    WHERE po.is_active = true
      AND po.created_at >= now() - make_interval(days => v_lookback)
      AND author.status = 'active'::public.user_status
      AND COALESCE(author.profile_is_public, true) = true
      AND NOT EXISTS (
        SELECT 1 FROM public.bot_like_jobs j WHERE j.post_id = po.id
      )
    ORDER BY po.created_at DESC
    LIMIT GREATEST(COALESCE(p_max_posts, 100), 1)
  LOOP
    v_count := v_min_count + floor(random() * (v_max_count - v_min_count + 1))::integer;
    IF v_count <= 0 THEN
      CONTINUE;
    END IF;

    INSERT INTO public.bot_like_jobs (bot_id, post_id, due_at)
    SELECT
      b.id,
      v_post.id,
      -- Vade gönderinin yayın anına göre kurulur; geçmişte kalıyorsa
      -- (birikmiş gönderi) şu andan itibaren pencereye YAYILIR.
      CASE
        WHEN d.due < now()
          THEN now() + make_interval(secs => (random() * v_max_hours * 3600)::integer)
        ELSE d.due
      END
    FROM public.profiles b
    JOIN public.bot_accounts ba ON ba.id = b.id
    CROSS JOIN LATERAL (
      SELECT v_post.created_at + make_interval(
        secs => ((v_min_hours * 3600)
                 + (random() * GREATEST(v_max_hours - v_min_hours, 0) * 3600))::integer
      ) AS due
    ) d
    WHERE b.is_bot = true
      AND b.status = 'active'::public.user_status
      AND ba.is_active = true
      AND b.id <> v_post.user_id
      AND NOT EXISTS (
        SELECT 1 FROM public.post_likes pl
        WHERE pl.post_id = v_post.id AND pl.user_id = b.id
      )
    ORDER BY random()
    LIMIT v_count
    ON CONFLICT (bot_id, post_id) DO NOTHING;

    v_total := v_total + 1;
  END LOOP;

  RETURN v_total;
END;
$$;

REVOKE ALL ON FUNCTION public.schedule_bot_likes(integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.schedule_bot_likes(integer) TO service_role;

commit;
