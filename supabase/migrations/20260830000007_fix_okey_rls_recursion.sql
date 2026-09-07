-- =============================================================================
-- 101 Okey modülü — Faz A / Düzeltme: RLS sonsuz döngü hatası
-- -----------------------------------------------------------------------------
-- HATA: okey_room_players_select politikası, KENDİ tablosunu (okey_room_players)
-- kendi USING ifadesinde sorguluyordu:
--   USING (EXISTS (SELECT 1 FROM public.okey_room_players AS me WHERE ...))
-- Postgres, bu alt sorguya da AYNI RLS politikasını tekrar uygulamaya
-- çalışıyor -> "infinite recursion detected in policy for relation
-- okey_room_players" (42P17). Bu politika, okey_rooms/okey_matches/
-- okey_table_melds/okey_moves/okey_scores_history politikalarından da
-- (hepsi okey_room_players'a subquery ile bakıyor) transitif olarak
-- tetikleniyor — yani gerçek istemci sorgularının (Flutter'daki doğrudan
-- .from('okey_room_players').select(...) gibi) TAMAMI bu hataya çarpıyordu.
-- SECURITY DEFINER RPC'ler (dolayısıyla önceki e2e testim) bu problemi hiç
-- görmedi çünkü onlar tablo sahibi olarak RLS'i zaten atlıyor.
--
-- ÇÖZÜM: "bu odada oturuyor muyum" kontrolünü SECURITY DEFINER bir
-- fonksiyona taşı. Fonksiyon kendi içinde RLS'i atladığı için (sahiplik)
-- döngü oluşmaz; RLS politikaları artık ham tabloya değil bu fonksiyona
-- bakıyor.
-- =============================================================================

SET search_path = public, pg_temp;
SET LOCAL lock_timeout = '5s';

CREATE OR REPLACE FUNCTION public.is_seated_in_okey_room(p_room_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.okey_room_players AS rp
    WHERE rp.room_id = p_room_id AND rp.user_id = (SELECT auth.uid())
  );
$$;
REVOKE ALL ON FUNCTION public.is_seated_in_okey_room(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.is_seated_in_okey_room(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.is_seated_in_okey_match(p_match_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.okey_room_players AS rp
    JOIN public.okey_matches AS m ON m.room_id = rp.room_id
    WHERE m.id = p_match_id AND rp.user_id = (SELECT auth.uid())
  );
$$;
REVOKE ALL ON FUNCTION public.is_seated_in_okey_match(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.is_seated_in_okey_match(uuid) TO authenticated;

-- okey_rooms
DROP POLICY IF EXISTS okey_rooms_select ON public.okey_rooms;
CREATE POLICY okey_rooms_select ON public.okey_rooms FOR SELECT TO authenticated
  USING (
    (status = 'waiting' AND is_private = false)
    OR public.is_seated_in_okey_room(id)
  );

-- okey_room_players (asıl döngünün kaynağı)
DROP POLICY IF EXISTS okey_room_players_select ON public.okey_room_players;
CREATE POLICY okey_room_players_select ON public.okey_room_players FOR SELECT TO authenticated
  USING (public.is_seated_in_okey_room(room_id));

-- okey_matches
DROP POLICY IF EXISTS okey_matches_select ON public.okey_matches;
CREATE POLICY okey_matches_select ON public.okey_matches FOR SELECT TO authenticated
  USING (public.is_seated_in_okey_room(room_id));

-- okey_table_melds
DROP POLICY IF EXISTS okey_table_melds_select ON public.okey_table_melds;
CREATE POLICY okey_table_melds_select ON public.okey_table_melds FOR SELECT TO authenticated
  USING (public.is_seated_in_okey_match(match_id));

-- okey_moves
DROP POLICY IF EXISTS okey_moves_select ON public.okey_moves;
CREATE POLICY okey_moves_select ON public.okey_moves FOR SELECT TO authenticated
  USING (public.is_seated_in_okey_match(match_id));

-- okey_scores_history
DROP POLICY IF EXISTS okey_scores_history_select ON public.okey_scores_history;
CREATE POLICY okey_scores_history_select ON public.okey_scores_history FOR SELECT TO authenticated
  USING (public.is_seated_in_okey_match(match_id));

NOTIFY pgrst, 'reload schema';
