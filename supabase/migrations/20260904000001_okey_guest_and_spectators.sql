-- =============================================================================
-- 101 Okey — MİSAFİR GİRİŞİ ve MASA İZLEYİCİLERİ
-- -----------------------------------------------------------------------------
-- Bu göç üç şey yapar:
--
--  1) handle_new_user artık ANONİM (misafir) kullanıcılar için BENZERSİZ bir
--     kullanıcı adı üretir. Zorunlu: profiles.username UNIQUE'tir ve eski
--     fonksiyon meta veri yoksa '' yazıyordu — yani İKİNCİ misafir girişi
--     "duplicate key value violates unique constraint profiles_username_key"
--     ile patlıyor, Supabase bunu "Database error saving new user" diye
--     döndürüyordu. Misafir girişi bu düzeltme olmadan ÇALIŞAMAZ.
--
--  2) okey_room_spectators tablosu: kim hangi masayı izliyor.
--
--  3) İzleyiciler masayı OKUYABİLİR, oynayamaz. Okuma izni, oturanlar için
--     zaten var olan SECURITY DEFINER yardımcılarının izleyici sürümüyle
--     verilir (bkz. 20260830000007 — RLS döngüsü bu yüzden fonksiyona
--     taşınmıştı; aynı gerekçe burada da geçerli, üstelik okey_room_spectators
--     kendi politikasında kendini sorgulayacağı için ZORUNLU).
--
-- DEĞİŞMEYEN KRİTİK KURAL: okey_player_hands'e DOKUNULMAZ. İzleyici hiçbir
-- oyuncunun taşlarını göremez — o tablonun politikası hâlâ tek satırdır
-- (user_id = auth.uid()) ve bu, tüm hile-önleme tasarımının kilit noktasıdır.
-- =============================================================================

SET search_path = public, pg_temp;
SET LOCAL lock_timeout = '5s';

-- -----------------------------------------------------------------------------
-- 1) MİSAFİR PROFİLİ — bir SONRAKİ göçe taşındı
-- -----------------------------------------------------------------------------
--
-- Bu göçün ilk sürümü handle_new_user()'ı burada yeniden yazıyordu ve İKİ
-- HATA yapıyordu:
--   (a) 20260817000035'teki "signup asla bloklanmasın" EXCEPTION sarmalayıcısı
--       düşüyordu;
--   (b) profiles.status artık text değil public.user_status enum'u ('active',
--       'suspended', 'deleted') ve 'online'::text ile yazılamıyor.
--
-- (b) canlıda ZATEN kırıktı: 33 kayıt denemesi signup_trigger_errors'a
-- düşmüştü, ama (a)'daki sarmalayıcı hatayı yuttuğu için kimse görmemişti.
-- Düzeltmenin tamamı 20260904000002'de, tek ve doğru bir sürüm olarak durur.
-- -----------------------------------------------------------------------------
-- 2) İZLEYİCİ TABLOSU
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.okey_room_spectators (
  room_id      uuid NOT NULL REFERENCES public.okey_rooms(id) ON DELETE CASCADE,
  user_id      uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  joined_at    timestamptz NOT NULL DEFAULT NOW(),
  -- Kalp atışı: istemci izlemeye devam ettikçe tazeler. Uygulamayı kapatan
  -- bir izleyici "çıkış" isteği gönderemez; canlı sayı ancak bu damgayla
  -- doğru kalır.
  last_seen_at timestamptz NOT NULL DEFAULT NOW(),
  PRIMARY KEY (room_id, user_id)
);

COMMENT ON TABLE public.okey_room_spectators IS
  'Masayı İZLEYEN kullanıcılar. İzleyici masayı okur, oynayamaz ve HİÇBİR oyuncunun taşlarını göremez (okey_player_hands politikası değişmedi).';

CREATE INDEX IF NOT EXISTS okey_room_spectators_room_idx
  ON public.okey_room_spectators (room_id, last_seen_at DESC);
CREATE INDEX IF NOT EXISTS okey_room_spectators_user_idx
  ON public.okey_room_spectators (user_id);

ALTER TABLE public.okey_room_spectators ENABLE ROW LEVEL SECURITY;

-- -----------------------------------------------------------------------------
-- 3) GÖRÜNTÜLEME YARDIMCILARI (oturan VEYA izleyen)
-- -----------------------------------------------------------------------------
--
-- Neden AYRI fonksiyonlar: is_seated_in_okey_room() yalnızca "oturuyor mu"
-- sorusunu yanıtlar ve YAZMA politikaları da onu kullanır. İzleyiciyi o
-- fonksiyona eklemek, izleyiciye yazma hakkı vermeye giden sessiz bir kapı
-- açardı. Okuma ve yazma soruları ayrı kalır.
CREATE OR REPLACE FUNCTION public.can_view_okey_room(p_room_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT public.is_seated_in_okey_room(p_room_id)
      OR EXISTS (
        SELECT 1 FROM public.okey_room_spectators AS s
        WHERE s.room_id = p_room_id AND s.user_id = (SELECT auth.uid())
      );
$$;
REVOKE ALL ON FUNCTION public.can_view_okey_room(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.can_view_okey_room(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.can_view_okey_match(p_match_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT public.is_seated_in_okey_match(p_match_id)
      OR EXISTS (
        SELECT 1
        FROM public.okey_matches AS m
        JOIN public.okey_room_spectators AS s ON s.room_id = m.room_id
        WHERE m.id = p_match_id AND s.user_id = (SELECT auth.uid())
      );
$$;
REVOKE ALL ON FUNCTION public.can_view_okey_match(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.can_view_okey_match(uuid) TO authenticated;

-- -----------------------------------------------------------------------------
-- 4) OKUMA POLİTİKALARI — izleyici de okuyabilir
-- -----------------------------------------------------------------------------
DROP POLICY IF EXISTS okey_rooms_select ON public.okey_rooms;
CREATE POLICY okey_rooms_select ON public.okey_rooms FOR SELECT TO authenticated
  USING (
    -- Herkese açık masalar listelenebilir (izlenecek masayı bulmanın yolu).
    is_private = false
    OR public.can_view_okey_room(id)
  );

DROP POLICY IF EXISTS okey_room_players_select ON public.okey_room_players;
CREATE POLICY okey_room_players_select ON public.okey_room_players FOR SELECT TO authenticated
  USING (public.can_view_okey_room(room_id));

DROP POLICY IF EXISTS okey_matches_select ON public.okey_matches;
CREATE POLICY okey_matches_select ON public.okey_matches FOR SELECT TO authenticated
  USING (public.can_view_okey_room(room_id));

DROP POLICY IF EXISTS okey_table_melds_select ON public.okey_table_melds;
CREATE POLICY okey_table_melds_select ON public.okey_table_melds FOR SELECT TO authenticated
  USING (public.can_view_okey_match(match_id));

DROP POLICY IF EXISTS okey_moves_select ON public.okey_moves;
CREATE POLICY okey_moves_select ON public.okey_moves FOR SELECT TO authenticated
  USING (public.can_view_okey_match(match_id));

DROP POLICY IF EXISTS okey_scores_history_select ON public.okey_scores_history;
CREATE POLICY okey_scores_history_select ON public.okey_scores_history FOR SELECT TO authenticated
  USING (public.can_view_okey_match(match_id));

-- İzleyici listesi: masayı görebilen herkes (oyuncular VE diğer izleyiciler)
-- okur. Politika kendi tablosunu sorgulayan bir fonksiyona bakar; fonksiyon
-- SECURITY DEFINER olduğu için RLS'i atlar ve döngü oluşmaz.
DROP POLICY IF EXISTS okey_room_spectators_select ON public.okey_room_spectators;
CREATE POLICY okey_room_spectators_select ON public.okey_room_spectators
  FOR SELECT TO authenticated
  USING (public.can_view_okey_room(room_id));

-- Kimse başkasını izleyici yapamaz / listeden atamaz.
DROP POLICY IF EXISTS okey_room_spectators_write ON public.okey_room_spectators;
CREATE POLICY okey_room_spectators_write ON public.okey_room_spectators
  FOR ALL TO authenticated
  USING (user_id = (SELECT auth.uid()))
  WITH CHECK (user_id = (SELECT auth.uid()));

-- -----------------------------------------------------------------------------
-- 5) RPC'LER
-- -----------------------------------------------------------------------------

-- Masayı izlemeye başla / kalp atışı gönder.
--
-- Aynı kullanıcı AYNI ANDA tek masa izler: yeni bir masaya geçince eski
-- kayıt silinir. Aksi halde bir kullanıcı onlarca masanın izleyici listesinde
-- birikir ve o listeler anlamını yitirirdi.
CREATE OR REPLACE FUNCTION public.okey_watch_room(p_room_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_uid uuid := (SELECT auth.uid());
  v_private boolean;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'not_authenticated';
  END IF;

  SELECT r.is_private INTO v_private
  FROM public.okey_rooms AS r WHERE r.id = p_room_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'room_not_found';
  END IF;
  IF v_private THEN
    RAISE EXCEPTION 'room_is_private';
  END IF;

  -- Masada OTURAN biri izleyici olamaz: zaten masada.
  IF public.is_seated_in_okey_room(p_room_id) THEN
    RAISE EXCEPTION 'already_seated';
  END IF;

  DELETE FROM public.okey_room_spectators AS s
  WHERE s.user_id = v_uid AND s.room_id <> p_room_id;

  INSERT INTO public.okey_room_spectators (room_id, user_id)
  VALUES (p_room_id, v_uid)
  ON CONFLICT (room_id, user_id)
  DO UPDATE SET last_seen_at = NOW();

  -- Bu masadaki ölü izleyicileri temizle (uygulamayı kapatanlar "çıktım"
  -- diyemez; sayının doğru kalmasının tek yolu budur).
  DELETE FROM public.okey_room_spectators AS s
  WHERE s.room_id = p_room_id
    AND s.last_seen_at < NOW() - INTERVAL '90 seconds';
END;
$$;
REVOKE ALL ON FUNCTION public.okey_watch_room(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.okey_watch_room(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.okey_unwatch_room(p_room_id uuid)
RETURNS void
LANGUAGE sql
SECURITY DEFINER
SET search_path = ''
AS $$
  DELETE FROM public.okey_room_spectators AS s
  WHERE s.room_id = p_room_id AND s.user_id = (SELECT auth.uid());
$$;
REVOKE ALL ON FUNCTION public.okey_unwatch_room(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.okey_unwatch_room(uuid) TO authenticated;

-- Masadakiler İZLEYENLERİ görür.
DROP FUNCTION IF EXISTS public.okey_room_spectators_list(uuid);
CREATE FUNCTION public.okey_room_spectators_list(p_room_id uuid)
RETURNS TABLE(
  user_id uuid,
  display_name text,
  avatar_url text,
  is_guest boolean,
  joined_at timestamptz
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT
    s.user_id,
    COALESCE(NULLIF(p.full_name, ''), p.username, 'İzleyici'),
    p.avatar_url,
    COALESCE(u.is_anonymous, false),
    s.joined_at
  FROM public.okey_room_spectators AS s
  LEFT JOIN public.profiles AS p ON p.id = s.user_id
  LEFT JOIN auth.users AS u ON u.id = s.user_id
  WHERE s.room_id = p_room_id
    AND s.last_seen_at > NOW() - INTERVAL '90 seconds'
    AND public.can_view_okey_room(p_room_id)
  ORDER BY s.joined_at;
$$;
REVOKE ALL ON FUNCTION public.okey_room_spectators_list(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.okey_room_spectators_list(uuid) TO authenticated;

-- İZLENEBİLİR masalar: oyunu SÜRMEKTE olan, herkese açık masalar.
--
-- okey_list_open_rooms yalnızca 'waiting' ve DOLMAMIŞ masaları döndürür —
-- yani tam olarak izlenemeyecek olanları. İzleyici için ayrı bir listeye
-- ihtiyaç var.
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
        AND s.last_seen_at > NOW() - INTERVAL '90 seconds'),
    r.created_at
  FROM public.okey_rooms AS r
  LEFT JOIN public.profiles AS p ON p.id = r.created_by
  WHERE (SELECT auth.uid()) IS NOT NULL
    AND r.status = 'in_progress'
    AND r.is_private = false
    AND r.current_match_id IS NOT NULL
  ORDER BY r.created_at DESC
  LIMIT LEAST(GREATEST(COALESCE(p_limit, 50), 1), 100);
$$;
REVOKE ALL ON FUNCTION public.okey_list_live_rooms(int) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.okey_list_live_rooms(int) TO authenticated;

-- -----------------------------------------------------------------------------
-- 6) REALTIME — izleyici listesi masadakilerde ANINDA güncellensin
-- -----------------------------------------------------------------------------
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime')
     AND NOT EXISTS (
       SELECT 1 FROM pg_publication_tables
       WHERE pubname = 'supabase_realtime'
         AND schemaname = 'public'
         AND tablename = 'okey_room_spectators'
     )
  THEN
    EXECUTE 'ALTER PUBLICATION supabase_realtime ADD TABLE public.okey_room_spectators';
  END IF;
END;
$$;

NOTIFY pgrst, 'reload schema';
