-- ============================================================================
-- 20260810000003_package_delivery_no_confirmation_and_auto_route.sql
-- ----------------------------------------------------------------------------
-- AMAÇ: Paket (courier_requests) teslimat akışını kullanıcının istediği hâle
-- getirmek — gönderici ONAY adımı yok, kurye doğrudan teslimi tamamlar; ayrıca
-- paket OLUŞTURULUNCA en uygun online kuryeye otomatik bildirim (yönlendirme).
--
-- İSTENEN AKIŞ:
--   Paket oluşur -> en uygun ONLINE kuryeye push bildirimi (route_new_package_request)
--   -> kurye KABUL eder (accept_package_request, zaten göndericiyi bildiriyor)
--   -> kurye paketi alır -> TESLİM EDER (complete_package_delivery, onaysız)
--   -> göndericiye "teslim edildi" bildirimi + kuryeye kazanç/delivered_count.
--   Gönderici onayı (request_package_delivery_confirmation + confirm_package_delivery)
--   artık UI'dan çağrılmaz; fonksiyonlar DB'de kalır (zararsız).
--
-- NEDEN İZOLE RPC'ler: create_package_request 5 kez yeniden tanımlandı (drift).
-- Ona dokunmak yerine oluşturma-sonrası ayrı bir route RPC ve kurye-taraflı
-- complete RPC ekliyoruz — düşük risk, tam idempotent.
--
-- MEVCUT (korunan) davranışlar:
--   * accept_package_request      -> kabul anında göndericiye bildirim (0809000004)
--   * reject_package_request      -> sıradaki uygun kuryeyi bul + bildir (0809000004)
--   * send-courier-package-email  -> kurye kabul edince email (edge function)
-- ============================================================================

-- -----------------------------------------------------------------------------
-- 1) route_new_package_request: oluşturma anında en uygun online kuryeye bildirim
-- -----------------------------------------------------------------------------
-- reject_package_request'in "en uygun kuryeyi bul + bildir" mantığını oluşturma
-- anında çalıştırır. Paket pending/courier_id=NULL olarak havuzda kalır; kurye
-- yine accept_package_request ile açıkça KABUL eder ("kuryeci onayı alınca").
-- Email göndermez (email yalnız kabul anında, mevcut edge function ile).
DROP FUNCTION IF EXISTS public.route_new_package_request(uuid);

CREATE FUNCTION public.route_new_package_request(p_request_id uuid)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_uid        CONSTANT uuid := (SELECT auth.uid());
  v_rec        public.courier_requests%ROWTYPE;
  v_courier_id uuid;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'APP:auth_required' USING ERRCODE = '42501';
  END IF;
  IF p_request_id IS NULL THEN
    RAISE EXCEPTION 'APP:request_id_required' USING ERRCODE = '22023';
  END IF;

  SELECT cr.* INTO v_rec
  FROM public.courier_requests AS cr
  WHERE cr.id = p_request_id
  FOR UPDATE;

  IF v_rec.id IS NULL THEN
    RAISE EXCEPTION 'APP:not_found' USING ERRCODE = 'P0001';
  END IF;

  -- Yalnız paket sahibi (gönderici) yönlendirmeyi tetikleyebilir.
  IF v_rec.sender_id <> v_uid THEN
    RAISE EXCEPTION 'APP:forbidden' USING ERRCODE = '42501';
  END IF;

  -- Yalnız bekleyen ve kuryesiz paketler yönlendirilir; aksi halde no-op.
  IF v_rec.status <> 'pending' OR v_rec.courier_id IS NOT NULL THEN
    RETURN 0;
  END IF;

  -- Dedup: aynı paket için zaten yönlendirme bildirimi atıldıysa tekrar atma
  -- (broadcast_order_to_couriers deseni).
  IF EXISTS (
    SELECT 1 FROM public.notifications n
    WHERE n.entity_id = p_request_id::text AND n.type = 'package_route'
  ) THEN
    RETURN 0;
  END IF;

  -- En uygun ONLINE kurye: online优先, en az teslimatlı, gönderici değil.
  SELECT p.id INTO v_courier_id
  FROM public.profiles AS p
  WHERE p.role = 'courier'::public.user_role
    AND COALESCE(p.is_online, false) = true
    AND p.id <> v_rec.sender_id
  ORDER BY COALESCE(p.delivered_count, 0) ASC, p.id
  LIMIT 1;

  -- Online kurye yoksa paket havuzda kalır (kuryeler list_available ile alınca
  -- kabul edebilir); bildirim atmadan dön.
  IF v_courier_id IS NULL THEN
    RETURN 0;
  END IF;

  PERFORM public.add_notification(
    p_user_id   => v_courier_id,
    p_type      => 'package_route',
    p_title     => '📦 Yeni Paket Talebi',
    p_content   => 'Bir paket talebi size yönlendirildi. Kurye panelinden inceleyebilirsiniz.',
    p_entity_id => p_request_id::text
  );

  RETURN 1;
END;
$$;

REVOKE ALL ON FUNCTION public.route_new_package_request(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.route_new_package_request(uuid) TO authenticated;

COMMENT ON FUNCTION public.route_new_package_request(uuid) IS
  'Paket oluşturulduğunda en uygun online kuryeye push bildirimi atar (otomatik yönlendirme). Paket havuzda kalır; kurye accept_package_request ile kabul eder. Email göndermez (email kabul anında). Aynı paket için dedup.';

-- -----------------------------------------------------------------------------
-- 2) complete_package_delivery: kurye doğrudan teslimi tamamlar (onaysız)
-- -----------------------------------------------------------------------------
-- confirm_package_delivery (02000005 satır 761-841) gövdesinin birebir kopyası;
-- TEK fark yetki: gönderici yerine ATANAN KURYE (courier_id = auth.uid()) çağırır.
-- Kurye "Teslim Ettim" der; sunucu atomik olarak delivered + idempotent earnings +
-- delivered_count++ + göndericiye "teslim edildi" bildirimi. Kuryeye ayrıca bildirim
-- atmaz (sipari�� akışı complete_order_delivery ile tutarlı; kurye zaten biliyor).
DROP FUNCTION IF EXISTS public.complete_package_delivery(uuid);

CREATE FUNCTION public.complete_package_delivery(p_request_id uuid)
RETURNS TABLE(
  request_id uuid,
  earning_id uuid,
  amount numeric,
  status text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_uid     CONSTANT uuid := (SELECT auth.uid());
  v_rec     public.courier_requests%ROWTYPE;
  v_earn_id uuid;
  v_amount  numeric(12, 2);
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'APP:auth_required' USING ERRCODE = '42501';
  END IF;

  SELECT cr.* INTO v_rec
  FROM public.courier_requests AS cr
  WHERE cr.id = p_request_id
  FOR UPDATE;

  IF v_rec.id IS NULL THEN
    RAISE EXCEPTION 'APP:not_found' USING ERRCODE = 'P0001';
  END IF;

  -- Yalnız ATANAN KURYE veya admin (gönderici onayı kaldırıldı).
  IF NOT (v_rec.courier_id = v_uid OR public.is_admin()) THEN
    RAISE EXCEPTION 'APP:forbidden | yalnız atanmış kurye veya admin' USING ERRCODE = '42501';
  END IF;

  IF v_rec.status NOT IN ('accepted', 'delivery_pending_confirmation') THEN
    RAISE EXCEPTION 'APP:invalid_state | durum: %', v_rec.status USING ERRCODE = 'P0001';
  END IF;
  IF v_rec.courier_id IS NULL THEN
    RAISE EXCEPTION 'APP:no_courier' USING ERRCODE = 'P0001';
  END IF;

  v_amount := COALESCE(v_rec.courier_fee, 0);

  UPDATE public.courier_requests AS cr
     SET status = 'delivered',
         delivered_at = now(),
         delivery_confirmed_at = now(),
         delivery_confirmed_by = v_uid
   WHERE cr.id = p_request_id;

  -- Idempotent earnings insert (package_request_id partial unique index bağımlılığı)
  INSERT INTO public.courier_earnings (
    courier_id, package_request_id, amount, amount_snapshot, status
  ) VALUES (
    v_rec.courier_id, p_request_id, v_amount, v_amount, 'pending'
  )
  ON CONFLICT (package_request_id) WHERE package_request_id IS NOT NULL DO NOTHING
  RETURNING id INTO v_earn_id;

  IF v_earn_id IS NULL THEN
    SELECT ce.id INTO v_earn_id
    FROM public.courier_earnings AS ce
    WHERE ce.package_request_id = p_request_id
    LIMIT 1;
  END IF;

  -- delivered_count atomik artış (SECURITY DEFINER => guard trigger bypass)
  UPDATE public.profiles AS p
     SET delivered_count = p.delivered_count + 1
   WHERE p.id = v_rec.courier_id;

  -- Göndericiye (müşteriye) teslim bildirimi. Kuryeye bildirim atılmaz.
  PERFORM public.add_notification(
    p_user_id   => v_rec.sender_id,
    p_type      => 'package_delivered',
    p_title     => 'Paketiniz Teslim Edildi',
    p_content   => 'Gönderdiğiniz paket alıcısına teslim edildi.',
    p_entity_id => p_request_id::text
  );

  RETURN QUERY
  SELECT p_request_id, v_earn_id, v_amount, 'pending'::text;
END;
$$;

REVOKE ALL ON FUNCTION public.complete_package_delivery(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.complete_package_delivery(uuid) TO authenticated;

COMMENT ON FUNCTION public.complete_package_delivery(uuid) IS
  'Atanan kurye paket teslimini doğrudan (gönderici onayı olmadan) tamamlar: delivered + idempotent earnings + delivered_count++ + göndericiye teslim bildirimi. confirm_package_delivery''in kurye-yetkili karşılığı.';

-- -----------------------------------------------------------------------------
-- 3) PostgREST şema cache'ini tazele (PGRST202 bir daha çıkmasın)
-- -----------------------------------------------------------------------------
NOTIFY pgrst, 'reload schema';

-- -----------------------------------------------------------------------------
-- 4) DOĞRULAMA — 2 yeni RPC'nin varlığını gösterir
-- -----------------------------------------------------------------------------
SELECT n.nspname AS schema,
       p.proname AS function_name,
       pg_get_function_arguments(p.oid) AS args
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname IN ('route_new_package_request', 'complete_package_delivery')
ORDER BY p.proname;
