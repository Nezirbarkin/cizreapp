-- =============================================================================
-- Kayıt (signup) akışını kalıcı olarak koru: auth.users INSERT'i asla
-- profiles/user_balances zincirindeki bir hata yüzünden başarısız olmasın.
--
-- Sorun: public.handle_new_user() (AFTER INSERT ON auth.users, SECURITY
-- DEFINER) profiles'a satır ekliyor; bu INSERT de BEFORE INSERT guard
-- trigger'ını (private.guard_profiles_privileged_columns) ve AFTER INSERT
-- bakiye trigger'ını (create_user_balance_on_signup) tetikliyor. Bu zincirde
-- HERHANGİ bir trigger (bugün veya ileride eklenecek başka bir tetikleyici)
-- beklenmeyen bir hata fırlatırsa, GoTrue tüm auth.users INSERT'ini geri alır
-- ve istemciye yalnız "Database error saving new user" / unexpected_failure
-- döner - kullanıcı hiç oluşmaz, kök neden istemciye hiç sızmaz.
--
-- Kalıcı çözüm: handle_new_user içindeki profil INSERT'i EXCEPTION bloğuyla
-- sarıyoruz. Herhangi bir hata olursa satır profiles'a yazılmaz, hata
-- public.signup_trigger_errors tablosuna loglanır (RAISE WARNING de basılır)
-- ama fonksiyon RETURN NEW ile devam eder → auth.users INSERT'i HER ZAMAN
-- başarılı olur. İstemci tarafı zaten ensure_my_profile() RPC'sini fallback
-- olarak çağırıyor (register_screen_v2.dart), böylece profil ilk girişte
-- güvenli varsayılanlarla tamamlanır.
--
-- create_user_balance_on_signup() de aynı prensiple sertleştirilir: pinned
-- search_path + kendi EXCEPTION bloğu, böylece ensure_my_profile() veya başka
-- bir profiles INSERT yolu üzerinden çağrıldığında da hata yutulur.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1) Tanılama için hafif bir log tablosu. Kayıt akışını asla bloklamaz;
--    yalnız admin/service_role okuyabilir.
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.signup_trigger_errors (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid,
  source text NOT NULL,
  error_sqlstate text,
  error_message text,
  error_detail text,
  created_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.signup_trigger_errors ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE public.signup_trigger_errors FROM PUBLIC, anon, authenticated;
GRANT SELECT ON TABLE public.signup_trigger_errors TO authenticated, service_role;
GRANT INSERT ON TABLE public.signup_trigger_errors TO service_role;

DROP POLICY IF EXISTS signup_trigger_errors_admin_select ON public.signup_trigger_errors;
CREATE POLICY signup_trigger_errors_admin_select
  ON public.signup_trigger_errors
  FOR SELECT
  USING (private.current_user_is_admin());

DROP POLICY IF EXISTS signup_trigger_errors_service_role_all ON public.signup_trigger_errors;
CREATE POLICY signup_trigger_errors_service_role_all
  ON public.signup_trigger_errors
  FOR ALL
  TO service_role
  USING (true)
  WITH CHECK (true);

-- -----------------------------------------------------------------------------
-- 2) handle_new_user: profil INSERT'i asla auth.users INSERT'ini bozmasın.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  BEGIN
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
      NEW.email,
      COALESCE(NEW.raw_user_meta_data->>'full_name', ''),
      LOWER(COALESCE(NEW.raw_user_meta_data->>'username', '')),
      'customer'::public.user_role,
      false,
      false,
      false,
      'online'::text,
      true,
      true,
      true,
      true,
      0,
      NOW(),
      NOW()
    )
    ON CONFLICT (id) DO NOTHING;
  EXCEPTION WHEN OTHERS THEN
    -- Profil (veya zincirindeki bir alt trigger) her ne sebeple olursa olsun
    -- başarısız olsa bile auth.users kaydı oluşmaya devam etmeli. İstemci
    -- ensure_my_profile() RPC'si ile profili ilk girişte tamamlar.
    BEGIN
      INSERT INTO public.signup_trigger_errors (
        user_id, source, error_sqlstate, error_message, error_detail
      ) VALUES (
        NEW.id, 'handle_new_user', SQLSTATE, SQLERRM, NULL
      );
    EXCEPTION WHEN OTHERS THEN
      -- Loglama bile başarısız olursa sessizce yut; signup asla bloklanmaz.
      NULL;
    END;
    RAISE WARNING 'handle_new_user: profile insert failed for %, % (%)', NEW.id, SQLERRM, SQLSTATE;
  END;

  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.handle_new_user() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.handle_new_user() FROM anon, authenticated;

COMMENT ON FUNCTION public.handle_new_user() IS
  'AFTER INSERT ON auth.users tetikleyicisi. Profil satırını güvenli varsayılanlarla oluşturur; profiles zincirindeki HERHANGİ bir hata yutulur ve signup_trigger_errors''a loglanır ki auth.users INSERT''i asla başarısız olmasın (kalıcı signup fix).';

-- -----------------------------------------------------------------------------
-- 3) create_user_balance_on_signup: pinned search_path + kendi EXCEPTION
--    bloğu. handle_new_user'ın INSERT'i içinden VEYA ensure_my_profile() gibi
--    başka bir profiles INSERT yolundan tetiklendiğinde de signup'ı bozmasın.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.create_user_balance_on_signup()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  BEGIN
    INSERT INTO public.user_balances (user_id, balance, locked_balance)
    VALUES (NEW.id, 0.00, 0.00)
    ON CONFLICT (user_id) DO NOTHING;
  EXCEPTION WHEN OTHERS THEN
    BEGIN
      INSERT INTO public.signup_trigger_errors (
        user_id, source, error_sqlstate, error_message, error_detail
      ) VALUES (
        NEW.id, 'create_user_balance_on_signup', SQLSTATE, SQLERRM, NULL
      );
    EXCEPTION WHEN OTHERS THEN
      NULL;
    END;
    RAISE WARNING 'create_user_balance_on_signup: balance insert failed for %, % (%)', NEW.id, SQLERRM, SQLSTATE;
  END;

  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.create_user_balance_on_signup() IS
  'AFTER INSERT ON profiles tetikleyicisi. Bakiye satırı oluşturmayı dener; hata durumunda signup/profil oluşturma akışını bozmadan sessizce loglar (kalıcı signup fix).';

NOTIFY pgrst, 'reload schema';
