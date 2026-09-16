-- =============================================================================
-- 20260908130004_bot_auth_provisioning.sql
-- -----------------------------------------------------------------------------
-- DÜZELTME: 20260908130002 numaralı migration, `public.profiles` üzerinde
-- `auth.users`'a giden bir FK OLMADIĞI varsayımıyla yazılmıştı. Bu varsayım
-- yanlış: `profiles_id_fkey` gerçekten vardır (information_schema üzerinden
-- görünmez, çünkü `auth.users` supabase_auth_admin'e aittir; pg_constraint
-- ile bakınca ortaya çıkar). Bu yüzden her bot profilinin karşılığında bir
-- `auth.users` satırı olmak ZORUNDA.
--
-- ÇÖZÜM: `private.provision_bot_auth_user()` botu önce auth tarafında açar,
-- sonra profil satırını bot alanlarıyla yazar. Bot auth kaydı GİRİŞ YAPAMAZ:
--   * `banned_until` 100 yıl ileri kurulur (GoTrue bu hesabı reddeder),
--   * parola hash'i tek kullanımlık rastgele bir değerden üretilir ve hiçbir
--     yerde saklanmaz/gösterilmez,
--   * e-posta alan adı `@bot.cizreapp.local` — teslim edilemez, yani parola
--     sıfırlama / magic link ile ele geçirilemez.
--
-- Ayrıca `admin_bot_delete` artık auth satırını siler (FK zinciri profili ve
-- gönderilerini CASCADE ile temizler); yalnız profili silmek auth tarafında
-- yetim kayıt bırakırdı.
--
-- NOT (üye sayacı): Supabase panelindeki ham "Auth users" sayısı artık botları
-- da içerir. Uygulamanın kendi üye sayaçları `profiles.is_bot = false` filtresi
-- kullandığı için (bkz. 20260908130001) admin panelindeki rakamlar temiz kalır.
-- =============================================================================

begin;

-- -----------------------------------------------------------------------------
-- 1) Bot sağlama sırasında takip planlayıcısını sustur
-- -----------------------------------------------------------------------------
-- `auth.users` INSERT'i `handle_new_user` trigger'ını tetikler; o da profili
-- (henüz is_bot=false olarak) yaratabilir. Bu, `trg_schedule_bot_follows`
-- tetikleyicisinin botun KENDİSİNİ yeni üye sanıp ona takip işi açmasına yol
-- açardı. İşlem-yerel (`is_local => true`) bir bayrakla bunu engelliyoruz.
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

  -- Bot sağlama işlemi sırasında oluşan profil satırları yeni üye değildir.
  IF COALESCE(current_setting('app.bot_provisioning', true), '') = '1' THEN
    RETURN NEW;
  END IF;

  IF NOT private.bot_setting_bool('bot_auto_follow_enabled', true) THEN
    RETURN NEW;
  END IF;

  v_min_hours := GREATEST(private.bot_setting_int('bot_follow_min_hours', 0), 0);
  v_max_hours := GREATEST(private.bot_setting_int('bot_follow_max_hours', 72), v_min_hours);
  v_min_count := GREATEST(private.bot_setting_int('bot_follow_min_count', 3), 0);
  v_max_count := GREATEST(private.bot_setting_int('bot_follow_max_count', 8), v_min_count);

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

-- -----------------------------------------------------------------------------
-- 2) Bot sağlama çekirdeği
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION private.provision_bot_auth_user(
  p_id uuid,
  p_email text,
  p_full_name text,
  p_username text,
  p_bio text,
  p_location text,
  p_avatar_url text,
  p_website text,
  p_created_at timestamptz,
  p_last_seen timestamptz
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  PERFORM set_config('app.bot_provisioning', '1', true);

  INSERT INTO auth.users (
    instance_id, id, aud, role, email, encrypted_password,
    email_confirmed_at, created_at, updated_at,
    raw_app_meta_data, raw_user_meta_data,
    confirmation_token, recovery_token, email_change_token_new, email_change,
    banned_until, is_sso_user, is_anonymous
  ) VALUES (
    '00000000-0000-0000-0000-000000000000',
    p_id,
    'authenticated',
    'authenticated',
    p_email,
    -- Tek kullanımlık rastgele parola; hiçbir yerde saklanmaz.
    extensions.crypt(gen_random_uuid()::text, extensions.gen_salt('bf')),
    now(),
    COALESCE(p_created_at, now()),
    now(),
    jsonb_build_object('provider', 'bot', 'providers', jsonb_build_array('bot')),
    jsonb_build_object('full_name', p_full_name, 'username', p_username, 'is_bot', true),
    '', '', '', '',
    now() + interval '100 years',
    false,
    false
  );

  -- handle_new_user trigger'ı profili yaratmış olabilir (veya hata yutup
  -- yaratmamış olabilir). Her iki durumu da tek yazımla kapatıyoruz.
  INSERT INTO public.profiles (
    id, email, full_name, username, bio, location, avatar_url, website,
    role, status, is_bot, profile_is_public, is_online, is_online_enabled,
    messages_enabled, allow_messages_from_non_followers, show_last_seen,
    created_at, updated_at, last_seen
  ) VALUES (
    p_id, p_email, p_full_name, p_username,
    NULLIF(btrim(COALESCE(p_bio, '')), ''),
    NULLIF(btrim(COALESCE(p_location, '')), ''),
    NULLIF(btrim(COALESCE(p_avatar_url, '')), ''),
    NULLIF(btrim(COALESCE(p_website, '')), ''),
    'customer'::public.user_role,
    'active'::public.user_status,
    true, true, false, false, false, false, false,
    COALESCE(p_created_at, now()), now(), COALESCE(p_last_seen, now())
  )
  ON CONFLICT (id) DO UPDATE SET
    email        = EXCLUDED.email,
    full_name    = EXCLUDED.full_name,
    username     = EXCLUDED.username,
    bio          = EXCLUDED.bio,
    location     = EXCLUDED.location,
    avatar_url   = EXCLUDED.avatar_url,
    website      = EXCLUDED.website,
    role         = EXCLUDED.role,
    status       = EXCLUDED.status,
    is_bot       = true,
    profile_is_public = true,
    created_at   = EXCLUDED.created_at,
    updated_at   = now(),
    last_seen    = EXCLUDED.last_seen;

  -- Sağlama sırasında yanlışlıkla açılmış olabilecek takip işlerini temizle.
  DELETE FROM public.bot_follow_jobs WHERE target_user_id = p_id;

  RETURN p_id;
END;
$$;

REVOKE ALL ON FUNCTION private.provision_bot_auth_user(uuid, text, text, text, text, text, text, text, timestamptz, timestamptz) FROM PUBLIC;

-- -----------------------------------------------------------------------------
-- 3) admin_bot_create — auth kaydıyla birlikte
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_bot_create(
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
  v_email text;
BEGIN
  IF NOT private.current_user_is_admin() THEN
    RAISE EXCEPTION 'admin_bot_create: not admin' USING ERRCODE = '42501';
  END IF;

  IF v_username = '' OR v_full_name = '' THEN
    RAISE EXCEPTION 'admin_bot_create: kullanıcı adı ve ad soyad zorunlu';
  END IF;

  IF v_username !~ '^[a-z0-9._]{3,30}$' THEN
    RAISE EXCEPTION 'admin_bot_create: kullanıcı adı yalnız a-z, 0-9, nokta ve alt çizgi içerebilir (3-30 karakter)';
  END IF;

  IF EXISTS (SELECT 1 FROM public.profiles WHERE lower(username) = v_username) THEN
    RAISE EXCEPTION 'admin_bot_create: "%" kullanıcı adı zaten kullanımda', v_username;
  END IF;

  v_email := v_username || '@bot.cizreapp.local';

  IF EXISTS (SELECT 1 FROM auth.users WHERE email = v_email) THEN
    RAISE EXCEPTION 'admin_bot_create: "%" için auth kaydı zaten var', v_email;
  END IF;

  PERFORM private.provision_bot_auth_user(
    v_id, v_email, v_full_name, v_username,
    p_bio, p_location, p_avatar_url, p_website, now(), now()
  );

  INSERT INTO public.bot_accounts (id, persona)
  VALUES (v_id, NULLIF(btrim(COALESCE(p_persona, '')), ''))
  ON CONFLICT (id) DO UPDATE SET persona = EXCLUDED.persona;

  RETURN v_id;
END;
$$;

-- -----------------------------------------------------------------------------
-- 4) admin_bot_delete — auth satırını da sil
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_bot_delete(p_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF NOT private.current_user_is_admin() THEN
    RAISE EXCEPTION 'admin_bot_delete: not admin' USING ERRCODE = '42501';
  END IF;

  -- GÜVENLİK: yalnız is_bot=true satır silinebilir. Gerçek bir üyenin bu RPC
  -- üzerinden silinmesi mümkün değildir.
  IF NOT EXISTS (SELECT 1 FROM public.profiles WHERE id = p_id AND is_bot = true) THEN
    RAISE EXCEPTION 'admin_bot_delete: bot bulunamadı';
  END IF;

  -- auth.users silinince profiles (FK CASCADE) ve ona bağlı posts/follows/
  -- bot_accounts/bot_* kayıtları da temizlenir.
  DELETE FROM auth.users WHERE id = p_id;
  DELETE FROM public.profiles WHERE id = p_id AND is_bot = true;
END;
$$;

-- Persona listesi tek yerde dursun ki seed hem RPC'den hem bakım
-- betiklerinden aynı veriyle çalışsın.
CREATE OR REPLACE FUNCTION private.bot_seed_personas()
RETURNS TABLE (username text, full_name text, bio text, location text, persona text)
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT * FROM (VALUES
    ('berivan.aydin',   'Berivan Aydın',   'Cizre''de doğdum, burada büyüdüm. Kahve, kitap ve uzun yürüyüşler. ☕📚', 'Cizre, Şırnak', 'Yerel / günlük hayat'),
    ('serhatdemir',     'Serhat Demir',    'Elektrik teknikeri ⚡ İşten arta kalan zaman sahada geçer.',             'Cizre, Şırnak', 'Esnaf / teknik'),
    ('rojda.kaya',      'Rojda Kaya',      'Anaokulu öğretmeni 🍎 Çocuklarla geçen her gün yeni bir hikâye.',        'Cizre, Şırnak', 'Eğitim'),
    ('mehmetalitunc',   'Mehmet Ali Tunç', 'Çarşıda üçüncü kuşak esnaf. Sabah çayı bizden. ☕',                      'Cizre, Şırnak', 'Esnaf'),
    ('delalyilmaz',     'Delal Yılmaz',    'Hemşire 👩‍⚕️ Boş vaktimde doğa fotoğrafı çekerim. 📷',                  'Cizre, Şırnak', 'Sağlık'),
    ('baranozcan',      'Baran Özcan',     'Yazılımcı 💻 Dicle kıyısında kod yazmak ayrı güzel.',                    'Cizre, Şırnak', 'Teknoloji'),
    ('hediyesahin',     'Hediye Şahin',    'Ev yemekleri ve tatlı tarifleri 🍰 Sipariş için mesaj.',                 'Cizre, Şırnak', 'Yemek'),
    ('cihanaslan',      'Cihan Aslan',     'Motosiklet tutkunu 🏍️ Cizre–Silopi–İdil rotası favorim.',              'Cizre, Şırnak', 'Gezi / hobi'),
    ('nurcanerdem',     'Nurcan Erdem',    'Üniversite öğrencisi 🎓 Psikoloji | kediler ve müzik.',                  'Şırnak',        'Öğrenci'),
    ('ferhatpolat',     'Ferhat Polat',    'Kurye 🛵 Şehri avucumun içi gibi bilirim.',                              'Cizre, Şırnak', 'Kurye / lojistik'),
    ('zilanaktas',      'Zilan Aktaş',     'Tekstil atölyesi 🧵 El emeği, göz nuru.',                                'Cizre, Şırnak', 'Zanaat'),
    ('cemalyildirim',   'Cemal Yıldırım',  'Emekli öğretmen ✏️ Otuz yıl anlattım, hâlâ öğreniyorum.',               'Cizre, Şırnak', 'Eğitim'),
    ('silakorkmaz',     'Sıla Korkmaz',    'Kuaför ✂️ Randevu için mesaj yeterli.',                                 'Cizre, Şırnak', 'Hizmet'),
    ('ercandogan',      'Ercan Doğan',     'Market işletmecisi 🛒 Taze meyve sebze her sabah.',                      'Cizre, Şırnak', 'Esnaf'),
    ('aysenurbayram',   'Ayşe Nur Bayram', 'Diş hekimi 🦷 Gülümsemek bulaşıcıdır.',                                  'Cizre, Şırnak', 'Sağlık'),
    ('ramazancelik',    'Ramazan Çelik',   'Oto tamir 🔧 Yirmi yıllık usta, sanayi sitesi.',                         'Cizre, Şırnak', 'Esnaf / teknik'),
    ('helinarslan',     'Helin Arslan',    'Grafik tasarımcı 🎨 Renklerle konuşurum.',                               'Cizre, Şırnak', 'Tasarım'),
    ('yusufkaratas',    'Yusuf Karataş',   'Antrenör 💪 Disiplin özgürlüktür.',                                      'Cizre, Şırnak', 'Spor'),
    ('gulistanacar',    'Gülistan Acar',   'Çiçekçi 🌷 Her buket bir hikâye.',                                       'Cizre, Şırnak', 'Esnaf'),
    ('kadirsimsek',     'Kadir Şimşek',    'Halı saha işletmecisi ⚽ Akşam maçı var mı?',                            'Cizre, Şırnak', 'Spor / işletme')
  ) AS t(username, full_name, bio, location, persona);
$$;

REVOKE ALL ON FUNCTION private.bot_seed_personas() FROM PUBLIC;

-- -----------------------------------------------------------------------------
-- 5) admin_bot_seed_defaults — auth kaydıyla birlikte
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_bot_seed_defaults()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_row record;
  v_id uuid;
  v_email text;
  v_created integer := 0;
BEGIN
  IF NOT private.current_user_is_admin() THEN
    RAISE EXCEPTION 'admin_bot_seed_defaults: not admin' USING ERRCODE = '42501';
  END IF;

  FOR v_row IN SELECT * FROM private.bot_seed_personas() LOOP
    IF EXISTS (SELECT 1 FROM public.profiles WHERE lower(username) = v_row.username) THEN
      CONTINUE;
    END IF;

    v_email := v_row.username || '@bot.cizreapp.local';
    IF EXISTS (SELECT 1 FROM auth.users WHERE email = v_email) THEN
      CONTINUE;
    END IF;

    v_id := gen_random_uuid();

    PERFORM private.provision_bot_auth_user(
      v_id, v_email, v_row.full_name, v_row.username,
      v_row.bio, v_row.location, NULL, NULL,
      -- Kayıt tarihlerini geçmişe yay: hepsi aynı anda açılmış görünmesin.
      now() - make_interval(days => 20 + floor(random() * 300)::integer),
      now() - make_interval(hours => floor(random() * 72)::integer)
    );

    INSERT INTO public.bot_accounts (id, persona)
    VALUES (v_id, v_row.persona)
    ON CONFLICT (id) DO UPDATE SET persona = EXCLUDED.persona;

    v_created := v_created + 1;
  END LOOP;

  RETURN v_created;
END;
$$;

commit;
