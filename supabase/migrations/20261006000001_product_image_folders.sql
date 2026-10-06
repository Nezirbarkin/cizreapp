-- =============================================================================
-- Ürün Görsel Kütüphanesi: klasörler + Türkçe uyumlu arama (2000+ görsel için)
-- =============================================================================
--
-- SORUN
-- -----
-- Kütüphane (`product_image_presets`) birkaç düzine görsel için tasarlandı:
--   * Klasör/kategori yok; Market, Kozmetik, Hırdavat… ayrımı yapılamıyor.
--   * Satıcı araması `name/description ILIKE '%q%'`. en_US.UTF-8 harmanlamasında
--     'İncir' ILIKE '%incir%' ve 'çilek' ILIKE '%cilek%' FALSE döner (canlıda
--     doğrulandı) — kütüphanede hem "İncir" hem "incir" kaydı bu yüzden var.
--   * Sonuçlar sıralanmıyor (yalnız display_order); "domates" araması
--     "Organik Köy Domatesi"ni "Domates"in önüne koyabiliyor.
--   * Toplu yükleme betiği aynı dosyayı ikinci çalıştırmada tekrar eklerdi.
--
-- ÇÖZÜM
-- -----
-- 1. `product_image_folders` (tek seviye). Kapalı klasörün görselleri
--    satıcılara GÖRÜNMEZ — kural presets SELECT politikasında (RLS), böylece
--    eski istemci sürümlerinin doğrudan tablo sorguları da uyar.
-- 2. presets'e `folder_id`, `source_key` (toplu yükleme kimliği, UNIQUE) ve
--    iki üretilmiş arama sütunu: `search_name`, `search_text`
--    (public.search_normalize — 20260907150001'de tanımlı, IMMUTABLE).
-- 3. `search_product_image_presets` RPC'si: Türkçe/aksan duyarsız, çok
--    kelimeli (her kelime geçmeli), sıralı, yazım hatasına toleranslı, sayfalı.
-- 4. `product_image_folder_summary` RPC'si: klasörler + görsel sayıları.
-- 5. Başlangıç klasörleri; mevcut görsellerin tamamı meyve/sebze olduğu için
--    "Manav"a yerleştirilir.
--
-- İki RPC de SECURITY INVOKER: görünürlük tamamen RLS'ten gelir.
-- Doğrulama: supabase/tests/manual/product_image_folders_test.sql
-- =============================================================================

BEGIN;

-- -----------------------------------------------------------------------------
-- 1) Klasörler
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.product_image_folders (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL
    CONSTRAINT product_image_folders_name_check
    CHECK (char_length(btrim(name)) BETWEEN 1 AND 40),
  display_order integer NOT NULL DEFAULT 0,
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now()
);

-- "Hırdavat" ile "hirdavat " aynı klasör sayılır (toplu yükleme betiği klasör
-- dizinini bu normalize adla eşler).
CREATE UNIQUE INDEX IF NOT EXISTS uq_product_image_folders_name
  ON public.product_image_folders (public.search_normalize(btrim(name)));

ALTER TABLE public.product_image_folders ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "product_image_folders_select_policy" ON public.product_image_folders;
CREATE POLICY "product_image_folders_select_policy"
ON public.product_image_folders FOR SELECT
TO authenticated
USING (is_active OR (SELECT public.auth_is_admin()));

DROP POLICY IF EXISTS "product_image_folders_admin_insert_policy" ON public.product_image_folders;
CREATE POLICY "product_image_folders_admin_insert_policy"
ON public.product_image_folders FOR INSERT
TO authenticated
WITH CHECK ((SELECT public.auth_is_admin()));

DROP POLICY IF EXISTS "product_image_folders_admin_update_policy" ON public.product_image_folders;
CREATE POLICY "product_image_folders_admin_update_policy"
ON public.product_image_folders FOR UPDATE
TO authenticated
USING ((SELECT public.auth_is_admin()))
WITH CHECK ((SELECT public.auth_is_admin()));

DROP POLICY IF EXISTS "product_image_folders_admin_delete_policy" ON public.product_image_folders;
CREATE POLICY "product_image_folders_admin_delete_policy"
ON public.product_image_folders FOR DELETE
TO authenticated
USING ((SELECT public.auth_is_admin()));

GRANT SELECT, INSERT, UPDATE, DELETE ON public.product_image_folders TO authenticated;

COMMENT ON TABLE public.product_image_folders IS
  'Ürün görsel kütüphanesi klasörleri (Market, Kozmetik…). Kapalı klasörün görselleri satıcılara gösterilmez.';

-- -----------------------------------------------------------------------------
-- 2) Görsellere klasör, toplu yükleme kimliği ve arama sütunları
-- -----------------------------------------------------------------------------
ALTER TABLE public.product_image_presets
  ADD COLUMN IF NOT EXISTS folder_id uuid
    REFERENCES public.product_image_folders (id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS source_key text,
  ADD COLUMN IF NOT EXISTS search_name text
    GENERATED ALWAYS AS (public.search_normalize(name)) STORED,
  ADD COLUMN IF NOT EXISTS search_text text
    GENERATED ALWAYS AS (
      public.search_normalize(name || ' ' || coalesce(description, ''))
    ) STORED;

-- Kısmi değil, düz UNIQUE: PostgREST upsert'i (on_conflict=source_key) yalnız
-- tam kısıtla çalışır. NULL'lar birbirinden farklı sayıldığı için elle eklenen
-- (source_key'siz) görseller etkilenmez.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
     WHERE conname = 'product_image_presets_source_key_key'
       AND conrelid = 'public.product_image_presets'::regclass
  ) THEN
    ALTER TABLE public.product_image_presets
      ADD CONSTRAINT product_image_presets_source_key_key UNIQUE (source_key);
  END IF;
END
$$;

CREATE INDEX IF NOT EXISTS idx_product_image_presets_folder_order
  ON public.product_image_presets (folder_id, display_order);

-- Arama artık search_name/search_text üzerinden; ham ad üzerindeki trigram
-- indeksini hiçbir sorgu kullanmıyor.
DROP INDEX IF EXISTS public.idx_product_image_presets_name_trgm;

COMMENT ON COLUMN public.product_image_presets.source_key IS
  'Toplu yükleme betiğinin (scripts/upload_product_image_library.py) dosya kimliği: "<klasör>/<dosya adı>" uzantısız, sadeleştirilmiş (ör. "manav/salkim-domates"); aynı dosya ikinci kez eklenmez. Elle eklenenlerde NULL.';
COMMENT ON COLUMN public.product_image_presets.search_text IS
  'search_normalize(ad + arama kelimeleri); search_product_image_presets RPC''si kullanır.';

-- -----------------------------------------------------------------------------
-- 3) Görünürlük: kapalı klasörün görselleri satıcıya gizli
-- -----------------------------------------------------------------------------
-- auth_is_admin() alt sorguya alındı: satır başına değil, sorgu başına bir kez
-- çalışır (initPlan).
DROP POLICY IF EXISTS "product_image_presets_select_policy" ON public.product_image_presets;
CREATE POLICY "product_image_presets_select_policy"
ON public.product_image_presets FOR SELECT
TO authenticated
USING (
  (
    is_active
    AND (
      folder_id IS NULL
      OR EXISTS (
        SELECT 1
          FROM public.product_image_folders f
         WHERE f.id = product_image_presets.folder_id
           AND f.is_active
      )
    )
  )
  OR (SELECT public.auth_is_admin())
);

-- -----------------------------------------------------------------------------
-- 4) Satıcı araması
-- -----------------------------------------------------------------------------
-- Eşleşme: sorgunun HER kelimesi ad+arama kelimelerinde geçmeli. Geçmeyen
-- kelime yazım hatası sayılabilir: görselin bir kelimesine harf düzeltme
-- mesafesi (Levenshtein) 4-7 harfte <= 1, 8+ harfte <= 2 ("domtes" -> domates,
-- "salatlik" -> salatalık). Trigram benzerliği denendi ve elendi: kısa Türkçe
-- kelimelerde "domtes"i kaçırıp (0.5) "cekic" -> "cekirdek"i (0.67) yakalıyor.
-- Tolerans kelime başınadır; tüm sorguya uygulanırsa "domates salkım"
-- "Domates Salçası"nı da getirir.
-- Sıralama katmanları (küçük önce):
--   0 ad birebir    1 ad sorguyla başlıyor    2 adda bir kelime sorguyla başlıyor
--   3 tüm kelimeler adda    4 tüm kelimeler ad+arama kelimelerinde
--   5 yazım hatasıyla adda eşleşen    6 yazım hatasıyla arama kelimelerinde
-- Katman içinde: toplam düzeltme mesafesi, KISA ad önce (sorguya en yakını:
-- "Salkım Domates" "Organik Köy Domatesi"nden önce), display_order, ad.
-- strpos/left kullanılır, LIKE değil: kullanıcı metnindeki % ve _ joker olmaz.
CREATE EXTENSION IF NOT EXISTS fuzzystrmatch WITH SCHEMA extensions;

CREATE OR REPLACE FUNCTION public.search_product_image_presets(
  p_query text DEFAULT NULL,
  p_folder_id uuid DEFAULT NULL,
  p_limit integer DEFAULT 60,
  p_offset integer DEFAULT 0
)
RETURNS SETOF public.product_image_presets
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = ''
AS $function$
DECLARE
  v_q text := btrim(regexp_replace(
    public.search_normalize(coalesce(p_query, '')), '\s+', ' ', 'g'
  ));
  v_tokens text[];
  v_limit integer := least(greatest(coalesce(p_limit, 60), 1), 100);
  v_offset integer := greatest(coalesce(p_offset, 0), 0);
BEGIN
  IF v_q = '' THEN
    RETURN QUERY
      SELECT p.*
        FROM public.product_image_presets p
        LEFT JOIN public.product_image_folders f ON f.id = p.folder_id
       WHERE p.is_active
         AND (p.folder_id IS NULL OR f.is_active)
         AND (p_folder_id IS NULL OR p.folder_id = p_folder_id)
       ORDER BY p.display_order, p.search_name, p.id
       LIMIT v_limit OFFSET v_offset;
    RETURN;
  END IF;

  v_tokens := string_to_array(v_q, ' ');

  RETURN QUERY
    SELECT p.*
      FROM public.product_image_presets p
      LEFT JOIN public.product_image_folders f ON f.id = p.folder_id
      CROSS JOIN LATERAL (
        SELECT bool_and(k.in_name) AS in_name,
               bool_and(k.in_text) AS in_text,
               bool_and(k.dist <= k.max_dist) AS matched,
               bool_and(k.name_dist <= k.max_dist) AS name_matched,
               sum(k.dist) AS dist
          FROM (
            SELECT d.*,
                   -- adın kelimelerine göre mesafe (yalnız katman 5/6 ayrımı)
                   CASE
                     WHEN d.in_name THEN 0
                     WHEN d.dist > d.max_dist THEN 99
                     ELSE coalesce((
                       SELECT min(extensions.levenshtein_less_equal(d.t, w, 2))
                         FROM unnest(string_to_array(p.search_name, ' ')) AS w
                        WHERE abs(char_length(w) - char_length(d.t)) <= 2
                     ), 99)
                   END AS name_dist
              FROM (
                SELECT t,
                       strpos(p.search_name, t) > 0 AS in_name,
                       strpos(p.search_text, t) > 0 AS in_text,
                       CASE
                         WHEN char_length(t) >= 8 THEN 2
                         WHEN char_length(t) >= 4 THEN 1
                         ELSE 0
                       END AS max_dist,
                       CASE
                         WHEN strpos(p.search_text, t) > 0 THEN 0
                         WHEN char_length(t) < 4 OR char_length(t) > 64 THEN 99
                         ELSE coalesce((
                           SELECT min(extensions.levenshtein_less_equal(t, w, 2))
                             FROM unnest(string_to_array(p.search_text, ' ')) AS w
                            WHERE abs(char_length(w) - char_length(t)) <= 2
                         ), 99)
                       END AS dist
                  FROM unnest(v_tokens) AS t
              ) d
          ) k
      ) m
     WHERE p.is_active
       AND (p.folder_id IS NULL OR f.is_active)
       AND (p_folder_id IS NULL OR p.folder_id = p_folder_id)
       AND m.matched
     ORDER BY
       CASE
         WHEN p.search_name = v_q THEN 0
         WHEN left(p.search_name, char_length(v_q)) = v_q THEN 1
         WHEN strpos(' ' || p.search_name, ' ' || v_q) > 0 THEN 2
         WHEN m.in_name THEN 3
         WHEN m.in_text THEN 4
         WHEN m.name_matched THEN 5
         ELSE 6
       END,
       m.dist,
       char_length(p.search_name),
       p.display_order,
       p.search_name,
       p.id
     LIMIT v_limit OFFSET v_offset;
END;
$function$;

COMMENT ON FUNCTION public.search_product_image_presets(text, uuid, integer, integer) IS
  'Satıcının görsel kütüphanesi araması: Türkçe/aksan duyarsız, çok kelimeli, sıralı, sayfalı. Yalnız yayındaki görseller (açık klasörde).';

REVOKE ALL ON FUNCTION public.search_product_image_presets(text, uuid, integer, integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.search_product_image_presets(text, uuid, integer, integer) TO authenticated;

-- -----------------------------------------------------------------------------
-- 5) Klasör özeti (satıcı çipleri + admin sayaçları)
-- -----------------------------------------------------------------------------
-- RLS sayesinde satıcı yalnız açık klasörleri ve yayındaki görselleri sayar;
-- admin hepsini görür (image_count = tümü, active_image_count = yayında).
CREATE OR REPLACE FUNCTION public.product_image_folder_summary()
RETURNS TABLE (
  id uuid,
  name text,
  display_order integer,
  is_active boolean,
  image_count bigint,
  active_image_count bigint
)
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = ''
AS $function$
#variable_conflict use_column
BEGIN
  RETURN QUERY
    SELECT f.id,
           f.name,
           f.display_order,
           f.is_active,
           count(p.id),
           count(p.id) FILTER (WHERE p.is_active)
      FROM public.product_image_folders f
      LEFT JOIN public.product_image_presets p ON p.folder_id = f.id
     GROUP BY f.id
     ORDER BY f.display_order, f.name;
END;
$function$;

COMMENT ON FUNCTION public.product_image_folder_summary() IS
  'Görsel kütüphanesi klasörleri ve çağıranın görebildiği görsel sayıları.';

REVOKE ALL ON FUNCTION public.product_image_folder_summary() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.product_image_folder_summary() TO authenticated;

-- -----------------------------------------------------------------------------
-- 6) Başlangıç klasörleri + mevcut görseller
-- -----------------------------------------------------------------------------
INSERT INTO public.product_image_folders (name, display_order)
SELECT v.name, v.ord
  FROM (VALUES ('Market', 1), ('Manav', 2), ('Kozmetik', 3), ('Hırdavat', 4))
       AS v(name, ord)
 WHERE NOT EXISTS (
   SELECT 1
     FROM public.product_image_folders f
    WHERE public.search_normalize(btrim(f.name)) = public.search_normalize(v.name)
 );

-- Bu göçten önce eklenen 34 görselin tamamı meyve/sebze. Tarih sınırı, göç
-- yeniden çalıştırılırsa sonradan eklenen klasörsüz görselleri süpürmesin diye.
UPDATE public.product_image_presets p
   SET folder_id = f.id
  FROM public.product_image_folders f
 WHERE public.search_normalize(f.name) = 'manav'
   AND p.folder_id IS NULL
   AND p.created_at < '2026-10-06 00:00:00+00';

COMMIT;

NOTIFY pgrst, 'reload schema';
