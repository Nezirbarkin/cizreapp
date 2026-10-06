-- =============================================================================
-- Görev 4.2 — Admin: sponsorluk (öne çıkarma) fiyat/paket/onay yönetimi
-- =============================================================================
-- 3.2'deki altyapının (sponsorship_packages, shop_sponsorships,
-- private.refresh_sponsored_until, app_settings.sponsorship_*) yönetim yüzü:
--   * admin_sponsorships_list(status, limit, offset): başvurular / yayında /
--     geçmiş + özet sayılar (tek istek),
--   * admin_review_sponsorship(id, approve, note): bekleyen başvuruyu onaylar
--     (zincirin sonundan başlatır, vitrin sütununu tazeler) ya da reddeder
--     (ücret bakiyeye İADE edilir),
--   * admin_cancel_sponsorship(id, refund, note): süren/sıradaki öne çıkarmayı
--     iptal eder; iade isteğe bağlı (başlamamışsa tamamı, sürüyorsa kalan süre
--     kadarı); aynı hedefte sıradakiler öne çekilir,
--   * her karar satıcıya bildirim (push) olarak gider.
-- Paketler ve iki genel anahtar mevcut admin RLS'iyle doğrudan yazılır.
-- =============================================================================

BEGIN;

-- -----------------------------------------------------------------------------
-- Yardımcı: satıcıya karar bildirimi
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION private.sponsorship_notify_owner(
  p_sponsorship public.shop_sponsorships,
  p_title text,
  p_body text
)
RETURNS void
LANGUAGE plpgsql
SET search_path = ''
AS $fn$
DECLARE
  v_owner uuid;
BEGIN
  SELECT s.owner_id INTO v_owner FROM public.shops s WHERE s.id = p_sponsorship.shop_id;
  IF v_owner IS NULL THEN
    RETURN;
  END IF;
  INSERT INTO public.notifications (user_id, type, title, content, entity_type, entity_id, data, is_read, created_at)
  VALUES (
    v_owner, 'sponsorship_update', p_title, p_body, 'shop_sponsorship', p_sponsorship.id::text,
    jsonb_build_object('sponsorship_id', p_sponsorship.id, 'shop_id', p_sponsorship.shop_id,
                       'status', p_sponsorship.status, 'placement', p_sponsorship.placement),
    false, now()
  );
END;
$fn$;

REVOKE ALL ON FUNCTION private.sponsorship_notify_owner(public.shop_sponsorships, text, text) FROM PUBLIC;

CREATE OR REPLACE FUNCTION private.sponsorship_placement_label(p_placement text)
RETURNS text
LANGUAGE sql
IMMUTABLE
SET search_path = ''
AS $fn$
  SELECT CASE p_placement
    WHEN 'shop_list' THEN 'Dükkanlar listesi'
    WHEN 'shop_category' THEN 'Kategori sayfası'
    WHEN 'product_category' THEN 'Ürünler sayfası'
    ELSE 'İndirimdekiler'
  END;
$fn$;

-- Bakiyeye iade (tutar > 0). Bakiye satırı yoksa açılır.
CREATE OR REPLACE FUNCTION private.sponsorship_refund(
  p_sponsorship public.shop_sponsorships,
  p_amount numeric,
  p_reason text
)
RETURNS numeric
LANGUAGE plpgsql
SET search_path = ''
AS $fn$
DECLARE
  v_user uuid := p_sponsorship.created_by;
  v_balance_id uuid;
  v_balance numeric(12,2);
  v_amount numeric(10,2) := round(GREATEST(COALESCE(p_amount, 0), 0), 2);
BEGIN
  IF v_amount <= 0 OR v_user IS NULL THEN
    RETURN 0;
  END IF;
  SELECT ub.id, ub.balance INTO v_balance_id, v_balance
    FROM public.user_balances ub WHERE ub.user_id = v_user FOR UPDATE;
  IF v_balance_id IS NULL THEN
    INSERT INTO public.user_balances (user_id, balance) VALUES (v_user, 0)
    RETURNING id, balance INTO v_balance_id, v_balance;
  END IF;
  UPDATE public.user_balances
     SET balance = v_balance + v_amount,
         total_refunds = COALESCE(total_refunds, 0) + v_amount,
         updated_at = now()
   WHERE id = v_balance_id;
  INSERT INTO public.balance_transactions (
    user_id, type, amount, net_amount, balance_before, balance_after,
    reference_type, reference_id, status, description, metadata
  ) VALUES (
    v_user, 'refund'::public.balance_transaction_type, v_amount, v_amount,
    v_balance, v_balance + v_amount, 'shop_sponsorship', p_sponsorship.id, 'completed',
    format('Öne çıkarma iadesi — %s (%s): %s',
      private.sponsorship_placement_label(p_sponsorship.placement), p_sponsorship.package_name, p_reason),
    jsonb_build_object('sponsorship_id', p_sponsorship.id, 'shop_id', p_sponsorship.shop_id)
  );
  RETURN v_amount;
END;
$fn$;

REVOKE ALL ON FUNCTION private.sponsorship_refund(public.shop_sponsorships, numeric, text) FROM PUBLIC;

-- Aynı hedef+vitrin için sıradaki (başlamamış) öne çıkarmaları boşluksuz
-- yeniden dizer: her biri öncekinin bitişinden (ya da şimdiden) başlar.
CREATE OR REPLACE FUNCTION private.sponsorship_rechain(
  p_shop_id uuid,
  p_product_id uuid,
  p_placement text
)
RETURNS void
LANGUAGE plpgsql
SET search_path = ''
AS $fn$
DECLARE
  v_cursor timestamptz;
  r record;
BEGIN
  SELECT GREATEST(now(), COALESCE(max(s.ends_at), now())) INTO v_cursor
    FROM public.shop_sponsorships s
   WHERE s.shop_id = p_shop_id AND s.placement = p_placement
     AND s.product_id IS NOT DISTINCT FROM p_product_id
     AND s.status = 'active' AND s.starts_at <= now() AND s.ends_at > now();

  FOR r IN
    SELECT s.id, s.duration_days FROM public.shop_sponsorships s
     WHERE s.shop_id = p_shop_id AND s.placement = p_placement
       AND s.product_id IS NOT DISTINCT FROM p_product_id
       AND s.status = 'active' AND s.starts_at > now()
     ORDER BY s.starts_at, s.created_at
     FOR UPDATE
  LOOP
    UPDATE public.shop_sponsorships
       SET starts_at = v_cursor,
           ends_at = v_cursor + make_interval(days => r.duration_days)
     WHERE id = r.id;
    v_cursor := v_cursor + make_interval(days => r.duration_days);
  END LOOP;

  PERFORM private.refresh_sponsored_until(p_shop_id, p_product_id, p_placement);
END;
$fn$;

REVOKE ALL ON FUNCTION private.sponsorship_rechain(uuid, uuid, text) FROM PUBLIC;

-- -----------------------------------------------------------------------------
-- Liste + özet
-- -----------------------------------------------------------------------------
-- p_status: 'pending' | 'active' (süren + sıradaki) | 'history' | 'all'
CREATE OR REPLACE FUNCTION public.admin_sponsorships_list(
  p_status text DEFAULT 'pending',
  p_limit integer DEFAULT 50,
  p_offset integer DEFAULT 0
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $fn$
DECLARE
  v_limit integer := LEAST(GREATEST(COALESCE(p_limit, 50), 1), 200);
  v_offset integer := GREATEST(COALESCE(p_offset, 0), 0);
  v_total integer;
  v_rows jsonb;
BEGIN
  IF NOT public.auth_is_admin() THEN
    RAISE EXCEPTION 'Yönetici yetkisi gerekli' USING ERRCODE = '42501';
  END IF;

  WITH filtered AS (
    SELECT s.*
      FROM public.shop_sponsorships s
     WHERE CASE COALESCE(p_status, 'pending')
             WHEN 'pending' THEN s.status = 'pending'
             WHEN 'active' THEN s.status = 'active' AND s.ends_at > now()
             WHEN 'history' THEN s.status IN ('rejected', 'cancelled')
                                 OR (s.status = 'active' AND s.ends_at <= now())
             ELSE true
           END
  )
  SELECT (SELECT count(*) FROM filtered),
         COALESCE(jsonb_agg(jsonb_build_object(
           'id', f.id,
           'shop_id', f.shop_id,
           'shop_name', sh.name,
           'product_id', f.product_id,
           'product_name', pr.name,
           'placement', f.placement,
           'package_name', f.package_name,
           'duration_days', f.duration_days,
           'price_paid', f.price_paid,
           'status', f.status,
           'starts_at', f.starts_at,
           'ends_at', f.ends_at,
           'created_at', f.created_at,
           'created_by_name', COALESCE(NULLIF(btrim(p.full_name), ''), p.username),
           'reviewed_at', f.reviewed_at,
           'review_note', f.review_note,
           'is_running', f.status = 'active' AND f.starts_at <= now() AND f.ends_at > now(),
           'is_queued', f.status = 'active' AND f.starts_at > now()
         ) ORDER BY
             CASE WHEN f.status = 'pending' THEN f.created_at END ASC,
             f.created_at DESC, f.id), '[]'::jsonb)
    INTO v_total, v_rows
    -- Sayfa kesimi ile sayfa içi sıra AYNI ifade: bekleyenler en eskiden,
    -- diğerleri en yeniden (sayfalar birleşince sıra bozulmaz).
    FROM (SELECT * FROM filtered
           ORDER BY CASE WHEN status = 'pending' THEN created_at END ASC, created_at DESC, id
           LIMIT v_limit OFFSET v_offset) f
    LEFT JOIN public.shops sh ON sh.id = f.shop_id
    LEFT JOIN public.products pr ON pr.id = f.product_id
    LEFT JOIN public.profiles p ON p.id = f.created_by;

  RETURN jsonb_build_object(
    'total', COALESCE(v_total, 0),
    'rows', v_rows,
    'summary', (
      SELECT jsonb_build_object(
        'pending', count(*) FILTER (WHERE s.status = 'pending'),
        'running', count(*) FILTER (WHERE s.status = 'active' AND s.starts_at <= now() AND s.ends_at > now()),
        'queued', count(*) FILTER (WHERE s.status = 'active' AND s.starts_at > now()),
        'revenue_30d', COALESCE(sum(s.price_paid) FILTER (
            WHERE s.status IN ('active', 'pending') AND s.created_at > now() - interval '30 days'), 0)
      )
      FROM public.shop_sponsorships s
    ),
    'settings', jsonb_build_object(
      'enabled', COALESCE((SELECT NULLIF(btrim(a.value #>> '{}'), '')::boolean
                             FROM public.app_settings a WHERE a.key = 'sponsorship_enabled'), true),
      'requires_approval', COALESCE((SELECT NULLIF(btrim(a.value #>> '{}'), '')::boolean
                                       FROM public.app_settings a WHERE a.key = 'sponsorship_requires_approval'), false)
    )
  );
END;
$fn$;

-- -----------------------------------------------------------------------------
-- Onay / ret
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_review_sponsorship(
  p_id uuid,
  p_approve boolean,
  p_note text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $fn$
DECLARE
  v public.shop_sponsorships%ROWTYPE;
  v_start timestamptz;
  v_refund numeric := 0;
  v_note text := NULLIF(btrim(COALESCE(p_note, '')), '');
BEGIN
  IF NOT public.auth_is_admin() THEN
    RAISE EXCEPTION 'Yönetici yetkisi gerekli' USING ERRCODE = '42501';
  END IF;
  SELECT * INTO v FROM public.shop_sponsorships WHERE id = p_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Başvuru bulunamadı' USING ERRCODE = 'P0001', HINT = 'SPONSORSHIP_NOT_FOUND';
  END IF;
  IF v.status <> 'pending' THEN
    RAISE EXCEPTION 'Bu başvuru zaten sonuçlandı' USING ERRCODE = 'P0001', HINT = 'SPONSORSHIP_NOT_PENDING';
  END IF;

  IF p_approve THEN
    -- Mağaza satırı kilitlenir (satın almadaki gibi): zincir bozulmasın.
    PERFORM 1 FROM public.shops WHERE id = v.shop_id FOR UPDATE;
    SELECT GREATEST(now(), COALESCE(max(s.ends_at), now())) INTO v_start
      FROM public.shop_sponsorships s
     WHERE s.shop_id = v.shop_id AND s.placement = v.placement
       AND s.product_id IS NOT DISTINCT FROM v.product_id
       AND s.status = 'active' AND s.ends_at > now();
    UPDATE public.shop_sponsorships
       SET status = 'active',
           starts_at = v_start,
           ends_at = v_start + make_interval(days => v.duration_days),
           reviewed_by = auth.uid(), reviewed_at = now(), review_note = v_note
     WHERE id = p_id
    RETURNING * INTO v;
    PERFORM private.refresh_sponsored_until(v.shop_id, v.product_id, v.placement);
    PERFORM private.sponsorship_notify_owner(v,
      'Öne çıkarma onaylandı',
      format('%s (%s) öne çıkarman onaylandı; %s tarihinden itibaren yayında.',
        private.sponsorship_placement_label(v.placement), v.package_name,
        to_char(v.starts_at AT TIME ZONE 'Europe/Istanbul', 'DD.MM.YYYY HH24:MI')));
  ELSE
    UPDATE public.shop_sponsorships
       SET status = 'rejected', reviewed_by = auth.uid(), reviewed_at = now(), review_note = v_note
     WHERE id = p_id
    RETURNING * INTO v;
    v_refund := private.sponsorship_refund(v, v.price_paid, COALESCE(v_note, 'başvuru reddedildi'));
    PERFORM private.sponsorship_notify_owner(v,
      'Öne çıkarma başvurun reddedildi',
      format('%s (%s) başvurun reddedildi%s; %s TL bakiyene iade edildi.',
        private.sponsorship_placement_label(v.placement), v.package_name,
        COALESCE(': ' || v_note, ''), v_refund));
  END IF;

  RETURN jsonb_build_object('id', v.id, 'status', v.status, 'starts_at', v.starts_at,
                            'ends_at', v.ends_at, 'refunded', v_refund);
END;
$fn$;

-- -----------------------------------------------------------------------------
-- İptal (süren ya da sıradaki)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_cancel_sponsorship(
  p_id uuid,
  p_refund boolean DEFAULT true,
  p_note text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $fn$
DECLARE
  v public.shop_sponsorships%ROWTYPE;
  v_refund numeric := 0;
  v_amount numeric := 0;
  v_note text := NULLIF(btrim(COALESCE(p_note, '')), '');
  v_total_secs numeric;
  v_left_secs numeric;
BEGIN
  IF NOT public.auth_is_admin() THEN
    RAISE EXCEPTION 'Yönetici yetkisi gerekli' USING ERRCODE = '42501';
  END IF;
  SELECT * INTO v FROM public.shop_sponsorships WHERE id = p_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Kayıt bulunamadı' USING ERRCODE = 'P0001', HINT = 'SPONSORSHIP_NOT_FOUND';
  END IF;
  IF v.status <> 'active' OR v.ends_at <= now() THEN
    RAISE EXCEPTION 'Yalnız süren ya da sıradaki öne çıkarma iptal edilebilir'
      USING ERRCODE = 'P0001', HINT = 'SPONSORSHIP_NOT_ACTIVE';
  END IF;

  IF COALESCE(p_refund, false) THEN
    IF v.starts_at > now() THEN
      v_amount := v.price_paid;                 -- hiç başlamadı: tamamı
    ELSE
      v_total_secs := extract(epoch FROM (v.ends_at - v.starts_at));
      v_left_secs := GREATEST(extract(epoch FROM (v.ends_at - now())), 0);
      v_amount := CASE WHEN v_total_secs > 0 THEN v.price_paid * v_left_secs / v_total_secs ELSE 0 END;
    END IF;
  END IF;

  UPDATE public.shop_sponsorships
     SET status = 'cancelled',
         ends_at = CASE WHEN starts_at <= now() THEN now() ELSE ends_at END,
         reviewed_by = auth.uid(), reviewed_at = now(), review_note = v_note
   WHERE id = p_id
  RETURNING * INTO v;

  v_refund := private.sponsorship_refund(v, v_amount, COALESCE(v_note, 'yönetici iptali'));
  PERFORM private.sponsorship_rechain(v.shop_id, v.product_id, v.placement);
  PERFORM private.sponsorship_notify_owner(v,
    'Öne çıkarman iptal edildi',
    format('%s (%s) öne çıkarman yönetim tarafından iptal edildi%s.%s',
      private.sponsorship_placement_label(v.placement), v.package_name,
      COALESCE(': ' || v_note, ''),
      CASE WHEN v_refund > 0 THEN format(' %s TL bakiyene iade edildi.', v_refund) ELSE '' END));

  RETURN jsonb_build_object('id', v.id, 'status', v.status, 'refunded', v_refund);
END;
$fn$;

REVOKE ALL ON FUNCTION public.admin_sponsorships_list(text, integer, integer) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.admin_review_sponsorship(uuid, boolean, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.admin_cancel_sponsorship(uuid, boolean, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_sponsorships_list(text, integer, integer) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_review_sponsorship(uuid, boolean, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_cancel_sponsorship(uuid, boolean, text) TO authenticated;

COMMIT;

NOTIFY pgrst, 'reload schema';
