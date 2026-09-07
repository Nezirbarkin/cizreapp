-- =============================================================================
-- 101 Okey Plus — BOT ATMA STRATEJİSİ DÜZELTİLDİ
-- -----------------------------------------------------------------------------
-- ÖLÇÜLEN SORUN: Botlar hiç açamıyordu. 120 turluk bir simülasyonda botların
-- elindeki en yüksek per puanı 79'da kalıyor, 101 barajını hiç geçemiyordu —
-- yani "botlar sadece taş atıyor" şikâyeti doğruydu ve sebebi ATMA KURALIYDI.
--
-- ESKİ KURAL: "perde olmayan EN YÜKSEK taşı at."
-- Bu tam tersiydi. 101 puana ulaşmanın hammaddesi yüksek taşlardır; bot
-- 12'leri, 13'leri atıp elinde düşük taşlarla kalıyordu. Üstelik "henüz per
-- olmamış ama olmaya yakın" taşlar (aynı sayının ikinci rengi, aynı renkte
-- komşu sayı) hiç korunmuyordu.
--
-- YENİ KURAL: her taşa bir POTANSİYEL puanı verilir —
--   * tamamlanmış bir perin parçası          → asla atılmaz
--   * aynı sayıdan başka renk var (grup adayı) → yüksek potansiyel
--   * aynı renkte komşu sayı var (per adayı)   → yüksek potansiyel
--   * hiçbiri                                  → potansiyelsiz
-- Potansiyeli EN DÜŞÜK taş atılır; eşitlikte sayısı EN YÜKSEK olan atılır
-- (el sonu cezası taş değerlerinden hesaplandığı için).
-- Okey hiçbir koşulda atılmaz.
-- =============================================================================

SET search_path = public, pg_temp;
SET LOCAL lock_timeout = '10s';

CREATE OR REPLACE FUNCTION public.okey_internal_bot_pick_discard(
  p_tiles jsonb,
  p_okey_tile jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SET search_path = ''
AS $$
DECLARE
  v_groups jsonb;
  v_used jsonb := '[]'::jsonb;
  v_tile jsonb;
  v_other jsonb;
  v_num int;
  v_color text;
  v_potential int;
  v_worst_potential int := NULL;
  v_worst_num int := -1;
  v_candidate jsonb := NULL;
  v_in_meld boolean;
  i int;
  j int;
BEGIN
  IF p_tiles IS NULL OR jsonb_array_length(p_tiles) = 0 THEN
    RETURN NULL;
  END IF;

  -- Tamamlanmış perlerdeki taşlar dokunulmazdır
  v_groups := public.okey_internal_find_melds(p_tiles, p_okey_tile);
  FOR i IN 0 .. GREATEST(jsonb_array_length(COALESCE(v_groups, '[]'::jsonb)) - 1, -1) LOOP
    v_used := v_used || (v_groups -> i);
  END LOOP;

  FOR i IN 0 .. jsonb_array_length(p_tiles) - 1 LOOP
    v_tile := p_tiles -> i;

    -- OKEY ASLA ATILMAZ (hem değerli hem de atmak cezalı)
    CONTINUE WHEN public.okey_tile_is_joker(v_tile, p_okey_tile);

    -- Tamamlanmış perin parçasıysa atma
    v_in_meld := false;
    FOR j IN 0 .. GREATEST(jsonb_array_length(v_used) - 1, -1) LOOP
      IF v_used -> j = v_tile THEN
        v_in_meld := true;
        EXIT;
      END IF;
    END LOOP;
    CONTINUE WHEN v_in_meld;

    v_num := COALESCE((v_tile->>'number')::int, 0);
    v_color := v_tile->>'color';
    v_potential := 0;

    -- Elde bu taşla EŞLEŞEBİLECEK başka taş var mı?
    FOR j IN 0 .. jsonb_array_length(p_tiles) - 1 LOOP
      CONTINUE WHEN i = j;
      v_other := p_tiles -> j;
      CONTINUE WHEN public.okey_tile_is_joker(v_other, p_okey_tile);

      -- Grup adayı: aynı sayı, FARKLI renk
      IF (v_other->>'number')::int = v_num
         AND v_other->>'color' IS DISTINCT FROM v_color THEN
        v_potential := v_potential + v_num;
      END IF;

      -- Per adayı: aynı renk, komşu sayı
      IF v_other->>'color' = v_color
         AND abs((v_other->>'number')::int - v_num) = 1 THEN
        v_potential := v_potential + v_num;
      END IF;
    END LOOP;

    -- En düşük potansiyelli taşı seç; eşitlikte sayısı en yüksek olanı
    IF v_worst_potential IS NULL
       OR v_potential < v_worst_potential
       OR (v_potential = v_worst_potential AND v_num > v_worst_num) THEN
      v_worst_potential := v_potential;
      v_worst_num := v_num;
      v_candidate := v_tile;
    END IF;
  END LOOP;

  IF v_candidate IS NOT NULL THEN
    RETURN v_candidate;
  END IF;

  -- Her taş bir perde: okey olmayan en yüksek taşı at
  v_worst_num := -1;
  FOR i IN 0 .. jsonb_array_length(p_tiles) - 1 LOOP
    v_tile := p_tiles -> i;
    CONTINUE WHEN public.okey_tile_is_joker(v_tile, p_okey_tile);
    v_num := COALESCE((v_tile->>'number')::int, 0);
    IF v_num > v_worst_num THEN
      v_worst_num := v_num;
      v_candidate := v_tile;
    END IF;
  END LOOP;

  -- Son çare: elde okeyden başka taş yok
  RETURN COALESCE(v_candidate, p_tiles -> 0);
END;
$$;
REVOKE ALL ON FUNCTION public.okey_internal_bot_pick_discard(jsonb, jsonb)
  FROM PUBLIC, anon, authenticated;

NOTIFY pgrst, 'reload schema';
