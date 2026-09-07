-- =============================================================================
-- 101 Okey modülü — Faz A / Adım 1: tablolar + RLS
-- -----------------------------------------------------------------------------
-- cizreapp'e tamamen yeni bir alan olarak eklenen 4 kişilik gerçek zamanlı
-- 101 Okey oyunu için temel şema. Bu dosya SADECE tabloları, index'leri ve
-- RLS politikalarını içerir — hiçbir RPC yok (onlar ayrı bir migration'da,
-- kural motoru/puanlama netleştikten sonra gelecek).
--
-- Tasarım ilkesi: RLS satır bazlı filtreler, kolon bazlı değil. Bu yüzden
-- "gizli" (sadece sahibi görür), "paylaşılan" (o maçtaki 4 koltuk görür) ve
-- "herkese açık" (lobi) bilgi ayrı tablolarda tutuluyor:
--   - okey_player_hands: SADECE sahibi okuyabilir (auth.uid() = user_id).
--     Rakiplerin kaç taşı kaldığı ayrı bir SECURITY DEFINER fonksiyonla
--     (ileride eklenecek get_match_seat_tile_counts) paylaşılacak, gerçek
--     taşlar asla başka bir koltuğa sızmayacak.
--   - okey_rooms/okey_room_players/okey_matches/okey_table_melds/okey_moves/
--     okey_scores_history: o maçın/odanın 4 koltuğundan biri olan herkes görür.
--   - okey_settings: herkese açık salt-okunur yapılandırma (max_score,
--     sıra süre sınırı vb.) — admin panelinden (Faz F) RPC ile güncellenecek.
--
-- Tüm tablolarda INSERT/UPDATE/DELETE `authenticated`'tan REVOKE edilir.
-- Her mutasyon (taş dağıtma, çekme/atma, per/grup açma, kazanma iddiası)
-- yalnızca sonraki migration'da eklenecek SECURITY DEFINER RPC'ler üzerinden
-- yapılabilecek — bu, kurye/sipariş akışlarında zaten kullanılan
-- "client asla ham tabloya yazamaz, sadece doğrulanmış RPC'ler yazar"
-- ilkesinin Okey'e uygulanmış hali.
-- =============================================================================

SET search_path = public, pg_temp;
SET LOCAL lock_timeout = '5s';

-- -----------------------------------------------------------------------------
-- 1) okey_rooms — lobi/oda konteynerı
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.okey_rooms (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  created_by uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  status text NOT NULL DEFAULT 'waiting'
    CHECK (status IN ('waiting', 'in_progress', 'finished', 'abandoned')),
  is_private boolean NOT NULL DEFAULT false,
  join_code text UNIQUE,
  max_score int NOT NULL DEFAULT 101 CHECK (max_score > 0),
  turn_seconds int NOT NULL DEFAULT 20 CHECK (turn_seconds > 0),
  current_match_id uuid,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.okey_rooms IS
  '101 Okey lobi/oda kaydı. current_match_id, aktif elin okey_matches satırına işaret eder (FK aşağıda, okey_matches oluşturulduktan sonra eklenir).';

CREATE INDEX IF NOT EXISTS idx_okey_rooms_status_created_at
  ON public.okey_rooms (status, created_at DESC)
  WHERE status = 'waiting' AND is_private = false;

-- -----------------------------------------------------------------------------
-- 2) okey_room_players — koltuklar (0-3)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.okey_room_players (
  room_id uuid NOT NULL REFERENCES public.okey_rooms(id) ON DELETE CASCADE,
  seat_no smallint NOT NULL CHECK (seat_no BETWEEN 0 AND 3),
  user_id uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  is_ready boolean NOT NULL DEFAULT false,
  joined_at timestamptz,
  left_at timestamptz,
  PRIMARY KEY (room_id, seat_no),
  UNIQUE (room_id, user_id)
);

COMMENT ON TABLE public.okey_room_players IS
  'Oda başına 4 koltuk satırı (seat_no 0-3). user_id NULL = boş koltuk. Bir kullanıcı aynı odada iki koltuk tutamaz (UNIQUE room_id,user_id).';

CREATE INDEX IF NOT EXISTS idx_okey_room_players_user
  ON public.okey_room_players (user_id)
  WHERE user_id IS NOT NULL;

-- -----------------------------------------------------------------------------
-- 3) okey_matches — bir elin/maçın paylaşılan durumu
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.okey_matches (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  room_id uuid NOT NULL REFERENCES public.okey_rooms(id) ON DELETE CASCADE,
  status text NOT NULL DEFAULT 'in_progress'
    CHECK (status IN ('in_progress', 'finished')),
  hand_no int NOT NULL DEFAULT 1 CHECK (hand_no > 0),
  dealer_seat smallint NOT NULL CHECK (dealer_seat BETWEEN 0 AND 3),
  turn_seat smallint NOT NULL CHECK (turn_seat BETWEEN 0 AND 3),
  turn_phase text NOT NULL DEFAULT 'draw' CHECK (turn_phase IN ('draw', 'discard')),
  turn_token uuid NOT NULL DEFAULT gen_random_uuid(),
  turn_deadline timestamptz,
  indicator_tile jsonb NOT NULL,
  okey_tile jsonb NOT NULL,
  deck_remaining int NOT NULL CHECK (deck_remaining >= 0),
  discard_piles jsonb NOT NULL DEFAULT '{}'::jsonb,
  scores jsonb NOT NULL DEFAULT '{}'::jsonb,
  winner_seat smallint CHECK (winner_seat IS NULL OR winner_seat BETWEEN 0 AND 3),
  win_type text CHECK (win_type IS NULL OR win_type IN ('normal', 'elden', 'cift', 'cifte_okey')),
  created_at timestamptz NOT NULL DEFAULT now(),
  finished_at timestamptz
);

COMMENT ON TABLE public.okey_matches IS
  'Bir elin (hand) tüm oyuncuların gördüğü ortak durumu: sıra, gösterge, atma yığınları, skorlar. Gerçek taşlar burada YOK (bkz. okey_player_hands).';

CREATE INDEX IF NOT EXISTS idx_okey_matches_room
  ON public.okey_matches (room_id, created_at DESC);

ALTER TABLE public.okey_rooms
  ADD CONSTRAINT okey_rooms_current_match_fk
  FOREIGN KEY (current_match_id) REFERENCES public.okey_matches(id) ON DELETE SET NULL;

-- -----------------------------------------------------------------------------
-- 4) okey_player_hands — GİZLİ: oyuncunun eli (RLS'in kilit noktası)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.okey_player_hands (
  match_id uuid NOT NULL REFERENCES public.okey_matches(id) ON DELETE CASCADE,
  seat_no smallint NOT NULL CHECK (seat_no BETWEEN 0 AND 3),
  user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  tiles jsonb NOT NULL,
  tile_count int GENERATED ALWAYS AS (jsonb_array_length(tiles)) STORED,
  is_opening_done boolean NOT NULL DEFAULT false,
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (match_id, seat_no)
);

COMMENT ON TABLE public.okey_player_hands IS
  'Oyuncunun gerçek taşları. RLS: SADECE user_id = auth.uid() okuyabilir. Başka hiçbir politika başka bir koltuğun taşlarını okumaya izin vermemeli — bu tablo tüm hile-önleme tasarımının kilit noktasıdır.';

CREATE INDEX IF NOT EXISTS idx_okey_player_hands_user
  ON public.okey_player_hands (user_id);

-- -----------------------------------------------------------------------------
-- 5) okey_table_melds — PAYLAŞILAN: masaya açık per/gruplar
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.okey_table_melds (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  match_id uuid NOT NULL REFERENCES public.okey_matches(id) ON DELETE CASCADE,
  hand_no int NOT NULL CHECK (hand_no > 0),
  laid_by_seat smallint NOT NULL CHECK (laid_by_seat BETWEEN 0 AND 3),
  meld_type text NOT NULL CHECK (meld_type IN ('run', 'set')),
  tiles jsonb NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.okey_table_melds IS
  'Masaya açık (face-up) per (run) veya grup (set). Eli açılmış herhangi bir oyuncu buraya taş ekleyebilir (Okey 101 Plus paritesi) — tiles alanı güncellenir.';

CREATE INDEX IF NOT EXISTS idx_okey_table_melds_match
  ON public.okey_table_melds (match_id, hand_no);

-- -----------------------------------------------------------------------------
-- 6) okey_moves — hamle günlüğü (realtime + reconnect + animasyon kaynağı)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.okey_moves (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  match_id uuid NOT NULL REFERENCES public.okey_matches(id) ON DELETE CASCADE,
  hand_no int NOT NULL CHECK (hand_no > 0),
  seat_no smallint NOT NULL CHECK (seat_no BETWEEN 0 AND 3),
  action text NOT NULL CHECK (action IN (
    'draw_deck', 'draw_discard', 'discard',
    'lay_meld', 'add_to_meld', 'declare_win', 'timeout_auto_discard'
  )),
  tile jsonb,
  created_at timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.okey_moves IS
  'Her hamlenin kalıcı kaydı. Postgres Changes ile dinlenir; reconnect sonrası state DB''den tam okunur, bu tablo yalnızca animasyon/geçmiş amaçlıdır.';

CREATE INDEX IF NOT EXISTS idx_okey_moves_match_created
  ON public.okey_moves (match_id, created_at DESC);

-- -----------------------------------------------------------------------------
-- 7) okey_scores_history — el bazlı finalize puanlar
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.okey_scores_history (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  match_id uuid NOT NULL REFERENCES public.okey_matches(id) ON DELETE CASCADE,
  hand_no int NOT NULL CHECK (hand_no > 0),
  seat_no smallint NOT NULL CHECK (seat_no BETWEEN 0 AND 3),
  user_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  points int NOT NULL,
  reason text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.okey_scores_history IS
  'El bazlı finalize puan kayıtları (kazanan/kaybeden, elden/çift/çifte okey çarpanları uygulanmış). Maç sonu özeti için kullanılır.';

CREATE INDEX IF NOT EXISTS idx_okey_scores_history_match
  ON public.okey_scores_history (match_id, hand_no);

-- -----------------------------------------------------------------------------
-- 8) okey_settings — herkese açık salt-okunur yapılandırma (tek satır)
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.okey_settings (
  id boolean PRIMARY KEY DEFAULT true CHECK (id = true), -- tek satır garantisi
  default_max_score int NOT NULL DEFAULT 101 CHECK (default_max_score > 0),
  default_turn_seconds int NOT NULL DEFAULT 20 CHECK (default_turn_seconds > 0),
  updated_at timestamptz NOT NULL DEFAULT now(),
  updated_by uuid REFERENCES public.profiles(id) ON DELETE SET NULL
);

COMMENT ON TABLE public.okey_settings IS
  'Tek satırlık genel Okey yapılandırması (varsayılan max_score, sıra süre sınırı). Faz F''de admin panelinden RPC ile güncellenecek; şimdilik yalnızca varsayılan değeri taşır.';

INSERT INTO public.okey_settings (id) VALUES (true) ON CONFLICT (id) DO NOTHING;

DROP TRIGGER IF EXISTS trg_okey_settings_updated_at ON public.okey_settings;
CREATE TRIGGER trg_okey_settings_updated_at
  BEFORE UPDATE ON public.okey_settings
  FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

-- =============================================================================
-- RLS
-- =============================================================================
ALTER TABLE public.okey_rooms ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.okey_room_players ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.okey_matches ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.okey_player_hands ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.okey_table_melds ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.okey_moves ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.okey_scores_history ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.okey_settings ENABLE ROW LEVEL SECURITY;

-- okey_rooms: bekleyen genel odalar herkese, kendi odası her zaman sahibine görünür
DROP POLICY IF EXISTS okey_rooms_select ON public.okey_rooms;
CREATE POLICY okey_rooms_select ON public.okey_rooms FOR SELECT TO authenticated
  USING (
    (status = 'waiting' AND is_private = false)
    OR EXISTS (
      SELECT 1 FROM public.okey_room_players AS rp
      WHERE rp.room_id = okey_rooms.id AND rp.user_id = (SELECT auth.uid())
    )
  );
REVOKE INSERT, UPDATE, DELETE ON public.okey_rooms FROM authenticated;

-- okey_room_players: yalnız aynı odada oturan biri görebilir (private oda koltuk sızıntısı önlenir)
DROP POLICY IF EXISTS okey_room_players_select ON public.okey_room_players;
CREATE POLICY okey_room_players_select ON public.okey_room_players FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.okey_room_players AS me
      WHERE me.room_id = okey_room_players.room_id AND me.user_id = (SELECT auth.uid())
    )
  );
REVOKE INSERT, UPDATE, DELETE ON public.okey_room_players FROM authenticated;

-- okey_matches: yalnız o odanın 4 koltuğundan biri
DROP POLICY IF EXISTS okey_matches_select ON public.okey_matches;
CREATE POLICY okey_matches_select ON public.okey_matches FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.okey_room_players AS rp
      WHERE rp.room_id = okey_matches.room_id AND rp.user_id = (SELECT auth.uid())
    )
  );
REVOKE INSERT, UPDATE, DELETE ON public.okey_matches FROM authenticated;

-- okey_player_hands: SADECE sahibi — tüm tasarımın kilit noktası
DROP POLICY IF EXISTS okey_player_hands_select_own ON public.okey_player_hands;
CREATE POLICY okey_player_hands_select_own ON public.okey_player_hands FOR SELECT TO authenticated
  USING (user_id = (SELECT auth.uid()));
REVOKE INSERT, UPDATE, DELETE ON public.okey_player_hands FROM authenticated;

-- okey_table_melds: yalnız o maçın 4 koltuğundan biri
DROP POLICY IF EXISTS okey_table_melds_select ON public.okey_table_melds;
CREATE POLICY okey_table_melds_select ON public.okey_table_melds FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.okey_room_players AS rp
      JOIN public.okey_matches AS m ON m.room_id = rp.room_id
      WHERE m.id = okey_table_melds.match_id AND rp.user_id = (SELECT auth.uid())
    )
  );
REVOKE INSERT, UPDATE, DELETE ON public.okey_table_melds FROM authenticated;

-- okey_moves: yalnız o maçın 4 koltuğundan biri
DROP POLICY IF EXISTS okey_moves_select ON public.okey_moves;
CREATE POLICY okey_moves_select ON public.okey_moves FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.okey_room_players AS rp
      JOIN public.okey_matches AS m ON m.room_id = rp.room_id
      WHERE m.id = okey_moves.match_id AND rp.user_id = (SELECT auth.uid())
    )
  );
REVOKE INSERT, UPDATE, DELETE ON public.okey_moves FROM authenticated;

-- okey_scores_history: yalnız o maçın 4 koltuğundan biri
DROP POLICY IF EXISTS okey_scores_history_select ON public.okey_scores_history;
CREATE POLICY okey_scores_history_select ON public.okey_scores_history FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.okey_room_players AS rp
      JOIN public.okey_matches AS m ON m.room_id = rp.room_id
      WHERE m.id = okey_scores_history.match_id AND rp.user_id = (SELECT auth.uid())
    )
  );
REVOKE INSERT, UPDATE, DELETE ON public.okey_scores_history FROM authenticated;

-- okey_settings: herkese açık salt-okunur (hassas veri değil)
DROP POLICY IF EXISTS okey_settings_select ON public.okey_settings;
CREATE POLICY okey_settings_select ON public.okey_settings FOR SELECT TO authenticated
  USING (true);
REVOKE INSERT, UPDATE, DELETE ON public.okey_settings FROM authenticated;

NOTIFY pgrst, 'reload schema';
