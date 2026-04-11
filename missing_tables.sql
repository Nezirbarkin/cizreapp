-- =====================================================
-- EKSİK TABLOLAR - SUPABASE SCHEMA'YA EKLENECEK
-- =====================================================
-- Bu dosyayı supabase_schema.sql'den SONRA çalıştırın

-- Post Saves (Kayıtlı Gönderiler) - Profil modülü için gerekli
CREATE TABLE IF NOT EXISTS post_saves (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    post_id UUID REFERENCES posts(id) ON DELETE CASCADE,
    user_id UUID REFERENCES profiles(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(post_id, user_id)
);

-- Campaigns (Kampanyalar) - Opsiyonel ama RLS için gerekli
CREATE TABLE IF NOT EXISTS campaigns (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    shop_id UUID REFERENCES shops(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    description TEXT,
    image_url TEXT,
    discount_percentage DECIMAL(5, 2),
    start_date TIMESTAMPTZ NOT NULL,
    end_date TIMESTAMPTZ NOT NULL,
    is_active BOOLEAN DEFAULT true,
    user_id UUID REFERENCES profiles(id) ON DELETE CASCADE, -- Kampanya oluşturan
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Coupons (Kuponlar) - Opsiyonel ama RLS için gerekli
CREATE TABLE IF NOT EXISTS coupons (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    code TEXT UNIQUE NOT NULL,
    description TEXT,
    discount_type TEXT CHECK (discount_type IN ('percentage', 'fixed')),
    discount_value DECIMAL(10, 2) NOT NULL,
    min_order_amount DECIMAL(10, 2),
    max_usage INT,
    used_count INT DEFAULT 0,
    valid_until TIMESTAMPTZ NOT NULL,
    is_active BOOLEAN DEFAULT true,
    user_id UUID REFERENCES profiles(id) ON DELETE CASCADE, -- Kupon oluşturan
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Index'ler
CREATE INDEX IF NOT EXISTS idx_post_saves_user ON post_saves(user_id);
CREATE INDEX IF NOT EXISTS idx_post_saves_post ON post_saves(post_id);
CREATE INDEX IF NOT EXISTS idx_campaigns_shop ON campaigns(shop_id);
CREATE INDEX IF NOT EXISTS idx_coupons_code ON coupons(code);

-- ✅ BAŞARILI - Artık RLS politikaları çalışacak!
