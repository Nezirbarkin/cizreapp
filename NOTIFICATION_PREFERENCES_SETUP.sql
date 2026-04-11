-- Bildirim Tercihleri Tablosu
CREATE TABLE IF NOT EXISTS public.notification_preferences (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    
    -- Bildirim türleri
    likes_enabled BOOLEAN DEFAULT TRUE,           -- Beğeni bildirimleri
    comments_enabled BOOLEAN DEFAULT TRUE,        -- Yorum bildirimleri
    followers_enabled BOOLEAN DEFAULT TRUE,       -- Takipçi bildirimleri
    order_updates_enabled BOOLEAN DEFAULT TRUE,   -- Sipariş güncellemeleri
    order_ready_enabled BOOLEAN DEFAULT TRUE,     -- Sipariş hazırlandı
    delivery_enabled BOOLEAN DEFAULT TRUE,        -- Teslimat başladı
    promotional_enabled BOOLEAN DEFAULT FALSE,    -- Promosyonel bildirimler
    
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    
    CONSTRAINT unique_user_preferences UNIQUE(user_id)
);

-- RLS Politikaları
ALTER TABLE public.notification_preferences ENABLE ROW LEVEL SECURITY;

-- Kullanıcı sadece kendi tercihlerini görebilir
CREATE POLICY "Users can view their own notification preferences"
    ON public.notification_preferences FOR SELECT
    USING (auth.uid() = user_id);

-- Kullanıcı sadece kendi tercihlerini güncelleyebilir
CREATE POLICY "Users can update their own notification preferences"
    ON public.notification_preferences FOR UPDATE
    USING (auth.uid() = user_id);

-- Kullanıcı sadece kendi tercihlerini ekleyebilir
CREATE POLICY "Users can insert their own notification preferences"
    ON public.notification_preferences FOR INSERT
    WITH CHECK (auth.uid() = user_id);

-- Index
CREATE INDEX idx_notification_preferences_user_id ON public.notification_preferences(user_id);

-- Yeni profil oluşturulduğunda otomatik bildirim tercihleri oluştur
CREATE OR REPLACE FUNCTION create_notification_preferences()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO public.notification_preferences (user_id)
    VALUES (NEW.id)
    ON CONFLICT (user_id) DO NOTHING;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Trigger
DROP TRIGGER IF EXISTS create_notification_preferences_trigger ON public.profiles;
CREATE TRIGGER create_notification_preferences_trigger
    AFTER INSERT ON public.profiles
    FOR EACH ROW
    EXECUTE FUNCTION create_notification_preferences();
