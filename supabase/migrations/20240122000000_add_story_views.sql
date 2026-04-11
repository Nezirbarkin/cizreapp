-- Story views tablosu oluştur
CREATE TABLE IF NOT EXISTS public.story_views (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    story_id UUID NOT NULL,
    viewer_id UUID NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(story_id, viewer_id)
);

-- Performans indexleri
CREATE INDEX IF NOT EXISTS idx_story_views_story_id ON public.story_views(story_id);
CREATE INDEX IF NOT EXISTS idx_story_views_viewer_id ON public.story_views(viewer_id);
CREATE INDEX IF NOT EXISTS idx_story_views_created_at ON public.story_views(created_at DESC);

-- RLS etkinleştir
ALTER TABLE public.story_views ENABLE ROW LEVEL SECURITY;

-- Politika: Kullanıcılar kendi görüntüleme kayıtlarını görebilir
DROP POLICY IF EXISTS "select_own_views" ON public.story_views;
CREATE POLICY "select_own_views" ON public.story_views
    FOR SELECT USING (viewer_id = (select auth.uid()));

-- Politika: Kullanıcılar kendi görüntüleme kaydını ekleyebilir
DROP POLICY IF EXISTS "insert_own_views" ON public.story_views;
CREATE POLICY "insert_own_views" ON public.story_views
    FOR INSERT WITH CHECK (viewer_id = (select auth.uid()));

-- Politika: Story sahibi görüntüleyenleri görebilir
DROP POLICY IF EXISTS "select_story_owner_views" ON public.story_views;
CREATE POLICY "select_story_owner_views" ON public.story_views
    FOR SELECT USING (
        EXISTS (
            SELECT 1 FROM public.stories
            WHERE stories.id = story_views.story_id
            AND stories.user_id = (select auth.uid())
        )
    );

-- Trigger fonksiyonu
DROP FUNCTION IF EXISTS public.increment_story_views_count() CASCADE;
CREATE FUNCTION public.increment_story_views_count()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    UPDATE public.stories
    SET views_count = COALESCE(views_count, 0) + 1
    WHERE id = NEW.story_id;
    RETURN NEW;
END;
$$;

-- Trigger
DROP TRIGGER IF EXISTS trigger_increment_story_views_count ON public.story_views;
CREATE TRIGGER trigger_increment_story_views_count
    AFTER INSERT ON public.story_views
    FOR EACH ROW
    EXECUTE FUNCTION public.increment_story_views_count();
