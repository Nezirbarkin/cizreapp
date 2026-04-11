-- Add min_order_amount and delivery_fee to shops table
ALTER TABLE shops 
ADD COLUMN IF NOT EXISTS min_order_amount NUMERIC DEFAULT 0.0 NOT NULL,
ADD COLUMN IF NOT EXISTS delivery_fee NUMERIC DEFAULT 0.0 NOT NULL;

-- Add comment
COMMENT ON COLUMN shops.min_order_amount IS 'Minimum order amount required for this shop';
COMMENT ON COLUMN shops.delivery_fee IS 'Delivery fee for orders from this shop';
