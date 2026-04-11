-- Fix auth_rls_initplan performance warnings
-- Replace auth.uid() with (select auth.uid()) in RLS policies for better performance

-- Drop and recreate product_favorites policies
DROP POLICY IF EXISTS "Users can view their own product favorites" ON product_favorites;
DROP POLICY IF EXISTS "Users can insert their own product favorites" ON product_favorites;
DROP POLICY IF EXISTS "Users can delete their own product favorites" ON product_favorites;

CREATE POLICY "Users can view their own product favorites"
    ON product_favorites FOR SELECT
    USING (user_id = (select auth.uid()));

CREATE POLICY "Users can insert their own product favorites"
    ON product_favorites FOR INSERT
    WITH CHECK (user_id = (select auth.uid()));

CREATE POLICY "Users can delete their own product favorites"
    ON product_favorites FOR DELETE
    USING (user_id = (select auth.uid()));

-- Drop and recreate post_favorites policies
DROP POLICY IF EXISTS "Users can view their own post favorites" ON post_favorites;
DROP POLICY IF EXISTS "Users can insert their own post favorites" ON post_favorites;
DROP POLICY IF EXISTS "Users can delete their own post favorites" ON post_favorites;

CREATE POLICY "Users can view their own post favorites"
    ON post_favorites FOR SELECT
    USING (user_id = (select auth.uid()));

CREATE POLICY "Users can insert their own post favorites"
    ON post_favorites FOR INSERT
    WITH CHECK (user_id = (select auth.uid()));

CREATE POLICY "Users can delete their own post favorites"
    ON post_favorites FOR DELETE
    USING (user_id = (select auth.uid()));

-- Drop and recreate story_likes policies
DROP POLICY IF EXISTS "Users can view all story likes" ON story_likes;
DROP POLICY IF EXISTS "Users can insert their own story likes" ON story_likes;
DROP POLICY IF EXISTS "Users can delete their own story likes" ON story_likes;

CREATE POLICY "Users can view all story likes"
    ON story_likes FOR SELECT
    USING (true);

CREATE POLICY "Users can insert their own story likes"
    ON story_likes FOR INSERT
    WITH CHECK (user_id = (select auth.uid()));

CREATE POLICY "Users can delete their own story likes"
    ON story_likes FOR DELETE
    USING (user_id = (select auth.uid()));

-- Drop and recreate coupons policies (if they exist)
-- Note: Skipped because coupons table doesn't have user_id column
-- Coupons policies need to be checked and fixed separately based on actual table structure
