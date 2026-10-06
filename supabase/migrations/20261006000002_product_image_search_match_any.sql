-- =============================================================================
-- Görsel kütüphanesi araması: "kelimelerden biri yeter" modu (p_match_any)
-- =============================================================================
--
-- SORUN
-- -----
-- 20261006000001'deki search_product_image_presets sorgunun HER kelimesinin
-- eşleşmesini ister. Bu, satıcının arama kutusu için doğru; ama satıcı ürün
-- ADINI yazarken otomatik görsel önerisi için işe yaramaz: "Salkım Domates
-- 1 kg" adında "1" ve "kg" hiçbir görselde geçmediği için hiç öneri çıkmaz.
--
-- ÇÖZÜM
-- -----
-- p_match_any = true iken:
--   * 3 harften kısa ve yalnız rakam olan kelimeler (1, kg, ml, 500, 2.5)
--     yok sayılır; anlamlı kelime kalmazsa sonuç boştur (göz atma listesi
--     DEĞİL).
--   * En az bir kelimenin eşleşmesi (içerme ya da yazım hatası) yeter.
--   * Sıralama önce eşleşen kelime SAYISINA göre (çok olan önce), sonra
--     normal katmanlar.
-- Varsayılan (false) davranış birebir aynıdır.
--
-- İmza değiştiği için eski 4 parametreli sürüm DÜŞÜRÜLÜR (aynı adda iki
-- fonksiyon PostgREST'te belirsiz çağrıya yol açar).
-- Doğrulama: supabase/tests/manual/product_image_folders_test.sql [15]
-- =============================================================================

BEGIN;

DROP FUNCTION IF EXISTS public.search_product_image_presets(text, uuid, integer, integer);

CREATE OR REPLACE FUNCTION public.search_product_image_presets(
  p_query text DEFAULT NULL,
  p_folder_id uuid DEFAULT NULL,
  p_limit integer DEFAULT 60,
  p_offset integer DEFAULT 0,
  p_match_any boolean DEFAULT false
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
  v_any boolean := coalesce(p_match_any, false);
  v_tokens text[];
  v_limit integer := least(greatest(coalesce(p_limit, 60), 1), 100);
  v_offset integer := greatest(coalesce(p_offset, 0), 0);
BEGIN
  IF v_q = '' THEN
    IF v_any THEN
      RETURN;
    END IF;
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
  IF v_any THEN
    SELECT coalesce(array_agg(t), '{}')
      INTO v_tokens
      FROM unnest(v_tokens) AS t
     WHERE char_length(t) >= 3
       AND t !~ '^[0-9.,]+$';
    IF cardinality(v_tokens) = 0 THEN
      RETURN;
    END IF;
  END IF;

  RETURN QUERY
    SELECT p.*
      FROM public.product_image_presets p
      LEFT JOIN public.product_image_folders f ON f.id = p.folder_id
      CROSS JOIN LATERAL (
        SELECT bool_and(k.in_name) AS in_name,
               bool_and(k.in_text) AS in_text,
               bool_and(k.dist <= k.max_dist) AS matched,
               count(*) FILTER (WHERE k.dist <= k.max_dist) AS hits,
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
       AND CASE WHEN v_any THEN m.hits > 0 ELSE m.matched END
     ORDER BY
       CASE WHEN v_any THEN -m.hits ELSE 0 END,
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

COMMENT ON FUNCTION public.search_product_image_presets(text, uuid, integer, integer, boolean) IS
  'Satıcının görsel kütüphanesi araması: Türkçe/aksan duyarsız, sıralı, sayfalı, yazım hatasına toleranslı. p_match_any: kelimelerden biri yeter (ürün adından öneri). Yalnız yayındaki görseller (açık klasörde).';

REVOKE ALL ON FUNCTION public.search_product_image_presets(text, uuid, integer, integer, boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.search_product_image_presets(text, uuid, integer, integer, boolean) TO authenticated;

COMMIT;

NOTIFY pgrst, 'reload schema';
