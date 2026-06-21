-- =====================================================
-- AI HIZLI ŞABLONLAR TABLOSU
-- Admin panelden yönetilebilir şablonlar
-- =====================================================

-- 1. Tablo oluştur
CREATE TABLE IF NOT EXISTS public.ai_quick_prompts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    title TEXT NOT NULL,
    prompt TEXT NOT NULL,
    icon TEXT DEFAULT 'lightbulb_outline',
    color TEXT DEFAULT '#FFC107',
    sort_order INT NOT NULL DEFAULT 0,
    is_active BOOLEAN NOT NULL DEFAULT true,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 2. updated_at trigger
CREATE OR REPLACE FUNCTION public.ai_quick_prompts_set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_ai_quick_prompts_updated ON public.ai_quick_prompts;
CREATE TRIGGER trg_ai_quick_prompts_updated
    BEFORE UPDATE ON public.ai_quick_prompts
    FOR EACH ROW
    EXECUTE FUNCTION public.ai_quick_prompts_set_updated_at();

-- 3. RLS politikaları
ALTER TABLE public.ai_quick_prompts ENABLE ROW LEVEL SECURITY;

-- Herkes okuyabilir (chat ekranında gösterilecek)
DROP POLICY IF EXISTS "ai_quick_prompts_read" ON public.ai_quick_prompts;
CREATE POLICY "ai_quick_prompts_read" ON public.ai_quick_prompts
    FOR SELECT USING (is_active = true);

-- Sadece admin ekleme yapabilir
DROP POLICY IF EXISTS "ai_quick_prompts_admin_insert" ON public.ai_quick_prompts;
CREATE POLICY "ai_quick_prompts_admin_insert" ON public.ai_quick_prompts
    FOR INSERT TO authenticated
    WITH CHECK (EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role = 'admin'));

-- Sadece admin güncelleme yapabilir
DROP POLICY IF EXISTS "ai_quick_prompts_admin_update" ON public.ai_quick_prompts;
CREATE POLICY "ai_quick_prompts_admin_update" ON public.ai_quick_prompts
    FOR UPDATE TO authenticated
    USING (EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role = 'admin'))
    WITH CHECK (EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role = 'admin'));

-- Sadece admin silebilir
DROP POLICY IF EXISTS "ai_quick_prompts_admin_delete" ON public.ai_quick_prompts;
CREATE POLICY "ai_quick_prompts_admin_delete" ON public.ai_quick_prompts
    FOR DELETE TO authenticated
    USING (EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role = 'admin'));

-- 4. İzinler
GRANT SELECT ON public.ai_quick_prompts TO authenticated, anon, service_role;
GRANT ALL ON public.ai_quick_prompts TO authenticated, service_role;

-- 5. Varsayılan şablonları ekle (yoksa)
INSERT INTO public.ai_quick_prompts (title, prompt, icon, color, sort_order)
SELECT 'Alışveriş Listesi', 'Bana bir alışveriş listesi öner', 'shopping_cart', '#6C5CE7', 1
WHERE NOT EXISTS (SELECT 1 FROM public.ai_quick_prompts WHERE title = 'Alışveriş Listesi');

INSERT INTO public.ai_quick_prompts (title, prompt, icon, color, sort_order)
SELECT 'Akşam Yemeği Tarifi', 'Bir akşam yemeği tarifi yaz', 'restaurant', '#00CEC9', 2
WHERE NOT EXISTS (SELECT 1 FROM public.ai_quick_prompts WHERE title = 'Akşam Yemeği Tarifi');

INSERT INTO public.ai_quick_prompts (title, prompt, icon, color, sort_order)
SELECT 'Hafta Sonu Önerisi', 'Bu hafta sonu ne yapabilirim?', 'weekend', '#FD79A8', 3
WHERE NOT EXISTS (SELECT 1 FROM public.ai_quick_prompts WHERE title = 'Hafta Sonu Önerisi');

INSERT INTO public.ai_quick_prompts (title, prompt, icon, color, sort_order)
SELECT 'Şiir Yaz', 'Benim için güzel bir şiir yaz', 'edit', '#FDCB6E', 4
WHERE NOT EXISTS (SELECT 1 FROM public.ai_quick_prompts WHERE title = 'Şiir Yaz');

INSERT INTO public.ai_quick_prompts (title, prompt, icon, color, sort_order)
SELECT 'Hikaye Anlat', 'Benim için kısa bir hikaye anlat', 'auto_stories', '#74B9FF', 5
WHERE NOT EXISTS (SELECT 1 FROM public.ai_quick_prompts WHERE title = 'Hikaye Anlat');

INSERT INTO public.ai_quick_prompts (title, prompt, icon, color, sort_order)
SELECT 'Günlük Plan', 'Bugünüm için bir plan oluştur', 'today', '#A29BFE', 6
WHERE NOT EXISTS (SELECT 1 FROM public.ai_quick_prompts WHERE title = 'Günlük Plan');

-- 6. Edge Function'ın erişmesi için service_role yetkisi
GRANT USAGE ON SCHEMA public TO service_role;
GRANT SELECT ON public.ai_quick_prompts TO service_role;
