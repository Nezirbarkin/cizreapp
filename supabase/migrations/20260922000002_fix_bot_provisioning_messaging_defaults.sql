-- =============================================================================
-- 20260922000002_fix_bot_provisioning_messaging_defaults.sql
-- -----------------------------------------------------------------------------
-- BUG: private.provision_bot_auth_user() (20260908130004) önce auth.users'a
-- INSERT ediyor; bu da handle_new_user AFTER INSERT tetikleyicisini ateşleyip
-- public.profiles satırını GÜVENLİ OLMAYAN varsayılanlarla yaratıyor:
--   messages_enabled sütun varsayılanı true (20260411000001),
--   allow_messages_from_non_followers / is_online_enabled / show_last_seen
--   handle_new_user içinde açıkça true veriliyor (20260916000001).
-- Ardından provision_bot_auth_user'ın kendi INSERT INTO public.profiles'ı bu
-- satırla ID çakışır (ON CONFLICT DO UPDATE) — ama UPDATE SET listesi
-- is_online / is_online_enabled / messages_enabled /
-- allow_messages_from_non_followers / show_last_seen sütunlarını HİÇ
-- içermiyor. Sonuç: fonksiyonun VALUES listesindeki "false" niyeti hiçbir
-- zaman uygulanmıyor; her bot (mevcut ~21 + az önce eklenen 50) canlıda
-- messages_enabled=true, allow_messages_from_non_followers=true,
-- is_online_enabled=true, show_last_seen=true ile duruyordu — yani "botlara
-- mesaj başlatılamasın" niyeti hiç çalışmıyordu.
--
-- ÇÖZÜM: (1) ON CONFLICT DO UPDATE SET listesine eksik 5 sütunu ekle, (2)
-- var olan TÜM bot satırlarını doğru (false) değerlere geri çek.
-- =============================================================================

begin;

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

  -- handle_new_user trigger'ı profili GÜVENSİZ varsayılanlarla (messages_enabled
  -- vb. true) yaratmış olabilir; aşağıdaki ON CONFLICT DO UPDATE bu sütunları
  -- artık AÇIKÇA ezer (bkz. dosya başlığındaki bug açıklaması).
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
    is_online    = EXCLUDED.is_online,
    is_online_enabled = EXCLUDED.is_online_enabled,
    messages_enabled = EXCLUDED.messages_enabled,
    allow_messages_from_non_followers = EXCLUDED.allow_messages_from_non_followers,
    show_last_seen = EXCLUDED.show_last_seen,
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
-- Geriye dönük düzeltme: var olan TÜM bot satırları (eski ~21 + yeni 50)
-- -----------------------------------------------------------------------------
UPDATE public.profiles
SET
  is_online = false,
  is_online_enabled = false,
  messages_enabled = false,
  allow_messages_from_non_followers = false,
  show_last_seen = false,
  updated_at = now()
WHERE is_bot = true
  AND (
    is_online <> false
    OR is_online_enabled <> false
    OR messages_enabled <> false
    OR allow_messages_from_non_followers <> false
    OR show_last_seen <> false
  );

commit;
