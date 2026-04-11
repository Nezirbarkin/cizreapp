-- Fix performance issues in story_views table
-- Merge multiple SELECT policies into one to improve performance

-- Drop all old policies
DROP POLICY IF EXISTS "select_own_views" ON public.story_views;
DROP POLICY IF EXISTS "insert_own_views" ON public.story_views;
DROP POLICY IF EXISTS "select_story_owner_views" ON public.story_views;
DROP POLICY IF EXISTS "story_views_select_policy" ON public.story_views;
DROP POLICY IF EXISTS "story_views_insert_policy" ON public.story_views;

-- Create consolidated SELECT policy (combines own views + story owner views)
CREATE POLICY "story_views_select_policy"
    ON public.story_views FOR SELECT
    USING (
        viewer_id = (select auth.uid())
        OR EXISTS (
            SELECT 1 FROM public.stories
            WHERE stories.id = story_views.story_id
            AND stories.user_id = (select auth.uid())
        )
    );

-- Create INSERT policy
CREATE POLICY "story_views_insert_policy"
    ON public.story_views FOR INSERT
    WITH CHECK (viewer_id = (select auth.uid()));
