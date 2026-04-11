-- Add is_pinned column to posts, stories, products and shops tables
-- This column controls whether an item is pinned/sponsored at the top

-- Add the column to posts table if it doesn't exist
ALTER TABLE posts 
ADD COLUMN IF NOT EXISTS is_pinned BOOLEAN DEFAULT false;

-- Add the column to stories table if it doesn't exist
ALTER TABLE stories 
ADD COLUMN IF NOT EXISTS is_pinned BOOLEAN DEFAULT false;

-- Add the column to products table if it doesn't exist
ALTER TABLE products 
ADD COLUMN IF NOT EXISTS is_pinned BOOLEAN DEFAULT false;

-- Add the column to shops table if it doesn't exist
ALTER TABLE shops 
ADD COLUMN IF NOT EXISTS is_pinned BOOLEAN DEFAULT false;

-- Add comments for documentation
COMMENT ON COLUMN posts.is_pinned IS 'Controls whether the post is pinned/sponsored at the top of feeds';
COMMENT ON COLUMN stories.is_pinned IS 'Controls whether the story is pinned/sponsored at the top';
COMMENT ON COLUMN products.is_pinned IS 'Controls whether the product is pinned/sponsored at the top';
COMMENT ON COLUMN shops.is_pinned IS 'Controls whether the shop is pinned/sponsored at the top';
