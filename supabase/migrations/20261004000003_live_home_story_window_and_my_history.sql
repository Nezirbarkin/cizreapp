-- =============================================================================
-- Canlı yayın: ana sayfada biten yayın hikâye gibi 24 saat; "Yayınlarım"
-- =============================================================================
--
-- 1) live_home_card(): biten yayın ana sayfa kartında yalnız bittikten sonraki
--    24 saat görünür (hikâye gibi), sonra kaybolur. Canlı yayın varsa kart
--    eskisi gibi onu gösterir. Canlı Yayınlar › Geçmiş sekmesi değişmez
--    (yönetici ayarındaki gün kadar: live_history_days).
-- 2) live_my_history(): yayıncı kendi biten yayınlarını (mağaza ya da kullanıcı
--    yayını; host_user_id = oturumdaki kişi) süre sınırı olmadan görür. Yalnız
--    oturum açmış kişi ve yalnız kendi yayınları; misafire kapalı.
--
-- live_home_card gövdesi 20261004000001'den birebir kopyalanır; yalnız süre
-- satırı değişir (sözleşme testi doğrular).
--
-- Bildirim değişmez: kullanıcı yayınının "yayın başladı" bildirimi zaten yalnız
-- yayıncının takipçilerine gider (20261004000001; mağazasız yayında abone/ürün/
-- müşteri dalları boş kalır). Canlı test bunu da doğrular.

BEGIN;

-- -----------------------------------------------------------------------------
-- 1) Ana sayfa kartı: 20261004000001 tanımı, biten yayın 24 saat
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.live_home_card()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $fn$
DECLARE
  v_uid uuid := auth.uid();
  v_live uuid;
  v_last uuid;
  v_count integer;
BEGIN
  IF NOT private.live_setting_bool('live_home_card_enabled', true) OR NOT private.live_module_enabled() THEN
    RETURN jsonb_build_object('enabled', false);
  END IF;

  SELECT count(*) INTO v_count
    FROM public.live_sessions ls
   WHERE ls.status = 'live'
     AND ls.last_heartbeat_at > now() - interval '2 minutes'
     AND private.live_session_listable(ls.shop_id, ls.host_user_id, v_uid);

  SELECT ls.id INTO v_live
    FROM public.live_sessions ls
   WHERE ls.status = 'live'
     AND ls.last_heartbeat_at > now() - interval '2 minutes'
     AND private.live_session_listable(ls.shop_id, ls.host_user_id, v_uid)
   ORDER BY ls.viewer_count DESC, ls.started_at DESC, ls.id
   LIMIT 1;

  SELECT ls.id INTO v_last
    FROM public.live_sessions ls
   WHERE ls.status = 'ended'
     AND ls.started_at IS NOT NULL
     -- Hikâye gibi: biten yayın ana sayfada 24 saat kalır (sahibi "Yayınlarım"da görür).
     AND ls.ended_at > now() - interval '24 hours'
     AND private.live_session_listable(ls.shop_id, ls.host_user_id, v_uid)
   ORDER BY ls.ended_at DESC, ls.id
   LIMIT 1;

  RETURN jsonb_build_object(
    'enabled', true,
    'live_count', COALESCE(v_count, 0),
    'live', CASE WHEN v_live IS NULL THEN NULL ELSE private.live_session_json(v_live) END,
    'last', CASE WHEN v_last IS NULL THEN NULL ELSE private.live_history_json(v_last) END
  );
END;
$fn$;

-- -----------------------------------------------------------------------------
-- 2) Yayınlarım: oturumdaki kişinin biten yayınları (süre sınırı yok)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.live_my_history(p_limit integer DEFAULT 20, p_offset integer DEFAULT 0)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $fn$
DECLARE
  v_uid uuid := auth.uid();
  v_limit integer := LEAST(GREATEST(COALESCE(p_limit, 20), 1), 50);
  v_offset integer := GREATEST(COALESCE(p_offset, 0), 0);
  v_total integer;
  v_rows jsonb;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Oturum açmanız gerekli' USING ERRCODE = '42501', HINT = 'AUTH_REQUIRED';
  END IF;

  WITH filtered AS (
    SELECT ls.id, ls.ended_at
      FROM public.live_sessions ls
     WHERE ls.host_user_id = v_uid
       AND ls.status = 'ended'
       AND ls.started_at IS NOT NULL
  ),
  page AS (
    -- Sayfa kesimi ile sayfa içi sıra aynı ifade (sayfalar birleşince bozulmaz).
    SELECT f.id, row_number() OVER (ORDER BY f.ended_at DESC, f.id) AS rn
      FROM filtered f
     ORDER BY rn
     LIMIT v_limit OFFSET v_offset
  )
  SELECT (SELECT count(*) FROM filtered),
         COALESCE(jsonb_agg(private.live_history_json(p.id) ORDER BY p.rn), '[]'::jsonb)
    INTO v_total, v_rows
    FROM page p;

  RETURN jsonb_build_object('total', COALESCE(v_total, 0), 'rows', v_rows);
END;
$fn$;

-- -----------------------------------------------------------------------------
-- 3) Yetkiler
-- -----------------------------------------------------------------------------
REVOKE ALL ON FUNCTION public.live_my_history(integer, integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.live_my_history(integer, integer) TO authenticated;

-- Yeniden tanımlananın yetkisi korunur (CREATE OR REPLACE); yine de açıkça:
REVOKE ALL ON FUNCTION public.live_home_card() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.live_home_card() TO anon, authenticated;

COMMIT;

NOTIFY pgrst, 'reload schema';
