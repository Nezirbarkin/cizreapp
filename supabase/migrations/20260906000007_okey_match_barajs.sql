-- =============================================================================
-- 101 Okey — MASADAKİ BARAJLAR (arayüz rozeti için)
-- -----------------------------------------------------------------------------
-- Baraj ödülü 20260906000005/6'da hesaplanıyordu ama masada GÖRÜNMÜYORDU:
-- oyuncunun cezası el sonunda 101 düşüyor, NEDEN düştüğü hiçbir yerde
-- yazmıyordu. Rozet bunu masanın kendisinde söyleyecek; bu RPC de rozetin
-- veri kaynağı.
--
-- ## Neden sunucudan sorulmak zorunda
--
-- Baraj, açılış anındaki puan/çift sayısından türüyor ve o sayılar
-- okey_player_hands'te. O tablo RLS ile korunuyor: bir oyuncu YALNIZCA kendi
-- satırını okuyabilir. Yani istemci rakiplerinin barajını kendi başına
-- hesaplayamaz.
--
-- ## Gizli bilgi DEĞİL
--
-- Dönen tek şey "bu koltuk baraj yaptı mı, hangi türden". İkisi de masada
-- zaten AÇIK duran perlerden sayılabilir (6 çift masada yatıyor; 151 puanlık
-- seri de öyle). Yani RPC, herkesin görebildiği bir şeyi tek sayıya indiriyor
-- — el, taş ya da puan sızdırmıyor.
-- =============================================================================

SET search_path = public, pg_temp;
SET LOCAL lock_timeout = '10s';

DROP FUNCTION IF EXISTS public.okey_match_barajs(uuid);

CREATE FUNCTION public.okey_match_barajs(p_match_id uuid)
RETURNS TABLE(seat_no smallint, kind text)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  s int;
  v_kind text;
BEGIN
  -- Masayı GÖREBİLEN herkes (oturan ya da izleyen) sorabilir; rozet
  -- izleyicide de görünmeli.
  IF NOT public.can_view_okey_match(p_match_id) THEN
    RETURN;
  END IF;

  FOR s IN 0..3 LOOP
    v_kind := public.okey_baraj_kind(p_match_id, s::smallint);
    IF v_kind IS NOT NULL THEN
      seat_no := s::smallint;
      kind := v_kind;
      RETURN NEXT;
    END IF;
  END LOOP;
END;
$$;
REVOKE ALL ON FUNCTION public.okey_match_barajs(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.okey_match_barajs(uuid) TO authenticated;

COMMENT ON FUNCTION public.okey_match_barajs(uuid) IS
  'Masadaki baraj rozetleri: koltuk → ''pairs'' | ''series''. Masayı görebilen herkes okuyabilir; el/taş/puan sızdırmaz.';

NOTIFY pgrst, 'reload schema';
