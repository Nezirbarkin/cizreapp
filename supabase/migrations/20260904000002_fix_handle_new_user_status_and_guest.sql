-- =============================================================================
-- handle_new_user() — İKİ HATA + MİSAFİR DESTEĞİ
-- -----------------------------------------------------------------------------
-- ## Bulunan gerçek hata
--
-- Profil oluşturma tetikleyicisi CANLIDA AYLARDIR SESSİZCE BAŞARISIZ:
--
--     column "status" is of type public.user_status but expression is of
--     type text                                            (SQLSTATE 42804)
--
-- `profiles.status` bir zamanlar text'ti, sonra `public.user_status` enum'una
-- ('active' | 'suspended' | 'deleted') çevrildi; tetikleyici ise hâlâ
-- `'online'::text` yazıyordu. 'online' üstelik enum'da HİÇ YOK.
--
-- Neden kimse fark etmedi: 20260817000035, "signup asla bloklanmasın" diye
-- profil INSERT'ini bir EXCEPTION bloğuna almıştı. Blok görevini yaptı —
-- kayıt akışı çalışmaya devam etti — ama hatayı da gizledi. Hata yalnızca
-- `public.signup_trigger_errors` tablosunda birikti: bu göç yazılırken orada
-- 33 kayıt vardı, en yenisi bir gün öncesine aitti. Yani her yeni
-- kullanıcının profili tetikleyiciyle DEĞİL, istemcinin sonradan çağırdığı
-- `ensure_my_profile()` yedeğiyle oluşuyordu.
--
-- ## Bu göç ne yapıyor
--
--  1. `status` doğru tiple yazılır: 'active'::public.user_status.
--  2. 20260817000035'teki EXCEPTION sarmalayıcısı AYNEN korunur — kayıt
--     akışı hiçbir koşulda bloklanmaz. (Bu göçün ilk taslağı sarmalayıcıyı
--     düşürmüştü; hatanın ortaya çıkması tam da o yüzden oldu.)
--  3. MİSAFİR (anonim) kullanıcılar için BENZERSİZ kullanıcı adı üretilir.
--     Zorunlu: `profiles.username` UNIQUE'tir ve eski gövde meta veri yoksa
--     '' yazıyordu — yani ikinci misafir girişi unique ihlaliyle düşerdi.
--     101 Okey'in misafir girişi bu olmadan çalışamaz.
--  4. MİSAFİR için yer tutucu e-posta üretilir. `profiles.email` NOT NULL ve
--     UNIQUE; anonim kullanıcının ise e-postası hiç yoktur. Bu satır olmadan
--     her misafir girişi 23502 (not-null violation) ile düşer — ki canlıda
--     ilk denemede tam olarak bu oldu.
-- =============================================================================

SET search_path = public, pg_temp;
SET LOCAL lock_timeout = '5s';

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_username  text;
  v_full_name text;
  v_email     text;
  v_short     text;
BEGIN
  BEGIN
    v_short := substr(replace(NEW.id::text, '-', ''), 1, 8);

    -- MİSAFİRİN E-POSTASI YOKTUR ama profiles.email NOT NULL ve UNIQUE'tir.
    -- Yer tutucu, kullanıcı kimliğinden türetilir (benzersizlik garantisi) ve
    -- RFC 2606'nın "asla teslim edilemez" TLD'sini kullanır: bu adrese
    -- yanlışlıkla posta gönderilmesi teknik olarak imkânsızdır.
    v_email := COALESCE(
      NEW.email,
      'misafir+' || replace(NEW.id::text, '-', '') || '@cizreapp.invalid'
    );

    -- Boş kullanıcı adı yalnızca anonim girişte değil, meta verisi eksik HER
    -- kayıtta unique çakışması üretiyordu; koşul bu yüzden "anonim mi" değil
    -- "boş mu". Normal kayıt akışı her zaman bir username gönderdiği için o
    -- yolun davranışı değişmez.
    v_username := LOWER(COALESCE(NEW.raw_user_meta_data->>'username', ''));
    IF v_username = '' THEN
      v_username := 'misafir_' || v_short;
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
      'customer'::public.user_role,
      false,
      false,
      false,
      -- DÜZELTİLEN SATIR. Eskiden 'online'::text idi ve enum'a yazılamıyordu.
      'active'::public.user_status,
      -- Misafir profili keşfet akışında görünmez: geçici bir kimliktir.
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
    -- KORUNAN DAVRANIŞ (20260817000035): profil zincirindeki HERHANGİ bir
    -- hata, auth.users INSERT'ini geri aldırmamalı. Aksi halde kullanıcı
    -- "Database error saving new user" görür ve hiç oluşmaz.
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
  'AFTER INSERT ON auth.users tetikleyicisi. Profili güvenli varsayılanlarla oluşturur; status enum''u doğru tiple yazılır, kullanıcı adı boşsa misafir_<id> üretilir (username UNIQUE), ve profiles zincirindeki HERHANGİ bir hata yutulup signup_trigger_errors''a loglanır ki auth.users INSERT''i asla başarısız olmasın.';

NOTIFY pgrst, 'reload schema';
