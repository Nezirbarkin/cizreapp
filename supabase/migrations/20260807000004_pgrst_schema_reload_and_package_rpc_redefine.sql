-- ============================================================================
-- list_available_package_requests RPC tanımını yeniden yükle + PostgREST
-- schema cache'ini yenile.
-- ============================================================================
-- Arka plan (tespit edilen hata):
--   * Kurye panel ekranı RPC `list_available_package_requests` çağırıyor;
--     istemci şu hatayı alıyor:
--       PGRST202: Could not find the function
--       public.list_available_package_requests without parameters in the
--       schema cache
--   * Olası kök nedenler:
--       (a) Migration remote DB'ye henüz uygulanmamış olabilir.
--       (b) Migration uygulandı ama PostgREST'in fonksiyon listesini tutan
--           `pg_catalog` cache'i eski kalmış olabilir. Yeni RPC tanımları
--           için `NOTIFY pgrst, 'reload schema'` gerekir.
--   * Bu migration her iki senaryoyu da aynı anda çözer:
--       1) `list_available_package_requests` fonksiyonunu
--          `CREATE OR REPLACE` ile idempotent şekilde yeniden tanımlar
--          (varsa gövde güncellenir, yoksa oluşturulur).
--       2) Migration sonunda PostgREST'e `NOTIFY pgrst, 'reload schema'`
--          gönderir; cache'i hemen yenilemesini söyler.
--   * İstemci tarafında değişiklik yok: RPC imzası (parametresiz,
--     aynı kolonlar) korundu.
--
-- Güvenlik kapsamı: Fonksiyon mevcut haliyle SECURITY DEFINER +
-- `is_courier_role()` + `auth.uid()` filtresi içeriyor. Bu migration
-- yalnızca yeniden tanımlama + cache tetikleme; güvenlik modeline
-- dokunmuyor.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.list_available_package_requests()
RETURNS TABLE(
  id uuid,
  distance_km numeric,
  total_fee numeric,
  courier_fee numeric,
  delivery_card_label text,
  created_at timestamptz
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT cr.id, cr.distance_km, cr.total_fee, cr.courier_fee,
         cr.delivery_card_label, cr.created_at
  FROM public.courier_requests AS cr
  WHERE cr.status = 'pending'
    AND cr.courier_id IS NULL
    AND cr.sender_id <> (SELECT auth.uid())
    AND NOT EXISTS (
      SELECT 1 FROM public.courier_request_rejections AS crr
      WHERE crr.request_id = cr.id
        AND crr.courier_id = (SELECT auth.uid())
    )
    AND (SELECT auth.uid()) IS NOT NULL
    AND public.is_courier_role()
  ORDER BY cr.created_at ASC;
$$;

-- Grant'leri koru (önceki migration'da da aynıydı; tekrar ver ki
-- CREATE OR REPLACE sonrası GRANT state'i deterministik olsun).
REVOKE ALL ON FUNCTION public.list_available_package_requests() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.list_available_package_requests() TO authenticated;

COMMENT ON FUNCTION public.list_available_package_requests()
  IS 'Kurye rolündeki authenticated kullanıcılar için PII içermeyen bekleyen havuz.';

-- -----------------------------------------------------------------------------
-- PostgREST schema cache'ini yenile
-- -----------------------------------------------------------------------------
-- NOTIFY channel adı PostgREST'in beklediği addır (`pgrst`). Payload olarak
-- 'reload schema' gönderildiğinde PostgREST fonksiyon/tablo listesini
-- `pg_catalog`'tan yeniden çeker. Çok sık çağrılması gereksiz reload'a
-- yol açar; bu yüzden yalnızca bu migration'ın sonunda tetikleniyor.
-- Çoğu durumda idempotenttir (PostgREST reload zaten atomik).
DO $$
BEGIN
  PERFORM pg_notify('pgrst', 'reload schema');
  RAISE NOTICE 'PostgREST schema cache reload tetiklendi (NOTIFY pgrst)';
EXCEPTION WHEN OTHERS THEN
  -- NOTIFY neredeyse her zaman başarılıdır, ama yine de migration'ı
  -- kırmayalım. Hata loglanır, manuel reload gerekebilir.
  RAISE WARNING 'PostgREST reload tetiklenemedi: %. Dashboard > API > '
                'Reload schema cache butonunu kullanın.', SQLERRM;
END;
$$;
