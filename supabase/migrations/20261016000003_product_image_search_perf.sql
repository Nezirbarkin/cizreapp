-- =============================================================================
-- Görsel kütüphanesi araması: performans (7.800+ görsel)
-- =============================================================================
--
-- SORUN (canlıda ölçüldü, satıcı rolüyle, 7.823 görsel)
-- -----
-- search_product_image_presets her satırda, sorgunun her kelimesi için,
-- görselin TÜM kelimelerine Levenshtein hesaplıyordu (~80 bin hesap/kelime):
--   'sampuan' 180 ms, 'deterjan' 280 ms, 'ulker cikolatali gofret' 590 ms,
--   ürün adından öneri (p_match_any) 470–590 ms. Satıcı seçicisinde tam
--   eşleşme yoksa ikinci istekle ~780 ms.
-- Ayrıca SELECT politikası her satırda klasör tablosuna EXISTS alt sorgusu
-- çalıştırıyordu (7.876 indeks taraması / sorgu; RLS koşulu kullanıcı
-- koşullarından ÖNCE değerlendirildiği için her sorguda tüm tablo).
--
-- ÇÖZÜM (sonuçlar birebir aynı — aşağıdaki "ANLAM" notu hariç)
-- -----
-- 1. product_image_search_words: kütüphanedeki farklı kelimelerin sözlüğü
--    (~6.600 kelime, 80 bin kelime geçişine karşı). Yazım hatası adayları
--    sözlükte BİR KEZ Levenshtein ile bulunur ("domtes" -> {domates, …}),
--    satırda yalnız dizi kesişimi (&&) bakılır. Tetikleyiciyle güncel tutulur;
--    silinen kelime sözlükte kalabilir (zararsız: eşleşecek satır yoktur).
-- 2. presets.search_words: search_text'in kelime dizisi (üretilmiş, STORED);
--    her aramada satır başına string_to_array maliyeti kalkar.
-- 3. Kelime koşulları dinamik SQL'e satır içi yazılır (satır başına
--    unnest/LATERAL alt sorgusu yok); değerler format(%L) ile tırnaklanır.
-- 4. SELECT politikası: EXISTS yerine açık klasör kimlikleri BİR KEZ
--    (initPlan) toplanır. Admin yazma politikaları da (SELECT …) içine alındı.
-- 5. RPC artık yalnız istemcinin okuduğu sütunları döner (search_* yok):
--    sayfa başına ~%40 daha az veri. Dönüş tipi değiştiği için DROP + CREATE.
--
-- ANLAM
-- -----
-- Tüm kelimeler modu (varsayılan): eski fonksiyonla 28 sorgu × 3 sayfa
-- birebir aynı (canlıda karşılaştırıldı). p_match_any modunda küme aynı;
-- eşleşmeyen kelimenin sıralamaya katkısı artık sabit (eskiden "2'den büyük
-- herhangi bir değer" ya da 99'du), bu yüzden aynı isabet sayılı satırların
-- kendi aralarındaki sırası değişebilir. 16'dan fazla kelimeli sorguda
-- ilk 16 kelime kullanılır (yapıştırılmış paragraf taranacak ifadeyi şişirmesin).
--
-- Doğrulama: supabase/tests/manual/product_image_folders_test.sql
-- =============================================================================

BEGIN;

-- -----------------------------------------------------------------------------
-- 1) Kelime dizisi sütunu
-- -----------------------------------------------------------------------------
-- Üretilmiş sütun başka bir üretilmiş sütuna başvuramaz; ifade search_text ile
-- aynıdır.
ALTER TABLE public.product_image_presets
  ADD COLUMN IF NOT EXISTS search_words text[]
    GENERATED ALWAYS AS (
      string_to_array(
        public.search_normalize(name || ' ' || coalesce(description, '')),
        ' '
      )
    ) STORED;

COMMENT ON COLUMN public.product_image_presets.search_words IS
  'string_to_array(search_text, '' ''); search_product_image_presets yazım hatası eşleşmesinde kullanır.';

-- -----------------------------------------------------------------------------
-- 2) Kelime sözlüğü
-- -----------------------------------------------------------------------------
-- "C" harmanlaması: kelimeler zaten normalize; bayt karşılaştırması yeter ve
-- indeks daha hızlı.
CREATE TABLE IF NOT EXISTS public.product_image_search_words (
  word text COLLATE "C" PRIMARY KEY
);

COMMENT ON TABLE public.product_image_search_words IS
  'Görsel kütüphanesindeki farklı kelimeler (search_normalize edilmiş, 3–66 harf). Yazım hatası adayları burada bir kez hesaplanır. Tetikleyiciyle eklenir, silinmez.';

ALTER TABLE public.product_image_search_words ENABLE ROW LEVEL SECURITY;

-- Arama fonksiyonu INVOKER olduğu için satıcı okuyabilmeli. Yalnız kelimeler
-- var (görsele bağlanamaz); pasif/kapalı klasör kelimeleri de zararsız.
DROP POLICY IF EXISTS "product_image_search_words_select_policy" ON public.product_image_search_words;
CREATE POLICY "product_image_search_words_select_policy"
ON public.product_image_search_words FOR SELECT
TO authenticated
USING (true);

REVOKE ALL ON TABLE public.product_image_search_words FROM PUBLIC, anon, authenticated;
GRANT SELECT ON TABLE public.product_image_search_words TO authenticated;

-- Yazım toleransı 4–64 harfli kelimelerde, en fazla 2 harf: 3–66 harf yeter.
CREATE OR REPLACE FUNCTION public.product_image_search_words_sync()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $function$
BEGIN
  INSERT INTO public.product_image_search_words (word)
  SELECT DISTINCT w
    FROM unnest(NEW.search_words) AS w
   WHERE char_length(w) BETWEEN 3 AND 66
  ON CONFLICT (word) DO NOTHING;
  RETURN NULL;
END;
$function$;

REVOKE ALL ON FUNCTION public.product_image_search_words_sync() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trg_product_image_search_words ON public.product_image_presets;
CREATE TRIGGER trg_product_image_search_words
AFTER INSERT OR UPDATE OF name, description ON public.product_image_presets
FOR EACH ROW
EXECUTE FUNCTION public.product_image_search_words_sync();

-- Tetikleyici kurulduktan SONRA doldurulur: CREATE TRIGGER'ın kilidi işlem
-- sonuna kadar eşzamanlı eklemeleri beklettiği için arada kelime kaçmaz.
INSERT INTO public.product_image_search_words (word)
SELECT DISTINCT w
  FROM public.product_image_presets p,
       unnest(p.search_words) AS w
 WHERE char_length(w) BETWEEN 3 AND 66
ON CONFLICT (word) DO NOTHING;

-- -----------------------------------------------------------------------------
-- 3) Politikalar: satır başına alt sorgu / fonksiyon çağrısı yok
-- -----------------------------------------------------------------------------
-- Açık klasör kimlikleri sorgu başına bir kez toplanır (initPlan). Satıcı,
-- klasör politikası gereği zaten yalnız açık klasörleri görür. ::uuid[]
-- zorunlu: yoksa "= ANY (alt sorgu)" satır kümesi olarak yorumlanır.
DROP POLICY IF EXISTS "product_image_presets_select_policy" ON public.product_image_presets;
CREATE POLICY "product_image_presets_select_policy"
ON public.product_image_presets FOR SELECT
TO authenticated
USING (
  (
    is_active
    AND (
      folder_id IS NULL
      OR folder_id = ANY ((
        SELECT array_agg(f.id)
          FROM public.product_image_folders f
         WHERE f.is_active
      )::uuid[])
    )
  )
  OR (SELECT public.auth_is_admin())
);

ALTER POLICY "product_image_presets_admin_insert_policy"
  ON public.product_image_presets
  WITH CHECK ((SELECT public.auth_is_admin()));

ALTER POLICY "product_image_presets_admin_update_policy"
  ON public.product_image_presets
  USING ((SELECT public.auth_is_admin()))
  WITH CHECK ((SELECT public.auth_is_admin()));

ALTER POLICY "product_image_presets_admin_delete_policy"
  ON public.product_image_presets
  USING ((SELECT public.auth_is_admin()));

-- -----------------------------------------------------------------------------
-- 4) Arama
-- -----------------------------------------------------------------------------
-- Eşleşme ve sıralama kuralları 20261006000001/000002 ile aynı:
--   kelime eşleşir = ad+arama kelimelerinde geçer YA DA bir kelimeye
--   Levenshtein mesafesi 4–7 harfte <= 1, 8–64 harfte <= 2.
--   Katmanlar: 0 ad birebir, 1 ad sorguyla başlıyor, 2 adda bir kelime
--   sorguyla başlıyor, 3 tüm kelimeler adda, 4 ad+arama kelimelerinde,
--   5 yazım hatasıyla adda, 6 yazım hatasıyla arama kelimelerinde; içinde
--   toplam mesafe, kısa ad, display_order, ad, id.
-- "Kelime geçer" = strpos(...) > 0; burada LIKE ile yazılır, kullanıcının
-- % _ \ karakterleri kaçışlanır (joker olmaz).
DROP FUNCTION IF EXISTS public.search_product_image_presets(text, uuid, integer, integer, boolean);

CREATE FUNCTION public.search_product_image_presets(
  p_query text DEFAULT NULL,
  p_folder_id uuid DEFAULT NULL,
  p_limit integer DEFAULT 60,
  p_offset integer DEFAULT 0,
  p_match_any boolean DEFAULT false
)
RETURNS TABLE (
  id uuid,
  name text,
  description text,
  image_url text,
  is_active boolean,
  display_order integer,
  created_at timestamptz,
  folder_id uuid
)
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = ''
AS $function$
#variable_conflict use_column
DECLARE
  v_q text := btrim(regexp_replace(
    public.search_normalize(coalesce(p_query, '')), '\s+', ' ', 'g'
  ));
  v_any boolean := coalesce(p_match_any, false);
  v_tokens text[];
  v_limit integer := least(greatest(coalesce(p_limit, 60), 1), 100);
  v_offset integer := greatest(coalesce(p_offset, 0), 0);
  v_t text;
  v_len integer;
  v_max integer;
  v_d1 text[];
  v_d2 text[];
  v_in_text text;
  v_in_name text;
  v_matched text[] := '{}';
  v_dist text[] := '{}';
  v_text_all text[] := '{}';
  v_name_all text[] := '{}';
  v_name_matched text[] := '{}';
BEGIN
  IF v_q = '' THEN
    IF v_any THEN
      RETURN;
    END IF;
    RETURN QUERY
      SELECT p.id, p.name, p.description, p.image_url, p.is_active,
             p.display_order, p.created_at, p.folder_id
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
    -- Rakam ve 3 harften kısa kelimeler (1, kg, ml, 2,5) yok sayılır.
    SELECT coalesce(array_agg(t), '{}')
      INTO v_tokens
      FROM unnest(v_tokens) AS t
     WHERE char_length(t) >= 3
       AND t !~ '^[0-9.,]+$';
    IF cardinality(v_tokens) = 0 THEN
      RETURN;
    END IF;
  END IF;
  v_tokens := v_tokens[1:16];

  FOREACH v_t IN ARRAY v_tokens LOOP
    v_len := char_length(v_t);
    v_max := CASE WHEN v_len >= 8 THEN 2 WHEN v_len >= 4 THEN 1 ELSE 0 END;

    v_in_text := format(
      'p.search_text LIKE %L',
      '%' || replace(replace(replace(v_t, '\', '\\'), '%', '\%'), '_', '\_') || '%'
    );
    v_in_name := replace(v_in_text, 'p.search_text', 'p.search_name');

    -- Yazım hatası adayları: sözlükteki kelimeler, mesafeye göre.
    v_d1 := NULL;
    v_d2 := NULL;
    IF v_max > 0 AND v_len <= 64 THEN
      SELECT array_agg(w.word) FILTER (WHERE w.d = 1),
             array_agg(w.word) FILTER (WHERE w.d = 2)
        INTO v_d1, v_d2
        FROM (
          SELECT s.word,
                 extensions.levenshtein_less_equal(v_t, s.word, v_max) AS d
            FROM public.product_image_search_words s
           WHERE char_length(s.word) BETWEEN v_len - v_max AND v_len + v_max
        ) w
       WHERE w.d BETWEEN 1 AND v_max;
    END IF;

    v_text_all := v_text_all || format('(%s)', v_in_text);
    v_name_all := v_name_all || format('(%s)', v_in_name);

    IF v_d1 IS NULL AND v_d2 IS NULL THEN
      v_matched := v_matched || format('(%s)', v_in_text);
      v_dist := v_dist || format('(CASE WHEN %s THEN 0 ELSE 99 END)', v_in_text);
      v_name_matched := v_name_matched || format('(%s)', v_in_name);
    ELSE
      v_matched := v_matched || format(
        '(%s OR p.search_words && %L::text[])',
        v_in_text, coalesce(v_d1, '{}') || coalesce(v_d2, '{}')
      );
      v_dist := v_dist || format(
        '(CASE WHEN %s THEN 0%s%s ELSE 99 END)',
        v_in_text,
        CASE WHEN v_d1 IS NOT NULL
          THEN format(' WHEN p.search_words && %L::text[] THEN 1', v_d1)
          ELSE '' END,
        CASE WHEN v_d2 IS NOT NULL
          THEN format(' WHEN p.search_words && %L::text[] THEN 2', v_d2)
          ELSE '' END
      );
      -- Adın kelimeleri search_words'ün alt kümesi; yalnız aday satırlarda
      -- (seçim listesinde) hesaplanır.
      v_name_matched := v_name_matched || format(
        '(%s OR string_to_array(p.search_name, '' '') && %L::text[])',
        v_in_name, coalesce(v_d1, '{}') || coalesce(v_d2, '{}')
      );
    END IF;
  END LOOP;

  -- $1 klasör, $2 limit, $3 offset, $4 normalize sorgu. OFFSET 0 alt sorguyu
  -- düzleştirmeyi engeller: koşullar satır başına bir kez hesaplanır.
  RETURN QUERY EXECUTE format(
    $sql$
    SELECT r.id, r.name, r.description, r.image_url, r.is_active,
           r.display_order, r.created_at, r.folder_id
      FROM (
        SELECT p.id, p.name, p.description, p.image_url, p.is_active,
               p.display_order, p.created_at, p.folder_id, p.search_name,
               %s AS in_name,
               %s AS in_text,
               %s AS name_matched,
               %s AS hits,
               %s AS dist
          FROM public.product_image_presets p
          LEFT JOIN public.product_image_folders f ON f.id = p.folder_id
         WHERE p.is_active
           AND (p.folder_id IS NULL OR f.is_active)
           AND ($1 IS NULL OR p.folder_id = $1)
           AND (%s)
        OFFSET 0
      ) r
     ORDER BY
       -r.hits,
       CASE
         WHEN r.search_name = $4 THEN 0
         WHEN left(r.search_name, char_length($4)) = $4 THEN 1
         WHEN strpos(' ' || r.search_name, ' ' || $4) > 0 THEN 2
         WHEN r.in_name THEN 3
         WHEN r.in_text THEN 4
         WHEN r.name_matched THEN 5
         ELSE 6
       END,
       r.dist,
       char_length(r.search_name),
       r.display_order,
       r.search_name,
       r.id
     LIMIT $2 OFFSET $3
    $sql$,
    array_to_string(v_name_all, ' AND '),
    array_to_string(v_text_all, ' AND '),
    array_to_string(v_name_matched, ' AND '),
    CASE
      WHEN v_any THEN array_to_string(
        ARRAY(SELECT format('%s::int', m) FROM unnest(v_matched) AS m), ' + '
      )
      ELSE '0'
    END,
    array_to_string(v_dist, ' + '),
    array_to_string(v_matched, CASE WHEN v_any THEN ' OR ' ELSE ' AND ' END)
  )
  USING p_folder_id, v_limit, v_offset, v_q;
END;
$function$;

COMMENT ON FUNCTION public.search_product_image_presets(text, uuid, integer, integer, boolean) IS
  'Satıcının görsel kütüphanesi araması: Türkçe/aksan duyarsız, sıralı, sayfalı, yazım hatasına toleranslı (sözlük: product_image_search_words). p_match_any: kelimelerden biri yeter (ürün adından öneri). Yalnız yayındaki görseller (açık klasörde); yalnız istemci sütunları.';

REVOKE ALL ON FUNCTION public.search_product_image_presets(text, uuid, integer, integer, boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.search_product_image_presets(text, uuid, integer, integer, boolean) TO authenticated;

COMMIT;

NOTIFY pgrst, 'reload schema';
