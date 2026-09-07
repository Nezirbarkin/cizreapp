-- ============================================================================
-- BEĞENİ SAYACI ÇİFT ARTIŞ DÜZELTMESİ (post_likes)
-- ============================================================================
-- Sorun: post_likes tablosunda AYNI işi yapan iki ayrı trigger seti canlıydı:
--   1) post_likes_insert_trigger / post_likes_delete_trigger
--      (20260210000002 migration'ı ile eklenen doğru çift)
--   2) trg_post_likes_count -> update_post_likes_count()
--      (INSERT OR DELETE, eski legacy trigger)
-- Her ikisi de posts.likes_count'u güncellediği için TEK beğeni +2, tek
-- beğeni kaldırma -2 sayıyordu. Kullanıcı 1 beğense sayaç 2 gösteriyor,
-- ardından beğeniyi geri alınca 0 yerine -2 (GREATEST ile 0) oluyordu; bu
-- yüzden feed'deki beğeni sayıları gerçek post_likes satır sayısıyla
-- tutmuyordu (canlıda 40 gönderinin 7'sinde sapma tespit edildi).
--
-- Çözüm: legacy trigger'ı kaldır ve tüm sayaçları gerçek satır sayısından
-- yeniden hesapla.

begin;

-- 1) Legacy çift sayan trigger'ı kaldır
DROP TRIGGER IF EXISTS trg_post_likes_count ON public.post_likes;

-- Fonksiyon başka bir trigger tarafından kullanılmıyorsa o da gitsin
DROP FUNCTION IF EXISTS public.update_post_likes_count();

-- 2) Sayaçları gerçek verilerle yeniden senkronize et
UPDATE public.posts p
SET likes_count = sub.cnt
FROM (
  SELECT po.id, COALESCE(COUNT(l.id), 0) AS cnt
  FROM public.posts po
  LEFT JOIN public.post_likes l ON l.post_id = po.id
  GROUP BY po.id
) sub
WHERE p.id = sub.id
  AND COALESCE(p.likes_count, 0) IS DISTINCT FROM sub.cnt;

UPDATE public.posts p
SET comments_count = sub.cnt
FROM (
  SELECT po.id, COALESCE(COUNT(c.id), 0) AS cnt
  FROM public.posts po
  LEFT JOIN public.post_comments c ON c.post_id = po.id
  GROUP BY po.id
) sub
WHERE p.id = sub.id
  AND COALESCE(p.comments_count, 0) IS DISTINCT FROM sub.cnt;

UPDATE public.stories s
SET likes_count = sub.cnt
FROM (
  SELECT st.id, COALESCE(COUNT(l.id), 0) AS cnt
  FROM public.stories st
  LEFT JOIN public.story_likes l ON l.story_id = st.id
  GROUP BY st.id
) sub
WHERE s.id = sub.id
  AND COALESCE(s.likes_count, 0) IS DISTINCT FROM sub.cnt;

UPDATE public.stories s
SET views_count = sub.cnt
FROM (
  SELECT st.id, COALESCE(COUNT(v.id), 0) AS cnt
  FROM public.stories st
  LEFT JOIN public.story_views v ON v.story_id = st.id
  GROUP BY st.id
) sub
WHERE s.id = sub.id
  AND COALESCE(s.views_count, 0) IS DISTINCT FROM sub.cnt;

commit;
