-- =============================================================================
-- Yeni dekorasyonlar + sipariş kilidinin SIRAYLA (round-robin) çalışması
-- =============================================================================
-- İSTEK (kullanıcı, 2026-08-19):
--   1) Yeni profil özellikleri: karınca yürümesi, dolu yağması, kar/yağmur ve
--      daha fazlası; profil ÇERÇEVESİNE de daha fazla seçenek.
--   2) Sipariş kilidi sırayla ilerlesin: 1 sipariş tamamlanınca TEK bir öğe
--      açılsın, sonra diğer kategoriye geçilsin; tur tamamlanınca başa dönsün.
--
-- 2. MADDE NEDEN GEREKLİ: 20260819000001'in merdiveni her kategoriye AYNI
-- eşiği veriyordu (tier), yani 1. siparişte dört kategoriden birer öğe AYNI
-- ANDA açılıyordu. Kullanıcının istediği bu değil — sırayla tek tek açılmalı.
--
-- TASARIM:
--   A) 66 yeni katalog satırı. Dart tarafında 15 yeni prosedürel çizer
--      (lib/kullaniciozellikler/widgets/seasonal_painters.dart) eklendi ve
--      renderer_registry.dart üzerinden TEK yerde kayıtlı — önizleme, avatar
--      ve kapak dağıtımları bu deftere düşüyor.
--        * 7 yüzey efekti (hem avatar fotoğrafı hem kapak): dolu, karınca
--          yürüyüşü, kiraz çiçeği, sonbahar yaprağı, meteor yağmuru, yıldız
--          yağmuru, sabun köpüğü.  -> 7 x 3 renk = 21 avatar + 21 kapak
--        * 8 yeni ÇERÇEVE (yalnız avatar): karınca yolu, dişliler, defne
--          çelengi, zincir, müzik notaları, pati izleri, elektrik yayı,
--          sarmaşık.                -> 8 x 3 renk = 24 avatar
--      Not: yağmur ve kar zaten vardı (photo_rain_overlay / photo_snow_overlay,
--      20260817 serisi); tekrar eklenmedi, dolu bunlara eşlik etsin diye
--      eklendi.
--      Yeni satırlar priority = 900 alır; merdiven priority'ye göre
--      sıralandığı için yeni içerik EN BAŞTA açılır (1. siparişte karınca
--      yolu gibi).
--
--   B) Merdiven round-robin'e çevrilir:
--        rn        = kind içindeki sıra (priority desc, name)
--        kind_rank = avatar_effect 1, cover_effect 2, effect 3, icon 4
--        unlock_after_orders = row_number() over (order by rn, kind_rank)
--      Yani: 1.sipariş avatar#1, 2. kapak#1, 3. profil#1, 4. ikon#1,
--            5. avatar#2, ... tur bitince başa döner.
--      Bir kategori tükenince (kapak 44 satırda biter) o kategorinin satırı
--      olmadığı için sıra kendiliğinden diğerlerinden devam eder — boşluk
--      oluşmaz. Toplam 522 öğe -> 1..522 sipariş.
--
--   C) Puan fiyatı GLOBAL sıraya değil kind içi sıraya (rn) bağlanır; aksi
--      halde son öğeler 522*15 gibi ulaşılamaz fiyatlara çıkardı:
--        points_price_monthly = taban(kind) + 8 * rn,  yearly = monthly * 10
--      Aralıklar: avatar 208-1992, kapak 258-602, profil 158-1222,
--      ikon 108-1060. 100 puan/gün tavanına göre ~1-20 gün.
--
--   D) 2 ücretsiz satır (20260819000001) merdivenin tamamen dışında kalır.
--      Rozet/tik yine yalnız admin tarafından verilir.
-- =============================================================================

begin;

-- -----------------------------------------------------------------------------
-- A) Yeni katalog satırları
-- -----------------------------------------------------------------------------
with defs(renderer, base_name, descr, as_cover) as (
  values
    ('photo_hail_storm',     'Dolu Yağışı',          'Fotoğrafın üzerine hızla düşen ve zeminden seken dolu taneleri.', true),
    ('photo_ant_march',      'Karınca Yürüyüşü',     'Fotoğrafın üzerinde sıra hâlinde yürüyen karıncalar.', true),
    ('photo_cherry_blossom', 'Kiraz Çiçeği',         'Dönerek süzülen kiraz çiçeği taç yaprakları.', true),
    ('photo_autumn_leaves',  'Sonbahar Yaprakları',  'Savrularak düşen sonbahar yaprakları.', true),
    ('photo_meteor_shower',  'Meteor Yağmuru',       'Gece göğünde çapraz inen kuyruklu meteorlar.', true),
    ('photo_star_rain',      'Yıldız Yağmuru',       'Süzülürken sönüp yanan yıldızlar.', true),
    ('photo_soap_foam',      'Sabun Köpüğü',         'Yüzeyde yükselen yanardöner sabun kabarcıkları.', true),
    ('frame_ant_trail',      'Karınca Yolu',         'Profil resminin çevresinde halka boyunca yürüyen karıncalar.', false),
    ('frame_gear_rotate',    'Dönen Dişliler',       'Çerçeveye yerleşmiş, ters yönlerde dönen çarklar.', false),
    ('frame_laurel_wreath',  'Defne Çelengi',        'İki yandan yukarı uzanan, nefes alan defne yaprakları.', false),
    ('frame_chain_links',    'Zincir Halkalar',      'Çerçeve boyunca dizilmiş, yavaşça dönen metal zincir.', false),
    ('frame_music_notes',    'Müzik Notaları',       'Çerçeve etrafında dolaşan, savrulan müzik notaları.', false),
    ('frame_paw_prints',     'Pati İzleri',          'Çerçeve boyunca sırayla beliren ve arkada solan pati izleri.', false),
    ('frame_lightning_arc',  'Elektrik Yayı',        'Çerçeve üzerinde dolaşan zikzak şimşek kavisi.', false),
    ('frame_vine_grow',      'Sarmaşık',             'Çerçeve boyunca büyüyüp geri çekilen sarmaşık filizi.', false)
),
variants(sfx, label, pc, sc) as (
  values
    ('a', 'Mavi',  '#4FC3F7', '#0277BD'),
    ('b', 'Mor',   '#B388FF', '#4527A0'),
    ('c', 'Altın', '#FFD54F', '#FF6F00')
),
rows_to_add as (
  -- Avatar tarafı: hem yüzey efektleri hem çerçeveler
  select
    'purchase_avatar_' || d.renderer || '_' || v.sfx as code,
    'avatar_effect' as kind,
    d.base_name || ' · ' || v.label as name,
    d.descr as description,
    d.renderer as renderer_key,
    v.pc as primary_color,
    v.sc as secondary_color
  from defs d cross join variants v
  union all
  -- Kapak tarafı: yalnız yüzey efektleri (çerçeve kapakta anlamsız)
  select
    'purchase_cover_' || d.renderer || '_' || v.sfx,
    'cover_effect',
    d.base_name || ' · ' || v.label,
    d.descr,
    d.renderer,
    v.pc,
    v.sc
  from defs d cross join variants v
  where d.as_cover
)
insert into public.profile_feature_catalog (
  code, kind, name, description, renderer_key,
  primary_color, secondary_color, config, priority, is_active
)
select
  r.code, r.kind, r.name, r.description, r.renderer_key,
  r.primary_color, r.secondary_color,
  '{"speed": 1}'::jsonb,
  900,
  true
from rows_to_add r
on conflict (code) do nothing;

-- -----------------------------------------------------------------------------
-- B + C) Round-robin merdiven + kind içi sıraya bağlı puan fiyatı
-- -----------------------------------------------------------------------------
with ranked as (
  select
    c.id,
    c.kind,
    row_number() over (
      partition by c.kind
      order by c.priority desc, c.name
    ) as rn,
    case c.kind
      when 'avatar_effect' then 1
      when 'cover_effect' then 2
      when 'effect' then 3
      when 'icon' then 4
    end as kind_rank
  from public.profile_feature_catalog c
  where c.is_active = true
    and c.kind <> 'badge'
    and c.is_user_claimable = false
),
sequenced as (
  select
    id,
    kind,
    rn,
    -- Sıra: her turda kategoriler kind_rank düzeninde birer öğe açar.
    -- Tükenen kategori o turdan itibaren satır üretmediği için sıra
    -- kendiliğinden kalanlardan devam eder.
    row_number() over (order by rn, kind_rank) as global_order
  from ranked
)
update public.profile_feature_catalog c
set unlock_after_orders = s.global_order,
    points_price_monthly = (
      case s.kind
        when 'icon' then 100
        when 'effect' then 150
        when 'avatar_effect' then 200
        when 'cover_effect' then 250
        else 150
      end + 8 * s.rn
    )::bigint,
    points_price_yearly = (
      (case s.kind
        when 'icon' then 100
        when 'effect' then 150
        when 'avatar_effect' then 200
        when 'cover_effect' then 250
        else 150
      end + 8 * s.rn) * 10
    )::bigint,
    updated_at = now()
from sequenced s
where c.id = s.id;

-- unlock_after_orders CHECK'i 1..1000 ile sınırlı; 522 öğe sığıyor, ancak
-- katalog büyümeye devam ederse bu sınır önce dolar. Sınırı öğe sayısının
-- makul üstüne çekiyoruz ki ileride yeni paket eklendiğinde migration
-- constraint'e takılmasın.
alter table public.profile_feature_catalog
  drop constraint if exists profile_feature_catalog_unlock_after_orders_check;
alter table public.profile_feature_catalog
  add constraint profile_feature_catalog_unlock_after_orders_check
  check (unlock_after_orders is null or unlock_after_orders between 1 and 5000);

-- Yeni eklenen satırlar için de geçmiş siparişleri karşıla (backfill).
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

commit;

-- =============================================================================
-- Kontrol:
--   -- Yeni satırlar geldi mi (66 beklenir):
--   select kind, count(*) from public.profile_feature_catalog
--   where priority = 900 group by kind order by kind;
--   -- Beklenen: avatar_effect 45, cover_effect 21
--
--   -- Round-robin doğru mu: ilk 8 sipariş sırayla kategori değiştirmeli
--   select unlock_after_orders, kind, name from public.profile_feature_catalog
--   where unlock_after_orders between 1 and 8 order by unlock_after_orders;
--   -- Beklenen kind sırası: avatar, cover, effect, icon, avatar, cover, effect, icon
--
--   -- Hiçbir sipariş numarası iki öğeye verilmemiş olmalı (tekillik):
--   select count(*) from (
--     select unlock_after_orders from public.profile_feature_catalog
--     where unlock_after_orders is not null
--     group by unlock_after_orders having count(*) > 1
--   ) s;
--   -- Beklenen: 0
--
--   -- Aktif non-badge satırların tamamı hâlâ hem eşiğe hem fiyata bağlı:
--   select count(*) from public.profile_feature_catalog
--   where is_active and kind <> 'badge' and not is_user_claimable
--     and (unlock_after_orders is null or points_price_monthly is null);
--   -- Beklenen: 0
-- =============================================================================
