-- ============================================================================
-- MAINTENANCE: 20260703_CHAT_DEDUP_CLEANUP.sql
-- -----------------------------------------------------------------------------
-- AMAC: Eski buggy surumlerin (fallback INSERT / cift RPC cagrisi) AYNI
--   conversation icinde olusturdugu GERCEK cift mesaj satirlarini temizler.
--
-- ONEMLI: Mailbox modelinde her mantiksal mesajin İKİ conversation'da (gonderen
--   + alici) birer kopyasi olmasi NORMALDIR ve silinmemelidir. Bu script SADECE
--   AYNI conversation_id icinde birebir ayni (sender_id, content, created_at)
--   olan fazladan satirlari siler; her grup icin en dusuk id'li satiri korur.
--   Boylece conversation'lar arasi mesbru mailbox kopyalarina DOKUNMAZ.
--
-- GUVENLIK: Once teshis SELECT'ini calistirip kac satir silinecegini gorun,
--   sonra DELETE'i calistirin. Islemler transaction icinde.
-- -----------------------------------------------------------------------------

-- 1) TESHIS: Silinecek fazladan satir sayisi (once bunu calistirin)
WITH ranked AS (
    SELECT
        id,
        ROW_NUMBER() OVER (
            PARTITION BY conversation_id, sender_id, content, created_at
            ORDER BY id
        ) AS rn
    FROM public.messages
)
SELECT COUNT(*) AS silinecek_fazladan_satir
FROM ranked
WHERE rn > 1;

-- 1b) DETAYLI TESHIS: Cift kayitlar hangi conversation'larda yogunlasmis?
--     (En cok fazladan satiri olan ilk 50 conversation)
WITH ranked AS (
    SELECT
        id,
        conversation_id,
        sender_id,
        content,
        created_at,
        ROW_NUMBER() OVER (
            PARTITION BY conversation_id, sender_id, content, created_at
            ORDER BY id
        ) AS rn
    FROM public.messages
)
SELECT
    conversation_id,
    COUNT(*) AS fazladan_satir,
    COUNT(DISTINCT (sender_id, content, created_at)) AS etkilenen_mesaj,
    MIN(created_at) AS en_eski,
    MAX(created_at) AS en_yeni
FROM ranked
WHERE rn > 1
GROUP BY conversation_id
ORDER BY fazladan_satir DESC
LIMIT 50;

-- 2) TEMIZLIK: Fazladan satirlari sil (en dusuk id korunur)
BEGIN;

WITH ranked AS (
    SELECT
        id,
        ROW_NUMBER() OVER (
            PARTITION BY conversation_id, sender_id, content, created_at
            ORDER BY id
        ) AS rn
    FROM public.messages
)
DELETE FROM public.messages m
USING ranked r
WHERE m.id = r.id
  AND r.rn > 1;

-- 3) Konusma ozetlerini son gercek mesaja gore tazele
UPDATE public.conversations c
SET
    last_message = lm.content,
    last_message_time = lm.created_at
FROM (
    SELECT DISTINCT ON (conversation_id)
        conversation_id, content, created_at
    FROM public.messages
    WHERE deleted_for_user_id IS NULL
    ORDER BY conversation_id, created_at DESC
) lm
WHERE c.id = lm.conversation_id;

COMMIT;

-- 4) (OPSIYONEL) Gelecekte ayni-conversation cift kaydi engelleyen unique index.
--    Eski kopyalar temizlendikten SONRA acmak guvenlidir. Mailbox modelini
--    bozmaz cunku iki kopya farkli conversation_id'de durur.
-- CREATE UNIQUE INDEX IF NOT EXISTS uniq_message_per_conversation
--     ON public.messages (conversation_id, sender_id, content, created_at);
