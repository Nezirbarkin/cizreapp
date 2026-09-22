-- messages.conversation_id NOT NULL iken FK'si ON DELETE SET NULL idi.
-- Bir konuşma silindiğinde (ör. admin_delete_user -> profiles silinir ->
-- conversations cascade silinir) Postgres mesajların conversation_id'sini NULL'a
-- çekmeye çalışıp 23502 "null value in column conversation_id of relation
-- messages violates not-null constraint" ile patlıyordu. Konuşması olmayan mesaj
-- anlamsız olduğundan doğru davranış CASCADE'dir.

ALTER TABLE public.messages
  DROP CONSTRAINT IF EXISTS messages_conversation_id_fkey;

ALTER TABLE public.messages
  ADD CONSTRAINT messages_conversation_id_fkey
  FOREIGN KEY (conversation_id) REFERENCES public.conversations(id)
  ON DELETE CASCADE;
