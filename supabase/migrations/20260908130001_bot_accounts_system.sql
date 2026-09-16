-- =============================================================================
-- 20260908130001_bot_accounts_system.sql
-- -----------------------------------------------------------------------------
-- AMAÇ: Uygulamanın sosyal tarafını (Keşfet akışı, profiller, takipçiler) dolu
-- göstermek için yönetilebilir "bot" hesapları.
--
-- TASARIM KARARLARI (önemli):
--
-- 1) Bot hesapları YALNIZCA `public.profiles` satırıdır; `auth.users` kaydı
--    YOKTUR. `profiles.id` üzerinde auth.users'a FK olmadığı için bu mümkün
--    (bkz. FK denetimi: profiles'ın hiç FK'si yok). Sonuç:
--      * Bir bot ASLA giriş yapamaz, oturum açamaz, parola sıfırlayamaz.
--      * `auth.users` sayacı (gerçek kayıtlı üye sayısı) kirlenmiş olmaz.
--      * Bot silmek auth tarafında hiçbir artık bırakmaz.
--
-- 2) `profiles.is_bot` bayrağı tek doğruluk kaynağıdır. Admin sayaç RPC'leri
--    (`admin_dashboard_counts`, `admin_logs_counts`, `admin_user_role_counts`)
--    bu bayrağı HARİÇ TUTAR — kullanıcının istediği gibi botlar gerçek üye
--    sayısına karışmaz. Bot sayısı ayrı `admin_bot_stats()` RPC'sinden okunur.
--
-- 3) İstemci `profiles` üzerinde yalnız SELECT hakkına sahiptir (INSERT/UPDATE
--    grant'i yok) ve `private.guard_profiles_privileged_columns` trigger'ı
--    ayrıcalıklı sütunları korur. Bu yüzden `is_bot` istemciden set edilemez;
--    tüm yazma yolları buradaki SECURITY DEFINER admin RPC'lerinden geçer.
--
-- 4) Takip planlaması: yeni (bot olmayan) bir profil oluştuğunda trigger,
--    rastgele N bot için `bot_follow_jobs` satırı yazar; `due_at` ayarlardaki
--    min/max saat aralığında (varsayılan 0-72 saat) rastgele dağıtılır.
--    pg_cron işi vadesi gelenleri `follows` tablosuna işler; oradaki mevcut
--    `notify_new_follower_trigger` bildirimi kendiliğinden üretir.
--
-- 5) Kayıt akışı ASLA bloklanmaz: trigger'ın gövdesi EXCEPTION ile sarılıdır
--    ve hata `signup_trigger_errors` tablosuna loglanır (bkz.
--    20260817000035_harden_signup_trigger_never_blocks_registration.sql).
-- =============================================================================

begin;

-- -----------------------------------------------------------------------------
-- 1) profiles.is_bot
-- -----------------------------------------------------------------------------
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS is_bot boolean NOT NULL DEFAULT false;

CREATE INDEX IF NOT EXISTS idx_profiles_is_bot
  ON public.profiles (id) WHERE is_bot = true;

COMMENT ON COLUMN public.profiles.is_bot IS
  'true ise bu profil yönetim tarafından oluşturulmuş bir vitrin hesabıdır; '
  'auth.users kaydı yoktur ve admin üye sayaçlarına dahil edilmez.';

-- -----------------------------------------------------------------------------
-- 2) bot_accounts — bot'a özel yönetim alanları
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.bot_accounts (
  id uuid PRIMARY KEY REFERENCES public.profiles(id) ON DELETE CASCADE,
  persona text,
  is_active boolean NOT NULL DEFAULT true,
  auto_follow_enabled boolean NOT NULL DEFAULT true,
  follow_weight integer NOT NULL DEFAULT 100 CHECK (follow_weight >= 0),
  notes text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.bot_accounts ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.bot_accounts FROM PUBLIC, anon, authenticated;
GRANT ALL ON TABLE public.bot_accounts TO service_role;

DROP POLICY IF EXISTS bot_accounts_admin_all ON public.bot_accounts;
CREATE POLICY bot_accounts_admin_all ON public.bot_accounts
  FOR ALL USING (private.current_user_is_admin())
  WITH CHECK (private.current_user_is_admin());

-- -----------------------------------------------------------------------------
-- 3) bot_follow_jobs — planlanmış takip işleri
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.bot_follow_jobs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  bot_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  target_user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  due_at timestamptz NOT NULL,
  status text NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending', 'done', 'skipped', 'failed', 'cancelled')),
  processed_at timestamptz,
  error_message text,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT bot_follow_jobs_unique UNIQUE (bot_id, target_user_id)
);

CREATE INDEX IF NOT EXISTS idx_bot_follow_jobs_due
  ON public.bot_follow_jobs (due_at) WHERE status = 'pending';
CREATE INDEX IF NOT EXISTS idx_bot_follow_jobs_target
  ON public.bot_follow_jobs (target_user_id);

ALTER TABLE public.bot_follow_jobs ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.bot_follow_jobs FROM PUBLIC, anon, authenticated;
GRANT ALL ON TABLE public.bot_follow_jobs TO service_role;

DROP POLICY IF EXISTS bot_follow_jobs_admin_all ON public.bot_follow_jobs;
CREATE POLICY bot_follow_jobs_admin_all ON public.bot_follow_jobs
  FOR ALL USING (private.current_user_is_admin())
  WITH CHECK (private.current_user_is_admin());

-- -----------------------------------------------------------------------------
-- 4) bot_post_queue — admin'in düzenlediği bot gönderi kuyruğu
-- -----------------------------------------------------------------------------
-- `bot_id` NULL ise yayın anında rastgele aktif bir bot seçilir. `images`
-- doğrudan `posts.images` (text[]) alanına kopyalanır; görseller mevcut
-- `posts` storage bucket'ına admin panelinden yüklenir.
CREATE TABLE IF NOT EXISTS public.bot_post_queue (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  bot_id uuid REFERENCES public.profiles(id) ON DELETE CASCADE,
  content text,
  images text[] NOT NULL DEFAULT '{}',
  location text,
  scheduled_at timestamptz NOT NULL DEFAULT now(),
  status text NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending', 'published', 'cancelled', 'failed')),
  post_id uuid,
  published_at timestamptz,
  error_message text,
  created_by uuid,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT bot_post_queue_has_body
    CHECK (COALESCE(btrim(content), '') <> '' OR array_length(images, 1) >= 1)
);

CREATE INDEX IF NOT EXISTS idx_bot_post_queue_due
  ON public.bot_post_queue (scheduled_at) WHERE status = 'pending';

ALTER TABLE public.bot_post_queue ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.bot_post_queue FROM PUBLIC, anon, authenticated;
GRANT ALL ON TABLE public.bot_post_queue TO service_role;

DROP POLICY IF EXISTS bot_post_queue_admin_all ON public.bot_post_queue;
CREATE POLICY bot_post_queue_admin_all ON public.bot_post_queue
  FOR ALL USING (private.current_user_is_admin())
  WITH CHECK (private.current_user_is_admin());

-- -----------------------------------------------------------------------------
-- 5) Ayarlar (app_settings, key/value jsonb)
-- -----------------------------------------------------------------------------
INSERT INTO public.app_settings (key, value, description)
VALUES
  ('bot_auto_follow_enabled', 'true'::jsonb,
   'Yeni üye kaydolduğunda bot hesapları otomatik takip etsin mi?'),
  ('bot_follow_min_hours', '0'::jsonb,
   'Bot takibinin en erken gerçekleşeceği saat (kayıttan sonra).'),
  ('bot_follow_max_hours', '72'::jsonb,
   'Bot takibinin en geç gerçekleşeceği saat (kayıttan sonra).'),
  ('bot_follow_min_count', '3'::jsonb,
   'Yeni üyeyi takip edecek en az bot sayısı.'),
  ('bot_follow_max_count', '8'::jsonb,
   'Yeni üyeyi takip edecek en fazla bot sayısı.')
ON CONFLICT (key) DO NOTHING;

-- -----------------------------------------------------------------------------
-- 6) Yardımcılar
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION private.bot_setting_int(p_key text, p_default integer)
RETURNS integer
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT COALESCE(
    (SELECT NULLIF(btrim(s.value #>> '{}'), '')::integer
       FROM public.app_settings s WHERE s.key = p_key),
    p_default
  );
$$;

CREATE OR REPLACE FUNCTION private.bot_setting_bool(p_key text, p_default boolean)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT COALESCE(
    (SELECT NULLIF(btrim(s.value #>> '{}'), '')::boolean
       FROM public.app_settings s WHERE s.key = p_key),
    p_default
  );
$$;

-- -----------------------------------------------------------------------------
-- 7) Yeni üye → bot takip işlerini planla (trigger)
-- -----------------------------------------------------------------------------
-- KRİTİK: Bu fonksiyon HİÇBİR koşulda hata fırlatmamalı. `profiles` INSERT'i
-- kayıt akışının (handle_new_user / ensure_my_profile) ortasında çalışır;
-- buradan çıkan bir hata kaydı tamamen geri alır. Bu yüzden tüm gövde
-- EXCEPTION ile sarılı ve hata yalnız loglanır.
CREATE OR REPLACE FUNCTION public.schedule_bot_follows_for_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_min_hours integer;
  v_max_hours integer;
  v_min_count integer;
  v_max_count integer;
  v_count integer;
BEGIN
  IF NEW.is_bot THEN
    RETURN NEW;
  END IF;

  IF NOT private.bot_setting_bool('bot_auto_follow_enabled', true) THEN
    RETURN NEW;
  END IF;

  v_min_hours := GREATEST(private.bot_setting_int('bot_follow_min_hours', 0), 0);
  v_max_hours := GREATEST(private.bot_setting_int('bot_follow_max_hours', 72), v_min_hours);
  v_min_count := GREATEST(private.bot_setting_int('bot_follow_min_count', 3), 0);
  v_max_count := GREATEST(private.bot_setting_int('bot_follow_max_count', 8), v_min_count);

  -- [min, max] aralığında rastgele bot sayısı
  v_count := v_min_count + floor(random() * (v_max_count - v_min_count + 1))::integer;

  IF v_count <= 0 THEN
    RETURN NEW;
  END IF;

  INSERT INTO public.bot_follow_jobs (bot_id, target_user_id, due_at)
  SELECT
    b.id,
    NEW.id,
    now() + make_interval(
      secs => (v_min_hours * 3600)
              + (random() * GREATEST(v_max_hours - v_min_hours, 0) * 3600)
    )
  FROM public.profiles b
  JOIN public.bot_accounts ba ON ba.id = b.id
  WHERE b.is_bot = true
    AND b.status = 'active'::public.user_status
    AND ba.is_active = true
    AND ba.auto_follow_enabled = true
    AND b.id <> NEW.id
  ORDER BY random() * GREATEST(ba.follow_weight, 1) DESC
  LIMIT v_count
  ON CONFLICT (bot_id, target_user_id) DO NOTHING;

  RETURN NEW;
EXCEPTION
  WHEN OTHERS THEN
    BEGIN
      INSERT INTO public.signup_trigger_errors
        (user_id, source, error_sqlstate, error_message)
      VALUES
        (NEW.id, 'schedule_bot_follows_for_new_user', SQLSTATE, SQLERRM);
    EXCEPTION WHEN OTHERS THEN
      NULL;
    END;
    RAISE WARNING 'schedule_bot_follows_for_new_user failed for %: %', NEW.id, SQLERRM;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_schedule_bot_follows ON public.profiles;
CREATE TRIGGER trg_schedule_bot_follows
  AFTER INSERT ON public.profiles
  FOR EACH ROW
  EXECUTE FUNCTION public.schedule_bot_follows_for_new_user();

-- -----------------------------------------------------------------------------
-- 8) Vadesi gelen takip işlerini işle (pg_cron)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.process_bot_follow_jobs(p_limit integer DEFAULT 200)
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
    SELECT j.id, j.bot_id, j.target_user_id
    FROM public.bot_follow_jobs j
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
      -- Hedef profil hâlâ var mı / silinmiş mi?
      IF NOT EXISTS (
        SELECT 1 FROM public.profiles p
        WHERE p.id = v_job.target_user_id
          AND p.status <> 'deleted'::public.user_status
      ) THEN
        UPDATE public.bot_follow_jobs
        SET status = 'skipped', processed_at = now(),
            error_message = 'target profile missing or deleted'
        WHERE id = v_job.id;
        CONTINUE;
      END IF;

      INSERT INTO public.follows (follower_id, following_id)
      VALUES (v_job.bot_id, v_job.target_user_id)
      ON CONFLICT DO NOTHING;

      UPDATE public.bot_follow_jobs
      SET status = 'done', processed_at = now()
      WHERE id = v_job.id;

      v_done := v_done + 1;
    EXCEPTION WHEN OTHERS THEN
      UPDATE public.bot_follow_jobs
      SET status = 'failed', processed_at = now(), error_message = SQLERRM
      WHERE id = v_job.id;
    END;
  END LOOP;

  RETURN v_done;
END;
$$;

REVOKE ALL ON FUNCTION public.process_bot_follow_jobs(integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.process_bot_follow_jobs(integer) TO service_role;

-- -----------------------------------------------------------------------------
-- 9) Vadesi gelen bot gönderilerini yayınla (pg_cron)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.publish_due_bot_posts(p_limit integer DEFAULT 50)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_row record;
  v_bot_id uuid;
  v_post_id uuid;
  v_done integer := 0;
BEGIN
  FOR v_row IN
    SELECT q.id, q.bot_id, q.content, q.images, q.location
    FROM public.bot_post_queue q
    WHERE q.status = 'pending'
      AND q.scheduled_at <= now()
    ORDER BY q.scheduled_at
    LIMIT GREATEST(COALESCE(p_limit, 50), 1)
    FOR UPDATE SKIP LOCKED
  LOOP
    BEGIN
      v_bot_id := v_row.bot_id;

      -- Bot atanmamışsa yayın anında rastgele aktif bir bot seç
      IF v_bot_id IS NULL THEN
        SELECT b.id INTO v_bot_id
        FROM public.profiles b
        JOIN public.bot_accounts ba ON ba.id = b.id
        WHERE b.is_bot = true
          AND b.status = 'active'::public.user_status
          AND ba.is_active = true
        ORDER BY random()
        LIMIT 1;
      END IF;

      IF v_bot_id IS NULL THEN
        UPDATE public.bot_post_queue
        SET status = 'failed', error_message = 'aktif bot bulunamadı',
            updated_at = now()
        WHERE id = v_row.id;
        CONTINUE;
      END IF;

      INSERT INTO public.posts (user_id, content, images, image_url, location, is_active)
      VALUES (
        v_bot_id,
        NULLIF(btrim(COALESCE(v_row.content, '')), ''),
        COALESCE(v_row.images, '{}'::text[]),
        CASE WHEN array_length(v_row.images, 1) >= 1 THEN v_row.images[1] ELSE NULL END,
        NULLIF(btrim(COALESCE(v_row.location, '')), ''),
        true
      )
      RETURNING id INTO v_post_id;

      UPDATE public.bot_post_queue
      SET status = 'published', post_id = v_post_id, published_at = now(),
          bot_id = v_bot_id, updated_at = now()
      WHERE id = v_row.id;

      v_done := v_done + 1;
    EXCEPTION WHEN OTHERS THEN
      UPDATE public.bot_post_queue
      SET status = 'failed', error_message = SQLERRM, updated_at = now()
      WHERE id = v_row.id;
    END;
  END LOOP;

  RETURN v_done;
END;
$$;

REVOKE ALL ON FUNCTION public.publish_due_bot_posts(integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.publish_due_bot_posts(integer) TO service_role;

-- -----------------------------------------------------------------------------
-- 10) pg_cron işleri
-- -----------------------------------------------------------------------------
-- Takip işleri 10 dakikada bir, gönderi kuyruğu 5 dakikada bir taranır.
-- 0-72 saatlik dağılım için 10 dakikalık çözünürlük fazlasıyla yeterli.
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    PERFORM cron.unschedule(jobid)
    FROM cron.job
    WHERE jobname IN ('bot_follow_jobs_tick', 'bot_post_queue_tick');

    PERFORM cron.schedule(
      'bot_follow_jobs_tick', '*/10 * * * *',
      $cron$SELECT public.process_bot_follow_jobs(200);$cron$
    );
    PERFORM cron.schedule(
      'bot_post_queue_tick', '*/5 * * * *',
      $cron$SELECT public.publish_due_bot_posts(50);$cron$
    );
  END IF;
END;
$$;

-- -----------------------------------------------------------------------------
-- 11) Admin sayaçlarından botları çıkar
-- -----------------------------------------------------------------------------
-- Kullanıcının açık isteği: "botları gerçek kişilerle karıştırma (üye sayısı
-- olarak)". Aşağıdaki üç RPC uygulamadaki TÜM üye sayaçlarının kaynağıdır.

DROP FUNCTION IF EXISTS public.admin_dashboard_counts();

CREATE FUNCTION public.admin_dashboard_counts()
RETURNS TABLE (
  total_users bigint,
  total_posts bigint,
  total_products bigint,
  total_orders bigint,
  total_reports bigint,
  unanswered_complaints bigint,
  unanswered_tickets bigint,
  total_revenue numeric,
  total_admin_commission numeric,
  total_digital_orders bigint,
  total_digital_revenue numeric,
  total_couriers bigint,
  online_couriers bigint
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF NOT private.current_user_is_admin() THEN
    RAISE EXCEPTION 'admin_dashboard_counts: not admin'
      USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
  SELECT
    (SELECT count(*) FROM public.profiles WHERE is_bot = false),
    (SELECT count(*) FROM public.posts),
    (SELECT count(*) FROM public.products),
    (SELECT count(*) FROM public.orders),
    (SELECT count(*) FROM public.user_reports),
    (SELECT count(*) FROM public.user_reports
       WHERE status IN ('pending','reviewing'))
      + COALESCE((SELECT count(*) FROM public.post_reports
                   WHERE status IN ('pending','reviewing')), 0),
    (SELECT count(*) FROM public.support_tickets
       WHERE status = 'open'),
    (SELECT COALESCE(SUM(COALESCE(NULLIF(o.total, 0), o.total_amount, 0)), 0)
       FROM public.orders o WHERE o.status <> 'cancelled'),
    (SELECT COALESCE(SUM(o.admin_commission), 0)
       FROM public.orders o WHERE o.status <> 'cancelled'),
    (SELECT count(*) FROM public.digital_orders),
    (SELECT COALESCE(SUM(d.total_price), 0)
       FROM public.digital_orders d
       WHERE d.status NOT IN ('canceled', 'refunded', 'failed')),
    (SELECT count(*) FROM public.profiles
       WHERE role = 'courier'::public.user_role AND is_bot = false),
    (SELECT count(*) FROM public.profiles
       WHERE role = 'courier'::public.user_role AND is_online = true AND is_bot = false);
END;
$$;

REVOKE ALL ON FUNCTION public.admin_dashboard_counts() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_dashboard_counts()
  TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.admin_user_role_counts()
RETURNS TABLE (
  role text,
  user_count bigint
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF NOT private.current_user_is_admin() THEN
    RAISE EXCEPTION 'admin_user_role_counts: not admin'
      USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
  SELECT COALESCE(p.role::text, 'customer') AS role, count(*)::bigint AS user_count
  FROM public.profiles p
  WHERE p.is_bot = false
  GROUP BY COALESCE(p.role::text, 'customer');
END;
$$;

REVOKE ALL ON FUNCTION public.admin_user_role_counts() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_user_role_counts()
  TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.admin_logs_counts()
RETURNS TABLE (
  online_count bigint,
  dau_count bigint,
  wau_count bigint,
  mau_count bigint,
  total_users bigint,
  new_today_count bigint,
  inactive_count bigint
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_now timestamptz := now();
  v_today_start timestamptz := date_trunc('day', v_now AT TIME ZONE 'UTC') AT TIME ZONE 'UTC';
  v_week_ago timestamptz := v_now - interval '7 days';
  v_five_min_ago timestamptz := v_now - interval '5 minutes';
  v_month_ago timestamptz := v_now - interval '30 days';
BEGIN
  IF NOT private.current_user_is_admin() THEN
    RAISE EXCEPTION 'admin_logs_counts: not admin' USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
  SELECT
    (SELECT count(*) FROM public.profiles
       WHERE is_bot = false AND last_seen >= v_five_min_ago),
    (SELECT count(*) FROM public.profiles
       WHERE is_bot = false AND last_seen >= v_today_start),
    (SELECT count(*) FROM public.profiles
       WHERE is_bot = false AND last_seen >= v_week_ago),
    (SELECT count(*) FROM public.profiles
       WHERE is_bot = false AND last_seen >= v_month_ago),
    (SELECT count(*) FROM public.profiles WHERE is_bot = false),
    (SELECT count(*) FROM public.profiles
       WHERE is_bot = false AND created_at >= v_today_start),
    (SELECT count(*) FROM public.profiles
       WHERE is_bot = false AND last_seen < v_month_ago);
END;
$$;

REVOKE ALL ON FUNCTION public.admin_logs_counts() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_logs_counts()
  TO authenticated, service_role;

commit;
