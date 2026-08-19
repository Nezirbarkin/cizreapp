-- =============================================================================
-- Benzersiz profil özellikleri + kullanıcıya açık sınırlı katalog
--
-- 1) Eski hız/renk varyasyonu olarak çoğaltılan benzer kayıtları pasifleştirir.
-- 2) 108 farklı genel efekt + 108 farklı avatar efekti + 100 farklı ikon ekler.
-- 3) Adminin yalnız seçtiği, badge olmayan özellikleri kullanıcının kendisine
--    ekleyebilmesini sağlar. Rozet/tik hiçbir zaman kullanıcı kataloğuna girmez.
-- =============================================================================

begin;

alter table public.profile_feature_catalog
  add column if not exists is_user_claimable boolean not null default false,
  add column if not exists claim_duration_days integer;

alter table public.profile_feature_catalog
  drop constraint if exists profile_feature_catalog_claim_duration_check;
alter table public.profile_feature_catalog
  add constraint profile_feature_catalog_claim_duration_check
  check (claim_duration_days is null or claim_duration_days between 1 and 3650);

create index if not exists profile_feature_catalog_claimable_idx
  on public.profile_feature_catalog(kind, priority desc)
  where is_active = true and is_user_claimable = true;

-- Aynı renderer'ın yalnız hız/renk numarası değişen eski kopyalarını kapat.
-- İlk kayıtlar geriye uyumluluk için tutulur.
update public.profile_feature_catalog
set is_active = false, is_user_claimable = false, updated_at = now()
where code ~ '^effect_.+_(02|03|04|05|06|07|08|09|10)$'
   or code ~ '^avatar_.+_(02|03|04|05|06|07|08|09|10)$'
   or code ~ '^icon_.+_(02|03|04|05|06)$';

-- 12 farklı hareket geometrisi x 9 farklı parçacık karakteri =
-- birbirinden farklı 108 genel profil efekti ve 108 avatar efekti.
with patterns(key, title, description, priority) as (
  values
    ('spiral', 'Sarmal', 'Merkezden açılan sarmal hareket', 130),
    ('wave', 'Dalga', 'Yatay ve dikey dalga hareketi', 131),
    ('burst', 'Patlama', 'Merkezden dışarı yayılan hareket', 132),
    ('vortex', 'Girdap', 'İçe ve dışa dönen girdap hareketi', 133),
    ('grid', 'Izgara', 'Düzenli dijital ızgara hareketi', 134),
    ('comet', 'Kuyruklu Yıldız', 'Kavisli kuyruklu yıldız hareketi', 135),
    ('halo', 'Hale', 'Katmanlı dairesel hale hareketi', 136),
    ('zigzag', 'Zikzak', 'Keskin yön değiştiren hareket', 137),
    ('fountain', 'Fıskiye', 'Aşağıdan yukarı püsküren hareket', 138),
    ('meteor', 'Meteor', 'Çapraz ve hızlı meteor hareketi', 139),
    ('orbit', 'Yörünge', 'Çoklu eliptik yörünge hareketi', 140),
    ('curtain', 'Işık Perdesi', 'Yukarıdan süzülen perde hareketi', 141)
), particles(key, title, symbol, color1, color2, priority) as (
  values
    ('starlight', 'Yıldız Işığı', 'star', '#FFD740', '#FFFFFF', 1),
    ('ember', 'Kor Ateşi', 'ember', '#FF3D00', '#FFC107', 2),
    ('crystal', 'Kristal', 'diamond', '#00E5FF', '#E1F5FE', 3),
    ('leaf', 'Yaprak', 'leaf', '#43A047', '#CDDC39', 4),
    ('rune', 'Rün', 'rune', '#7C4DFF', '#E040FB', 5),
    ('bubble', 'Baloncuk', 'bubble', '#26C6DA', '#B2EBF2', 6),
    ('petal', 'Çiçek Yaprağı', 'petal', '#EC407A', '#F8BBD0', 7),
    ('pixel', 'Piksel', 'pixel', '#00E676', '#1B5E20', 8),
    ('spark', 'Kıvılcım', 'spark', '#FF9100', '#FFF59D', 9)
), generated as (
  select
    p.key as pattern_key,
    p.title as pattern_title,
    p.description,
    q.key as particle_key,
    q.title as particle_title,
    q.symbol,
    q.color1,
    q.color2,
    p.priority + q.priority as priority
  from patterns p cross join particles q
)
insert into public.profile_feature_catalog (
  code, kind, name, description, renderer_key, primary_color, secondary_color,
  config, priority, is_active, is_user_claimable, claim_duration_days
)
select
  'unique_effect_' || pattern_key || '_' || particle_key,
  'effect',
  pattern_title || ' ' || particle_title,
  description || ' ve ' || lower(particle_title) || ' parçacıkları',
  'procedural_effect', color1, color2,
  jsonb_build_object(
    'pattern', pattern_key, 'particle', symbol,
    'speed', 0.65 + (priority % 7) * 0.16,
    'intensity', 1 + (priority % 3), 'size', 0.8 + (priority % 5) * 0.12
  ),
  priority, true,
  -- Kullanıcılar tümünden değil, yaklaşık üçte birinden yararlanabilir.
  (priority % 3 = 0),
  case when priority % 3 = 0 then 30 else null end
from generated
on conflict (code) do update set
  name = excluded.name,
  description = excluded.description,
  config = excluded.config,
  is_active = true,
  is_user_claimable = excluded.is_user_claimable,
  claim_duration_days = excluded.claim_duration_days,
  updated_at = now();

with patterns(key, title, description, priority) as (
  values
    ('spiral', 'Sarmal Çerçeve', 'Avatar çevresinde sarmal hareket', 230),
    ('wave', 'Dalga Çerçeve', 'Avatar çevresinde dalga hareketi', 231),
    ('burst', 'Patlama Çerçeve', 'Avatar çevresinde dışa yayılan hareket', 232),
    ('vortex', 'Girdap Çerçeve', 'Avatar çevresinde girdap hareketi', 233),
    ('grid', 'Dijital Çerçeve', 'Avatar çevresinde dijital ızgara', 234),
    ('comet', 'Kuyruklu Çerçeve', 'Avatar çevresinde kuyruklu hareket', 235),
    ('halo', 'Hale Çerçeve', 'Avatar çevresinde katmanlı hale', 236),
    ('zigzag', 'Zikzak Çerçeve', 'Avatar çevresinde zikzak enerji', 237),
    ('fountain', 'Fıskiye Çerçeve', 'Avatar çevresinde püsküren parçacıklar', 238),
    ('meteor', 'Meteor Çerçeve', 'Avatar çevresinde çapraz meteorlar', 239),
    ('orbit', 'Yörünge Çerçeve', 'Avatar çevresinde çoklu yörünge', 240),
    ('curtain', 'Perde Çerçeve', 'Avatar çevresinde ışık perdesi', 241)
), particles(key, title, symbol, color1, color2, priority) as (
  values
    ('starlight', 'Yıldız', 'star', '#FFD740', '#FFFFFF', 1),
    ('ember', 'Kor', 'ember', '#FF3D00', '#FFC107', 2),
    ('crystal', 'Kristal', 'diamond', '#00E5FF', '#E1F5FE', 3),
    ('leaf', 'Yaprak', 'leaf', '#43A047', '#CDDC39', 4),
    ('rune', 'Rün', 'rune', '#7C4DFF', '#E040FB', 5),
    ('bubble', 'Baloncuk', 'bubble', '#26C6DA', '#B2EBF2', 6),
    ('petal', 'Çiçek', 'petal', '#EC407A', '#F8BBD0', 7),
    ('pixel', 'Piksel', 'pixel', '#00E676', '#1B5E20', 8),
    ('spark', 'Kıvılcım', 'spark', '#FF9100', '#FFF59D', 9)
)
insert into public.profile_feature_catalog (
  code, kind, name, description, renderer_key, primary_color, secondary_color,
  config, priority, is_active, is_user_claimable, claim_duration_days
)
select
  'unique_avatar_' || p.key || '_' || q.key,
  'avatar_effect', p.title || ' · ' || q.title,
  p.description || '; ' || lower(q.title) || ' parçacıkları kullanır',
  'avatar_procedural', q.color1, q.color2,
  jsonb_build_object(
    'pattern', p.key, 'particle', q.symbol,
    'speed', 0.7 + ((p.priority + q.priority) % 7) * 0.15,
    'thickness', 1.5 + ((p.priority + q.priority) % 5) * 0.5,
    'particle_count', 7 + ((p.priority + q.priority) % 6) * 2
  ),
  p.priority + q.priority, true,
  ((p.priority + q.priority) % 4 = 0),
  case when (p.priority + q.priority) % 4 = 0 then 30 else null end
from patterns p cross join particles q
on conflict (code) do update set
  name = excluded.name,
  description = excluded.description,
  config = excluded.config,
  is_active = true,
  is_user_claimable = excluded.is_user_claimable,
  claim_duration_days = excluded.claim_duration_days,
  updated_at = now();

-- 100 farklı Material ikon kimliği. Aynı ikonun renk/hız kopyası yoktur.
with icons(key, title, description, color, motion, priority) as (
  values
    ('accessibility', 'Erişilebilirlik', 'Erişilebilir topluluk üyesi', '#5C6BC0', 'pulse', 301),
    ('anchor', 'Çapa', 'Güçlü ve kararlı profil', '#546E7A', 'swing', 302),
    ('architecture', 'Mimar', 'Tasarım ve mimari tutkunu', '#8D6E63', 'bounce', 303),
    ('auto_stories', 'Hikâye Ustası', 'Hikâye anlatıcısı', '#7E57C2', 'pulse', 304),
    ('bakery', 'Fırıncı', 'Fırın ve hamur işi tutkunu', '#D4A574', 'bounce', 305),
    ('beach', 'Tatilci', 'Deniz ve tatil tutkunu', '#26C6DA', 'swing', 306),
    ('bike', 'Bisikletçi', 'Bisiklet tutkunu', '#43A047', 'bounce', 307),
    ('book', 'Kitap Kurdu', 'Kitap ve okuma tutkunu', '#5D4037', 'pulse', 308),
    ('brush', 'Ressam', 'Resim ve çizim tutkunu', '#EC407A', 'swing', 309),
    ('bug', 'Hata Avcısı', 'Yazılım hata avcısı', '#66BB6A', 'bounce', 310),
    ('build', 'Usta', 'Üreten ve onaran kullanıcı', '#78909C', 'swing', 311),
    ('cake', 'Kutlama', 'Kutlamayı seven kullanıcı', '#F06292', 'pulse', 312),
    ('campaign', 'Duyurucu', 'Topluluk duyurucusu', '#EF5350', 'swing', 313),
    ('camping', 'Kampçı', 'Kamp ve doğa tutkunu', '#558B2F', 'bounce', 314),
    ('car', 'Otomobil', 'Otomobil tutkunu', '#3949AB', 'swing', 315),
    ('code', 'Kod Ustası', 'Yazılım geliştiricisi', '#00897B', 'pulse', 316),
    ('construction', 'İnşaatçı', 'Yapı ve inşaat uzmanı', '#F9A825', 'swing', 317),
    ('cookie', 'Kurabiye', 'Tatlı tutkunu', '#A1887F', 'rotate', 318),
    ('cruelty_free', 'Hayvan Dostu', 'Hayvanları koruyan kullanıcı', '#8BC34A', 'pulse', 319),
    ('directions_boat', 'Denizci', 'Deniz ve tekne tutkunu', '#0288D1', 'swing', 320),
    ('eco', 'Çevreci', 'Doğayı koruyan kullanıcı', '#2E7D32', 'swing', 321),
    ('electric_car', 'Elektrikli Araç', 'Elektrikli araç tutkunu', '#00ACC1', 'pulse', 322),
    ('emoji_events', 'Şampiyon', 'Başarı sahibi kullanıcı', '#F9A825', 'bounce', 323),
    ('engineering', 'Mühendis', 'Mühendislik uzmanı', '#607D8B', 'swing', 324),
    ('explore', 'Kaşif', 'Yeni yerler keşfeden kullanıcı', '#00838F', 'rotate', 325),
    ('fitness', 'Sporcu', 'Fitness ve spor tutkunu', '#E53935', 'bounce', 326),
    ('flight', 'Gezgin', 'Dünya gezgini', '#1E88E5', 'swing', 327),
    ('forest', 'Orman Dostu', 'Orman ve doğa tutkunu', '#388E3C', 'pulse', 328),
    ('handyman', 'Tamirci', 'El işi ve tamir ustası', '#6D4C41', 'swing', 329),
    ('headphones', 'Müziksever', 'Müzik tutkunu', '#8E24AA', 'pulse', 330),
    ('hiking', 'Dağcı', 'Doğa yürüyüşü tutkunu', '#689F38', 'bounce', 331),
    ('history_edu', 'Tarihçi', 'Tarih araştırmacısı', '#795548', 'swing', 332),
    ('icecream', 'Dondurma', 'Dondurma tutkunu', '#F48FB1', 'pulse', 333),
    ('interests', 'Koleksiyoncu', 'Özel koleksiyon sahibi', '#5E35B1', 'rotate', 334),
    ('language', 'Dünya Vatandaşı', 'Farklı diller ve kültürler', '#039BE5', 'rotate', 335),
    ('local_cafe', 'Kahve Uzmanı', 'Kahve kültürü tutkunu', '#6D4C41', 'swing', 336),
    ('local_florist', 'Çiçek Dostu', 'Çiçek ve bahçe tutkunu', '#D81B60', 'rotate', 337),
    ('medication', 'Sağlıkçı', 'Sağlık çalışanı', '#E53935', 'pulse', 338),
    ('memory', 'Teknoloji', 'Donanım ve teknoloji tutkunu', '#455A64', 'pulse', 339),
    ('mic', 'Ses Sanatçısı', 'Ses ve sahne sanatçısı', '#8E24AA', 'bounce', 340),
    ('military', 'Disiplin', 'Disiplinli topluluk üyesi', '#455A64', 'swing', 341),
    ('movie', 'Sinemasever', 'Film ve sinema tutkunu', '#C62828', 'pulse', 342),
    ('museum', 'Kültür Dostu', 'Müze ve kültür tutkunu', '#6A1B9A', 'swing', 343),
    ('nightlife', 'Gece Hayatı', 'Eğlence tutkunu', '#AD1457', 'bounce', 344),
    ('palette', 'Tasarımcı', 'Görsel tasarım uzmanı', '#F4511E', 'rotate', 345),
    ('pets', 'Pati Dostu', 'Evcil hayvan dostu', '#8D6E63', 'bounce', 346),
    ('photo_camera', 'Fotoğrafçı', 'Fotoğraf sanatçısı', '#37474F', 'pulse', 347),
    ('piano', 'Piyanist', 'Piyano sanatçısı', '#212121', 'swing', 348),
    ('psychology', 'Düşünür', 'Araştıran ve düşünen kullanıcı', '#5C6BC0', 'pulse', 349),
    ('recycling', 'Geri Dönüşüm', 'Sürdürülebilir yaşam destekçisi', '#43A047', 'rotate', 350),
    ('restaurant', 'Gurme', 'Yemek kültürü tutkunu', '#F4511E', 'swing', 351),
    ('sailing', 'Yelkenci', 'Yelken ve deniz tutkunu', '#0277BD', 'swing', 352),
    ('school', 'Eğitimci', 'Eğitim gönüllüsü', '#3949AB', 'pulse', 353),
    ('science', 'Bilim İnsanı', 'Bilim ve deney tutkunu', '#00838F', 'bounce', 354),
    ('self_improvement', 'Meditasyon', 'Kişisel gelişim tutkunu', '#7E57C2', 'pulse', 355),
    ('skateboarding', 'Kaykaycı', 'Kaykay tutkunu', '#EF6C00', 'swing', 356),
    ('sports_basketball', 'Basketbolcu', 'Basketbol tutkunu', '#EF6C00', 'bounce', 357),
    ('sports_cricket', 'Kriketçi', 'Kriket tutkunu', '#43A047', 'swing', 358),
    ('sports_esports', 'Oyuncu', 'Video oyunu tutkunu', '#7B1FA2', 'pulse', 359),
    ('sports_football', 'Amerikan Futbolu', 'Amerikan futbolu tutkunu', '#6D4C41', 'rotate', 360),
    ('sports_golf', 'Golfçü', 'Golf tutkunu', '#388E3C', 'swing', 361),
    ('sports_handball', 'Hentbolcu', 'Hentbol tutkunu', '#F9A825', 'bounce', 362),
    ('sports_hockey', 'Hokeyci', 'Hokey tutkunu', '#039BE5', 'swing', 363),
    ('sports_kabaddi', 'Güreşçi', 'Mücadele sporları tutkunu', '#D84315', 'bounce', 364),
    ('sports_martial_arts', 'Dövüş Sanatları', 'Dövüş sanatları tutkunu', '#C62828', 'swing', 365),
    ('sports_motorsports', 'Motor Sporu', 'Motor sporları tutkunu', '#E53935', 'pulse', 366),
    ('sports_rugby', 'Ragbi', 'Ragbi tutkunu', '#5D4037', 'rotate', 367),
    ('sports_soccer', 'Futbolcu', 'Futbol tutkunu', '#43A047', 'bounce', 368),
    ('sports_tennis', 'Tenisçi', 'Tenis tutkunu', '#9E9D24', 'swing', 369),
    ('sports_volleyball', 'Voleybolcu', 'Voleybol tutkunu', '#1E88E5', 'bounce', 370),
    ('surfing', 'Sörfçü', 'Sörf tutkunu', '#00ACC1', 'swing', 371),
    ('theater_comedy', 'Tiyatrocu', 'Tiyatro sanatçısı', '#8E24AA', 'pulse', 372),
    ('two_wheeler', 'Motosikletçi', 'Motosiklet tutkunu', '#455A64', 'swing', 373),
    ('volunteer_activism', 'Gönüllü', 'Topluluk gönüllüsü', '#D81B60', 'pulse', 374),
    ('watch', 'Saat Tutkunu', 'Saat koleksiyoncusu', '#546E7A', 'swing', 375),
    ('water', 'Su Dostu', 'Su sporları ve doğa tutkunu', '#039BE5', 'pulse', 376),
    ('wine_bar', 'Tadım Uzmanı', 'İçecek kültürü tutkunu', '#8E244D', 'swing', 377),
    ('yard', 'Bahçıvan', 'Bahçe ve bitki tutkunu', '#43A047', 'bounce', 378),
    ('agriculture', 'Çiftçi', 'Tarım ve üretim uzmanı', '#689F38', 'swing', 379),
    ('biotech', 'Biyoteknoloji', 'Biyoteknoloji tutkunu', '#00897B', 'pulse', 380),
    ('calculate', 'Matematikçi', 'Matematik ve hesap uzmanı', '#3949AB', 'bounce', 381),
    ('carpenter', 'Marangoz', 'Ahşap işleme ustası', '#795548', 'swing', 382),
    ('cleaning', 'Temizlik Uzmanı', 'Düzen ve temizlik uzmanı', '#00ACC1', 'pulse', 383),
    ('coffee_maker', 'Barista', 'Kahve hazırlama uzmanı', '#5D4037', 'swing', 384),
    ('colorize', 'Boyacı', 'Renk ve boya ustası', '#F4511E', 'swing', 385),
    ('computer', 'Bilgisayar Uzmanı', 'Bilgisayar teknolojileri uzmanı', '#455A64', 'pulse', 386),
    ('content_cut', 'Kuaför', 'Saç ve stil uzmanı', '#AD1457', 'swing', 387),
    ('design_services', 'Ürün Tasarımcısı', 'Ürün tasarımı uzmanı', '#7E57C2', 'rotate', 388),
    ('diamond', 'Mücevher', 'Mücevher ve değerli taş tutkunu', '#00ACC1', 'pulse', 389),
    ('edit_note', 'Yazar', 'Yazı ve edebiyat tutkunu', '#5D4037', 'swing', 390),
    ('fastfood', 'Sokak Lezzeti', 'Sokak lezzetleri tutkunu', '#F4511E', 'bounce', 391),
    ('festival', 'Festivalci', 'Festival ve etkinlik tutkunu', '#E040FB', 'bounce', 392),
    ('hardware', 'Donanım Ustası', 'Teknik donanım uzmanı', '#607D8B', 'swing', 393),
    ('local_fire_department', 'Ateşli', 'Yüksek enerjili kullanıcı', '#FF3D00', 'pulse', 394),
    ('map', 'Haritacı', 'Harita ve rota uzmanı', '#00897B', 'swing', 395),
    ('podcasts', 'Podcastçi', 'Podcast içerik üreticisi', '#8E24AA', 'pulse', 396),
    ('public', 'Küresel', 'Küresel topluluk üyesi', '#1E88E5', 'rotate', 397),
    ('rocket_launch', 'Girişimci', 'Yeni fikirler geliştiren kullanıcı', '#EF6C00', 'bounce', 398),
    ('solar_power', 'Güneş Enerjisi', 'Yenilenebilir enerji destekçisi', '#F9A825', 'rotate', 399),
    ('terminal', 'Terminal Ustası', 'Komut satırı ve sistem uzmanı', '#263238', 'pulse', 400)
)
insert into public.profile_feature_catalog (
  code, kind, name, description, renderer_key, primary_color, secondary_color,
  config, priority, is_active, is_user_claimable, claim_duration_days
)
select
  'unique_icon_' || key, 'icon', title, description, key, color, '#FFFFFF',
  jsonb_build_object('motion', motion, 'speed', 0.75 + (priority % 6) * 0.2),
  priority, true,
  -- Yalnız her dört ikondan biri kullanıcı kataloğunda.
  (priority % 4 = 0),
  case when priority % 4 = 0 then 90 else null end
from icons
on conflict (code) do update set
  name = excluded.name,
  description = excluded.description,
  renderer_key = excluded.renderer_key,
  config = excluded.config,
  is_active = true,
  is_user_claimable = excluded.is_user_claimable,
  claim_duration_days = excluded.claim_duration_days,
  updated_at = now();

-- Kullanıcının yararlanabileceği katalog. Badge/tik sabit olarak hariçtir.
create or replace function public.get_my_claimable_profile_features()
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
  is_claimed boolean,
  is_self_claimed boolean,
  is_user_claimable boolean,
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
    c.priority, coalesce(upf.is_enabled, false), upf.id is not null,
    (upf.id is not null and upf.granted_by is null), c.is_user_claimable,
    upf.starts_at, upf.expires_at
  from public.profile_feature_catalog c
  left join public.user_profile_features upf
    on upf.feature_id = c.id and upf.user_id = auth.uid()
  where auth.uid() is not null
    and c.is_active = true
    and c.is_user_claimable = true
    and c.kind in ('effect', 'avatar_effect', 'icon')
  order by c.kind, c.priority desc, c.name;
$$;

create or replace function public.claim_my_profile_feature(p_feature_id uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_days integer;
  v_id uuid;
begin
  if v_uid is null then
    raise exception 'authentication required' using errcode = '42501';
  end if;

  select c.claim_duration_days into v_days
  from public.profile_feature_catalog c
  where c.id = p_feature_id
    and c.is_active = true
    and c.is_user_claimable = true
    and c.kind in ('effect', 'avatar_effect', 'icon');

  if not found then
    raise exception 'Bu özellik kullanıcı kullanımına açık değildir'
      using errcode = '42501';
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

create or replace function public.release_my_claimed_profile_feature(p_feature_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception 'authentication required' using errcode = '42501';
  end if;

  delete from public.user_profile_features upf
  using public.profile_feature_catalog c
  where upf.user_id = auth.uid()
    and upf.feature_id = p_feature_id
    and upf.granted_by is null
    and c.id = upf.feature_id
    and c.kind in ('effect', 'avatar_effect', 'icon')
    and c.is_user_claimable = true;

  if not found then
    raise exception 'Yalnız kendin eklediğin özellikleri kaldırabilirsin'
      using errcode = '42501';
  end if;
end;
$$;

create or replace function public.admin_set_profile_feature_claimable(
  p_feature_id uuid,
  p_claimable boolean,
  p_duration_days integer default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not private.current_user_is_admin() then
    raise exception 'not admin' using errcode = '42501';
  end if;
  if p_duration_days is not null and (p_duration_days < 1 or p_duration_days > 3650) then
    raise exception 'Süre 1-3650 gün arasında olmalıdır' using errcode = '22023';
  end if;

  update public.profile_feature_catalog
  set is_user_claimable = case when kind = 'badge' then false else coalesce(p_claimable, false) end,
      claim_duration_days = case
        when kind = 'badge' or not coalesce(p_claimable, false) then null
        else p_duration_days end,
      updated_at = now()
  where id = p_feature_id;
end;
$$;

revoke all on function public.get_my_claimable_profile_features() from public;
revoke all on function public.claim_my_profile_feature(uuid) from public;
revoke all on function public.release_my_claimed_profile_feature(uuid) from public;
revoke all on function public.admin_set_profile_feature_claimable(uuid, boolean, integer) from public;
grant execute on function public.get_my_claimable_profile_features() to authenticated, service_role;
grant execute on function public.claim_my_profile_feature(uuid) to authenticated, service_role;
grant execute on function public.release_my_claimed_profile_feature(uuid) to authenticated, service_role;
grant execute on function public.admin_set_profile_feature_claimable(uuid, boolean, integer) to authenticated, service_role;

commit;

-- Kontrol:
-- select kind, count(*) from public.profile_feature_catalog
-- where is_active group by kind order by kind;
-- select kind, count(*) from public.profile_feature_catalog
-- where is_active and is_user_claimable group by kind order by kind;
