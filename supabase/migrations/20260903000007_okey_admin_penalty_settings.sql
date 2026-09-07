-- =============================================================================
-- 101 Okey Plus — CEZA AYARLARI ADMİN PANELİNE BAĞLANDI
-- -----------------------------------------------------------------------------
-- RULES.md §8 "İki ceza da admin panelinden ayrı ayrı ayarlanabilir" diyordu
-- ama admin_okey_update_settings bu kolonlara HİÇ dokunmuyordu: dört ceza
-- ayarı da (okey atma, okey elde kalma, işlek taş atma, yandan çekme) yalnızca
-- veritabanından elle değiştirilebiliyordu. Doküman ile gerçek uyuşmuyordu.
--
-- Sınırlar: ceza negatif olamaz (0 = "bu cezayı kapat" demektir ve ilgili
-- fonksiyonlar `IF penalty > 0` ile zaten bunu destekliyor).
-- =============================================================================

SET search_path = public, pg_temp;
SET LOCAL lock_timeout = '5s';

-- Eski 7 parametreli imza düşürülür: yeni imzadaki 4 ek parametrenin
-- varsayılanı olduğu için ikisi yan yana kalırsa çağrılar belirsizleşir.
DROP FUNCTION IF EXISTS public.admin_okey_update_settings(int, int, int, int, int, int, int);

CREATE OR REPLACE FUNCTION public.admin_okey_update_settings(
  p_max_score int,
  p_turn_seconds int,
  p_room_creation_fee int DEFAULT NULL,
  p_commission_percent int DEFAULT NULL,
  p_hourly_gift_points int DEFAULT NULL,
  p_ad_reward_points int DEFAULT NULL,
  p_starting_points int DEFAULT NULL,
  p_okey_discard_penalty int DEFAULT NULL,
  p_okey_in_hand_penalty int DEFAULT NULL,
  p_mistake_discard_penalty int DEFAULT NULL,
  p_side_draw_penalty int DEFAULT NULL
)
RETURNS public.okey_settings
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_row public.okey_settings%ROWTYPE;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'APP:forbidden' USING ERRCODE = '42501';
  END IF;
  IF p_max_score <= 0 OR p_turn_seconds <= 0 THEN
    RAISE EXCEPTION 'APP:invalid_value' USING ERRCODE = '22023';
  END IF;
  IF p_commission_percent IS NOT NULL
     AND (p_commission_percent < 0 OR p_commission_percent > 50) THEN
    RAISE EXCEPTION 'APP:invalid_commission | 0-50 arasi olmali'
      USING ERRCODE = '22023';
  END IF;
  IF p_room_creation_fee IS NOT NULL AND p_room_creation_fee < 0 THEN
    RAISE EXCEPTION 'APP:invalid_value' USING ERRCODE = '22023';
  END IF;
  IF LEAST(
       COALESCE(p_okey_discard_penalty, 0),
       COALESCE(p_okey_in_hand_penalty, 0),
       COALESCE(p_mistake_discard_penalty, 0),
       COALESCE(p_side_draw_penalty, 0)
     ) < 0 THEN
    RAISE EXCEPTION 'APP:invalid_penalty | ceza negatif olamaz'
      USING ERRCODE = '22023';
  END IF;

  UPDATE public.okey_settings
  SET default_max_score = p_max_score,
      default_turn_seconds = p_turn_seconds,
      room_creation_fee = COALESCE(p_room_creation_fee, room_creation_fee),
      commission_percent = COALESCE(p_commission_percent, commission_percent),
      hourly_gift_points = COALESCE(p_hourly_gift_points, hourly_gift_points),
      ad_reward_points = COALESCE(p_ad_reward_points, ad_reward_points),
      starting_points = COALESCE(p_starting_points, starting_points),
      okey_discard_penalty =
        COALESCE(p_okey_discard_penalty, okey_discard_penalty),
      okey_in_hand_penalty =
        COALESCE(p_okey_in_hand_penalty, okey_in_hand_penalty),
      mistake_discard_penalty =
        COALESCE(p_mistake_discard_penalty, mistake_discard_penalty),
      side_draw_penalty = COALESCE(p_side_draw_penalty, side_draw_penalty),
      updated_by = (SELECT auth.uid())
  WHERE id = true
  RETURNING * INTO v_row;

  RETURN v_row;
END;
$$;
REVOKE ALL ON FUNCTION public.admin_okey_update_settings(
  int, int, int, int, int, int, int, int, int, int, int) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_okey_update_settings(
  int, int, int, int, int, int, int, int, int, int, int) TO authenticated;

NOTIFY pgrst, 'reload schema';
