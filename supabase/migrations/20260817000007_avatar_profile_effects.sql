-- =============================================================================
-- Profil resmi (avatar) efektleri
-- 20260817000005_user_profile_privileges.sql üzerine ileri yönlü genişletmedir.
-- Eski migration değiştirilmez. Mevcut katalog/RPC/atama güvenliği korunur.
-- =============================================================================

begin;

-- Katalog türüne avatar_effect ekle. Constraint adı PostgreSQL tarafından
-- tablo+sütun üzerinden üretildi; IF EXISTS ile tekrar çalıştırılabilir.
alter table public.profile_feature_catalog
  drop constraint if exists profile_feature_catalog_kind_check;

alter table public.profile_feature_catalog
  add constraint profile_feature_catalog_kind_check
  check (kind in ('effect', 'avatar_effect', 'icon', 'badge'));

-- 12 renderer ailesi x 10 varyasyon = 120 hareketli avatar efekti.
-- Flutter tarafında renderer_key + config ile prosedürel çizilir; medya dosyası
-- gerekmez ve yeni katalog kayıtları uygulama kodunu şişirmez.
with avatar_base(
  renderer_key, title, description, color1, color2, base_priority
) as (
  values
    ('neon_ring', 'Neon Halka', 'Profil resminin çevresinde dönen neon halka', '#00E5FF', '#E040FB', 180),
    ('lightning_ring', 'Şimşek Çemberi', 'Avatar çevresinde hareketli elektrik kıvılcımları', '#FFD740', '#FFFFFF', 190),
    ('rain_border', 'Yağmur Çerçevesi', 'Profil resminin çevresinden akan yağmur damlaları', '#42A5F5', '#B3E5FC', 160),
    ('fire_ring', 'Ateş Halkası', 'Avatar çevresinde canlı ateş parçacıkları', '#FF3D00', '#FFC107', 185),
    ('sparkle_ring', 'Yıldız Halkası', 'Profil resminin etrafında parlayan yıldızlar', '#FFCA28', '#FFF9C4', 175),
    ('orbit', 'Yörünge', 'Avatar çevresinde yörüngede dönen parçacıklar', '#7C4DFF', '#18FFFF', 170),
    ('pulse_glow', 'Nabız Işığı', 'Ritmik büyüyüp küçülen renkli ışık halesi', '#EC407A', '#7E57C2', 165),
    ('rainbow_ring', 'Gökkuşağı', 'Avatar çevresinde dönen çok renkli halka', '#F44336', '#2196F3', 188),
    ('snow_ring', 'Kar Çemberi', 'Profil resmi çevresinde dönen kar taneleri', '#E1F5FE', '#FFFFFF', 150),
    ('heart_orbit', 'Kalp Yörüngesi', 'Avatar çevresinde hareketli kalpler', '#EC407A', '#F8BBD0', 168),
    ('crown_glow', 'Taç Işığı', 'Profil resminin üstünde parlayan taç ve hale', '#F9A825', '#FFF176', 195),
    ('portal', 'Enerji Portalı', 'Avatar çevresinde çift yönlü enerji portalı', '#00BFA5', '#651FFF', 182)
), variants as (
  select generate_series(1, 10) as n
)
insert into public.profile_feature_catalog (
  code, kind, name, description, renderer_key,
  primary_color, secondary_color, config, priority
)
select
  'avatar_' || b.renderer_key || '_' || lpad(v.n::text, 2, '0'),
  'avatar_effect',
  b.title || ' ' || v.n,
  b.description,
  b.renderer_key,
  b.color1,
  b.color2,
  jsonb_build_object(
    'speed', (0.55 + v.n * 0.13)::numeric(4,2),
    'intensity', 1 + ((v.n - 1) % 4),
    'thickness', (1.4 + ((v.n - 1) % 5) * 0.55)::numeric(4,2),
    'particle_count', 6 + ((v.n - 1) % 5) * 3,
    'variant', v.n
  ),
  b.base_priority + v.n
from avatar_base b
cross join variants v
on conflict (code) do nothing;

commit;

-- Kontrol:
-- select kind, count(*) from public.profile_feature_catalog group by kind order by kind;
-- avatar_effect için beklenen: 120
