-- =============================================================================
-- Görev 3.4 — Satıcı canlı yayınının (canlı alışveriş) eksiklerinin tamamlanması
-- =============================================================================
-- Canlıda bulunan durum: özellik HİÇ çalışmıyordu (tabloda 0 yayın).
--   * İstemci `users!host_user_id(...)` gömmesi istiyor; public.users yok →
--     yayın oluşturma/listeleme/detay PostgREST'te 400 dönüyordu.
--   * Mesaj geçmişi `users(...)` gömmesiyle okunuyordu → her zaman boş.
--   * Agora App ID/anahtar istemcinin .env'inden okunuyor; .env pakete girmiyor.
--
-- Çözüm (Agora — pubspec'te zaten var; ayda 10.000 dk ücretsiz, SFU ile 1→N
-- yayında P2P'den çok daha kararlı):
--   1) live_sessions: canlılık sinyali (heartbeat), anlık izleyici sayısı, bitiş
--      nedeni, o an sabitlenen ürün; mağaza başına tek açık yayın.
--   2) Tüm yayın/ürün sabitleme yazmaları DEFINER RPC'lerle. Doğrudan INSERT/
--      UPDATE politikaları kaldırılır: satıcı durum, izleyici sayısı veya kanal
--      adını elle yazamaz.
--   3) Mesajlarda yazar adı/avatarı ve satıcı bayrağı SUNUCUDA (tetikleyici):
--      yalnız canlı yayına, 1–300 karakter, 10 sn'de en çok 5 mesaj. Satıcı kendi
--      yayınındaki her mesajı silebilir (moderasyon).
--   4) live_token_grant: Agora anahtarını üreten `live-token` Edge Function'ın
--      yetki kararı (yalnız service_role çalıştırır). App Certificate yalnız
--      Supabase secret'ta durur.
--   5) Keşfet / detay RPC'leri: tek istek; mağaza adı-logosu, sabit ürün, sayaçlar.
--   6) pg_cron: her dakika 2 dakikadır sinyal vermeyen yayını kapatır.
--
-- Canlılık eşiği her yerde 2 dakikadır (istemci 20 sn'de bir sinyal gönderir).
-- =============================================================================

BEGIN;

-- -----------------------------------------------------------------------------
-- 1) Şema
-- -----------------------------------------------------------------------------
ALTER TABLE public.live_sessions
  ADD COLUMN IF NOT EXISTS last_heartbeat_at timestamptz,
  ADD COLUMN IF NOT EXISTS viewer_count integer NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS ended_reason text,
  ADD COLUMN IF NOT EXISTS pinned_product_id uuid REFERENCES public.products(id) ON DELETE SET NULL;

ALTER TABLE public.live_sessions DROP CONSTRAINT IF EXISTS live_sessions_ended_reason_check;
ALTER TABLE public.live_sessions ADD CONSTRAINT live_sessions_ended_reason_check
  CHECK (ended_reason IS NULL OR ended_reason IN ('host', 'timeout', 'admin'));

ALTER TABLE public.live_sessions DROP CONSTRAINT IF EXISTS live_sessions_viewer_count_check;
ALTER TABLE public.live_sessions ADD CONSTRAINT live_sessions_viewer_count_check
  CHECK (viewer_count >= 0 AND peak_viewer_count >= 0);

-- Mağaza başına aynı anda tek açık (hazırlık/canlı) yayın.
CREATE UNIQUE INDEX IF NOT EXISTS live_sessions_one_open_per_shop
  ON public.live_sessions (shop_id)
  WHERE status IN ('scheduled', 'live');

-- Mesajın yazar adı/avatarı ekleme anında kopyalanır: Realtime yükü tek başına
-- gösterilebilir olur (ek profil sorgusu yok).
ALTER TABLE public.live_messages
  ADD COLUMN IF NOT EXISTS author_name text,
  ADD COLUMN IF NOT EXISTS author_avatar text;

-- -----------------------------------------------------------------------------
-- 2) Yetkiler ve politikalar — yazmalar RPC'lerden
-- -----------------------------------------------------------------------------
DROP POLICY IF EXISTS "live_sessions_insert_host" ON public.live_sessions;
DROP POLICY IF EXISTS "live_sessions_update_host" ON public.live_sessions;
DROP POLICY IF EXISTS "live_pin_insert_host" ON public.live_pinned_products;
DROP POLICY IF EXISTS "live_pin_update_host" ON public.live_pinned_products;
DROP POLICY IF EXISTS "live_pin_delete_host" ON public.live_pinned_products;

REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON public.live_sessions FROM anon, authenticated;
REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON public.live_pinned_products FROM anon, authenticated;
REVOKE INSERT, UPDATE, DELETE, TRUNCATE ON public.live_messages FROM anon;
REVOKE UPDATE, TRUNCATE ON public.live_messages FROM authenticated;

-- Mesaj yazma: yalnız giriş yapmış kullanıcı, kendi adına (alanlar tetikleyicide).
DROP POLICY IF EXISTS "live_messages_insert_auth" ON public.live_messages;
CREATE POLICY "live_messages_insert_auth" ON public.live_messages
  FOR INSERT TO authenticated
  WITH CHECK ((SELECT auth.uid()) = user_id);

-- Moderasyon: satıcı kendi yayınındaki HER mesajı silebilir (eskisi yalnız
-- kendi mesajını silebiliyordu).
DROP POLICY IF EXISTS "live_messages_delete_host" ON public.live_messages;
CREATE POLICY "live_messages_delete_host" ON public.live_messages
  FOR DELETE TO authenticated
  USING (EXISTS (
    SELECT 1 FROM public.live_sessions ls
    WHERE ls.id = live_messages.session_id
      AND ls.host_user_id = (SELECT auth.uid())
  ));

-- -----------------------------------------------------------------------------
-- 3) İç yardımcılar (private)
-- -----------------------------------------------------------------------------

-- Tek yayının istemciye dönen hâli (keşfet, detay ve RPC dönüşleri aynı biçim).
CREATE OR REPLACE FUNCTION private.live_session_json(p_session_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SET search_path = ''
AS $fn$
DECLARE
  v_json jsonb;
BEGIN
  SELECT jsonb_build_object(
    'id', ls.id,
    'shop_id', ls.shop_id,
    'host_user_id', ls.host_user_id,
    'title', ls.title,
    'description', ls.description,
    'cover_image_url', ls.cover_image_url,
    'channel_name', ls.channel_name,
    'status', ls.status,
    'is_live', (ls.status = 'live' AND ls.last_heartbeat_at > now() - interval '2 minutes'),
    'started_at', ls.started_at,
    'ended_at', ls.ended_at,
    'ended_reason', ls.ended_reason,
    'viewer_count', ls.viewer_count,
    'peak_viewer_count', ls.peak_viewer_count,
    'last_heartbeat_at', ls.last_heartbeat_at,
    'created_at', ls.created_at,
    'updated_at', ls.updated_at,
    'shop_name', s.name,
    'shop_logo_url', s.logo_url,
    'pinned_product', CASE WHEN p.id IS NULL THEN NULL ELSE jsonb_build_object(
      'id', p.id,
      'name', p.name,
      'image_url', p.image_url,
      'price', p.price,
      'discount_price', p.discount_price,
      'effective_price', CASE
        WHEN p.discount_price IS NOT NULL AND p.discount_price > 0 AND p.discount_price < p.price
          THEN p.discount_price
        ELSE p.price
      END,
      'is_available', COALESCE(p.is_available, false)
    ) END
  )
  INTO v_json
  FROM public.live_sessions ls
  JOIN public.shops s ON s.id = ls.shop_id
  LEFT JOIN public.products p ON p.id = ls.pinned_product_id
  WHERE ls.id = p_session_id;

  RETURN v_json;
END;
$fn$;

-- Yayını kapatır. Hiç başlamamış (hazırlıktaki) yayın silinir; canlı yayın
-- 'ended' olur, sabit ürün kalkar. Özet döner (süre, en yüksek izleyici, mesaj).
CREATE OR REPLACE FUNCTION private.live_close_session(p_session_id uuid, p_reason text)
RETURNS jsonb
LANGUAGE plpgsql
SET search_path = ''
AS $fn$
DECLARE
  v public.live_sessions%ROWTYPE;
  v_messages integer;
BEGIN
  SELECT * INTO v FROM public.live_sessions WHERE id = p_session_id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('status', 'missing');
  END IF;

  IF v.status = 'scheduled' THEN
    DELETE FROM public.live_sessions WHERE id = p_session_id;
    RETURN jsonb_build_object('status', 'discarded');
  END IF;

  IF v.status = 'live' THEN
    UPDATE public.live_pinned_products
       SET is_current = false
     WHERE session_id = p_session_id AND is_current;

    UPDATE public.live_sessions
       SET status = 'ended',
           -- Zaman aşımında yayının gerçekten bittiği an son sinyaldir.
           ended_at = CASE
             WHEN p_reason = 'timeout' THEN COALESCE(v.last_heartbeat_at, v.started_at, now())
             ELSE now()
           END,
           ended_reason = p_reason,
           viewer_count = 0,
           pinned_product_id = NULL
     WHERE id = p_session_id
    RETURNING * INTO v;
  END IF;

  SELECT count(*) INTO v_messages FROM public.live_messages m WHERE m.session_id = p_session_id;

  RETURN jsonb_build_object(
    'status', v.status,
    'ended_reason', v.ended_reason,
    'started_at', v.started_at,
    'ended_at', v.ended_at,
    'duration_seconds', GREATEST(0, floor(extract(epoch FROM (v.ended_at - v.started_at))))::integer,
    'peak_viewer_count', v.peak_viewer_count,
    'message_count', v_messages
  );
END;
$fn$;

-- Her dakika: 2 dakikadır sinyal vermeyen canlı yayını kapat, 6 saattir
-- başlatılmamış hazırlık kaydını sil. Kapatılan yayın sayısını döner.
CREATE OR REPLACE FUNCTION private.live_reap_stale_sessions()
RETURNS integer
LANGUAGE plpgsql
SET search_path = ''
AS $fn$
DECLARE
  v_id uuid;
  v_closed integer := 0;
BEGIN
  FOR v_id IN
    SELECT id FROM public.live_sessions
     WHERE status = 'live'
       AND COALESCE(last_heartbeat_at, started_at, created_at) < now() - interval '2 minutes'
     FOR UPDATE SKIP LOCKED
  LOOP
    PERFORM private.live_close_session(v_id, 'timeout');
    v_closed := v_closed + 1;
  END LOOP;

  DELETE FROM public.live_sessions
   WHERE status = 'scheduled'
     AND created_at < now() - interval '6 hours';

  RETURN v_closed;
END;
$fn$;

-- Mesaj ekleme tetikleyicisi: istemcinin gönderdiği is_host / ad / zaman
-- YOK SAYILIR; hepsi sunucuda belirlenir.
CREATE OR REPLACE FUNCTION private.live_messages_before_insert()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $fn$
DECLARE
  v_session public.live_sessions%ROWTYPE;
  v_text text;
  v_recent integer;
BEGIN
  SELECT * INTO v_session FROM public.live_sessions WHERE id = NEW.session_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Yayın bulunamadı' USING ERRCODE = 'P0001', HINT = 'LIVE_NOT_FOUND';
  END IF;
  IF v_session.status <> 'live' THEN
    RAISE EXCEPTION 'Yayın şu an canlı değil' USING ERRCODE = 'P0001', HINT = 'LIVE_NOT_LIVE';
  END IF;

  v_text := btrim(regexp_replace(COALESCE(NEW.message, ''), '\s+', ' ', 'g'));
  IF char_length(v_text) = 0 THEN
    RAISE EXCEPTION 'Mesaj boş olamaz' USING ERRCODE = 'P0001', HINT = 'LIVE_MESSAGE_EMPTY';
  END IF;
  IF char_length(v_text) > 300 THEN
    RAISE EXCEPTION 'Mesaj en fazla 300 karakter olabilir' USING ERRCODE = 'P0001', HINT = 'LIVE_MESSAGE_TOO_LONG';
  END IF;

  SELECT count(*) INTO v_recent
    FROM public.live_messages m
   WHERE m.session_id = NEW.session_id
     AND m.user_id = NEW.user_id
     AND m.created_at > now() - interval '10 seconds';
  IF v_recent >= 5 THEN
    RAISE EXCEPTION 'Çok hızlı mesaj gönderiyorsun; biraz bekle' USING ERRCODE = 'P0001', HINT = 'LIVE_MESSAGE_RATE';
  END IF;

  NEW.message := v_text;
  NEW.created_at := now();
  NEW.is_host := (NEW.user_id = v_session.host_user_id);
  NEW.author_name := NULL;
  NEW.author_avatar := NULL;

  IF NEW.is_host THEN
    -- Satıcının mesajı mağaza adıyla görünür.
    SELECT s.name, s.logo_url INTO NEW.author_name, NEW.author_avatar
      FROM public.shops s WHERE s.id = v_session.shop_id;
  ELSE
    -- Herkese açık sohbet: önce kullanıcı adı (takma ad), yoksa ad.
    SELECT COALESCE(NULLIF(btrim(p.username), ''), NULLIF(btrim(p.full_name), '')), p.avatar_url
      INTO NEW.author_name, NEW.author_avatar
      FROM public.profiles p WHERE p.id = NEW.user_id;
  END IF;
  NEW.author_name := COALESCE(NULLIF(btrim(NEW.author_name), ''), 'Kullanıcı');

  RETURN NEW;
END;
$fn$;

DROP TRIGGER IF EXISTS live_messages_before_insert ON public.live_messages;
CREATE TRIGGER live_messages_before_insert
  BEFORE INSERT ON public.live_messages
  FOR EACH ROW EXECUTE FUNCTION private.live_messages_before_insert();

REVOKE ALL ON FUNCTION private.live_session_json(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION private.live_close_session(uuid, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION private.live_reap_stale_sessions() FROM PUBLIC;
REVOKE ALL ON FUNCTION private.live_messages_before_insert() FROM PUBLIC;

-- -----------------------------------------------------------------------------
-- 4) Satıcı RPC'leri
-- -----------------------------------------------------------------------------

-- Yayın hazırla (ya da mağazanın açık yayınını sürdür).
--   * taze canlı yayın varsa aynen döner (resumed=true: uygulama kapanıp açıldı),
--   * hazırlıktaki kayıt varsa başlığı güncellenip döner,
--   * 2 dakikadır sinyalsiz canlı yayın zaman aşımıyla kapatılıp yenisi açılır.
CREATE OR REPLACE FUNCTION public.live_create_session(
  p_shop_id uuid,
  p_title text,
  p_description text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $fn$
DECLARE
  v_uid uuid := auth.uid();
  v_owner uuid;
  v_active boolean;
  v_title text := btrim(regexp_replace(COALESCE(p_title, ''), '\s+', ' ', 'g'));
  v_desc text := NULLIF(btrim(COALESCE(p_description, '')), '');
  v_open public.live_sessions%ROWTYPE;
  v_id uuid;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Oturum açmanız gerekli' USING ERRCODE = '42501', HINT = 'AUTH_REQUIRED';
  END IF;

  SELECT s.owner_id, COALESCE(s.is_active, false) AND COALESCE(s.is_approved, false)
    INTO v_owner, v_active
    FROM public.shops s WHERE s.id = p_shop_id;
  IF v_owner IS NULL OR v_owner <> v_uid THEN
    RAISE EXCEPTION 'Bu mağaza adına yayın açamazsınız' USING ERRCODE = '42501', HINT = 'LIVE_NOT_SHOP_OWNER';
  END IF;
  IF NOT v_active THEN
    RAISE EXCEPTION 'Yayın için mağazanız aktif ve onaylı olmalı' USING ERRCODE = 'P0001', HINT = 'LIVE_SHOP_INACTIVE';
  END IF;
  IF char_length(v_title) < 3 OR char_length(v_title) > 80 THEN
    RAISE EXCEPTION 'Yayın başlığı 3–80 karakter olmalı' USING ERRCODE = 'P0001', HINT = 'LIVE_TITLE_INVALID';
  END IF;
  v_desc := left(v_desc, 300);

  SELECT * INTO v_open
    FROM public.live_sessions
   WHERE shop_id = p_shop_id AND status IN ('scheduled', 'live')
   FOR UPDATE;

  IF FOUND THEN
    IF v_open.status = 'live' AND v_open.last_heartbeat_at > now() - interval '2 minutes' THEN
      RETURN private.live_session_json(v_open.id) || jsonb_build_object('resumed', true);
    ELSIF v_open.status = 'scheduled' THEN
      UPDATE public.live_sessions
         SET title = v_title, description = v_desc, host_user_id = v_uid
       WHERE id = v_open.id;
      RETURN private.live_session_json(v_open.id) || jsonb_build_object('resumed', false);
    END IF;
    PERFORM private.live_close_session(v_open.id, 'timeout');
  END IF;

  BEGIN
    INSERT INTO public.live_sessions (host_user_id, shop_id, title, description, channel_name, status)
    VALUES (v_uid, p_shop_id, v_title, v_desc, 'cz_' || replace(gen_random_uuid()::text, '-', ''), 'scheduled')
    RETURNING id INTO v_id;
  EXCEPTION WHEN unique_violation THEN
    -- Aynı anda ikinci cihazdan açıldı: açık olanı dön.
    SELECT id INTO v_id FROM public.live_sessions
     WHERE shop_id = p_shop_id AND status IN ('scheduled', 'live');
  END;

  RETURN private.live_session_json(v_id) || jsonb_build_object('resumed', false);
END;
$fn$;

-- Yayını başlat (Agora kanalına katılınca). Tekrar çağrılırsa yalnız sinyal.
CREATE OR REPLACE FUNCTION public.start_live_session(p_session_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $fn$
DECLARE
  v public.live_sessions%ROWTYPE;
  v_active boolean;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Oturum açmanız gerekli' USING ERRCODE = '42501', HINT = 'AUTH_REQUIRED';
  END IF;
  SELECT * INTO v FROM public.live_sessions WHERE id = p_session_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Yayın bulunamadı' USING ERRCODE = 'P0001', HINT = 'LIVE_NOT_FOUND';
  END IF;
  IF v.host_user_id <> auth.uid() THEN
    RAISE EXCEPTION 'Bu yayın size ait değil' USING ERRCODE = '42501', HINT = 'LIVE_NOT_HOST';
  END IF;
  IF v.status = 'ended' THEN
    RAISE EXCEPTION 'Bu yayın sona erdi' USING ERRCODE = 'P0001', HINT = 'LIVE_ENDED';
  END IF;
  SELECT COALESCE(s.is_active, false) AND COALESCE(s.is_approved, false) INTO v_active
    FROM public.shops s WHERE s.id = v.shop_id;
  IF NOT COALESCE(v_active, false) THEN
    RAISE EXCEPTION 'Yayın için mağazanız aktif ve onaylı olmalı' USING ERRCODE = 'P0001', HINT = 'LIVE_SHOP_INACTIVE';
  END IF;

  UPDATE public.live_sessions
     SET status = 'live',
         started_at = COALESCE(started_at, now()),
         last_heartbeat_at = now()
   WHERE id = p_session_id;

  RETURN private.live_session_json(p_session_id);
END;
$fn$;

-- Yayını bitir (hiç başlamadıysa kaydı siler). Özet döner.
CREATE OR REPLACE FUNCTION public.end_live_session(p_session_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $fn$
DECLARE
  v_host uuid;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Oturum açmanız gerekli' USING ERRCODE = '42501', HINT = 'AUTH_REQUIRED';
  END IF;
  SELECT host_user_id INTO v_host FROM public.live_sessions WHERE id = p_session_id;
  IF v_host IS NULL THEN
    RAISE EXCEPTION 'Yayın bulunamadı' USING ERRCODE = 'P0001', HINT = 'LIVE_NOT_FOUND';
  END IF;
  IF v_host <> auth.uid() THEN
    RAISE EXCEPTION 'Bu yayın size ait değil' USING ERRCODE = '42501', HINT = 'LIVE_NOT_HOST';
  END IF;
  RETURN private.live_close_session(p_session_id, 'host');
END;
$fn$;

-- Satıcı uygulaması 20 sn'de bir: "yayındayım" + anlık izleyici sayısı.
-- Yayın bu arada kapatıldıysa (zaman aşımı) status='ended' döner.
CREATE OR REPLACE FUNCTION public.live_session_heartbeat(
  p_session_id uuid,
  p_viewer_count integer DEFAULT 0
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $fn$
DECLARE
  v public.live_sessions%ROWTYPE;
  v_count integer := LEAST(GREATEST(COALESCE(p_viewer_count, 0), 0), 100000);
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Oturum açmanız gerekli' USING ERRCODE = '42501', HINT = 'AUTH_REQUIRED';
  END IF;
  SELECT * INTO v FROM public.live_sessions WHERE id = p_session_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Yayın bulunamadı' USING ERRCODE = 'P0001', HINT = 'LIVE_NOT_FOUND';
  END IF;
  IF v.host_user_id <> auth.uid() THEN
    RAISE EXCEPTION 'Bu yayın size ait değil' USING ERRCODE = '42501', HINT = 'LIVE_NOT_HOST';
  END IF;

  IF v.status = 'live' THEN
    UPDATE public.live_sessions
       SET last_heartbeat_at = now(),
           viewer_count = v_count,
           peak_viewer_count = GREATEST(peak_viewer_count, v_count)
     WHERE id = p_session_id
    RETURNING * INTO v;
  END IF;

  RETURN jsonb_build_object(
    'status', v.status,
    'ended_reason', v.ended_reason,
    'viewer_count', v.viewer_count,
    'peak_viewer_count', v.peak_viewer_count
  );
END;
$fn$;

-- Yayında ürün sabitle: ürün yayının mağazasına ait ve satışta olmalı.
CREATE OR REPLACE FUNCTION public.live_pin_product(p_session_id uuid, p_product_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $fn$
DECLARE
  v public.live_sessions%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Oturum açmanız gerekli' USING ERRCODE = '42501', HINT = 'AUTH_REQUIRED';
  END IF;
  SELECT * INTO v FROM public.live_sessions WHERE id = p_session_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Yayın bulunamadı' USING ERRCODE = 'P0001', HINT = 'LIVE_NOT_FOUND';
  END IF;
  IF v.host_user_id <> auth.uid() THEN
    RAISE EXCEPTION 'Bu yayın size ait değil' USING ERRCODE = '42501', HINT = 'LIVE_NOT_HOST';
  END IF;
  IF v.status = 'ended' THEN
    RAISE EXCEPTION 'Bu yayın sona erdi' USING ERRCODE = 'P0001', HINT = 'LIVE_ENDED';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.products p
     WHERE p.id = p_product_id
       AND p.shop_id = v.shop_id
       AND COALESCE(p.is_available, false)
       AND COALESCE(p.is_active, true)
  ) THEN
    RAISE EXCEPTION 'Bu ürün yayında gösterilemez' USING ERRCODE = 'P0001', HINT = 'LIVE_PRODUCT_INVALID';
  END IF;

  UPDATE public.live_pinned_products
     SET is_current = false
   WHERE session_id = p_session_id AND is_current;
  INSERT INTO public.live_pinned_products (session_id, product_id, pinned_by, is_current)
  VALUES (p_session_id, p_product_id, auth.uid(), true);
  UPDATE public.live_sessions SET pinned_product_id = p_product_id WHERE id = p_session_id;

  RETURN private.live_session_json(p_session_id);
END;
$fn$;

CREATE OR REPLACE FUNCTION public.live_unpin_product(p_session_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $fn$
DECLARE
  v_host uuid;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Oturum açmanız gerekli' USING ERRCODE = '42501', HINT = 'AUTH_REQUIRED';
  END IF;
  SELECT host_user_id INTO v_host FROM public.live_sessions WHERE id = p_session_id FOR UPDATE;
  IF v_host IS NULL THEN
    RAISE EXCEPTION 'Yayın bulunamadı' USING ERRCODE = 'P0001', HINT = 'LIVE_NOT_FOUND';
  END IF;
  IF v_host <> auth.uid() THEN
    RAISE EXCEPTION 'Bu yayın size ait değil' USING ERRCODE = '42501', HINT = 'LIVE_NOT_HOST';
  END IF;

  UPDATE public.live_pinned_products
     SET is_current = false
   WHERE session_id = p_session_id AND is_current;
  UPDATE public.live_sessions SET pinned_product_id = NULL WHERE id = p_session_id;

  RETURN private.live_session_json(p_session_id);
END;
$fn$;

-- -----------------------------------------------------------------------------
-- 5) Herkese açık okuma RPC'leri (misafir de izleyebilir)
-- -----------------------------------------------------------------------------

-- Keşfet: şu an canlı olanlar (izleyiciye göre) + son 7 günün biten yayınları.
CREATE OR REPLACE FUNCTION public.live_sessions_feed(p_limit integer DEFAULT 30)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $fn$
DECLARE
  v_limit integer := LEAST(GREATEST(COALESCE(p_limit, 30), 1), 100);
  v_live jsonb;
  v_recent jsonb;
BEGIN
  SELECT COALESCE(jsonb_agg(private.live_session_json(x.id) ORDER BY x.viewer_count DESC, x.started_at DESC), '[]'::jsonb)
    INTO v_live
    FROM (
      SELECT ls.id, ls.viewer_count, ls.started_at
        FROM public.live_sessions ls
        JOIN public.shops s ON s.id = ls.shop_id
       WHERE ls.status = 'live'
         AND ls.last_heartbeat_at > now() - interval '2 minutes'
         AND COALESCE(s.is_active, false)
         AND COALESCE(s.is_approved, false)
       ORDER BY ls.viewer_count DESC, ls.started_at DESC
       LIMIT v_limit
    ) x;

  SELECT COALESCE(jsonb_agg(private.live_session_json(y.id) ORDER BY y.ended_at DESC), '[]'::jsonb)
    INTO v_recent
    FROM (
      SELECT ls.id, ls.ended_at
        FROM public.live_sessions ls
       WHERE ls.status = 'ended'
         AND ls.started_at IS NOT NULL
         AND ls.ended_at > now() - interval '7 days'
       ORDER BY ls.ended_at DESC
       LIMIT 20
    ) y;

  RETURN jsonb_build_object('live', v_live, 'recent', v_recent);
END;
$fn$;

CREATE OR REPLACE FUNCTION public.live_session_detail(p_session_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $fn$
BEGIN
  RETURN private.live_session_json(p_session_id);
END;
$fn$;

-- -----------------------------------------------------------------------------
-- 6) Agora anahtarı yetki kararı — YALNIZ `live-token` Edge Function (service_role)
-- -----------------------------------------------------------------------------
-- host  : yalnız yayının sahibi; yayın hazırlıkta ya da canlı; mağaza aktif.
-- viewer: yayın canlı ve son 2 dakikada sinyal var (misafir de olabilir).
-- Satıcının Agora uid'i sabit 1'dir (izleyici yalnız bu uid'in görüntüsünü açar;
-- satıcı başka cihazdan yeniden katılırsa eski bağlantı düşer).
CREATE OR REPLACE FUNCTION public.live_token_grant(
  p_session_id uuid,
  p_role text,
  p_user_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $fn$
DECLARE
  v public.live_sessions%ROWTYPE;
  v_active boolean;
BEGIN
  IF p_role IS NULL OR p_role NOT IN ('host', 'viewer') THEN
    RETURN jsonb_build_object('ok', false, 'error', 'BAD_ROLE');
  END IF;
  SELECT * INTO v FROM public.live_sessions WHERE id = p_session_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'error', 'NOT_FOUND');
  END IF;
  IF v.status = 'ended' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'ENDED');
  END IF;
  SELECT COALESCE(s.is_active, false) AND COALESCE(s.is_approved, false) INTO v_active
    FROM public.shops s WHERE s.id = v.shop_id;
  IF NOT COALESCE(v_active, false) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'SHOP_INACTIVE');
  END IF;

  IF p_role = 'host' THEN
    IF p_user_id IS NULL THEN
      RETURN jsonb_build_object('ok', false, 'error', 'AUTH_REQUIRED');
    END IF;
    IF p_user_id <> v.host_user_id THEN
      RETURN jsonb_build_object('ok', false, 'error', 'FORBIDDEN');
    END IF;
  ELSIF v.status <> 'live' OR v.last_heartbeat_at IS NULL
        OR v.last_heartbeat_at < now() - interval '2 minutes' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'NOT_LIVE');
  END IF;

  RETURN jsonb_build_object('ok', true, 'channel', v.channel_name, 'host_uid', 1, 'role', p_role);
END;
$fn$;

-- -----------------------------------------------------------------------------
-- 7) Çalıştırma yetkileri
-- -----------------------------------------------------------------------------
REVOKE ALL ON FUNCTION public.live_create_session(uuid, text, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.start_live_session(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.end_live_session(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.live_session_heartbeat(uuid, integer) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.live_pin_product(uuid, uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.live_unpin_product(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.live_create_session(uuid, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.start_live_session(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.end_live_session(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.live_session_heartbeat(uuid, integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.live_pin_product(uuid, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.live_unpin_product(uuid) TO authenticated;

REVOKE ALL ON FUNCTION public.live_sessions_feed(integer) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.live_session_detail(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.live_sessions_feed(integer) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.live_session_detail(uuid) TO anon, authenticated;

REVOKE ALL ON FUNCTION public.live_token_grant(uuid, text, uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.live_token_grant(uuid, text, uuid) TO service_role;

-- -----------------------------------------------------------------------------
-- 8) pg_cron: bayat yayın temizliği (her dakika)
-- -----------------------------------------------------------------------------
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    PERFORM cron.schedule(
      'live-reap-stale-sessions',
      '* * * * *',
      'select private.live_reap_stale_sessions();'
    );
  END IF;
END $$;

COMMIT;

NOTIFY pgrst, 'reload schema';
