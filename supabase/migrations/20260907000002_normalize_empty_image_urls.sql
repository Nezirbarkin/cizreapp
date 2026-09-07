-- Admin > Loglar > "Son Hatalar" listesindeki
-- "Invalid argument(s): No host specified in URI file:///" kayitlarinin kaynagi.
--
-- profiles.avatar_url'de NULL yerine BOS STRING duruyordu (7 satir). Istemci
-- tarafindaki kontrollerin cogu `avatar_url != null` seklinde; bos string bu
-- kontrolden geciyor ve NetworkImage('') calisma zamaninda
-- Uri.base.resolve('') -> file:/// olarak cozuluyor. Image.network bunu
-- errorBuilder ile yutabilir, ama DecorationImage ve
-- CircleAvatar.backgroundImage yutamaz: hata dogrudan FlutterError.onError'a
-- duser ve merkezi hata kaydina yazilir. Yani her ekran acilisinda o 7
-- kullaniciyi gosteren her liste bir hata uretiyordu.
--
-- Istemci tarafinda ayrica core/utils/image_url.dart -> safeNetworkImage()
-- eklendi; burasi veriyi kaynagi kaynaginda temizler.

BEGIN;

UPDATE public.profiles SET avatar_url = NULL WHERE btrim(avatar_url) = '';
UPDATE public.profiles SET banner_url = NULL WHERE btrim(banner_url) = '';
UPDATE public.profiles SET cover_url  = NULL WHERE btrim(cover_url)  = '';

UPDATE public.notifications SET actor_avatar = NULL WHERE btrim(actor_avatar) = '';
UPDATE public.notifications SET entity_image = NULL WHERE btrim(entity_image) = '';

-- Bos string bir daha geri gelmesin: eski istemci surumleri (ve avatar
-- kaldirma akislari) '' yaziyor. NULL'a normalize ediyoruz ki "gorsel yok"
-- durumunun tek bir temsili olsun.
CREATE OR REPLACE FUNCTION public.normalize_profile_image_urls()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $$
BEGIN
  NEW.avatar_url := NULLIF(btrim(NEW.avatar_url), '');
  NEW.banner_url := NULLIF(btrim(NEW.banner_url), '');
  NEW.cover_url  := NULLIF(btrim(NEW.cover_url),  '');
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_normalize_profile_image_urls ON public.profiles;
CREATE TRIGGER trg_normalize_profile_image_urls
  BEFORE INSERT OR UPDATE ON public.profiles
  FOR EACH ROW
  EXECUTE FUNCTION public.normalize_profile_image_urls();

COMMIT;
