-- =============================================================================
-- 101 OKEY — ÇEKİLEN TAŞ, ÇEKME CEVABINDA GELİR (performans, 2026-09-08)
--
-- SORUN: `okey_take_turn_action` yalnızca MAÇ satırını döndürüyordu. Desteden
-- çekilen taş ise oyuncunun EL satırında (okey_player_hands) — yani istemci,
-- çektiği taşı görebilmek için çekme çağrısından SONRA ikinci bir ağ turu
-- atmak zorundaydı. Kullanıcının şikâyeti tam olarak bu iki turdu: "taş çekme
-- veya taş atma ağır işliyor".
--
-- ÇÖZÜM: aynı gövdeyi çalıştıran ama ÇEKİLEN TAŞI da döndüren bir v2.
--   { "match": <okey_matches satırı>, "drawn": <taş | null> }
--
-- v1 OLDUĞU GİBİ KALIR. Dönüş tipi (public.okey_matches) değiştirilseydi,
-- güncellenmemiş istemciler maç satırı yerine bu zarfı alır ve masayı hiç
-- kuramazdı. Yeni istemci v2'yi dener, yoksa (PGRST202) sessizce v1'e düşer.
--
-- GİZLİLİK: 'drawn' yalnızca ÇAĞIRANIN kendi çektiği taştır — fonksiyon
-- sırayı zaten `v_seat = turn_seat` ile doğruluyor, dolayısıyla bir oyuncu
-- başkasının çektiği taşı bu yolla göremez.
-- =============================================================================

SET search_path = public, pg_temp;
SET LOCAL lock_timeout = '10s';

CREATE OR REPLACE FUNCTION public.okey_take_turn_action_v2(
  p_match_id uuid,
  p_action text,
  p_tile jsonb DEFAULT NULL,
  p_expected_turn_token uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_uid CONSTANT uuid := (SELECT auth.uid());
  v_match public.okey_matches%ROWTYPE;
  v_seat smallint;
  v_drawn jsonb := NULL;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'APP:auth_required' USING ERRCODE = '42501';
  END IF;
  IF p_action NOT IN ('draw_deck', 'draw_discard', 'discard') THEN
    RAISE EXCEPTION 'APP:invalid_action' USING ERRCODE = '22023';
  END IF;

  SELECT m.* INTO v_match FROM public.okey_matches AS m
  WHERE m.id = p_match_id FOR UPDATE;
  IF v_match.id IS NULL THEN
    RAISE EXCEPTION 'APP:not_found' USING ERRCODE = 'P0001';
  END IF;
  IF v_match.status <> 'in_progress' THEN
    RAISE EXCEPTION 'APP:match_finished' USING ERRCODE = 'P0001';
  END IF;

  SELECT rp.seat_no INTO v_seat FROM public.okey_room_players AS rp
  WHERE rp.room_id = v_match.room_id AND rp.user_id = v_uid;
  IF v_seat IS NULL THEN
    RAISE EXCEPTION 'APP:not_seated' USING ERRCODE = '42501';
  END IF;
  IF v_seat IS DISTINCT FROM v_match.turn_seat THEN
    RAISE EXCEPTION 'APP:not_your_turn' USING ERRCODE = '42501';
  END IF;
  IF p_expected_turn_token IS NOT NULL
     AND p_expected_turn_token IS DISTINCT FROM v_match.turn_token THEN
    RAISE EXCEPTION 'APP:stale_turn' USING ERRCODE = '40001';
  END IF;

  IF p_action IN ('draw_deck', 'draw_discard') THEN
    IF v_match.turn_phase <> 'draw' THEN
      RAISE EXCEPTION 'APP:wrong_phase' USING ERRCODE = '22023';
    END IF;
    v_drawn := public.okey_internal_draw_for_seat(
      p_match_id, v_seat,
      CASE WHEN p_action = 'draw_deck' THEN 'deck' ELSE 'discard' END
    );
  ELSE
    IF v_match.turn_phase <> 'discard' THEN
      RAISE EXCEPTION 'APP:wrong_phase' USING ERRCODE = '22023';
    END IF;
    IF p_tile IS NULL THEN
      RAISE EXCEPTION 'APP:tile_required' USING ERRCODE = '22023';
    END IF;
    PERFORM public.okey_internal_discard_for_seat(p_match_id, v_seat, p_tile);
  END IF;

  SELECT m.* INTO v_match FROM public.okey_matches AS m WHERE m.id = p_match_id;
  RETURN jsonb_build_object('match', to_jsonb(v_match), 'drawn', v_drawn);
END;
$$;

REVOKE ALL ON FUNCTION public.okey_take_turn_action_v2(uuid, text, jsonb, uuid)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.okey_take_turn_action_v2(uuid, text, jsonb, uuid)
  TO authenticated;

NOTIFY pgrst, 'reload schema';
