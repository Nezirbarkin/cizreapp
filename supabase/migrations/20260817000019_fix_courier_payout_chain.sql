-- =============================================================================
-- Kurye odeme (payout) zinciri duzeltmeleri
--
-- BULGU 1 (BIRINCIL — "admin panelinde kurye odeme onayinda hata"):
--   public.notifications uzerindeki notifications_type_check CHECK kisiti,
--   migration gecmisinde 15+ kez DROP/ADD edilmis bir beyaz listedir. En son
--   uygulanan surum 20260801000004_add_post_share_notification_type.sql'dir ve
--   "gecmiste kullanilmis TUM tiplerin birlesimi" oldugunu iddia etmesine
--   ragmen 20260723000300_add_package_notification_types.sql'deki kurye/paket
--   tiplerinin TAMAMINI listeden dusurmustur.
--t(), notific
--   Sonuc: admin_approve_courier_payouations'a
--   type = 'courier_payout_approved' ile INSERT ettigi anda
--   23514 check_violation firlatir. Hata fonksiyonun EN SON adiminda olustugu
--   icin ayni transaction'daki payout_items/earnings/payout_requests
--   guncellemeleri de geri alinir -> admin panelde "Hata: ..." goruntulenir ve
--   odeme HIC onaylanmaz.
--
--   Not: 20260801000003 kendi ALTER'ini "EXCEPTION WHEN OTHERS" ile sardigi
--   icin prod'da iki olasi durum vardir (ADD basarili / basarisiz olup
--   20260723000300'un listesi kalmis). 'courier_payout_approved' HER IKI
--   listede de yoktur; bu nedenle hata her durumda olusur.
--
--   Kisit ayrica su tipleri de reddeder (tum kurye/paket bildirim zinciri):
--     courier_payout_request, courier_payout_rejected, courier_delivered,
--     courier_assigned, new_package_request, package_delivered, package_route,
--     package_dispute_rejected, message, chat, verification_code,
--     cancellation_*, task_*, balance_topup, news_* ...
--
--   Cozum: Bildirim tipi acik uclu ve surekli buyuyen bir sozluktur; sabit
--   beyaz liste her yeni ozellikte sessiz kesinti uretmektedir (bu repoda 15
--   kez oldu). Beyaz liste yerine bicimsel bir saglik kontrolu konur.
--
-- BULGU 2 (kurye bir daha ASLA odeme isteyemez):
--   uq_courier_payout_items_earning_id, courier_payout_items(earning_id)
--   uzerinde KOSULSUZ bir UNIQUE indekstir. admin_reject_courier_payout()
--   item satirlarini silmez, yalnizca status='rejected' yapar; ilgili
--   courier_earnings satirlarini ise 'pending'e geri dondurur.
--   Kurye tekrar request_courier_payout() cagirdiginda ayni earning_id icin
--   yeni bir item INSERT edilir -> 23505 unique_violation. Reddedilen kurye
--   kalici olarak odeme isteyemez hale gelir.
--
--   Cozum: indeks kismi (partial) hale getirilir; 'rejected' item'lar denetim
--   izi olarak korunur ama tekrar talebi engellemez. Aktif (pending/paid)
--   item'lar icin tekillik — yani mukerrer odeme korumasi — aynen surer.
--
-- BULGU 3 (idempotency anahtarinin yeniden kullanimi):
--   request_courier_payout() idempotency dalinda payout'un durumuna bakmaz.
--   Reddedilmis bir payout ile ayni idempotency_key tekrar gonderilirse
--   fonksiyon o eski (rejected) payout'u "basarili" gibi doner ve kurye yeni
--   talep olusturamaz. Idempotency yalnizca hala gecerli (pending/approved)
--   payout'lar icin uygulanmalidir.
-- =============================================================================

SET search_path = public, pg_temp;
SET LOCAL lock_timeout = '5s';

-- -----------------------------------------------------------------------------
-- 1) notifications_type_check: kirilgan beyaz listeyi kaldir
-- -----------------------------------------------------------------------------
-- Tip adlari sunucu tarafi kodda uretilir (SECURITY DEFINER RPC'ler ve
-- trigger'lar). Istemci serbest metin yazamadigi icin beyaz liste guvenlik
-- siniri degil, yalnizca yazim hatasi korumasidir. Bicimsel kontrol bu amaci
-- kesinti uretmeden karsilar.
-- Ad'a degil, KOLONA gore temizle: gecmiste kisit farkli adlarla da
-- olusturulmus (20260228000003 ad kalibiyla '%type%' arayarak temizliyordu).
-- Burada 'type' kolonuna dokunan TUM CHECK kisitlari kaldirilir; aksi halde
-- eski adli bir kisit hayatta kalip ayni 23514'u uretmeye devam ederdi.
DO $cleanup$
DECLARE
  r RECORD;
BEGIN
  FOR r IN
    SELECT con.conname
    FROM pg_constraint con
    JOIN pg_class rel ON rel.oid = con.conrelid
    JOIN pg_namespace nsp ON nsp.oid = rel.relnamespace
    JOIN pg_attribute att
      ON att.attrelid = rel.oid
     AND att.attnum = ANY (con.conkey)
    WHERE nsp.nspname = 'public'
      AND rel.relname = 'notifications'
      AND con.contype = 'c'
      AND att.attname = 'type'
  LOOP
    EXECUTE format(
      'ALTER TABLE public.notifications DROP CONSTRAINT IF EXISTS %I',
      r.conname
    );
    RAISE NOTICE 'Kaldirilan bildirim tipi kisiti: %', r.conname;
  END LOOP;
END
$cleanup$;

ALTER TABLE public.notifications
  ADD CONSTRAINT notifications_type_check
  CHECK (
    type IS NOT NULL
    AND length(btrim(type)) BETWEEN 1 AND 64
  )
  NOT VALID;

-- Bilerek yalniz uzunluk kontrolu yapilir: bicim (snake_case) kontrolu eklemek,
-- gecmiste yazilmis farkli bicimdeki satirlar yuzunden VALIDATE adiminda
-- migration'i dusurebilirdi. Mevcut satirlar bu kontrolu gecer.
ALTER TABLE public.notifications
  VALIDATE CONSTRAINT notifications_type_check;

COMMENT ON CONSTRAINT notifications_type_check ON public.notifications IS
  'Bicimsel kontrol (bos olmayan, <=64 karakter). Sabit tip beyaz listesi '
  '20260817000018 ile kaldirildi: liste her yeni ozellikte guncellenmedigi '
  'icin bildirim INSERT''lerini 23514 ile sessizce dusuruyordu.';

-- -----------------------------------------------------------------------------
-- 2) courier_payout_items: reddedilen kalemler tekrar talebi engellemesin
-- -----------------------------------------------------------------------------
DROP INDEX IF EXISTS public.uq_courier_payout_items_earning_id;

CREATE UNIQUE INDEX IF NOT EXISTS uq_courier_payout_items_earning_id_active
  ON public.courier_payout_items (earning_id)
  WHERE status <> 'rejected';

COMMENT ON INDEX public.uq_courier_payout_items_earning_id_active IS
  'Bir kazanc ayni anda yalniz bir AKTIF (pending/paid) payout kalemine '
  'baglanabilir. Reddedilen kalemler denetim izi olarak kalir ve kuryenin '
  'yeniden odeme talebi olusturmasini engellemez.';

-- -----------------------------------------------------------------------------
-- 3) request_courier_payout: idempotency yalnizca gecerli payout'lar icin
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.request_courier_payout(p_idempotency_key uuid)
RETURNS TABLE(
  payout_id uuid,
  amount numeric,
  item_count integer
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_uid         CONSTANT uuid := (SELECT auth.uid());
  v_payout_id   uuid;
  v_amount      numeric(12, 2);
  v_count       integer;
  v_earning_ids uuid[];
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'APP:auth_required' USING ERRCODE = '42501';
  END IF;

  IF NOT public.is_courier_role() THEN
    RAISE EXCEPTION 'APP:forbidden' USING ERRCODE = '42501';
  END IF;

  IF p_idempotency_key IS NULL THEN
    RAISE EXCEPTION 'APP:idempotency_key_required' USING ERRCODE = '22023';
  END IF;

  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(v_uid::text, 71005)
  );

  -- Idempotency yalnizca hala gecerli payout'lar icin gecerlidir. Reddedilen
  -- bir payout'un anahtari tekrar gonderilirse yeni talep olusturulabilmelidir.
  SELECT cpr.id, cpr.amount
    INTO v_payout_id, v_amount
  FROM public.courier_payout_requests AS cpr
  WHERE cpr.courier_id = v_uid
    AND cpr.idempotency_key = p_idempotency_key
    AND cpr.status IN ('pending', 'approved')
  LIMIT 1;

  IF v_payout_id IS NOT NULL THEN
    SELECT pg_catalog.count(*)::integer
      INTO v_count
    FROM public.courier_payout_items AS cpi
    WHERE cpi.payout_id = v_payout_id;

    RETURN QUERY SELECT v_payout_id, v_amount, v_count;
    RETURN;
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.courier_payout_requests AS cpr
    WHERE cpr.courier_id = v_uid
      AND cpr.status = 'pending'
  ) THEN
    RAISE EXCEPTION 'APP:open_payout_exists | zaten bekleyen bir payout var'
      USING ERRCODE = 'P0001';
  END IF;

  SELECT
    pg_catalog.array_agg(locked.id),
    COALESCE(pg_catalog.sum(locked.amount)::numeric, 0::numeric),
    pg_catalog.count(*)::integer
  INTO v_earning_ids, v_amount, v_count
  FROM (
    SELECT ce.id, ce.amount
    FROM public.courier_earnings AS ce
    WHERE ce.courier_id = v_uid
      AND ce.status = 'pending'
    ORDER BY ce.id
    FOR UPDATE
  ) AS locked;

  IF v_count = 0 THEN
    RAISE EXCEPTION 'APP:no_pending_earnings' USING ERRCODE = 'P0001';
  END IF;

  INSERT INTO public.courier_payout_requests (
    courier_id, amount, status, requested_at, idempotency_key
  ) VALUES (
    v_uid, v_amount, 'pending', pg_catalog.now(), p_idempotency_key
  )
  RETURNING id INTO v_payout_id;

  INSERT INTO public.courier_payout_items (
    payout_id, earning_id, amount_snapshot, status
  )
  SELECT v_payout_id, ce.id, ce.amount, 'pending'
  FROM public.courier_earnings AS ce
  WHERE ce.id = ANY(v_earning_ids);

  UPDATE public.courier_earnings AS ce
  SET status = 'requested'
  WHERE ce.id = ANY(v_earning_ids);

  INSERT INTO public.notifications (
    user_id, type, title, content, metadata, is_read
  )
  SELECT
    p.id,
    'courier_payout_request',
    'Yeni kurye odeme istegi',
    'Bir kurye odeme istegi gonderdi.',
    pg_catalog.jsonb_build_object(
      'courier_id', v_uid,
      'amount', v_amount,
      'payout_id', v_payout_id
    ),
    false
  FROM public.profiles AS p
  WHERE p.role::text = 'admin';

  RETURN QUERY SELECT v_payout_id, v_amount, v_count;
END;
$$;

REVOKE ALL ON FUNCTION public.request_courier_payout(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.request_courier_payout(uuid) TO authenticated;

COMMENT ON FUNCTION public.request_courier_payout(uuid) IS
  'Kimligi dogrulanmis kuryenin pending kazanc satirlarindan atomik ve '
  'idempotent odeme istegi olusturur. Idempotency yalnizca pending/approved '
  'payout''lar icin uygulanir; reddedilen talep yeniden gonderilebilir.';

-- -----------------------------------------------------------------------------
-- 4) admin_approve_courier_payout: idempotent + sema-nitelikli + tutar tutarli
-- -----------------------------------------------------------------------------
-- Degisiklikler:
--   * Zaten 'approved' olan payout icin sessizce basarili don (cift tiklama /
--     ag yeniden denemesi admin'e sahte hata gostermesin).
--   * SET search_path = '' altinda now()/jsonb_build_object/coalesce cagrilari
--     pg_catalog ile nitelendirildi.
--   * Bildirim tutari, header yerine gercekten odenen kalemlerin toplamindan
--     alinir (header ile item'lar arasindaki olasi drift'i maskelemez).
CREATE OR REPLACE FUNCTION public.admin_approve_courier_payout(
  p_payout_id uuid,
  p_payment_reference text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_payout public.courier_payout_requests%ROWTYPE;
  v_paid   numeric(12, 2);
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'APP:forbidden | admin gerekli' USING ERRCODE = '42501';
  END IF;
  IF p_payout_id IS NULL THEN
    RAISE EXCEPTION 'APP:payout_id_required' USING ERRCODE = '22023';
  END IF;

  SELECT cpr.* INTO v_payout
  FROM public.courier_payout_requests AS cpr
  WHERE cpr.id = p_payout_id
  FOR UPDATE;

  IF v_payout.id IS NULL THEN
    RAISE EXCEPTION 'APP:not_found' USING ERRCODE = 'P0001';
  END IF;

  -- Idempotent: ayni payout ikinci kez onaylanirsa hata uretme.
  IF v_payout.status = 'approved' THEN
    RETURN;
  END IF;

  IF v_payout.status <> 'pending' THEN
    RAISE EXCEPTION 'APP:invalid_state | durum: %', v_payout.status
      USING ERRCODE = 'P0001';
  END IF;

  UPDATE public.courier_payout_items AS cpi
     SET status = 'paid'
   WHERE cpi.payout_id = p_payout_id;

  UPDATE public.courier_earnings AS ce
     SET status = 'paid'
   WHERE ce.id IN (
     SELECT cpi.earning_id
     FROM public.courier_payout_items AS cpi
     WHERE cpi.payout_id = p_payout_id
   );

  SELECT COALESCE(pg_catalog.sum(cpi.amount_snapshot), 0)::numeric(12, 2)
    INTO v_paid
  FROM public.courier_payout_items AS cpi
  WHERE cpi.payout_id = p_payout_id;

  UPDATE public.courier_payout_requests AS cpr
     SET status = 'approved',
         approved_at = pg_catalog.now(),
         approved_by = (SELECT auth.uid()),
         payment_reference = p_payment_reference
   WHERE cpr.id = p_payout_id;

  INSERT INTO public.notifications (
    user_id, type, title, content, metadata, is_read
  )
  VALUES (
    v_payout.courier_id,
    'courier_payout_approved',
    'Odemeniz onaylandi',
    'Odeme talebiniz admin tarafindan onaylandi.',
    pg_catalog.jsonb_build_object(
      'payout_id', p_payout_id,
      'reference', p_payment_reference,
      'amount', v_paid
    ),
    false
  );
END;
$$;

REVOKE ALL ON FUNCTION public.admin_approve_courier_payout(uuid, text)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_approve_courier_payout(uuid, text)
  TO authenticated;

-- -----------------------------------------------------------------------------
-- 5) admin_reject_courier_payout: sema-nitelikli + idempotent
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_reject_courier_payout(
  p_payout_id uuid,
  p_reason text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_payout public.courier_payout_requests%ROWTYPE;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'APP:forbidden | admin gerekli' USING ERRCODE = '42501';
  END IF;
  IF p_payout_id IS NULL THEN
    RAISE EXCEPTION 'APP:payout_id_required' USING ERRCODE = '22023';
  END IF;

  SELECT cpr.* INTO v_payout
  FROM public.courier_payout_requests AS cpr
  WHERE cpr.id = p_payout_id
  FOR UPDATE;

  IF v_payout.id IS NULL THEN
    RAISE EXCEPTION 'APP:not_found' USING ERRCODE = 'P0001';
  END IF;

  IF v_payout.status = 'rejected' THEN
    RETURN;
  END IF;

  IF v_payout.status <> 'pending' THEN
    RAISE EXCEPTION 'APP:invalid_state | durum: %', v_payout.status
      USING ERRCODE = 'P0001';
  END IF;

  UPDATE public.courier_payout_items AS cpi
     SET status = 'rejected'
   WHERE cpi.payout_id = p_payout_id;

  UPDATE public.courier_earnings AS ce
     SET status = 'pending'
   WHERE ce.id IN (
     SELECT cpi.earning_id
     FROM public.courier_payout_items AS cpi
     WHERE cpi.payout_id = p_payout_id
   );

  UPDATE public.courier_payout_requests AS cpr
     SET status = 'rejected',
         rejected_at = pg_catalog.now(),
         rejection_reason = p_reason
   WHERE cpr.id = p_payout_id;

  INSERT INTO public.notifications (
    user_id, type, title, content, metadata, is_read
  )
  VALUES (
    v_payout.courier_id,
    'courier_payout_rejected',
    'Odeme isteginiz reddedildi',
    'Gerekce: ' || COALESCE(p_reason, '-'),
    pg_catalog.jsonb_build_object('payout_id', p_payout_id, 'reason', p_reason),
    false
  );
END;
$$;

REVOKE ALL ON FUNCTION public.admin_reject_courier_payout(uuid, text)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_reject_courier_payout(uuid, text)
  TO authenticated;

NOTIFY pgrst, 'reload schema';
