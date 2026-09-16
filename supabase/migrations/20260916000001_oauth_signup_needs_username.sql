-- =============================================================================
-- Google/Apple kayıtta kullanıcı adı seçim adımı: needs_username + claim_username
-- =============================================================================
-- SORUN
-- -----
-- handle_new_user(), OAuth (Google/Apple) ile kayıt olan kullanıcılar için
-- (raw_user_meta_data->>'username' boş olduğundan) sessizce 'misafir_xxxxxxxx'
-- yer tutucu adı atıyor — 101 Okey misafir girişiyle AYNI kod yolu. İstemci
-- bunu hiç fark etmiyor, kullanıcı doğrudan ana ekrana düşüyor ve kalıcı
-- olarak "misafir_" adıyla kalıyor (username sonradan değiştirilemiyor,
-- register_screen_v2.dart'taki alan yardım metnine bakın).
--
-- ÇÖZÜM
-- -----
-- 1. profiles.needs_username: trigger/ensure_my_profile placeholder ürettiğinde
--    true yazar (yalnız NOT is_anonymous — 101 Okey misafirleri etkilenmez).
-- 2. claim_username(p_username): needs_username=true iken TEK SEFERLİK gerçek
--    kullanıcı adını yazan SECURITY DEFINER RPC. needs_username=false ise
--    reddeder — genel bir "rename" özelliği DEĞİLDİR.
-- 3. Geriye dönük: canlıda hâlâ misafir_ önekiyle dolaşan (is_anonymous=false)
--    mevcut Google/Apple kullanıcıları da needs_username=true'ya çekilir ki
--    istemci onlara da bir dahaki girişte adı sorabilsin.
-- =============================================================================

SET search_path = public, pg_temp;
SET LOCAL lock_timeout = '5s';

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS needs_username boolean NOT NULL DEFAULT false;

COMMENT ON COLUMN public.profiles.needs_username IS
  'true = username otomatik misafir_<id> olarak üretildi (OAuth kaydı username göndermedi); istemci claim_username() ile gerçek adı sorana kadar kalır.';

-- Geriye dönük: is_anonymous=false (gerçek OAuth/e-posta kullanıcısı) olup
-- hâlâ üretilmiş misafir_ önekini taşıyanları işaretle.
UPDATE public.profiles p
SET needs_username = true
FROM auth.users u
WHERE p.id = u.id
  AND u.is_anonymous = false
  AND p.username LIKE 'misafir\_%' ESCAPE '\';

-- -----------------------------------------------------------------------------
-- handle_new_user(): 20260904000002 ile AYNI gövde; tek fark misafir_
-- fallback'inin artık needs_username'i de işaretlemesi.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_username       text;
  v_full_name      text;
  v_email          text;
  v_short          text;
  v_needs_username boolean := false;
BEGIN
  BEGIN
    v_short := substr(replace(NEW.id::text, '-', ''), 1, 8);

    v_email := COALESCE(
      NEW.email,
      'misafir+' || replace(NEW.id::text, '-', '') || '@cizreapp.invalid'
    );

    v_username := LOWER(COALESCE(NEW.raw_user_meta_data->>'username', ''));
    IF v_username = '' THEN
      v_username := 'misafir_' || v_short;
      -- Misafirde (anonim, 101 Okey) bu beklenen davranıştır; gerçek bir
      -- hesapta (Google/Apple) ise kullanıcı henüz ad seçmedi demektir —
      -- istemci claim_username() ile bir dahaki girişte sorar.
      v_needs_username := NOT NEW.is_anonymous;
    END IF;

    v_full_name := COALESCE(NEW.raw_user_meta_data->>'full_name', '');
    IF v_full_name = '' AND NEW.is_anonymous THEN
      v_full_name := 'Misafir ' || UPPER(substr(v_short, 1, 4));
    END IF;

    INSERT INTO public.profiles (
      id,
      email,
      full_name,
      username,
      needs_username,
      role,
      is_admin,
      is_suspicious,
      is_ghost_mode,
      status,
      profile_is_public,
      is_online_enabled,
      show_last_seen,
      allow_messages_from_non_followers,
      delivered_count,
      created_at,
      updated_at
    )
    VALUES (
      NEW.id,
      v_email,
      v_full_name,
      v_username,
      v_needs_username,
      'customer'::public.user_role,
      false,
      false,
      false,
      'active'::public.user_status,
      NOT NEW.is_anonymous,
      true,
      true,
      true,
      0,
      NOW(),
      NOW()
    )
    ON CONFLICT (id) DO NOTHING;
  EXCEPTION WHEN OTHERS THEN
    BEGIN
      INSERT INTO public.signup_trigger_errors (
        user_id, source, error_sqlstate, error_message, error_detail
      ) VALUES (
        NEW.id, 'handle_new_user', SQLSTATE, SQLERRM, NULL
      );
    EXCEPTION WHEN OTHERS THEN
      NULL;
    END;
    RAISE WARNING 'handle_new_user: profile insert failed for %, % (%)',
      NEW.id, SQLERRM, SQLSTATE;
  END;

  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.handle_new_user() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.handle_new_user() FROM anon, authenticated;

COMMENT ON FUNCTION public.handle_new_user() IS
  'AFTER INSERT ON auth.users tetikleyicisi. Profili güvenli varsayılanlarla oluşturur; username boşsa misafir_<id> üretir ve gerçek (is_anonymous=false) kullanıcılarda needs_username=true işaretler; profiles zincirindeki HERHANGİ bir hata yutulup signup_trigger_errors''a loglanır.';

-- -----------------------------------------------------------------------------
-- ensure_my_profile(): trigger başarısız olursa devreye giren istemci
-- yedeği. Aynı needs_username mantığı eklendi; ayrıca iki eski hata
-- düzeltildi: 'online' geçersiz enum değeriydi (user_status yalnız
-- active/suspended/deleted kabul eder) ve boş username handle_new_user'daki
-- gibi misafir_ üretmiyordu (ikinci böyle çağrı UNIQUE ihlaliyle düşerdi).
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.ensure_my_profile()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_uid            uuid := auth.uid();
  v_email          text;
  v_meta           jsonb;
  v_is_anonymous   boolean;
  v_username       text;
  v_needs_username boolean := false;
  v_short          text;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'ensure_my_profile: not authenticated'
      USING ERRCODE = '28000';
  END IF;

  SELECT u.email, u.raw_user_meta_data, u.is_anonymous
    INTO v_email, v_meta, v_is_anonymous
  FROM auth.users u
  WHERE u.id = v_uid;

  v_short := substr(replace(v_uid::text, '-', ''), 1, 8);
  v_email := COALESCE(
    v_email,
    'misafir+' || replace(v_uid::text, '-', '') || '@cizreapp.invalid'
  );

  v_username := LOWER(COALESCE(v_meta->>'username', ''));
  IF v_username = '' THEN
    v_username := 'misafir_' || v_short;
    v_needs_username := NOT COALESCE(v_is_anonymous, false);
  END IF;

  INSERT INTO public.profiles (
    id, email, full_name, username, needs_username, role, is_admin,
    is_suspicious, is_ghost_mode, status, profile_is_public,
    is_online_enabled, show_last_seen, allow_messages_from_non_followers,
    delivered_count, created_at, updated_at
  )
  VALUES (
    v_uid, v_email,
    COALESCE(v_meta->>'full_name', ''),
    v_username,
    v_needs_username,
    'customer'::public.user_role, false, false, false,
    'active'::public.user_status,
    NOT COALESCE(v_is_anonymous, false),
    true, true, true, 0,
    NOW(), NOW()
  )
  ON CONFLICT (id) DO NOTHING;
END;
$$;

REVOKE ALL ON FUNCTION public.ensure_my_profile() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.ensure_my_profile() TO authenticated, service_role;

COMMENT ON FUNCTION public.ensure_my_profile() IS
  'handle_new_user tetikleyicisi başarısız olursa istemcinin çağırdığı idempotent yedek. Aynı misafir_/needs_username/status mantığını handle_new_user ile paylaşır.';

-- -----------------------------------------------------------------------------
-- claim_username(): needs_username=true iken TEK SEFERLİK gerçek kullanıcı
-- adını yazan RPC. Genel bir rename endpoint'i DEĞİLDİR — register_screen_v2
-- zaten "kullanıcı adın sonradan değiştirilemez" diyor; bu RPC yalnızca
-- OAuth kaydının bıraktığı misafir_ yer tutucusunu tamamlar.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.claim_username(p_username text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_uid            uuid := auth.uid();
  v_username       text := LOWER(TRIM(p_username));
  v_needs_username boolean;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'claim_username: not authenticated'
      USING ERRCODE = '28000';
  END IF;

  IF v_username !~ '^[a-z0-9._-]{3,20}$' THEN
    RAISE EXCEPTION 'claim_username: invalid format'
      USING ERRCODE = '22023';
  END IF;

  IF v_username LIKE 'misafir\_%' ESCAPE '\' THEN
    RAISE EXCEPTION 'claim_username: reserved prefix'
      USING ERRCODE = '22023';
  END IF;

  SELECT needs_username INTO v_needs_username
  FROM public.profiles
  WHERE id = v_uid
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'claim_username: profile not found'
      USING ERRCODE = 'P0002';
  END IF;

  IF NOT v_needs_username THEN
    RAISE EXCEPTION 'claim_username: username already set'
      USING ERRCODE = '22023';
  END IF;

  BEGIN
    UPDATE public.profiles
      SET username = v_username, needs_username = false, updated_at = NOW()
    WHERE id = v_uid;
  EXCEPTION WHEN unique_violation THEN
    RAISE EXCEPTION 'claim_username: username taken'
      USING ERRCODE = '23505';
  END;
END;
$$;

REVOKE ALL ON FUNCTION public.claim_username(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.claim_username(text) TO authenticated;

COMMENT ON FUNCTION public.claim_username(text) IS
  'Google/Apple kaydından sonra tek seferlik gerçek kullanıcı adı seçimi. Yalnız profiles.needs_username=true iken çalışır; genel rename RPC''si değildir.';

-- needs_username az önce eklendi; authenticated rolü şu an profiles üzerinde
-- tablo seviyesi SELECT'e sahip (bkz. 20260907110002) ama sütun seviyesi
-- GRANT'ler PENDING_RELEASE_20260908_revoke_profiles_pii.sql.txt uygulanınca
-- tekrar tek yetki kaynağı olacak; o zaman bu sütunun eksik kalmaması için
-- şimdiden ekleniyor.
GRANT SELECT (needs_username) ON public.profiles TO authenticated;

NOTIFY pgrst, 'reload schema';
