-- =============================================================================
-- 20260908140001_bot_content_library_and_likes.sql
-- -----------------------------------------------------------------------------
-- İKİ EKSİĞİ KAPATIR:
--
-- 1) İÇERİK KITAPLIĞI. İlk tohumlamada her bot 2-3 gönderi paylaşmıştı ve
--    aralıklar düzenliydi — bu, hesapların otomatik olduğunu ele veriyordu.
--    Gerçek hesaplarda gönderi sayısı çok değişkendir (biri 14, biri 1) ve
--    zamanlama kümelenir (bir gün üç gönderi, sonra üç hafta sessizlik).
--    `bot_content_library` + `bot_image_library` hazır içeriği tutar;
--    `admin_bot_publish_from_library()` bu içeriği DÜZENSİZ dağıtır.
--
-- 2) BOT BEĞENİLERİ. Botlar artık gönderi beğenebilir. Asıl değer gerçek
--    üyelerde: `notify_post_like_trigger` sayesinde üye "gönderini beğendi"
--    bildirimi alır. Beğeniler anında değil, `bot_like_jobs` kuyruğu üzerinden
--    saatlere yayılarak işlenir — hepsi aynı dakikada gelseydi yine bot
--    olduğu anlaşılırdı.
--
-- NOT: `post_likes` üzerinde (post_id, user_id) tekil kısıtı ve
-- increment/decrement trigger'ları var; `likes_count` kendiliğinden doğru
-- kalır, elle güncellenmemelidir.
-- =============================================================================

begin;

-- -----------------------------------------------------------------------------
-- 1) Metin kitaplığı
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.bot_content_library (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  body text NOT NULL,
  tone text NOT NULL DEFAULT 'gunluk',
  is_active boolean NOT NULL DEFAULT true,
  used_count integer NOT NULL DEFAULT 0,
  last_used_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT bot_content_library_body_not_blank CHECK (btrim(body) <> '')
);

-- Aynı metnin iki kez eklenmesini engeller (tohumlama tekrar çalıştırılabilir).
CREATE UNIQUE INDEX IF NOT EXISTS idx_bot_content_library_body
  ON public.bot_content_library (md5(btrim(body)));

ALTER TABLE public.bot_content_library ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.bot_content_library FROM PUBLIC, anon, authenticated;
GRANT ALL ON TABLE public.bot_content_library TO service_role;

DROP POLICY IF EXISTS bot_content_library_admin_all ON public.bot_content_library;
CREATE POLICY bot_content_library_admin_all ON public.bot_content_library
  FOR ALL USING (private.current_user_is_admin())
  WITH CHECK (private.current_user_is_admin());

-- -----------------------------------------------------------------------------
-- 2) Görsel kitaplığı
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.bot_image_library (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  url text NOT NULL,
  caption text,
  tone text NOT NULL DEFAULT 'gunluk',
  is_active boolean NOT NULL DEFAULT true,
  used_count integer NOT NULL DEFAULT 0,
  last_used_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT bot_image_library_url_not_blank CHECK (btrim(url) <> '')
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_bot_image_library_url
  ON public.bot_image_library (url);

ALTER TABLE public.bot_image_library ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.bot_image_library FROM PUBLIC, anon, authenticated;
GRANT ALL ON TABLE public.bot_image_library TO service_role;

DROP POLICY IF EXISTS bot_image_library_admin_all ON public.bot_image_library;
CREATE POLICY bot_image_library_admin_all ON public.bot_image_library
  FOR ALL USING (private.current_user_is_admin())
  WITH CHECK (private.current_user_is_admin());

-- -----------------------------------------------------------------------------
-- 3) Beğeni kuyruğu
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.bot_like_jobs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  bot_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  post_id uuid NOT NULL REFERENCES public.posts(id) ON DELETE CASCADE,
  due_at timestamptz NOT NULL,
  status text NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending', 'done', 'skipped', 'failed', 'cancelled')),
  processed_at timestamptz,
  error_message text,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT bot_like_jobs_unique UNIQUE (bot_id, post_id)
);

CREATE INDEX IF NOT EXISTS idx_bot_like_jobs_due
  ON public.bot_like_jobs (due_at) WHERE status = 'pending';
CREATE INDEX IF NOT EXISTS idx_bot_like_jobs_post
  ON public.bot_like_jobs (post_id);

ALTER TABLE public.bot_like_jobs ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.bot_like_jobs FROM PUBLIC, anon, authenticated;
GRANT ALL ON TABLE public.bot_like_jobs TO service_role;

DROP POLICY IF EXISTS bot_like_jobs_admin_all ON public.bot_like_jobs;
CREATE POLICY bot_like_jobs_admin_all ON public.bot_like_jobs
  FOR ALL USING (private.current_user_is_admin())
  WITH CHECK (private.current_user_is_admin());

-- -----------------------------------------------------------------------------
-- 4) Beğeni ayarları
-- -----------------------------------------------------------------------------
INSERT INTO public.app_settings (key, value, description)
VALUES
  ('bot_auto_like_enabled', 'true'::jsonb,
   'Botlar yeni gönderileri otomatik beğensin mi?'),
  ('bot_like_min_hours', '1'::jsonb,
   'Bir gönderi paylaşıldıktan en erken kaç saat sonra beğeni gelebilir.'),
  ('bot_like_max_hours', '48'::jsonb,
   'Bir gönderi paylaşıldıktan en geç kaç saat sonra beğeni gelebilir.'),
  ('bot_like_min_count', '1'::jsonb,
   'Bir gönderiye en az kaç bot beğenisi planlansın.'),
  ('bot_like_max_count', '7'::jsonb,
   'Bir gönderiye en fazla kaç bot beğenisi planlansın.'),
  ('bot_like_lookback_days', '10'::jsonb,
   'Kaç günlük geçmişteki gönderiler beğeni için değerlendirilsin.')
ON CONFLICT (key) DO NOTHING;

-- -----------------------------------------------------------------------------
-- 5) Beğeni planlayıcı
-- -----------------------------------------------------------------------------
-- Son N gündeki, henüz beğeni işi açılmamış aktif gönderiler için rastgele
-- sayıda bot beğenisi planlar. Kendi gönderisini beğenmez, gizli/silinmiş
-- hesapların gönderilerine dokunmaz, zaten beğenilmiş olanı tekrar planlamaz.
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
      -- Gönderinin YAYIN anına göre gecikme: geçmişe dönük bir gönderi için
      -- de "paylaşımdan birkaç saat sonra beğenilmiş" görüntüsü oluşur.
      GREATEST(
        v_post.created_at + make_interval(
          secs => (v_min_hours * 3600)
                  + (random() * GREATEST(v_max_hours - v_min_hours, 0) * 3600)
        ),
        now() - interval '5 minutes'
      )
    FROM public.profiles b
    JOIN public.bot_accounts ba ON ba.id = b.id
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

-- -----------------------------------------------------------------------------
-- 6) Beğeni işleyici
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.process_bot_like_jobs(p_limit integer DEFAULT 200)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_job record;
  v_done integer := 0;
BEGIN
  FOR v_job IN
    SELECT j.id, j.bot_id, j.post_id
    FROM public.bot_like_jobs j
    JOIN public.profiles b ON b.id = j.bot_id
    JOIN public.bot_accounts ba ON ba.id = j.bot_id
    WHERE j.status = 'pending'
      AND j.due_at <= now()
      AND b.is_bot = true
      AND b.status = 'active'::public.user_status
      AND ba.is_active = true
    ORDER BY j.due_at
    LIMIT GREATEST(COALESCE(p_limit, 200), 1)
    FOR UPDATE OF j SKIP LOCKED
  LOOP
    BEGIN
      IF NOT EXISTS (
        SELECT 1 FROM public.posts po
        WHERE po.id = v_job.post_id AND po.is_active = true
      ) THEN
        UPDATE public.bot_like_jobs
        SET status = 'skipped', processed_at = now(),
            error_message = 'post missing or inactive'
        WHERE id = v_job.id;
        CONTINUE;
      END IF;

      -- likes_count'u ELLE artırma: post_likes_insert_trigger zaten yapıyor.
      INSERT INTO public.post_likes (post_id, user_id)
      VALUES (v_job.post_id, v_job.bot_id)
      ON CONFLICT DO NOTHING;

      UPDATE public.bot_like_jobs
      SET status = 'done', processed_at = now()
      WHERE id = v_job.id;

      v_done := v_done + 1;
    EXCEPTION WHEN OTHERS THEN
      UPDATE public.bot_like_jobs
      SET status = 'failed', processed_at = now(), error_message = SQLERRM
      WHERE id = v_job.id;
    END;
  END LOOP;

  RETURN v_done;
END;
$$;

REVOKE ALL ON FUNCTION public.process_bot_like_jobs(integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.process_bot_like_jobs(integer) TO service_role;

-- -----------------------------------------------------------------------------
-- 7) Kitaplıktan gönderi üret — DÜZENSİZ dağıtım
-- -----------------------------------------------------------------------------
-- Gerçekçiliğin püf noktası burada:
--   * Bot başına gönderi sayısı üstel benzeri bir dağılımdan gelir; birkaç bot
--     çok üretken, çoğu az paylaşan olur (sabit "herkes 3 tane" görüntüsü yok).
--   * Zaman damgaları rastgele güne + rastgele saate düşer, gündüz saatleri
--     ağırlıklıdır; aynı güne birden fazla gönderi düşebilir (kümelenme).
--   * Görsel yalnız gönderilerin bir kısmına eklenir.
CREATE OR REPLACE FUNCTION public.admin_bot_publish_from_library(
  p_total integer DEFAULT 120,
  p_spread_days integer DEFAULT 240,
  p_image_percent integer DEFAULT 30
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_bots uuid[];
  v_weights numeric[];
  v_bot_count integer;
  v_text record;
  v_bot_id uuid;
  v_image_url text;
  v_created integer := 0;
  v_pick numeric;
  v_acc numeric;
  v_i integer;
  v_days integer := GREATEST(COALESCE(p_spread_days, 240), 1);
  v_created_at timestamptz;
BEGIN
  IF NOT private.current_user_is_admin() THEN
    RAISE EXCEPTION 'admin_bot_publish_from_library: not admin' USING ERRCODE = '42501';
  END IF;

  SELECT array_agg(b.id ORDER BY b.id)
  INTO v_bots
  FROM public.profiles b
  JOIN public.bot_accounts ba ON ba.id = b.id
  WHERE b.is_bot = true
    AND b.status = 'active'::public.user_status
    AND ba.is_active = true;

  v_bot_count := COALESCE(array_length(v_bots, 1), 0);
  IF v_bot_count = 0 THEN
    RAISE EXCEPTION 'admin_bot_publish_from_library: aktif bot yok';
  END IF;

  -- Her bota sabit ama birbirinden ÇOK farklı bir "paylaşma iştahı" ağırlığı
  -- ver. random()^3 dağılımı birkaç yüksek, çok sayıda düşük değer üretir.
  v_weights := ARRAY[]::numeric[];
  FOR v_i IN 1..v_bot_count LOOP
    v_weights := v_weights || (0.15 + power(random(), 3) * 3.0)::numeric;
  END LOOP;

  FOR v_text IN
    SELECT l.id, l.body, l.tone
    FROM public.bot_content_library l
    WHERE l.is_active = true
    ORDER BY l.used_count, random()
    LIMIT GREATEST(COALESCE(p_total, 120), 1)
  LOOP
    -- Ağırlıklı bot seçimi
    v_pick := random() * (SELECT sum(w) FROM unnest(v_weights) AS w);
    v_acc := 0;
    v_bot_id := v_bots[v_bot_count];
    FOR v_i IN 1..v_bot_count LOOP
      v_acc := v_acc + v_weights[v_i];
      IF v_pick <= v_acc THEN
        v_bot_id := v_bots[v_i];
        EXIT;
      END IF;
    END LOOP;

    -- Rastgele gün + gündüz ağırlıklı saat
    v_created_at := now()
      - make_interval(days => floor(random() * v_days)::integer)
      - make_interval(
          hours => (6 + floor(power(random(), 0.8) * 17))::integer,
          mins  => floor(random() * 60)::integer
        );
    IF v_created_at > now() THEN
      v_created_at := now() - interval '1 hour';
    END IF;

    -- Gönderilerin bir kısmına kitaplıktan görsel
    v_image_url := NULL;
    IF random() * 100 < GREATEST(COALESCE(p_image_percent, 30), 0) THEN
      SELECT i.url INTO v_image_url
      FROM public.bot_image_library i
      WHERE i.is_active = true
        AND (i.tone = v_text.tone OR random() < 0.5)
      ORDER BY i.used_count, random()
      LIMIT 1;

      IF v_image_url IS NOT NULL THEN
        UPDATE public.bot_image_library
        SET used_count = used_count + 1, last_used_at = now()
        WHERE url = v_image_url;
      END IF;
    END IF;

    INSERT INTO public.posts (user_id, content, images, image_url, is_active, created_at, updated_at)
    VALUES (
      v_bot_id,
      v_text.body,
      CASE WHEN v_image_url IS NULL THEN '{}'::text[] ELSE ARRAY[v_image_url] END,
      v_image_url,
      true,
      v_created_at,
      v_created_at
    );

    UPDATE public.bot_content_library
    SET used_count = used_count + 1, last_used_at = now()
    WHERE id = v_text.id;

    v_created := v_created + 1;
  END LOOP;

  RETURN v_created;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_bot_publish_from_library(integer, integer, integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_bot_publish_from_library(integer, integer, integer)
  TO authenticated, service_role;

-- -----------------------------------------------------------------------------
-- 8) Kitaplık yönetim RPC'leri
-- -----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.admin_bot_library_texts(text, integer);

CREATE FUNCTION public.admin_bot_library_texts(
  p_tone text DEFAULT NULL,
  p_limit integer DEFAULT 500
)
RETURNS TABLE (
  id uuid,
  body text,
  tone text,
  is_active boolean,
  used_count integer,
  created_at timestamptz
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF NOT private.current_user_is_admin() THEN
    RAISE EXCEPTION 'admin_bot_library_texts: not admin' USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
  SELECT l.id, l.body, l.tone, l.is_active, l.used_count, l.created_at
  FROM public.bot_content_library l
  WHERE p_tone IS NULL OR l.tone = p_tone
  ORDER BY l.tone, l.created_at
  LIMIT GREATEST(COALESCE(p_limit, 500), 1);
END;
$$;

REVOKE ALL ON FUNCTION public.admin_bot_library_texts(text, integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_bot_library_texts(text, integer)
  TO authenticated, service_role;

DROP FUNCTION IF EXISTS public.admin_bot_library_images(text, integer);

CREATE FUNCTION public.admin_bot_library_images(
  p_tone text DEFAULT NULL,
  p_limit integer DEFAULT 300
)
RETURNS TABLE (
  id uuid,
  url text,
  caption text,
  tone text,
  is_active boolean,
  used_count integer,
  created_at timestamptz
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF NOT private.current_user_is_admin() THEN
    RAISE EXCEPTION 'admin_bot_library_images: not admin' USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
  SELECT i.id, i.url, i.caption, i.tone, i.is_active, i.used_count, i.created_at
  FROM public.bot_image_library i
  WHERE p_tone IS NULL OR i.tone = p_tone
  ORDER BY i.created_at
  LIMIT GREATEST(COALESCE(p_limit, 300), 1);
END;
$$;

REVOKE ALL ON FUNCTION public.admin_bot_library_images(text, integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_bot_library_images(text, integer)
  TO authenticated, service_role;

DROP FUNCTION IF EXISTS public.admin_bot_library_text_upsert(uuid, text, text, boolean);

CREATE FUNCTION public.admin_bot_library_text_upsert(
  p_id uuid DEFAULT NULL,
  p_body text DEFAULT NULL,
  p_tone text DEFAULT 'gunluk',
  p_is_active boolean DEFAULT true
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_id uuid;
BEGIN
  IF NOT private.current_user_is_admin() THEN
    RAISE EXCEPTION 'admin_bot_library_text_upsert: not admin' USING ERRCODE = '42501';
  END IF;

  IF COALESCE(btrim(p_body), '') = '' THEN
    RAISE EXCEPTION 'admin_bot_library_text_upsert: metin boş olamaz';
  END IF;

  IF p_id IS NULL THEN
    INSERT INTO public.bot_content_library (body, tone, is_active)
    VALUES (btrim(p_body), COALESCE(NULLIF(btrim(p_tone), ''), 'gunluk'),
            COALESCE(p_is_active, true))
    RETURNING id INTO v_id;
  ELSE
    UPDATE public.bot_content_library
    SET body = btrim(p_body),
        tone = COALESCE(NULLIF(btrim(p_tone), ''), tone),
        is_active = COALESCE(p_is_active, is_active)
    WHERE id = p_id
    RETURNING id INTO v_id;

    IF v_id IS NULL THEN
      RAISE EXCEPTION 'admin_bot_library_text_upsert: kayıt bulunamadı';
    END IF;
  END IF;

  RETURN v_id;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_bot_library_text_upsert(uuid, text, text, boolean) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_bot_library_text_upsert(uuid, text, text, boolean)
  TO authenticated, service_role;

DROP FUNCTION IF EXISTS public.admin_bot_library_image_upsert(uuid, text, text, text, boolean);

CREATE FUNCTION public.admin_bot_library_image_upsert(
  p_id uuid DEFAULT NULL,
  p_url text DEFAULT NULL,
  p_caption text DEFAULT NULL,
  p_tone text DEFAULT 'gunluk',
  p_is_active boolean DEFAULT true
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_id uuid;
BEGIN
  IF NOT private.current_user_is_admin() THEN
    RAISE EXCEPTION 'admin_bot_library_image_upsert: not admin' USING ERRCODE = '42501';
  END IF;

  IF p_id IS NULL THEN
    IF COALESCE(btrim(p_url), '') = '' THEN
      RAISE EXCEPTION 'admin_bot_library_image_upsert: görsel adresi boş olamaz';
    END IF;
    INSERT INTO public.bot_image_library (url, caption, tone, is_active)
    VALUES (btrim(p_url), NULLIF(btrim(COALESCE(p_caption, '')), ''),
            COALESCE(NULLIF(btrim(p_tone), ''), 'gunluk'),
            COALESCE(p_is_active, true))
    ON CONFLICT (url) DO UPDATE SET
      caption = EXCLUDED.caption,
      tone = EXCLUDED.tone,
      is_active = EXCLUDED.is_active
    RETURNING id INTO v_id;
  ELSE
    UPDATE public.bot_image_library
    SET url = COALESCE(NULLIF(btrim(p_url), ''), url),
        caption = CASE WHEN p_caption IS NULL THEN caption
                       ELSE NULLIF(btrim(p_caption), '') END,
        tone = COALESCE(NULLIF(btrim(p_tone), ''), tone),
        is_active = COALESCE(p_is_active, is_active)
    WHERE id = p_id
    RETURNING id INTO v_id;

    IF v_id IS NULL THEN
      RAISE EXCEPTION 'admin_bot_library_image_upsert: kayıt bulunamadı';
    END IF;
  END IF;

  RETURN v_id;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_bot_library_image_upsert(uuid, text, text, text, boolean) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_bot_library_image_upsert(uuid, text, text, text, boolean)
  TO authenticated, service_role;

DROP FUNCTION IF EXISTS public.admin_bot_library_delete(text, uuid);

CREATE FUNCTION public.admin_bot_library_delete(p_kind text, p_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF NOT private.current_user_is_admin() THEN
    RAISE EXCEPTION 'admin_bot_library_delete: not admin' USING ERRCODE = '42501';
  END IF;

  IF p_kind = 'text' THEN
    DELETE FROM public.bot_content_library WHERE id = p_id;
  ELSIF p_kind = 'image' THEN
    DELETE FROM public.bot_image_library WHERE id = p_id;
  ELSE
    RAISE EXCEPTION 'admin_bot_library_delete: geçersiz tür (text|image)';
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_bot_library_delete(text, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_bot_library_delete(text, uuid)
  TO authenticated, service_role;

-- -----------------------------------------------------------------------------
-- 9) admin_bot_run_queues — beğeni kuyruğunu da kapsasın
-- -----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.admin_bot_run_queues();

CREATE FUNCTION public.admin_bot_run_queues()
RETURNS TABLE (
  follows_done integer,
  posts_published integer,
  likes_scheduled integer,
  likes_done integer
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_follows integer;
  v_posts integer;
  v_like_sched integer;
  v_likes integer;
BEGIN
  IF NOT private.current_user_is_admin() THEN
    RAISE EXCEPTION 'admin_bot_run_queues: not admin' USING ERRCODE = '42501';
  END IF;

  v_follows := public.process_bot_follow_jobs(500);
  v_posts := public.publish_due_bot_posts(200);
  v_like_sched := public.schedule_bot_likes(200);
  v_likes := public.process_bot_like_jobs(500);

  RETURN QUERY SELECT v_follows, v_posts, v_like_sched, v_likes;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_bot_run_queues() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_bot_run_queues() TO authenticated, service_role;

-- -----------------------------------------------------------------------------
-- 10) admin_bot_stats — beğeni sayaçları eklendi
-- -----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.admin_bot_stats();

CREATE FUNCTION public.admin_bot_stats()
RETURNS TABLE (
  bot_count bigint,
  active_bot_count bigint,
  real_user_count bigint,
  pending_follow_jobs bigint,
  done_follow_jobs bigint,
  queued_posts bigint,
  published_posts bigint,
  bot_post_count bigint,
  pending_like_jobs bigint,
  done_like_jobs bigint,
  library_text_count bigint,
  library_image_count bigint
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF NOT private.current_user_is_admin() THEN
    RAISE EXCEPTION 'admin_bot_stats: not admin' USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
  SELECT
    (SELECT count(*) FROM public.profiles WHERE is_bot = true),
    (SELECT count(*) FROM public.profiles p
       JOIN public.bot_accounts ba ON ba.id = p.id
       WHERE p.is_bot = true AND ba.is_active = true),
    (SELECT count(*) FROM public.profiles WHERE is_bot = false),
    (SELECT count(*) FROM public.bot_follow_jobs WHERE status = 'pending'),
    (SELECT count(*) FROM public.bot_follow_jobs WHERE status = 'done'),
    (SELECT count(*) FROM public.bot_post_queue WHERE status = 'pending'),
    (SELECT count(*) FROM public.bot_post_queue WHERE status = 'published'),
    (SELECT count(*) FROM public.posts po
       JOIN public.profiles p ON p.id = po.user_id
       WHERE p.is_bot = true),
    (SELECT count(*) FROM public.bot_like_jobs WHERE status = 'pending'),
    (SELECT count(*) FROM public.bot_like_jobs WHERE status = 'done'),
    (SELECT count(*) FROM public.bot_content_library WHERE is_active = true),
    (SELECT count(*) FROM public.bot_image_library WHERE is_active = true);
END;
$$;

REVOKE ALL ON FUNCTION public.admin_bot_stats() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_bot_stats() TO authenticated, service_role;

-- -----------------------------------------------------------------------------
-- 11) pg_cron: beğeni planla + işle
-- -----------------------------------------------------------------------------
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    PERFORM cron.unschedule(jobid)
    FROM cron.job
    WHERE jobname IN ('bot_like_schedule_tick', 'bot_like_process_tick');

    -- Planlama seyrek (yeni gönderileri yakalamak için 20 dk yeter),
    -- işleme sık (vadesi gelen beğeniler gecikmesin).
    PERFORM cron.schedule(
      'bot_like_schedule_tick', '*/20 * * * *',
      $cron$SELECT public.schedule_bot_likes(200);$cron$
    );
    PERFORM cron.schedule(
      'bot_like_process_tick', '*/7 * * * *',
      $cron$SELECT public.process_bot_like_jobs(300);$cron$
    );
  END IF;
END;
$$;

commit;
