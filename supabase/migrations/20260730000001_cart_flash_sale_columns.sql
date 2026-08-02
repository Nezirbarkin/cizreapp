-- ============================================================================
-- FLASH SALE: cart + order_items kolonları
-- ============================================================================
-- CizreApp - Sepet ve sipariş kalemlerinde flaş indirim bilgisini taşımak
-- için `flash_sale_id` ve `flash_price` kolonları eklenir.
-- - `flash_sale_id`: Hangi flaş satıştan geldi (release için referans).
-- - `flash_price`: Sepete eklenirken sabitlenen fiyat. Satıcı sale'i
--   güncellerse bile kullanıcı aleyhine değişmez (kullanıcı deneyimi).
-- - Nullable: Mevcut cart ve order satırları etkilenmez, geriye uyumlu.
-- ============================================================================

-- cart tablosu
ALTER TABLE cart
  ADD COLUMN IF NOT EXISTS flash_sale_id UUID NULL REFERENCES flash_sales(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS flash_price NUMERIC(10,2) NULL;

CREATE INDEX IF NOT EXISTS idx_cart_flash_sale ON cart(flash_sale_id);

-- order_items tablosu
ALTER TABLE order_items
  ADD COLUMN IF NOT EXISTS flash_sale_id UUID NULL,
  ADD COLUMN IF NOT EXISTS flash_price NUMERIC(10,2) NULL;

CREATE INDEX IF NOT EXISTS idx_order_items_flash_sale ON order_items(flash_sale_id);

-- ============================================================================
-- TAMAMLANDI
-- ============================================================================
-- Bu script idempotent: tekrar çalıştırılabilir.
-- ============================================================================
