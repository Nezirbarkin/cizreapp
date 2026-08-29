-- =============================================================================
-- Admin toplu bildirim (broadcast) push teslimatı eksikliği düzeltmesi
--
-- Sorun: admin_broadcast_notification yalnızca public.admin_broadcasts
-- tablosuna yazıyordu; public.notifications'a hiç INSERT yapmıyordu.
-- Push pipeline'ı (20260802000003_secure_push_notification_pipeline.sql)
-- yalnızca notifications INSERT'ini notification_outbox'a alan bir trigger'a
-- dayanıyor; broadcast bu satırı hiç oluşturmadığı için "Tümü / Müşteriler /
-- Satıcılar" hedefine gönderilen admin bildirimleri cihazlara push olarak
-- gitmiyordu (uygulama içi bildirim listesinde admin_broadcasts tablosundan
-- doğrudan görünüyordu, bu yüzden "DB'ye yazılıyor ama push gitmiyor" hiç
-- fark edilmemişti). Kişisel bildirim yolu (admin_send_personal_notification)
-- zaten notifications'a yazdığı için push orada sorunsuz çalışıyordu.
--
-- Çözüm: admin_broadcast_notification artık admin_broadcasts kaydından sonra
-- hedef kitledeki her kullanıcı için public.notifications'a bir satır ekliyor
-- (type='admin_broadcast', entity_id='admin_icon:<icon>' - istemcinin admin
-- bildirimlerini tanıdığı mevcut format). Mevcut notifications_outbox_trigger
-- bu satırları otomatik olarak outbox'a alıp FCM ile push gönderir.
-- RPC imzası değişmediği için Flutter tarafında hiçbir değişiklik gerekmez.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.admin_broadcast_notification(
  p_title     TEXT,
  p_content   TEXT,
  p_icon_type TEXT DEFAULT 'info',
  p_target_audience TEXT DEFAULT 'all_users'
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_admin_id     CONSTANT UUID := auth.uid();
  v_caller_role  CONSTANT TEXT := COALESCE(auth.role(), '');
  v_audit_id     UUID;
  v_audience     TEXT;
  v_icon         TEXT;
  v_broadcast_id UUID;
BEGIN
  IF v_admin_id IS NULL OR v_caller_role = 'anon' THEN
    RAISE EXCEPTION 'Oturum açmanız gerekiyor' USING ERRCODE = '42501';
  END IF;

  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Bu işlem için admin yetkisi gereklidir' USING ERRCODE = '42501';
  END IF;

  IF p_title IS NULL OR LENGTH(p_title) = 0 OR LENGTH(p_title) > 100 THEN
    RAISE EXCEPTION 'Başlık 1-100 karakter olmalıdır' USING ERRCODE = '22000';
  END IF;

  IF p_content IS NULL OR LENGTH(p_content) = 0 OR LENGTH(p_content) > 1000 THEN
    RAISE EXCEPTION 'İçerik 1-1000 karakter olmalıdır' USING ERRCODE = '22000';
  END IF;

  v_audience := COALESCE(NULLIF(p_target_audience, ''), 'all_users');
  IF v_audience NOT IN ('customers', 'sellers', 'all_users') THEN
    RAISE EXCEPTION 'Geçersiz hedef kitle' USING ERRCODE = '22000';
  END IF;

  v_icon := COALESCE(NULLIF(p_icon_type, ''), 'info');

  INSERT INTO public.admin_notification_audit (
    admin_id, action, target_audience, title, content
  ) VALUES (
    v_admin_id, 'broadcast', v_audience, p_title, p_content
  )
  RETURNING id INTO v_audit_id;

  INSERT INTO public.admin_broadcasts (
    title, content, icon_type, target_audience, is_active
  ) VALUES (
    p_title, p_content, v_icon, v_audience, true
  )
  RETURNING id INTO v_broadcast_id;

  -- Hedef kitledeki her kullanıcı için notifications satırı ekle;
  -- notifications_outbox_trigger bunu otomatik olarak outbox'a alıp
  -- push worker'ın FCM ile göndermesini sağlar.
  INSERT INTO public.notifications (
    user_id, type, title, content, actor_id, entity_id, metadata, is_read, created_at
  )
  SELECT
    p.id,
    'admin_broadcast',
    p_title,
    p_content,
    v_admin_id,
    format('admin_icon:%s', v_icon),
    jsonb_build_object(
      'icon_type', v_icon,
      'target', v_audience,
      'broadcast_id', v_broadcast_id
    ),
    false,
    NOW()
  FROM public.profiles p
  WHERE p.id <> v_admin_id
    AND (
      v_audience = 'all_users'
      OR (v_audience = 'customers' AND p.role = 'customer')
      OR (v_audience = 'sellers' AND p.role = 'seller')
    );

  RETURN v_audit_id;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_broadcast_notification(TEXT, TEXT, TEXT, TEXT)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_broadcast_notification(TEXT, TEXT, TEXT, TEXT)
  TO authenticated;

-- -----------------------------------------------------------------------------
-- Tek seferlik telafi: bugün "all_users" hedefine gönderilen ama düzeltme
-- öncesi push'u hiç gitmemiş "CizreApp Android için Yeni sürüm" duyurusunu,
-- artık aktif olan outbox trigger üzerinden geriye dönük push'a alır.
-- -----------------------------------------------------------------------------
INSERT INTO public.notifications (
  user_id, type, title, content, actor_id, entity_id, metadata, is_read, created_at
)
SELECT
  p.id,
  'admin_broadcast',
  b.title,
  b.content,
  '78665f8b-6a07-40f3-b13d-d4b5a29296c6'::uuid,
  format('admin_icon:%s', COALESCE(NULLIF(b.icon_type, ''), 'info')),
  jsonb_build_object(
    'icon_type', COALESCE(NULLIF(b.icon_type, ''), 'info'),
    'target', b.target_audience,
    'broadcast_id', b.id,
    'backfill', true
  ),
  false,
  NOW()
FROM public.admin_broadcasts b
CROSS JOIN public.profiles p
WHERE b.id = '7d6ec0d4-1be1-4da2-bbe7-f98e32825797'::uuid
  AND p.id <> '78665f8b-6a07-40f3-b13d-d4b5a29296c6'::uuid
  AND NOT EXISTS (
    SELECT 1 FROM public.notifications n
    WHERE n.user_id = p.id
      AND n.type = 'admin_broadcast'
      AND n.metadata->>'broadcast_id' = b.id::text
  );
