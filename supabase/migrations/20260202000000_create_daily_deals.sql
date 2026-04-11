-- Daily Deals tablosu
-- Admin'in günün fırsatları kartlarını yönetebileceği tablo

CREATE TABLE IF NOT EXISTS daily_deals (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    title VARCHAR(100) NOT NULL,
    subtitle VARCHAR(100),
    image_url TEXT NOT NULL,
    link_type VARCHAR(20) NOT NULL DEFAULT 'shop', -- 'shop', 'campaign', 'category', 'product'
    link_id UUID, -- shop_id, campaign_id, category_id veya product_id
    link_url TEXT, -- Opsiyonel harici URL
    sort_order INTEGER DEFAULT 0,
    is_active BOOLEAN DEFAULT true,
    start_date TIMESTAMPTZ,
    end_date TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Indexler
CREATE INDEX IF NOT EXISTS idx_daily_deals_active ON daily_deals(is_active);
CREATE INDEX IF NOT EXISTS idx_daily_deals_sort ON daily_deals(sort_order);
CREATE INDEX IF NOT EXISTS idx_daily_deals_dates ON daily_deals(start_date, end_date);

-- RLS politikaları
ALTER TABLE daily_deals ENABLE ROW LEVEL SECURITY;

-- Herkes okuyabilir (aktif olanları)
CREATE POLICY "daily_deals_select_policy" ON daily_deals
    FOR SELECT USING (true);

-- Sadece admin ekleyebilir/güncelleyebilir/silebilir
CREATE POLICY "daily_deals_insert_policy" ON daily_deals
    FOR INSERT WITH CHECK (
        EXISTS (
            SELECT 1 FROM profiles
            WHERE id = (SELECT auth.uid())
            AND role = 'admin'
        )
    );

CREATE POLICY "daily_deals_update_policy" ON daily_deals
    FOR UPDATE USING (
        EXISTS (
            SELECT 1 FROM profiles
            WHERE id = (SELECT auth.uid())
            AND role = 'admin'
        )
    );

CREATE POLICY "daily_deals_delete_policy" ON daily_deals
    FOR DELETE USING (
        EXISTS (
            SELECT 1 FROM profiles
            WHERE id = (SELECT auth.uid())
            AND role = 'admin'
        )
    );

-- Updated_at trigger
CREATE OR REPLACE FUNCTION update_daily_deals_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

DROP TRIGGER IF EXISTS daily_deals_updated_at ON daily_deals;
CREATE TRIGGER daily_deals_updated_at
    BEFORE UPDATE ON daily_deals
    FOR EACH ROW
    EXECUTE FUNCTION update_daily_deals_updated_at();

-- Storage bucket for deal images
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES ('deals', 'deals', true, 5242880, ARRAY['image/png', 'image/jpeg', 'image/webp', 'image/gif'])
ON CONFLICT (id) DO NOTHING;

-- Storage policies for deals bucket
CREATE POLICY "deals_select_policy" ON storage.objects
    FOR SELECT USING (bucket_id = 'deals');

CREATE POLICY "deals_insert_policy" ON storage.objects
    FOR INSERT WITH CHECK (
        bucket_id = 'deals' 
        AND EXISTS (
            SELECT 1 FROM profiles
            WHERE id = (SELECT auth.uid())
            AND role = 'admin'
        )
    );

CREATE POLICY "deals_update_policy" ON storage.objects
    FOR UPDATE USING (
        bucket_id = 'deals'
        AND EXISTS (
            SELECT 1 FROM profiles
            WHERE id = (SELECT auth.uid())
            AND role = 'admin'
        )
    );

CREATE POLICY "deals_delete_policy" ON storage.objects
    FOR DELETE USING (
        bucket_id = 'deals'
        AND EXISTS (
            SELECT 1 FROM profiles
            WHERE id = (SELECT auth.uid())
            AND role = 'admin'
        )
    );

-- Örnek veriler
INSERT INTO daily_deals (title, subtitle, image_url, link_type, sort_order, is_active) VALUES
    ('Kasap', '%20 İndirim', 'https://images.unsplash.com/photo-1607623814075-e51df1bdc82f?w=400', 'category', 1, true),
    ('Fırın', 'Taze Ekmek', 'https://images.unsplash.com/photo-1509440159596-0249088772ff?w=400', 'category', 2, true),
    ('Manav', '3 Al 2 Öde', 'https://images.unsplash.com/photo-1542838132-92c53300491e?w=400', 'category', 3, true),
    ('Teknoloji', 'Fırsat', 'https://images.unsplash.com/photo-1505740420928-5e560c06d30e?w=400', 'category', 4, true)
ON CONFLICT DO NOTHING;

COMMENT ON TABLE daily_deals IS 'Günün fırsatları kartları - Admin tarafından yönetilir';
