-- =====================================================
-- POST REPORTS TABLE FOR APPLE GUIDELINE 1.2 COMPLIANCE
-- User-Generated Content Safety Requirements
-- =====================================================

-- Create post_reports table
CREATE TABLE IF NOT EXISTS post_reports (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    reporter_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
    reported_post_id UUID NOT NULL REFERENCES posts(id) ON DELETE CASCADE,
    reason TEXT NOT NULL,
    description TEXT,
    status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'reviewing', 'resolved', 'rejected')),
    admin_response TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    
    -- Prevent duplicate reports from same user for same post
    UNIQUE(reporter_id, reported_post_id)
);

-- Add comments
COMMENT ON TABLE post_reports IS 'User reports for posts - Apple App Store UGC compliance';
COMMENT ON COLUMN post_reports.reason IS 'Report reason: inappropriate, spam, harassment, misinformation, violence, other';

-- Create indexes
CREATE INDEX IF NOT EXISTS idx_post_reports_status ON post_reports(status);
CREATE INDEX IF NOT EXISTS idx_post_reports_post ON post_reports(reported_post_id);
CREATE INDEX IF NOT EXISTS idx_post_reports_reporter ON post_reports(reporter_id);

-- Enable Row Level Security
ALTER TABLE post_reports ENABLE ROW LEVEL SECURITY;

-- Policies
CREATE POLICY "post_reports_insert" ON post_reports
    FOR INSERT WITH CHECK (auth.uid() = reporter_id);

CREATE POLICY "post_reports_select_own" ON post_reports
    FOR SELECT USING (auth.uid() = reporter_id);

CREATE POLICY "post_reports_select_admin" ON post_reports
    FOR SELECT USING (
        EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND is_admin = true)
    );

CREATE POLICY "post_reports_update_admin" ON post_reports
    FOR UPDATE USING (
        EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND is_admin = true)
    );

CREATE POLICY "post_reports_delete_admin" ON post_reports
    FOR DELETE USING (
        EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND is_admin = true)
    );

-- Enable realtime
ALTER TABLE post_reports ENABLE ROW LEVEL SECURITY;
ALTER PUBLICATION supabase_realtime ADD TABLE post_reports;

-- Grant permissions
GRANT SELECT ON post_reports TO authenticated;
GRANT SELECT ON post_reports TO anon;
GRANT INSERT ON post_reports TO authenticated;
GRANT UPDATE ON post_reports TO authenticated;
GRANT DELETE ON post_reports TO authenticated;
