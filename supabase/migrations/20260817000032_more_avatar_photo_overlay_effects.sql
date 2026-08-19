-- =============================================================================
-- Fotoğraf-üstü avatar efektlerinin genişletilmesi (onlarca yeni efekt)
-- =============================================================================
-- İSTEK: 20260817000031'de eklenen 3 fotoğraf-üstü efekt (şimşek, yağmur,
-- eski TV) sadece ÖRNEKTİ — "onlarca efekt koy" istendi. Bu migration 14
-- YENİ, birbirinden farklı fotoğraf-üstü efekt ekliyor: kar, sis, sıcak hava
-- dalgalanması, neon dijital glitch, VHS statiği, film grenli, güneş
-- parlaması, bokeh ışıkları, kırağı, konfeti, su altı baloncuğu, çatlak cam,
-- duman, alev.
--
-- Şema değişikliği YOK — hepsi kind = 'avatar_effect', renderer_key yine
-- 'photo_' önekiyle başlıyor (Flutter tarafı isPhotoOverlayEffect() ile
-- tanıyıp çerçeve çizmeden doğrudan fotoğrafın üzerine, dairesel kırpılı
-- bindiriyor — bkz. 20260817000031).
--
-- 20260817000031 ile birlikte toplam: 3 + 14 = 17 farklı fotoğraf-üstü efekt
-- türü, renk varyantlarıyla 9 + 28 = 37 satır.
-- =============================================================================

begin;

with overlays(renderer_key, title, description, color1, color2, priority, price_monthly, price_yearly) as (
  values
    ('photo_snow_overlay', 'Kar Efekti', 'Fotoğrafın üzerine kar taneleri yağar', '#90CAF9', '#E3F2FD', 820, 49.90, 459.00),
    ('photo_fog_overlay', 'Sis Perdesi', 'Fotoğrafın üzerinde dalgalanan sis katmanları', '#B0BEC5', '#ECEFF1', 821, 44.90, 409.00),
    ('photo_heat_wave', 'Sıcak Hava Dalgalanması', 'Fotoğrafta ısı tirtili gibi dalgalanma', '#FF7043', '#FFCCBC', 822, 44.90, 409.00),
    ('photo_neon_glitch', 'Neon Glitch', 'RGB kayması ve neon çizgilerle dijital parazit', '#E91E63', '#00E5FF', 823, 54.90, 499.00),
    ('photo_vhs_static', 'VHS Statiği', 'Eski kaset kaydı gibi statik parazit ve renk kayması', '#7E57C2', '#B39DDB', 824, 49.90, 459.00),
    ('photo_film_grain', 'Film Grenli', 'Sinema filmi dokusu, flicker ve vinyet', '#5D4037', '#A1887F', 825, 54.90, 499.00),
    ('photo_sun_flare', 'Güneş Parlaması', 'Fotoğraftan geçen sıcak lens flare ışığı', '#FFB300', '#FFF176', 826, 59.90, 549.00),
    ('photo_bokeh_lights', 'Bokeh Işıkları', 'Bulanık, yumuşak ışık daireleri süzülür', '#F06292', '#F8BBD0', 827, 54.90, 499.00),
    ('photo_ice_frost', 'Kırağı Efekti', 'Köşelerden büyüyen buz/kırağı deseni', '#4FC3F7', '#E1F5FE', 828, 59.90, 549.00),
    ('photo_confetti_burst', 'Konfeti Patlaması', 'Fotoğrafın üzerinde renkli konfeti dansı', '#AB47BC', '#F3E5F5', 829, 49.90, 459.00),
    ('photo_bubble_overlay', 'Su Altı Baloncuğu', 'Fotoğrafın üzerinde yükselen baloncuklar', '#26C6DA', '#B2EBF2', 830, 44.90, 409.00),
    ('photo_crack_glass', 'Çatlak Cam', 'Fotoğrafın üzerinde çatlamış cam deseni ve parıltı', '#78909C', '#CFD8DC', 831, 54.90, 499.00),
    ('photo_smoke_drift', 'Duman Efekti', 'Fotoğrafın üzerinde yavaşça süzülen duman', '#607D8B', '#B0BEC5', 832, 44.90, 409.00),
    ('photo_flame_overlay', 'Alev Efekti', 'Fotoğrafın alt kısmından yükselen alev parçacıkları', '#FF5722', '#FFAB91', 833, 59.90, 549.00)
), variants(suffix, color1, color2) as (
  values ('a', null, null), ('b', '#00BFA5', '#1DE9B6')
)
insert into public.profile_feature_catalog (
  code, kind, name, description, renderer_key, primary_color, secondary_color,
  config, priority, is_active, is_user_claimable, price_monthly, price_yearly
)
select
  'purchase_avatar_' || o.renderer_key || '_' || v.suffix,
  'avatar_effect',
  o.title || (case when v.suffix = 'a' then '' else ' · Alternatif ' || upper(v.suffix) end),
  o.description,
  o.renderer_key,
  coalesce(v.color1, o.color1),
  coalesce(v.color2, o.color2),
  jsonb_build_object('speed', 1.0, 'variant', v.suffix),
  o.priority,
  true,
  false,
  o.price_monthly,
  o.price_yearly
from overlays o cross join variants v
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
-- select code, renderer_key, price_monthly, price_yearly from public.profile_feature_catalog
-- where renderer_key like 'photo_%' order by code;
-- Beklenen: 37 satır (17 farklı efekt türü x renk varyantları), hepsi
-- kind = avatar_effect.
