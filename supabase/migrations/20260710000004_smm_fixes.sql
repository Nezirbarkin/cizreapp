-- SMM entegrasyonu düzeltmeleri ve ek özellikler
-- 1) digital_orders tablosuna table-level GRANT eksikti (RLS policy'si vardı ama GRANT olmadan
--    authenticated rolü satırlara erişemiyordu) - müşteri sipariş verdikten sonra listede
--    görünmemesinin sebebi buydu.
GRANT SELECT ON digital_orders TO authenticated;
GRANT ALL ON digital_orders TO service_role;
GRANT ALL ON smm_providers TO service_role;

-- 2) Ürünün bağlı olduğu SMM servisi sağlayıcıda artık yoksa/pasifse ürünü otomatik gizlemek için
--    smm-sync-products Edge Function'ının kullanacağı kolon: sağlayıcıda servis bulunamazsa
--    is_available false yapılır, sebebi burada tutulur.
ALTER TABLE products ADD COLUMN IF NOT EXISTS smm_disabled_reason TEXT;
