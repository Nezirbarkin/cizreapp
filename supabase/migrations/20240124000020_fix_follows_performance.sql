-- Fix performance issues in follows table
-- 1. Fix auth_rls_initplan issues by using (select auth.uid())
-- 2. Remove duplicate policies

-- Drop old policies
DROP POLICY IF EXISTS "Follows are viewable by everyone" ON public.follows;
DROP POLICY IF EXISTS "Users can follow others" ON public.follows;
DROP POLICY IF EXISTS "Users can unfollow" ON public.follows;
DROP POLICY IF EXISTS "follows_select_policy" ON public.follows;
DROP POLICY IF EXISTS "follows_insert_policy" ON public.follows;
DROP POLICY IF EXISTS "follows_delete_policy" ON public.follows;

-- Create optimized policies with (select auth.uid()) to avoid re-evaluation per row
CREATE POLICY "follows_select_policy"
    ON public.follows FOR SELECT
    USING (true);

CREATE POLICY "follows_insert_policy"
    ON public.follows FOR INSERT
    WITH CHECK ((select auth.uid()) = follower_id);

CREATE POLICY "follows_delete_policy"
    ON public.follows FOR DELETE
    USING ((select auth.uid()) = follower_id);
