-- Add seller_pinned column to products table
-- This allows sellers to pin products in their own shop
-- is_pinned remains admin-only for global sponsor products

ALTER TABLE products
ADD COLUMN IF NOT EXISTS seller_pinned BOOLEAN DEFAULT FALSE;

-- Create index for better query performance
CREATE INDEX IF NOT EXISTS idx_products_seller_pinned ON products(seller_pinned) WHERE seller_pinned = TRUE;

-- Add comment
COMMENT ON COLUMN products.seller_pinned IS 'Seller can pin products in their shop. is_pinned is for admin sponsor products.';
