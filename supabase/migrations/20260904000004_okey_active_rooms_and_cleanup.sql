-- =============================================================================
-- 101 Okey — TERK EDİLMİŞ MASALAR: tespit, temizlik ve "aktif" tanımı
-- -----------------------------------------------------------------------------
-- ## Bulunan hata
--
-- Canlıda 37 adet `in_progress` masa vardı; en eskisi 5 gün önce açılmış,
-- 33'ünde son hamle GÜNLER öncesine ait. Yani oyuncular uygulamayı kapatıp
-- gitmiş, masalar sonsuza kadar "oynanıyor" olarak kalmış.
--
-- Sebep: `okey_cleanup_stale_rooms` yalnızca iki durumu kapatıyordu —
--   (a) maçı BİTMİŞ ama odası açık kalanlar,
--   (b) 2 saatten eski ve İÇİNDE HİÇ KİMSE OLMAYAN 'waiting' odalar.
-- Terk edilmiş bir `in_progress` masa ikisine de girmez: maçı bitmemiştir ve
-- koltuklarda (artık orada olmayan) oyuncu satırları durur. Hiçbir kural onu
-- kapatmadığı için kalıcı hale gelir.
--
-- Etkisi yalnızca admin paneli değildi: 20260904000001 ile eklenen
-- `okey_list_live_rooms` bu masaları "canlı masalar — izle" listesinde
-- misafirlere gösteriyordu. Yani izlemeye giren biri, günlerdir kimsenin
-- oynamadığı bir masayı seyredecekti.
--
-- ## Çözüm
--
-- "Son etkinlik" tek bir yerde tanımlanır ([okey_room_last_activity]) ve
-- temizlik, admin listesi ve izleme listesi AYNI tanımı kullanır. Üç yerde üç
-- ayrı eşik yazılsaydı, biri değişince diğerleri sessizce ayrışırdı — bu
-- göçün düzelttiği hata sınıfının ta kendisi.
-- =============================================================================

SET search_path = public, pg_temp;
SET LOCAL lock_timeout = '5s';

-- -----------------------------------------------------------------------------
-- 1) Bir masanın SON ETKİNLİĞİ — tek kaynak
-- -----------------------------------------------------------------------------
--
-- Üç sinyalin en yenisi:
--   * odanın kurulma anı (henüz hiçbir şey olmamış yeni masa ölü sayılmasın)
--   * koltuklardaki "buradayım" damgaları (istemci 10 sn'de bir tazeler)
--   * maçtaki son hamle
--
-- Hepsi indekslidir: okey_room_players (room_id, seat_no) birincil anahtar,
-- okey_moves (match_id, created_at DESC) indeksi.
CREATE OR REPLACE FUNCTION public.okey_room_last_activity(p_room_id uuid)
RETURNS timestamptz
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT GREATEST(
    r.created_at,
    COALESCE(
      (SELECT max(rp.last_seen_at) FROM public.okey_room_players AS rp
        WHERE rp.room_id = r.id),
      r.created_at
    ),
    COALESCE(
      (SELECT max(mo.created_at) FROM public.okey_moves AS mo
        WHERE mo.match_id = r.current_match_id),
      r.created_at
    )
  )
  FROM public.okey_rooms AS r
  WHERE r.id = p_room_id;
$$;
REVOKE ALL ON FUNCTION public.okey_room_last_activity(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.okey_room_last_activity(uuid) TO authenticated;

COMMENT ON FUNCTION public.okey_room_last_activity(uuid) IS
  'Masadaki son etkinlik anı: kurulma / "buradayım" damgası / son hamle içinde EN YENİSİ. Temizlik, admin listesi ve izleme listesi bu tek tanımı kullanır.';

-- -----------------------------------------------------------------------------
-- 2) "Ölü masa" eşiği — tek sabit
-- -----------------------------------------------------------------------------
--
-- 30 dakika bilerek CÖMERT: bir tur en fazla ~20 saniye sürer ve süresi dolan
-- oyuncu sunucu tarafından otomatik oynatılır, yani GERÇEKTEN oynanan bir
-- masa dakikalarca sessiz kalamaz. Eşiği kısa tutmak (ör. 5 dk) ağı bir
-- süreliğine kopan bir masayı canlıyken kapatma riski taşırdı.
CREATE OR REPLACE FUNCTION public.okey_idle_room_interval()
RETURNS interval
LANGUAGE sql
IMMUTABLE
SET search_path = ''
AS $$ SELECT interval '30 minutes'; $$;
REVOKE ALL ON FUNCTION public.okey_idle_room_interval() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.okey_idle_room_interval() TO authenticated;

-- -----------------------------------------------------------------------------
-- 3) Temizlik: terk edilmiş masaları da kapat
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.okey_cleanup_stale_rooms()
RETURNS int
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_closed int := 0;
  v_n int;
  v_idle interval := public.okey_idle_room_interval();
BEGIN
  -- (a) Maçı BİTMİŞ ama odası hâlâ açık görünenler
  UPDATE public.okey_rooms AS r
  SET status = 'finished', updated_at = now()
  WHERE r.status = 'in_progress'
    AND r.current_match_id IS NOT NULL
    AND EXISTS (
      SELECT 1 FROM public.okey_matches AS m
      WHERE m.id = r.current_match_id AND m.status = 'finished'
    );
  GET DIAGNOSTICS v_n = ROW_COUNT;
  v_closed := v_closed + COALESCE(v_n, 0);

  -- (b) Uzun süredir bekleyen ve İÇİNDE KİMSE OLMAYAN odalar
  UPDATE public.okey_rooms AS r
  SET status = 'abandoned', updated_at = now()
  WHERE r.status = 'waiting'
    AND r.created_at < now() - interval '2 hours'
    AND NOT EXISTS (
      SELECT 1 FROM public.okey_room_players AS rp
      WHERE rp.room_id = r.id AND (rp.user_id IS NOT NULL OR rp.is_bot)
    );
  GET DIAGNOSTICS v_n = ROW_COUNT;
  v_closed := v_closed + COALESCE(v_n, 0);

  -- (c) YENİ: TERK EDİLMİŞ masalar — oturanlar var ama kimse orada değil.
  --
  -- Asıl sızıntı buydu. Koltuklarda satır olduğu için (b) yakalamıyor, maç
  -- bitmediği için (a) yakalamıyordu; masa sonsuza kadar "oynanıyor" olarak
  -- kalıyordu.
  UPDATE public.okey_rooms AS r
  SET status = 'abandoned', updated_at = now()
  WHERE r.status IN ('waiting', 'in_progress')
    AND public.okey_room_last_activity(r.id) < now() - v_idle;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  v_closed := v_closed + COALESCE(v_n, 0);

  RETURN v_closed;
END;
$$;
REVOKE ALL ON FUNCTION public.okey_cleanup_stale_rooms() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.okey_cleanup_stale_rooms() TO authenticated;

COMMENT ON FUNCTION public.okey_cleanup_stale_rooms() IS
  'Maçı bitmiş, boş bekleyen ve TERK EDİLMİŞ (30 dk etkinlik yok) odaları kapatır. Lobi her açıldığında ve admin panelinden çağrılır.';

-- -----------------------------------------------------------------------------
-- 4) Admin listesi: varsayılan olarak SADECE AKTİF masalar
-- -----------------------------------------------------------------------------
--
-- `last_activity` ve `spectator_count` da döner: admin bir masanın neden
-- listede olduğunu (ya da olmadığını) görebilmeli, tahmin etmemeli.
DROP FUNCTION IF EXISTS public.admin_okey_overview();
DROP FUNCTION IF EXISTS public.admin_okey_overview(boolean);

CREATE FUNCTION public.admin_okey_overview(p_include_idle boolean DEFAULT false)
RETURNS TABLE(
  room_id uuid,
  status text,
  game_mode text,
  team_mode text,
  assist_mode text,
  is_private boolean,
  hand_no int,
  turn_seat smallint,
  seated_count int,
  bot_count int,
  spectator_count int,
  last_activity timestamptz,
  created_at timestamptz
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT
    r.id,
    r.status,
    r.game_mode,
    r.team_mode,
    r.assist_mode,
    r.is_private,
    COALESCE(m.hand_no, 0),
    COALESCE(m.turn_seat, 0::smallint),
    (SELECT count(*)::int FROM public.okey_room_players rp
      WHERE rp.room_id = r.id AND rp.user_id IS NOT NULL),
    (SELECT count(*)::int FROM public.okey_room_players rp
      WHERE rp.room_id = r.id AND rp.is_bot),
    (SELECT count(*)::int FROM public.okey_room_spectators s
      WHERE s.room_id = r.id
        AND s.last_seen_at > now() - interval '90 seconds'),
    public.okey_room_last_activity(r.id),
    r.created_at
  FROM public.okey_rooms AS r
  LEFT JOIN public.okey_matches AS m ON m.id = r.current_match_id
  WHERE public.is_admin()
    AND r.status IN ('waiting', 'in_progress')
    AND (
      COALESCE(p_include_idle, false)
      OR public.okey_room_last_activity(r.id)
         >= now() - public.okey_idle_room_interval()
    )
  ORDER BY public.okey_room_last_activity(r.id) DESC
  LIMIT 100;
$$;
REVOKE ALL ON FUNCTION public.admin_okey_overview(boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_okey_overview(boolean) TO authenticated;

COMMENT ON FUNCTION public.admin_okey_overview(boolean) IS
  'Admin masa listesi. Varsayılan olarak yalnız AKTİF masalar (son 30 dk içinde etkinlik) döner; p_include_idle=true ile terk edilmiş masalar da görünür.';

-- -----------------------------------------------------------------------------
-- 5) İzleme listesi de aynı tanımı kullanır
-- -----------------------------------------------------------------------------
--
-- 20260904000001'deki sürüm yalnızca `status='in_progress'` bakıyordu; yani
-- misafirlere günlerdir kimsenin oynamadığı masaları "canlı" diye
-- gösteriyordu.
DROP FUNCTION IF EXISTS public.okey_list_live_rooms(int);
CREATE FUNCTION public.okey_list_live_rooms(p_limit int DEFAULT 50)
RETURNS TABLE(
  id uuid,
  created_by uuid,
  creator_name text,
  creator_avatar text,
  status text,
  is_private boolean,
  join_code text,
  max_score int,
  turn_seconds int,
  game_mode text,
  team_mode text,
  assist_mode text,
  entry_fee int,
  current_match_id uuid,
  seated_count int,
  bot_count int,
  spectator_count int,
  created_at timestamptz
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT
    r.id,
    r.created_by,
    COALESCE(NULLIF(p.full_name, ''), p.username, 'Oyuncu'),
    p.avatar_url,
    r.status,
    r.is_private,
    r.join_code,
    r.max_score,
    r.turn_seconds,
    r.game_mode,
    r.team_mode,
    r.assist_mode,
    r.entry_fee,
    r.current_match_id,
    (SELECT count(*)::int FROM public.okey_room_players rp
      WHERE rp.room_id = r.id AND rp.user_id IS NOT NULL),
    (SELECT count(*)::int FROM public.okey_room_players rp
      WHERE rp.room_id = r.id AND rp.is_bot),
    (SELECT count(*)::int FROM public.okey_room_spectators s
      WHERE s.room_id = r.id
        AND s.last_seen_at > now() - interval '90 seconds'),
    r.created_at
  FROM public.okey_rooms AS r
  LEFT JOIN public.profiles AS p ON p.id = r.created_by
  WHERE (SELECT auth.uid()) IS NOT NULL
    AND r.status = 'in_progress'
    AND r.is_private = false
    AND r.current_match_id IS NOT NULL
    -- İzlenecek masa GERÇEKTEN oynanıyor olmalı.
    AND public.okey_room_last_activity(r.id)
        >= now() - public.okey_idle_room_interval()
    AND EXISTS (
      SELECT 1 FROM public.okey_matches AS m
      WHERE m.id = r.current_match_id AND m.status = 'in_progress'
    )
  ORDER BY public.okey_room_last_activity(r.id) DESC
  LIMIT LEAST(GREATEST(COALESCE(p_limit, 50), 1), 100);
$$;
REVOKE ALL ON FUNCTION public.okey_list_live_rooms(int) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.okey_list_live_rooms(int) TO authenticated;

-- -----------------------------------------------------------------------------
-- 6) Birikmiş ölü masaları ŞİMDİ kapat
-- -----------------------------------------------------------------------------
SELECT public.okey_cleanup_stale_rooms();

NOTIFY pgrst, 'reload schema';
