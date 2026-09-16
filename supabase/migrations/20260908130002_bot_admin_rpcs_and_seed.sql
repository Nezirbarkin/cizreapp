-- =============================================================================
-- 20260908130002_bot_admin_rpcs_and_seed.sql
-- -----------------------------------------------------------------------------
-- Bot hesaplarının admin panelinden yönetimi: liste, oluştur, güncelle, sil,
-- gönderi kuyruğu ve istatistikler. Tüm RPC'ler SECURITY DEFINER + admin
-- kontrolü ile korunur; istemcinin `profiles`/`posts` üzerinde doğrudan yazma
-- hakkı yoktur.
--
-- Ayrıca 20 adet hazır (Cizre/Şırnak bağlamına uygun) bot personası tohumlanır.
-- Tohumlama idempotenttir: `admin_bot_seed_defaults()` her çağrıldığında yalnız
-- eksik olan kullanıcı adlarını ekler, mevcut botların admin tarafından
-- düzenlenmiş bilgilerini EZMEZ.
-- =============================================================================

begin;

-- -----------------------------------------------------------------------------
-- 1) Liste
-- -----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.admin_bot_list();

CREATE FUNCTION public.admin_bot_list()
RETURNS TABLE (
  id uuid,
  username text,
  full_name text,
  bio text,
  avatar_url text,
  banner_url text,
  location text,
  website text,
  persona text,
  is_active boolean,
  auto_follow_enabled boolean,
  follow_weight integer,
  followers_count bigint,
  following_count bigint,
  posts_count bigint,
  pending_jobs bigint,
  created_at timestamptz
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF NOT private.current_user_is_admin() THEN
    RAISE EXCEPTION 'admin_bot_list: not admin' USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
  SELECT
    p.id,
    p.username,
    p.full_name,
    p.bio,
    p.avatar_url,
    p.banner_url,
    p.location,
    p.website,
    ba.persona,
    ba.is_active,
    ba.auto_follow_enabled,
    ba.follow_weight,
    (SELECT count(*) FROM public.follows f WHERE f.following_id = p.id),
    (SELECT count(*) FROM public.follows f WHERE f.follower_id = p.id),
    (SELECT count(*) FROM public.posts po WHERE po.user_id = p.id),
    (SELECT count(*) FROM public.bot_follow_jobs j
       WHERE j.bot_id = p.id AND j.status = 'pending'),
    p.created_at
  FROM public.profiles p
  JOIN public.bot_accounts ba ON ba.id = p.id
  WHERE p.is_bot = true
  ORDER BY p.created_at;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_bot_list() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_bot_list() TO authenticated, service_role;

-- -----------------------------------------------------------------------------
-- 2) İstatistik
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
  bot_post_count bigint
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
       WHERE p.is_bot = true);
END;
$$;

REVOKE ALL ON FUNCTION public.admin_bot_stats() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_bot_stats() TO authenticated, service_role;

-- -----------------------------------------------------------------------------
-- 3) Oluştur / Güncelle / Sil
-- -----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.admin_bot_create(text, text, text, text, text, text, text);

CREATE FUNCTION public.admin_bot_create(
  p_full_name text,
  p_username text,
  p_bio text DEFAULT NULL,
  p_avatar_url text DEFAULT NULL,
  p_location text DEFAULT NULL,
  p_website text DEFAULT NULL,
  p_persona text DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_id uuid := gen_random_uuid();
  v_username text := lower(btrim(COALESCE(p_username, '')));
  v_full_name text := btrim(COALESCE(p_full_name, ''));
BEGIN
  IF NOT private.current_user_is_admin() THEN
    RAISE EXCEPTION 'admin_bot_create: not admin' USING ERRCODE = '42501';
  END IF;

  IF v_username = '' OR v_full_name = '' THEN
    RAISE EXCEPTION 'admin_bot_create: kullanıcı adı ve ad soyad zorunlu';
  END IF;

  IF EXISTS (SELECT 1 FROM public.profiles WHERE lower(username) = v_username) THEN
    RAISE EXCEPTION 'admin_bot_create: "%" kullanıcı adı zaten kullanımda', v_username;
  END IF;

  INSERT INTO public.profiles (
    id, email, full_name, username, bio, avatar_url, location, website,
    role, status, is_bot, profile_is_public, is_online, is_online_enabled,
    messages_enabled, allow_messages_from_non_followers, created_at, last_seen
  ) VALUES (
    v_id,
    v_username || '@bot.cizreapp.local',
    v_full_name,
    v_username,
    NULLIF(btrim(COALESCE(p_bio, '')), ''),
    NULLIF(btrim(COALESCE(p_avatar_url, '')), ''),
    NULLIF(btrim(COALESCE(p_location, '')), ''),
    NULLIF(btrim(COALESCE(p_website, '')), ''),
    'customer'::public.user_role,
    'active'::public.user_status,
    true,
    true,
    false,
    false,
    false,
    false,
    now(),
    now()
  );

  INSERT INTO public.bot_accounts (id, persona)
  VALUES (v_id, NULLIF(btrim(COALESCE(p_persona, '')), ''));

  RETURN v_id;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_bot_create(text, text, text, text, text, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_bot_create(text, text, text, text, text, text, text)
  TO authenticated, service_role;

DROP FUNCTION IF EXISTS public.admin_bot_update(uuid, text, text, text, text, text, text, text, text, boolean, boolean, integer);

CREATE FUNCTION public.admin_bot_update(
  p_id uuid,
  p_full_name text DEFAULT NULL,
  p_username text DEFAULT NULL,
  p_bio text DEFAULT NULL,
  p_avatar_url text DEFAULT NULL,
  p_banner_url text DEFAULT NULL,
  p_location text DEFAULT NULL,
  p_website text DEFAULT NULL,
  p_persona text DEFAULT NULL,
  p_is_active boolean DEFAULT NULL,
  p_auto_follow_enabled boolean DEFAULT NULL,
  p_follow_weight integer DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_username text := lower(btrim(COALESCE(p_username, '')));
BEGIN
  IF NOT private.current_user_is_admin() THEN
    RAISE EXCEPTION 'admin_bot_update: not admin' USING ERRCODE = '42501';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM public.profiles WHERE id = p_id AND is_bot = true) THEN
    RAISE EXCEPTION 'admin_bot_update: bot bulunamadı';
  END IF;

  IF v_username <> '' AND EXISTS (
    SELECT 1 FROM public.profiles
    WHERE lower(username) = v_username AND id <> p_id
  ) THEN
    RAISE EXCEPTION 'admin_bot_update: "%" kullanıcı adı zaten kullanımda', v_username;
  END IF;

  -- NULL gelen alanlar dokunulmadan bırakılır; boş string ise temizlenir.
  UPDATE public.profiles p
  SET
    full_name  = COALESCE(NULLIF(btrim(p_full_name), ''), p.full_name),
    username   = CASE WHEN v_username <> '' THEN v_username ELSE p.username END,
    bio        = CASE WHEN p_bio        IS NULL THEN p.bio        ELSE NULLIF(btrim(p_bio), '')        END,
    avatar_url = CASE WHEN p_avatar_url IS NULL THEN p.avatar_url ELSE NULLIF(btrim(p_avatar_url), '') END,
    banner_url = CASE WHEN p_banner_url IS NULL THEN p.banner_url ELSE NULLIF(btrim(p_banner_url), '') END,
    location   = CASE WHEN p_location   IS NULL THEN p.location   ELSE NULLIF(btrim(p_location), '')   END,
    website    = CASE WHEN p_website    IS NULL THEN p.website    ELSE NULLIF(btrim(p_website), '')    END,
    updated_at = now()
  WHERE p.id = p_id;

  UPDATE public.bot_accounts ba
  SET
    persona             = CASE WHEN p_persona IS NULL THEN ba.persona
                               ELSE NULLIF(btrim(p_persona), '') END,
    is_active           = COALESCE(p_is_active, ba.is_active),
    auto_follow_enabled = COALESCE(p_auto_follow_enabled, ba.auto_follow_enabled),
    follow_weight       = COALESCE(GREATEST(p_follow_weight, 0), ba.follow_weight),
    updated_at          = now()
  WHERE ba.id = p_id;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_bot_update(uuid, text, text, text, text, text, text, text, text, boolean, boolean, integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_bot_update(uuid, text, text, text, text, text, text, text, text, boolean, boolean, integer)
  TO authenticated, service_role;

DROP FUNCTION IF EXISTS public.admin_bot_delete(uuid);

CREATE FUNCTION public.admin_bot_delete(p_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF NOT private.current_user_is_admin() THEN
    RAISE EXCEPTION 'admin_bot_delete: not admin' USING ERRCODE = '42501';
  END IF;

  -- GÜVENLİK: yalnız is_bot=true satır silinebilir. Gerçek bir üyenin
  -- bu RPC üzerinden silinmesi mümkün değildir.
  IF NOT EXISTS (SELECT 1 FROM public.profiles WHERE id = p_id AND is_bot = true) THEN
    RAISE EXCEPTION 'admin_bot_delete: bot bulunamadı';
  END IF;

  -- posts / follows / bot_* tabloları ON DELETE CASCADE ile temizlenir.
  DELETE FROM public.profiles WHERE id = p_id AND is_bot = true;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_bot_delete(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_bot_delete(uuid) TO authenticated, service_role;

-- -----------------------------------------------------------------------------
-- 4) Gönderi kuyruğu yönetimi
-- -----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.admin_bot_queue_list(text, integer);

CREATE FUNCTION public.admin_bot_queue_list(
  p_status text DEFAULT NULL,
  p_limit integer DEFAULT 100
)
RETURNS TABLE (
  id uuid,
  bot_id uuid,
  bot_username text,
  bot_full_name text,
  bot_avatar_url text,
  content text,
  images text[],
  location text,
  scheduled_at timestamptz,
  status text,
  post_id uuid,
  published_at timestamptz,
  error_message text,
  created_at timestamptz
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF NOT private.current_user_is_admin() THEN
    RAISE EXCEPTION 'admin_bot_queue_list: not admin' USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
  SELECT
    q.id, q.bot_id, p.username, p.full_name, p.avatar_url,
    q.content, q.images, q.location, q.scheduled_at, q.status,
    q.post_id, q.published_at, q.error_message, q.created_at
  FROM public.bot_post_queue q
  LEFT JOIN public.profiles p ON p.id = q.bot_id
  WHERE p_status IS NULL OR q.status = p_status
  ORDER BY q.scheduled_at DESC
  LIMIT GREATEST(COALESCE(p_limit, 100), 1);
END;
$$;

REVOKE ALL ON FUNCTION public.admin_bot_queue_list(text, integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_bot_queue_list(text, integer)
  TO authenticated, service_role;

DROP FUNCTION IF EXISTS public.admin_bot_queue_upsert(uuid, uuid, text, text[], text, timestamptz);

CREATE FUNCTION public.admin_bot_queue_upsert(
  p_id uuid DEFAULT NULL,
  p_bot_id uuid DEFAULT NULL,
  p_content text DEFAULT NULL,
  p_images text[] DEFAULT '{}'::text[],
  p_location text DEFAULT NULL,
  p_scheduled_at timestamptz DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_id uuid;
  v_images text[] := COALESCE(p_images, '{}'::text[]);
BEGIN
  IF NOT private.current_user_is_admin() THEN
    RAISE EXCEPTION 'admin_bot_queue_upsert: not admin' USING ERRCODE = '42501';
  END IF;

  IF p_bot_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM public.profiles WHERE id = p_bot_id AND is_bot = true
  ) THEN
    RAISE EXCEPTION 'admin_bot_queue_upsert: geçersiz bot';
  END IF;

  IF COALESCE(btrim(p_content), '') = '' AND array_length(v_images, 1) IS NULL THEN
    RAISE EXCEPTION 'admin_bot_queue_upsert: metin veya en az bir görsel gerekli';
  END IF;

  IF p_id IS NULL THEN
    INSERT INTO public.bot_post_queue
      (bot_id, content, images, location, scheduled_at, created_by)
    VALUES
      (p_bot_id,
       NULLIF(btrim(COALESCE(p_content, '')), ''),
       v_images,
       NULLIF(btrim(COALESCE(p_location, '')), ''),
       COALESCE(p_scheduled_at, now()),
       auth.uid())
    RETURNING id INTO v_id;
  ELSE
    UPDATE public.bot_post_queue q
    SET bot_id       = p_bot_id,
        content      = NULLIF(btrim(COALESCE(p_content, '')), ''),
        images       = v_images,
        location     = NULLIF(btrim(COALESCE(p_location, '')), ''),
        scheduled_at = COALESCE(p_scheduled_at, q.scheduled_at),
        updated_at   = now()
    WHERE q.id = p_id AND q.status = 'pending'
    RETURNING q.id INTO v_id;

    IF v_id IS NULL THEN
      RAISE EXCEPTION 'admin_bot_queue_upsert: yalnız bekleyen kayıtlar düzenlenebilir';
    END IF;
  END IF;

  RETURN v_id;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_bot_queue_upsert(uuid, uuid, text, text[], text, timestamptz) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_bot_queue_upsert(uuid, uuid, text, text[], text, timestamptz)
  TO authenticated, service_role;

DROP FUNCTION IF EXISTS public.admin_bot_queue_delete(uuid);

CREATE FUNCTION public.admin_bot_queue_delete(p_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF NOT private.current_user_is_admin() THEN
    RAISE EXCEPTION 'admin_bot_queue_delete: not admin' USING ERRCODE = '42501';
  END IF;
  DELETE FROM public.bot_post_queue WHERE id = p_id;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_bot_queue_delete(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_bot_queue_delete(uuid) TO authenticated, service_role;

-- -----------------------------------------------------------------------------
-- 5) Elle çalıştırma (admin panelindeki "Şimdi çalıştır" düğmeleri)
-- -----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.admin_bot_run_queues();

CREATE FUNCTION public.admin_bot_run_queues()
RETURNS TABLE (follows_done integer, posts_published integer)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_follows integer;
  v_posts integer;
BEGIN
  IF NOT private.current_user_is_admin() THEN
    RAISE EXCEPTION 'admin_bot_run_queues: not admin' USING ERRCODE = '42501';
  END IF;

  v_follows := public.process_bot_follow_jobs(500);
  v_posts := public.publish_due_bot_posts(200);

  RETURN QUERY SELECT v_follows, v_posts;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_bot_run_queues() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_bot_run_queues() TO authenticated, service_role;

-- Mevcut (geçmişte kaydolmuş) üyeler için de takip planla. Yalnız hiç bot
-- takip işi almamış üyelere iş açar; tekrar çağırmak güvenlidir.
DROP FUNCTION IF EXISTS public.admin_bot_backfill_follows(integer, integer);

CREATE FUNCTION public.admin_bot_backfill_follows(
  p_max_users integer DEFAULT 500,
  p_spread_hours integer DEFAULT 72
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_user record;
  v_min_count integer;
  v_max_count integer;
  v_count integer;
  v_total integer := 0;
BEGIN
  IF NOT private.current_user_is_admin() THEN
    RAISE EXCEPTION 'admin_bot_backfill_follows: not admin' USING ERRCODE = '42501';
  END IF;

  v_min_count := GREATEST(private.bot_setting_int('bot_follow_min_count', 3), 0);
  v_max_count := GREATEST(private.bot_setting_int('bot_follow_max_count', 8), v_min_count);

  FOR v_user IN
    SELECT p.id
    FROM public.profiles p
    WHERE p.is_bot = false
      AND p.status = 'active'::public.user_status
      AND NOT EXISTS (
        SELECT 1 FROM public.bot_follow_jobs j WHERE j.target_user_id = p.id
      )
    ORDER BY p.created_at DESC
    LIMIT GREATEST(COALESCE(p_max_users, 500), 1)
  LOOP
    v_count := v_min_count + floor(random() * (v_max_count - v_min_count + 1))::integer;
    IF v_count <= 0 THEN
      CONTINUE;
    END IF;

    INSERT INTO public.bot_follow_jobs (bot_id, target_user_id, due_at)
    SELECT b.id, v_user.id,
           now() + make_interval(
             secs => random() * GREATEST(COALESCE(p_spread_hours, 72), 0) * 3600
           )
    FROM public.profiles b
    JOIN public.bot_accounts ba ON ba.id = b.id
    WHERE b.is_bot = true
      AND b.status = 'active'::public.user_status
      AND ba.is_active = true
      AND ba.auto_follow_enabled = true
      AND NOT EXISTS (
        SELECT 1 FROM public.follows f
        WHERE f.follower_id = b.id AND f.following_id = v_user.id
      )
    ORDER BY random() * GREATEST(ba.follow_weight, 1) DESC
    LIMIT v_count
    ON CONFLICT (bot_id, target_user_id) DO NOTHING;

    v_total := v_total + 1;
  END LOOP;

  RETURN v_total;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_bot_backfill_follows(integer, integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_bot_backfill_follows(integer, integer)
  TO authenticated, service_role;

-- -----------------------------------------------------------------------------
-- 6) 20 hazır persona
-- -----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.admin_bot_seed_defaults();

CREATE FUNCTION public.admin_bot_seed_defaults()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_row record;
  v_id uuid;
  v_created integer := 0;
BEGIN
  IF NOT private.current_user_is_admin() THEN
    RAISE EXCEPTION 'admin_bot_seed_defaults: not admin' USING ERRCODE = '42501';
  END IF;

  FOR v_row IN
    SELECT * FROM (VALUES
      ('berivan.aydin',   'Berivan Aydın',      'Cizre''de doğdum, burada büyüdüm. Kahve, kitap ve uzun yürüyüşler. ☕📚', 'Cizre, Şırnak', 'Yerel / günlük hayat'),
      ('serhatdemir',     'Serhat Demir',       'Elektrik teknikeri ⚡ İşten arta kalan zaman sahada geçer.',              'Cizre, Şırnak', 'Esnaf / teknik'),
      ('rojda.kaya',      'Rojda Kaya',         'Anaokulu öğretmeni 🍎 Çocuklarla geçen her gün yeni bir hikâye.',        'Cizre, Şırnak', 'Eğitim'),
      ('mehmetalitunc',   'Mehmet Ali Tunç',    'Çarşıda üçüncü kuşak esnaf. Sabah çayı bizden. ☕',                      'Cizre, Şırnak', 'Esnaf'),
      ('delalyilmaz',     'Delal Yılmaz',       'Hemşire 👩‍⚕️ Boş vaktimde doğa fotoğrafı çekerim. 📷',                   'Cizre, Şırnak', 'Sağlık'),
      ('baranozcan',      'Baran Özcan',        'Yazılımcı 💻 Dicle kıyısında kod yazmak ayrı güzel.',                    'Cizre, Şırnak', 'Teknoloji'),
      ('hediyesahin',     'Hediye Şahin',       'Ev yemekleri ve tatlı tarifleri 🍰 Sipariş için mesaj.',                 'Cizre, Şırnak', 'Yemek'),
      ('cihanaslan',      'Cihan Aslan',        'Motosiklet tutkunu 🏍️ Cizre–Silopi–İdil rotası favorim.',               'Cizre, Şırnak', 'Gezi / hobi'),
      ('nurcanerdem',     'Nurcan Erdem',       'Üniversite öğrencisi 🎓 Psikoloji | kediler ve müzik.',                  'Şırnak', 'Öğrenci'),
      ('ferhatpolat',     'Ferhat Polat',       'Kurye 🛵 Şehri avucumun içi gibi bilirim.',                              'Cizre, Şırnak', 'Kurye / lojistik'),
      ('zilanaktas',      'Zilan Aktaş',        'Tekstil atölyesi 🧵 El emeği, göz nuru.',                                'Cizre, Şırnak', 'Zanaat'),
      ('cemalyildirim',   'Cemal Yıldırım',     'Emekli öğretmen ✏️ Otuz yıl anlattım, hâlâ öğreniyorum.',               'Cizre, Şırnak', 'Eğitim'),
      ('silakorkmaz',     'Sıla Korkmaz',       'Kuaför ✂️ Randevu için mesaj yeterli.',                                  'Cizre, Şırnak', 'Hizmet'),
      ('ercandogan',      'Ercan Doğan',        'Market işletmecisi 🛒 Taze meyve sebze her sabah.',                      'Cizre, Şırnak', 'Esnaf'),
      ('aysenurbayram',   'Ayşe Nur Bayram',    'Diş hekimi 🦷 Gülümsemek bulaşıcıdır.',                                  'Cizre, Şırnak', 'Sağlık'),
      ('ramazancelik',    'Ramazan Çelik',      'Oto tamir 🔧 Yirmi yıllık usta, sanayi sitesi.',                         'Cizre, Şırnak', 'Esnaf / teknik'),
      ('helinarslan',     'Helin Arslan',       'Grafik tasarımcı 🎨 Renklerle konuşurum.',                               'Cizre, Şırnak', 'Tasarım'),
      ('yusufkaratas',    'Yusuf Karataş',      'Antrenör 💪 Disiplin özgürlüktür.',                                      'Cizre, Şırnak', 'Spor'),
      ('gulistanacar',    'Gülistan Acar',      'Çiçekçi 🌷 Her buket bir hikâye.',                                       'Cizre, Şırnak', 'Esnaf'),
      ('kadirsimsek',     'Kadir Şimşek',       'Halı saha işletmecisi ⚽ Akşam maçı var mı?',                             'Cizre, Şırnak', 'Spor / işletme')
    ) AS t(username, full_name, bio, location, persona)
  LOOP
    IF EXISTS (SELECT 1 FROM public.profiles WHERE lower(username) = v_row.username) THEN
      CONTINUE;
    END IF;

    v_id := gen_random_uuid();

    INSERT INTO public.profiles (
      id, email, full_name, username, bio, location,
      role, status, is_bot, profile_is_public, is_online, is_online_enabled,
      messages_enabled, allow_messages_from_non_followers, created_at, last_seen
    ) VALUES (
      v_id,
      v_row.username || '@bot.cizreapp.local',
      v_row.full_name,
      v_row.username,
      v_row.bio,
      v_row.location,
      'customer'::public.user_role,
      'active'::public.user_status,
      true, true, false, false, false, false,
      -- Kayıt tarihlerini geçmişe yay: hepsi aynı anda açılmış görünmesin.
      now() - make_interval(days => 20 + floor(random() * 300)::integer),
      now() - make_interval(hours => floor(random() * 72)::integer)
    );

    INSERT INTO public.bot_accounts (id, persona)
    VALUES (v_id, v_row.persona);

    v_created := v_created + 1;
  END LOOP;

  RETURN v_created;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_bot_seed_defaults() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_bot_seed_defaults() TO authenticated, service_role;

commit;
