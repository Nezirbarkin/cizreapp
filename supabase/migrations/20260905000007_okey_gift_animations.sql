-- =============================================================================
-- 101 Okey — HAREKETLİ HEDİYE İKONLARI (kullanıcı isteği, 2026-09-05:
-- "hareketli iconlar da koy (gülme, alkışlama vs)")
-- -----------------------------------------------------------------------------
-- ## Hareket bir VERİ alanı, kodda bir switch değil
--
-- İkon zaten katalogda (emoji) ve fiyatı admin belirliyor. "Nasıl oynasın"
-- da aynı yere ait: yeni bir hediye eklemek uygulamayı yeniden yayınlamayı
-- gerektirmemeli. Bu yüzden hareket, ikonun yanında bir ALAN:
--
--   bounce — zıplayarak büyüyüp küçülür (genel amaçlı; çay, kahve, dondurma)
--   shake  — hızlıca sağa sola sallanır (GÜLME, ALKIŞ — kahkahanın ritmi)
--   beat   — kalp atışı gibi iki vuruşta şişip söner (kalp, gül)
--   spin   — bir tam tur döner (havai fişek, yıldız)
--   float  — yavaşça yükselir (çiçek, balon)
--
-- İstemci tanımadığı bir değeri görürse 'bounce'a düşer: admin yarın
-- 'confetti' yazsa uygulama çökmez, sadece o hediye zıplar.
--
-- ## Neden emoji hâlâ yeterli
--
-- "Hareketli ikon" için GIF/Lottie dosyası gerekmiyor: hareket ikonun
-- KENDİSİNDE değil, onu çizen widget'ta. Emoji her platformda hazır ve
-- ölçeklenir; animasyon bir AnimationController'dan ibaret. Dosya tabanlı
-- bir çözüm her yeni hediye için yükleme + depolama + CDN yolu demek olurdu.
-- =============================================================================

SET search_path = public, pg_temp;
SET LOCAL lock_timeout = '10s';

ALTER TABLE public.okey_gift_catalog
  ADD COLUMN IF NOT EXISTS anim text NOT NULL DEFAULT 'bounce';

COMMENT ON COLUMN public.okey_gift_catalog.anim IS
  'İkonun masada nasıl oynayacağı: bounce | shake | beat | spin | float. Tanınmayan değer istemcide bounce olarak çizilir.';

-- Kısıt YOK ve bilerek: yeni bir hareket eklemek, önce bu tabloyu sonra
-- uygulamayı güncellemeyi gerektirmesin. Bilinmeyen değerin bedeli
-- "yanlış animasyon", geçersiz veri değil.

-- Mevcut hediyelerin hareketleri — admin sonradan değiştirebilir.
UPDATE public.okey_gift_catalog SET anim = 'shake' WHERE code = 'alkis';
UPDATE public.okey_gift_catalog SET anim = 'beat'  WHERE code = 'kalp';
UPDATE public.okey_gift_catalog SET anim = 'float' WHERE code = 'cicek';

-- HAREKETLİ TEPKİLER — ucuz, sık gönderilen, masada anlık duygu.
--
-- Fiyatları kasten düşük: bunlar bir ikram değil, bir TEPKİ. 500 puanlık bir
-- kahkaha kimsenin göndermeyeceği bir şeydir; masayı canlandıran şey ise tam
-- olarak sık gönderilmeleri.
INSERT INTO public.okey_gift_catalog (code, name, icon, price, sort_order, anim)
VALUES
  ('gulme',    'Gülme',    '😂', 25, 1, 'shake'),
  ('sasirma',  'Şaşırma',  '😮', 25, 2, 'bounce'),
  ('selam',    'Selam',    '👋', 25, 3, 'shake'),
  ('bravo',    'Bravo',    '🔥', 40, 4, 'beat'),
  ('yildiz',   'Yıldız',   '⭐', 60, 5, 'spin')
ON CONFLICT (code) DO NOTHING;

-- -----------------------------------------------------------------------------
-- Listeleme RPC'leri artık hareketi de döndürür
-- -----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.okey_list_gifts();

CREATE FUNCTION public.okey_list_gifts()
RETURNS TABLE(
  id uuid,
  code text,
  name text,
  icon text,
  price int,
  anim text
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT g.id, g.code, g.name, g.icon, g.price, COALESCE(g.anim, 'bounce')
  FROM public.okey_gift_catalog AS g
  WHERE g.is_active
  ORDER BY g.sort_order, g.price, g.name;
$$;
REVOKE ALL ON FUNCTION public.okey_list_gifts() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.okey_list_gifts() TO authenticated;

DROP FUNCTION IF EXISTS public.okey_admin_list_gifts();

CREATE FUNCTION public.okey_admin_list_gifts()
RETURNS TABLE(
  id uuid,
  code text,
  name text,
  icon text,
  price int,
  sort_order int,
  is_active boolean,
  anim text
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'APP:admin_only' USING ERRCODE = '42501';
  END IF;
  RETURN QUERY
  SELECT g.id, g.code, g.name, g.icon, g.price, g.sort_order, g.is_active,
         COALESCE(g.anim, 'bounce')
  FROM public.okey_gift_catalog AS g
  ORDER BY g.sort_order, g.price, g.name;
END;
$$;
REVOKE ALL ON FUNCTION public.okey_admin_list_gifts() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.okey_admin_list_gifts() TO authenticated;

-- -----------------------------------------------------------------------------
-- Admin kaydı hareketi de yazsın
-- -----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.okey_admin_upsert_gift(uuid, text, text, text, int, int, boolean);
DROP FUNCTION IF EXISTS public.okey_admin_upsert_gift(uuid, text, text, text, int, int, boolean, text);

CREATE FUNCTION public.okey_admin_upsert_gift(
  p_id uuid,
  p_code text,
  p_name text,
  p_icon text,
  p_price int,
  p_sort_order int DEFAULT 0,
  p_is_active boolean DEFAULT true,
  p_anim text DEFAULT 'bounce'
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_id uuid;
  v_code text := lower(trim(COALESCE(p_code, '')));
  v_anim text := lower(trim(COALESCE(NULLIF(trim(p_anim), ''), 'bounce')));
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'APP:admin_only' USING ERRCODE = '42501';
  END IF;
  IF v_code = '' OR trim(COALESCE(p_name, '')) = ''
     OR trim(COALESCE(p_icon, '')) = '' THEN
    RAISE EXCEPTION 'APP:gift_fields_required' USING ERRCODE = '22023';
  END IF;
  IF COALESCE(p_price, -1) < 0 THEN
    RAISE EXCEPTION 'APP:gift_price_invalid' USING ERRCODE = '22023';
  END IF;

  IF p_id IS NULL THEN
    INSERT INTO public.okey_gift_catalog AS g
      (code, name, icon, price, sort_order, is_active, anim)
    VALUES (v_code, trim(p_name), trim(p_icon), p_price,
            COALESCE(p_sort_order, 0), COALESCE(p_is_active, true), v_anim)
    ON CONFLICT (code) DO UPDATE SET
      name = EXCLUDED.name,
      icon = EXCLUDED.icon,
      price = EXCLUDED.price,
      sort_order = EXCLUDED.sort_order,
      is_active = EXCLUDED.is_active,
      anim = EXCLUDED.anim,
      updated_at = now()
    RETURNING g.id INTO v_id;
  ELSE
    UPDATE public.okey_gift_catalog AS g SET
      code = v_code,
      name = trim(p_name),
      icon = trim(p_icon),
      price = p_price,
      sort_order = COALESCE(p_sort_order, 0),
      is_active = COALESCE(p_is_active, true),
      anim = v_anim,
      updated_at = now()
    WHERE g.id = p_id
    RETURNING g.id INTO v_id;
  END IF;

  RETURN v_id;
END;
$$;
REVOKE ALL ON FUNCTION
  public.okey_admin_upsert_gift(uuid, text, text, text, int, int, boolean, text)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION
  public.okey_admin_upsert_gift(uuid, text, text, text, int, int, boolean, text)
  TO authenticated;

-- -----------------------------------------------------------------------------
-- Gönderilen hediye kaydı da hareketi TAŞIR
--
-- Ad ve ikon gibi hareket de KOPYALANIR: admin yarın kahvenin hareketini
-- değiştirse bile dün masada oynanmış an geriye dönük değişmemeli.
-- -----------------------------------------------------------------------------
ALTER TABLE public.okey_gifts_sent
  ADD COLUMN IF NOT EXISTS gift_anim text NOT NULL DEFAULT 'bounce';

DROP FUNCTION IF EXISTS public.okey_send_gift(uuid, smallint, text);

CREATE FUNCTION public.okey_send_gift(
  p_room_id uuid,
  p_seat smallint,
  p_gift_code text
)
RETURNS TABLE(
  gift_id bigint,
  price int,
  balance_after bigint
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_me CONSTANT uuid := (SELECT auth.uid());
  v_gift public.okey_gift_catalog%ROWTYPE;
  v_room public.okey_rooms%ROWTYPE;
  v_player public.okey_room_players%ROWTYPE;
  v_sender_name text;
  v_recipient_name text;
  v_bot_name text;
  v_percent int;
  v_to_recipient bigint;
  v_to_house bigint;
  v_balance bigint;
  v_ref text;
  v_id bigint;
BEGIN
  IF v_me IS NULL THEN
    RAISE EXCEPTION 'APP:auth_required' USING ERRCODE = '42501';
  END IF;

  -- MASAYI GÖREBİLEN GÖNDEREBİLİR: oturan da, izleyen de.
  IF NOT public.can_view_okey_room(p_room_id) THEN
    RAISE EXCEPTION 'APP:not_at_table' USING ERRCODE = '42501';
  END IF;

  SELECT r.* INTO v_room FROM public.okey_rooms AS r WHERE r.id = p_room_id;
  IF v_room.id IS NULL THEN
    RAISE EXCEPTION 'APP:room_not_found' USING ERRCODE = 'P0001';
  END IF;

  SELECT g.* INTO v_gift FROM public.okey_gift_catalog AS g
  WHERE g.code = p_gift_code AND g.is_active;
  IF v_gift.id IS NULL THEN
    RAISE EXCEPTION 'APP:gift_not_found' USING ERRCODE = 'P0001';
  END IF;

  SELECT rp.* INTO v_player FROM public.okey_room_players AS rp
  WHERE rp.room_id = p_room_id AND rp.seat_no = p_seat;
  IF v_player.room_id IS NULL THEN
    RAISE EXCEPTION 'APP:seat_empty' USING ERRCODE = 'P0001';
  END IF;
  IF v_player.user_id = v_me THEN
    RAISE EXCEPTION 'APP:cannot_gift_self' USING ERRCODE = 'P0001';
  END IF;

  -- Görünen adlar KAYDA YAZILIR. Dıştaki COALESCE, SELECT'in HİÇ SATIR
  -- BULAMADIĞI durum içindir (profil satırı henüz oluşmamış misafir).
  SELECT COALESCE(NULLIF(p.full_name, ''), p.username, 'Oyuncu')
  INTO v_sender_name FROM public.profiles AS p WHERE p.id = v_me;
  v_sender_name := COALESCE(v_sender_name, 'Oyuncu');

  IF v_player.user_id IS NOT NULL THEN
    SELECT COALESCE(NULLIF(p.full_name, ''), p.username, 'Oyuncu')
    INTO v_recipient_name FROM public.profiles AS p WHERE p.id = v_player.user_id;
    v_recipient_name := COALESCE(v_recipient_name, 'Oyuncu');
  ELSE
    -- BOT: masadaki adıyla görünür, "bot" olduğu ele verilmez.
    SELECT b.display_name INTO v_bot_name
    FROM public.okey_bot_profiles AS b WHERE b.id = v_player.bot_profile_id;
    v_recipient_name := COALESCE(NULLIF(v_bot_name, ''), 'Oyuncu');
  END IF;

  -- Her hediye AYRI bir olaydır: ref benzersiz üretilir.
  v_ref := p_room_id::text || ':' || gen_random_uuid()::text;

  IF v_gift.price > 0 THEN
    v_balance := public.okey_internal_add_points(
      v_me, -v_gift.price::bigint, 'gift_sent', v_ref);

    SELECT COALESCE(s.gift_recipient_percent, 50) INTO v_percent
    FROM public.okey_settings AS s WHERE s.id = true;

    v_to_recipient := (v_gift.price::bigint * COALESCE(v_percent, 0)) / 100;
    v_to_house := v_gift.price::bigint - v_to_recipient;

    IF v_to_recipient > 0 AND v_player.user_id IS NOT NULL THEN
      PERFORM public.okey_internal_add_points(
        v_player.user_id, v_to_recipient, 'gift_received', v_ref);
    ELSE
      -- Alıcı bot ya da pay sıfır: puanın tamamı kasaya yazılır.
      v_to_house := v_gift.price::bigint;
    END IF;

    IF v_to_house > 0 THEN
      INSERT INTO public.okey_house_revenue (source, amount, room_id, user_id, ref)
      VALUES ('gift', v_to_house, p_room_id, v_me, v_ref)
      ON CONFLICT DO NOTHING;
    END IF;
  ELSE
    SELECT w.points INTO v_balance FROM public.okey_wallets AS w
    WHERE w.user_id = v_me;
  END IF;

  INSERT INTO public.okey_gifts_sent (
    room_id, match_id, sender_id, sender_name,
    recipient_seat, recipient_user_id, recipient_name,
    gift_code, gift_name, gift_icon, gift_anim, price
  ) VALUES (
    p_room_id, v_room.current_match_id, v_me, v_sender_name,
    p_seat, v_player.user_id, v_recipient_name,
    v_gift.code, v_gift.name, v_gift.icon,
    COALESCE(v_gift.anim, 'bounce'), v_gift.price
  )
  RETURNING okey_gifts_sent.id INTO v_id;

  RETURN QUERY SELECT v_id, v_gift.price, COALESCE(v_balance, 0)::bigint;
END;
$$;
REVOKE ALL ON FUNCTION public.okey_send_gift(uuid, smallint, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.okey_send_gift(uuid, smallint, text) TO authenticated;

COMMENT ON FUNCTION public.okey_send_gift(uuid, smallint, text) IS
  'Masadaki bir koltuğa hediye gönderir. Masayı görebilen herkes (oyuncu ve izleyici) çağırabilir; fiyat gönderenin cüzdanından düşer, payı alıcıya geçer, kalanı kasaya yazılır. İkon ve HAREKET kayda kopyalanır.';

DROP FUNCTION IF EXISTS public.okey_recent_gifts(uuid, int);

CREATE FUNCTION public.okey_recent_gifts(p_room_id uuid, p_limit int DEFAULT 20)
RETURNS TABLE(
  id bigint,
  sender_name text,
  recipient_seat smallint,
  recipient_name text,
  gift_name text,
  gift_icon text,
  gift_anim text,
  price int,
  created_at timestamptz
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT g.id, g.sender_name, g.recipient_seat, g.recipient_name,
         g.gift_name, g.gift_icon, COALESCE(g.gift_anim, 'bounce'),
         g.price, g.created_at
  FROM public.okey_gifts_sent AS g
  WHERE g.room_id = p_room_id
    AND public.can_view_okey_room(p_room_id)
  ORDER BY g.id DESC
  LIMIT LEAST(GREATEST(COALESCE(p_limit, 20), 1), 50);
$$;
REVOKE ALL ON FUNCTION public.okey_recent_gifts(uuid, int) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.okey_recent_gifts(uuid, int) TO authenticated;

NOTIFY pgrst, 'reload schema';
