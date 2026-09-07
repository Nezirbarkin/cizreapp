-- =============================================================================
-- 101 Okey — MASAYA HEDİYE GÖNDERME (kullanıcı isteği, 2026-09-05:
-- "seyirci ya da normal oyuncu, oyunculara hediye göndersin; bu hediyeler
--  puanla olsun; admin 101 okey yönetiminde düzenleyebilsin —
--  kahve, çay, dondurma ikonlar vs")
-- -----------------------------------------------------------------------------
-- ## İki tablo, tek RPC
--
--   okey_gift_catalog  — NE gönderilebilir (ad, ikon, fiyat, sıra, aktif mi).
--                        Tamamen ADMİN tarafından düzenlenir; kod içinde
--                        gömülü bir hediye listesi YOKTUR, çünkü fiyat da
--                        çeşit de zamanla değişecek bir ekonomi kararıdır.
--   okey_gifts_sent    — KİM KİME NE gönderdi (masa günlüğü + animasyon
--                        tetikleyicisi).
--
-- ## Neden ikon bir EMOJİ
--
-- Görsel dosyası olsaydı her yeni hediye bir yükleme, bir depolama kovası ve
-- bir CDN yolu demek olurdu; admin panelinden "dondurma ekle" demek beş
-- dakikalık bir iş olmaktan çıkardı. Emoji her platformda hazır, ölçeklenir
-- ve tek bir metin alanında düzenlenir.
--
-- ## Puanın akışı
--
-- Gönderen hediyenin fiyatını öder. Bu puanın ne kadarının ALICIYA geçtiği
-- admin ayarıdır (`okey_settings.gift_recipient_percent`, varsayılan %50):
--
--   * %0   → hediye tamamen jest; puan dolaşımdan çıkar (kasa geliri)
--   * %100 → hediye saf bir puan transferi olur
--
-- Varsayılan ortada: alıcı için gerçekten bir şey ifade etsin ama hediye
-- iki hesap arasında sınırsız puan taşımanın yolu OLMASIN. Alıcıya geçmeyen
-- kısım okey_house_revenue'ya 'gift' olarak yazılır — dolaşımdan çıkan her
-- puan raporlarda görünür.
--
-- ## BOT KOLTUĞUNA DA HEDİYE GİDER
--
-- Botlar masada gerçek oyuncular gibi görünür (2026-09 kullanıcı kuralı).
-- Bot koltuğu hediye kabul etmeseydi, "hediye gönderilemedi" hatası botun
-- bot olduğunu ele veren en net sinyal olurdu. Bu yüzden hediye kabul
-- edilir; alıcı payı sahibi olmadığı için kasaya yazılır.
-- =============================================================================

SET search_path = public, pg_temp;
SET LOCAL lock_timeout = '10s';

-- -----------------------------------------------------------------------------
-- 1) AYAR: alıcıya geçen pay
-- -----------------------------------------------------------------------------
ALTER TABLE public.okey_settings
  ADD COLUMN IF NOT EXISTS gift_recipient_percent int NOT NULL DEFAULT 50;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'okey_settings_gift_percent_check'
  ) THEN
    ALTER TABLE public.okey_settings
      ADD CONSTRAINT okey_settings_gift_percent_check
      CHECK (gift_recipient_percent BETWEEN 0 AND 100);
  END IF;
END;
$$;

COMMENT ON COLUMN public.okey_settings.gift_recipient_percent IS
  'Gönderilen hediyenin ALICIYA geçen yüzdesi. Kalanı kasa geliridir (okey_house_revenue.source = ''gift'').';

-- Deftere ve kasa kayıtlarına yeni sebepler
ALTER TABLE public.okey_point_transactions
  DROP CONSTRAINT IF EXISTS okey_point_transactions_reason_check;
ALTER TABLE public.okey_point_transactions
  ADD CONSTRAINT okey_point_transactions_reason_check
  CHECK (reason IN (
    'signup_bonus', 'hourly_gift', 'ad_reward',
    'entry_fee', 'room_fee', 'match_win', 'stake_refund',
    'gift_sent', 'gift_received',
    'admin_grant', 'refund'
  ));

ALTER TABLE public.okey_house_revenue
  DROP CONSTRAINT IF EXISTS okey_house_revenue_source_check;
ALTER TABLE public.okey_house_revenue
  ADD CONSTRAINT okey_house_revenue_source_check
  CHECK (source IN ('room_fee', 'commission', 'unclaimed_pot', 'gift'));

-- -----------------------------------------------------------------------------
-- 2) HEDİYE KATALOĞU
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.okey_gift_catalog (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  code       text NOT NULL UNIQUE,
  name       text NOT NULL,
  icon       text NOT NULL,
  price      int  NOT NULL CHECK (price >= 0),
  sort_order int  NOT NULL DEFAULT 0,
  is_active  boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.okey_gift_catalog IS
  'Masada gönderilebilen hediyeler (kahve, çay, dondurma...). Admin panelinden düzenlenir; fiyat okey puanıdır.';

ALTER TABLE public.okey_gift_catalog ENABLE ROW LEVEL SECURITY;

-- OKUMA herkese (giriş yapmış): hediye listesi gizli bir bilgi değil,
-- masadaki menünün ta kendisidir.
DROP POLICY IF EXISTS okey_gift_catalog_select ON public.okey_gift_catalog;
CREATE POLICY okey_gift_catalog_select ON public.okey_gift_catalog
  FOR SELECT TO authenticated USING (true);

-- YAZMA yalnızca admin.
DROP POLICY IF EXISTS okey_gift_catalog_write ON public.okey_gift_catalog;
CREATE POLICY okey_gift_catalog_write ON public.okey_gift_catalog
  FOR ALL TO authenticated
  USING (public.is_admin()) WITH CHECK (public.is_admin());

-- BAŞLANGIÇ LİSTESİ — admin silebilir/değiştirebilir. ON CONFLICT DO NOTHING:
-- göç yeniden çalıştırılırsa adminin düzenlediği fiyatlar geri gelmesin.
INSERT INTO public.okey_gift_catalog (code, name, icon, price, sort_order)
VALUES
  ('cay',       'Çay',        '🍵', 50,   10),
  ('kahve',     'Kahve',      '☕', 100,  20),
  ('dondurma',  'Dondurma',   '🍦', 150,  30),
  ('cikolata',  'Çikolata',   '🍫', 200,  40),
  ('cicek',     'Çiçek',      '💐', 300,  50),
  ('baklava',   'Baklava',    '🍮', 400,  60),
  ('alkis',     'Alkış',      '👏', 25,   70),
  ('kalp',      'Kalp',       '❤️', 500,  80)
ON CONFLICT (code) DO NOTHING;

-- -----------------------------------------------------------------------------
-- 3) GÖNDERİLEN HEDİYELER
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.okey_gifts_sent (
  id                bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  room_id           uuid NOT NULL REFERENCES public.okey_rooms(id) ON DELETE CASCADE,
  match_id          uuid,
  sender_id         uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  sender_name       text NOT NULL,
  recipient_seat    smallint NOT NULL CHECK (recipient_seat BETWEEN 0 AND 3),
  recipient_user_id uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  recipient_name    text NOT NULL,
  -- İkon ve ad KOPYALANIR: admin hediyeyi sonradan yeniden adlandırsa ya da
  -- silse bile masada oynanmış bir an geriye dönük değişmemeli.
  gift_code text NOT NULL,
  gift_name text NOT NULL,
  gift_icon text NOT NULL,
  price     int  NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.okey_gifts_sent IS
  'Masada gönderilen hediyelerin günlüğü. Realtime ile masadaki herkese (oyuncu ve izleyici) animasyon olarak yansır.';

CREATE INDEX IF NOT EXISTS okey_gifts_sent_room_idx
  ON public.okey_gifts_sent (room_id, id DESC);

ALTER TABLE public.okey_gifts_sent ENABLE ROW LEVEL SECURITY;

-- Masayı GÖREBİLEN herkes (oturan veya izleyen) hediyeleri de görür.
DROP POLICY IF EXISTS okey_gifts_sent_select ON public.okey_gifts_sent;
CREATE POLICY okey_gifts_sent_select ON public.okey_gifts_sent
  FOR SELECT TO authenticated
  USING (public.can_view_okey_room(room_id) OR public.is_admin());

-- YAZMA yalnızca RPC üzerinden (SECURITY DEFINER): fiyat, bakiye ve yetki
-- kontrolü tek bir yerde kalsın.
REVOKE INSERT, UPDATE, DELETE ON public.okey_gifts_sent FROM authenticated;

-- -----------------------------------------------------------------------------
-- 4) LİSTELEME — masadaki hediye menüsü
-- -----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.okey_list_gifts();

CREATE FUNCTION public.okey_list_gifts()
RETURNS TABLE(
  id uuid,
  code text,
  name text,
  icon text,
  price int
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT g.id, g.code, g.name, g.icon, g.price
  FROM public.okey_gift_catalog AS g
  WHERE g.is_active
  ORDER BY g.sort_order, g.price, g.name;
$$;
REVOKE ALL ON FUNCTION public.okey_list_gifts() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.okey_list_gifts() TO authenticated;

-- -----------------------------------------------------------------------------
-- 5) GÖNDERME
-- -----------------------------------------------------------------------------
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

  -- MASAYI GÖREBİLEN GÖNDEREBİLİR: oturan da, izleyen de
  -- (kullanıcı isteği: "seyirci ya da normal oyuncu").
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

  -- Görünen adlar KAYDA YAZILIR (bkz. tablo yorumu).
  --
  -- Dıştaki COALESCE, SELECT'in HİÇ SATIR BULAMADIĞI durum içindir (misafir
  -- girişli bir izleyicinin profil satırı henüz oluşmamışsa v_sender_name
  -- NULL kalır ve NOT NULL kolonu patlar) — içteki COALESCE ise satır var
  -- ama adı boşsa devreye girer.
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

  -- ÖDEME. Bakiye yetmezse okey_internal_add_points 'APP:insufficient_points'
  -- ile düşer ve HİÇBİR satır yazılmaz (tek işlem).
  -- Her hediye AYRI bir olaydır: ref benzersiz üretilir. (Idempotans
  -- anahtarı sabit olsaydı aynı oyuncunun aynı masada gönderdiği ikinci
  -- kahve sessizce yok sayılır, puanı da düşülmezdi.)
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
    gift_code, gift_name, gift_icon, price
  ) VALUES (
    p_room_id, v_room.current_match_id, v_me, v_sender_name,
    p_seat, v_player.user_id, v_recipient_name,
    v_gift.code, v_gift.name, v_gift.icon, v_gift.price
  )
  RETURNING okey_gifts_sent.id INTO v_id;

  RETURN QUERY SELECT v_id, v_gift.price, COALESCE(v_balance, 0)::bigint;
END;
$$;
REVOKE ALL ON FUNCTION public.okey_send_gift(uuid, smallint, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.okey_send_gift(uuid, smallint, text) TO authenticated;

COMMENT ON FUNCTION public.okey_send_gift(uuid, smallint, text) IS
  'Masadaki bir koltuğa hediye gönderir. Masayı görebilen herkes (oyuncu ve izleyici) çağırabilir; fiyat gönderenin cüzdanından düşer, payı alıcıya geçer, kalanı kasaya yazılır.';

-- -----------------------------------------------------------------------------
-- 6) SON HEDİYELER — masaya girenin geçmişi kaçırmaması için
-- -----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.okey_recent_gifts(uuid, int);

CREATE FUNCTION public.okey_recent_gifts(p_room_id uuid, p_limit int DEFAULT 20)
RETURNS TABLE(
  id bigint,
  sender_name text,
  recipient_seat smallint,
  recipient_name text,
  gift_name text,
  gift_icon text,
  price int,
  created_at timestamptz
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT g.id, g.sender_name, g.recipient_seat, g.recipient_name,
         g.gift_name, g.gift_icon, g.price, g.created_at
  FROM public.okey_gifts_sent AS g
  WHERE g.room_id = p_room_id
    AND public.can_view_okey_room(p_room_id)
  ORDER BY g.id DESC
  LIMIT LEAST(GREATEST(COALESCE(p_limit, 20), 1), 50);
$$;
REVOKE ALL ON FUNCTION public.okey_recent_gifts(uuid, int) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.okey_recent_gifts(uuid, int) TO authenticated;

-- -----------------------------------------------------------------------------
-- 7) ADMİN — kataloğu düzenle
-- -----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.okey_admin_upsert_gift(uuid, text, text, text, int, int, boolean);

CREATE FUNCTION public.okey_admin_upsert_gift(
  p_id uuid,
  p_code text,
  p_name text,
  p_icon text,
  p_price int,
  p_sort_order int DEFAULT 0,
  p_is_active boolean DEFAULT true
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_id uuid;
  v_code text := lower(trim(COALESCE(p_code, '')));
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
      (code, name, icon, price, sort_order, is_active)
    VALUES (v_code, trim(p_name), trim(p_icon), p_price,
            COALESCE(p_sort_order, 0), COALESCE(p_is_active, true))
    ON CONFLICT (code) DO UPDATE SET
      name = EXCLUDED.name,
      icon = EXCLUDED.icon,
      price = EXCLUDED.price,
      sort_order = EXCLUDED.sort_order,
      is_active = EXCLUDED.is_active,
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
      updated_at = now()
    WHERE g.id = p_id
    RETURNING g.id INTO v_id;
  END IF;

  RETURN v_id;
END;
$$;
REVOKE ALL ON FUNCTION
  public.okey_admin_upsert_gift(uuid, text, text, text, int, int, boolean)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION
  public.okey_admin_upsert_gift(uuid, text, text, text, int, int, boolean)
  TO authenticated;

DROP FUNCTION IF EXISTS public.okey_admin_delete_gift(uuid);

CREATE FUNCTION public.okey_admin_delete_gift(p_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'APP:admin_only' USING ERRCODE = '42501';
  END IF;
  DELETE FROM public.okey_gift_catalog AS g WHERE g.id = p_id;
END;
$$;
REVOKE ALL ON FUNCTION public.okey_admin_delete_gift(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.okey_admin_delete_gift(uuid) TO authenticated;

-- Admin listesi: pasif hediyeler de görünmeli (yoksa kapatılan bir hediye
-- panelden kaybolur ve geri açılamazdı).
DROP FUNCTION IF EXISTS public.okey_admin_list_gifts();

CREATE FUNCTION public.okey_admin_list_gifts()
RETURNS TABLE(
  id uuid,
  code text,
  name text,
  icon text,
  price int,
  sort_order int,
  is_active boolean
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
  SELECT g.id, g.code, g.name, g.icon, g.price, g.sort_order, g.is_active
  FROM public.okey_gift_catalog AS g
  ORDER BY g.sort_order, g.price, g.name;
END;
$$;
REVOKE ALL ON FUNCTION public.okey_admin_list_gifts() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.okey_admin_list_gifts() TO authenticated;

-- ALICI PAYI — admin ayarı.
--
-- Neden ayrı bir RPC, admin_okey_update_settings'e bir parametre daha değil:
-- o fonksiyonun imzası on bir parametreli ve masa/ceza ayarlarını yönetiyor;
-- hediye ekonomisi ayrı bir sekmede yaşıyor ve oraya ait bir alanı oradan
-- yazmak, imza değişikliğinin (DROP + yeniden GRANT + istemci güncellemesi)
-- yayılma riskini almaktan daha ucuz.
DROP FUNCTION IF EXISTS public.okey_admin_set_gift_percent(int);

CREATE FUNCTION public.okey_admin_set_gift_percent(p_percent int)
RETURNS int
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_value int := LEAST(GREATEST(COALESCE(p_percent, 0), 0), 100);
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'APP:admin_only' USING ERRCODE = '42501';
  END IF;
  UPDATE public.okey_settings SET gift_recipient_percent = v_value
  WHERE id = true;
  RETURN v_value;
END;
$$;
REVOKE ALL ON FUNCTION public.okey_admin_set_gift_percent(int) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.okey_admin_set_gift_percent(int) TO authenticated;

DROP FUNCTION IF EXISTS public.okey_admin_get_gift_percent();

CREATE FUNCTION public.okey_admin_get_gift_percent()
RETURNS int
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_value int;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'APP:admin_only' USING ERRCODE = '42501';
  END IF;
  SELECT COALESCE(s.gift_recipient_percent, 50) INTO v_value
  FROM public.okey_settings AS s WHERE s.id = true;
  RETURN COALESCE(v_value, 50);
END;
$$;
REVOKE ALL ON FUNCTION public.okey_admin_get_gift_percent() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.okey_admin_get_gift_percent() TO authenticated;

-- -----------------------------------------------------------------------------
-- 8) REALTIME — hediye masadaki HERKESTE anında belirsin
-- -----------------------------------------------------------------------------
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime')
     AND NOT EXISTS (
       SELECT 1 FROM pg_publication_tables
       WHERE pubname = 'supabase_realtime'
         AND schemaname = 'public'
         AND tablename = 'okey_gifts_sent'
     )
  THEN
    EXECUTE 'ALTER PUBLICATION supabase_realtime ADD TABLE public.okey_gifts_sent';
  END IF;
END;
$$;

NOTIFY pgrst, 'reload schema';
