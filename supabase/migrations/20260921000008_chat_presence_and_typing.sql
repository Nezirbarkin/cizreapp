-- =============================================================================
-- 20260921000008_chat_presence_and_typing.sql
-- -----------------------------------------------------------------------------
-- Sohbet ve profil: SON GÖRÜLME, ÇEVRİMİÇİ durumu ve "YAZIYOR…" göstergesi.
--
--   * Son görülme sohbet ekranında ve profilde görünür; admin'in belirlediği
--     gün sayısından (varsayılan 7) eskiyse HİÇ gösterilmez.
--   * Kullanıcı kimin görebileceğini seçer: herkes / yalnız arkadaşlar
--     (karşılıklı takip) / hiç kimse. "Yazıyor…" bilgisini de kapatabilir.
--   * Admin her özelliği ayrı ayrı açıp kapatır (app_settings `chat_presence_*`).
--
-- ## Kural nerede uygulanıyor?
--
-- Hepsi SUNUCUDA, tek yerde: `presence_resolve(hedef, bağlam)`. Aynı çözümleyici
-- yeni `get_user_presence` RPC'sini, iki profil görünümünü ve `get_online_users`
-- fonksiyonunu besler; yani istemci ne çizerse çizsin, "gizli" bilgi bu yollardan
-- hiç çıkmaz. Eski istemciler bu görünümleri okumaya devam eder ve otomatik
-- olarak maskelenmiş değer görür.
--
-- Görünürlük şu durumlarda kapanır (biri yeter):
--   - görüntüleyici oturum açmamış, ya da iki taraftan biri diğerini engellemiş
--   - hedef gizli hesap ve görüntüleyici onu takip etmiyor
--   - hedef Hayalet Modu'nda (çevrimiçi de son görülme de gizli)
--   - admin ilgili özelliği / bağlamı kapatmış
--   - hedef "çevrimiçi görünme"yi kapatmış (çevrimiçi rozeti gizlenir; ayrıca
--     şu an aktifse son görülmesi de gizlenir, yoksa "az önce" ile kendini ele
--     verirdi)
--   - hedef son görülmeyi kapatmış ya da "yalnız arkadaşlar" demiş ve
--     görüntüleyici karşılıklı takipleşmiyor
--   - son görülme admin'in belirlediği günden eski
--
-- ## Bilinen sınır (kapatılamadı, bilerek)
--
-- `profiles` tablosunda `profiles_select_public` (herkese USING true) ve
-- `authenticated` için tablo düzeyi SELECT hâlâ duruyor; `is_online` / `last_seen`
-- ham sütunları doğrudan okunabilir. Bunu sütun REVOKE'u ile kapatmak,
-- mağazadaki eski istemcilerin argümansız `.select()` çağrılarını kırar
-- (bkz. supabase/migrations/PENDING_RELEASE_20260908_revoke_profiles_pii.sql.txt).
-- Bu göç, uygulamanın kullandığı BÜTÜN okuma yollarını (görünümler, RPC'ler)
-- kapatır; ham sütun kapısı o bekleyen sürüm göçüyle kapanacak.
--
-- ## "Yazıyor…" nasıl taşınıyor
--
-- Realtime broadcast ile (veritabanına hiç yazılmaz). Kanal adı tahmin
-- edilemez: sunucudaki gizli anahtarla HMAC'lenmiş çift kimliği. Adı yalnız
-- `get_typing_channel()` verir ve yalnız engel olmayan, özellik açık, kendi
-- çiftin için verir; üçüncü biri bir konuşmanın kanalını türetemez.
-- Grup kanalı `get_group_typing_channel()` ile yalnız üyelere verilir.
--
-- Tümü idempotenttir (yeniden çalıştırılabilir).
-- =============================================================================

begin;

SET LOCAL lock_timeout = '10s';

-- -----------------------------------------------------------------------------
-- 1) Kullanıcı tercihleri (profiles) — kimseye ait olmayan varsayılanlarla
-- -----------------------------------------------------------------------------
-- show_last_seen zaten var (Hesap Ayarları'ndaki anahtar). Yeni iki sütun onu
-- tamamlar; eski istemci show_last_seen'i değiştirmeye devam edebilir:
--   herkes        = show_last_seen true,  last_seen_friends_only false
--   arkadaşlar    = show_last_seen true,  last_seen_friends_only true
--   hiç kimse     = show_last_seen false  (friends_only anlamsız)
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS last_seen_friends_only boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS show_typing_indicator  boolean NOT NULL DEFAULT true;

COMMENT ON COLUMN public.profiles.last_seen_friends_only IS
  'show_last_seen açıkken son görülmeyi yalnız karşılıklı takipleşilen arkadaşlara göster.';
COMMENT ON COLUMN public.profiles.show_typing_indicator IS
  'Karşı tarafa "yazıyor…" bilgisini gönder. Kapalıysa istemci hiç yayın yapmaz.';

-- -----------------------------------------------------------------------------
-- 2) Admin anahtarları (app_settings)
-- -----------------------------------------------------------------------------
-- Konvansiyon: jsonb'ye JSON string yazılır ('"true"'); okuyucular tırnağa
-- dayanıklıdır (bkz. leaderboard_setting). Eksik/anlamsız değer = varsayılan.
INSERT INTO public.app_settings (key, value, description)
VALUES
  ('chat_presence_last_seen_enabled', '"true"',
   'Sohbet: SON GÖRÜLME özelliği (ana anahtar). Kapalıyken hiçbir yerde gösterilmez.'),
  ('chat_presence_last_seen_in_chat', '"true"',
   'Sohbet: son görülme sohbet ekranında görünsün'),
  ('chat_presence_last_seen_in_profile', '"true"',
   'Sohbet: son görülme profilde görünsün'),
  ('chat_presence_last_seen_max_days', '"7"',
   'Sohbet: son görülme bu günden eskiyse hiç gösterilmez (1-365, varsayılan 7)'),
  ('chat_presence_online_enabled', '"true"',
   'Sohbet: ÇEVRİMİÇİ durumu (yeşil nokta, "çevrimiçi" yazısı, aktif kullanıcılar şeridi)'),
  ('chat_presence_typing_enabled', '"true"',
   'Sohbet: "YAZIYOR…" göstergesi (ana anahtar)'),
  ('chat_presence_typing_in_groups', '"true"',
   'Sohbet: "yazıyor…" grup sohbetlerinde de çalışsın')
ON CONFLICT (key) DO NOTHING;

-- -----------------------------------------------------------------------------
-- 3) Ayarları tek sorguda okuyan iç yardımcı
-- -----------------------------------------------------------------------------
-- Görünüm/RPC her satır için çağırdığından ayarlar TEK sorguyla okunur.
-- Eksik, boş ya da anlamsız değer varsayılana düşer (özellikler varsayılan AÇIK,
-- süre 7 gün); yalnız açıkça false/0/no/off yazılan kapanır.
CREATE OR REPLACE FUNCTION public.chat_presence_cfg()
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $fn$
  WITH kv AS (
    SELECT s.key, lower(btrim(s.value #>> '{}', E'" \t\r\n')) AS v
    FROM public.app_settings s
    WHERE starts_with(s.key, 'chat_presence_')
  )
  SELECT jsonb_build_object(
    'last_seen',
      COALESCE((SELECT k.v NOT IN ('false', 'f', '0', 'no', 'off')
                FROM kv k WHERE k.key = 'chat_presence_last_seen_enabled'), true),
    'last_seen_in_chat',
      COALESCE((SELECT k.v NOT IN ('false', 'f', '0', 'no', 'off')
                FROM kv k WHERE k.key = 'chat_presence_last_seen_in_chat'), true),
    'last_seen_in_profile',
      COALESCE((SELECT k.v NOT IN ('false', 'f', '0', 'no', 'off')
                FROM kv k WHERE k.key = 'chat_presence_last_seen_in_profile'), true),
    'last_seen_max_days',
      COALESCE((SELECT CASE WHEN k.v ~ '^[0-9]{1,3}$' AND k.v::integer BETWEEN 1 AND 365
                            THEN k.v::integer END
                FROM kv k WHERE k.key = 'chat_presence_last_seen_max_days'), 7),
    'online',
      COALESCE((SELECT k.v NOT IN ('false', 'f', '0', 'no', 'off')
                FROM kv k WHERE k.key = 'chat_presence_online_enabled'), true),
    'typing',
      COALESCE((SELECT k.v NOT IN ('false', 'f', '0', 'no', 'off')
                FROM kv k WHERE k.key = 'chat_presence_typing_enabled'), true),
    'typing_in_groups',
      COALESCE((SELECT k.v NOT IN ('false', 'f', '0', 'no', 'off')
                FROM kv k WHERE k.key = 'chat_presence_typing_in_groups'), true)
  );
$fn$;

REVOKE ALL ON FUNCTION public.chat_presence_cfg() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.chat_presence_cfg() TO service_role;

-- İstemci (ve admin ekranı) için: ham anahtarlar, birbirine VE'lenmemiş halde.
-- Etkin değeri (ör. ana anahtar kapalıyken alt anahtar) istemci hesaplar.
CREATE OR REPLACE FUNCTION public.get_chat_presence_settings()
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $fn$
  SELECT public.chat_presence_cfg();
$fn$;

REVOKE ALL ON FUNCTION public.get_chat_presence_settings() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_chat_presence_settings() TO authenticated, service_role;

-- -----------------------------------------------------------------------------
-- 4) ÇEKİRDEK: bir kullanıcının durumu, GÖRÜNTÜLEYİCİYE göre
-- -----------------------------------------------------------------------------
-- Döner (tek satır; hedef yoksa satır yok):
--   can_see_online : görüntüleyici bu kişinin "çevrimiçi" durumunu görebilir mi?
--                    (canlı presence akışıyla birleştirilirken istemci buna bakar)
--   online         : görebiliyorsa VE şu an gerçekten aktif mi (is_online + ≤3 dk)
--   last_seen      : görebiliyorsa, admin sınırından yeniyse, tarih; aksi NULL
--
-- p_context: 'profile' | 'chat' ('list' ve bilinmeyenler 'chat' sayılır);
-- admin'in "profilde/sohbette göster" anahtarlarını ayırır.
--
-- ÖNEMLİ: Bu fonksiyon görünümlerde (security_invoker) çağrıldığı için anon ve
-- authenticated EXECUTE almak ZORUNDA; bu yüzden ek parametre ile ayar geçirmek
-- (kuralları atlatmak) mümkün olmasın diye yalnız (hedef, bağlam) alır.
--
-- 3 dakika = PrivacyService.activeThreshold (2 dk'lık nabız + tolerans).
CREATE OR REPLACE FUNCTION public.presence_resolve(
  p_target  uuid,
  p_context text DEFAULT 'chat'
)
RETURNS TABLE (can_see_online boolean, online boolean, last_seen timestamptz)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $fn$
  WITH ctx AS (
    SELECT (SELECT auth.uid()) AS viewer, public.chat_presence_cfg() AS cfg
  ),
  t AS (
    SELECT
      p.id,
      p.is_online,
      p.last_seen,
      COALESCE(p.is_ghost_mode, false)          AS ghost,
      COALESCE(p.is_online_enabled, true)       AS online_pref,
      COALESCE(p.show_last_seen, true)          AS seen_pref,
      COALESCE(p.last_seen_friends_only, false) AS friends_only,
      COALESCE(p.profile_is_public, true)       AS is_public,
      ctx.viewer,
      ctx.cfg,
      (ctx.viewer IS NOT NULL AND ctx.viewer = p.id) AS is_self
    FROM public.profiles p
    CROSS JOIN ctx
    WHERE p.id = p_target
  ),
  -- Pahalı aramalar YALNIZ gerektiğinde çalışsın diye CASE ile korunur:
  -- çoğu satırda yalnız engel kontrolü (2 indeksli arama) yapılır.
  rel AS (
    SELECT
      t.*,
      CASE WHEN t.viewer IS NULL OR t.is_self THEN false
           ELSE EXISTS (
             SELECT 1 FROM public.blocked_users b
             WHERE (b.blocker_id = t.viewer AND b.blocked_id = t.id)
                OR (b.blocker_id = t.id AND b.blocked_id = t.viewer)
           ) END AS blocked,
      CASE WHEN t.viewer IS NOT NULL AND NOT t.is_self
                AND (NOT t.is_public OR t.friends_only)
           THEN EXISTS (
             SELECT 1 FROM public.follows f
             WHERE f.follower_id = t.viewer AND f.following_id = t.id
           ) ELSE false END AS viewer_follows,
      CASE WHEN t.viewer IS NOT NULL AND NOT t.is_self AND t.friends_only
           THEN EXISTS (
             SELECT 1 FROM public.follows f
             WHERE f.follower_id = t.id AND f.following_id = t.viewer
           ) ELSE false END AS target_follows
    FROM t
  ),
  fin AS (
    SELECT
      r.*,
      -- Oturum açık + engel yok + (herkese açık hesap ya da takip ediyor)
      (r.viewer IS NOT NULL AND NOT r.blocked AND (r.is_public OR r.viewer_follows)) AS reachable
    FROM rel r
  ),
  vis AS (
    SELECT
      f.*,
      (f.is_self OR (f.reachable
                     AND (f.cfg->>'online')::boolean
                     AND NOT f.ghost
                     AND f.online_pref)) AS see_online,
      (f.is_self OR (f.reachable
                     AND (f.cfg->>'last_seen')::boolean
                     AND CASE WHEN p_context = 'profile'
                              THEN (f.cfg->>'last_seen_in_profile')::boolean
                              ELSE (f.cfg->>'last_seen_in_chat')::boolean END
                     AND NOT f.ghost
                     AND f.seen_pref
                     AND (NOT f.friends_only OR (f.viewer_follows AND f.target_follows)))) AS see_seen
    FROM fin f
  )
  SELECT
    v.see_online,
    (v.see_online
       AND COALESCE(v.is_online, false)
       AND v.last_seen IS NOT NULL
       AND v.last_seen > now() - interval '3 minutes'),
    CASE
      WHEN v.see_seen
       AND v.last_seen IS NOT NULL
       AND v.last_seen > now() - make_interval(days => (v.cfg->>'last_seen_max_days')::integer)
       -- "Çevrimdışı görün" diyen biri şu an aktifse, son görülmesi "az önce"
       -- diyerek onu ele vermesin: taze nabız varken gizli tutulur.
       AND (v.online_pref OR v.is_self OR v.last_seen <= now() - interval '3 minutes')
      THEN v.last_seen
    END
  FROM vis v;
$fn$;

REVOKE ALL ON FUNCTION public.presence_resolve(uuid, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.presence_resolve(uuid, text)
  TO anon, authenticated, service_role;

-- Toplu: sohbet listesi / üye listeleri için tek çağrı (en çok 500 kimlik).
CREATE OR REPLACE FUNCTION public.get_user_presence(
  p_user_ids uuid[],
  p_context  text DEFAULT 'chat'
)
RETURNS TABLE (user_id uuid, can_see_online boolean, online boolean, last_seen timestamptz)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $fn$
  SELECT ids.id, pr.can_see_online, pr.online, pr.last_seen
  FROM (
    SELECT DISTINCT u AS id
    FROM unnest(COALESCE(p_user_ids, ARRAY[]::uuid[])) AS u
    WHERE u IS NOT NULL
    LIMIT 500
  ) ids
  CROSS JOIN LATERAL public.presence_resolve(ids.id, p_context) pr;
$fn$;

REVOKE ALL ON FUNCTION public.get_user_presence(uuid[], text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_user_presence(uuid[], text)
  TO authenticated, service_role;

-- -----------------------------------------------------------------------------
-- 5) İki profil görünümü: is_online / last_seen artık MASKELİ
-- -----------------------------------------------------------------------------
-- Sütun adları, türleri ve SIRASI değişmez (eski istemciler aynı şekli okur).
-- security_invoker AÇIK KALIR: CREATE OR REPLACE VIEW seçenekleri sıfırladığı
-- için burada yeniden verilmek zorundadır.
--
-- is_online  : görünür VE gerçekten aktif (eski istemci `isUserTrulyActive`
--              ile birlikte kullanıyor; ikisi tutarlı kalır)
-- last_seen  : aktifse taze nabız zamanı; değilse izin verilen son görülme ya da NULL
CREATE OR REPLACE VIEW public.public_profiles_chat
WITH (security_invoker = true) AS
SELECT
  p.id,
  p.username,
  p.full_name,
  p.avatar_url,
  p.messages_enabled,
  COALESCE(pr.online, false)                                AS is_online,
  CASE WHEN pr.online THEN p.last_seen ELSE pr.last_seen END AS last_seen,
  p.is_ghost_mode,
  p.created_at,
  p.bio
FROM public.profiles p
LEFT JOIN LATERAL public.presence_resolve(p.id, 'chat') pr ON true
WHERE COALESCE(p.profile_is_public, true) = true
   OR p.id = (SELECT auth.uid());

CREATE OR REPLACE VIEW public.public_profiles_safe
WITH (security_invoker = true) AS
SELECT
  p.id,
  p.username,
  p.full_name,
  p.avatar_url,
  p.cover_url,
  p.bio,
  p.website,
  p.location,
  p.gender,
  p.profile_is_public,
  p.created_at,
  p.updated_at,
  CASE WHEN pr.online THEN p.last_seen ELSE pr.last_seen END AS last_seen,
  p.status,
  p.is_ghost_mode
FROM public.profiles p
LEFT JOIN LATERAL public.presence_resolve(p.id, 'profile') pr ON true
WHERE COALESCE(p.profile_is_public, true) = true;

-- -----------------------------------------------------------------------------
-- 6) get_online_users — artık yalnız GÖRÜNTÜLEYİCİNİN görebildiği aktifler
-- -----------------------------------------------------------------------------
-- Eski gövde ghost/tercih/engel/admin kapısına bakmadan herkesin (ghost dahil)
-- son 3 dakikadaki last_seen'ini dönüyordu; istemci süzüyordu. Şimdi sunucu süzer.
-- İmza ve dönüş şekli AYNI (eski istemci bozulmaz).
CREATE OR REPLACE FUNCTION public.get_online_users(p_exclude_user_id uuid DEFAULT NULL::uuid)
RETURNS TABLE(
  user_id uuid,
  full_name text,
  username text,
  avatar_url text,
  is_online boolean,
  is_online_enabled boolean,
  is_ghost_mode boolean,
  last_seen timestamp with time zone,
  is_truly_active boolean
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  SELECT
    p.id,
    p.full_name,
    p.username,
    p.avatar_url,
    pr.online,
    COALESCE(p.is_online_enabled, true),
    COALESCE(p.is_ghost_mode, false),
    p.last_seen,
    pr.online
  FROM (
    SELECT x.id, x.full_name, x.username, x.avatar_url,
           x.is_online_enabled, x.is_ghost_mode, x.last_seen
    FROM public.profiles x
    WHERE x.is_online = true
      AND x.last_seen > now() - interval '3 minutes'
      AND (p_exclude_user_id IS NULL OR x.id <> p_exclude_user_id)
  ) p
  CROSS JOIN LATERAL public.presence_resolve(p.id, 'chat') pr
  WHERE pr.online
  ORDER BY p.last_seen DESC NULLS LAST
  LIMIT 100;
$function$;

-- -----------------------------------------------------------------------------
-- 7) "YAZIYOR…" kanalı
-- -----------------------------------------------------------------------------
-- Gizli anahtar istemciye kapalı tek satırlık tabloda durur (yalnız SECURITY
-- DEFINER fonksiyonlar okur). Sızarsa kanal adları türetilebilir; bu yüzden
-- REVOKE + RLS açık + politika yok.
CREATE TABLE IF NOT EXISTS public.chat_typing_secret (
  id     boolean PRIMARY KEY DEFAULT true CHECK (id),
  secret text    NOT NULL DEFAULT encode(extensions.gen_random_bytes(32), 'hex')
);

ALTER TABLE public.chat_typing_secret ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.chat_typing_secret FROM PUBLIC, anon, authenticated;
GRANT ALL ON public.chat_typing_secret TO service_role;

INSERT INTO public.chat_typing_secret (id) VALUES (true) ON CONFLICT (id) DO NOTHING;

COMMENT ON TABLE public.chat_typing_secret IS
  '"Yazıyor…" kanal adlarını HMAC ile türeten gizli anahtar. İstemciye kapalı; yalnız get_typing_channel / get_group_typing_channel okur.';

-- Birebir sohbet: {topic, send}. topic NULL ise özellik yok/kapalı/engelli ve
-- istemci hiç abone olmaz. send=false ise kullanıcı kendi "yazıyor" bilgisini
-- paylaşmak istemiyor (yine de karşıdakini görebilir).
CREATE OR REPLACE FUNCTION public.get_typing_channel(p_peer uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $fn$
DECLARE
  v_me     uuid := (SELECT auth.uid());
  v_secret text;
  v_send   boolean;
BEGIN
  IF v_me IS NULL
     OR p_peer IS NULL
     OR p_peer = v_me
     OR NOT COALESCE((public.chat_presence_cfg() ->> 'typing')::boolean, true)
     OR public.social_block_exists(p_peer) THEN
    RETURN jsonb_build_object('topic', NULL::text, 'send', false);
  END IF;

  SELECT s.secret INTO v_secret FROM public.chat_typing_secret s LIMIT 1;
  SELECT COALESCE(pr.show_typing_indicator, true) INTO v_send
  FROM public.profiles pr WHERE pr.id = v_me;

  RETURN jsonb_build_object(
    'topic', 'typing:' || encode(
      extensions.hmac(
        least(v_me::text, p_peer::text) || '|' || greatest(v_me::text, p_peer::text),
        v_secret,
        'sha256'
      ),
      'hex'
    ),
    'send', COALESCE(v_send, true)
  );
END;
$fn$;

REVOKE ALL ON FUNCTION public.get_typing_channel(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_typing_channel(uuid) TO authenticated, service_role;

-- Grup sohbeti: yalnız üyeye ve yalnız admin grup göstergesini açtıysa.
CREATE OR REPLACE FUNCTION public.get_group_typing_channel(p_group_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $fn$
DECLARE
  v_me     uuid := (SELECT auth.uid());
  v_cfg    jsonb := public.chat_presence_cfg();
  v_secret text;
  v_send   boolean;
BEGIN
  IF v_me IS NULL
     OR p_group_id IS NULL
     OR NOT COALESCE((v_cfg ->> 'typing')::boolean, true)
     OR NOT COALESCE((v_cfg ->> 'typing_in_groups')::boolean, true)
     OR NOT public.is_group_member(p_group_id, v_me) THEN
    RETURN jsonb_build_object('topic', NULL::text, 'send', false);
  END IF;

  SELECT s.secret INTO v_secret FROM public.chat_typing_secret s LIMIT 1;
  SELECT COALESCE(pr.show_typing_indicator, true) INTO v_send
  FROM public.profiles pr WHERE pr.id = v_me;

  RETURN jsonb_build_object(
    'topic', 'typing_g:' || encode(
      extensions.hmac(p_group_id::text, v_secret, 'sha256'),
      'hex'
    ),
    'send', COALESCE(v_send, true)
  );
END;
$fn$;

REVOKE ALL ON FUNCTION public.get_group_typing_channel(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_group_typing_channel(uuid) TO authenticated, service_role;

-- -----------------------------------------------------------------------------
-- 8) Kullanıcının kendi sohbet gizliliği
-- -----------------------------------------------------------------------------
-- Yalnız çağıranın satırını, yalnız bu üç alanı değiştirir. Mevcut
-- update_my_privacy_settings'e dokunulmaz (o her çağrıda last_seen'i de
-- güncelliyor; bir gizlilik seçimi "şimdi aktifti" izi bırakmasın).
CREATE OR REPLACE FUNCTION public.update_my_chat_privacy(
  p_show_last_seen         boolean DEFAULT NULL,
  p_last_seen_friends_only boolean DEFAULT NULL,
  p_show_typing_indicator  boolean DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $fn$
DECLARE
  v_uid uuid := (SELECT auth.uid());
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'update_my_chat_privacy: not authenticated'
      USING ERRCODE = '28000';
  END IF;

  UPDATE public.profiles
  SET
    show_last_seen         = COALESCE(p_show_last_seen, show_last_seen),
    last_seen_friends_only = COALESCE(p_last_seen_friends_only, last_seen_friends_only),
    show_typing_indicator  = COALESCE(p_show_typing_indicator, show_typing_indicator)
  WHERE id = v_uid;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'update_my_chat_privacy: profile not found'
      USING ERRCODE = 'P0002';
  END IF;
END;
$fn$;

REVOKE ALL ON FUNCTION public.update_my_chat_privacy(boolean, boolean, boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.update_my_chat_privacy(boolean, boolean, boolean)
  TO authenticated, service_role;

-- -----------------------------------------------------------------------------
-- 9) Admin
-- -----------------------------------------------------------------------------
-- Tek yazım noktası: anahtar beyaz listesi + değer doğrulaması. (app_settings'e
-- doğrudan upsert de admin için mümkün ama "süre = -5" gibi çöp değeri
-- engellemez.) Güncel ayarları döner.
CREATE OR REPLACE FUNCTION public.admin_set_chat_presence_setting(
  p_key   text,
  p_value text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $fn$
DECLARE
  v_value text := lower(btrim(COALESCE(p_value, '')));
BEGIN
  IF NOT public.auth_is_admin() THEN
    RAISE EXCEPTION 'admin_set_chat_presence_setting: admin required'
      USING ERRCODE = '42501';
  END IF;

  IF p_key IN (
       'chat_presence_last_seen_enabled', 'chat_presence_last_seen_in_chat',
       'chat_presence_last_seen_in_profile', 'chat_presence_online_enabled',
       'chat_presence_typing_enabled', 'chat_presence_typing_in_groups'
     ) THEN
    IF v_value NOT IN ('true', 'false') THEN
      RAISE EXCEPTION 'admin_set_chat_presence_setting: % must be true or false', p_key
        USING ERRCODE = '22023';
    END IF;
  ELSIF p_key = 'chat_presence_last_seen_max_days' THEN
    IF v_value !~ '^[0-9]{1,3}$' OR v_value::integer NOT BETWEEN 1 AND 365 THEN
      RAISE EXCEPTION 'admin_set_chat_presence_setting: days must be 1-365'
        USING ERRCODE = '22023';
    END IF;
  ELSE
    RAISE EXCEPTION 'admin_set_chat_presence_setting: unknown key %', p_key
      USING ERRCODE = '22023';
  END IF;

  INSERT INTO public.app_settings (key, value, updated_at)
  VALUES (p_key, to_jsonb(v_value), now())
  ON CONFLICT (key) DO UPDATE
    SET value = EXCLUDED.value, updated_at = now();

  RETURN public.chat_presence_cfg();
END;
$fn$;

REVOKE ALL ON FUNCTION public.admin_set_chat_presence_setting(text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_set_chat_presence_setting(text, text)
  TO authenticated, service_role;

-- Admin ekranındaki özet kutuları: kullanıcılar bu özellikleri nasıl kullanıyor.
-- Bot vitrin hesapları sayılmaz.
CREATE OR REPLACE FUNCTION public.admin_chat_presence_stats()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $fn$
BEGIN
  IF NOT public.auth_is_admin() THEN
    RAISE EXCEPTION 'admin_chat_presence_stats: admin required'
      USING ERRCODE = '42501';
  END IF;

  RETURN (
    SELECT jsonb_build_object(
      'total',             count(*),
      'last_seen_hidden',  count(*) FILTER (WHERE NOT COALESCE(p.show_last_seen, true)),
      'last_seen_friends', count(*) FILTER (WHERE COALESCE(p.show_last_seen, true)
                                              AND COALESCE(p.last_seen_friends_only, false)),
      'typing_off',        count(*) FILTER (WHERE NOT COALESCE(p.show_typing_indicator, true)),
      'ghost',             count(*) FILTER (WHERE COALESCE(p.is_ghost_mode, false)),
      'online_off',        count(*) FILTER (WHERE NOT COALESCE(p.is_online_enabled, true)),
      'online_now',        count(*) FILTER (WHERE COALESCE(p.is_online, false)
                                              AND p.last_seen > now() - interval '3 minutes')
    )
    FROM public.profiles p
    WHERE NOT COALESCE(p.is_bot, false)
  );
END;
$fn$;

REVOKE ALL ON FUNCTION public.admin_chat_presence_stats() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_chat_presence_stats() TO authenticated, service_role;

NOTIFY pgrst, 'reload schema';

commit;
