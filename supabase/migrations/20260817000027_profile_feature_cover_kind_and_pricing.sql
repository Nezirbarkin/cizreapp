-- =============================================================================
-- Ücretli profil/kapak dekorasyonları: yeni "cover_effect" türü + fiyatlandırma
-- =============================================================================
-- İSTEK: Bakiyeden (cizreapp bakiyesi) aylık/yıllık satın alınabilen, sadece
-- profil resmine VEYA sadece kapak fotoğrafına uygulanan hayvan/doğa figürü
-- temalı yeni dekorasyonlar (yılanın avatar çerçevesine dolanması, kelebeğin
-- profile konması vb.).
--
-- TASARIM: 20260817000004/6/12 üzerine ileri yönlü genişletmedir; eski
-- migration'lar değiştirilmez.
--   1) "cover_effect" yeni bir kind değeri olarak eklenir — "avatar_effect"in
--      kapak fotoğrafı karşılığı. Böylece bir dekorasyon ya sadece avatara
--      (avatar_effect) ya da sadece kapağa (cover_effect) uygulanır, asla
--      ikisine birden.
--   2) profile_feature_catalog'a price_monthly/price_yearly eklenir. Her
--      ikisi de NULL olan satırlar mevcut ücretsiz sistemle (admin ataması /
--      is_user_claimable) aynen çalışmaya devam eder — geriye dönük uyumlu.
--   3) user_profile_features'a purchase_plan/purchased_price eklenir; bir
--      satın alma anındaki fiyat kalıcı olarak saklanır (katalog fiyatı
--      sonradan değişse bile geçmiş kayıt sabit kalır — ilanlar.paid_fee
--      deseniyle aynı, bkz. 20260817000024).
--   4) El yazımı (hand-authored), az sayıda ama özenli yeni dekorasyon:
--      4 avatar yaratığı (yılan, kelebek, ateş böceği, pati) ve 4 kapak
--      sahnesi (kelebek çayırı, aurora, yaprak, alacakaranlık), her biri 2
--      renk varyantıyla. is_user_claimable=false: bunlar ücretsiz elde
--      edilemez, yalnız satın alınabilir (claim_my_profile_feature zaten
--      is_user_claimable=true şartı arıyor, bu satırlar orada elenir).
--      Fiyatlar admin panelinden değiştirilebilir başlangıç değerleridir.
-- =============================================================================

begin;

alter table public.profile_feature_catalog
  drop constraint if exists profile_feature_catalog_kind_check;
alter table public.profile_feature_catalog
  add constraint profile_feature_catalog_kind_check
  check (kind in ('effect', 'avatar_effect', 'cover_effect', 'icon', 'badge'));

alter table public.profile_feature_catalog
  add column if not exists price_monthly numeric(10,2) check (price_monthly is null or price_monthly >= 0),
  add column if not exists price_yearly numeric(10,2) check (price_yearly is null or price_yearly >= 0);

comment on column public.profile_feature_catalog.price_monthly is
  'Aylık satın alma fiyatı (cizreapp bakiyesi/TL). NULL = aylık plan yok.';
comment on column public.profile_feature_catalog.price_yearly is
  'Yıllık satın alma fiyatı (cizreapp bakiyesi/TL). NULL = yıllık plan yok.';

alter table public.user_profile_features
  add column if not exists purchase_plan text check (purchase_plan is null or purchase_plan in ('monthly', 'yearly')),
  add column if not exists purchased_price numeric(10,2) check (purchased_price is null or purchased_price >= 0);

comment on column public.user_profile_features.purchase_plan is
  'Satın alma anında seçilen plan (monthly/yearly). Admin ataması veya ücretsiz self-claim ise NULL.';
comment on column public.user_profile_features.purchased_price is
  'Satın alma anında fiilen tahsil edilen tutar (katalog fiyatı sonradan değişse bile sabit kalır).';

create index if not exists profile_feature_catalog_purchasable_idx
  on public.profile_feature_catalog(kind, priority desc)
  where is_active = true and (price_monthly is not null or price_yearly is not null);

-- -----------------------------------------------------------------------------
-- Avatar-only yaratık dekorasyonları (kind = avatar_effect, satın alınabilir)
-- -----------------------------------------------------------------------------
with creatures(renderer_key, title, description, color1, color2, priority, price_monthly, price_yearly) as (
  values
    ('snake_coil', 'Yılan Çerçeve', 'Yılan profil fotoğrafı çerçevesine dolanır', '#43A047', '#1B5E20', 500, 59.90, 549.00),
    ('butterfly_land', 'Kelebek', 'Kelebek periyodik olarak profiline konar', '#EC407A', '#F8BBD0', 501, 49.90, 459.00),
    ('firefly_dance', 'Ateş Böceği', 'Ateş böcekleri profil çevresinde dans eder', '#CDDC39', '#FFF176', 502, 39.90, 369.00),
    ('cat_paw_peek', 'Kedi Patisi', 'Kedi patisi profilin alt kenarından belirir', '#8D6E63', '#D7CCC8', 503, 44.90, 409.00)
), variants(suffix, color1, color2) as (
  values ('a', null, null), ('b', '#00BFA5', '#1DE9B6')
)
insert into public.profile_feature_catalog (
  code, kind, name, description, renderer_key, primary_color, secondary_color,
  config, priority, is_active, is_user_claimable, price_monthly, price_yearly
)
select
  'purchase_avatar_' || c.renderer_key || '_' || v.suffix,
  'avatar_effect',
  c.title || (case when v.suffix = 'a' then '' else ' · Alternatif' end),
  c.description,
  c.renderer_key,
  coalesce(v.color1, c.color1),
  coalesce(v.color2, c.color2),
  jsonb_build_object('speed', 1.0, 'thickness', 2.5, 'variant', v.suffix),
  c.priority,
  true,
  false,
  c.price_monthly,
  c.price_yearly
from creatures c cross join variants v
on conflict (code) do update set
  name = excluded.name,
  description = excluded.description,
  renderer_key = excluded.renderer_key,
  primary_color = excluded.primary_color,
  secondary_color = excluded.secondary_color,
  config = excluded.config,
  is_active = true,
  is_user_claimable = false,
  price_monthly = excluded.price_monthly,
  price_yearly = excluded.price_yearly,
  updated_at = now();

-- -----------------------------------------------------------------------------
-- Cover-only sahne dekorasyonları (kind = cover_effect, satın alınabilir)
-- -----------------------------------------------------------------------------
with scenes(renderer_key, title, description, color1, color2, priority, price_monthly, price_yearly) as (
  values
    ('butterfly_meadow_cover', 'Kelebek Çayırı', 'Kapak fotoğrafı boyunca kelebekler süzülür', '#EC407A', '#F8BBD0', 600, 69.90, 639.00),
    ('aurora_veil_cover', 'Aurora Perdesi', 'Kapağın üst kenarında dalgalanan ışık perdesi', '#00BFA5', '#7C4DFF', 601, 64.90, 599.00),
    ('petal_drift_cover', 'Yaprak Dansı', 'Kapak boyunca süzülen çiçek yaprakları', '#F06292', '#FCE4EC', 602, 54.90, 499.00),
    ('firefly_dusk_cover', 'Alacakaranlık', 'Alacakaranlık tonu ve parıldayan ateş böcekleri', '#3949AB', '#FFD740', 603, 59.90, 549.00)
), variants(suffix, color1, color2) as (
  values ('a', null, null), ('b', '#FF7043', '#FFCCBC')
)
insert into public.profile_feature_catalog (
  code, kind, name, description, renderer_key, primary_color, secondary_color,
  config, priority, is_active, is_user_claimable, price_monthly, price_yearly
)
select
  'purchase_cover_' || s.renderer_key || '_' || v.suffix,
  'cover_effect',
  s.title || (case when v.suffix = 'a' then '' else ' · Alternatif' end),
  s.description,
  s.renderer_key,
  coalesce(v.color1, s.color1),
  coalesce(v.color2, s.color2),
  jsonb_build_object('speed', 1.0, 'density', 1.0, 'variant', v.suffix),
  s.priority,
  true,
  false,
  s.price_monthly,
  s.price_yearly
from scenes s cross join variants v
on conflict (code) do update set
  name = excluded.name,
  description = excluded.description,
  renderer_key = excluded.renderer_key,
  primary_color = excluded.primary_color,
  secondary_color = excluded.secondary_color,
  config = excluded.config,
  is_active = true,
  is_user_claimable = false,
  price_monthly = excluded.price_monthly,
  price_yearly = excluded.price_yearly,
  updated_at = now();

commit;

-- Kontrol:
-- select code, kind, price_monthly, price_yearly from public.profile_feature_catalog
-- where price_monthly is not null order by kind, code;
-- Beklenen: 8 avatar_effect + 8 cover_effect satır.
