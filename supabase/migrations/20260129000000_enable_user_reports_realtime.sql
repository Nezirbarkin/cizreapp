-- Enable Realtime for user_reports table
-- This allows admin dashboard to listen for new complaints and updates

-- Alter publication to include user_reports table
ALTER PUBLICATION supabase_realtime ADD TABLE user_reports;

-- Grant necessary permissions for realtime
GRANT SELECT ON user_reports TO authenticated;
GRANT SELECT ON user_reports TO anon;

-- Note: RLS policies will still apply, so only admins can see the reports
-- Realtime will only send updates that pass RLS policies
