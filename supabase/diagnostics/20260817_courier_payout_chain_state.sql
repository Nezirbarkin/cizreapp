-- =============================================================================
-- Kurye odeme zinciri — prod durum tespiti
--
-- Neden gerekli: public.courier_earnings ve public.courier_payout_requests
-- tablolari repodaki HICBIR migration tarafindan CREATE edilmiyor (yalnizca
-- ALTER ediliyorlar). Bu tablolar Supabase dashboard'undan elle olusturulmus;
-- dolayisiyla CHECK kisitlari ve kolon tipleri repodan okunamaz.
--
-- Supabase SQL Editor'de admin olarak calistirin ve ciktiyi paylasin.
-- =============================================================================

-- 1) BIRINCIL SUPHELI: notifications tip kisitinin GERCEK hali.
--    'courier_payout_approved' bu listede yoksa admin onayi 23514 ile patlar.
SELECT 'notifications_type_check' AS kontrol,
       pg_get_constraintdef(c.oid) AS tanim
FROM pg_constraint c
JOIN pg_class t ON t.oid = c.conrelid
JOIN pg_namespace n ON n.oid = t.relnamespace
WHERE n.nspname = 'public'
  AND t.relname = 'notifications'
  AND c.contype = 'c';

-- 2) Kurye/paket bildirim tiplerinin tek tek gecerliligi.
--    "REDDEDER" cikan her tip, o akisin bildirim adiminda kirildigini gosterir.
--    Ciktiyi gormek icin SQL Editor'de "Messages/Notices" sekmesine bakin.
DO $$
DECLARE
  v_tip text;
  v_def text;
BEGIN
  SELECT pg_get_constraintdef(c.oid) INTO v_def
  FROM pg_constraint c
  JOIN pg_class t ON t.oid = c.conrelid
  JOIN pg_namespace n ON n.oid = t.relnamespace
  WHERE n.nspname='public' AND t.relname='notifications'
    AND c.conname='notifications_type_check';

  IF v_def IS NULL THEN
    RAISE NOTICE 'notifications_type_check YOK (kisit kaldirilmis).';
    RETURN;
  END IF;

  FOREACH v_tip IN ARRAY ARRAY[
    'courier_payout_approved','courier_payout_rejected','courier_payout_request',
    'courier_delivered','courier_assigned','new_package_request',
    'package_delivered','package_route','package_dispute_rejected',
    'message','chat','verification_code','task_approved','balance_topup'
  ] LOOP
    IF v_def LIKE '%''' || v_tip || '''%' THEN
      RAISE NOTICE 'IZINLI   : %', v_tip;
    ELSE
      RAISE NOTICE 'REDDEDER : %  <-- bu tipi yazan akis 23514 ile kiriliyor', v_tip;
    END IF;
  END LOOP;
END $$;

-- 3) Odeme zinciri tablolarinin gercek kolonlari ve tipleri.
SELECT table_name, column_name, data_type, is_nullable, column_default
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name IN ('courier_payout_requests','courier_payout_items',
                     'courier_earnings','courier_requests')
ORDER BY table_name, ordinal_position;

-- 4) Bu tablolardaki TUM CHECK kisitlari.
--    courier_payout_requests.status 'approved' kabul ediyor mu?
--    courier_earnings.status 'requested' ve 'paid' kabul ediyor mu?
SELECT t.relname AS tablo, c.conname AS kisit, pg_get_constraintdef(c.oid) AS tanim
FROM pg_constraint c
JOIN pg_class t ON t.oid = c.conrelid
JOIN pg_namespace n ON n.oid = t.relnamespace
WHERE n.nspname='public'
  AND t.relname IN ('courier_payout_requests','courier_payout_items',
                    'courier_earnings','courier_requests')
  AND c.contype = 'c'
ORDER BY t.relname, c.conname;

-- 5) Indeksler: uq_courier_payout_items_earning_id kosulsuz mu?
--    (kosulsuz ise reddedilen kurye bir daha odeme isteyemez -> 23505)
SELECT tablename, indexname, indexdef
FROM pg_indexes
WHERE schemaname='public'
  AND tablename IN ('courier_payout_items','courier_payout_requests','courier_earnings')
ORDER BY tablename, indexname;

-- 6) RPC'lerin varligi ve imzalari (PGRST202 teshisi).
SELECT p.proname,
       pg_get_function_identity_arguments(p.oid) AS argumanlar,
       p.prosecdef AS security_definer,
       pg_get_userbyid(p.proowner) AS sahip
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname='public'
  AND p.proname IN ('admin_approve_courier_payout','admin_reject_courier_payout',
                    'request_courier_payout','admin_resolve_package_dispute',
                    'is_admin','is_courier_role','complete_package_delivery')
ORDER BY p.proname;

-- 7) EXECUTE yetkileri (42501 teshisi).
SELECT routine_name, grantee, privilege_type
FROM information_schema.routine_privileges
WHERE routine_schema='public'
  AND routine_name IN ('admin_approve_courier_payout','admin_reject_courier_payout',
                       'request_courier_payout','admin_resolve_package_dispute')
ORDER BY routine_name, grantee;

-- 8) courier_id -> profiles FK var mi?
--    Yoksa admin panelin  profiles:courier_id(...)  embed'i PGRST200 verir.
SELECT c.conname, pg_get_constraintdef(c.oid) AS tanim
FROM pg_constraint c
JOIN pg_class t ON t.oid = c.conrelid
JOIN pg_namespace n ON n.oid = t.relnamespace
WHERE n.nspname='public'
  AND t.relname='courier_payout_requests'
  AND c.contype='f';

-- 9) Sikisip kalmis veri: 'requested' durumunda ama hicbir AKTIF payout
--    kalemine bagli olmayan kazanclar (yetim kayitlar).
SELECT ce.id, ce.courier_id, ce.amount, ce.status, ce.created_at
FROM public.courier_earnings ce
WHERE ce.status = 'requested'
  AND NOT EXISTS (
    SELECT 1 FROM public.courier_payout_items cpi
    JOIN public.courier_payout_requests cpr ON cpr.id = cpi.payout_id
    WHERE cpi.earning_id = ce.id AND cpr.status = 'pending'
  )
ORDER BY ce.created_at DESC
LIMIT 50;

-- 10) Mevcut payout istekleri ozeti.
SELECT status, count(*) AS adet, sum(amount) AS toplam
FROM public.courier_payout_requests
GROUP BY status
ORDER BY status;
