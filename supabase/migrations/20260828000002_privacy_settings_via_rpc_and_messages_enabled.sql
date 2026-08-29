-- lib/features/profile/screens/account_settings_screen.dart ("Hesap Ayarları" >
-- "Durum ve Gizlilik") doğrudan `profiles` tablosuna raw .update() çağrısı
-- yapıyordu. 20260803000006 migration'ı `authenticated` rolünden profiles
-- tablosu üzerindeki UPDATE yetkisini tamamen REVOKE etmişti (yalnız
-- SECURITY DEFINER RPC'ler yazabilsin diye) - bu yüzden o ekrandaki HİÇBİR
-- toggle (son görülme, mesajları kabul et, takip etmeyenlerden mesaj,
-- herkese açık profil) hiçbir zaman kaydedilemiyordu (42501 permission
-- denied, sessizce yakalanıp sadece snackbar'da gösteriliyordu).
--
-- update_my_privacy_settings RPC'si zaten show_last_seen /
-- allow_messages_from_non_followers / profile_is_public alanlarını
-- destekliyor; yalnız messages_enabled eksik. Bu migration RPC'yi
-- p_messages_enabled parametresiyle genişletir. Fonksiyon arity'si
-- değiştiği için (6 -> 7 parametre) önce eski imzayı DROP ediyoruz;
-- aksi halde CREATE OR REPLACE aynı isimde ayrı bir overload yaratır ve
-- PostgREST var olan çağrılarda (yalnız bir kısım p_* isimlendirilmiş
-- parametre gönderen) "birden fazla aday fonksiyon" hatası (PGRST203)
-- verir.
begin;

DROP FUNCTION IF EXISTS public.update_my_privacy_settings(
  text, boolean, boolean, boolean, boolean, boolean
);

CREATE FUNCTION public.update_my_privacy_settings(
  p_status text DEFAULT NULL,
  p_show_last_seen boolean DEFAULT NULL,
  p_allow_messages_from_non_followers boolean DEFAULT NULL,
  p_profile_is_public boolean DEFAULT NULL,
  p_is_ghost_mode boolean DEFAULT NULL,
  p_is_online_enabled boolean DEFAULT NULL,
  p_messages_enabled boolean DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_uid uuid := auth.uid();
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'update_my_privacy_settings: not authenticated'
      USING ERRCODE = '28000';
  END IF;

  IF p_status IS NOT NULL AND p_status NOT IN ('online','busy','away','offline') THEN
    RAISE EXCEPTION 'update_my_privacy_settings: invalid status'
      USING ERRCODE = '22023';
  END IF;

  UPDATE public.profiles
    SET
      status = COALESCE(p_status::public.user_status, status),
      show_last_seen = COALESCE(p_show_last_seen, show_last_seen),
      allow_messages_from_non_followers = COALESCE(p_allow_messages_from_non_followers, allow_messages_from_non_followers),
      profile_is_public = COALESCE(p_profile_is_public, profile_is_public),
      is_ghost_mode = COALESCE(p_is_ghost_mode, is_ghost_mode),
      is_online_enabled = COALESCE(p_is_online_enabled, is_online_enabled),
      messages_enabled = COALESCE(p_messages_enabled, messages_enabled),
      -- is_online gerçek durumu: hayalet moddaysa kapat; değilse tercihe bırak.
      is_online = CASE
        WHEN COALESCE(p_is_ghost_mode, is_ghost_mode) = true THEN false
        WHEN p_is_online_enabled IS NOT NULL THEN p_is_online_enabled
        ELSE is_online
      END,
      last_seen = NOW(),
      updated_at = NOW()
  WHERE id = v_uid;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'update_my_privacy_settings: profile not found'
      USING ERRCODE = 'P0002';
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.update_my_privacy_settings(
  text, boolean, boolean, boolean, boolean, boolean, boolean
) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.update_my_privacy_settings(
  text, boolean, boolean, boolean, boolean, boolean, boolean
) TO authenticated, service_role;

commit;
