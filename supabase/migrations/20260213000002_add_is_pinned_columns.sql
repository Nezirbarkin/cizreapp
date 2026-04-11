-- is_pinned kolonu ekleme - Story, Product, Post, Shop tablolarına
-- Admin panelinden içerik sabitleme özelliği

-- Stories tablosuna is_pinned ekle
ALTER TABLE stories ADD COLUMN IF NOT EXISTS is_pinned BOOLEAN DEFAULT false;
CREATE INDEX IF NOT EXISTS idx_stories_is_pinned ON stories (is_pinned) WHERE is_pinned = true;

-- Products tablosuna is_pinned ekle
ALTER TABLE products ADD COLUMN IF NOT EXISTS is_pinned BOOLEAN DEFAULT false;
CREATE INDEX IF NOT EXISTS idx_products_is_pinned ON products (is_pinned) WHERE is_pinned = true;

-- Posts tablosuna is_pinned ekle
ALTER TABLE posts ADD COLUMN IF NOT EXISTS is_pinned BOOLEAN DEFAULT false;
CREATE INDEX IF NOT EXISTS idx_posts_is_pinned ON posts (is_pinned) WHERE is_pinned = true;

-- Shops tablosuna is_pinned ekle
ALTER TABLE shops ADD COLUMN IF NOT EXISTS is_pinned BOOLEAN DEFAULT false;
CREATE INDEX IF NOT EXISTS idx_shops_is_pinned ON shops (is_pinned) WHERE is_pinned = true;
