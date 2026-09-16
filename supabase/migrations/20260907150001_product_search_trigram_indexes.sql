-- =============================================================================
-- Ürün/dükkan/kategori araması: ILIKE'ı gerçekten indeksleyen trigram indeksleri
-- =============================================================================
-- SORUN
-- -----
-- Canlıda şu indeksler var:
--     idx_products_name_search = GIN (to_tsvector('simple', name))
--     idx_products_desc_search = GIN (to_tsvector('simple', description))
--
-- Ancak uygulama tam metin araması DEĞİL, kalıp araması yapıyor:
--     lib/features/market/services/product_service.dart:105
--         .or('name.ilike.%$query%,description.ilike.%$query%')
--     lib/features/market/services/shop_service.dart:189
--     lib/features/market/services/category_service.dart:154
--
-- Bir `to_tsvector` GIN indeksi `ILIKE '%...%'` sorgusuna ASLA hizmet edemez.
-- Yani iki indeks de bugüne kadar hiç kullanılmadı ve her arama `products`
-- üzerinde sequential scan yaptı. Katalog büyüdükçe "Ürünler" sekmesi
-- doğrusal olarak yavaşlayacaktı.
--
-- Ayrıca `'simple'` konfigürasyonu seçilmiş (Türkçe kök bulma yok) ve
-- `unaccent` kurulu değildi: "sari" araması "sarı" ürününü bulamıyordu.
--
-- ÇÖZÜM
-- -----
-- 1. pg_trgm + unaccent kurulur.
-- 2. ILIKE'ı indeksleyebilen GIN trigram indeksleri eklenir.
-- 3. Türkçe aksan duyarsız arama için immutable bir normalize fonksiyonu ve
--    onun üzerinde indeks eklenir (uygulama ileride buna geçebilir).
--
-- İstemci değişikliği GEREKMEZ: mevcut `.ilike('%q%')` sorguları bu
-- indekslerden anında faydalanır.
-- =============================================================================

BEGIN;

CREATE EXTENSION IF NOT EXISTS pg_trgm  WITH SCHEMA extensions;
CREATE EXTENSION IF NOT EXISTS unaccent WITH SCHEMA extensions;

-- -----------------------------------------------------------------------------
-- 1) ILIKE '%...%' için trigram indeksleri
-- -----------------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_products_name_trgm
  ON public.products USING gin (name extensions.gin_trgm_ops);

CREATE INDEX IF NOT EXISTS idx_products_description_trgm
  ON public.products USING gin (description extensions.gin_trgm_ops);

CREATE INDEX IF NOT EXISTS idx_shops_name_trgm
  ON public.shops USING gin (name extensions.gin_trgm_ops);

CREATE INDEX IF NOT EXISTS idx_shops_description_trgm
  ON public.shops USING gin (description extensions.gin_trgm_ops);

CREATE INDEX IF NOT EXISTS idx_categories_name_trgm
  ON public.categories USING gin (name extensions.gin_trgm_ops);

-- -----------------------------------------------------------------------------
-- 2) Türkçe aksan duyarsız normalize
-- -----------------------------------------------------------------------------
-- unaccent() STABLE olduğu için doğrudan indekste kullanılamaz; IMMUTABLE
-- bir sarmalayıcı gerekiyor. Türkçe'ye özel ı/İ eşlemesi de burada yapılır:
-- PostgreSQL'in lower() fonksiyonu 'I' -> 'i' çevirir, Türkçe'de ise
-- 'I' -> 'ı' olmalıdır; arama için her ikisini de 'i'ye indirgiyoruz.
CREATE OR REPLACE FUNCTION public.search_normalize(p_text text)
RETURNS text
LANGUAGE sql
IMMUTABLE
PARALLEL SAFE
STRICT
SET search_path = ''
AS $$
  SELECT lower(extensions.unaccent('extensions.unaccent', translate(
    p_text,
    'ıİşŞğĞçÇöÖüÜ',
    'iIsSgGcCoOuU'
  )));
$$;

COMMENT ON FUNCTION public.search_normalize(text) IS
  'Arama için Türkçe aksan/büyük-küçük harf normalize eder. IMMUTABLE olduğu için indekslenebilir.';

CREATE INDEX IF NOT EXISTS idx_products_name_normalized_trgm
  ON public.products USING gin (public.search_normalize(name) extensions.gin_trgm_ops);

CREATE INDEX IF NOT EXISTS idx_shops_name_normalized_trgm
  ON public.shops USING gin (public.search_normalize(name) extensions.gin_trgm_ops);

-- -----------------------------------------------------------------------------
-- 3) Kullanılmayan tsvector indekslerini düşür
-- -----------------------------------------------------------------------------
-- Bu indeksler hiçbir sorgu tarafından kullanılamıyor ama her INSERT/UPDATE'te
-- bakım maliyeti üretiyor.
DROP INDEX IF EXISTS public.idx_products_name_search;
DROP INDEX IF EXISTS public.idx_products_desc_search;

COMMIT;

NOTIFY pgrst, 'reload schema';
