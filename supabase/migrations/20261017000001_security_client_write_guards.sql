-- ============================================================================
-- İstemci yazma korumaları: para / moderasyon / kimlik sütunları (2026-10-17)
-- ----------------------------------------------------------------------------
-- Canlı denetimde (yetki + RLS + tetikleyici okuması) bulunan açıklar:
--
-- 1) coupons: INSERT/UPDATE/DELETE politikası "auth.uid() IS NOT NULL" idi.
--    Oturum açmış herkes %100 indirimli kupon yazıp private.reprice_cart'a
--    kimliğini vererek siparişi bedavaya getirebiliyordu. → yalnız admin.
--
-- 2) shops: guard_shop_financial_columns SECURITY DEFINER idi; DEFINER
--    fonksiyonda current_user = sahip (postgres) olduğundan "istemci mi?"
--    kontrolü hep "hayır" dönüyor, koruma HİÇ çalışmıyordu. Satıcı kendi
--    dükkânında commission_rate=0, pending_payout/admin_credit şişirme,
--    is_approved/is_verified/is_pinned=true, rating=5 yapabiliyordu.
--    force_default_shop_commission_on_insert de aynı nedenle etkisizdi.
--    → INVOKER; moderasyon/istatistik sütunları da korunur.
--    Bu tetikleyiciyi etkin yapınca satıcının "teslim edildi" akışı
--    kırılmasın diye orders/payout_requests üzerindeki INVOKER bakiye
--    tetikleyicileri (update_shop_balance, clear_shop_balance) DEFINER
--    yapılır: sistem mantığıdır, çağıranın RLS'ine takılmamalı (kurye
--    yolunda RLS yüzünden sessizce 0 satır güncelleniyordu).
--
-- 3) orders: authenticated rolünün TÜM sütunlarda UPDATE yetkisi var ve
--    koruma tetikleyicisi yoktu. Müşteri kendi siparişinde payment_status,
--    total, status='delivered'; satıcı seller_credit_amount'u şişirip
--    'delivered' yaparak update_shop_balance üzerinden dükkân bakiyesine
--    para yazdırabiliyordu. → tutar/kimlik sütunları kilitli, durum
--    geçişleri role göre sınırlı. Mevcut istemci yazımları (denetlendi):
--      müşteri  : pending → cancelled (bakiye düşmezse checkout geri alma)
--      satıcı   : status (teslim dahil), courier_name, payment_status=paid
--                 (kapıda ödemeli siparişi teslim ederken)
--      kurye    : status → on_the_way
--      admin    : serbest; DEFINER RPC'ler ve service_role serbest.
--
-- 4) courier_assignments: kurye kendi satırında fee_amount'u
--    değiştirebiliyordu; complete_order_delivery kazancı bu alandan yazıyor.
--    → ücret/kimlik sütunları kilitli, 'delivered' yalnız teslim RPC'siyle.
--
-- 5) shop_reviews: shop_reviews_update_policy dükkân sahibine sütun kısıtı
--    olmadan UPDATE veriyordu → satıcı müşterinin 1 yıldızını 5 yapabiliyordu;
--    yorum sahibi de sahte "satıcı cevabı" yazabiliyordu. → satıcı yalnız
--    cevap alanlarını, yazar yalnız kendi puan/metin/gizlilik alanlarını
--    değiştirebilir (sessizce eski değere döner).
--
-- 6) Savunma: guard_payment_transaction_client_writes ve
--    private.guard_profiles_privileged_columns de DEFINER + current_user
--    kalıbındaydı. Bugün istismar edilemiyor (istemcinin bu tablolarda
--    yazma yetkisi/politikası yok) ama ileride yetki açılırsa koruma
--    çalışsın diye INVOKER yapılır. İşlevsel etkisi yok.
--
-- Kural (yeni koruma yazarken): koruma tetikleyicileri SECURITY INVOKER
-- olmalı; DEFINER RPC içinden gelen yazımda current_user = sahip olduğu için
-- otomatik serbest kalır, istemciden gelen yazımda 'authenticated'/'anon'dur.
-- ============================================================================

BEGIN;

-- ---------------------------------------------------------------------------
-- 1) coupons: yazma yalnız admin
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS coupons_insert_policy ON public.coupons;
DROP POLICY IF EXISTS coupons_update_policy ON public.coupons;
DROP POLICY IF EXISTS coupons_delete_policy ON public.coupons;

CREATE POLICY coupons_insert_policy ON public.coupons
  FOR INSERT TO authenticated
  WITH CHECK ((SELECT public.auth_is_admin()));

CREATE POLICY coupons_update_policy ON public.coupons
  FOR UPDATE TO authenticated
  USING ((SELECT public.auth_is_admin()))
  WITH CHECK ((SELECT public.auth_is_admin()));

CREATE POLICY coupons_delete_policy ON public.coupons
  FOR DELETE TO authenticated
  USING ((SELECT public.auth_is_admin()));

-- ---------------------------------------------------------------------------
-- 2) shops: finans + moderasyon sütunları
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.guard_shop_financial_columns()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path TO ''
AS $function$
declare
  -- Değişirse hata verilen finans sütunları. to_jsonb ile karşılaştırılıyor ki
  -- bir ortamda sütun yoksa fonksiyon patlamasın.
  c_protected constant text[] := array[
    'admin_credit',
    'commission_debt',
    'commission_rate',
    'digital_commission_rate',
    'total_paid',
    'pending_payout',
    'cash_payment_revenue',
    'online_payment_revenue',
    'total_collected_cash'
  ];
  v_old_row jsonb;
  v_new_row jsonb;
  v_col     text;
  v_changed text[] := '{}';
begin
  -- Sunucu bağlamı: SECURITY DEFINER RPC/tetikleyiciler (current_user = sahip)
  -- ve service_role serbest. Fonksiyon INVOKER olduğu için bu kontrol artık
  -- istemciden gelen yazımda gerçekten 'authenticated' görür.
  if current_user not in ('authenticated', 'anon') then
    return new;
  end if;

  -- Admin serbest (admin paneli bu sütunları doğrudan düzenliyor).
  if public.auth_is_admin() then
    return new;
  end if;

  -- Moderasyon / istatistik sütunları: sessizce eski değer. Hata yerine geri
  -- alma, bayat tam-satır yazımlarının (ör. puan arada değişti) kaydı
  -- kırmasını önler.
  new.owner_id          := old.owner_id;
  new.is_approved       := old.is_approved;
  new.is_verified       := old.is_verified;
  new.is_pinned         := old.is_pinned;
  new.is_active         := old.is_active;
  new.rating            := old.rating;
  new.review_count      := old.review_count;
  new.total_reviews     := old.total_reviews;
  new.total_orders      := old.total_orders;
  new.total_paid_amount := old.total_paid_amount;
  new.paid_at           := old.paid_at;

  v_old_row := to_jsonb(old);
  v_new_row := to_jsonb(new);

  foreach v_col in array c_protected loop
    if v_new_row ? v_col
       and (v_new_row -> v_col) is distinct from (v_old_row -> v_col) then
      v_changed := v_changed || v_col;
    end if;
  end loop;

  if array_length(v_changed, 1) > 0 then
    raise exception
      'Magaza finansal alanlari satici tarafindan degistirilemez: %',
      array_to_string(v_changed, ', ')
      using errcode = '42501';
  end if;

  return new;
end;
$function$;

-- system_settings'i RLS yalnız admine okutuyor; INVOKER tetikleyici oranı
-- göremezdi. Tek değer döndüren dar DEFINER yardımcı. public şemasında,
-- çünkü authenticated'ın private şemasında USAGE yetkisi yok (INVOKER
-- gövdeden çağrılıyor).
CREATE OR REPLACE FUNCTION public.default_shop_commission_rate()
RETURNS numeric
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $function$
  select nullif(value, '')::numeric
  from public.system_settings
  where key = 'admin_commission_rate'
$function$;

REVOKE ALL ON FUNCTION public.default_shop_commission_rate() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.default_shop_commission_rate() TO authenticated;

CREATE OR REPLACE FUNCTION public.force_default_shop_commission_on_insert()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path TO ''
AS $function$
begin
  if current_user not in ('authenticated', 'anon') then
    return new;
  end if;
  if public.auth_is_admin() then
    return new;
  end if;

  new.commission_rate         := coalesce(public.default_shop_commission_rate(), 10);
  new.digital_commission_rate := null;
  new.admin_credit            := 0;
  new.commission_debt         := 0;
  new.total_paid              := 0;
  new.pending_payout          := 0;
  new.cash_payment_revenue    := 0;
  new.online_payment_revenue  := 0;
  new.total_collected_cash    := 0;

  -- Moderasyon / istatistik: yeni dükkân onaysız ve sıfırdan başlar.
  new.is_approved       := false;
  new.is_verified       := false;
  new.is_pinned         := false;
  new.rating            := 0;
  new.review_count      := 0;
  new.total_reviews     := 0;
  new.total_orders      := 0;
  new.total_paid_amount := 0;
  new.paid_at           := null;
  new.can_use_own_smm_api := false;

  return new;
end;
$function$;

-- Bakiye tetikleyicileri sistem mantığıdır: çağıranın (satıcı/kurye) RLS'ine
-- ve yukarıdaki istemci korumasına takılmamalı. Girdileri (orders tutar
-- sütunları, payout_requests durumu) artık istemciden değiştirilemiyor.
ALTER FUNCTION public.update_shop_balance() SECURITY DEFINER;
ALTER FUNCTION public.clear_shop_balance() SECURITY DEFINER;
REVOKE ALL ON FUNCTION public.update_shop_balance() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.clear_shop_balance() FROM PUBLIC, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 3) orders: tutar/kimlik kilidi + rol bazlı durum geçişleri
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION private.guard_orders_client_update()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path TO ''
AS $function$
declare
  c_locked constant text[] := array[
    'id', 'order_number', 'order_number_int', 'user_id', 'shop_id',
    'subtotal', 'delivery_fee', 'discount', 'total', 'total_amount',
    'payment_method', 'coupon_id', 'coupon_discount',
    'commission_status', 'admin_commission', 'admin_delivery_fee',
    'seller_net_amount', 'commission_debt', 'commission_calculated_at',
    'seller_has_own_courier', 'seller_debt_amount', 'seller_credit_amount',
    'seller_cash_collected', 'seller_delivery_charge',
    'payment_transaction_id', 'iyzico_payment_id', 'iyzico_conversation_id',
    'payout_request_id', 'order_group_id', 'group_order_number',
    'checkout_session_id', 'committed_at', 'price_mismatch', 'is_pickup',
    'return_status', 'returned_amount',
    'assigned_courier_id', 'delivered_courier_id',
    'created_at'
  ];
  v_uid      uuid := auth.uid();
  v_old_row  jsonb;
  v_new_row  jsonb;
  v_col      text;
  v_changed  text[] := '{}';
  v_is_owner boolean;
begin
  if current_user not in ('authenticated', 'anon') then
    return new;
  end if;
  if public.auth_is_admin() then
    return new;
  end if;

  v_old_row := to_jsonb(old);
  v_new_row := to_jsonb(new);
  foreach v_col in array c_locked loop
    if (v_new_row -> v_col) is distinct from (v_old_row -> v_col) then
      v_changed := v_changed || v_col;
    end if;
  end loop;
  if array_length(v_changed, 1) > 0 then
    raise exception
      'Siparis tutar/kimlik alanlari istemciden degistirilemez: %',
      array_to_string(v_changed, ', ')
      using errcode = '42501';
  end if;

  v_is_owner := exists (
    select 1 from public.shops s
    where s.id = old.shop_id and s.owner_id = v_uid
  );

  if new.status is distinct from old.status then
    if old.status in ('delivered', 'cancelled') then
      raise exception
        'Tamamlanmis veya iptal edilmis siparisin durumu degistirilemez (% -> %)',
        old.status, new.status
        using errcode = '42501';
    end if;

    if not v_is_owner then
      if old.assigned_courier_id is not null
         and old.assigned_courier_id = v_uid
         and new.status = 'on_the_way' then
        null;  -- kurye siparişi teslim aldı
      elsif old.user_id = v_uid
            and new.status = 'cancelled'
            and old.status in ('pending', 'processing') then
        null;  -- müşteri: ödemesi tamamlanmayan siparişi geri alıyor
      else
        raise exception
          'Bu siparis durum degisikligine yetkiniz yok (% -> %)',
          old.status, new.status
          using errcode = '42501';
      end if;
    end if;
  end if;

  -- Ödeme durumu: yalnız satıcı, kapıda ödemeli siparişi teslim ederken
  -- 'paid' yapabilir. Diğer her durumda sessizce eski değer (satıcının
  -- durum güncellemesi bu yüzden kırılmasın).
  if new.payment_status is distinct from old.payment_status then
    if not (
      v_is_owner
      and new.status = 'delivered'
      and new.payment_status = 'paid'
      and old.payment_method in ('cash', 'card_on_delivery', 'cardOnDelivery')
    ) then
      new.payment_status := old.payment_status;
    end if;
  end if;

  return new;
end;
$function$;

REVOKE ALL ON FUNCTION private.guard_orders_client_update() FROM PUBLIC, anon, authenticated;

-- Adı bilerek "a_" ile başlıyor: BEFORE tetikleyicileri ada göre sırayla
-- çalışır; koruma, başka tetikleyiciler (ör. calculate_order_commission_on_total_change)
-- NEW'i değiştirmeden ÖNCE istemcinin gönderdiğini OLD ile karşılaştırmalı.
DROP TRIGGER IF EXISTS a_orders_guard_client_update ON public.orders;
CREATE TRIGGER a_orders_guard_client_update
  BEFORE UPDATE ON public.orders
  FOR EACH ROW EXECUTE FUNCTION private.guard_orders_client_update();

-- ---------------------------------------------------------------------------
-- 4) courier_assignments: ücret/kimlik kilidi, teslim yalnız RPC ile
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION private.guard_courier_assignment_client_update()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path TO ''
AS $function$
begin
  if current_user not in ('authenticated', 'anon') then
    return new;
  end if;
  if public.auth_is_admin() then
    return new;
  end if;

  if new.status is distinct from old.status then
    if old.status in ('delivered', 'cancelled') then
      raise exception
        'Tamamlanmis veya iptal edilmis kurye atamasinin durumu degistirilemez'
        using errcode = '42501';
    end if;
    if new.status = 'delivered' then
      raise exception
        'Teslimat yalnizca teslim akisi (complete_order_delivery) ile tamamlanir'
        using errcode = '42501';
    end if;
  end if;

  new.id           := old.id;
  new.order_id     := old.order_id;
  new.courier_id   := old.courier_id;
  new.fee_amount   := old.fee_amount;
  new.assigned_at  := old.assigned_at;
  new.delivered_at := old.delivered_at;
  new.created_at   := old.created_at;

  return new;
end;
$function$;

REVOKE ALL ON FUNCTION private.guard_courier_assignment_client_update() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trg_courier_assignments_guard_client_update ON public.courier_assignments;
CREATE TRIGGER trg_courier_assignments_guard_client_update
  BEFORE UPDATE ON public.courier_assignments
  FOR EACH ROW EXECUTE FUNCTION private.guard_courier_assignment_client_update();

-- ---------------------------------------------------------------------------
-- 5) shop_reviews: satıcı yalnız cevap, yazar yalnız kendi içeriği
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION private.guard_shop_review_columns()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path TO ''
AS $function$
declare
  v_uid uuid := auth.uid();
begin
  if current_user not in ('authenticated', 'anon') then
    return new;
  end if;
  if public.auth_is_admin() then
    return new;
  end if;

  new.id               := old.id;
  new.shop_id          := old.shop_id;
  new.user_id          := old.user_id;
  new.order_id         := old.order_id;
  new.digital_order_id := old.digital_order_id;
  new.created_at       := old.created_at;

  -- Yorumun sahibi değilse (satıcı yolu) puan/metin/gizlilik değişmez.
  if v_uid is distinct from old.user_id then
    new.rating       := old.rating;
    new.comment      := old.comment;
    new.is_anonymous := old.is_anonymous;
  end if;

  -- Dükkânın sahibi değilse satıcı cevabı yazamaz.
  if not exists (
    select 1 from public.shops s
    where s.id = old.shop_id and s.owner_id = v_uid
  ) then
    new.seller_reply      := old.seller_reply;
    new.seller_replied_at := old.seller_replied_at;
  end if;

  return new;
end;
$function$;

REVOKE ALL ON FUNCTION private.guard_shop_review_columns() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trg_shop_reviews_guard_columns ON public.shop_reviews;
CREATE TRIGGER trg_shop_reviews_guard_columns
  BEFORE UPDATE ON public.shop_reviews
  FOR EACH ROW EXECUTE FUNCTION private.guard_shop_review_columns();

-- ---------------------------------------------------------------------------
-- 6) Savunma: aynı DEFINER + current_user kalıbındaki iki koruma
-- ---------------------------------------------------------------------------
ALTER FUNCTION public.guard_payment_transaction_client_writes() SECURITY INVOKER;
ALTER FUNCTION private.guard_profiles_privileged_columns() SECURITY INVOKER;

COMMIT;

NOTIFY pgrst, 'reload schema';
