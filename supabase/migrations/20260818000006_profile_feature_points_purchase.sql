-- =============================================================================
-- Profil özellikleri: TL ücreti kaldırılıp puanla satın almaya geçiş
-- =============================================================================
-- İSTEK: Mağaza uyum denetiminde bulundu — profil/kapak dekorasyonları iyzico
-- ile yüklenen gerçek TL bakiyesinden satın alınıyordu. Bu, dijital bir
-- özelliğin harici ödeme sağlayıcısıyla satılması demek; Apple 3.1.1 ve
-- Google Play Faturalandırma politikasına aykırı (istisna yalnızca fiziksel
-- mal/hizmet için geçerli). Karar: TL ücreti tamamen kaldırılır, yerine
-- parayla satın alınamayan, yalnızca reklam izleyerek/görev tamamlayarak
-- kazanılan ayrı puan defteri (20260730000002_admob_reward_points_system.sql)
-- kullanılır.
--
-- TASARIM:
--   1) profile_feature_catalog'a points_price_monthly/points_price_yearly
--      (bigint) eklenir. Mevcut 16 satın alınabilir satırın puan fiyatı,
--      ad_settings.points_per_try (reklam puanı <-> 1 TL dönüşüm oranı,
--      zaten var olan bir admin ayarı) ile eski TL fiyatından hesaplanır —
--      yalnızca başlangıç değeridir, admin panelden değiştirilebilir.
--      Ardından price_monthly/price_yearly NULL'a çekilir (TL ücreti biter).
--   2) user_profile_features'a purchased_points eklenir; purchased_price
--      (TL) koloni geçmiş kayıtlar için dokunulmadan kalır.
--   3) point_ledger_entries.entry_type/reference_type CHECK listelerine
--      'profile_feature_debit'/'profile_feature' eklenir — native enum değil
--      düz text+CHECK olduğu için tek migration'da yapılabilir (bkz.
--      20260817000007'deki profile_feature_catalog.kind genişletme deseni).
--      point_ledger_type_direction eşleşme constraint'i de aynı şekilde
--      genişletilir (yoksa yeni entry_type hiçbir zaman debit ile eşleşmez).
--   4) purchase_my_profile_feature_with_points(): reward_points_apply_entry()
--      üzerinden puan düşer. O fonksiyon SADECE reward_points_owner sahipli
--      fonksiyonlarca çağrılabildiği için (20260730000002'deki kilit), bu
--      fonksiyon da aynı desene uyar: yalnızca service_role'e GRANT edilir
--      (authenticated'a asla doğrudan açılmaz — puan harcayan her akış
--      zaten bir Edge Function üzerinden gider, bkz. smm-order-create), ve
--      OWNER TO reward_points_owner ile biter.
--   5) Eski TL akışı (purchase_my_profile_feature, admin_set_profile_feature_pricing)
--      DROP edilir. Geçmiş satın alma kayıtları (user_profile_features,
--      balance_transactions satırları) veridir, fonksiyonun varlığına bağlı
--      değildir.
--   6) İADE YOK politikası korunur (20260817000028'deki karar) — yeni bir
--      iade entry_type/RPC eklenmez.
--   7) Admin manuel atama / self-claim / sipariş-kilit açma yolları
--      (20260817000008, 20260817000013, 20260818000001) bu migration'dan
--      etkilenmez.
-- =============================================================================

begin;

-- -----------------------------------------------------------------------------
-- 1) Katalog: puan fiyatı kolonları + başlangıç değeri + TL ücretinin sonu
-- -----------------------------------------------------------------------------
alter table public.profile_feature_catalog
  add column if not exists points_price_monthly bigint check (points_price_monthly is null or points_price_monthly >= 0),
  add column if not exists points_price_yearly bigint check (points_price_yearly is null or points_price_yearly >= 0);

comment on column public.profile_feature_catalog.points_price_monthly is
  'Aylık satın alma fiyatı (puan — user_point_accounts). TL bakiyesiyle ilgisi yok, parayla satın alınamaz. NULL = aylık plan yok.';
comment on column public.profile_feature_catalog.points_price_yearly is
  'Yıllık satın alma fiyatı (puan). NULL = yıllık plan yok.';

with rate as (
  select coalesce((select points_per_try from public.ad_settings where id = 1), 100) as points_per_try
)
update public.profile_feature_catalog c
set points_price_monthly = case when c.price_monthly is not null
      then round(c.price_monthly * r.points_per_try)::bigint else c.points_price_monthly end,
    points_price_yearly = case when c.price_yearly is not null
      then round(c.price_yearly * r.points_per_try)::bigint else c.points_price_yearly end,
    price_monthly = null,
    price_yearly = null,
    updated_at = now()
from rate r
where c.price_monthly is not null or c.price_yearly is not null;

-- -----------------------------------------------------------------------------
-- 2) user_profile_features: puan cinsinden ödenen tutar için ayrı kolon
-- -----------------------------------------------------------------------------
alter table public.user_profile_features
  add column if not exists purchased_points bigint check (purchased_points is null or purchased_points >= 0);

comment on column public.user_profile_features.purchased_points is
  'Satın alma anında fiilen düşülen puan tutarı (katalog fiyatı sonradan değişse bile sabit kalır). TL ile satın alınmış eski kayıtlarda NULL, purchased_price doludur.';

-- -----------------------------------------------------------------------------
-- 3) point_ledger_entries: yeni entry_type/reference_type değerleri
--    Bu tablo reward_points_owner'a ait (20260730000002'de OWNER TO ile
--    devredildi, rol NOINHERIT — sahiplik otomatik miras kalmaz). Constraint
--    değiştirmek sahiplik ister, salt üyelik yetmez; bu yüzden bu blok için
--    geçici olarak o role geçilir.
-- -----------------------------------------------------------------------------
set role reward_points_owner;

alter table public.point_ledger_entries
  drop constraint if exists point_ledger_entries_entry_type_check;
alter table public.point_ledger_entries
  add constraint point_ledger_entries_entry_type_check
  check (entry_type in (
    'ad_reward_credit', 'digital_order_debit', 'digital_order_refund',
    'admin_correction_credit', 'admin_correction_debit', 'expiry_debit',
    'profile_feature_debit'
  ));

alter table public.point_ledger_entries
  drop constraint if exists point_ledger_entries_reference_type_check;
alter table public.point_ledger_entries
  add constraint point_ledger_entries_reference_type_check
  check (reference_type in ('ad_reward_session', 'digital_order', 'admin_case', 'profile_feature'));

alter table public.point_ledger_entries
  drop constraint if exists point_ledger_type_direction;
alter table public.point_ledger_entries
  add constraint point_ledger_type_direction
  check (
    (entry_type in ('ad_reward_credit', 'digital_order_refund', 'admin_correction_credit') and direction = 'credit')
    or (entry_type in ('digital_order_debit', 'admin_correction_debit', 'expiry_debit', 'profile_feature_debit') and direction = 'debit')
  );

reset role;

-- -----------------------------------------------------------------------------
-- 4) Satın alma RPC'si (service_role-only — bkz. yukarıdaki TASARIM 4)
-- -----------------------------------------------------------------------------
create or replace function public.purchase_my_profile_feature_with_points(
  p_user_id uuid,
  p_feature_id uuid,
  p_plan text,
  p_idempotency_key text
) returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_settings public.ad_settings%rowtype;
  v_is_active boolean;
  v_points bigint;
  v_interval interval;
  v_duplicate boolean;
  v_id uuid;
  v_expires_at timestamptz;
begin
  if coalesce(nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role', '') <> 'service_role' then
    raise exception 'SERVICE_ROLE_REQUIRED' using errcode = '42501';
  end if;
  if p_user_id is null then
    raise exception 'authentication required' using errcode = '42501';
  end if;
  if p_plan not in ('monthly', 'yearly') then
    raise exception 'Geçersiz plan: monthly veya yearly olmalıdır' using errcode = '22023';
  end if;
  if p_idempotency_key is null or length(p_idempotency_key) not between 8 and 200 then
    raise exception 'INVALID_IDEMPOTENCY_KEY' using errcode = '22023';
  end if;

  select * into v_settings from public.ad_settings where id = 1;
  if not coalesce(v_settings.reward_points_spend_enabled, false)
     or v_settings.reward_feature_mode <> 'enabled' then
    raise exception 'REWARD_FEATURE_DISABLED' using errcode = '55000';
  end if;

  select c.is_active,
    case when p_plan = 'monthly' then c.points_price_monthly else c.points_price_yearly end
  into v_is_active, v_points
  from public.profile_feature_catalog c
  where c.id = p_feature_id;

  if not found or not coalesce(v_is_active, false) or v_points is null then
    raise exception 'Bu özellik bu plan için satın alınabilir değildir' using errcode = '42501';
  end if;

  v_interval := case when p_plan = 'monthly' then interval '1 month' else interval '1 year' end;

  -- Bu idempotency_key daha önce kullanıldı mı? (reward_points_apply_entry
  -- çağrısından ÖNCE, o anki gerçek durumu yakalamak için.)
  select exists(
    select 1 from public.point_ledger_entries where idempotency_key = p_idempotency_key
  ) into v_duplicate;

  -- Puanı düş. Yetersizse INSUFFICIENT_POINTS fırlatır. Aynı idempotency_key
  -- ile tekrar çağrılırsa içeride güvenle aynı satırı döner, ikinci kez
  -- düşmez — bu yüzden aşağıda user_profile_features'ı yalnızca ilk
  -- (gerçek) çağrıda güncelliyoruz, replay'de süreyi tekrar uzatmıyoruz.
  perform public.reward_points_apply_entry(
    p_user_id, 'profile_feature_debit', 'debit', v_points,
    'profile_feature', p_feature_id, p_idempotency_key,
    jsonb_build_object('plan', p_plan)
  );

  if not v_duplicate then
    insert into public.user_profile_features (
      user_id, feature_id, granted_by, is_enabled, starts_at, expires_at,
      purchase_plan, purchased_points, config_override, updated_at
    ) values (
      p_user_id, p_feature_id, null, true, now(), now() + v_interval,
      p_plan, v_points, '{}'::jsonb, now()
    )
    on conflict (user_id, feature_id) do update set
      is_enabled = true,
      granted_by = null,
      starts_at = case
        when user_profile_features.expires_at is not null
         and user_profile_features.expires_at > now()
        then user_profile_features.starts_at
        else now() end,
      expires_at = case
        when user_profile_features.expires_at is not null
         and user_profile_features.expires_at > now()
        then user_profile_features.expires_at + v_interval
        else now() + v_interval end,
      purchase_plan = p_plan,
      purchased_points = v_points,
      updated_at = now()
    returning id, expires_at into v_id, v_expires_at;
  else
    select id, expires_at into v_id, v_expires_at
    from public.user_profile_features
    where user_id = p_user_id and feature_id = p_feature_id;
  end if;

  return jsonb_build_object(
    'assignment_id', v_id,
    'feature_id', p_feature_id,
    'plan', p_plan,
    'points_spent', v_points,
    'expires_at', v_expires_at,
    'duplicate', v_duplicate
  );
end;
$$;

-- -----------------------------------------------------------------------------
-- 5) Admin: katalog satırına aylık/yıllık PUAN fiyatı tanımla
-- -----------------------------------------------------------------------------
create or replace function public.admin_set_profile_feature_points_pricing(
  p_feature_id uuid,
  p_points_monthly bigint,
  p_points_yearly bigint
) returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not private.current_user_is_admin() then
    raise exception 'admin_set_profile_feature_points_pricing: not admin' using errcode = '42501';
  end if;
  if p_points_monthly is not null and p_points_monthly < 0 then
    raise exception 'Aylık puan negatif olamaz' using errcode = '22023';
  end if;
  if p_points_yearly is not null and p_points_yearly < 0 then
    raise exception 'Yıllık puan negatif olamaz' using errcode = '22023';
  end if;

  update public.profile_feature_catalog
  set points_price_monthly = case when kind = 'badge' then null else p_points_monthly end,
      points_price_yearly = case when kind = 'badge' then null else p_points_yearly end,
      updated_at = now()
  where id = p_feature_id;
end;
$$;

-- -----------------------------------------------------------------------------
-- 6) get_my_purchasable_profile_features(): puan kolonlarını döndür
--    (RETURNS TABLE şekli değiştiği için CREATE OR REPLACE yetmiyor, önce
--    DROP gerekiyor)
-- -----------------------------------------------------------------------------
drop function if exists public.get_my_purchasable_profile_features();

create function public.get_my_purchasable_profile_features()
returns table (
  assignment_id uuid,
  feature_id uuid,
  code text,
  kind text,
  name text,
  description text,
  renderer_key text,
  primary_color text,
  secondary_color text,
  config jsonb,
  priority integer,
  is_enabled boolean,
  is_purchased boolean,
  purchase_plan text,
  purchased_points bigint,
  points_price_monthly bigint,
  points_price_yearly bigint,
  starts_at timestamptz,
  expires_at timestamptz
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    upf.id, c.id, c.code, c.kind, c.name, c.description, c.renderer_key,
    c.primary_color, c.secondary_color,
    coalesce(c.config, '{}'::jsonb) || coalesce(upf.config_override, '{}'::jsonb),
    c.priority, coalesce(upf.is_enabled, false),
    (upf.id is not null and upf.purchase_plan is not null),
    upf.purchase_plan, upf.purchased_points,
    c.points_price_monthly, c.points_price_yearly,
    upf.starts_at, upf.expires_at
  from public.profile_feature_catalog c
  left join public.user_profile_features upf
    on upf.feature_id = c.id and upf.user_id = auth.uid()
  where auth.uid() is not null
    and c.is_active = true
    and (c.points_price_monthly is not null or c.points_price_yearly is not null)
  order by c.kind, c.priority desc, c.name;
$$;

-- -----------------------------------------------------------------------------
-- 7) Eski TL akışını kaldır
-- -----------------------------------------------------------------------------
drop function if exists public.purchase_my_profile_feature(uuid, text);
drop function if exists public.admin_set_profile_feature_pricing(uuid, numeric, numeric);

-- -----------------------------------------------------------------------------
-- 8) Grant/revoke + ownership
-- -----------------------------------------------------------------------------
revoke all on function public.get_my_purchasable_profile_features() from public;
grant execute on function public.get_my_purchasable_profile_features() to authenticated, service_role;

revoke all on function public.admin_set_profile_feature_points_pricing(uuid, bigint, bigint) from public;
grant execute on function public.admin_set_profile_feature_points_pricing(uuid, bigint, bigint) to authenticated, service_role;

revoke all on function public.purchase_my_profile_feature_with_points(uuid, uuid, text, text) from public, anon, authenticated;
grant execute on function public.purchase_my_profile_feature_with_points(uuid, uuid, text, text) to service_role;

-- reward_points_owner'ın public şemasındaki CREATE yetkisi 20260730000002'den
-- sonra bir sertleştirme adımıyla geri alınmış (has_schema_privilege ile
-- doğrulandı). ALTER FUNCTION ... OWNER TO, PostgreSQL kuralı gereği hedef
-- rolün o şemada CREATE'e sahip olmasını şart koşuyor — yetki yalnızca bu
-- tek devir işlemi için geri verilip hemen tekrar kaldırılır; kalıcı durum
-- değişmez.
grant create on schema public to reward_points_owner;
alter function public.purchase_my_profile_feature_with_points(uuid, uuid, text, text) owner to reward_points_owner;
revoke create on schema public from reward_points_owner;

commit;

-- =============================================================================
-- Kontrol:
--   -- 16 satırın puan fiyatı dolu, TL fiyatı NULL olmalı:
--   select code, kind, price_monthly, price_yearly, points_price_monthly, points_price_yearly
--   from public.profile_feature_catalog
--   where points_price_monthly is not null or points_price_yearly is not null
--   order by kind, code;
--
--   -- reward_points_spend_enabled kapalıyken satın alma denemesi REWARD_FEATURE_DISABLED vermeli:
--   select public.purchase_my_profile_feature_with_points(
--     '<user-id>', '<feature-id>', 'monthly', 'test-idem-key-0001'
--   );
--
--   -- Eski fonksiyonlar artık yok:
--   select proname from pg_proc where proname in ('purchase_my_profile_feature', 'admin_set_profile_feature_pricing');
--   -- Beklenen: 0 satır.
--
--   -- Yeni fonksiyon yalnızca service_role'e açık:
--   select has_function_privilege('authenticated', 'public.purchase_my_profile_feature_with_points(uuid,uuid,text,text)', 'execute');
--   -- Beklenen: false.
-- =============================================================================
