-- =============================================================================
-- 101 Okey Plus — Lobi listesi (oyuncu doluluğu ile)
-- -----------------------------------------------------------------------------
-- Lobide her masanın kaç kişilik olduğunu göstermek için oda başına ayrı
-- sorgu atmak (N+1) yerine tek çağrıda doluluk bilgisi döndürülür.
-- Yalnız BEKLEYEN ve HERKESE AÇIK odalar listelenir.
-- =============================================================================

SET search_path = public, pg_temp;
SET LOCAL lock_timeout = '5s';

DROP FUNCTION IF EXISTS public.okey_list_open_rooms(int);

CREATE FUNCTION public.okey_list_open_rooms(p_limit int DEFAULT 50)
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
    COALESCE(p.full_name, p.username, 'Oyuncu'),
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
    r.created_at
  FROM public.okey_rooms AS r
  LEFT JOIN public.profiles AS p ON p.id = r.created_by
  WHERE (SELECT auth.uid()) IS NOT NULL
    AND r.status = 'waiting'
    AND r.is_private = false
    -- Dolu masalar listelenmez (4 koltuk insan+bot ile dolmuşsa)
    AND (
      SELECT count(*) FROM public.okey_room_players rp
      WHERE rp.room_id = r.id AND (rp.user_id IS NOT NULL OR rp.is_bot)
    ) < 4
  ORDER BY r.created_at DESC
  LIMIT LEAST(GREATEST(COALESCE(p_limit, 50), 1), 100);
$$;

REVOKE ALL ON FUNCTION public.okey_list_open_rooms(int) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.okey_list_open_rooms(int) TO authenticated;

NOTIFY pgrst, 'reload schema';
