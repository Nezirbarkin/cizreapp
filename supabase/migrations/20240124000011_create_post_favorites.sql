-- Gönderi favorileri tablosu
CREATE TABLE IF NOT EXISTS post_favorites (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    post_id UUID NOT NULL REFERENCES posts(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(user_id, post_id)
);

-- İndeksler
CREATE INDEX IF NOT EXISTS idx_post_favorites_user_id ON post_favorites(user_id);
CREATE INDEX IF NOT EXISTS idx_post_favorites_post_id ON post_favorites(post_id);
CREATE INDEX IF NOT EXISTS idx_post_favorites_created_at ON post_favorites(created_at DESC);

-- RLS Politikaları
ALTER TABLE post_favorites ENABLE ROW LEVEL SECURITY;

-- Kullanıcı sadece kendi favorilerini görebilir
CREATE POLICY "Users can view their own post favorites"
ON post_favorites
FOR SELECT
USING (auth.uid() = user_id);

-- Kullanıcı sadece kendi favori ekleyebilir
CREATE POLICY "Users can insert their own post favorites"
ON post_favorites
FOR INSERT
WITH CHECK (auth.uid() = user_id);

-- Kullanıcı sadece kendi favorilerini silebilir
CREATE POLICY "Users can delete their own post favorites"
ON post_favorites
FOR DELETE
USING (auth.uid() = user_id);

-- Fonksiyon: Gönderinin favori sayısını getir
CREATE OR REPLACE FUNCTION get_post_favorite_count(p_post_id UUID)
RETURNS INTEGER AS $$
BEGIN
    RETURN (
        SELECT COUNT(*)
        FROM post_favorites
        WHERE post_id = p_post_id
    );
END;
$$ LANGUAGE plpgsql;

-- Fonksiyon: Gönderinin kullanıcı tarafından favorilenip favorilenmediğini kontrol et
CREATE OR REPLACE FUNCTION is_post_favorited(p_user_id UUID, p_post_id UUID)
RETURNS BOOLEAN AS $$
BEGIN
    RETURN EXISTS (
        SELECT 1
        FROM post_favorites
        WHERE user_id = p_user_id AND post_id = p_post_id
    );
END;
$$ LANGUAGE plpgsql;

-- Fonksiyon: Gönderiyi favorilere ekle veya çıkar
CREATE OR REPLACE FUNCTION toggle_post_favorite(p_user_id UUID, p_post_id UUID)
RETURNS BOOLEAN AS $$
DECLARE
    v_is_favorited BOOLEAN;
BEGIN
    -- Önce mevcut durumunu kontrol et
    SELECT EXISTS (
        SELECT 1 FROM post_favorites
        WHERE user_id = p_user_id AND post_id = p_post_id
    ) INTO v_is_favorited;

    IF v_is_favorited THEN
        -- Favoriden çıkar
        DELETE FROM post_favorites
        WHERE user_id = p_user_id AND post_id = p_post_id;
        RETURN FALSE;
    ELSE
        -- Favoriye ekle
        INSERT INTO post_favorites (user_id, post_id)
        VALUES (p_user_id, p_post_id);
        RETURN TRUE;
    END IF;
END;
$$ LANGUAGE plpgsql;
