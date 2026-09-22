-- =============================================================================
-- REALTIME YAYINI — UYGULAMANIN ABONE OLDUĞU AMA YAYINDA OLMAYAN TABLOLAR
-- -----------------------------------------------------------------------------
-- 20260917000001 Okey masasındaki sessiz senkron hatasını düzeltirken aynı
-- sınıftan altı hata daha çıktı: uygulama `onPostgresChanges` ile abone
-- oluyor, tablo `supabase_realtime` publication'ında olmadığı için tek olay
-- bile gelmiyor. Kanal "SUBSCRIBED" der, hiçbir yere hata düşmez.
--
-- Etkilenen ekranlar:
--   * notifications, courier_assignments → kurye paneli
--     (courier_panel_screen.dart _subscribeToCourierWorkChanges): yeni sipariş
--     teklifi / devir anında düşmüyor, kurye listeyi elle yenilemek zorunda.
--   * orders, courier_assignments → satıcı sipariş ekranı
--     (seller_orders_screen.dart): yeni sipariş ve durum değişimi canlı değil.
--   * orders → alıcının sipariş takibi (order_detail_screen.dart): "hazırlanıyor
--     → yolda → teslim edildi" ekranda kendiliğinden ilerlemiyordu.
--   * orders, digital_orders, posts, products → admin panelinin canlı sayaçları.
--
-- ## Güvenlik — yayın RLS'i atlatmaz, ama RLS'in doğru olması ŞART
--
-- Realtime her olayı abonenin yetkisiyle süzer; buradaki altı tablonun da
-- RLS'i açık ve SELECT politikaları sahibine/ilgilisine bağlı:
--   * notifications → user_id = auth.uid()
--   * courier_assignments → dükkân sahibi | atanan kurye | admin
--   * orders → müşteri | dükkân sahibi | atanan kurye | admin | (kurye havuzu,
--     artık `is_courier_role()` ile kapılı — bkz. 20260917000002; O DÜZELTME
--     BU GÖÇÜN ÖN KOŞULUDUR, çünkü satırda adres ve telefon var)
--   * digital_orders → alıcı | sağlayıcı satıcı | admin
--   * posts → zaten görünen akış kuralı (aktif gönderi + can_view_social_author)
--   * products → aktif/satıştaki ürün, yani herkese açık katalog verisi
--
-- Satıcı sipariş ekranı `orders`a FİLTRESİZ abone olup shop_id'yi istemcide
-- eleediği için bu özellikle önemli: süzgeç RLS'tir, istemci değil.
--
-- ## Kapsam dışı bırakılanlar
--
-- `okey_room_players` (10 saniyelik "buradayım" damgaları yüzünden olay seli)
-- ve `okey_rooms` eklenmedi — oda ekranının kendi yoklaması var
-- (bkz. 20260917000001).
--
-- Altı tablonun da birincil anahtarı var; REPLICA IDENTITY'ye dokunulmadı,
-- dolayısıyla UPDATE'ler replica identity hatasına düşmez. Bu göç İSTEMCİ
-- GÜNCELLEMESİ GEREKTİRMEZ: mağazadaki sürüm bu abonelikleri zaten açıyor.
-- =============================================================================

SET search_path = public, pg_temp;

DO $$
DECLARE
  v_table text;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime') THEN
    RAISE NOTICE 'supabase_realtime publication yok — atlandı';
    RETURN;
  END IF;

  FOREACH v_table IN ARRAY ARRAY[
    'notifications',
    'courier_assignments',
    'orders',
    'digital_orders',
    'posts',
    'products'
  ]
  LOOP
    IF NOT EXISTS (
      SELECT 1 FROM pg_class c
      JOIN pg_namespace n ON n.oid = c.relnamespace
      WHERE n.nspname = 'public' AND c.relname = v_table
    ) THEN
      RAISE NOTICE 'tablo yok, atlandı: %', v_table;
      CONTINUE;
    END IF;

    -- RLS kapalıysa EKLEME: Realtime böyle bir tablonun her satırını her
    -- aboneye gönderir.
    IF NOT (SELECT c.relrowsecurity FROM pg_class c
            JOIN pg_namespace n ON n.oid = c.relnamespace
            WHERE n.nspname = 'public' AND c.relname = v_table) THEN
      RAISE WARNING 'RLS kapalı, yayına EKLENMEDİ: %', v_table;
      CONTINUE;
    END IF;

    -- Birincil anahtarı olmayan tabloyu eklemek UPDATE'leri kırar
    -- ("cannot update table ... does not have a replica identity").
    IF NOT EXISTS (
      SELECT 1 FROM pg_constraint con
      JOIN pg_class c ON c.oid = con.conrelid
      JOIN pg_namespace n ON n.oid = c.relnamespace
      WHERE n.nspname = 'public' AND c.relname = v_table AND con.contype = 'p'
    ) THEN
      RAISE WARNING 'birincil anahtar yok, yayına EKLENMEDİ: %', v_table;
      CONTINUE;
    END IF;

    IF EXISTS (
      SELECT 1 FROM pg_publication_tables
      WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = v_table
    ) THEN
      CONTINUE;
    END IF;

    EXECUTE format('ALTER PUBLICATION supabase_realtime ADD TABLE public.%I', v_table);
    RAISE NOTICE 'supabase_realtime yayınına eklendi: %', v_table;
  END LOOP;
END;
$$;
