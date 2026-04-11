-- Optimize edilmiş like durumu sorgulama
-- Tek sorguda kullanıcının tüm beğenilerini çek

CREATE OR REPLACE FUNCTION get_user_liked_posts(p_user_id UUID, p_post_ids UUID[])
RETURNS TABLE (post_id UUID) AS $$
BEGIN
  RETURN QUERY
  SELECT DISTINCT pl.post_id
  FROM post_likes pl
  WHERE pl.user_id = p_user_id 
    AND pl.post_id = ANY(p_post_ids);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Grant execute permission
GRANT EXECUTE ON FUNCTION get_user_liked_posts(UUID, UUID[]) TO authenticated;
