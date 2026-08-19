-- =============================================================================
-- Daha fazla benzersiz, şık satın alınabilir dekorasyon
-- =============================================================================
-- İSTEK: "çok fazla benzersiz profil resmi, kapak fotoğrafı, çerçeve ve
-- profil/hesaba dinamik daha şık yeniler ekle" — 20260817000027'de eklenen
-- ilk 8 avatar + 8 kapak dekorasyonuna ek olarak:
--   - 5 yeni avatar çerçevesi/yaratığı (kraliyet altın çerçeve, koi balığı,
--     baykuş, ejderha alevi, yıldız konfeti çerçevesi)
--   - 5 yeni kapak sahnesi (yıldızlı gece, kar yağışı, altın saat, okyanus
--     dalgası, havai fişek)
--   - 5 yeni TÜM PROFİLİ kaplayan premium hale ("kind = effect" — sadece
--     avatar/kapak değil, hesabın tamamına uygulanan lüks efektler: kraliyet
--     halesi, galaksi sarmalı, anka alevi, kristal parıltı, fırtına)
-- Her biri 3 renk varyantıyla (a/b/c) — toplam 45 yeni katalog satırı.
--
-- kind kısıtlaması zaten 20260817000027'de ('effect','avatar_effect',
-- 'cover_effect','icon','badge') genişletildiği için burada şema değişikliği
-- YOK — sadece yeni katalog satırları ekleniyor. Fiyatlandırma admin
-- panelinden (admin_set_profile_feature_pricing RPC, 20260817000028)
-- istendiği zaman değiştirilebilir; bu migration sadece başlangıç fiyatlarını
-- tanımlar.
-- =============================================================================

begin;

-- -----------------------------------------------------------------------------
-- Avatar-only yeni çerçeveler/yaratıklar (kind = avatar_effect)
-- -----------------------------------------------------------------------------
with creatures(renderer_key, title, description, color1, color2, priority, price_monthly, price_yearly) as (
  values
    ('royal_gold_frame', 'Kraliyet Altın Çerçeve', 'Dönen altın halka ve parıldayan mücevher noktaları', '#F9A825', '#FFD54F', 510, 79.90, 729.00),
    ('koi_swim', 'Koi Balığı', 'Koi balığı kuyruğunu dalgalandırarak avatar çevresinde yüzer', '#EF5350', '#FFCDD2', 511, 54.90, 499.00),
    ('owl_perch', 'Gece Baykuşu', 'Baykuş periyodik olarak avatarın üstüne konar, gözlerini kırpar', '#5D4037', '#D7CCC8', 512, 49.90, 459.00),
    ('dragon_wisp', 'Ejderha Alevi', 'Avatar çevresinde dolanan parıldayan alev izi', '#FF5722', '#FFAB91', 513, 64.90, 599.00),
    ('star_confetti_frame', 'Yıldız Konfeti Çerçevesi', 'İnce halka ve patlayan yıldız konfetileri', '#AB47BC', '#E1BEE7', 514, 44.90, 409.00)
), variants(suffix, color1, color2) as (
  values ('a', null, null), ('b', '#00BFA5', '#1DE9B6'), ('c', '#FF7043', '#FFAB91')
)
insert into public.profile_feature_catalog (
  code, kind, name, description, renderer_key, primary_color, secondary_color,
  config, priority, is_active, is_user_claimable, price_monthly, price_yearly
)
select
  'purchase_avatar_' || c.renderer_key || '_' || v.suffix,
  'avatar_effect',
  c.title || (case when v.suffix = 'a' then '' else ' · Alternatif ' || upper(v.suffix) end),
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
-- Cover-only yeni sahneler (kind = cover_effect)
-- -----------------------------------------------------------------------------
with scenes(renderer_key, title, description, color1, color2, priority, price_monthly, price_yearly) as (
  values
    ('starry_night_cover', 'Yıldızlı Gece', 'Parıldayan yıldızlar ve kayan yıldız', '#283593', '#7986CB', 610, 59.90, 549.00),
    ('snowfall_cover', 'Kar Yağışı', 'Kapak boyunca yumuşak kar yağışı', '#90CAF9', '#E3F2FD', 611, 49.90, 459.00),
    ('golden_hour_cover', 'Altın Saat', 'Sıcak tonlarda süzülen ışık huzmeleri', '#FB8C00', '#FFE0B2', 612, 69.90, 639.00),
    ('ocean_wave_cover', 'Okyanus Dalgası', 'Alt kenarda dalgalanan iki katmanlı deniz', '#0288D1', '#B3E5FC', 613, 54.90, 499.00),
    ('firework_burst_cover', 'Havai Fişek', 'Periyodik havai fişek patlamaları', '#D81B60', '#F8BBD0', 614, 64.90, 599.00)
), variants(suffix, color1, color2) as (
  values ('a', null, null), ('b', '#FF7043', '#FFCCBC'), ('c', '#7E57C2', '#D1C4E9')
)
insert into public.profile_feature_catalog (
  code, kind, name, description, renderer_key, primary_color, secondary_color,
  config, priority, is_active, is_user_claimable, price_monthly, price_yearly
)
select
  'purchase_cover_' || s.renderer_key || '_' || v.suffix,
  'cover_effect',
  s.title || (case when v.suffix = 'a' then '' else ' · Alternatif ' || upper(v.suffix) end),
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

-- -----------------------------------------------------------------------------
-- Hesabın tamamını kaplayan premium haleler (kind = effect) — sadece avatar
-- veya kapak değil, tüm profil sayfasında görünür (bkz. ProfilePrivilegesOverlay).
-- -----------------------------------------------------------------------------
with auras(renderer_key, title, description, color1, color2, priority, price_monthly, price_yearly) as (
  values
    ('royal_aura', 'Kraliyet Halesi', 'Tüm profilde merkezi altın parıltı ve dönen ışık noktaları', '#F9A825', '#FFF176', 710, 99.90, 899.00),
    ('galaxy_swirl', 'Galaksi Sarmalı', 'Merkezden dışa doğru dönen yıldız tozu sarmalı', '#5C6BC0', '#B39DDB', 711, 89.90, 819.00),
    ('phoenix_flame', 'Anka Alevi', 'Tüm profilde yükselen parıldayan alev parçacıkları', '#FF5722', '#FFCCBC', 712, 94.90, 859.00),
    ('crystal_shimmer', 'Kristal Parıltı', 'Dönen küçük elmas parçacıklarıyla parıltı', '#26C6DA', '#B2EBF2', 713, 79.90, 729.00),
    ('thunder_storm', 'Gök Gürültülü Fırtına', 'Yağmur ve periyodik şimşek flaşıyla dramatik hava', '#37474F', '#90A4AE', 714, 84.90, 769.00)
), variants(suffix, color1, color2) as (
  values ('a', null, null), ('b', '#F9A825', '#FFF176'), ('c', '#5C6BC0', '#9FA8DA')
)
insert into public.profile_feature_catalog (
  code, kind, name, description, renderer_key, primary_color, secondary_color,
  config, priority, is_active, is_user_claimable, price_monthly, price_yearly
)
select
  'purchase_profile_' || a.renderer_key || '_' || v.suffix,
  'effect',
  a.title || (case when v.suffix = 'a' then '' else ' · Alternatif ' || upper(v.suffix) end),
  a.description,
  a.renderer_key,
  coalesce(v.color1, a.color1),
  coalesce(v.color2, a.color2),
  jsonb_build_object('speed', 1.0, 'intensity', 1.0, 'variant', v.suffix),
  a.priority,
  true,
  false,
  a.price_monthly,
  a.price_yearly
from auras a cross join variants v
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
-- select kind, count(*) from public.profile_feature_catalog
-- where price_monthly is not null
--   and (code like 'purchase_avatar_%' or code like 'purchase_cover_%' or code like 'purchase_profile_%')
-- group by kind order by kind;
-- Beklenen (bu migration'dan sonra, 20260817000027 ile birlikte):
--   avatar_effect = 8 + 15 = 23, cover_effect = 8 + 15 = 23, effect = 15
