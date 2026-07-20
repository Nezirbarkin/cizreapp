-- Fix: grant-ad-reward Edge Function'daki race condition.
-- Önceki akış: limit kontrolleri + bakiye okuma/yazma ayrı SELECT/UPDATE
-- adımlarıydı, aralarında kilit yoktu. Aynı kullanıcı isteği paralel iki kez
-- gönderirse cooldown/saatlik/günlük limitler ve bakiye güncellemesi
-- atlanabiliyordu (lost update + limit bypass).
-- Çözüm: tüm akışı pg_advisory_xact_lock ile kullanıcı bazında serileştirilen,
-- SECURITY DEFINER bir RPC içine taşımak. Edge Function artık sadece bu
-- fonksiyonu çağırır.

CREATE OR REPLACE FUNCTION grant_ad_reward(
  p_user_id uuid,
  p_device_id text,
  p_ip_address text,
  p_watched_seconds int
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_settings ad_settings;
  v_now timestamptz := now();
  v_day_start timestamptz := date_trunc('day', v_now);
  v_hour_start timestamptz := v_now - interval '1 hour';
  v_today_count int;
  v_hour_count int;
  v_last_view timestamptz;
  v_device_count_today int;
  v_reward numeric;
  v_today_total_paid numeric;
  v_balance user_balances;
  v_new_balance numeric;
  v_tx_id uuid;
BEGIN
  -- Aynı kullanıcı için eşzamanlı çağrıları serileştir.
  PERFORM pg_advisory_xact_lock(hashtext(p_user_id::text));

  SELECT * INTO v_settings FROM ad_settings WHERE id = 1;
  IF v_settings IS NULL THEN
    RETURN jsonb_build_object('error', 'Reklam ayarları bulunamadı', 'status', 500);
  END IF;
  IF NOT v_settings.is_enabled THEN
    RETURN jsonb_build_object('error', 'Reklam izleyerek bakiye kazanma şu anda kapalı', 'status', 403);
  END IF;

  IF p_watched_seconds > 0 AND p_watched_seconds < v_settings.min_watch_seconds THEN
    INSERT INTO ad_reward_views (user_id, reward_amount, status, block_reason, device_id, ip_address)
    VALUES (p_user_id, 0, 'blocked', 'watched_seconds too short: ' || p_watched_seconds, p_device_id, p_ip_address);
    RETURN jsonb_build_object('error', 'Reklam yeterince izlenmedi', 'status', 400);
  END IF;

  SELECT count(*) INTO v_today_count
  FROM ad_reward_views
  WHERE user_id = p_user_id AND status = 'success' AND created_at >= v_day_start;

  SELECT count(*) INTO v_hour_count
  FROM ad_reward_views
  WHERE user_id = p_user_id AND status = 'success' AND created_at >= v_hour_start;

  SELECT max(created_at) INTO v_last_view
  FROM ad_reward_views
  WHERE user_id = p_user_id AND status = 'success' AND created_at >= v_day_start;

  IF v_today_count >= v_settings.max_views_per_day THEN
    RETURN jsonb_build_object(
      'error', 'Bugünlük reklam izleme hakkınız doldu', 'status', 429,
      'limit_type', 'daily',
      'retry_after_seconds', GREATEST(1, ceil(extract(epoch FROM (date_trunc('day', v_now) + interval '1 day' - v_now))))
    );
  END IF;

  IF v_hour_count >= v_settings.max_views_per_hour THEN
    RETURN jsonb_build_object(
      'error', 'Saatlik reklam izleme limitine ulaştın, biraz beklemelisin', 'status', 429,
      'limit_type', 'hourly',
      'retry_after_seconds', GREATEST(1, ceil(60 * 60 - extract(epoch FROM (v_now - v_hour_start))))
    );
  END IF;

  IF v_last_view IS NOT NULL AND extract(epoch FROM (v_now - v_last_view)) < v_settings.cooldown_seconds THEN
    RETURN jsonb_build_object(
      'error', 'Yeni reklam izlemek için bekle', 'status', 429,
      'limit_type', 'cooldown',
      'retry_after_seconds', ceil(v_settings.cooldown_seconds - extract(epoch FROM (v_now - v_last_view)))
    );
  END IF;

  IF p_device_id IS NOT NULL THEN
    SELECT count(*) INTO v_device_count_today
    FROM ad_reward_views
    WHERE device_id = p_device_id AND status = 'success' AND created_at >= v_day_start;

    IF v_device_count_today >= v_settings.max_views_per_day * 3 THEN
      INSERT INTO ad_reward_views (user_id, reward_amount, status, block_reason, device_id, ip_address)
      VALUES (p_user_id, 0, 'blocked', 'device_daily_limit_exceeded', p_device_id, p_ip_address);
      RETURN jsonb_build_object('error', 'Bu cihaz için günlük limit aşıldı', 'status', 429);
    END IF;
  END IF;

  v_reward := round((v_settings.reward_min_try + power(random(), 4) * (v_settings.reward_max_try - v_settings.reward_min_try))::numeric, 2);

  SELECT coalesce(sum(reward_amount), 0) INTO v_today_total_paid
  FROM ad_reward_views
  WHERE status = 'success' AND created_at >= v_day_start;

  IF v_today_total_paid + v_reward > v_settings.max_daily_payout_try THEN
    RETURN jsonb_build_object('error', 'Günlük toplam reklam ödül bütçesi tükendi, yarın tekrar deneyin', 'status', 429);
  END IF;

  SELECT * INTO v_balance FROM user_balances WHERE user_id = p_user_id FOR UPDATE;
  IF v_balance IS NULL THEN
    RETURN jsonb_build_object('error', 'Kullanıcı bakiyesi bulunamadı', 'status', 404);
  END IF;

  v_new_balance := v_balance.balance + v_reward;

  UPDATE user_balances
  SET balance = v_new_balance, total_earned = total_earned + v_reward
  WHERE user_id = p_user_id;

  INSERT INTO balance_transactions (
    user_id, type, amount, fee, net_amount, balance_before, balance_after,
    reference_type, description, status, payment_method
  ) VALUES (
    p_user_id, 'ad_reward', v_reward, 0, v_reward, v_balance.balance, v_new_balance,
    'ad_reward', 'Reklam izleyerek bakiye kazanıldı', 'completed', 'ad_reward'
  ) RETURNING id INTO v_tx_id;

  INSERT INTO ad_reward_views (user_id, reward_amount, status, device_id, ip_address, balance_transaction_id)
  VALUES (p_user_id, v_reward, 'success', p_device_id, p_ip_address, v_tx_id);

  RETURN jsonb_build_object(
    'status', 200,
    'reward_amount', v_reward,
    'new_balance', v_new_balance,
    'remaining_today', v_settings.max_views_per_day - (v_today_count + 1)
  );
END;
$$;

GRANT EXECUTE ON FUNCTION grant_ad_reward(uuid, text, text, int) TO service_role;
REVOKE EXECUTE ON FUNCTION grant_ad_reward(uuid, text, text, int) FROM anon, authenticated;
