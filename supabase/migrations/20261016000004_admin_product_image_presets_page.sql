-- =============================================================================
-- Admin > Ürün Görsel Kütüphanesi: sunucuda süzülen, sayfalı liste
-- =============================================================================
--
-- SORUN
-- -----
-- Admin ekranı açılışta kütüphanenin TAMAMINI çekiyordu (11.000+ satır,
-- ~3–4 MB JSON, 1000'lik paralel sayfalar) ve süzme/sıralama/sayaçları
-- istemcide yapıyordu; kütüphane büyüdükçe açılış ve bellek kötüleşiyordu.
--
-- ÇÖZÜM
-- -----
-- 1. admin_product_image_presets_page: klasör / durum / arama / sıralama
--    süzgeciyle bir sayfa + süzgece uyan toplam. p_with_summary ile
--    kütüphane özeti de gelir: klasörler (ad, sıra, açık/kapalı) ve klasör
--    başına tüm/yayında sayıları, klasörsüzlerin sayıları, en büyük sıra no.
--    Açılış = tek istek (sayfa + özet); p_limit 0 = yalnız toplam + özet.
-- 2. admin_product_image_preset_ids: aynı süzgece uyan TÜM kimlikler
--    ("süzgece uyanların tümünü seç"); satır verisi yok.
-- 3. product_image_like_patterns: iki fonksiyonun ortak arama kalıbı.
--
-- Arama: sorgu search_normalize ile sadeleştirilir (Türkçe harf, aksan,
-- büyük/küçük harf duyarsız) ve boşluklardan kelimelere bölünür; HER kelime
-- search_text'te (ad + arama kelimeleri) geçmeli. Yazım hatası toleransı ve
-- alaka sıralaması YOK: bu bir yönetim süzgeci, sıralamayı admin seçer
-- (satıcı araması search_product_image_presets'te). En fazla 16 kelime.
-- Sıralama: 'order' = display_order, search_name, id; 'newest' = created_at
-- ve id azalan. İkisi de id ile biter (sabit) — sayfalar çakışmaz.
--
-- İkisi de SECURITY INVOKER: admin kontrolü başta (42501), görünürlük
-- RLS'ten (SELECT politikası admine her satırı gösterir).
-- Doğrulama: supabase/tests/manual/admin_product_image_presets_page_test.sql
-- =============================================================================

BEGIN;

-- -----------------------------------------------------------------------------
-- 1) Arama kalıbı
-- -----------------------------------------------------------------------------
-- 'Çiğ  Köfte' -> {'%cig%', '%kofte%'}; LIKE joker karakterleri (% _ \)
-- kaçışlanır. Boş sorgu -> {} (LIKE ALL boş diziyle her satırda doğru).
CREATE OR REPLACE FUNCTION public.product_image_like_patterns(p_query text)
RETURNS text[]
LANGUAGE sql
IMMUTABLE
PARALLEL SAFE
SET search_path = ''
AS $function$
  SELECT coalesce(
           array_agg(
             '%' || replace(replace(replace(u.t, '\', '\\'), '%', '\%'), '_', '\_') || '%'
             ORDER BY u.o
           ),
           '{}'::text[]
         )
    FROM unnest(regexp_split_to_array(
           btrim(public.search_normalize(coalesce(p_query, ''))), '\s+'
         )) WITH ORDINALITY AS u(t, o)
   WHERE u.t <> ''
     AND u.o <= 16;
$function$;

COMMENT ON FUNCTION public.product_image_like_patterns(text) IS
  'Görsel kütüphanesi admin araması: sorgunun kelimelerinden search_text LIKE ALL kalıpları (search_normalize, joker kaçışlı, en fazla 16).';

REVOKE ALL ON FUNCTION public.product_image_like_patterns(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.product_image_like_patterns(text) TO authenticated;

-- -----------------------------------------------------------------------------
-- 2) Sayfa + toplam + özet
-- -----------------------------------------------------------------------------
-- p_folder_id: yalnız o klasör (NULL = tümü); p_unfiled: yalnız klasörsüzler.
-- p_status: 'all' | 'active' | 'passive'; p_sort: 'order' | 'newest'.
-- p_limit 0–500 (varsayılan 60).
CREATE OR REPLACE FUNCTION public.admin_product_image_presets_page(
  p_folder_id uuid DEFAULT NULL,
  p_unfiled boolean DEFAULT false,
  p_status text DEFAULT 'all',
  p_query text DEFAULT NULL,
  p_sort text DEFAULT 'order',
  p_limit integer DEFAULT 60,
  p_offset integer DEFAULT 0,
  p_with_summary boolean DEFAULT false
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = ''
AS $function$
DECLARE
  v_status text := coalesce(p_status, 'all');
  v_sort text := coalesce(p_sort, 'order');
  v_unfiled boolean := coalesce(p_unfiled, false);
  v_patterns text[] := public.product_image_like_patterns(p_query);
  v_limit integer := least(greatest(coalesce(p_limit, 60), 0), 500);
  v_offset integer := greatest(coalesce(p_offset, 0), 0);
  v_total integer;
  v_items jsonb;
  v_result jsonb;
BEGIN
  IF NOT coalesce((SELECT public.auth_is_admin()), false) THEN
    RAISE EXCEPTION 'Bu işlem yalnız yöneticilere açık' USING ERRCODE = '42501';
  END IF;
  IF v_status NOT IN ('all', 'active', 'passive') THEN
    RAISE EXCEPTION 'Geçersiz durum süzgeci: %', p_status USING ERRCODE = '22023';
  END IF;
  IF v_sort NOT IN ('order', 'newest') THEN
    RAISE EXCEPTION 'Geçersiz sıralama: %', p_sort USING ERRCODE = '22023';
  END IF;

  -- Süzgece uyanlar bir kez taranır (CTE iki kez okunduğu için bir kez
  -- hesaplanır); toplam ve sayfa aynı kümeden. Sayfa LIMIT'li alt sorguda
  -- seçilir (tüm küme değil, yalnız ilk offset+limit sıralanır); jsonb_agg
  -- aynı anahtarlarla yalnız o sayfayı yeniden sıralar (dizi sırası garanti).
  -- k_* anahtarları 'order' sıralamasında NULL'dır (etkisiz).
  WITH m AS (
    SELECT p.id, p.name, p.description, p.image_url, p.is_active,
           p.display_order, p.created_at, p.folder_id, p.search_name,
           CASE WHEN v_sort = 'newest' THEN p.created_at END AS k_created,
           CASE WHEN v_sort = 'newest' THEN p.id END AS k_id
      FROM public.product_image_presets p
     WHERE (p_folder_id IS NULL OR p.folder_id = p_folder_id)
       AND (NOT v_unfiled OR p.folder_id IS NULL)
       AND (v_status = 'all' OR p.is_active = (v_status = 'active'))
       AND p.search_text LIKE ALL (v_patterns)
  )
  SELECT (SELECT count(*)::integer FROM m),
         coalesce((
           SELECT jsonb_agg(
                    jsonb_build_object(
                      'id', x.id,
                      'name', x.name,
                      'description', x.description,
                      'image_url', x.image_url,
                      'is_active', x.is_active,
                      'display_order', x.display_order,
                      'created_at', x.created_at,
                      'folder_id', x.folder_id
                    )
                    ORDER BY x.k_created DESC, x.k_id DESC,
                             x.display_order, x.search_name, x.id
                  )
             FROM (
               SELECT m.*
                 FROM m
                ORDER BY m.k_created DESC, m.k_id DESC,
                         m.display_order, m.search_name, m.id
                LIMIT v_limit OFFSET v_offset
             ) x
         ), '[]'::jsonb)
    INTO v_total, v_items;

  v_result := jsonb_build_object('items', v_items, 'total', v_total);

  IF coalesce(p_with_summary, false) THEN
    WITH c AS (
      SELECT p.folder_id,
             count(*)::integer AS n,
             (count(*) FILTER (WHERE p.is_active))::integer AS n_active,
             max(p.display_order) AS max_order
        FROM public.product_image_presets p
       GROUP BY p.folder_id
    )
    SELECT v_result || jsonb_build_object(
             'summary', jsonb_build_object(
               'folders', coalesce((
                 SELECT jsonb_agg(
                          jsonb_build_object(
                            'id', f.id,
                            'name', f.name,
                            'display_order', f.display_order,
                            'is_active', f.is_active,
                            'image_count', coalesce(c.n, 0),
                            'active_image_count', coalesce(c.n_active, 0)
                          )
                          ORDER BY f.display_order, f.name, f.id
                        )
                   FROM public.product_image_folders f
                   LEFT JOIN c ON c.folder_id = f.id
               ), '[]'::jsonb),
               'unfiled_count', coalesce((SELECT c.n FROM c WHERE c.folder_id IS NULL), 0),
               'unfiled_active_count', coalesce((SELECT c.n_active FROM c WHERE c.folder_id IS NULL), 0),
               'max_display_order', coalesce((SELECT max(c.max_order) FROM c), 0)
             )
           )
      INTO v_result;
  END IF;

  RETURN v_result;
END;
$function$;

COMMENT ON FUNCTION public.admin_product_image_presets_page(uuid, boolean, text, text, text, integer, integer, boolean) IS
  'Admin görsel kütüphanesi: klasör/durum/arama/sıralama süzgeciyle bir sayfa + süzgece uyan toplam; p_with_summary ile klasörler ve klasör başına tüm/yayında sayaçları. Yalnız admin (INVOKER, RLS).';

REVOKE ALL ON FUNCTION public.admin_product_image_presets_page(uuid, boolean, text, text, text, integer, integer, boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_product_image_presets_page(uuid, boolean, text, text, text, integer, integer, boolean) TO authenticated;

-- -----------------------------------------------------------------------------
-- 3) Süzgece uyan tüm kimlikler
-- -----------------------------------------------------------------------------
-- Süzgeç admin_product_image_presets_page ile BİREBİR aynı olmalı (test
-- ikisini karşılaştırır). Sıralamasız.
CREATE OR REPLACE FUNCTION public.admin_product_image_preset_ids(
  p_folder_id uuid DEFAULT NULL,
  p_unfiled boolean DEFAULT false,
  p_status text DEFAULT 'all',
  p_query text DEFAULT NULL
)
RETURNS uuid[]
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = ''
AS $function$
DECLARE
  v_status text := coalesce(p_status, 'all');
  v_unfiled boolean := coalesce(p_unfiled, false);
  v_patterns text[] := public.product_image_like_patterns(p_query);
BEGIN
  IF NOT coalesce((SELECT public.auth_is_admin()), false) THEN
    RAISE EXCEPTION 'Bu işlem yalnız yöneticilere açık' USING ERRCODE = '42501';
  END IF;
  IF v_status NOT IN ('all', 'active', 'passive') THEN
    RAISE EXCEPTION 'Geçersiz durum süzgeci: %', p_status USING ERRCODE = '22023';
  END IF;

  RETURN coalesce((
    SELECT array_agg(p.id)
      FROM public.product_image_presets p
     WHERE (p_folder_id IS NULL OR p.folder_id = p_folder_id)
       AND (NOT v_unfiled OR p.folder_id IS NULL)
       AND (v_status = 'all' OR p.is_active = (v_status = 'active'))
       AND p.search_text LIKE ALL (v_patterns)
  ), '{}'::uuid[]);
END;
$function$;

COMMENT ON FUNCTION public.admin_product_image_preset_ids(uuid, boolean, text, text) IS
  'Admin görsel kütüphanesi: admin_product_image_presets_page ile aynı süzgece uyan TÜM görsel kimlikleri ("süzgece uyanların tümünü seç"). Yalnız admin (INVOKER, RLS).';

REVOKE ALL ON FUNCTION public.admin_product_image_preset_ids(uuid, boolean, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_product_image_preset_ids(uuid, boolean, text, text) TO authenticated;

COMMIT;

NOTIFY pgrst, 'reload schema';
