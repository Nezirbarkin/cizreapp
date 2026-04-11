-- Fix posts table RLS policies for admin users
-- Allow admins to delete any post

-- Drop existing admin policies if they exist
DROP POLICY IF EXISTS "posts_select_admin_policy" ON public.posts;
DROP POLICY IF EXISTS "posts_update_admin_policy" ON public.posts;
DROP POLICY IF EXISTS "posts_delete_admin_policy" ON public.posts;

-- Create admin SELECT policy - admins can view all posts
CREATE POLICY "posts_select_admin_policy" ON public.posts
    FOR SELECT
    USING (EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND is_admin = true));

-- Create admin UPDATE policy - admins can update any post
CREATE POLICY "posts_update_admin_policy" ON public.posts
    FOR UPDATE
    USING (EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND is_admin = true));

-- Create admin DELETE policy - admins can delete any post
CREATE POLICY "posts_delete_admin_policy" ON public.posts
    FOR DELETE
    USING (EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND is_admin = true));
