-- ============================================================================
-- 20260709_NOTIFICATION_FIX.sql
-- ----------------------------------------------------------------------------
-- 3 bildirim sorununu çözer. PARÇA PARÇA çalıştırılabilir (her bölüm bağımsız).
--
-- SORU 1 & 2 (sohbet kartı + yüzen mesaj ikonu rozeti yok):
--   KÖK NEDEN: message_replicate_to_recipient trigger'ı (eski "tek kopya +
--   trigger çoğaltması" modeli) HALEN aktif. send_message_with_recipient RPC'si
--   (yeni mailbox modeli) zaten her mantıksal mesajı İKİ satır olarak ekliyor
--   (gönderen conv'u is_read=TRUE + alıcı conv'u is_read=FALSE). Eski trigger
--   ise gönderenin is_read=TRUE kopyasını alıcı conv'una DAHA kopyalıyor ->
--   alıcının conv'unda mesaj is_read=TRUE olarak duruyor -> unread_count 0
--   kalıyor -> sohbet kartı + yüzen ikon rozeti görünmüyor.
--
--   ÇÖZÜM: Eski replicate trigger'ını + fonksiyonunu KALDIR (RPC tek yetkili
--   kaynak). Ardından conversations.unread_count'u GERÇEK okunmamış mesaj
--   sayısına göre yeniden hesapla.
--
-- SORU 3 (admin bildirimleri kullanıcının Bildirimler ekranında görünmüyor):
--   KÖK NEDEN: admin_broadcasts tablosu HİÇ OLUŞTURULMAMAMIŞ. frontend
--   (notifications_screen.dart + notifications_content_v2.dart) toplu
--   duyuruları bu tablodan okumaya çalışıyor -> boş kalıyor.
--
--   ÇÖZÜM: admin_broadcasts tablosunu + RLS + policy kur (ADD_ADMIN_BROADCASTS_TABLE.sql
--   içeriği idempotent olarak).
--
-- GÜVENLİK: Bu migration veri SİLMEZ (sadece eski trigger/fonksiyon drop +
--   unread_count UPDATE + yeni tablo create). Mevcut mesajlar korunur.
--
-- NOT: Dosya PARÇA PARÇA çalıştırılır. Her bölüm ayrı transaction'dır.
-- ============================================================================


-- ============================================================================
-- BÖLÜM A -- SORU 1 & 2: Çift mesaj kopyalama çakışmasını gider
-- ============================================================================

BEGIN;

-- A.1) Eski çoğaltma trigger'ını kaldır (RPC zaten iki kopya ekliyor)
DROP TRIGGER IF EXISTS message_replicate_to_recipient ON public.messages;

-- A.2) Eski çoğaltma fonksiyonunu kaldır (artık çağrılmıyor)
DROP FUNCTION IF EXISTS public.replicate_message_to_recipient();

-- A.3) update_conversation_on_message trigger'ı + fonksiyonu zaten doğru
--   (20260703_CHAT_UNREAD_BADGE_FIX.sql). Dokunmuyoruz; sadece teyit:
DO $$
DECLARE
    v_fn_exists BOOLEAN;
    v_trg_exists BOOLEAN;
BEGIN
    SELECT EXISTS(
        SELECT 1 FROM pg_proc p
        JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE p.proname = 'update_conversation_on_message' AND n.nspname='public'
    ) INTO v_fn_exists;
    SELECT EXISTS(
        SELECT 1 FROM pg_trigger t
        JOIN pg_class c ON c.oid = t.tgrelid
        WHERE c.relname = 'messages' AND t.tgname = 'message_insert_trigger'
          AND NOT t.tgisinternal
    ) INTO v_trg_exists;
    IF NOT v_fn_exists THEN
        RAISE EXCEPTION 'update_conversation_on_message FONKSIYONU YOK - once 20260703_CHAT_UNREAD_BADGE_FIX.sql calistirilmali';
    END IF;
    IF NOT v_trg_exists THEN
        RAISE EXCEPTION 'message_insert_trigger YOK - once 20260703_CHAT_UNREAD_BADGE_FIX.sql calistirilmali';
    END IF;
    RAISE NOTICE 'A.3 OK: update_conversation_on_message + message_insert_trigger aktif';
END $$;

-- A.4) conversations.unread_count'u GERÇEK okunmamış mesaj sayısına göre yeniden hesapla.
--   Mailbox modeli: unread = alıcının conv'unda sender_id != user_id AND is_read=false.
UPDATE conversations c
SET unread_count = subq.gercek_unread
FROM (
    SELECT
        m.conversation_id,
        COUNT(*) AS gercek_unread
    FROM messages m
    JOIN conversations cv ON cv.id = m.conversation_id
    WHERE m.sender_id <> cv.user_id          -- mesaj KARŞIDAN geldi (sahip alıcı)
      AND COALESCE(m.is_read, false) = false -- okunmamış
      AND m.deleted_for_user_id IS NULL       -- soft-delete edilmemiş (genel)
    GROUP BY m.conversation_id
) subq
WHERE c.id = subq.conversation_id
  AND COALESCE(c.unread_count, 0) <> subq.gercek_unread;

DO $$ BEGIN
    RAISE NOTICE 'A.4 OK: unread_count yeniden hesaplandı';
END $$;

-- A.5) NOT: replicate trigger kaldırıldıktan sonra YENI mesajlar doğru akacak.
--   Geçmiş mesajlarda bazı alıcı kopyaları is_read=TRUE olabilir (eski trigger
--   hatası). Bu migration eski mesajları değiştirmez; yalnızca unread_count
--   sayacını düzeltir. Geçmiş mesajlar görünür kalır.

COMMIT;


-- ============================================================================
-- BÖLÜM B -- SORU 3: admin_broadcasts tablosunu kur
-- ============================================================================

BEGIN;

-- B.1) Tablo
CREATE TABLE IF NOT EXISTS public.admin_broadcasts (
    id              UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    title           TEXT NOT NULL,
    content         TEXT NOT NULL,
    icon_type       TEXT NOT NULL DEFAULT 'announcement',
    target_audience TEXT DEFAULT 'all',
    is_active       BOOLEAN DEFAULT TRUE,
    created_by      UUID REFERENCES auth.users(id),
    created_at      TIMESTAMPTZ DEFAULT NOW(),
    expires_at      TIMESTAMPTZ
);

-- B.2) Index
CREATE INDEX IF NOT EXISTS admin_broadcasts_active_idx
    ON public.admin_broadcasts(is_active, created_at DESC)
    WHERE is_active = TRUE;

-- B.3) RLS
ALTER TABLE public.admin_broadcasts ENABLE ROW LEVEL SECURITY;

-- B.4) Policy: aktif broadcast'leri her authenticated kullanıcı okuyabilir
DO $$ BEGIN
    CREATE POLICY "Anyone can read active broadcasts"
    ON public.admin_broadcasts
    FOR SELECT
    TO authenticated
    USING (is_active = TRUE);
EXCEPTION WHEN duplicate_object THEN
    RAISE NOTICE 'read policy zaten mevcut';
END $$;

-- B.5) Policy: sadece admin insert
DO $$ BEGIN
    CREATE POLICY "Admins can insert broadcasts"
    ON public.admin_broadcasts
    FOR INSERT
    TO authenticated
    WITH CHECK (
        EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role = 'admin')
    );
EXCEPTION WHEN duplicate_object THEN
    RAISE NOTICE 'insert policy zaten mevcut';
END $$;

-- B.6) Policy: sadece admin update
DO $$ BEGIN
    CREATE POLICY "Admins can update broadcasts"
    ON public.admin_broadcasts
    FOR UPDATE
    TO authenticated
    USING (EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role = 'admin'))
    WITH CHECK (EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role = 'admin'));
EXCEPTION WHEN duplicate_object THEN
    RAISE NOTICE 'update policy zaten mevcut';
END $$;

-- B.7) Policy: sadece admin delete
DO $$ BEGIN
    CREATE POLICY "Admins can delete broadcasts"
    ON public.admin_broadcasts
    FOR DELETE
    TO authenticated
    USING (EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role = 'admin'));
EXCEPTION WHEN duplicate_object THEN
    RAISE NOTICE 'delete policy zaten mevcut';
END $$;

COMMENT ON TABLE public.admin_broadcasts IS 'Admin tarafından gönderilen duyurular (toplu). Kişiye özel admin bildirimleri notifications tablosunda kalır.';
COMMENT ON COLUMN public.admin_broadcasts.icon_type IS 'announcement|discount|campaign|news|event|update|warning|gift|info';

COMMIT;


-- ============================================================================
-- BÖLÜM C -- (OPSİYONEL) Eski message tipi notifications temizliği
-- ============================================================================
-- Frontend zaten message/chat tiplerini filtreliyor (notification_service.dart:47,95).
-- 604 eski message-tipi bildirim DB'yi şişiriyor. İsteğe bağlı temizlik:
--   BEGIN; DELETE FROM notifications WHERE type IN ('message','chat'); COMMIT;
-- (Varsayılan: çalıştırılmaz. İsterseniz yorumsuz satırı çalıştırın.)


-- ============================================================================
-- DOĞRULAMA (migration sonrası çalıştır -- bu sorgular ayrı çalıştırılır)
-- ============================================================================

SELECT '1) Trigger durumu (message_replicate_to_recipient OLMAMALI)' AS bilgi;

SELECT tgname FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid
 WHERE c.relname='messages' AND NOT t.tgisinternal
 ORDER BY tgname;

SELECT '2) unread_count vs gercek okunmamis' AS bilgi;

SELECT id, user_id, unread_count,
       (SELECT COUNT(*) FROM messages m
          JOIN conversations cv ON cv.id=m.conversation_id
          WHERE m.conversation_id=c.id AND m.sender_id<>c.user_id
            AND COALESCE(m.is_read,false)=false) AS gercek
FROM conversations c ORDER BY updated_at DESC LIMIT 10;

SELECT '3) admin_broadcasts tablosu' AS bilgi;

SELECT COUNT(*) AS broadcast_sayisi FROM admin_broadcasts;