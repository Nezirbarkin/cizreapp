-- Add delete confirmation columns to profiles table
ALTER TABLE public.profiles
ADD COLUMN IF NOT EXISTS delete_confirmation_code TEXT,
ADD COLUMN IF NOT EXISTS delete_confirmation_expires_at TIMESTAMPTZ;

-- Add index for faster lookups
CREATE INDEX IF NOT EXISTS idx_profiles_delete_confirmation_code 
ON public.profiles(delete_confirmation_code) 
WHERE delete_confirmation_code IS NOT NULL;

-- Add comment
COMMENT ON COLUMN public.profiles.delete_confirmation_code IS 'Temporary 6-digit code for account deletion confirmation';
COMMENT ON COLUMN public.profiles.delete_confirmation_expires_at IS 'Expiration timestamp for delete confirmation code (15 minutes)';
