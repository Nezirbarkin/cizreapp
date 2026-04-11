-- Story likes tablosu oluştur
CREATE TABLE IF NOT EXISTS story_likes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    story_id UUID NOT NULL REFERENCES stories(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    UNIQUE(story_id, user_id)
);

-- Index for faster queries
CREATE INDEX IF NOT EXISTS idx_story_likes_story_id ON story_likes(story_id);
CREATE INDEX IF NOT EXISTS idx_story_likes_user_id ON story_likes(user_id);

-- Enable RLS
ALTER TABLE story_likes ENABLE ROW LEVEL SECURITY;

-- RLS Policies
CREATE POLICY "Users can view all story likes"
    ON story_likes FOR SELECT
    USING (true);

CREATE POLICY "Users can insert their own story likes"
    ON story_likes FOR INSERT
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can delete their own story likes"
    ON story_likes FOR DELETE
    USING (auth.uid() = user_id);

-- Update stories table to include likes_count
ALTER TABLE stories ADD COLUMN IF NOT EXISTS likes_count INTEGER DEFAULT 0;

-- RPC function to increment likes count
CREATE OR REPLACE FUNCTION increment_story_likes(story_id UUID)
RETURNS VOID AS $$
BEGIN
    UPDATE stories 
    SET likes_count = likes_count + 1
    WHERE id = story_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- RPC function to decrement likes count
CREATE OR REPLACE FUNCTION decrement_story_likes(story_id UUID)
RETURNS VOID AS $$
BEGIN
    UPDATE stories 
    SET likes_count = GREATEST(0, likes_count - 1)
    WHERE id = story_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Grant execute permissions
GRANT EXECUTE ON FUNCTION increment_story_likes(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION decrement_story_likes(UUID) TO authenticated;
