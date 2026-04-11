-- Performance Indexes
-- Sık kullanılan sorgular için index ekler
-- Bu index'ler sorgu performansını önemli ölçüde artırır

-- Sadece kesin olarak bildiğimiz tablolar için index

-- Posts tablosu index'leri
CREATE INDEX IF NOT EXISTS idx_posts_created_at ON posts(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_posts_user_id ON posts(user_id);
CREATE INDEX IF NOT EXISTS idx_posts_is_active ON posts(is_active) WHERE is_active = true;

-- Products tablosu index'leri
CREATE INDEX IF NOT EXISTS idx_products_shop_id ON products(shop_id);
CREATE INDEX IF NOT EXISTS idx_products_category ON products(category);
CREATE INDEX IF NOT EXISTS idx_products_is_active ON products(is_active) WHERE is_active = true;

-- Shops tablosu index'leri
CREATE INDEX IF NOT EXISTS idx_shops_owner_id ON shops(owner_id);
CREATE INDEX IF NOT EXISTS idx_shops_category_id ON shops(category_id);
CREATE INDEX IF NOT EXISTS idx_shops_rating ON shops(rating DESC);

-- Orders tablosu index'leri
CREATE INDEX IF NOT EXISTS idx_orders_user_id ON orders(user_id);
CREATE INDEX IF NOT EXISTS idx_orders_created_at ON orders(created_at DESC);

-- Post comments tablosu index'leri
CREATE INDEX IF NOT EXISTS idx_post_comments_post_id ON post_comments(post_id);
CREATE INDEX IF NOT EXISTS idx_post_comments_created_at ON post_comments(created_at DESC);

-- Post likes tablosu index'leri
CREATE INDEX IF NOT EXISTS idx_post_likes_user_id ON post_likes(user_id);
CREATE INDEX IF NOT EXISTS idx_post_likes_post_id ON post_likes(post_id);

-- Follows tablosu index'leri
CREATE INDEX IF NOT EXISTS idx_follows_follower_id ON follows(follower_id);
CREATE INDEX IF NOT EXISTS idx_follows_following_id ON follows(following_id);

-- Story views tablosu index'leri - tablo yapısı farklı, kaldırıldı
