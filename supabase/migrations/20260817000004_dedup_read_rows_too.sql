-- ============================================================================
-- Tekrar eden eylemlerde bildirim çakışmasını düzelt (2026-08-14)
-- ----------------------------------------------------------------------------
-- SORUN: idx_notifications_user_entity_type tekil kısıtı (user_id, entity_id,
-- type WHERE entity_id IS NOT NULL) nedeniyle aynı (alıcı, gönderi, tip)
-- için ikinci bildirim satırı eklenemiyor. dedup_notification() BEFORE
-- INSERT ile eski OKUNMAMIŞ satırı silip yer açıyordu; satır okunmuşsa
-- (is_read = TRUE) silinmiyordu → INSERT 23505 veriyor → hatayı yutan
-- değil, bildirimi üreten trigger beğeni/yorum eyleminin KENDİ
-- transaction'ını geri alıyordu.
--
-- Senaryo: gönderiyi beğen → bildirim gider, alıcı okur → beğeniyi geri al
-- → tekrar beğen → 23505 → "Beğeni eklenirken hata". Aynı tuzak aynı
-- gönderiye ikinci yorum, tekrar takip vb. için de geçerliydi.
--
-- ÇÖZÜM: dedup silme koşulundan is_read = FALSE kaldırılır. Eski satır
-- okunmuş olsa da silinir; INSERT her zaman başarılı olur ve eylem
-- (beğeni/yorum) asla bloklanmaz. Tekrar eden eylem bildirimi taze,
-- okunmamış ve push'lanmış olarak yeniler (outbox INSERT trigger'ı yeni
-- satır için yine tetiklenir; notification_outbox'un notifications(id)
-- ON DELETE CASCADE FK'sı eski satırın outbox kaydını temizler).
-- ============================================================================

CREATE OR REPLACE FUNCTION public.dedup_notification()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  -- Aynı kullanıcı + entity + tip için varolan bildirimi sil. Okunmuş
  -- olsa bile: tekil kısıt (idx_notifications_user_entity_type) yüzünden
  -- eski satır dururken INSERT 23505 veriyor ve eylem geri alınıyordu.
  -- Sil-yenile: tekrar eden eylem bildirimi taze/okunmamış yeniler.
  IF NEW.entity_id IS NOT NULL THEN
    DELETE FROM notifications
    WHERE user_id = NEW.user_id
      AND entity_id = NEW.entity_id
      AND type = NEW.type
      AND id != NEW.id;
  END IF;

  RETURN NEW;
END;
$$;
