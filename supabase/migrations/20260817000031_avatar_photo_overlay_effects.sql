-- =============================================================================
-- Fotoğraf-üstü (overlay) avatar efektleri
-- =============================================================================
-- İSTEK: Önceki avatar dekorasyonlarının hepsi (yılan, kelebek, kraliyet
-- çerçevesi vb.) fotoğrafın ÇEVRESİNE/ARKASINA çizilen "çerçeve" tipiydi.
-- Bu migration, doğrudan fotoğrafın KENDİ YÜZEYİNE binen, çerçeveye
-- dokunmayan yeni bir alt-tür ekliyor: şimşek çakması, yağmur ve eski TV
-- parazit efekti fotoğrafın üzerinde oynuyor.
--
-- Şema değişikliği YOK — hâlâ kind = 'avatar_effect' (sadece profil resmine
-- uygulanır, kapağa değil). Flutter tarafı bu üç renderer_key'i "photo_"
-- öneki ile tanıyıp (bkz. isPhotoOverlayEffect() / privileged_avatar.dart)
-- halka çizmeden doğrudan fotoğrafın üzerine, dairesel kırpılmış olarak
-- bindiriyor.
-- =============================================================================

begin;

with overlays(renderer_key, title, description, color1, color2, priority, price_monthly, price_yearly) as (
  values
    ('photo_lightning_strike', 'Şimşek Çakması', 'Fotoğrafın üzerinde periyodik şimşek flaşı çakar', '#FFD740', '#FFF9C4', 810, 59.90, 549.00),
    ('photo_rain_overlay', 'Yağmur Efekti', 'Fotoğrafın üzerine yağmur damlaları kayar', '#42A5F5', '#B3E5FC', 811, 54.90, 499.00),
    ('photo_old_tv', 'Eski TV Efekti', 'Fotoğrafın üzerinde tarama çizgileri ve statik parazit oynar', '#607D8B', '#CFD8DC', 812, 49.90, 459.00)
), variants(suffix, color1, color2) as (
  values ('a', null, null), ('b', '#00BFA5', '#1DE9B6'), ('c', '#FF7043', '#FFAB91')
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
-- Beklenen: 9 satır (3 efekt x 3 renk varyantı), hepsi kind = avatar_effect.
