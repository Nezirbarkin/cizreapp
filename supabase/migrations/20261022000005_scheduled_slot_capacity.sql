-- ============================================================================
-- Randevulu sipariş: "aynı saate en fazla" sınırı (2026-10-22, depoya 10-24)
-- ----------------------------------------------------------------------------
-- Bu şema 2026-10-22'de canlıya doğrudan uygulanmış ama depoda göç dosyası
-- yoktu. Dosya canlı tanımlardan (pg_get_functiondef) birebir üretildi ve
-- tekrar çalıştırılabilir (IF NOT EXISTS / CREATE OR REPLACE).
--
-- * shops.scheduled_slot_capacity: aynı saate en fazla kaç (iptal/teslim
--   edilmemiş) sipariş; NULL = sınırsız (1..500).
-- * get_shop_schedule_slot_status(shop): get_shop_schedule_slots + her saatin
--   dolu olup olmadığı ve kalan yer. Müşteri seçicisi dolu saati "Dolu"
--   gösterir (ScheduledOrderService.fullSlots).
-- * validate_scheduled_order_slot: sınır dolduysa "Seçtiğiniz saat doldu…".
-- * orders_validate_scheduled_for (BEFORE INSERT tetikleyicisi, 20261022000002):
--   dükkan+saat için advisory kilitle sayar (eşzamanlı son yer); sunucu
--   bağlamında dolu saat korunur ve satıcıya scheduled_slot_overbooked gider.
--   Yetkileri CREATE OR REPLACE ile korunur.
-- Test: supabase/tests/manual/scheduled_slot_capacity_test.sql
-- ============================================================================
BEGIN;

ALTER TABLE public.shops ADD COLUMN IF NOT EXISTS scheduled_slot_capacity integer;

DO $do$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
     WHERE conrelid = 'public.shops'::regclass
       AND conname = 'shops_scheduled_slot_capacity_chk'
  ) THEN
    ALTER TABLE public.shops
      ADD CONSTRAINT shops_scheduled_slot_capacity_chk
      CHECK (scheduled_slot_capacity IS NULL OR (scheduled_slot_capacity >= 1 AND scheduled_slot_capacity <= 500));
  END IF;
END
$do$;

COMMENT ON COLUMN public.shops.scheduled_slot_capacity IS
  'Randevulu sipariş: aynı saate en fazla kaç (iptal/teslim edilmemiş) sipariş; NULL = sınırsız.';

CREATE OR REPLACE FUNCTION public.get_shop_schedule_slot_status(p_shop_id uuid)
 RETURNS TABLE(slot_at timestamp with time zone, is_full boolean, remaining integer)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_cap integer;
begin
  select s.scheduled_slot_capacity into v_cap from public.shops s where s.id = p_shop_id;

  return query
  select g.slot_at,
         (v_cap is not null and coalesce(c.n, 0) >= v_cap) as is_full,
         case when v_cap is null then null
              else greatest(v_cap - coalesce(c.n, 0), 0)::integer end as remaining
    from public.get_shop_schedule_slots(p_shop_id) g
    left join (
      select o.scheduled_for, count(*)::integer as n
        from public.orders o
       where o.shop_id = p_shop_id
         and o.scheduled_for is not null
         and o.scheduled_for >= now()
         and o.status::text not in ('cancelled', 'delivered')
       group by o.scheduled_for
    ) c on c.scheduled_for = g.slot_at
   order by g.slot_at;
end;
$function$;

REVOKE ALL ON FUNCTION public.get_shop_schedule_slot_status(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_shop_schedule_slot_status(uuid)
  TO anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION public.validate_scheduled_order_slot(p_shop_id uuid, p_at timestamp with time zone)
 RETURNS text
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_enabled boolean;
  v_blocked boolean;
  v_cap     integer;
begin
  if p_at is null then
    return null;
  end if;
  if not public.scheduled_orders_globally_enabled() then
    return 'Randevulu sipariş şu an kullanılamıyor.';
  end if;
  select s.scheduled_orders_enabled, s.scheduled_orders_admin_blocked, s.scheduled_slot_capacity
    into v_enabled, v_blocked, v_cap
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
  if v_cap is not null and private.scheduled_slot_taken(p_shop_id, p_at) >= v_cap then
    return 'Seçtiğiniz saat doldu, lütfen başka bir saat seçin.';
  end if;
  return null;
end;
$function$;

REVOKE ALL ON FUNCTION public.validate_scheduled_order_slot(uuid, timestamp with time zone) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.validate_scheduled_order_slot(uuid, timestamp with time zone)
  TO anon, authenticated, service_role;

CREATE OR REPLACE FUNCTION public.orders_validate_scheduled_for()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare
  v_err text;
begin
  if new.scheduled_for is null then
    return new;
  end if;

  -- Aynı dükkan + saat için eşzamanlı eklemeleri sıraya sok: ikinci işlem
  -- birincinin commit'ini bekler, sonra güncel sayıyı görür.
  perform pg_advisory_xact_lock(
    hashtextextended('sched:' || new.shop_id::text || ':' || new.scheduled_for::text, 0)
  );

  v_err := public.validate_scheduled_order_slot(new.shop_id, new.scheduled_for);
  if v_err is null then
    return new;
  end if;

  if current_user not in ('authenticated', 'anon') then
    -- Sunucu bağlamı (ör. online ödeme sonrası sipariş): ödeme alınmış
    -- siparişi asla düşürme.
    if v_err like 'Seçtiğiniz saat doldu%' and new.scheduled_for > now() then
      -- Saat ödeme sırasında doldu: randevu korunur, kapasite aşılır,
      -- satıcı haberdar edilir.
      insert into public.notifications (
        user_id, type, title, content, entity_id, metadata, is_read, created_at
      )
      select s.owner_id,
             'scheduled_slot_overbooked',
             '⚠️ Dolu saate randevulu sipariş geldi',
             format('Online ödemeli bir sipariş, %s saati dolmuşken alındı (ödeme sırasında doldu). '
                    'Siparişler sekmesinden kontrol edin.',
                    to_char(new.scheduled_for at time zone 'Europe/Istanbul', 'DD.MM HH24:MI')),
             new.id::text,
             jsonb_build_object('order_id', new.id, 'scheduled_for', new.scheduled_for),
             false,
             now()
        from public.shops s
       where s.id = new.shop_id
         and s.owner_id is not null;
      return new;
    end if;
    -- Hâlâ gelecekte ve dükkan randevu alıyorsa (yalnız hazırlık süresi
    -- kaçtıysa) koru; değilse hemen teslime çevir.
    if new.scheduled_for <= now()
       or v_err not like 'Seçtiğiniz randevu saati%' then
      new.scheduled_for := null;
    end if;
    return new;
  end if;

  raise exception '%', v_err
    using errcode = '22023', hint = 'scheduled_slot_invalid';
end;
$function$;

COMMIT;

NOTIFY pgrst, 'reload schema';
