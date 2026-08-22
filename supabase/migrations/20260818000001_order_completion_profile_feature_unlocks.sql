-- =============================================================================
-- Sipariş tamamlama ile profil/kapak özelliği kilidi açma
-- =============================================================================
-- İSTEK: "1 sipariş tamamlandı -> bu özelliği artık kullanabilirsin" (örnek:
-- profil resmine yağmur yağdırma), profil resmi için 30 ve kapak fotoğrafı
-- için mevcut kataloğun izin verdiği kadar (23) BENZERSİZ görsel özellik,
-- kullanıcının tamamladığı sipariş sayısına göre sırayla açılsın.
--
-- Mevcut sistem (20260817000005 ve devamı) zaten bir kozmetik katalog +
-- atama altyapısı sağlıyor: admin manuel atama, admin "self-claimable"
-- işaretlemesi (ücretsiz kullanıcı talebi) ve bakiye ile satın alma. Bu
-- migration DÖRDÜNCÜ bir kilit açma yolu ekliyor: "N. tamamlanmış sipariş".
--
-- TASARIM:
--   1) profile_feature_catalog.unlock_after_orders (nullable int) — bu
--      katalog satırının kullanıcının kaçıncı tamamlanmış (delivered)
--      siparişinde otomatik açılacağını belirtir. NULL = sipariş ile açılan
--      bir öğe değil (mevcut yollarla değişmez).
--   2) Avatar (avatar_effect) ve kapak (cover_effect) listeleri BİRBİRİNDEN
--      BAĞIMSIZ sıralanır: her ikisi de aynı "toplam tamamlanmış sipariş
--      sayısı" girdisini kullanır ama kendi 1..N sırasında ilerler.
--   3) orders tablosunda status 'delivered' olduğunda (mevcut
--      trigger_create_seller_earnings ile AYNI savunmacı desende, ayrı bir
--      trigger olarak) kullanıcının o ana kadar hak ettiği ama henüz
--      user_profile_features'a eklenmemiş satırlar otomatik eklenir
--      (is_enabled = false — kullanıcı "Profil Özelliklerim" ekranından
--      kendi açar, satın alma/self-claim akışıyla tutarlı).
--   4) get_my_order_unlock_progress(): kullanıcıya ilerleme durumu
--      (tamamlanmış sipariş sayısı, avatar/kapak için sıradaki kilitli öğe,
--      kalan öğe sayısı) döner.
--   5) admin_set_profile_feature_order_unlock(): admin panelinden bir
--      katalog satırının kaçıncı siparişte açılacağını ayarlar.
-- =============================================================================

begin;

alter table public.profile_feature_catalog
  add column if not exists unlock_after_orders integer;

alter table public.profile_feature_catalog
  drop constraint if exists profile_feature_catalog_unlock_after_orders_check;
alter table public.profile_feature_catalog
  add constraint profile_feature_catalog_unlock_after_orders_check
  check (unlock_after_orders is null or unlock_after_orders between 1 and 1000);

create index if not exists profile_feature_catalog_order_unlock_idx
  on public.profile_feature_catalog(kind, unlock_after_orders)
  where is_active = true and unlock_after_orders is not null;

-- -----------------------------------------------------------------------------
-- 30 benzersiz profil resmi (avatar_effect) özelliği: hayvan/yaratık
-- çerçeveleri + fotoğraf-üstü doğa/atmosfer efektleri + fotoğraf-üstü
-- dijital efektler + tek-renk halka temaları. Her satır farklı bir
-- renderer_key kullanır (hiçbiri aynı animasyonun sadece renk kopyası
-- değildir). Her temanın "a" / "01" (temel renk) varyantı milestone olarak
-- seçildi; diğer renk varyantları satın alınabilir olarak kalmaya devam eder.
-- -----------------------------------------------------------------------------
with avatar_order(code, ord) as (
  values
    ('purchase_avatar_snake_coil_a', 1),
    ('purchase_avatar_butterfly_land_a', 2),
    ('purchase_avatar_firefly_dance_a', 3),
    ('purchase_avatar_cat_paw_peek_a', 4),
    ('purchase_avatar_koi_swim_a', 5),
    ('purchase_avatar_owl_perch_a', 6),
    ('purchase_avatar_dragon_wisp_a', 7),
    ('purchase_avatar_royal_gold_frame_a', 8),
    ('purchase_avatar_star_confetti_frame_a', 9),
    ('purchase_avatar_photo_rain_overlay_a', 10),
    ('purchase_avatar_photo_snow_overlay_a', 11),
    ('purchase_avatar_photo_fog_overlay_a', 12),
    ('purchase_avatar_photo_heat_wave_a', 13),
    ('purchase_avatar_photo_ice_frost_a', 14),
    ('purchase_avatar_photo_bubble_overlay_a', 15),
    ('purchase_avatar_photo_smoke_drift_a', 16),
    ('purchase_avatar_photo_flame_overlay_a', 17),
    ('purchase_avatar_photo_sun_flare_a', 18),
    ('purchase_avatar_photo_bokeh_lights_a', 19),
    ('purchase_avatar_photo_lightning_strike_a', 20),
    ('purchase_avatar_photo_neon_glitch_a', 21),
    ('purchase_avatar_photo_vhs_static_a', 22),
    ('purchase_avatar_photo_film_grain_a', 23),
    ('purchase_avatar_photo_confetti_burst_a', 24),
    ('purchase_avatar_photo_crack_glass_a', 25),
    ('purchase_avatar_photo_old_tv_a', 26),
    ('avatar_neon_ring_01', 27),
    ('avatar_fire_ring_01', 28),
    ('avatar_rainbow_ring_01', 29),
    ('avatar_crown_glow_01', 30)
)
update public.profile_feature_catalog c
set unlock_after_orders = a.ord,
    updated_at = now()
from avatar_order a
where c.code = a.code;

-- -----------------------------------------------------------------------------
-- Kapak fotoğrafı (cover_effect) özellikleri: kodda CoverEffectFrame yalnız
-- 9 farklı sahne render edebildiği için (bkz. lib/kullaniciozellikler/
-- widgets/cover_effect_frame.dart) tam 30'a çıkılamıyor. 9 sahnenin tüm renk
-- varyantlarıyla (4 sahne x 2 + 5 sahne x 3 = 23 satır) sıralı liste
-- oluşturuluyor: önce 9 farklı sahne (1-9), sonra "b" renk varyantları
-- (10-18), sonra 3. varyantı olan sahnelerin "c" varyantları (19-23).
-- -----------------------------------------------------------------------------
with cover_order(code, ord) as (
  values
    ('purchase_cover_butterfly_meadow_cover_a', 1),
    ('purchase_cover_aurora_veil_cover_a', 2),
    ('purchase_cover_petal_drift_cover_a', 3),
    ('purchase_cover_firefly_dusk_cover_a', 4),
    ('purchase_cover_starry_night_cover_a', 5),
    ('purchase_cover_snowfall_cover_a', 6),
    ('purchase_cover_golden_hour_cover_a', 7),
    ('purchase_cover_ocean_wave_cover_a', 8),
    ('purchase_cover_firework_burst_cover_a', 9),
    ('purchase_cover_butterfly_meadow_cover_b', 10),
    ('purchase_cover_aurora_veil_cover_b', 11),
    ('purchase_cover_petal_drift_cover_b', 12),
    ('purchase_cover_firefly_dusk_cover_b', 13),
    ('purchase_cover_starry_night_cover_b', 14),
    ('purchase_cover_snowfall_cover_b', 15),
    ('purchase_cover_golden_hour_cover_b', 16),
    ('purchase_cover_ocean_wave_cover_b', 17),
    ('purchase_cover_firework_burst_cover_b', 18),
    ('purchase_cover_starry_night_cover_c', 19),
    ('purchase_cover_snowfall_cover_c', 20),
    ('purchase_cover_golden_hour_cover_c', 21),
    ('purchase_cover_ocean_wave_cover_c', 22),
    ('purchase_cover_firework_burst_cover_c', 23)
)
update public.profile_feature_catalog c
set unlock_after_orders = co.ord,
    updated_at = now()
from cover_order co
where c.code = co.code;

-- -----------------------------------------------------------------------------
-- Trigger: sipariş 'delivered' olduğunda hak edilen özellikleri otomatik ekle.
-- create_seller_earnings_on_delivery() ile aynı savunmacı desen: hata asla
-- sipariş güncellemesini engellemez.
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
      and c.kind in ('avatar_effect', 'cover_effect')
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

drop trigger if exists trigger_unlock_profile_features_on_delivery on public.orders;
create trigger trigger_unlock_profile_features_on_delivery
  after update of status on public.orders
  for each row
  execute function public.unlock_order_milestone_profile_features();

comment on function public.unlock_order_milestone_profile_features is
  'Sipariş delivered durumuna geçtiğinde kullanıcının tamamlanmış sipariş sayısına göre hak ettiği sipariş-kilitli profil/kapak özelliklerini user_profile_features''a ekler (is_enabled=false, kullanıcı kendi açar).';

-- -----------------------------------------------------------------------------
-- Kullanıcıya ilerleme durumu: tamamlanmış sipariş sayısı + avatar/kapak
-- için sıradaki kilitli öğe + kalan öğe sayısı.
-- -----------------------------------------------------------------------------
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
  with kinds(k) as (values ('avatar_effect'), ('cover_effect')),
  next_item as (
    select
      ki.k,
      (
        select c.code from public.profile_feature_catalog c
        where c.kind = ki.k and c.is_active = true and c.unlock_after_orders is not null
          and c.unlock_after_orders > v_completed_count
        order by c.unlock_after_orders asc limit 1
      ) as code,
      (
        select c.name from public.profile_feature_catalog c
        where c.kind = ki.k and c.is_active = true and c.unlock_after_orders is not null
          and c.unlock_after_orders > v_completed_count
        order by c.unlock_after_orders asc limit 1
      ) as name,
      (
        select c.unlock_after_orders from public.profile_feature_catalog c
        where c.kind = ki.k and c.is_active = true and c.unlock_after_orders is not null
          and c.unlock_after_orders > v_completed_count
        order by c.unlock_after_orders asc limit 1
      ) as unlock_at,
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

revoke all on function public.get_my_order_unlock_progress() from public;
grant execute on function public.get_my_order_unlock_progress() to authenticated, service_role;

-- -----------------------------------------------------------------------------
-- Admin: bir katalog satırının kaçıncı tamamlanmış siparişte açılacağını
-- ayarlar (admin_set_profile_feature_claimable ile aynı yetki deseni).
-- -----------------------------------------------------------------------------
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
    and kind in ('avatar_effect', 'cover_effect');
end;
$$;

revoke all on function public.admin_set_profile_feature_order_unlock(uuid, integer) from public;
grant execute on function public.admin_set_profile_feature_order_unlock(uuid, integer)
  to authenticated, service_role;

commit;

-- Kontrol:
-- select kind, count(*) from public.profile_feature_catalog
-- where unlock_after_orders is not null group by kind order by kind;
-- Beklenen: avatar_effect = 30, cover_effect = 23.
