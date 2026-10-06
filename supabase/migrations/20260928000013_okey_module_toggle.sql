-- =============================================================================
-- Görev 4.1 — Admin: 101 Okey modülünü uygulama genelinde gizle/göster
-- =============================================================================
-- app_settings.okey_module_enabled (varsayılan AÇIK). Kapalıyken:
--   * istemci tüm girişleri gizler (yan menü, lobi, davet bildirimi, liderler
--     tablosundaki Okey kartları, özelleştir ekranındaki Okey sesleri) — bu
--     yalnız ARAYÜZ kapısıdır;
--   * ASIL kapı burada: yeni oda, koltuğa oturma, izleyici ve davet kayıtları
--     (okey_rooms / okey_room_players / okey_room_spectators / okey_room_invites)
--     reddedilir. Hangi RPC'den gelirse gelsin (hızlı eşleşme, davet kabulü,
--     koltuk seçimi, rövanş, izleme) aynı tetikleyiciye takılır.
--   * Süren maçlar bozulmaz: hamle/el tabloları engellenmez, oyun biter.
--   * Yönetici (test için) ve sistem bağlamı (cron temizliği, bot doldurma)
--     serbesttir.
-- =============================================================================

BEGIN;

INSERT INTO public.app_settings (key, value, description)
VALUES (
  'okey_module_enabled',
  'true'::jsonb,
  '101 Okey modülü uygulamada görünsün ve oynanabilsin mi (admin anahtarı). Kapalıyken yeni oyun açılamaz, süren oyunlar biter.'
)
ON CONFLICT (key) DO NOTHING;

-- Okuma: misafir de (arayüz kapısı için). Değer jsonb true ya da "true" olabilir.
CREATE OR REPLACE FUNCTION public.okey_module_enabled()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $fn$
  SELECT COALESCE(
    (SELECT NULLIF(btrim(s.value #>> '{}'), '')::boolean
       FROM public.app_settings s
      WHERE s.key = 'okey_module_enabled'),
    true
  );
$fn$;

REVOKE ALL ON FUNCTION public.okey_module_enabled() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.okey_module_enabled() TO anon, authenticated;

-- Yeni oyun/katılım kayıtlarını modül kapalıyken reddeder (INVOKER: auth.uid()
-- çağıranın kendisi olmalı).
CREATE OR REPLACE FUNCTION private.okey_module_guard()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $fn$
BEGIN
  IF public.okey_module_enabled() OR auth.uid() IS NULL OR public.auth_is_admin() THEN
    RETURN NEW;
  END IF;
  RAISE EXCEPTION '101 Okey şu anda kapalı'
    USING ERRCODE = 'P0001', HINT = 'OKEY_DISABLED';
END;
$fn$;

REVOKE ALL ON FUNCTION private.okey_module_guard() FROM PUBLIC;

DROP TRIGGER IF EXISTS trg_okey_rooms_module_guard ON public.okey_rooms;
CREATE TRIGGER trg_okey_rooms_module_guard
  BEFORE INSERT ON public.okey_rooms
  FOR EACH ROW EXECUTE FUNCTION private.okey_module_guard();

DROP TRIGGER IF EXISTS trg_okey_room_players_module_guard ON public.okey_room_players;
CREATE TRIGGER trg_okey_room_players_module_guard
  BEFORE INSERT ON public.okey_room_players
  FOR EACH ROW EXECUTE FUNCTION private.okey_module_guard();

DROP TRIGGER IF EXISTS trg_okey_room_spectators_module_guard ON public.okey_room_spectators;
CREATE TRIGGER trg_okey_room_spectators_module_guard
  BEFORE INSERT ON public.okey_room_spectators
  FOR EACH ROW EXECUTE FUNCTION private.okey_module_guard();

DROP TRIGGER IF EXISTS trg_okey_room_invites_module_guard ON public.okey_room_invites;
CREATE TRIGGER trg_okey_room_invites_module_guard
  BEFORE INSERT ON public.okey_room_invites
  FOR EACH ROW EXECUTE FUNCTION private.okey_module_guard();

COMMIT;

NOTIFY pgrst, 'reload schema';
