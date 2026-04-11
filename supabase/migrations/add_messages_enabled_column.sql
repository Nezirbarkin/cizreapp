-- Add messages_enabled column to profiles table
-- This column controls whether a user can receive messages

-- Add the column if it doesn't exist
ALTER TABLE profiles 
ADD COLUMN IF NOT EXISTS messages_enabled BOOLEAN DEFAULT true;

-- Add comment for documentation
COMMENT ON COLUMN profiles.messages_enabled IS 'Controls whether the user can receive direct messages from other users';
