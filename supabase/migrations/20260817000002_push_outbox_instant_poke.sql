-- ============================================================================
-- Push notification anlık teslim poke trigger'ı (2026-08-14)
-- ----------------------------------------------------------------------------
-- AMAÇ: notification_outbox'a her INSERT'te process-notification-outbox
-- Edge Function'ını anında çağırmak. Böylece push, dakikalık pg_cron job'ını
-- (20260817000001) beklemeden saniyeler içinde gönderilir. Cron yedek
-- süpürücü olarak kalır: poke kaçarsa/başarısız olursa bildirim en geç
-- 1 dakika sonra yine gider.
--
-- TASARIM:
--   - FOR EACH STATEMENT: tek INSERT..SELECT ile 1000 satır eklenen
--     broadcast'lerde satır başına değil, ifade başına TEK poke atılır.
--   - EXCEPTION guard: pg_net/Vault hatası bildirim yazan transaction'ı
--     asla bozamaz; poke best-effort'tir.
--   - SECURITY DEFINER: outbox'a authenticated roller üzerinden yazıldığında
--     da Vault okunabilsin diye (fonksiyon tek iş yapar, girdisi yoktur).
--   - pg_net çağrısı net.http_post şeklinde (net şeması; cron job'larıyla
--     aynı çözümleme).
--   - Secret çözümü cron job'ıyla aynı: custom config → Vault
--     (COURIER_ASSIGNMENT_EMAIL_WORKER_SECRET önce; edge env
--     INTERNAL_WORKER_SECRET ile kanıtlanmış eşleşen değer odur).
-- ============================================================================

CREATE EXTENSION IF NOT EXISTS pg_net;

CREATE OR REPLACE FUNCTION public.poke_notification_outbox_worker()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_secret text;
  v_url text;
BEGIN
  BEGIN
    v_secret := COALESCE(
      NULLIF(
        current_setting('app.settings.internal_worker_secret', true),
        ''
      ),
      (
        SELECT vault.decrypted_secrets.decrypted_secret
        FROM vault.decrypted_secrets
        WHERE vault.decrypted_secrets.name IN (
          'COURIER_ASSIGNMENT_EMAIL_WORKER_SECRET',
          'INTERNAL_WORKER_SECRET'
        )
        ORDER BY
          CASE
            WHEN vault.decrypted_secrets.name = 'COURIER_ASSIGNMENT_EMAIL_WORKER_SECRET' THEN 0
            ELSE 1
          END,
          vault.decrypted_secrets.created_at DESC
        LIMIT 1
      )
    );

    IF v_secret IS NULL OR v_secret = '' THEN
      -- Secret çözülemedi; dakikalık cron yine de süpürür.
      RETURN NULL;
    END IF;

    v_url := COALESCE(
      NULLIF(current_setting('app.settings.supabase_url', true), ''),
      'https://xsbukxkgtmdyickknqzf.supabase.co'
    ) || '/functions/v1/process-notification-outbox';

    -- NOT: pg_net fonksiyonu İKİ kısımlı yazılmalı (net.http_post). Üç
    -- kısımlı yazım (extensions.net.http_post) fonksiyon değil
    -- db.schema.tablo olarak çözümlenir: "cross-database references" hatası
    -- verir ve exception guard tarafından yutulur.
    PERFORM net.http_post(
      url := v_url,
      headers := jsonb_build_object(
        'x-worker-secret', v_secret,
        'Content-Type', 'application/json'
      ),
      body := '{}'::jsonb,
      timeout_milliseconds := 30000
    );
  EXCEPTION WHEN OTHERS THEN
    -- Poke best-effort: herhangi bir hata bildirim akışını etkilemez.
    NULL;
  END;

  RETURN NULL;
END;
$$;

-- Trigger fonksiyonları çağrı için EXECUTE izni istemez; doğrudan
-- çağrılabilmeyi kapat (SECURITY DEFINER olduğu için gereksiz yüzey açma).
REVOKE EXECUTE ON FUNCTION public.poke_notification_outbox_worker()
  FROM PUBLIC, authenticated, anon;

DROP TRIGGER IF EXISTS notification_outbox_poke_worker
  ON public.notification_outbox;

CREATE TRIGGER notification_outbox_poke_worker
AFTER INSERT ON public.notification_outbox
FOR EACH STATEMENT
EXECUTE FUNCTION public.poke_notification_outbox_worker();
