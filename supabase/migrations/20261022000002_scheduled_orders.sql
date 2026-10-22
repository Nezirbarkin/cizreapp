-- =============================================================================
-- Randevulu sipariş (2026-10-22)
--
-- Müşteri checkout'ta "Hemen" yerine ileri bir saat (randevu) seçebilir; Gel Al
-- siparişinde bu "teslim alma saati" olur. Kapıda nakit/kart, bakiye ve online
-- ödemenin üçünde de çalışır.
--
--   * Admin: app_about_settings.scheduled_orders_enabled (global anahtar) ve
--     scheduled_courier_lead_minutes (randevulu sipariş kurye havuzuna saatinden
--     kaç dk önce düşer). Dükkan bazında shops.scheduled_orders_admin_blocked
--     (satıcı değiştiremez — guard_shop_financial_columns geri alır).
--   * Satıcı: shops.scheduled_orders_enabled, scheduled_slot_minutes (15/30/60/120),
--     scheduled_max_days (0 = yalnız bugün … 14), scheduled_min_lead_minutes.
--   * Saatler TEK yerde üretilir: public.get_shop_schedule_slots(shop) — Türkiye
--     saati, shops.working_hours (gece yarısını aşan kapanış dahil; tanımsızsa
--     09:00-22:00), slot hizası, hazırlık süresi. İstemci saatleri buradan alır.
--   * orders.scheduled_for: BEFORE INSERT tetikleyicisi doğrular. İstemci
--     eklemesinde geçersizse anlaşılır hata; sunucu bağlamında (online ödeme
--     geri çağrısı — para çekilmiş) ASLA hata vermez: geçmişte kalmış ya da artık
--     izin verilmeyen randevu NULL'a (hemen teslim) çevrilir.
--   * Kurye: get_available_orders_for_courier randevulu siparişi saatine
--     lead dk kalana kadar göstermez (ve scheduled_for döndürür);
--     assign_order_to_courier admin dışında erken atamayı reddeder
--     (APP:scheduled_too_early). Admin yönlendirmesi ve RLS değişmedi.
--   * Online: complete_online_payment order_data.scheduled_for'u yazar.
--   * Hatırlatma: pg_cron (5 dk) saati 60 dk kalan randevulu sipariş için
--     satıcıya bir kez bildirim (orders.scheduled_reminder_sent_at).
-- =============================================================================

begin;

set local lock_timeout = '10s';

-- -----------------------------------------------------------------------------
-- 1) Sütunlar
-- -----------------------------------------------------------------------------
alter table public.app_about_settings
  add column if not exists scheduled_orders_enabled boolean not null default false,
  add column if not exists scheduled_courier_lead_minutes integer not null default 60;

alter table public.shops
  add column if not exists scheduled_orders_enabled       boolean not null default false,
  add column if not exists scheduled_slot_minutes         integer not null default 60,
  add column if not exists scheduled_max_days             integer not null default 3,
  add column if not exists scheduled_min_lead_minutes     integer not null default 60,
  add column if not exists scheduled_orders_admin_blocked boolean not null default false;

alter table public.orders
  add column if not exists scheduled_for              timestamptz,
  add column if not exists scheduled_reminder_sent_at timestamptz;

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'shops_scheduled_settings_chk') then
    alter table public.shops add constraint shops_scheduled_settings_chk check (
      scheduled_slot_minutes in (15, 30, 60, 120)
      and scheduled_max_days between 0 and 14
      and scheduled_min_lead_minutes between 0 and 1440
    );
  end if;
  if not exists (select 1 from pg_constraint where conname = 'app_about_scheduled_lead_chk') then
    alter table public.app_about_settings add constraint app_about_scheduled_lead_chk check (
      scheduled_courier_lead_minutes between 10 and 600
    );
  end if;
end;
$$;

create index if not exists idx_orders_scheduled_pending
  on public.orders (scheduled_for)
  where scheduled_for is not null and scheduled_reminder_sent_at is null;

comment on column public.orders.scheduled_for is
  'Randevulu sipariş: müşterinin seçtiği teslim (Gel Al''da teslim alma) zamanı; NULL = hemen.';

-- -----------------------------------------------------------------------------
-- 2) Ayar okuyucuları
-- -----------------------------------------------------------------------------
create or replace function public.scheduled_orders_globally_enabled()
returns boolean
language sql
stable
security definer
set search_path = ''
as $fn$
  select coalesce((select a.scheduled_orders_enabled
                     from public.app_about_settings a
                    order by a.id limit 1), false);
$fn$;

create or replace function public.scheduled_courier_lead_minutes()
returns integer
language sql
stable
security definer
set search_path = ''
as $fn$
  select coalesce((select a.scheduled_courier_lead_minutes
                     from public.app_about_settings a
                    order by a.id limit 1), 60);
$fn$;

revoke all on function public.scheduled_orders_globally_enabled() from public;
revoke all on function public.scheduled_courier_lead_minutes() from public;
grant execute on function public.scheduled_orders_globally_enabled() to anon, authenticated, service_role;
grant execute on function public.scheduled_courier_lead_minutes() to anon, authenticated, service_role;

-- -----------------------------------------------------------------------------
-- 3) Uygun saatler (tek doğruluk kaynağı)
--    p_grace: hazırlık süresinden düşülecek tolerans (doğrulamada seçim ile
--    onay arasında geçen süre için).
-- -----------------------------------------------------------------------------
create or replace function public.get_shop_schedule_slots(
  p_shop_id uuid,
  p_grace   interval default interval '0'
)
returns table(slot_at timestamptz)
language plpgsql
stable
security definer
set search_path = ''
as $fn$
declare
  v_shop      record;
  v_tz        constant text := 'Europe/Istanbul';
  v_today     date;
  v_earliest  timestamptz;
  v_day       date;
  v_wh        jsonb;
  v_open      text;
  v_close     text;
  v_open_t    time;
  v_close_t   time;
  v_start     timestamptz;
  v_end       timestamptz;
  v_t         timestamptz;
  v_step      interval;
  v_count     integer := 0;
  v_dayname   text;
begin
  if not public.scheduled_orders_globally_enabled() then
    return;
  end if;

  select s.id, s.working_hours, s.scheduled_orders_enabled, s.scheduled_orders_admin_blocked,
         s.scheduled_slot_minutes, s.scheduled_max_days, s.scheduled_min_lead_minutes
    into v_shop
    from public.shops s
   where s.id = p_shop_id;

  if not found
     or not coalesce(v_shop.scheduled_orders_enabled, false)
     or coalesce(v_shop.scheduled_orders_admin_blocked, false) then
    return;
  end if;

  v_step     := make_interval(mins => coalesce(v_shop.scheduled_slot_minutes, 60));
  v_today    := (now() at time zone v_tz)::date;
  v_earliest := now() + make_interval(mins => coalesce(v_shop.scheduled_min_lead_minutes, 60))
                - coalesce(p_grace, interval '0');

  -- Dünden başla: dünün gece yarısını aşan çalışma aralığı bugüne taşabilir.
  for i in -1 .. coalesce(v_shop.scheduled_max_days, 3) loop
    v_day := v_today + i;
    v_dayname := case extract(isodow from v_day)::int
      when 1 then 'monday' when 2 then 'tuesday' when 3 then 'wednesday'
      when 4 then 'thursday' when 5 then 'friday' when 6 then 'saturday'
      else 'sunday' end;

    if v_shop.working_hours is null
       or jsonb_typeof(v_shop.working_hours) <> 'object'
       or v_shop.working_hours = '{}'::jsonb then
      v_open := '09:00';
      v_close := '22:00';
    else
      v_wh := v_shop.working_hours -> v_dayname;
      if v_wh is null or jsonb_typeof(v_wh) <> 'object' then
        continue;  -- o gün tanımsız → kapalı
      end if;
      if lower(coalesce(v_wh ->> 'active', 'true')) in ('false', 'f', '0') then
        continue;
      end if;
      v_open := v_wh ->> 'open';
      v_close := v_wh ->> 'close';
    end if;

    if v_open is null or v_close is null
       or v_open !~ '^\d{1,2}:\d{2}$' or v_close !~ '^\d{1,2}:\d{2}$' then
      continue;
    end if;
    begin
      v_open_t := v_open::time;
      v_close_t := v_close::time;
    exception when others then
      continue;
    end;

    v_start := (v_day + v_open_t) at time zone v_tz;
    v_end := (v_day + v_close_t) at time zone v_tz;
    if v_end <= v_start then
      v_end := v_end + interval '1 day';  -- 22:00 - 02:00 gibi
    end if;

    v_t := v_start;
    while v_t + v_step <= v_end loop
      -- Son gün sınırı: en fazla scheduled_max_days gün ilerisi (yerel takvim).
      exit when (v_t at time zone v_tz)::date > v_today + coalesce(v_shop.scheduled_max_days, 3);
      if v_t >= v_earliest then
        slot_at := v_t;
        return next;
        v_count := v_count + 1;
        if v_count >= 400 then
          return;
        end if;
      end if;
      v_t := v_t + v_step;
    end loop;
  end loop;
end;
$fn$;

revoke all on function public.get_shop_schedule_slots(uuid, interval) from public;
grant execute on function public.get_shop_schedule_slots(uuid, interval) to anon, authenticated, service_role;

comment on function public.get_shop_schedule_slots(uuid, interval) is
  'Randevulu sipariş için seçilebilir saatler (artan). Global anahtar/dükkan kapalıysa boş.';

-- Hata metni ya da NULL (geçerli).
create or replace function public.validate_scheduled_order_slot(
  p_shop_id uuid,
  p_at      timestamptz
)
returns text
language plpgsql
stable
security definer
set search_path = ''
as $fn$
declare
  v_enabled boolean;
  v_blocked boolean;
begin
  if p_at is null then
    return null;
  end if;
  if not public.scheduled_orders_globally_enabled() then
    return 'Randevulu sipariş şu an kullanılamıyor.';
  end if;
  select s.scheduled_orders_enabled, s.scheduled_orders_admin_blocked
    into v_enabled, v_blocked
    from public.shops s where s.id = p_shop_id;
  if not found or not coalesce(v_enabled, false) or coalesce(v_blocked, false) then
    return 'Bu dükkan randevulu sipariş almıyor.';
  end if;
  -- Seçimden onaya kadar geçen süre için 10 dk tolerans.
  if not exists (
    select 1 from public.get_shop_schedule_slots(p_shop_id, interval '10 minutes') g
     where g.slot_at = p_at
  ) then
    return 'Seçtiğiniz randevu saati artık uygun değil, lütfen başka bir saat seçin.';
  end if;
  return null;
end;
$fn$;

revoke all on function public.validate_scheduled_order_slot(uuid, timestamptz) from public;
grant execute on function public.validate_scheduled_order_slot(uuid, timestamptz)
  to anon, authenticated, service_role;

-- -----------------------------------------------------------------------------
-- 4) Sipariş eklerken doğrulama (INVOKER: current_user istemciyi gösterir)
-- -----------------------------------------------------------------------------
create or replace function public.orders_validate_scheduled_for()
returns trigger
language plpgsql
set search_path = ''
as $fn$
declare
  v_err text;
begin
  if new.scheduled_for is null then
    return new;
  end if;

  v_err := public.validate_scheduled_order_slot(new.shop_id, new.scheduled_for);
  if v_err is null then
    return new;
  end if;

  if current_user not in ('authenticated', 'anon') then
    -- Sunucu bağlamı (ör. online ödeme sonrası sipariş): ödeme alınmış
    -- siparişi asla düşürme. Hâlâ gelecekte ve dükkan randevu alıyorsa
    -- (yalnız hazırlık süresi kaçtıysa) koru; değilse hemen teslime çevir.
    if new.scheduled_for <= now()
       or v_err not like 'Seçtiğiniz randevu saati%' then
      new.scheduled_for := null;
    end if;
    return new;
  end if;

  raise exception '%', v_err
    using errcode = '22023', hint = 'scheduled_slot_invalid';
end;
$fn$;

drop trigger if exists b_orders_validate_scheduled_for on public.orders;
create trigger b_orders_validate_scheduled_for
  before insert on public.orders
  for each row
  when (new.scheduled_for is not null)
  execute function public.orders_validate_scheduled_for();

-- -----------------------------------------------------------------------------
-- 5) Satıcıya hatırlatma (pg_cron, 5 dk)
-- -----------------------------------------------------------------------------
create or replace function private.notify_due_scheduled_orders()
returns integer
language plpgsql
security definer
set search_path = ''
as $fn$
declare
  r       record;
  v_count integer := 0;
begin
  for r in
    select o.id, o.order_number, o.scheduled_for, o.is_pickup, s.owner_id
      from public.orders o
      join public.shops s on s.id = o.shop_id
     where o.scheduled_for is not null
       and o.scheduled_reminder_sent_at is null
       and o.status::text not in ('delivered', 'cancelled')
       and o.scheduled_for <= now() + interval '60 minutes'
       and o.scheduled_for > now() - interval '30 minutes'
     order by o.scheduled_for
     limit 200
     for update of o skip locked
  loop
    if r.owner_id is not null then
      insert into public.notifications (
        user_id, type, title, content, entity_id, metadata, is_read, created_at
      ) values (
        r.owner_id,
        'scheduled_order_reminder',
        '⏰ Randevulu sipariş yaklaşıyor',
        format('#%s numaralı siparişin %s saati %s.',
               coalesce(r.order_number::text, ''),
               case when r.is_pickup then 'teslim alma' else 'teslimat' end,
               to_char(r.scheduled_for at time zone 'Europe/Istanbul', 'HH24:MI')),
        r.id::text,
        jsonb_build_object('order_id', r.id, 'scheduled_for', r.scheduled_for),
        false,
        now()
      );
    end if;
    update public.orders
       set scheduled_reminder_sent_at = now()
     where id = r.id;
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$fn$;

revoke all on function private.notify_due_scheduled_orders() from public, anon, authenticated;

do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.schedule(
      'scheduled-order-reminders',
      '*/5 * * * *',
      'select private.notify_due_scheduled_orders()'
    );
  end if;
end;
$$;

-- -----------------------------------------------------------------------------
-- 6) Kurye havuzu: randevulu sipariş saatine lead dk kalana kadar görünmez
--    (dönüş tipine scheduled_for eklendiği için DROP+CREATE)
-- -----------------------------------------------------------------------------
drop function if exists public.get_available_orders_for_courier();

create function public.get_available_orders_for_courier()
returns table(
  id uuid, total numeric, shop_id uuid, shop_name text, created_at timestamptz,
  item_count bigint, shop_phone text, shop_address text, shop_latitude numeric,
  shop_longitude numeric, scheduled_for timestamptz
)
language sql
stable
security definer
set search_path = ''
as $function$
  SELECT
    o.id,
    o.total,
    o.shop_id,
    s.name,
    o.created_at,
    (
      SELECT count(*)
      FROM public.order_items AS oi
      WHERE oi.order_id = o.id
    ) AS item_count,
    s.phone,
    s.address,
    s.latitude,
    s.longitude,
    o.scheduled_for
  FROM public.orders AS o
  JOIN public.shops AS s ON s.id = o.shop_id
  WHERE o.status IN ('confirmed', 'preparing', 'ready')
    AND o.is_pickup = false
    AND COALESCE(s.has_own_courier, false) = false
    AND (
      o.scheduled_for IS NULL
      OR o.scheduled_for <= now()
           + make_interval(mins => public.scheduled_courier_lead_minutes())
    )
    AND (SELECT auth.uid()) IS NOT NULL
    AND public.is_courier_role()
    AND public.is_courier_document_approved()
    AND o.user_id IS DISTINCT FROM (SELECT auth.uid())
    AND NOT EXISTS (
      SELECT 1
      FROM public.courier_assignments AS ca
      WHERE ca.order_id = o.id
        AND ca.status IN ('assigned', 'picked_up', 'on_the_way')
    )
    AND NOT EXISTS (
      SELECT 1
      FROM public.courier_order_rejections AS cor
      WHERE cor.order_id = o.id
        AND cor.courier_id = (SELECT auth.uid())
    )
  ORDER BY COALESCE(o.scheduled_for, o.created_at) ASC;
$function$;

revoke all on function public.get_available_orders_for_courier() from public, anon;
grant execute on function public.get_available_orders_for_courier() to authenticated, service_role;

-- -----------------------------------------------------------------------------
-- 7) guard_shop_financial_columns: scheduled_orders_admin_blocked satıcıya kapalı
-- (canlı tanımdan türetildi; yalnız işaretli satırlar değişti)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.guard_shop_financial_columns()
 RETURNS trigger
 LANGUAGE plpgsql
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
  -- Randevulu sipariş: dükkan bazlı yönetici engeli yalnız admin değiştirir.
  new.scheduled_orders_admin_blocked := old.scheduled_orders_admin_blocked;

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

-- -----------------------------------------------------------------------------
-- 8) guard_orders_client_update: scheduled_for kilitli
-- (canlı tanımdan türetildi; yalnız işaretli satırlar değişti)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION private.guard_orders_client_update()
 RETURNS trigger
 LANGUAGE plpgsql
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
    'scheduled_for', 'scheduled_reminder_sent_at',
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

-- -----------------------------------------------------------------------------
-- 9) complete_online_payment: order_data.scheduled_for
-- (canlı tanımdan türetildi; yalnız işaretli satırlar değişti)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.complete_online_payment(p_payment_transaction_id uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_payment_record RECORD;
  v_order_data JSONB;
  v_user_id UUID;
  v_shop_id UUID;
  v_order_id UUID;
  v_order_number VARCHAR;
  v_item JSONB;
  v_items JSONB;
  v_total DECIMAL;
  v_subtotal DECIMAL;
  v_delivery_fee DECIMAL;
  v_coupon_discount DECIMAL;
  v_coupon_id UUID;
  v_delivery_address_text TEXT;
  v_delivery_address_id UUID;
  v_note TEXT;
  v_customer_phone TEXT;
  v_shop_name TEXT;
  v_existing_order_id UUID;
  v_scheduled_for TIMESTAMPTZ;
BEGIN
  -- IDEMPOTENT: Önce bu transaction için zaten oluşturulmuş order var mı?
  SELECT order_id INTO v_existing_order_id
  FROM public.payment_transactions
  WHERE id = p_payment_transaction_id;

  IF v_existing_order_id IS NOT NULL THEN
    RAISE NOTICE 'Sipariş zaten oluşturulmuş (idempotent): order_id=%', v_existing_order_id;
    RETURN v_existing_order_id;
  END IF;

  -- 1. Payment transaction'ı al
  SELECT * INTO v_payment_record
  FROM public.payment_transactions
  WHERE id = p_payment_transaction_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Payment transaction bulunamadı: %', p_payment_transaction_id;
  END IF;

  IF v_payment_record.payment_status = 'failure' THEN
    RAISE EXCEPTION 'Başarısız ödeme için sipariş oluşturulamaz: %', p_payment_transaction_id;
  END IF;

  -- 1b. Sunucu-otoriteli oturum (2026-10-17): sipariş(ler) oturum dökümünden
  IF v_payment_record.checkout_session_id IS NOT NULL
     OR NULLIF(v_payment_record.callback_data ->> 'checkout_session_id', '') IS NOT NULL THEN
    SELECT c.order_id INTO v_order_id
      FROM public.commit_online_order(p_payment_transaction_id) AS c;
    RETURN v_order_id;
  END IF;

  -- 2. Callback data'dan sipariş bilgilerini çıkar
  v_order_data := v_payment_record.callback_data -> 'order_data';
  v_user_id := (v_payment_record.callback_data ->> 'user_id')::UUID;

  IF v_order_data IS NULL OR v_user_id IS NULL THEN
    RAISE EXCEPTION 'Sipariş verileri eksik (callback_data). callback_data: %', v_payment_record.callback_data;
  END IF;

  v_shop_id := (v_order_data ->> 'shop_id')::UUID;
  v_total := (v_order_data ->> 'total')::DECIMAL;
  v_subtotal := (v_order_data ->> 'subtotal')::DECIMAL;
  v_delivery_fee := COALESCE((v_order_data ->> 'delivery_fee')::DECIMAL, 0);
  v_coupon_discount := COALESCE((v_order_data ->> 'coupon_discount')::DECIMAL, 0);
  -- coupon_id opsiyonel: boş string/null/eksik ise NULL bırak (kupon yok).
  -- NULLIF(..., '') boş string'i de yakalar; aksi halde ''::UUID exception fırlatır.
  v_coupon_id := NULLIF(v_order_data ->> 'coupon_id', '')::UUID;
  v_delivery_address_text := v_order_data ->> 'delivery_address_text';
  v_note := v_order_data ->> 'note';
  v_items := v_order_data -> 'items';
  v_customer_phone := v_order_data ->> 'customer_phone';
  -- Randevulu sipariş (2026-10-22): bozuk değer siparişi düşürmez, yok sayılır;
  -- geçerliliği orders_validate_scheduled_for tetikleyicisi denetler.
  BEGIN
    v_scheduled_for := NULLIF(v_order_data ->> 'scheduled_for', '')::timestamptz;
  EXCEPTION WHEN others THEN
    v_scheduled_for := NULL;
  END;

  SELECT name INTO v_shop_name FROM public.shops WHERE id = v_shop_id;

  IF v_order_data ->> 'delivery_address_id' IS NOT NULL AND v_order_data ->> 'delivery_address_id' != '' THEN
    v_delivery_address_id := (v_order_data ->> 'delivery_address_id')::UUID;
  END IF;

  -- 3. Sipariş numarası oluştur
  v_order_number := 'ONL-' || TO_CHAR(NOW(), 'YYYYMMDD') || '-' ||
                    LPAD(FLOOR(RANDOM() * 99999)::TEXT, 5, '0');

  -- 4. Siparişi oluştur (coupon_id artık dahil)
  INSERT INTO public.orders (
    user_id,
    shop_id,
    order_number,
    status,
    payment_method,
    payment_status,
    total,
    subtotal,
    delivery_fee,
    discount,
    coupon_id,
    coupon_discount,
    delivery_address_text,
    delivery_address_id,
    notes,
    customer_phone,
    payment_transaction_id,
    iyzico_payment_id,
    iyzico_conversation_id,
    scheduled_for
  ) VALUES (
    v_user_id,
    v_shop_id,
    v_order_number,
    'pending',
    'online',
    'paid',
    v_total,
    v_subtotal,
    v_delivery_fee,
    v_coupon_discount,
    v_coupon_id,
    v_coupon_discount,
    v_delivery_address_text,
    v_delivery_address_id,
    v_note,
    v_customer_phone,
    p_payment_transaction_id,
    v_payment_record.payment_id,
    v_payment_record.conversation_id,
    v_scheduled_for
  )
  RETURNING id INTO v_order_id;

  -- 5. Sipariş kalemlerini oluştur
  FOR v_item IN SELECT * FROM jsonb_array_elements(v_items)
  LOOP
    INSERT INTO public.order_items (
      order_id,
      product_id,
      product_name,
      quantity,
      price,
      product_price,
      subtotal,
      shop_id,
      shop_name
    ) VALUES (
      v_order_id,
      (v_item ->> 'product_id')::UUID,
      v_item ->> 'product_name',
      (v_item ->> 'quantity')::INTEGER,
      (v_item ->> 'price')::DECIMAL,
      (v_item ->> 'price')::DECIMAL,
      (v_item ->> 'price')::DECIMAL * (v_item ->> 'quantity')::INTEGER,
      v_shop_id,
      v_shop_name
    );
  END LOOP;

  -- 6. Payment transaction'a order_id'yi bağla (race condition koruması)
  UPDATE public.payment_transactions
  SET order_id = v_order_id,
      updated_at = NOW()
  WHERE id = p_payment_transaction_id
    AND order_id IS NULL;

  RAISE NOTICE 'Online sipariş oluşturuldu: order_id=%, order_number=%, coupon_id=%', v_order_id, v_order_number, v_coupon_id;

  RETURN v_order_id;
END;
$function$;

-- -----------------------------------------------------------------------------
-- 10) assign_order_to_courier: erken atama yok
-- (canlı tanımdan türetildi; yalnız işaretli satırlar değişti)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.assign_order_to_courier(p_order_id uuid, p_courier_id uuid DEFAULT NULL::uuid)
 RETURNS TABLE(r_assignment_id uuid, r_courier_id uuid, r_courier_name text, r_fee_amount numeric, r_order_status text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_uid        CONSTANT uuid := (SELECT auth.uid());
  v_target     uuid;
  v_self_assign boolean := false;
  v_order      public.orders%ROWTYPE;
  v_assignment_id uuid;
  v_existing   uuid;
  v_fee        numeric(12, 2);
  v_courier_name text;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'APP:auth_required' USING ERRCODE = '42501';
  END IF;
  IF p_order_id IS NULL THEN
    RAISE EXCEPTION 'APP:order_id_required' USING ERRCODE = '22023';
  END IF;

  -- Siparişi kilitle (paralel atayan çağrıları serialize eder)
  SELECT o.* INTO v_order
  FROM public.orders AS o
  WHERE o.id = p_order_id
  FOR UPDATE;

  IF v_order.id IS NULL THEN
    RAISE EXCEPTION 'APP:not_found' USING ERRCODE = 'P0001';
  END IF;

  -- Randevulu sipariş: kurye ancak saatine lead dk kala alabilir/atanabilir.
  IF v_order.scheduled_for IS NOT NULL
     AND NOT public.is_admin()
     AND now() < v_order.scheduled_for
                 - make_interval(mins => public.scheduled_courier_lead_minutes()) THEN
    RAISE EXCEPTION 'APP:scheduled_too_early' USING ERRCODE = 'P0001';
  END IF;

  -- Hedef kurye + yetkilendirme
  IF p_courier_id IS NULL THEN
    IF public.is_courier_role() THEN
      v_target := v_uid;
      v_self_assign := true;
    ELSE
      -- satıcı/admin değilse reddet; satıcı yalnız kendi dükkanının siparişini atayabilir
      IF NOT public.is_admin() AND NOT EXISTS (
        SELECT 1 FROM public.shops AS s
        WHERE s.id = v_order.shop_id AND s.owner_id = v_uid
      ) THEN
        RAISE EXCEPTION 'APP:forbidden' USING ERRCODE = '42501';
      END IF;
      -- En uygun kurye: online優先, en az teslimat, reddetmeyen, evrakı onaylı
      SELECT p.id INTO v_target
      FROM public.profiles AS p
      WHERE p.role = 'courier'::public.user_role
        AND p.id IS DISTINCT FROM v_order.user_id
        AND public.is_courier_document_approved(p.id)
        AND NOT EXISTS (
          SELECT 1 FROM public.courier_order_rejections AS cor
          WHERE cor.order_id = p_order_id AND cor.courier_id = p.id
        )
      ORDER BY COALESCE(p.is_online, false) DESC,
               COALESCE(p.delivered_count, 0) ASC,
               p.id
      LIMIT 1;
      IF v_target IS NULL THEN
        RAISE EXCEPTION 'APP:no_courier_available' USING ERRCODE = 'P0001';
      END IF;
    END IF;
  ELSE
    v_target := p_courier_id;
    IF NOT public.is_admin() AND NOT EXISTS (
      SELECT 1 FROM public.shops AS s
      WHERE s.id = v_order.shop_id AND s.owner_id = v_uid
    ) THEN
      RAISE EXCEPTION 'APP:forbidden' USING ERRCODE = '42501';
    END IF;
  END IF;

  -- Evrak onayı olmayan kurye siparişi teslim alamaz — self-accept, otomatik
  -- seçim (yukarıda zaten filtrelendi, burada savunma amaçlı tekrar kontrol)
  -- veya admin/satıcının elle p_courier_id vermesi fark etmeksizin.
  IF NOT public.is_courier_document_approved(v_target) THEN
    RAISE EXCEPTION 'APP:courier_documents_not_approved' USING ERRCODE = '42501';
  END IF;

  -- Zaten aktif atama var mı (anti-race; order FOR UPDATE ile serialize edildi)
  SELECT ca.id INTO v_existing
  FROM public.courier_assignments AS ca
  WHERE ca.order_id = p_order_id
    AND ca.status IN ('assigned', 'picked_up', 'on_the_way')
  LIMIT 1;
  IF v_existing IS NOT NULL THEN
    RAISE EXCEPTION 'APP:already_assigned' USING ERRCODE = 'P0001';
  END IF;

  -- Ücret: courier_settings.fee_per_delivery (yoksa 15)
  SELECT cs.fee_per_delivery INTO v_fee
  FROM public.courier_settings AS cs
  LIMIT 1;
  v_fee := COALESCE(v_fee, 15);

  INSERT INTO public.courier_assignments (
    order_id, courier_id, status, fee_amount, assigned_at
  ) VALUES (
    p_order_id, v_target, 'assigned', v_fee, now()
  )
  RETURNING id INTO v_assignment_id;

  -- Müşteriye "yolda" görünsün (mevcut _acceptOrder davranışını korur)
  UPDATE public.orders
     SET status = 'on_the_way', updated_at = now()
   WHERE id = p_order_id
     AND status IN ('confirmed', 'preparing', 'ready');

  SELECT COALESCE(p.full_name, p.username, 'Kurye') INTO v_courier_name
  FROM public.profiles AS p
  WHERE p.id = v_target;

  -- Müşteriye tek "yolda" bildirimi (önceden hem accept hem pickup'ta çift gidiyordu)
  PERFORM public.add_notification(
    p_user_id  => v_order.user_id,
    p_type     => 'order_update',
    p_title    => '🚴 Siparişiniz Yolda!',
    p_content  => v_courier_name || ' siparişinizi teslim etmek için yola çıktı.',
    p_entity_id => p_order_id::text
  );

  -- Atanan kuryeye bildirim (otomatik/satıcı yolu); self-accept'te atlanır
  IF NOT v_self_assign THEN
    PERFORM public.add_notification(
      p_user_id   => v_target,
      p_type      => 'courier_order_assigned',
      p_title     => '🛵 Sipariş Sana Atandı!',
      p_content   => 'Sana bir sipariş atandı. Kurye panelinden teslim alabilirsin.',
      p_entity_id => p_order_id::text
    );
  END IF;

  RETURN QUERY
  SELECT v_assignment_id, v_target, v_courier_name, v_fee, 'on_the_way'::text;
END;
$function$;

-- -----------------------------------------------------------------------------
-- 11) admin_shops_page: randevu alanları
-- (canlı tanımdan türetildi; yalnız işaretli satırlar değişti)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_shops_page(p_search text DEFAULT NULL::text, p_filter text DEFAULT NULL::text, p_sort text DEFAULT 'default'::text, p_limit integer DEFAULT 20, p_offset integer DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_limit  integer := LEAST(GREATEST(COALESCE(p_limit, 20), 1), 100);
  v_offset integer := GREATEST(COALESCE(p_offset, 0), 0);
  v_q      text := NULLIF(btrim(COALESCE(p_search, '')), '');
  v_filter text := CASE
                     WHEN p_filter IN ('pending', 'active', 'passive', 'pinned',
                                       'verified', 'admin_courier', 'overridden')
                     THEN p_filter
                   END;
  v_sort   text := COALESCE(p_sort, 'default');
  v_fee    double precision;
  v_res    jsonb;
BEGIN
  IF NOT private.current_user_is_admin() THEN
    RAISE EXCEPTION 'admin_shops_page: not admin' USING ERRCODE = '42501';
  END IF;

  -- Kuryesi olmayan dükkanın teslimat başı kurye ücreti (eski _getCourierFee).
  SELECT cs.fee_per_delivery INTO v_fee
    FROM public.courier_settings cs
   ORDER BY cs.updated_at DESC
   LIMIT 1;
  v_fee := COALESCE(v_fee, 15);

  WITH ord AS (
    SELECT o.shop_id,
           count(*) AS total_orders,
           count(*) FILTER (WHERE o.status::text = 'delivered') AS delivered_orders,
           count(*) FILTER (WHERE o.status::text = 'cancelled') AS cancelled_orders,
           COALESCE(sum(o.total) FILTER (WHERE o.status::text = 'delivered'), 0)
             AS total_earnings,
           COALESCE(sum(o.total) FILTER (
             WHERE o.status::text = 'delivered'
               AND o.created_at > now() - interval '7 days'), 0) AS weekly_earnings,
           COALESCE(sum(o.total) FILTER (
             WHERE o.status::text = 'delivered'
               AND o.created_at > now() - interval '30 days'), 0) AS monthly_earnings
      FROM public.orders o
     GROUP BY o.shop_id
  ),
  prod AS (
    SELECT p.shop_id, count(*) AS product_count
      FROM public.products p
     GROUP BY p.shop_id
  ),
  base AS (
    SELECT s.id, s.name, s.slug, s.description, s.logo_url, s.category_id,
           s.owner_id, s.commission_rate, s.is_verified, s.is_approved,
           s.is_active, s.is_pinned, s.has_own_courier, s.delivery_fee,
           s.scheduled_orders_enabled, s.scheduled_orders_admin_blocked,
           s.min_order_amount, s.delivery_time, s.pre_override_delivery_fee,
           s.pre_override_min_order_amount, s.pre_override_delivery_time,
           s.admin_pricing_override_at, s.admin_pricing_override_note,
           s.created_at, s.admin_credit, s.commission_debt,
           s.total_collected_cash, s.total_paid, s.cash_payment_revenue,
           s.online_payment_revenue,
           -- Görev 4.5: ana kategori adı/ikonu ve yönetici kilidi
           c.name AS category_name,
           c.icon AS category_icon,
           (cl.shop_id IS NOT NULL) AS category_locked,
           cl.note AS category_lock_note,
           CASE WHEN pf.id IS NULL THEN NULL
                ELSE jsonb_build_object(
                       'id', pf.id,
                       'username', pf.username,
                       'full_name', pf.full_name,
                       'avatar_url', pf.avatar_url,
                       'email', pf.email)
           END AS profiles,
           COALESCE(pr.product_count, 0) AS product_count,
           COALESCE(od.total_orders, 0) AS total_orders,
           COALESCE(od.delivered_orders, 0) AS delivered_orders,
           COALESCE(od.total_orders, 0) - COALESCE(od.delivered_orders, 0)
             - COALESCE(od.cancelled_orders, 0) AS pending_orders,
           COALESCE(od.cancelled_orders, 0) AS cancelled_orders,
           COALESCE(od.total_earnings, 0) AS total_earnings,
           COALESCE(od.weekly_earnings, 0) AS weekly_earnings,
           COALESCE(od.monthly_earnings, 0) AS monthly_earnings,
           COALESCE(od.total_earnings, 0) * COALESCE(s.commission_rate, 10) / 100
             AS admin_commission_total,
           CASE WHEN NOT COALESCE(s.has_own_courier, true)
                THEN COALESCE(od.delivered_orders, 0) * v_fee
                ELSE 0
           END AS courier_deduction
      FROM public.shops s
      LEFT JOIN public.profiles pf ON pf.id = s.owner_id
      LEFT JOIN public.categories c ON c.id = s.category_id
      LEFT JOIN public.shop_category_locks cl ON cl.shop_id = s.id
      LEFT JOIN ord od ON od.shop_id = s.id
      LEFT JOIN prod pr ON pr.shop_id = s.id
  ),
  full_rows AS (
    SELECT b.*,
           b.total_earnings - b.admin_commission_total - b.courier_deduction
             AS net_earnings,
           (b.pre_override_delivery_fee IS NOT NULL
            OR b.pre_override_min_order_amount IS NOT NULL
            OR b.pre_override_delivery_time IS NOT NULL) AS is_overridden
      FROM base b
  ),
  f AS (
    SELECT r.*
      FROM full_rows r
     WHERE (v_q IS NULL
            OR r.name ILIKE '%' || v_q || '%'
            OR r.slug ILIKE '%' || v_q || '%'
            OR r.description ILIKE '%' || v_q || '%'
            OR r.profiles->>'full_name' ILIKE '%' || v_q || '%'
            OR r.profiles->>'username' ILIKE '%' || v_q || '%'
            OR r.profiles->>'email' ILIKE '%' || v_q || '%'
            OR r.category_name ILIKE '%' || v_q || '%')
       AND (v_filter IS NULL
            OR (v_filter = 'pending'       AND NOT COALESCE(r.is_approved, false))
            OR (v_filter = 'active'        AND COALESCE(r.is_active, true))
            OR (v_filter = 'passive'       AND NOT COALESCE(r.is_active, true))
            OR (v_filter = 'pinned'        AND COALESCE(r.is_pinned, false))
            OR (v_filter = 'verified'      AND COALESCE(r.is_verified, false))
            OR (v_filter = 'admin_courier' AND NOT COALESCE(r.has_own_courier, false))
            OR (v_filter = 'overridden'    AND r.is_overridden))
  ),
  ranked AS (
    SELECT f.*,
           row_number() OVER (
             ORDER BY
               CASE WHEN v_sort = 'earnings' THEN f.total_earnings END DESC NULLS LAST,
               CASE WHEN v_sort = 'orders'   THEN f.total_orders   END DESC NULLS LAST,
               CASE WHEN v_sort = 'newest'   THEN f.created_at     END DESC NULLS LAST,
               CASE WHEN v_sort NOT IN ('name', 'earnings', 'orders', 'newest')
                    THEN CASE WHEN COALESCE(f.is_pinned, false) THEN 0 ELSE 1 END
               END ASC,
               lower(COALESCE(f.name, '')) ASC,
               f.id
           ) AS rn
      FROM f
  )
  SELECT jsonb_build_object(
    'total', (SELECT count(*) FROM f),
    'rows', COALESCE((
      SELECT jsonb_agg(to_jsonb(pg) - 'rn' - 'is_overridden' ORDER BY pg.rn)
        FROM (SELECT * FROM ranked ORDER BY rn LIMIT v_limit OFFSET v_offset) pg
    ), '[]'::jsonb),
    'summary', (
      SELECT jsonb_build_object(
        'total',         count(*),
        'pending',       count(*) FILTER (WHERE NOT COALESCE(a.is_approved, false)),
        'active',        count(*) FILTER (WHERE COALESCE(a.is_active, true)),
        'passive',       count(*) FILTER (WHERE NOT COALESCE(a.is_active, true)),
        'pinned',        count(*) FILTER (WHERE COALESCE(a.is_pinned, false)),
        'verified',      count(*) FILTER (WHERE COALESCE(a.is_verified, false)),
        'admin_courier', count(*) FILTER (WHERE NOT COALESCE(a.has_own_courier, false)),
        'overridden',    count(*) FILTER (WHERE a.is_overridden),
        'revenue',       COALESCE(sum(a.total_earnings), 0),
        'commission',    COALESCE(sum(a.admin_commission_total), 0)
      )
        FROM full_rows a
    )
  ) INTO v_res;

  RETURN v_res;
END;
$function$;

commit;

notify pgrst, 'reload schema';
