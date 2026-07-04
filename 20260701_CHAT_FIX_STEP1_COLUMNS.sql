ALTER TABLE public.conversations
    ADD COLUMN IF NOT EXISTS deleted_for_user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL;

ALTER TABLE public.messages
    ADD COLUMN IF NOT EXISTS deleted_for_user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_conversations_deleted_for_user_id
    ON public.conversations(deleted_for_user_id);

CREATE INDEX IF NOT EXISTS idx_messages_deleted_for_user_id
    ON public.messages(deleted_for_user_id);