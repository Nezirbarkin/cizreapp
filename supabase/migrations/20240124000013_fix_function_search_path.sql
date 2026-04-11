-- Fix search_path security warnings for all functions
-- This migration adds SET search_path = '' to all functions that were flagged

-- Fix: get_product_favorite_count
CREATE OR REPLACE FUNCTION get_product_favorite_count(p_product_id UUID)
RETURNS INTEGER
SET search_path = ''
SECURITY DEFINER
AS $$
BEGIN
    RETURN (
        SELECT COUNT(*)
        FROM product_favorites
        WHERE product_id = p_product_id
    );
END;
$$ LANGUAGE plpgsql;

-- Fix: is_product_favorited
CREATE OR REPLACE FUNCTION is_product_favorited(p_user_id UUID, p_product_id UUID)
RETURNS BOOLEAN
SET search_path = ''
SECURITY DEFINER
AS $$
BEGIN
    RETURN EXISTS (
        SELECT 1
        FROM product_favorites
        WHERE user_id = p_user_id AND product_id = p_product_id
    );
END;
$$ LANGUAGE plpgsql;

-- Fix: toggle_product_favorite
CREATE OR REPLACE FUNCTION toggle_product_favorite(p_user_id UUID, p_product_id UUID)
RETURNS BOOLEAN
SET search_path = ''
SECURITY DEFINER
AS $$
DECLARE
    v_is_favorited BOOLEAN;
BEGIN
    -- Check if already favorited
    SELECT EXISTS (
        SELECT 1
        FROM product_favorites
        WHERE user_id = p_user_id AND product_id = p_product_id
    ) INTO v_is_favorited;

    IF v_is_favorited THEN
        -- Remove from favorites
        DELETE FROM product_favorites
        WHERE user_id = p_user_id AND product_id = p_product_id;
        RETURN FALSE;
    ELSE
        -- Add to favorites
        INSERT INTO product_favorites (user_id, product_id)
        VALUES (p_user_id, p_product_id);
        RETURN TRUE;
    END IF;
END;
$$ LANGUAGE plpgsql;

-- Fix: get_post_favorite_count
CREATE OR REPLACE FUNCTION get_post_favorite_count(p_post_id UUID)
RETURNS INTEGER
SET search_path = ''
SECURITY DEFINER
AS $$
BEGIN
    RETURN (
        SELECT COUNT(*)
        FROM post_favorites
        WHERE post_id = p_post_id
    );
END;
$$ LANGUAGE plpgsql;

-- Fix: is_post_favorited
CREATE OR REPLACE FUNCTION is_post_favorited(p_user_id UUID, p_post_id UUID)
RETURNS BOOLEAN
SET search_path = ''
SECURITY DEFINER
AS $$
BEGIN
    RETURN EXISTS (
        SELECT 1
        FROM post_favorites
        WHERE user_id = p_user_id AND post_id = p_post_id
    );
END;
$$ LANGUAGE plpgsql;

-- Fix: toggle_post_favorite
CREATE OR REPLACE FUNCTION toggle_post_favorite(p_user_id UUID, p_post_id UUID)
RETURNS BOOLEAN
SET search_path = ''
SECURITY DEFINER
AS $$
DECLARE
    v_is_favorited BOOLEAN;
BEGIN
    -- Check if already favorited
    SELECT EXISTS (
        SELECT 1
        FROM post_favorites
        WHERE user_id = p_user_id AND post_id = p_post_id
    ) INTO v_is_favorited;

    IF v_is_favorited THEN
        -- Remove from favorites
        DELETE FROM post_favorites
        WHERE user_id = p_user_id AND post_id = p_post_id;
        RETURN FALSE;
    ELSE
        -- Add to favorites
        INSERT INTO post_favorites (user_id, post_id)
        VALUES (p_user_id, p_post_id);
        RETURN TRUE;
    END IF;
END;
$$ LANGUAGE plpgsql;

-- Fix: increment_story_likes
CREATE OR REPLACE FUNCTION increment_story_likes(story_id UUID)
RETURNS VOID
SET search_path = ''
SECURITY DEFINER
AS $$
BEGIN
    UPDATE public.stories 
    SET likes_count = likes_count + 1
    WHERE id = story_id;
END;
$$ LANGUAGE plpgsql;

-- Fix: decrement_story_likes
CREATE OR REPLACE FUNCTION decrement_story_likes(story_id UUID)
RETURNS VOID
SET search_path = ''
SECURITY DEFINER
AS $$
BEGIN
    UPDATE public.stories 
    SET likes_count = GREATEST(0, likes_count - 1)
    WHERE id = story_id;
END;
$$ LANGUAGE plpgsql;

-- Fix: get_user_liked_posts
DROP FUNCTION IF EXISTS get_user_liked_posts(UUID);

CREATE OR REPLACE FUNCTION get_user_liked_posts(p_user_id UUID)
RETURNS SETOF UUID
SET search_path = ''
SECURITY DEFINER
AS $$
BEGIN
    RETURN QUERY
    SELECT pf.post_id
    FROM post_favorites pf
    WHERE pf.user_id = p_user_id
    ORDER BY pf.created_at DESC;
END;
$$ LANGUAGE plpgsql;

-- Re-grant permissions
GRANT EXECUTE ON FUNCTION get_product_favorite_count(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION is_product_favorited(UUID, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION toggle_product_favorite(UUID, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION get_post_favorite_count(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION is_post_favorited(UUID, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION toggle_post_favorite(UUID, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION increment_story_likes(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION decrement_story_likes(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION get_user_liked_posts(UUID) TO authenticated;
