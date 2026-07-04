-- ============================================================================
-- MAINTENANCE: 20260703_CHAT_UNREAD_RECOUNT.sql
-- -----------------------------------------------------------------------------
-- AMAC: Eski buggy trigger (çift yönetim) yüzünden bozulmuş
--   conversations.unread_count değerlerini GERÇEK okunmamış mesaj sayısına
--   eşitler.
--
-- DOĞRU TANIM: Bir conversation'ın unread_count'u = o conv'daki, SAHİBİNİN
--   GÖNDERMEDİĞİ (sender_id != conversations.user_id) ve okunmamış (is_read=false)
--   ve o kullanıcı için silinmemiş mesajların sayısı.
--
-- GÜVENLİK: Önce teşhis SELECT'i (mevcut vs doğru) çalıştırılıp fark görülebilir.
--   Sonra UPDATE çalıştırılır. 20260703_CHAT_UNREAD_BADGE_FIX.sql ÇALIŞTIRILDIKTAN
--   SONRA bir kez çalıştırılmalı (yeni mesajlar zaten doğru sayılacak).
-- ============================================================================

-- 1) TEŞHİS: fark olan conversation'lar (önce bunu çalıştır)
WITH correct AS (
  SELECT c.id,
         c.unread_count AS mevcut,
         COUNT(m.id) FILTER (
           WHERE m.sender_id <> c.user_id
             AND m.is_read = FALSE
             AND m.deleted_for_user_id IS NULL
         ) AS dogru
  FROM conversations c
  LEFT JOIN messages m ON m.conversation_id = c.id
  GROUP BY c.id, c.unread_count
)
SELECT * FROM correct WHERE mevcut IS DISTINCT FROM dogru ORDER BY ABS(COALESCE(mevcut,0) - dogru) DESC LIMIT 100;

-- 2) DÜZELTME: unread_count'u gerçek değere eşitle
UPDATE conversations c
SET unread_count = sub.dogru,
    updated_at = NOW()
FROM (
  SELECT c2.id,
         COUNT(m.id) FILTER (
           WHERE m.sender_id <> c2.user_id
             AND m.is_read = FALSE
             AND m.deleted_for_user_id IS NULL
         ) AS dogru
  FROM conversations c2
  LEFT JOIN messages m ON m.conversation_id = c2.id
  GROUP BY c2.id
) sub
WHERE c.id = sub.id
  AND c.unread_count IS DISTINCT FROM sub.dogru;
