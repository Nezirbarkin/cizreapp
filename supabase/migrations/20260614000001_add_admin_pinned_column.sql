-- Admin sabitleme için ayrı bir sütun ekle
-- is_pinned: kullanıcı kendi gönderisini sabitlediğinde (sadece profil sayfasında görünür)
-- admin_pinned: admin sabitlediğinde (feed'de sabitlenmiş olarak görünür)

-- Posts tablosuna admin_pinned sütunu ekle
ALTER TABLE posts ADD COLUMN IF NOT EXISTS admin_pinned BOOLEAN DEFAULT false;

-- Stories tablosuna admin_pinned sütunu ekle
ALTER TABLE stories ADD COLUMN IF NOT EXISTS admin_pinned BOOLEAN DEFAULT false;

-- Products tablosuna admin_pinned sütunu ekle
ALTER TABLE products ADD COLUMN IF NOT EXISTS admin_pinned BOOLEAN DEFAULT false;

-- Shops tablosuna admin_pinned sütunu ekle
ALTER TABLE shops ADD COLUMN IF NOT EXISTS admin_pinned BOOLEAN DEFAULT false;

-- Index oluştur (partial index, sadece admin_pinned = true olanlar için)
CREATE INDEX IF NOT EXISTS idx_posts_admin_pinned ON posts (admin_pinned) WHERE admin_pinned = true;
CREATE INDEX IF NOT EXISTS idx_stories_admin_pinned ON stories (admin_pinned) WHERE admin_pinned = true;
CREATE INDEX IF NOT EXISTS idx_products_admin_pinned ON products (admin_pinned) WHERE admin_pinned = true;
CREATE INDEX IF NOT EXISTS idx_shops_admin_pinned ON shops (admin_pinned) WHERE admin_pinned = true;

-- Comments ekle
COMMENT ON COLUMN posts.admin_pinned IS 'Admin tarafından sabitlenen gönderiler. Feedde sabitlenmiş olarak görünür.';
COMMENT ON COLUMN stories.admin_pinned IS 'Admin tarafından sabitlenen hikayeler.';
COMMENT ON COLUMN products.admin_pinned IS 'Admin tarafından sabitlenen ürünler.';
COMMENT ON COLUMN shops.admin_pinned IS 'Admin tarafından sabitlenen dükkanlar.';
