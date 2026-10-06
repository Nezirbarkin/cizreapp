-- =============================================================================
-- Görev 4.7 — Bot yorumları: manuel (şimdi / zamanlı) ve otomatik
-- =============================================================================
--
-- Bot hesapları (profiles.is_bot + bot_accounts, 71 adet) admin panelinden
-- yönetiliyordu; gönderi paylaşıyor, takip ediyor ve beğeniyorlardı. Bu göç
-- yorum ekler:
--   * bot_comment_library — yorum metinleri (tonlu), yalnız admin RPC'leri.
--   * bot_comment_jobs    — kuyruk (source 'auto' | 'manual'). Bir bot bir
--     gönderiye en çok BİR otomatik yorum yapar (kısmi benzersiz indeks).
--   * schedule_bot_comments() — son gönderileri BİR KEZ değerlendirir
--     (bot_comment_seen_posts): olasılık %p ile [min, max] bot, gönderinin
--     yayınından [min_saat, max_saat] sonra; geçmişte kalan vade şu andan
--     itibaren yayılır (beğenilerdeki gibi — birikmiş işler tek turda düşmesin).
--   * process_bot_comment_jobs() — vadesi gelen yorumları post_comments'e yazar
--     (gönderi gizlendiyse/bot pasifse atlar).
--   * Otomatik yorum VARSAYILAN KAPALI (beğeniden çok daha görünür; admin
--     Ayarlar'dan açar).
--   * notify_post_comment artık gönderi sahibi BOT ise bildirim yazmaz
--     (takip/beğeni bildirimleriyle aynı kural; bot-bot yorumu notifications'ı
--     şişirmesin). Gerçek kullanıcıya giden yorum bildirimi korunur.

BEGIN;

-- -----------------------------------------------------------------------------
-- 1) Yorum kitaplığı
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.bot_comment_library (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  body text NOT NULL CHECK (char_length(btrim(body)) BETWEEN 1 AND 300),
  tone text NOT NULL DEFAULT 'genel'
    CHECK (tone IN ('genel', 'tebrik', 'soru', 'mizah', 'yerel', 'destek')),
  is_active boolean NOT NULL DEFAULT true,
  use_count integer NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX IF NOT EXISTS bot_comment_library_body_key
  ON public.bot_comment_library (lower(btrim(body)));

ALTER TABLE public.bot_comment_library ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.bot_comment_library FROM PUBLIC, anon, authenticated;
GRANT ALL ON TABLE public.bot_comment_library TO service_role;

INSERT INTO public.bot_comment_library (body, tone) VALUES
  ('Çok güzel olmuş 👏', 'tebrik'),
  ('Eline sağlık', 'tebrik'),
  ('Harika bir paylaşım', 'genel'),
  ('Bayıldım 😍', 'genel'),
  ('Tebrikler, çok başarılı', 'tebrik'),
  ('Muhteşem görünüyor', 'genel'),
  ('Ellerine sağlık, çok emek var belli', 'tebrik'),
  ('Ne güzel bir kare', 'genel'),
  ('Bunu görünce içim açıldı', 'genel'),
  ('Süper 👍', 'genel'),
  ('Hayırlı olsun', 'destek'),
  ('Kolay gelsin', 'destek'),
  ('Allah bereket versin', 'destek'),
  ('Yolun açık olsun', 'destek'),
  ('Başarılarının devamını dilerim', 'destek'),
  ('Emeğine sağlık', 'tebrik'),
  ('Paylaşım için teşekkürler', 'genel'),
  ('Çok hoş 🌸', 'genel'),
  ('Mükemmel olmuş', 'tebrik'),
  ('Tam benlik 😄', 'mizah'),
  ('Bunu kaçırmamak lazım', 'genel'),
  ('Harika fikir', 'genel'),
  ('Aynen katılıyorum', 'genel'),
  ('Çok doğru söylemişsin', 'genel'),
  ('Gözüme çok güzel geldi', 'genel'),
  ('İyi ki paylaşmışsın', 'genel'),
  ('Böyle paylaşımların devamını bekliyoruz', 'destek'),
  ('Neresi burası? Çok güzelmiş', 'soru'),
  ('Ne zaman çekildi bu?', 'soru'),
  ('Fiyatı ne kadar?', 'soru'),
  ('Nereden bulabilirim?', 'soru'),
  ('Tarifini paylaşır mısın? 😋', 'soru'),
  ('Bir dahakine ben de gelmek isterim', 'genel'),
  ('Cizre''nin en güzel yerlerinden', 'yerel'),
  ('Cizre''de böyle güzellikler olduğunu bilmiyordum', 'yerel'),
  ('Dicle kenarı her zaman ayrı güzel', 'yerel'),
  ('Memleket gibisi yok ❤️', 'yerel'),
  ('Cizre''ye yakışmış', 'yerel'),
  ('Şırnak''tan selamlar 👋', 'yerel'),
  ('Bizim oralar bu mevsimde çok güzel oluyor', 'yerel'),
  ('Canım Cizre 😍', 'yerel'),
  ('Harikasın 😂', 'mizah'),
  ('Güldüm ama çok 😄', 'mizah'),
  ('Bu ne güzellik böyle', 'genel'),
  ('Çok şık 👌', 'genel'),
  ('Kalite belli oluyor', 'tebrik'),
  ('Tebrik ederim, çok güzel iş', 'tebrik'),
  ('Beğenmemek elde değil', 'genel'),
  ('Rengi çok güzel', 'genel'),
  ('Görünce acıktım 😋', 'mizah'),
  ('Ben de denemek istiyorum', 'genel'),
  ('Tavsiye için teşekkürler', 'genel'),
  ('Selamlar, kolay gelsin 🙏', 'destek'),
  ('Sağlıkla kullanın', 'destek'),
  ('Harika bir gün geçirmişsin', 'genel'),
  ('Çok tatlı 🥰', 'genel'),
  ('Bunu çok sevdim', 'genel'),
  ('Paylaştığın için sağ ol', 'genel'),
  ('Daha çok paylaşım bekliyoruz', 'destek'),
  ('Harika, devamı gelsin', 'destek')
ON CONFLICT DO NOTHING;

-- -----------------------------------------------------------------------------
-- 2) Yorum kuyruğu ve değerlendirilmiş gönderiler
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.bot_comment_jobs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  bot_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  post_id uuid NOT NULL REFERENCES public.posts(id) ON DELETE CASCADE,
  body text NOT NULL CHECK (char_length(btrim(body)) BETWEEN 1 AND 1000),
  library_id uuid REFERENCES public.bot_comment_library(id) ON DELETE SET NULL,
  source text NOT NULL DEFAULT 'auto' CHECK (source IN ('auto', 'manual')),
  due_at timestamptz NOT NULL,
  status text NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending', 'done', 'skipped', 'failed', 'cancelled')),
  comment_id uuid,
  created_by uuid,
  processed_at timestamptz,
  error_message text,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX IF NOT EXISTS bot_comment_jobs_auto_unique
  ON public.bot_comment_jobs (bot_id, post_id) WHERE source = 'auto';
CREATE INDEX IF NOT EXISTS idx_bot_comment_jobs_due
  ON public.bot_comment_jobs (due_at) WHERE status = 'pending';
CREATE INDEX IF NOT EXISTS idx_bot_comment_jobs_post
  ON public.bot_comment_jobs (post_id);

ALTER TABLE public.bot_comment_jobs ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.bot_comment_jobs FROM PUBLIC, anon, authenticated;
GRANT ALL ON TABLE public.bot_comment_jobs TO service_role;

-- Otomatik zamanlayıcının bir gönderiyi yalnız BİR KEZ değerlendirmesi için
-- (her turda zar atılsaydı olasılık zamanla %100'e yaklaşırdı).
CREATE TABLE IF NOT EXISTS public.bot_comment_seen_posts (
  post_id uuid PRIMARY KEY REFERENCES public.posts(id) ON DELETE CASCADE,
  decided_at timestamptz NOT NULL DEFAULT now(),
  scheduled integer NOT NULL DEFAULT 0
);
ALTER TABLE public.bot_comment_seen_posts ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.bot_comment_seen_posts FROM PUBLIC, anon, authenticated;
GRANT ALL ON TABLE public.bot_comment_seen_posts TO service_role;

-- -----------------------------------------------------------------------------
-- 3) Ayarlar (admin panelinden app_settings upsert ile değişir)
-- -----------------------------------------------------------------------------
INSERT INTO public.app_settings (key, value, description)
VALUES
  ('bot_auto_comment_enabled', '"false"',
   'Botlar son gönderilere otomatik yorum yapsın mı (Görev 4.7). Varsayılan kapalı.'),
  ('bot_comment_probability', '"25"',
   'Uygun bir gönderinin otomatik bot yorumu alma olasılığı (%, 0-100).'),
  ('bot_comment_min_count', '"1"', 'Yorum alacak gönderiye en az kaç bot yorum yapsın.'),
  ('bot_comment_max_count', '"1"', 'Yorum alacak gönderiye en çok kaç bot yorum yapsın.'),
  ('bot_comment_min_hours', '"0"', 'Yorumun gönderiden en erken kaç saat sonra düşeceği.'),
  ('bot_comment_max_hours', '"6"', 'Yorumun gönderiden en geç kaç saat sonra düşeceği.'),
  ('bot_comment_lookback_days', '"2"', 'Kaç gün önceye kadarki gönderiler değerlendirilsin.')
ON CONFLICT (key) DO NOTHING;

-- -----------------------------------------------------------------------------
-- 4) Yardımcılar
-- -----------------------------------------------------------------------------
-- Etkin bir bot mu (bot hesabı, aktif profil, bot_accounts'ta aktif)?
CREATE OR REPLACE FUNCTION private.bot_is_active(p_bot_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SET search_path = ''
AS $fn$
  SELECT EXISTS (
    SELECT 1 FROM public.profiles p
      JOIN public.bot_accounts ba ON ba.id = p.id
     WHERE p.id = p_bot_id AND COALESCE(p.is_bot, false)
       AND p.status::text = 'active' AND ba.is_active
  );
$fn$;

-- Kuyruktaki tek işi yürütür: gönderi/bot hâlâ uygunsa yorumu yazar.
CREATE OR REPLACE FUNCTION private.bot_comment_execute(p_job_id uuid)
RETURNS text
LANGUAGE plpgsql
SET search_path = ''
AS $fn$
DECLARE
  v_job public.bot_comment_jobs%ROWTYPE;
  v_comment uuid;
BEGIN
  SELECT * INTO v_job FROM public.bot_comment_jobs WHERE id = p_job_id FOR UPDATE;
  IF NOT FOUND OR v_job.status <> 'pending' THEN
    RETURN 'missing';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.posts po WHERE po.id = v_job.post_id AND po.is_active IS NOT FALSE) THEN
    UPDATE public.bot_comment_jobs SET status = 'skipped', error_message = 'Gönderi gizli ya da silinmiş',
           processed_at = now() WHERE id = p_job_id;
    RETURN 'skipped';
  END IF;
  IF NOT private.bot_is_active(v_job.bot_id) THEN
    UPDATE public.bot_comment_jobs SET status = 'skipped', error_message = 'Bot pasif',
           processed_at = now() WHERE id = p_job_id;
    RETURN 'skipped';
  END IF;

  BEGIN
    INSERT INTO public.post_comments (post_id, user_id, content)
    VALUES (v_job.post_id, v_job.bot_id, btrim(v_job.body))
    RETURNING id INTO v_comment;
  EXCEPTION WHEN OTHERS THEN
    UPDATE public.bot_comment_jobs SET status = 'failed', error_message = left(SQLERRM, 300),
           processed_at = now() WHERE id = p_job_id;
    RETURN 'failed';
  END;

  UPDATE public.bot_comment_jobs
     SET status = 'done', comment_id = v_comment, processed_at = now(), error_message = NULL
   WHERE id = p_job_id;
  IF v_job.library_id IS NOT NULL THEN
    UPDATE public.bot_comment_library SET use_count = use_count + 1 WHERE id = v_job.library_id;
  END IF;
  RETURN 'done';
END;
$fn$;

-- -----------------------------------------------------------------------------
-- 5) Otomatik zamanlayıcı ve işleyici (pg_cron)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.schedule_bot_comments(p_max_posts integer DEFAULT 100)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $fn$
DECLARE
  v_post record;
  v_probability integer;
  v_min_hours integer;
  v_max_hours integer;
  v_min_count integer;
  v_max_count integer;
  v_lookback integer;
  v_count integer;
  v_inserted integer;
  v_total integer := 0;
BEGIN
  IF NOT private.bot_setting_bool('bot_auto_comment_enabled', false) THEN
    RETURN 0;
  END IF;
  v_probability := LEAST(GREATEST(private.bot_setting_int('bot_comment_probability', 25), 0), 100);
  v_min_hours := GREATEST(private.bot_setting_int('bot_comment_min_hours', 0), 0);
  v_max_hours := GREATEST(private.bot_setting_int('bot_comment_max_hours', 6), v_min_hours);
  v_min_count := GREATEST(private.bot_setting_int('bot_comment_min_count', 1), 0);
  v_max_count := LEAST(GREATEST(private.bot_setting_int('bot_comment_max_count', 1), v_min_count), 10);
  v_lookback := GREATEST(private.bot_setting_int('bot_comment_lookback_days', 2), 1);

  FOR v_post IN
    SELECT po.id, po.user_id, po.created_at
      FROM public.posts po
      JOIN public.profiles author ON author.id = po.user_id
     WHERE po.is_active = true
       AND po.created_at >= now() - make_interval(days => v_lookback)
       AND author.status::text = 'active'
       AND COALESCE(author.profile_is_public, true)
       AND NOT EXISTS (SELECT 1 FROM public.bot_comment_seen_posts s WHERE s.post_id = po.id)
     ORDER BY po.created_at DESC
     LIMIT GREATEST(COALESCE(p_max_posts, 100), 1)
  LOOP
    v_inserted := 0;
    IF random() * 100 < v_probability THEN
      v_count := v_min_count + floor(random() * (v_max_count - v_min_count + 1))::integer;
      IF v_count > 0 THEN
        INSERT INTO public.bot_comment_jobs (bot_id, post_id, body, library_id, source, due_at)
        SELECT b.bot_id, v_post.id, t.body, t.id, 'auto',
               CASE WHEN d.due < now()
                    THEN now() + make_interval(secs => (random() * GREATEST(v_max_hours, 1) * 3600)::integer)
                    ELSE d.due END
          FROM (
            SELECT p.id AS bot_id, row_number() OVER (ORDER BY random()) AS rn
              FROM public.profiles p
              JOIN public.bot_accounts ba ON ba.id = p.id
             WHERE COALESCE(p.is_bot, false) AND p.status::text = 'active' AND ba.is_active
               AND p.id <> v_post.user_id
               AND NOT EXISTS (SELECT 1 FROM public.post_comments c
                                WHERE c.post_id = v_post.id AND c.user_id = p.id)
             ORDER BY random()
             LIMIT v_count
          ) b
          JOIN (
            SELECT l.id, l.body, row_number() OVER (ORDER BY l.use_count + random() * 3) AS rn
              FROM public.bot_comment_library l
             WHERE l.is_active
             ORDER BY l.use_count + random() * 3
             LIMIT v_count
          ) t ON t.rn = b.rn
          CROSS JOIN LATERAL (
            SELECT v_post.created_at + make_interval(
                     secs => ((v_min_hours * 3600)
                              + (random() * GREATEST(v_max_hours - v_min_hours, 0) * 3600))::integer) AS due
          ) d
        ON CONFLICT DO NOTHING;
        GET DIAGNOSTICS v_inserted = ROW_COUNT;
      END IF;
    END IF;
    INSERT INTO public.bot_comment_seen_posts (post_id, scheduled)
    VALUES (v_post.id, v_inserted)
    ON CONFLICT (post_id) DO NOTHING;
    v_total := v_total + v_inserted;
  END LOOP;

  RETURN v_total;
END;
$fn$;

CREATE OR REPLACE FUNCTION public.process_bot_comment_jobs(p_limit integer DEFAULT 200)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $fn$
DECLARE
  v_id uuid;
  v_done integer := 0;
BEGIN
  FOR v_id IN
    SELECT j.id FROM public.bot_comment_jobs j
     WHERE j.status = 'pending' AND j.due_at <= now()
     ORDER BY j.due_at
     LIMIT GREATEST(COALESCE(p_limit, 200), 1)
     FOR UPDATE SKIP LOCKED
  LOOP
    IF private.bot_comment_execute(v_id) = 'done' THEN
      v_done := v_done + 1;
    END IF;
  END LOOP;
  RETURN v_done;
END;
$fn$;

-- -----------------------------------------------------------------------------
-- 6) Yönetici RPC'leri
-- -----------------------------------------------------------------------------
-- Manuel yorum: şimdi yazar (p_due_at NULL/geçmiş) ya da zamanlar.
CREATE OR REPLACE FUNCTION public.admin_bot_comment(
  p_bot_id uuid,
  p_post_id uuid,
  p_body text,
  p_due_at timestamptz DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $fn$
DECLARE
  v_body text := btrim(COALESCE(p_body, ''));
  v_job uuid;
  v_result text;
  v_comment uuid;
BEGIN
  IF NOT private.current_user_is_admin() THEN
    RAISE EXCEPTION 'Yönetici yetkisi gerekli' USING ERRCODE = '42501';
  END IF;
  IF char_length(v_body) < 1 OR char_length(v_body) > 1000 THEN
    RAISE EXCEPTION 'Yorum 1-1000 karakter olmalı' USING ERRCODE = 'P0001', HINT = 'BOT_COMMENT_INVALID';
  END IF;
  IF NOT private.bot_is_active(p_bot_id) THEN
    RAISE EXCEPTION 'Bot bulunamadı ya da pasif' USING ERRCODE = 'P0001', HINT = 'BOT_INACTIVE';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.posts po WHERE po.id = p_post_id AND po.is_active IS NOT FALSE) THEN
    RAISE EXCEPTION 'Gönderi bulunamadı ya da gizli' USING ERRCODE = 'P0001', HINT = 'BOT_POST_UNAVAILABLE';
  END IF;
  IF p_due_at IS NOT NULL AND p_due_at > now() + interval '30 days' THEN
    RAISE EXCEPTION 'En çok 30 gün sonrasına zamanlanabilir' USING ERRCODE = 'P0001', HINT = 'BOT_COMMENT_TOO_LATE';
  END IF;

  INSERT INTO public.bot_comment_jobs (bot_id, post_id, body, source, due_at, created_by)
  VALUES (p_bot_id, p_post_id, v_body, 'manual', GREATEST(COALESCE(p_due_at, now()), now()), auth.uid())
  RETURNING id INTO v_job;

  IF p_due_at IS NULL OR p_due_at <= now() + interval '1 minute' THEN
    v_result := private.bot_comment_execute(v_job);
    IF v_result <> 'done' THEN
      RAISE EXCEPTION 'Yorum yazılamadı' USING ERRCODE = 'P0001', HINT = 'BOT_COMMENT_FAILED';
    END IF;
    SELECT comment_id INTO v_comment FROM public.bot_comment_jobs WHERE id = v_job;
  END IF;

  INSERT INTO public.admin_audit_log (admin_id, action, target_table, target_id, new_data)
  VALUES (auth.uid(), 'bot_comment', 'posts', p_post_id::text,
          jsonb_build_object('bot_id', p_bot_id, 'job_id', v_job, 'scheduled', v_comment IS NULL));

  RETURN jsonb_build_object('job_id', v_job, 'comment_id', v_comment,
                            'status', CASE WHEN v_comment IS NULL THEN 'pending' ELSE 'done' END);
END;
$fn$;

-- p_status: 'pending' | 'done' | 'failed' (hatalı + atlanan) | 'all'
CREATE OR REPLACE FUNCTION public.admin_bot_comment_jobs(
  p_status text DEFAULT 'pending',
  p_limit integer DEFAULT 30,
  p_offset integer DEFAULT 0
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $fn$
DECLARE
  v_status text := CASE WHEN p_status IN ('pending', 'done', 'failed', 'all') THEN p_status ELSE 'pending' END;
  v_limit integer := LEAST(GREATEST(COALESCE(p_limit, 30), 1), 100);
  v_offset integer := GREATEST(COALESCE(p_offset, 0), 0);
  v_total integer;
  v_rows jsonb;
BEGIN
  IF NOT private.current_user_is_admin() THEN
    RAISE EXCEPTION 'Yönetici yetkisi gerekli' USING ERRCODE = '42501';
  END IF;

  WITH f AS (
    SELECT j.*
      FROM public.bot_comment_jobs j
     WHERE CASE v_status
             WHEN 'pending' THEN j.status = 'pending'
             WHEN 'done' THEN j.status = 'done'
             WHEN 'failed' THEN j.status IN ('failed', 'skipped')
             ELSE true
           END
  ),
  page AS (
    SELECT f.id,
           row_number() OVER (
             ORDER BY CASE WHEN f.status = 'pending' THEN f.due_at END ASC NULLS LAST,
                      COALESCE(f.processed_at, f.created_at) DESC, f.id) AS rn
      FROM f
     ORDER BY rn
     LIMIT v_limit OFFSET v_offset
  )
  SELECT (SELECT count(*) FROM f),
         COALESCE(jsonb_agg(jsonb_build_object(
           'id', j.id,
           'body', j.body,
           'source', j.source,
           'status', j.status,
           'due_at', j.due_at,
           'processed_at', j.processed_at,
           'error_message', j.error_message,
           'comment_id', j.comment_id,
           'created_at', j.created_at,
           'bot', jsonb_build_object(
             'id', b.id, 'name', COALESCE(NULLIF(btrim(b.full_name), ''), b.username),
             'username', b.username, 'avatar_url', b.avatar_url),
           'post', CASE WHEN po.id IS NULL THEN NULL ELSE jsonb_build_object(
             'id', po.id,
             'preview', COALESCE(NULLIF(left(regexp_replace(btrim(COALESCE(po.content, '')), '\s+', ' ', 'g'), 120), ''),
                                 'Fotoğraflı gönderi'),
             'author_name', COALESCE(NULLIF(btrim(a.full_name), ''), a.username)) END
         ) ORDER BY pg.rn), '[]'::jsonb)
    INTO v_total, v_rows
    FROM page pg
    JOIN public.bot_comment_jobs j ON j.id = pg.id
    LEFT JOIN public.profiles b ON b.id = j.bot_id
    LEFT JOIN public.posts po ON po.id = j.post_id
    LEFT JOIN public.profiles a ON a.id = po.user_id;

  RETURN jsonb_build_object(
    'total', COALESCE(v_total, 0),
    'rows', v_rows,
    'summary', jsonb_build_object(
      'pending', (SELECT count(*) FROM public.bot_comment_jobs WHERE status = 'pending'),
      'done_24h', (SELECT count(*) FROM public.bot_comment_jobs
                    WHERE status = 'done' AND processed_at > now() - interval '24 hours'),
      'failed_24h', (SELECT count(*) FROM public.bot_comment_jobs
                      WHERE status IN ('failed', 'skipped') AND processed_at > now() - interval '24 hours'),
      'library_active', (SELECT count(*) FROM public.bot_comment_library WHERE is_active)
    )
  );
END;
$fn$;

-- Bekleyen işi iptal et ya da yazılmış bot yorumunu sil.
CREATE OR REPLACE FUNCTION public.admin_bot_comment_cancel(p_job_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $fn$
DECLARE
  v public.bot_comment_jobs%ROWTYPE;
BEGIN
  IF NOT private.current_user_is_admin() THEN
    RAISE EXCEPTION 'Yönetici yetkisi gerekli' USING ERRCODE = '42501';
  END IF;
  SELECT * INTO v FROM public.bot_comment_jobs WHERE id = p_job_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Kayıt bulunamadı' USING ERRCODE = 'P0001', HINT = 'BOT_JOB_NOT_FOUND';
  END IF;
  IF v.status = 'pending' THEN
    UPDATE public.bot_comment_jobs SET status = 'cancelled', processed_at = now() WHERE id = p_job_id;
    RETURN jsonb_build_object('status', 'cancelled');
  END IF;
  IF v.status = 'done' THEN
    -- Yazılmış yorumu sil (yalnız bu botun yorumu).
    DELETE FROM public.post_comments WHERE id = v.comment_id AND user_id = v.bot_id;
    UPDATE public.bot_comment_jobs
       SET status = 'cancelled', error_message = 'Yorum yönetici tarafından silindi'
     WHERE id = p_job_id;
    INSERT INTO public.admin_audit_log (admin_id, action, target_table, target_id, old_data)
    VALUES (auth.uid(), 'bot_comment_delete', 'post_comments', COALESCE(v.comment_id::text, ''),
            jsonb_build_object('job_id', v.id, 'bot_id', v.bot_id, 'body', v.body));
    RETURN jsonb_build_object('status', 'deleted');
  END IF;
  RAISE EXCEPTION 'Bu kayıt artık değiştirilemez' USING ERRCODE = 'P0001', HINT = 'BOT_JOB_CLOSED';
END;
$fn$;

-- Yorum kitaplığı
CREATE OR REPLACE FUNCTION public.admin_bot_comment_library()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $fn$
BEGIN
  IF NOT private.current_user_is_admin() THEN
    RAISE EXCEPTION 'Yönetici yetkisi gerekli' USING ERRCODE = '42501';
  END IF;
  RETURN (
    SELECT COALESCE(jsonb_agg(jsonb_build_object(
             'id', l.id, 'body', l.body, 'tone', l.tone, 'is_active', l.is_active,
             'use_count', l.use_count, 'created_at', l.created_at
           ) ORDER BY l.is_active DESC, l.tone, lower(l.body)), '[]'::jsonb)
      FROM public.bot_comment_library l
  );
END;
$fn$;

CREATE OR REPLACE FUNCTION public.admin_bot_comment_library_upsert(
  p_id uuid,
  p_body text,
  p_tone text DEFAULT 'genel',
  p_is_active boolean DEFAULT true
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $fn$
DECLARE
  v_body text := btrim(COALESCE(p_body, ''));
  v_id uuid;
BEGIN
  IF NOT private.current_user_is_admin() THEN
    RAISE EXCEPTION 'Yönetici yetkisi gerekli' USING ERRCODE = '42501';
  END IF;
  IF char_length(v_body) < 1 OR char_length(v_body) > 300 THEN
    RAISE EXCEPTION 'Yorum 1-300 karakter olmalı' USING ERRCODE = 'P0001', HINT = 'BOT_COMMENT_INVALID';
  END IF;
  IF p_tone IS NULL OR p_tone NOT IN ('genel', 'tebrik', 'soru', 'mizah', 'yerel', 'destek') THEN
    RAISE EXCEPTION 'Geçersiz ton' USING ERRCODE = 'P0001', HINT = 'BOT_COMMENT_TONE_INVALID';
  END IF;
  BEGIN
    IF p_id IS NULL THEN
      INSERT INTO public.bot_comment_library (body, tone, is_active)
      VALUES (v_body, p_tone, COALESCE(p_is_active, true))
      RETURNING id INTO v_id;
    ELSE
      UPDATE public.bot_comment_library
         SET body = v_body, tone = p_tone, is_active = COALESCE(p_is_active, true), updated_at = now()
       WHERE id = p_id
      RETURNING id INTO v_id;
      IF v_id IS NULL THEN
        RAISE EXCEPTION 'Kayıt bulunamadı' USING ERRCODE = 'P0001', HINT = 'BOT_JOB_NOT_FOUND';
      END IF;
    END IF;
  EXCEPTION WHEN unique_violation THEN
    RAISE EXCEPTION 'Bu yorum kitaplıkta zaten var' USING ERRCODE = 'P0001', HINT = 'BOT_COMMENT_DUPLICATE';
  END;
  RETURN v_id;
END;
$fn$;

CREATE OR REPLACE FUNCTION public.admin_bot_comment_library_delete(p_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $fn$
BEGIN
  IF NOT private.current_user_is_admin() THEN
    RAISE EXCEPTION 'Yönetici yetkisi gerekli' USING ERRCODE = '42501';
  END IF;
  DELETE FROM public.bot_comment_library WHERE id = p_id;
END;
$fn$;

-- Manuel yorum için gönderi seçici: son yayındaki gönderiler (arama: metin/yazar).
CREATE OR REPLACE FUNCTION public.admin_bot_recent_posts(p_search text DEFAULT NULL, p_limit integer DEFAULT 30)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $fn$
DECLARE
  v_search text := NULLIF(btrim(COALESCE(p_search, '')), '');
  v_pattern text;
BEGIN
  IF NOT private.current_user_is_admin() THEN
    RAISE EXCEPTION 'Yönetici yetkisi gerekli' USING ERRCODE = '42501';
  END IF;
  IF v_search IS NOT NULL THEN
    v_pattern := '%' || replace(replace(replace(v_search, '\', '\\'), '%', '\%'), '_', '\_') || '%';
  END IF;
  RETURN (
    SELECT COALESCE(jsonb_agg(x.j ORDER BY x.created_at DESC, x.id), '[]'::jsonb)
      FROM (
        SELECT po.id, po.created_at, jsonb_build_object(
                 'id', po.id,
                 'preview', COALESCE(NULLIF(left(regexp_replace(btrim(COALESCE(po.content, '')), '\s+', ' ', 'g'), 120), ''),
                                     'Fotoğraflı gönderi'),
                 'created_at', po.created_at,
                 'comments_count', COALESCE(po.comments_count, 0),
                 'author_name', COALESCE(NULLIF(btrim(a.full_name), ''), a.username),
                 'author_is_bot', COALESCE(a.is_bot, false)) AS j
          FROM public.posts po
          JOIN public.profiles a ON a.id = po.user_id
         WHERE po.is_active IS NOT FALSE
           AND (v_pattern IS NULL OR po.content ILIKE v_pattern OR a.username ILIKE v_pattern OR a.full_name ILIKE v_pattern)
         ORDER BY po.created_at DESC, po.id
         LIMIT LEAST(GREATEST(COALESCE(p_limit, 30), 1), 100)
      ) x
  );
END;
$fn$;

-- Kuyruğu hemen çalıştır (zamanla + vadesi gelenleri yaz).
CREATE OR REPLACE FUNCTION public.admin_bot_run_comment_queue()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $fn$
BEGIN
  IF NOT private.current_user_is_admin() THEN
    RAISE EXCEPTION 'Yönetici yetkisi gerekli' USING ERRCODE = '42501';
  END IF;
  RETURN jsonb_build_object(
    'scheduled', public.schedule_bot_comments(100),
    'processed', public.process_bot_comment_jobs(200)
  );
END;
$fn$;

-- -----------------------------------------------------------------------------
-- 7) Bot sahibine yorum bildirimi yazılmaz (takip/beğeni ile aynı kural)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.notify_post_comment()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
    post_owner_id UUID;
    commenter_info JSONB;
BEGIN
    SELECT user_id INTO post_owner_id
    FROM public.posts WHERE id = NEW.post_id;

    IF post_owner_id IS NULL OR post_owner_id = NEW.user_id THEN
        RETURN NEW;
    END IF;

    -- Görev 4.7: alıcı bot ise bildirim yok (bot-bot yorumları tabloyu şişirmesin).
    IF EXISTS (SELECT 1 FROM public.profiles WHERE id = post_owner_id AND COALESCE(is_bot, false)) THEN
        RETURN NEW;
    END IF;

    SELECT jsonb_build_object(
        'id', p.id, 'username', p.username,
        'full_name', COALESCE(p.full_name, p.username),
        'avatar_url', p.avatar_url
    ) INTO commenter_info
    FROM public.profiles p WHERE p.id = NEW.user_id;

    INSERT INTO public.notifications (
        user_id, type, title, content, actor_id, actor_name, actor_avatar,
        entity_id, is_read, created_at
    ) VALUES (
        post_owner_id, 'post_comment',
        (commenter_info->>'full_name') || ' gönderine yorum yaptı',
        SUBSTRING(NEW.content FROM 1 FOR 100), NEW.user_id,
        commenter_info->>'full_name', commenter_info->>'avatar_url',
        NEW.post_id, false, NOW()
    );

    RETURN NEW;
END;
$function$;

-- -----------------------------------------------------------------------------
-- 8) Yetkiler ve zamanlanmış iş
-- -----------------------------------------------------------------------------
REVOKE ALL ON FUNCTION private.bot_is_active(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION private.bot_comment_execute(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.schedule_bot_comments(integer) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.process_bot_comment_jobs(integer) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.schedule_bot_comments(integer) TO service_role;
GRANT EXECUTE ON FUNCTION public.process_bot_comment_jobs(integer) TO service_role;

REVOKE ALL ON FUNCTION public.admin_bot_comment(uuid, uuid, text, timestamptz) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.admin_bot_comment_jobs(text, integer, integer) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.admin_bot_comment_cancel(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.admin_bot_comment_library() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.admin_bot_comment_library_upsert(uuid, text, text, boolean) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.admin_bot_comment_library_delete(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.admin_bot_recent_posts(text, integer) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.admin_bot_run_comment_queue() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_bot_comment(uuid, uuid, text, timestamptz) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_bot_comment_jobs(text, integer, integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_bot_comment_cancel(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_bot_comment_library() TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_bot_comment_library_upsert(uuid, text, text, boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_bot_comment_library_delete(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_bot_recent_posts(text, integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_bot_run_comment_queue() TO authenticated;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    PERFORM cron.schedule(
      'bot_comment_tick',
      '*/10 * * * *',
      'select public.schedule_bot_comments(100); select public.process_bot_comment_jobs(200);'
    );
  END IF;
END $$;

COMMIT;

NOTIFY pgrst, 'reload schema';
