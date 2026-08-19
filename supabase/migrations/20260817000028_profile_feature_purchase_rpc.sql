-- =============================================================================
-- Profil/kapak dekorasyonu satın alma RPC'leri
-- =============================================================================
-- Mevcut bakiye altyapısı (user_balances/balance_transactions) yeniden
-- kullanılıyor — yeni bir cüzdan icat edilmiyor. deduct_from_balance/
-- add_to_balance RPC'leri BİLEREK çağrılmıyor: 20260727000008 ile
-- deduct_from_balance yalnız 'courier_payment' tipiyle sınırlandı. Bu yüzden
-- bu RPC (zaten SECURITY DEFINER) aynı muhasebe desenini
-- 20260817000025_ilan_category_publish_fee.sql'deki gibi doğrudan uyguluyor.
--
-- İADE YOK: Kullanıcı satın aldığı bir dekorasyonu kendi isteğiyle kaldırırsa
-- (release_my_claimed_profile_feature) ücret iade edilmez — ilan yayınlama
-- ücretindeki "kullanıcı kendi ilanını silerse iade yok" kararıyla aynı.
-- Süre dolumunda (expires_at geçince) zaten otomatik olarak görünmez olur,
-- ekstra bir "iptal" akışı gerekmez.
-- =============================================================================

begin;

-- -----------------------------------------------------------------------------
-- Kullanıcının satın alabileceği katalog (fiyatı olan satırlar).
-- -----------------------------------------------------------------------------
create or replace function public.get_my_purchasable_profile_features()
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
  purchased_price numeric,
  price_monthly numeric,
  price_yearly numeric,
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
    upf.purchase_plan, upf.purchased_price,
    c.price_monthly, c.price_yearly,
    upf.starts_at, upf.expires_at
  from public.profile_feature_catalog c
  left join public.user_profile_features upf
    on upf.feature_id = c.id and upf.user_id = auth.uid()
  where auth.uid() is not null
    and c.is_active = true
    and (c.price_monthly is not null or c.price_yearly is not null)
  order by c.kind, c.priority desc, c.name;
$$;

-- -----------------------------------------------------------------------------
-- Satın alma: bakiyeyi kilitle, kontrol et, düş, süreyi başlat/uzat.
-- -----------------------------------------------------------------------------
create or replace function public.purchase_my_profile_feature(
  p_feature_id uuid,
  p_plan text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_is_active boolean;
  v_name text;
  v_price numeric(10,2);
  v_interval interval;
  v_balance_id uuid;
  v_current_balance numeric(12,2);
  v_id uuid;
begin
  if v_uid is null then
    raise exception 'authentication required' using errcode = '42501';
  end if;
  if p_plan not in ('monthly', 'yearly') then
    raise exception 'Geçersiz plan: monthly veya yearly olmalıdır' using errcode = '22023';
  end if;

  select c.is_active, c.name,
    case when p_plan = 'monthly' then c.price_monthly else c.price_yearly end
  into v_is_active, v_name, v_price
  from public.profile_feature_catalog c
  where c.id = p_feature_id;

  if not found or not coalesce(v_is_active, false) or v_price is null then
    raise exception 'Bu özellik bu plan için satın alınabilir değildir' using errcode = '42501';
  end if;

  v_interval := case when p_plan = 'monthly' then interval '1 month' else interval '1 year' end;

  select ub.id, ub.balance into v_balance_id, v_current_balance
  from public.user_balances ub
  where ub.user_id = v_uid
  for update;

  if v_balance_id is null or v_current_balance < v_price then
    raise exception 'Yetersiz bakiye: bu özellik % TL ücretlidir', v_price
      using errcode = 'P0001';
  end if;

  update public.user_balances
  set balance = v_current_balance - v_price,
      total_spent = total_spent + v_price,
      updated_at = now()
  where id = v_balance_id;

  insert into public.balance_transactions (
    user_id, type, amount, net_amount, balance_before, balance_after,
    reference_type, reference_id, status, description
  ) values (
    v_uid, 'profile_feature_purchase'::public.balance_transaction_type,
    v_price, v_price,
    v_current_balance, v_current_balance - v_price,
    'profile_feature', p_feature_id, 'completed',
    format('Profil özelliği satın alma (%s): %s', p_plan, left(coalesce(v_name, ''), 120))
  );

  insert into public.user_profile_features (
    user_id, feature_id, granted_by, is_enabled, starts_at, expires_at,
    purchase_plan, purchased_price, config_override, updated_at
  ) values (
    v_uid, p_feature_id, null, true, now(), now() + v_interval,
    p_plan, v_price, '{}'::jsonb, now()
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
    purchased_price = v_price,
    updated_at = now()
  returning id into v_id;

  return v_id;
end;
$$;

-- -----------------------------------------------------------------------------
-- Admin: katalog satırına aylık/yıllık fiyat tanımla (NULL = o plan kapalı).
-- -----------------------------------------------------------------------------
create or replace function public.admin_set_profile_feature_pricing(
  p_feature_id uuid,
  p_price_monthly numeric,
  p_price_yearly numeric
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not private.current_user_is_admin() then
    raise exception 'admin_set_profile_feature_pricing: not admin' using errcode = '42501';
  end if;
  if p_price_monthly is not null and p_price_monthly < 0 then
    raise exception 'Aylık fiyat negatif olamaz' using errcode = '22023';
  end if;
  if p_price_yearly is not null and p_price_yearly < 0 then
    raise exception 'Yıllık fiyat negatif olamaz' using errcode = '22023';
  end if;

  update public.profile_feature_catalog
  set price_monthly = case when kind = 'badge' then null else p_price_monthly end,
      price_yearly = case when kind = 'badge' then null else p_price_yearly end,
      updated_at = now()
  where id = p_feature_id;
end;
$$;

revoke all on function public.get_my_purchasable_profile_features() from public;
revoke all on function public.purchase_my_profile_feature(uuid, text) from public;
revoke all on function public.admin_set_profile_feature_pricing(uuid, numeric, numeric) from public;

grant execute on function public.get_my_purchasable_profile_features() to authenticated, service_role;
grant execute on function public.purchase_my_profile_feature(uuid, text) to authenticated, service_role;
grant execute on function public.admin_set_profile_feature_pricing(uuid, numeric, numeric) to authenticated, service_role;

commit;

-- =============================================================================
-- DOĞRULAMA:
--   -- Satın alınabilir katalog:
--   SELECT code, price_monthly, price_yearly FROM public.profile_feature_catalog
--     WHERE price_monthly IS NOT NULL ORDER BY code;
--
--   -- Yetersiz bakiyeli kullanıcı satın almayı denerse:
--   SELECT public.purchase_my_profile_feature('<feature-id>', 'monthly');
--   -- Beklenen: "Yetersiz bakiye: ..." hatası (P0001).
--
--   -- Yeterli bakiyeli kullanıcı satın alınca:
--   SELECT purchase_plan, purchased_price, expires_at FROM public.user_profile_features
--     WHERE user_id = auth.uid() AND feature_id = '<feature-id>';
--   SELECT * FROM public.balance_transactions
--     WHERE reference_type = 'profile_feature' AND reference_id = '<feature-id>'
--     ORDER BY created_at DESC LIMIT 1; -- type = profile_feature_purchase
-- =============================================================================
