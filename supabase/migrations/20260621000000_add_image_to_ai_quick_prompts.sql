-- =====================================================
-- AI Quick Prompts tablosuna görsel desteği ekle
-- =====================================================

-- Görsel URL alanı (thumbnail için)
ALTER TABLE ai_quick_prompts 
ADD COLUMN IF NOT EXISTS image_url TEXT;

-- Kategori alanı
ALTER TABLE ai_quick_prompts 
ADD COLUMN IF NOT EXISTS category TEXT DEFAULT 'general';

-- Thumbnail arka plan rengi (görsel yoksa kullanılacak)
ALTER TABLE ai_quick_prompts 
ADD COLUMN IF NOT EXISTS thumbnail_color TEXT DEFAULT '#7B2CBF';

-- Mevcut verileri güncelle (varsayılan değerlerle)
UPDATE ai_quick_prompts 
SET 
    category = COALESCE(category, 'general'),
    thumbnail_color = COALESCE(thumbnail_color, '#7B2CBF')
WHERE TRUE;

-- Index ekle (performans için)
CREATE INDEX IF NOT EXISTS idx_ai_quick_prompts_category 
ON ai_quick_prompts(category);

CREATE INDEX IF NOT EXISTS idx_ai_quick_prompts_active 
ON ai_quick_prompts(is_active) 
WHERE is_active = true;

CREATE INDEX IF NOT EXISTS idx_ai_quick_prompts_sort 
ON ai_quick_prompts(sort_order);

-- NOT: RLS zaten ai_quick_prompts için tanımlı olmalı
-- Eğer yoksa ekleyin:
-- ALTER TABLE ai_quick_prompts ENABLE ROW LEVEL SECURITY;

-- Yeni admin yetkisi ekle (güncelleme için)
-- INSERT POLICY için mevcut policy kontrol edilmeli
