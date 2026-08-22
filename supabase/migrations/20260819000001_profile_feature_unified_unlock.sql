-- =============================================================================
-- Profil özellikleri: tek kilit modeli (2 ücretsiz + sipariş VEYA puan)
-- =============================================================================
-- İSTEK (kullanıcı, 2026-08-19):
--   1) "Profil Özelliklerim" ekranı aşağı kaydıra kaydıra bitmiyor; kategoriler
--      (kapak / profil resmi / tik-rozet ...) yan yana olmalı.
--   2) Ücretsiz özellik sayısı SADECE 2 olmalı.
--   3) Geri kalan TÜM özellikler ya "kaç sipariş verince açılır" ya da
--      "kaç puanla açılır" (mevcut puandan düşerek) kuralına bağlanmalı.
--   4) Puanla satın alma sorunu çözülmeli.
--
-- MEVCUT DURUM TESPİTİ (canlı DB üzerinde ölçüldü):
--   * 470 aktif katalog satırı: avatar_effect 180, effect 135, icon 120,
--     cover_effect 23, badge 12.
--   * 88 satır is_user_claimable = true (bedava). İstek: 2.
--   * Sipariş kilidi yalnız avatar_effect (30) ve cover_effect (23) satırında
--     tanımlıydı; effect/icon hiç sipariş yoluna bağlı değildi.
--   * Puan fiyatları 3.990-9.990 puan/ay. Kazanç tavanı reward_max_points=10 x
--     max_views_per_day=10 = GÜNDE 100 PUAN. Yani bir aylık dekorasyon için
--     40-100 GÜN kesintisiz reklam izlemek gerekiyordu -> satın alma yolu
--     fiilen ölüydü. (Bu, istek 4'ün asıl sebebi.)
--   * reward_points_apply_entry() lifetime_spent_points toplamına
--     'profile_feature_debit' entry_type'ını EKLEMİYORDU (20260818000006 yeni
--     entry_type'ı CHECK listelerine ekledi ama bu toplamı güncellemeyi
--     atladı). Sonuç: puanla alım bakiyeyi düşürüyor, ömür boyu harcama
--     muhasebesinde hiç görünmüyordu. Gerçek bir muhasebe hatası.
--
-- TASARIM:
--   1) reward_points_apply_entry() düzeltilir (profile_feature_debit ->
--      lifetime_spent_points). Fonksiyon reward_points_owner'a ait olduğu için
--      20260818000006'daki "geçici grant create + set role" deseni tekrarlanır.
--   2) is_user_claimable tüm katalogda kapatılır, tam 2 satırda açılır ve bu
--      2 satır SÜRESİZ olur (claim_duration_days = null). Bu 2 satırın sipariş
--      eşiği ve puan fiyatı NULL kalır (bedava olduklarını tek yerden okumak
--      için).
--   3) Kalan tüm aktif non-badge satırlarına HEM sipariş eşiği HEM puan fiyatı
--      atanır (iki alternatif yol, aynı öğe). Merdiven:
--        rn = kind içinde sıra (mevcut curated sipariş eşikleri önce gelir,
--             böylece 20260818000001'de elle seçilen 30 avatar / 23 kapak
--             öğesinin sırası korunur)
--        tier = rn <= 30 ? rn : 30 + ceil((rn - 30) / 3)
--        points_price_monthly = taban(kind) + 15 * tier
--        points_price_yearly  = monthly * 10   (2 ay bedava)
--      taban: icon 100, effect 150, avatar_effect 200, cover_effect 250.
--      Sonuç aralıkları: icon 1-60 sipariş / 115-1000 puan, effect 1-65 /
--      165-1125, avatar_effect 1-80 / 215-1400, cover_effect 1-23 / 265-595.
--      100 puan/gün tavanına göre en ucuz ~1 gün, en pahalı ~14 gün reklam.
--   4) Sipariş kilidi artık badge dışındaki TÜM kind'lerde geçerli: trigger,
--      admin RPC'si ve ilerleme RPC'si genişletilir.
--   5) Trigger yalnız YENİ teslimatta çalıştığı (ve hataları yutan savunmacı
--      desende olduğu) için iki ek güvenlik: (a) mevcut kullanıcılar için
--      tek seferlik backfill, (b) claim_my_profile_feature() artık sipariş
--      eşiğini karşılayan öğeyi de kabul eder — trigger sessizce başarısız
--      olsa bile kullanıcı öğesini alabilir.
--   6) Ekranın tek çağrıda kategori bazlı render edilebilmesi için birleşik
--      get_my_profile_feature_catalog(p_kind) ve hafif
--      get_my_profile_feature_summary() RPC'leri eklenir. Eski RPC'ler
--      (get_my_claimable / get_my_purchasable / assignments) admin ve geriye
--      dönük uyumluluk için DURUYOR.
--   7) İADE YOK politikası korunur (20260817000028).
-- =============================================================================

begin;

-- -----------------------------------------------------------------------------
-- 1) HATA DÜZELTME: profile_feature_debit lifetime_spent_points'e yazılmıyordu
--    Fonksiyon reward_points_owner'a ait; REPLACE için o role geçmek gerekiyor.
--    (20260818000006'daki grant/revoke deseninin aynısı.)
-- -----------------------------------------------------------------------------
grant create on schema public to reward_points_owner;
set role reward_points_owner;

create or replace function public.reward_points_apply_entry(
  p_user_id uuid,
  p_entry_type text,
  p_direction text,
  p_points bigint,
  p_reference_type text,
  p_reference_id uuid,
  p_idempotency_key text,
  p_metadata jsonb default '{}'::jsonb
) returns public.point_ledger_entries
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_account public.user_point_accounts%rowtype;
  v_entry public.point_ledger_entries%rowtype;
  v_after bigint;
begin
  select * into v_entry
  from public.point_ledger_entries as le
  where le.idempotency_key = p_idempotency_key;
  if found then
    if v_entry.user_id is distinct from p_user_id
       or v_entry.entry_type is distinct from p_entry_type
       or v_entry.direction is distinct from p_direction
       or v_entry.reference_type is distinct from p_reference_type
       or v_entry.points is distinct from p_points
       or v_entry.reference_id is distinct from p_reference_id
       or v_entry.metadata is distinct from coalesce(p_metadata, '{}'::jsonb) then
      raise exception 'IDEMPOTENCY_CONFLICT' using errcode = '23505';
    end if;
    return v_entry;
  end if;

  if p_points is null or p_points <= 0 then
    raise exception 'INVALID_POINTS' using errcode = '22023';
  end if;

  insert into public.user_point_accounts(user_id)
  values (p_user_id)
  on conflict (user_id) do nothing;

  select * into v_account
  from public.user_point_accounts as a
  where a.user_id = p_user_id
  for update;

  v_after := case when p_direction = 'credit'
    then v_account.balance_points + p_points
    else v_account.balance_points - p_points end;
  if v_after < 0 then
    raise exception 'INSUFFICIENT_POINTS' using errcode = 'P0001';
  end if;

  insert into public.point_ledger_entries (
    user_id, entry_type, direction, points, balance_before_points,
    balance_after_points, reference_type, reference_id, idempotency_key, metadata
  ) values (
    p_user_id, p_entry_type, p_direction, p_points, v_account.balance_points,
    v_after, p_reference_type, p_reference_id, p_idempotency_key,
    coalesce(p_metadata, '{}'::jsonb)
  ) returning * into v_entry;

  update public.user_point_accounts as a
  set balance_points = v_after,
      lifetime_earned_points = a.lifetime_earned_points
        + case when p_entry_type in ('ad_reward_credit', 'admin_correction_credit')
               then p_points else 0 end,
      -- DÜZELTME: 'profile_feature_debit' burada eksikti.
      lifetime_spent_points = a.lifetime_spent_points
        + case when p_entry_type in ('digital_order_debit', 'admin_correction_debit',
                                     'expiry_debit', 'profile_feature_debit')
               then p_points else 0 end,
      lifetime_refunded_points = a.lifetime_refunded_points
        + case when p_entry_type = 'digital_order_refund' then p_points else 0 end,
      version = a.version + 1,
      updated_at = clock_timestamp()
  where a.user_id = p_user_id;

  return v_entry;
end;
$$;

reset role;
revoke create on schema public from reward_points_owner;

-- Geçmişte puanla alınmış ama lifetime_spent_points'e yazılmamış kayıtları
-- telafi et (bakiye zaten doğru; yalnız ömür-boyu sayaç eksikti).
update public.user_point_accounts a
set lifetime_spent_points = a.lifetime_spent_points + m.missed,
    updated_at = now()
from (
  select user_id, sum(points) as missed
  from public.point_ledger_entries
  where entry_type = 'profile_feature_debit'
  group by user_id
) m
where m.user_id = a.user_id and m.missed > 0;

-- -----------------------------------------------------------------------------
-- 2) TAM 2 ÜCRETSİZ ÖZELLİK
--    Seçim: her biri farklı kategoriden bir "giriş seviyesi" öğe —
--    profil resmi için Hale Çerçeve · Piksel, profil efekti için Hale Piksel.
--    Süresiz (claim_duration_days = null): ücretsiz olanın süresi dolup
--    kullanıcıyı tekrar talep etmeye zorlaması anlamsız.
-- -----------------------------------------------------------------------------
update public.profile_feature_catalog
set is_user_claimable = false,
    claim_duration_days = null,
    updated_at = now()
where is_user_claimable = true;

update public.profile_feature_catalog
set is_user_claimable = true,
    claim_duration_days = null,
    unlock_after_orders = null,
    points_price_monthly = null,
    points_price_yearly = null,
    updated_at = now()
where code in ('unique_avatar_halo_pixel', 'unique_effect_halo_pixel');

-- -----------------------------------------------------------------------------
-- 3) SİPARİŞ MERDİVENİ + PUAN FİYATI (badge ve 2 ücretsiz hariç her aktif satır)
-- -----------------------------------------------------------------------------
with ranked as (
  select
    c.id,
    c.kind,
    row_number() over (
      partition by c.kind
      -- Mevcut curated eşikler (20260818000001) önce gelsin ki elle seçilmiş
      -- 30 avatar / 23 kapak öğesinin sırası bozulmasın.
      order by (c.unlock_after_orders is null), c.unlock_after_orders,
               c.priority desc, c.name
    ) as rn
  from public.profile_feature_catalog c
  where c.is_active = true
    and c.kind <> 'badge'
    and c.is_user_claimable = false
),
tiered as (
  select
    id,
    kind,
    case when rn <= 30 then rn::integer
         else 30 + ceil((rn - 30) / 3.0)::integer end as tier
  from ranked
)
update public.profile_feature_catalog c
set unlock_after_orders = t.tier,
    points_price_monthly = (
      case t.kind
        when 'icon' then 100
        when 'effect' then 150
        when 'avatar_effect' then 200
        when 'cover_effect' then 250
        else 150
      end + 15 * t.tier
    )::bigint,
    points_price_yearly = (
      (case t.kind
        when 'icon' then 100
        when 'effect' then 150
        when 'avatar_effect' then 200
        when 'cover_effect' then 250
        else 150
      end + 15 * t.tier) * 10
    )::bigint,
    updated_at = now()
from tiered t
where c.id = t.id;

-- Pasif satırların artık ne fiyatı ne eşiği olsun (mağazada görünmüyorlar).
update public.profile_feature_catalog
set unlock_after_orders = null,
    points_price_monthly = null,
    points_price_yearly = null,
    updated_at = now()
where is_active = false
  and (unlock_after_orders is not null
       or points_price_monthly is not null
       or points_price_yearly is not null);

-- Rozet/tik hiçbir zaman satın alınamaz veya siparişle açılamaz (yalnız admin).
update public.profile_feature_catalog
set unlock_after_orders = null,
    points_price_monthly = null,
    points_price_yearly = null,
    is_user_claimable = false,
    updated_at = now()
where kind = 'badge'
  and (unlock_after_orders is not null
       or points_price_monthly is not null
       or points_price_yearly is not null
       or is_user_claimable = true);

-- -----------------------------------------------------------------------------
-- 4) SİPARİŞ KİLİDİ ARTIK TÜM KİND'LERDE (badge hariç)
-- -----------------------------------------------------------------------------
create or replace function public.unlock_order_milestone_profile_features()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_completed_count integer;
begin
  if new.status = 'delivered' and (old.status is distinct from 'delivered') then
    select count(*) into v_completed_count
    from public.orders
    where user_id = new.user_id and status = 'delivered';

    insert into public.user_profile_features (
      user_id, feature_id, granted_by, is_enabled, starts_at, expires_at
    )
    select
      new.user_id, c.id, null, false, now(), null
    from public.profile_feature_catalog c
    where c.is_active = true
      and c.kind <> 'badge'
      and c.unlock_after_orders is not null
      and c.unlock_after_orders <= v_completed_count
    on conflict (user_id, feature_id) do nothing;
  end if;

  return new;
exception when others then
  raise notice 'unlock_order_milestone_profile_features hatası (görmezden gelindi): %', sqlerrm;
  return new;
end;
$$;

create or replace function public.admin_set_profile_feature_order_unlock(
  p_feature_id uuid,
  p_unlock_after_orders integer
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if not private.current_user_is_admin() then
    raise exception 'not admin' using errcode = '42501';
  end if;
  if p_unlock_after_orders is not null
     and (p_unlock_after_orders < 1 or p_unlock_after_orders > 1000) then
    raise exception 'Sipariş kilidi 1-1000 arasında olmalıdır' using errcode = '22023';
  end if;

  update public.profile_feature_catalog
  set unlock_after_orders = p_unlock_after_orders,
      updated_at = now()
  where id = p_feature_id
    and kind <> 'badge';
end;
$$;

-- İlerleme RPC'si: artık 4 kind için de satır döner.
create or replace function public.get_my_order_unlock_progress()
returns table (
  kind text,
  completed_orders integer,
  next_locked_code text,
  next_locked_name text,
  next_locked_unlock_after_orders integer,
  remaining_orders integer,
  total_items integer,
  unlocked_items integer
)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_completed_count integer;
begin
  if v_uid is null then
    raise exception 'authentication required' using errcode = '42501';
  end if;

  select count(*) into v_completed_count
  from public.orders
  where user_id = v_uid and status = 'delivered';

  return query
  with kinds(k) as (
    values ('avatar_effect'), ('cover_effect'), ('effect'), ('icon')
  ),
  next_item as (
    select
      ki.k,
      n.code,
      n.name,
      n.unlock_after_orders as unlock_at,
      (
        select count(*)::integer from public.profile_feature_catalog c
        where c.kind = ki.k and c.is_active = true and c.unlock_after_orders is not null
      ) as total,
      (
        select count(*)::integer from public.profile_feature_catalog c
        where c.kind = ki.k and c.is_active = true and c.unlock_after_orders is not null
          and c.unlock_after_orders <= v_completed_count
      ) as unlocked
    from kinds ki
    left join lateral (
      select c.code, c.name, c.unlock_after_orders
      from public.profile_feature_catalog c
      where c.kind = ki.k and c.is_active = true and c.unlock_after_orders is not null
        and c.unlock_after_orders > v_completed_count
      order by c.unlock_after_orders asc
      limit 1
    ) n on true
  )
  select
    ni.k,
    v_completed_count,
    ni.code,
    ni.name,
    ni.unlock_at,
    greatest(coalesce(ni.unlock_at, 0) - v_completed_count, 0),
    ni.total,
    ni.unlocked
  from next_item ni;
end;
$$;

-- -----------------------------------------------------------------------------
-- 5a) BACKFILL: hâlihazırda yeterli teslimatı olan kullanıcılara hak ettikleri
--     öğeleri ver. Trigger yalnız YENİ teslimatta çalıştığı için geçmiş
--     siparişler tek seferlik burada karşılanır.
-- -----------------------------------------------------------------------------
insert into public.user_profile_features (
  user_id, feature_id, granted_by, is_enabled, starts_at, expires_at
)
select o.user_id, c.id, null, false, now(), null
from (
  select user_id, count(*)::integer as delivered
  from public.orders
  where status = 'delivered' and user_id is not null
  group by user_id
) o
join public.profile_feature_catalog c
  on c.is_active = true
 and c.kind <> 'badge'
 and c.unlock_after_orders is not null
 and c.unlock_after_orders <= o.delivered
on conflict (user_id, feature_id) do nothing;

-- -----------------------------------------------------------------------------
-- 5b) claim_my_profile_feature(): ücretsiz öğelere EK OLARAK sipariş eşiğini
--     karşılayan öğeleri de kabul et. Trigger hataları yutan savunmacı
--     desende olduğu için (bkz. 20260818000001) bu, kullanıcının hak ettiği
--     öğeyi almasının garantili ikinci yolu.
-- -----------------------------------------------------------------------------
create or replace function public.claim_my_profile_feature(p_feature_id uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_days integer;
  v_free boolean;
  v_unlock_after integer;
  v_delivered integer;
  v_id uuid;
begin
  if v_uid is null then
    raise exception 'authentication required' using errcode = '42501';
  end if;

  select c.claim_duration_days, c.is_user_claimable, c.unlock_after_orders
  into v_days, v_free, v_unlock_after
  from public.profile_feature_catalog c
  where c.id = p_feature_id
    and c.is_active = true
    and c.kind <> 'badge';

  if not found then
    raise exception 'Bu özellik kullanıcı kullanımına açık değildir'
      using errcode = '42501';
  end if;

  if not coalesce(v_free, false) then
    -- Ücretsiz değil: yalnız sipariş eşiği karşılanmışsa talep edilebilir.
    -- (Puan yolu ayrı: purchase_my_profile_feature_with_points.)
    if v_unlock_after is null then
      raise exception 'Bu özellik kullanıcı kullanımına açık değildir'
        using errcode = '42501';
    end if;

    select count(*)::integer into v_delivered
    from public.orders
    where user_id = v_uid and status = 'delivered';

    if v_delivered < v_unlock_after then
      raise exception 'ORDER_THRESHOLD_NOT_MET' using errcode = '42501';
    end if;

    -- Siparişle açılan öğe süresizdir; talep süresi uygulanmaz.
    v_days := null;
  end if;

  insert into public.user_profile_features (
    user_id, feature_id, granted_by, is_enabled, starts_at, expires_at,
    config_override, updated_at
  ) values (
    v_uid, p_feature_id, null, true, now(),
    case when v_days is null then null else now() + make_interval(days => v_days) end,
    '{}'::jsonb, now()
  )
  on conflict (user_id, feature_id) do update set
    is_enabled = true,
    starts_at = case
      when user_profile_features.expires_at is not null
       and user_profile_features.expires_at <= now() then now()
      else user_profile_features.starts_at end,
    expires_at = case
      when user_profile_features.granted_by is null
       and (user_profile_features.expires_at is null or user_profile_features.expires_at <= now())
      then case when v_days is null then null else now() + make_interval(days => v_days) end
      else user_profile_features.expires_at end,
    updated_at = now()
  returning id into v_id;

  return v_id;
end;
$$;

-- -----------------------------------------------------------------------------
-- 6a) BİRLEŞİK KATALOG RPC'si — ekran kategori (tab) başına TEK çağrı yapar.
--     Sıralama: önce en yakın kilit (motivasyon), ücretsizler en başta.
-- -----------------------------------------------------------------------------
create or replace function public.get_my_profile_feature_catalog(
  p_kind text,
  p_limit integer default 300,
  p_offset integer default 0
)
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
  is_owned boolean,
  is_free boolean,
  is_admin_granted boolean,
  is_purchased boolean,
  purchase_plan text,
  unlock_after_orders integer,
  order_unlock_met boolean,
  points_price_monthly bigint,
  points_price_yearly bigint,
  starts_at timestamptz,
  expires_at timestamptz
)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_delivered integer;
begin
  if v_uid is null then
    raise exception 'authentication required' using errcode = '42501';
  end if;
  if p_kind not in ('effect', 'avatar_effect', 'cover_effect', 'icon', 'badge') then
    raise exception 'Geçersiz kategori: %', p_kind using errcode = '22023';
  end if;

  select count(*)::integer into v_delivered
  from public.orders
  where user_id = v_uid and status = 'delivered';

  return query
  select
    upf.id,
    c.id,
    c.code,
    c.kind,
    c.name,
    c.description,
    c.renderer_key,
    c.primary_color,
    c.secondary_color,
    coalesce(c.config, '{}'::jsonb) || coalesce(upf.config_override, '{}'::jsonb),
    c.priority,
    coalesce(upf.is_enabled, false),
    (upf.id is not null
      and upf.starts_at <= now()
      and (upf.expires_at is null or upf.expires_at > now())),
    coalesce(c.is_user_claimable, false),
    (upf.id is not null and upf.granted_by is not null),
    (upf.id is not null and upf.purchase_plan is not null),
    upf.purchase_plan,
    c.unlock_after_orders,
    (c.unlock_after_orders is not null and c.unlock_after_orders <= v_delivered),
    c.points_price_monthly,
    c.points_price_yearly,
    upf.starts_at,
    upf.expires_at
  from public.profile_feature_catalog c
  left join public.user_profile_features upf
    on upf.feature_id = c.id and upf.user_id = v_uid
  where c.is_active = true
    and c.kind = p_kind
    -- Rozet/tik yalnız kullanıcıya verilmişse listelenir (mağazada satılmaz).
    and (c.kind <> 'badge' or upf.id is not null)
  order by
    coalesce(c.is_user_claimable, false) desc,
    (upf.id is null),
    coalesce(c.unlock_after_orders, 2147483647) asc,
    c.priority desc,
    c.name
  limit greatest(coalesce(p_limit, 300), 1)
  offset greatest(coalesce(p_offset, 0), 0);
end;
$$;

-- -----------------------------------------------------------------------------
-- 6b) ÖZET RPC'si — puan bakiyesi, teslim edilen sipariş sayısı, kazanma/harcama
--     anahtarları ve kategori başına sahiplik sayacı. Ekran başlığı bunu tek
--     çağrıda okur (önceden 3 ayrı istek gerekiyordu).
-- -----------------------------------------------------------------------------
create or replace function public.get_my_profile_feature_summary()
returns jsonb
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_delivered integer;
  v_points bigint;
  v_settings public.ad_settings%rowtype;
begin
  if v_uid is null then
    raise exception 'authentication required' using errcode = '42501';
  end if;

  select count(*)::integer into v_delivered
  from public.orders
  where user_id = v_uid and status = 'delivered';

  select coalesce(balance_points, 0) into v_points
  from public.user_point_accounts where user_id = v_uid;

  select * into v_settings from public.ad_settings where id = 1;

  return jsonb_build_object(
    'completed_orders', v_delivered,
    'balance_points', coalesce(v_points, 0),
    'points_earn_enabled', coalesce(v_settings.is_enabled, false)
      and coalesce(v_settings.reward_points_earn_enabled, false),
    'points_spend_enabled', coalesce(v_settings.reward_points_spend_enabled, false)
      and coalesce(v_settings.reward_feature_mode, '') = 'enabled',
    'kinds', (
      select coalesce(jsonb_object_agg(s.kind, jsonb_build_object(
        'total', s.total,
        'owned', s.owned,
        'next_unlock_at', s.next_unlock_at,
        'next_unlock_name', s.next_unlock_name
      )), '{}'::jsonb)
      from (
        select
          c.kind,
          count(*)::integer as total,
          count(*) filter (
            where upf.id is not null
              and upf.starts_at <= now()
              and (upf.expires_at is null or upf.expires_at > now())
          )::integer as owned,
          min(c.unlock_after_orders) filter (
            where c.unlock_after_orders > v_delivered
          ) as next_unlock_at,
          (array_agg(c.name order by c.unlock_after_orders asc)
             filter (where c.unlock_after_orders > v_delivered))[1] as next_unlock_name
        from public.profile_feature_catalog c
        left join public.user_profile_features upf
          on upf.feature_id = c.id and upf.user_id = v_uid
        where c.is_active = true and c.kind <> 'badge'
        group by c.kind
      ) s
    )
  );
end;
$$;

revoke all on function public.get_my_profile_feature_catalog(text, integer, integer) from public;
grant execute on function public.get_my_profile_feature_catalog(text, integer, integer)
  to authenticated, service_role;

revoke all on function public.get_my_profile_feature_summary() from public;
grant execute on function public.get_my_profile_feature_summary()
  to authenticated, service_role;

-- -----------------------------------------------------------------------------
-- 7) PUAN KAZANMAYI AÇ (kullanıcı onayı: 2026-08-19)
--    test_mode = true olduğu için canlıda AdMob TEST reklamı gösterilir;
--    gerçek reklam yayını için test_mode ayrıca kapatılmalıdır.
-- -----------------------------------------------------------------------------
update public.ad_settings
set is_enabled = true,
    reward_points_earn_enabled = true,
    updated_at = now()
where id = 1;

commit;

-- =============================================================================
-- Kontrol:
--   -- Tam 2 ücretsiz:
--   select count(*) from public.profile_feature_catalog where is_user_claimable;
--   -- Beklenen: 2
--
--   -- Aktif non-badge satırların TAMAMI hem eşiğe hem fiyata bağlı olmalı:
--   select count(*) from public.profile_feature_catalog
--   where is_active and kind <> 'badge' and not is_user_claimable
--     and (unlock_after_orders is null or points_price_monthly is null);
--   -- Beklenen: 0
--
--   -- Merdiven aralıkları:
--   select kind, min(unlock_after_orders), max(unlock_after_orders),
--          min(points_price_monthly), max(points_price_monthly)
--   from public.profile_feature_catalog
--   where is_active and unlock_after_orders is not null group by kind order by kind;
--
--   -- Muhasebe düzeltmesi yerinde mi:
--   select pg_get_functiondef(oid) like '%expiry_debit%profile_feature_debit%'
--   from pg_proc where proname = 'reward_points_apply_entry';
--   -- Beklenen: true
-- =============================================================================
