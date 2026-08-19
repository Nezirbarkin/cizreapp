-- =====================================================
-- AI Prompt Görsel Kütüphanesi Tablosu
-- =====================================================

CREATE TABLE IF NOT EXISTS ai_prompt_images (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    
    -- Görsel bilgileri
    image_url TEXT NOT NULL,
    thumbnail_url TEXT,
    
    -- Kategori ve etiketler
    category TEXT DEFAULT 'general',
    tags TEXT[] DEFAULT '{}',
    
    -- Erişilebilirlik
    alt_text TEXT,
    
    -- Boyut bilgileri
    width INTEGER,
    height INTEGER,
    file_size INTEGER,
    
    -- Metadata
    created_by UUID REFERENCES profiles(id) ON DELETE SET NULL,
    
    -- Durum
    is_active BOOLEAN DEFAULT true,
    usage_count INTEGER DEFAULT 0,
    
    -- Zaman damgaları
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);

-- =====================================================
-- Indexes
-- =====================================================
CREATE INDEX IF NOT EXISTS idx_ai_prompt_images_category ON ai_prompt_images(category);
CREATE INDEX IF NOT EXISTS idx_ai_prompt_images_active ON ai_prompt_images(is_active) WHERE is_active = true;
CREATE INDEX IF NOT EXISTS idx_ai_prompt_images_created_at ON ai_prompt_images(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_ai_prompt_images_usage ON ai_prompt_images(usage_count DESC);

-- =====================================================
-- RLS Policies
-- =====================================================
ALTER TABLE ai_prompt_images ENABLE ROW LEVEL SECURITY;

-- Herkes okuyabilir (aktif görselleri)
CREATE POLICY "Anyone can view active ai prompt images"
ON ai_prompt_images
FOR SELECT
USING (is_active = true);

-- Admin her şeyi yapabilir
CREATE POLICY "Admins can do everything with ai prompt images"
ON ai_prompt_images
FOR ALL
USING (
    EXISTS (
        SELECT 1 FROM profiles 
        WHERE id = auth.uid() 
        AND role = 'admin'
    )
);

-- =====================================================
-- Updated_at otomatik güncelleme fonksiyonu
-- =====================================================
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Tetikleyici
DROP TRIGGER IF EXISTS update_ai_prompt_images_updated_at ON ai_prompt_images;
CREATE TRIGGER update_ai_prompt_images_updated_at
    BEFORE UPDATE ON ai_prompt_images
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- =====================================================
-- NOT: Varsayılan görseller eklenmedi - Görseller admin tarafından yüklenecek
-- =====================================================
