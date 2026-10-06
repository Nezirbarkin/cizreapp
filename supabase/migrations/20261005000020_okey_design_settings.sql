-- =============================================================================
-- 101 Okey — Tasarım Sistemi v6: yönetici tasarım seçimi (2026-10-05)
-- =============================================================================
-- Kullanıcı isteği: "okey 101 UI/UX anasayfa, oyun içi yeniden tümünü tasarla
-- ve admin yeni UX/UI seçeneği de ekle, 5'ten fazla tasarım ekle".
--
-- Tasarım paketleri istemcide tanımlıdır (lib/okey/theme/okey_design.dart:
-- salon, zumrut, bordo, neon, cini, saray, ege). Sunucu yalnızca HANGİSİNİN
-- aktif olduğunu tutar:
--
--   okey_design              aktif tasarım anahtarı            (varsayılan "salon")
--   okey_lobby_layout        lobi düzeni: auto|salon|arena|kompakt (varsayılan "auto")
--   okey_design_user_choice  oyuncu kendi cihazında seçebilir mi (varsayılan true)
--
-- Okuma tek RPC: public.okey_design_config() → jsonb. Misafir de okur (Okey'e
-- misafir girişi var). Yazma app_settings'in MEVCUT yönetici politikalarıyla
-- yapılır (okey_module_enabled ile aynı yol); bu yüzden yeni politika yok.
--
-- Görünüm bir güvenlik sınırı değildir: bilinmeyen/bozuk değer okuyucuda
-- varsayılana düşer, istemci de bilinmeyen anahtarı varsayılan tasarıma çevirir.
-- =============================================================================

BEGIN;

INSERT INTO public.app_settings (key, value, description)
VALUES
  (
    'okey_design',
    '"salon"'::jsonb,
    '101 Okey aktif tasarım paketi: salon, zumrut, bordo, neon, cini, saray, ege (Admin › 101 Okey › Tasarım).'
  ),
  (
    'okey_lobby_layout',
    '"auto"'::jsonb,
    '101 Okey lobi düzeni: auto (tasarıma göre), salon, arena, kompakt.'
  ),
  (
    'okey_design_user_choice',
    '"true"'::jsonb,
    '101 Okey: oyuncu kendi cihazında başka tasarım/masa/ıstaka seçebilir mi.'
  )
ON CONFLICT (key) DO NOTHING;

-- Ham metin okuyucu: kenar tırnak/boşlukları soyar (istemci düz 'true' yazar;
-- yanlışlıkla '"true"' yazılırsa da çalışsın — bkz. leaderboard_setting).
CREATE OR REPLACE FUNCTION public.okey_design_setting(p_key text)
RETURNS text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $fn$
  SELECT NULLIF(btrim(s.value #>> '{}', E'" \t\r\n'), '')
  FROM public.app_settings s
  WHERE s.key = p_key;
$fn$;

REVOKE ALL ON FUNCTION public.okey_design_setting(text) FROM PUBLIC;

-- Herkese açık okuma. Biçim dışı değerler varsayılana düşer: anahtar yalnızca
-- küçük harf/rakam/alt çizgi (en çok 32), düzen bilinen dört değerden biri,
-- seçim bayrağı yalnızca açıkça "false" ise kapalı.
CREATE OR REPLACE FUNCTION public.okey_design_config()
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $fn$
  WITH raw AS (
    SELECT
      lower(public.okey_design_setting('okey_design'))             AS design,
      lower(public.okey_design_setting('okey_lobby_layout'))       AS layout,
      lower(public.okey_design_setting('okey_design_user_choice')) AS choice
  )
  SELECT jsonb_build_object(
    'design',
      CASE WHEN design ~ '^[a-z0-9_]{1,32}$' THEN design ELSE 'salon' END,
    'layout',
      CASE WHEN layout IN ('auto', 'salon', 'arena', 'kompakt') THEN layout ELSE 'auto' END,
    'user_choice',
      COALESCE(choice NOT IN ('false', 'f', '0', 'no', 'off'), true)
  )
  FROM raw;
$fn$;

REVOKE ALL ON FUNCTION public.okey_design_config() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.okey_design_config() TO anon, authenticated;

COMMIT;

NOTIFY pgrst, 'reload schema';
