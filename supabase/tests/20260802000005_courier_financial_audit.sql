-- =============================================================================
-- Salt-okunur finansal bütünlük denetimi (audit)
-- -----------------------------------------------------------------------------
-- Bu dosya yalnızca SELECT içerir. Veri silmez, güncellemez.
-- Şüpheli kayıtları listeler; manuel inceleme için rapor üretir.
--
-- Çalıştırma: Supabase SQL Editor'a yapıştırıp çalıştırın, veya
--   psql -f 20260802000005_courier_financial_audit.sql
-- =============================================================================

SET search_path = public, pg_temp;

SELECT '=== 1) Delivered olmayan pakete bağlı earnings ===' AS section;
SELECT ce.id AS earning_id, ce.package_request_id, ce.courier_id,
       ce.amount, ce.amount_snapshot, ce.status, ce.created_at
FROM public.courier_earnings AS ce
LEFT JOIN public.courier_requests AS cr ON cr.id = ce.package_request_id
WHERE ce.package_request_id IS NOT NULL
  AND (cr.id IS NULL OR cr.status <> 'delivered')
ORDER BY ce.created_at DESC;

SELECT '=== 2) Aynı package_request_id için birden fazla earnings ===' AS section;
SELECT ce.package_request_id, count(*) AS earning_count,
       sum(ce.amount) AS total_amount
FROM public.courier_earnings AS ce
WHERE ce.package_request_id IS NOT NULL
GROUP BY ce.package_request_id
HAVING count(*) > 1
ORDER BY earning_count DESC;

SELECT '=== 3) courier_request fee ile earning amount uyuşmazlıkları ===' AS section;
SELECT cr.id AS request_id, cr.courier_id,
       cr.total_fee, cr.courier_fee, cr.admin_commission,
       ce.amount AS earning_amount, ce.amount_snapshot
FROM public.courier_requests AS cr
JOIN public.courier_earnings AS ce ON ce.package_request_id = cr.id
WHERE ce.amount IS DISTINCT FROM cr.courier_fee
   OR (ce.amount_snapshot IS NOT NULL
       AND ce.amount_snapshot IS DISTINCT FROM cr.courier_fee);

SELECT '=== 4) Bakiye transaction''ı olmayan paket talepleri ===' AS section;
SELECT cr.id AS request_id, cr.sender_id, cr.total_fee, cr.status, cr.created_at
FROM public.courier_requests AS cr
WHERE cr.status IN ('accepted','delivery_pending_confirmation','delivered')
  AND NOT EXISTS (
    SELECT 1 FROM public.balance_transactions AS bt
    WHERE bt.reference_type = 'courier_request'
      AND bt.reference_id = cr.id
  )
ORDER BY cr.created_at DESC;

SELECT '=== 5) Payout amount ile item toplamı uyuşmazlıkları ===' AS section;
SELECT cpr.id AS payout_id, cpr.courier_id, cpr.amount AS payout_amount,
       cpr.status, cpr.requested_at,
       coalesce(sum(cpi.amount_snapshot), 0) AS items_total,
       cpr.amount - coalesce(sum(cpi.amount_snapshot), 0) AS diff
FROM public.courier_payout_requests AS cpr
LEFT JOIN public.courier_payout_items AS cpi ON cpi.payout_id = cpr.id
GROUP BY cpr.id
HAVING cpr.amount IS DISTINCT FROM coalesce(sum(cpi.amount_snapshot), 0)
ORDER BY abs(cpr.amount - coalesce(sum(cpi.amount_snapshot), 0)) DESC;

SELECT '=== 6) payment_reference olmayan approved payouts ===' AS section;
SELECT id, courier_id, amount, status, approved_at, approved_by
FROM public.courier_payout_requests
WHERE status = 'approved' AND (payment_reference IS NULL OR length(trim(payment_reference)) = 0);

SELECT '=== 7) Olağan dışı yüksek tutarlı earnings (>10000) ===' AS section;
SELECT id, courier_id, package_request_id, amount, status, created_at
FROM public.courier_earnings
WHERE amount > 10000
ORDER BY amount DESC;

SELECT '=== 8) Olağan dışı yüksek tutarlı payouts (>50000) ===' AS section;
SELECT id, courier_id, amount, status, requested_at
FROM public.courier_payout_requests
WHERE amount > 50000
ORDER BY amount DESC;

SELECT '=== 9) Durum aşamasını atlamış talepler (accepted olmadan delivered) ===' AS section;
SELECT id, sender_id, courier_id, status, created_at, accepted_at, delivered_at
FROM public.courier_requests
WHERE status = 'delivered'
  AND (accepted_at IS NULL OR delivered_at < accepted_at)
ORDER BY created_at DESC;

SELECT '=== 10) Rejected_by tutarsızlıkları (courier_request_rejections vs rejected_by) ===' AS section;
SELECT cr.id AS request_id,
       cr.rejected_by,
       (SELECT array_agg(crr.courier_id)
        FROM public.courier_request_rejections AS crr
        WHERE crr.request_id = cr.id) AS normalized_rejectors
FROM public.courier_requests AS cr
WHERE cr.rejected_by <> COALESCE(
        (SELECT array_agg(crr.courier_id)
         FROM public.courier_request_rejections AS crr
         WHERE crr.request_id = cr.id),
        ARRAY[]::uuid[]
      );

SELECT '=== Denetim tamamlandı. Yukarıdaki listeler yalnızca raporlama amaçlıdır; ===' AS section;
SELECT '=== hiçbir satır bu sorgu ile değiştirilmez veya silinmez. ===' AS section;
