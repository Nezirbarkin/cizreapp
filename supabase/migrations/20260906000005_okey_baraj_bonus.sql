-- =============================================================================
-- 101 Okey — BARAJ ÖDÜLÜ (kullanıcı isteği, 2026-09-06)
-- -----------------------------------------------------------------------------
-- ## Kural
--
-- Bir oyuncu eli AÇARKEN
--   * 6 veya daha fazla ÇİFT ile açarsa            → ÇİFT BARAJI
--   * 151 veya daha fazla puanlık PER ile açarsa   → PER BARAJI
-- barajı yapmış sayılır ve el sonunda cezasından 101 DÜŞER (skorlar cezadır,
-- düşük olan kazanır — yani -101 bir ödüldür).
--
-- Barajı olan oyuncu eli BİTİRİRSE ödül ikiye katlanır: -101 yerine -202.
-- (Üst üste binmez; -202 onun YERİNE geçer.)
--
-- EŞLİ MODDA: eşlerden biri ÇİFT barajını, diğeri PER barajını yaptıysa
-- takım ayrıca -202 kazanır (her eşe -101). İki eşin de aynı türden baraj
-- yapması bu ek ödülü vermez — kural iki FARKLI barajı ödüllendiriyor.
--
-- ## Neden "yalnızca açılışta"
--
-- Baraj, elin en riskli anını ödüllendiriyor: oyuncu 101'de açıp güvene
-- alabilecekken taş biriktirip 151'i (ya da 6. çifti) bekliyor. Sonradan
-- işlenen taşlar bu riski taşımaz; 151'i el boyunca toplamak neredeyse
-- kaçınılmaz olurdu ve ödül anlamını yitirirdi.
--
-- ## Neden AÇILIŞ PUANI AYRICA KAYDEDİLİYOR
--
-- Açılışta masaya konan puan hiçbir yerde saklanmıyordu: okey_table_melds
-- perleri tutar ama hangilerinin AÇILIŞTA konduğunu bilmez, okey_moves'un
-- 'lay_meld' satırı ise taş taşımaz. El sonunda geriye dönük hesaplamak
-- imkânsız; bu yüzden açılış anında yazılıyor.
--
-- Yazan yer okey_internal_add_open_points: hem seri hem çift açılışı, masaya
-- koyduğu puanı oraya bildiriyor ve bir oyuncunun o eldeki İLK bildirimi
-- tanımı gereği AÇILIŞIDIR (açmadan işleme yapılamaz). Böylece iki ayrı lay
-- fonksiyonuna dokunmadan tek bir yerden yakalanıyor.
-- =============================================================================

SET search_path = public, pg_temp;
SET LOCAL lock_timeout = '10s';

-- -----------------------------------------------------------------------------
-- 1) AYARLAR — eşikler ve ödüller admin tarafından değiştirilebilir olsun
-- -----------------------------------------------------------------------------
ALTER TABLE public.okey_settings
  ADD COLUMN IF NOT EXISTS baraj_min_pairs int NOT NULL DEFAULT 6,
  ADD COLUMN IF NOT EXISTS baraj_min_points int NOT NULL DEFAULT 151,
  ADD COLUMN IF NOT EXISTS baraj_bonus int NOT NULL DEFAULT 101,
  ADD COLUMN IF NOT EXISTS baraj_finish_bonus int NOT NULL DEFAULT 202,
  ADD COLUMN IF NOT EXISTS baraj_team_bonus int NOT NULL DEFAULT 202;

COMMENT ON COLUMN public.okey_settings.baraj_min_pairs IS
  'ÇİFT BARAJI eşiği: açılışta bu kadar (veya daha fazla) çift koyan baraj yapmış sayılır.';
COMMENT ON COLUMN public.okey_settings.baraj_min_points IS
  'PER BARAJI eşiği: açılışta bu kadar (veya daha fazla) puan koyan baraj yapmış sayılır.';
COMMENT ON COLUMN public.okey_settings.baraj_bonus IS
  'Barajı olan oyuncunun cezasından düşülen puan. 0 = baraj ödülü kapalı.';
COMMENT ON COLUMN public.okey_settings.baraj_finish_bonus IS
  'Barajı olan oyuncu eli BİTİRİRSE düşülen puan (baraj_bonus''un YERİNE geçer).';
COMMENT ON COLUMN public.okey_settings.baraj_team_bonus IS
  'Eşli modda eşlerden biri ÇİFT, diğeri PER barajı yaptıysa takıma düşülen toplam puan (eşit bölünür).';

-- -----------------------------------------------------------------------------
-- 2) AÇILIŞ KAYDI — el başına, koltuk başına
-- -----------------------------------------------------------------------------
ALTER TABLE public.okey_player_hands
  ADD COLUMN IF NOT EXISTS opening_points int,
  ADD COLUMN IF NOT EXISTS opening_pairs int;

COMMENT ON COLUMN public.okey_player_hands.opening_points IS
  'Oyuncunun eli AÇARKEN masaya koyduğu toplam puan. Sonradan işlenen taşlar dahil DEĞİLDİR (baraj bunun üstünden hesaplanır).';
COMMENT ON COLUMN public.okey_player_hands.opening_pairs IS
  'Açılışta masaya konan ÇİFT sayısı (gösterge çifti dahil). Çift barajı bunun üstünden hesaplanır.';

-- -----------------------------------------------------------------------------
-- 3) okey_internal_add_open_points — İLK bildirimi açılış olarak yakala
--
-- Gövde 20260905000001'den taşındı; tek fark açılış kaydı.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.okey_internal_add_open_points(
  p_match_id uuid,
  p_seat smallint,
  p_points int
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_hand_no int;
  v_pairs int;
BEGIN
  IF p_points IS NULL OR p_points = 0 THEN
    RETURN;
  END IF;

  UPDATE public.okey_matches
  SET open_points = jsonb_set(
        COALESCE(open_points, '{}'::jsonb),
        ARRAY[p_seat::text],
        to_jsonb(
          COALESCE((open_points ->> p_seat::text)::int, 0) + p_points
        )
      )
  WHERE id = p_match_id;

  -- AÇILIŞ KAYDI — yalnızca bu koltuğun o eldeki İLK bildirimi.
  --
  -- İlk bildirim tanımı gereği açılıştır: açmadan işleme yapılamaz
  -- (okey_add_to_meld ve okey_internal_bot_process_tiles açık olmayan eli
  -- reddeder). Sonraki bildirimler işlemedir ve baraja SAYILMAZ.
  SELECT m.hand_no INTO v_hand_no
  FROM public.okey_matches AS m WHERE m.id = p_match_id;

  -- Çift sayısı, açılışta konan perlerden okunur. Bu satır açılış
  -- perleri INSERT edildikten SONRA çalışır (bkz. lay fonksiyonları), yani
  -- sayım tam olarak açılışta konanları görür.
  SELECT count(*)::int INTO v_pairs
  FROM public.okey_table_melds AS tm
  WHERE tm.match_id = p_match_id
    AND tm.hand_no = v_hand_no
    AND tm.laid_by_seat = p_seat
    AND tm.meld_type IN ('pair', 'gosterge');

  UPDATE public.okey_player_hands
  SET opening_points = p_points,
      opening_pairs = COALESCE(v_pairs, 0)
  WHERE match_id = p_match_id AND seat_no = p_seat
    AND opening_points IS NULL;
END;
$$;

REVOKE ALL ON FUNCTION public.okey_internal_add_open_points(uuid, smallint, int)
  FROM PUBLIC, anon, authenticated;

-- -----------------------------------------------------------------------------
-- 4) okey_baraj_kind — bir koltuk baraj yaptı mı, hangi türden
--
-- Kural TEK YERDE: hem el sonu hesabı hem de (ileride) arayüz bunu okur.
-- İki ayrı yerde yazılsaydı eşikler kaçınılmaz olarak ayrışırdı.
-- -----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.okey_baraj_kind(uuid, smallint);

CREATE FUNCTION public.okey_baraj_kind(p_match_id uuid, p_seat smallint)
RETURNS text
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_hand public.okey_player_hands%ROWTYPE;
  v_min_pairs int;
  v_min_points int;
BEGIN
  SELECT h.* INTO v_hand FROM public.okey_player_hands AS h
  WHERE h.match_id = p_match_id AND h.seat_no = p_seat;
  IF v_hand.match_id IS NULL OR v_hand.opening_points IS NULL THEN
    RETURN NULL; -- hiç açmamış
  END IF;

  SELECT COALESCE(s.baraj_min_pairs, 6), COALESCE(s.baraj_min_points, 151)
  INTO v_min_pairs, v_min_points
  FROM public.okey_settings AS s WHERE s.id = true;

  -- ÇİFT BARAJI önce bakılır: çiftle açan biri hem 6 çift hem 151 puan
  -- koymuş olabilir ve bu tek bir barajdır, iki değil.
  IF COALESCE(v_hand.opened_with_pairs, false)
     AND COALESCE(v_hand.opening_pairs, 0) >= COALESCE(v_min_pairs, 6) THEN
    RETURN 'pairs';
  END IF;

  IF NOT COALESCE(v_hand.opened_with_pairs, false)
     AND COALESCE(v_hand.opening_points, 0) >= COALESCE(v_min_points, 151) THEN
    RETURN 'series';
  END IF;

  RETURN NULL;
END;
$$;
REVOKE ALL ON FUNCTION public.okey_baraj_kind(uuid, smallint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.okey_baraj_kind(uuid, smallint) TO authenticated;

COMMENT ON FUNCTION public.okey_baraj_kind(uuid, smallint) IS
  'Koltuk baraj yaptı mı: ''pairs'' (açılışta 6+ çift), ''series'' (açılışta 151+ puan) ya da NULL.';

-- -----------------------------------------------------------------------------
-- 5) okey_internal_baraj_adjustments — el sonu baraj indirimleri
--
-- Koltuk → düşülecek puan (POZİTİF sayı; çağıran taraf çıkarır).
-- Ayrı bir fonksiyon çünkü finalize zaten uzun ve bu kuralın kendi testi var.
-- -----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.okey_internal_baraj_adjustments(uuid, smallint);

CREATE FUNCTION public.okey_internal_baraj_adjustments(
  p_match_id uuid,
  p_winner_seat smallint
)
RETURNS TABLE(seat_no smallint, bonus int, kind text)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_match public.okey_matches%ROWTYPE;
  v_room public.okey_rooms%ROWTYPE;
  v_bonus int;
  v_finish int;
  v_team int;
  v_kind text[] := ARRAY[NULL, NULL, NULL, NULL]::text[];
  v_out int[] := ARRAY[0, 0, 0, 0];
  s int;
BEGIN
  SELECT m.* INTO v_match FROM public.okey_matches AS m WHERE m.id = p_match_id;
  IF v_match.id IS NULL THEN RETURN; END IF;
  SELECT r.* INTO v_room FROM public.okey_rooms AS r WHERE r.id = v_match.room_id;

  SELECT COALESCE(st.baraj_bonus, 101), COALESCE(st.baraj_finish_bonus, 202),
         COALESCE(st.baraj_team_bonus, 202)
  INTO v_bonus, v_finish, v_team
  FROM public.okey_settings AS st WHERE st.id = true;

  FOR s IN 0..3 LOOP
    v_kind[s + 1] := public.okey_baraj_kind(p_match_id, s::smallint);
    IF v_kind[s + 1] IS NOT NULL THEN
      -- BİTİREN İKİ KAT ALIR — üst üste binmez, ödülün YERİNE geçer.
      v_out[s + 1] := CASE
        WHEN p_winner_seat IS NOT NULL AND s = p_winner_seat THEN v_finish
        ELSE v_bonus
      END;
    END IF;
  END LOOP;

  -- EŞLİ MODDA EK TAKIM ÖDÜLÜ: eşlerden biri ÇİFT, diğeri PER barajı
  -- yaptıysa. Aynı türden iki baraj bu ödülü VERMEZ — kural iki FARKLI
  -- barajın birlikte çıkmasını ödüllendiriyor.
  IF v_room.team_mode = 'esli' AND COALESCE(v_team, 0) > 0 THEN
    -- Takım 1 = 0. + 2. koltuk, Takım 2 = 1. + 3. koltuk.
    IF (v_kind[1] = 'pairs' AND v_kind[3] = 'series')
       OR (v_kind[1] = 'series' AND v_kind[3] = 'pairs') THEN
      v_out[1] := v_out[1] + v_team / 2;
      v_out[3] := v_out[3] + v_team - (v_team / 2);
    END IF;
    IF (v_kind[2] = 'pairs' AND v_kind[4] = 'series')
       OR (v_kind[2] = 'series' AND v_kind[4] = 'pairs') THEN
      v_out[2] := v_out[2] + v_team / 2;
      v_out[4] := v_out[4] + v_team - (v_team / 2);
    END IF;
  END IF;

  FOR s IN 0..3 LOOP
    IF v_out[s + 1] <> 0 THEN
      seat_no := s::smallint;
      bonus := v_out[s + 1];
      kind := v_kind[s + 1];
      RETURN NEXT;
    END IF;
  END LOOP;
END;
$$;
REVOKE ALL ON FUNCTION public.okey_internal_baraj_adjustments(uuid, smallint)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.okey_internal_baraj_adjustments(uuid, smallint)
  TO authenticated;

COMMENT ON FUNCTION public.okey_internal_baraj_adjustments(uuid, smallint) IS
  'El sonu baraj indirimleri: koltuk → cezadan DÜŞÜLECEK puan (pozitif). Bitiren iki kat alır; eşli modda çift+per barajı yapan takıma ek ödül.';

NOTIFY pgrst, 'reload schema';
