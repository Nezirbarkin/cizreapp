-- Ürün favorileri tablosu
CREATE TABLE IF NOT EXISTS product_favorites (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    product_id UUID NOT NULL REFERENCES products(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(user_id, product_id)
);

-- İndeksler
CREATE INDEX IF NOT EXISTS idx_product_favorites_user_id ON product_favorites(user_id);
CREATE INDEX IF NOT EXISTS idx_product_favorites_product_id ON product_favorites(product_id);
CREATE INDEX IF NOT EXISTS idx_product_favorites_created_at ON product_favorites(created_at DESC);

-- RLS Politikaları
ALTER TABLE product_favorites ENABLE ROW LEVEL SECURITY;

-- Kullanıcı sadece kendi favorilerini görebilir
CREATE POLICY "Users can view their own product favorites"
ON product_favorites
FOR SELECT
USING (auth.uid() = user_id);

-- Kullanıcı sadece kendi favori ekleyebilir
CREATE POLICY "Users can insert their own product favorites"
ON product_favorites
FOR INSERT
WITH CHECK (auth.uid() = user_id);

-- Kullanıcı sadece kendi favorilerini silebilir
CREATE POLICY "Users can delete their own product favorites"
ON product_favorites
FOR DELETE
USING (auth.uid() = user_id);

-- Fonksiyon: Ürünün favori sayısını getir
CREATE OR REPLACE FUNCTION get_product_favorite_count(p_product_id UUID)
RETURNS INTEGER AS $$
BEGIN
    RETURN (
        SELECT COUNT(*)
        FROM product_favorites
        WHERE product_id = p_product_id
    );
END;
$$ LANGUAGE plpgsql;

-- Fonksiyon: Ürünün kullanıcı tarafından favorilenip favorilenmediğini kontrol et
CREATE OR REPLACE FUNCTION is_product_favorited(p_user_id UUID, p_product_id UUID)
RETURNS BOOLEAN AS $$
BEGIN
    RETURN EXISTS (
        SELECT 1
        FROM product_favorites
        WHERE user_id = p_user_id AND product_id = p_product_id
    );
END;
$$ LANGUAGE plpgsql;

-- Fonksiyon: Ürünü favorilere ekle veya çıkar
CREATE OR REPLACE FUNCTION toggle_product_favorite(p_user_id UUID, p_product_id UUID)
RETURNS BOOLEAN AS $$
DECLARE
    v_is_favorited BOOLEAN;
BEGIN
    -- Önce mevcut durumunu kontrol et
    SELECT EXISTS (
        SELECT 1 FROM product_favorites
        WHERE user_id = p_user_id AND product_id = p_product_id
    ) INTO v_is_favorited;

    IF v_is_favorited THEN
        -- Favoriden çıkar
        DELETE FROM product_favorites
        WHERE user_id = p_user_id AND product_id = p_product_id;
        RETURN FALSE;
    ELSE
        -- Favoriye ekle
        INSERT INTO product_favorites (user_id, product_id)
        VALUES (p_user_id, p_product_id);
        RETURN TRUE;
    END IF;
END;
$$ LANGUAGE plpgsql;
