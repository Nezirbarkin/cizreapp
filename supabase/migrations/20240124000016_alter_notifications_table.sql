-- ============================================================================
-- NOTIFICATIONS TABLE - ALTER
-- Mevcut notifications tablosunu güncelle
-- ============================================================================

-- Önce mevcut tabloyu kontrol et
-- Eğer actor_id sütunu yoksa ekle

DO $$
BEGIN
    -- actor_id sütunu yoksa ekle
    IF NOT EXISTS (
        SELECT 1 
        FROM information_schema.columns 
        WHERE table_name = 'notifications' 
        AND column_name = 'actor_id'
        AND table_schema = 'public'
    ) THEN
        ALTER TABLE public.notifications ADD COLUMN actor_id UUID REFERENCES auth.users(id) ON DELETE SET NULL;
    END IF;

    -- actor_name sütunu yoksa ekle
    IF NOT EXISTS (
        SELECT 1 
        FROM information_schema.columns 
        WHERE table_name = 'notifications' 
        AND column_name = 'actor_name'
        AND table_schema = 'public'
    ) THEN
        ALTER TABLE public.notifications ADD COLUMN actor_name TEXT;
    END IF;

    -- actor_avatar sütunu yoksa ekle
    IF NOT EXISTS (
        SELECT 1 
        FROM information_schema.columns 
        WHERE table_name = 'notifications' 
        AND column_name = 'actor_avatar'
        AND table_schema = 'public'
    ) THEN
        ALTER TABLE public.notifications ADD COLUMN actor_avatar TEXT;
    END IF;

    -- entity_id sütunu yoksa ekle
    IF NOT EXISTS (
        SELECT 1 
        FROM information_schema.columns 
        WHERE table_name = 'notifications' 
        AND column_name = 'entity_id'
        AND table_schema = 'public'
    ) THEN
        ALTER TABLE public.notifications ADD COLUMN entity_id TEXT;
    END IF;

    -- entity_image sütunu yoksa ekle
    IF NOT EXISTS (
        SELECT 1 
        FROM information_schema.columns 
        WHERE table_name = 'notifications' 
        AND column_name = 'entity_image'
        AND table_schema = 'public'
    ) THEN
        ALTER TABLE public.notifications ADD COLUMN entity_image TEXT;
    END IF;

    -- updated_at sütunu yoksa ekle
    IF NOT EXISTS (
        SELECT 1 
        FROM information_schema.columns 
        WHERE table_name = 'notifications' 
        AND column_name = 'updated_at'
        AND table_schema = 'public'
    ) THEN
        ALTER TABLE public.notifications ADD COLUMN updated_at TIMESTAMPTZ DEFAULT NOW();
    END IF;
END $$;

-- Index'leri oluştur yoksa
CREATE INDEX IF NOT EXISTS notifications_actor_id_idx ON public.notifications(actor_id);
CREATE INDEX IF NOT EXISTS notifications_entity_id_idx ON public.notifications(entity_id);

-- Type constraint'i güncelle
ALTER TABLE public.notifications DROP CONSTRAINT IF EXISTS notifications_type_check;
ALTER TABLE public.notifications ADD CONSTRAINT notifications_type_check 
    CHECK (type IN ('like', 'comment', 'follow', 'mention', 'order', 'shop'));

-- Updated_at trigger'ı oluştur
CREATE OR REPLACE FUNCTION update_notifications_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS notifications_updated_at ON public.notifications;
CREATE TRIGGER notifications_updated_at
BEFORE UPDATE ON public.notifications
FOR EACH ROW
EXECUTE FUNCTION update_notifications_updated_at();
