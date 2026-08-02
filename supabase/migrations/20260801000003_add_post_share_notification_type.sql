-- ============================================================================
-- notifications.type kısıtına 'post_share' ekle
-- ----------------------------------------------------------------------------
-- Sorun: profile_screen.dart ve user_profile_screen.dart "arkadaşa gönder"
-- özelliğinde type='post_share' ile bildirim eklemeye çalışıyor, ancak
-- notifications_type_check constraint'i bu tipi içermiyordu. Bu nedenle
-- insert her seferinde Postgres check violation ile reddediliyordu.
--
-- Çözüm: constraint'i, migration geçmişinde kullanılmış TÜM tiplerin
-- birleşimi + 'post_share' ile yeniden oluştur. Birleşim mevcut tüm
-- tipleri kapsadığı için eski kayıtlar ihlal etmez.
-- ============================================================================

DO $$
BEGIN
  ALTER TABLE public.notifications DROP CONSTRAINT IF EXISTS notifications_type_check;

  ALTER TABLE public.notifications
  ADD CONSTRAINT notifications_type_check CHECK (type IN (
    -- temel sosyal
    'like',
    'comment',
    'follow',
    'mention',
    'story_mention',
    'post_share',
    -- sipariş / mağaza
    'order',
    'order_update',
    'order_ready',
    'delivery',
    'shop',
    'shop_approved',
    'shop_rejected',
    'shop_review',
    'shop_review_reply',
    -- destek
    'support_response',
    'support_status',
    'support_reply',
    'support_closed',
    'complaint_response',
    'report',
    -- ödeme
    'payout_approved',
    'payout_rejected',
    -- admin
    'admin_message'
  ));
EXCEPTION
  WHEN OTHERS THEN
    RAISE NOTICE 'notifications_type_check güncellenemedi (mevcut veriler yeni listeyi ihlal ediyor olabilir): %', SQLERRM;
END $$;

COMMENT ON CONSTRAINT notifications_type_check ON public.notifications IS
  'Bildirim tipleri; post_share arkadaşa gönderilen gönderi bildirimi için eklendi.';