-- =============================================================================
-- admin_scan_fraud_signals: risk_score bigint -> integer tip uyuşmazlığı
-- =============================================================================
-- 20260907140001 search_path'i düzeltince altından ikinci bir hata çıktı:
--
--   ERROR: function public.upsert_fraud_signal(uuid, unknown, text, bigint,
--          unknown, ...) does not exist
--
-- NEDEN: `upsert_fraud_signal` dördüncü parametreyi (p_risk_score) INTEGER
-- bekliyor. Ancak tarama sorgularındaki sayaçlar `count(*)` üzerinden geldiği
-- için BIGINT; `least(100, 40 + (account_count * 15))` ifadesi de bigint
-- üretiyor. PostgreSQL fonksiyon çözümlemesinde bigint -> integer örtük
-- daraltma yapmaz, bu yüzden dört çağrının DÖRDÜ de patlıyordu.
--
-- Yani admin panelindeki "Dolandırıcılık Sinyalleri" taraması hiçbir zaman
-- çalışmamış: multiple_accounts, unusual_returns, coupon_abuse ve
-- fake_reviews kurallarının tamamı bu satırlarda düşüyordu.
--
-- ÇÖZÜM: Fonksiyon tanımı DB'den okunur, dört risk_score ifadesi
-- ::integer ile sarmalanır ve fonksiyon yeniden yaratılır. Gövde elle
-- kopyalanmadığı için geri kalan mantık bit düzeyinde korunur.
-- =============================================================================

DO $$
DECLARE
  v_def      text;
  v_before   text;
  v_replaced integer := 0;
  v_pairs    text[][] := ARRAY[
    ['least(100, 40 + (v_row.account_count * 15))',
     '(least(100, 40 + (v_row.account_count * 15)))::integer'],
    ['least(100, 35 + (v_row.return_count * 7) + round(v_row.return_ratio * 20)::integer)',
     '(least(100, 35 + (v_row.return_count * 7) + round(v_row.return_ratio * 20)::integer))::integer'],
    ['least(100, 30 + (v_row.usage_count * 5) + least(25, floor(v_row.total_discount / 100)::integer))',
     '(least(100, 30 + (v_row.usage_count * 5) + least(25, floor(v_row.total_discount / 100)::integer)))::integer'],
    ['least(100, 35 + (v_row.review_count * 5))',
     '(least(100, 35 + (v_row.review_count * 5)))::integer']
  ];
  i integer;
BEGIN
  SELECT pg_get_functiondef(p.oid)
    INTO v_def
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public'
     AND p.proname = 'admin_scan_fraud_signals'
     AND p.pronargs = 0;

  IF v_def IS NULL THEN
    RAISE EXCEPTION 'admin_scan_fraud_signals() bulunamadi';
  END IF;

  FOR i IN 1 .. array_length(v_pairs, 1) LOOP
    v_before := v_def;
    v_def := replace(v_def, v_pairs[i][1], v_pairs[i][2]);
    IF v_def <> v_before THEN
      v_replaced := v_replaced + 1;
    END IF;
  END LOOP;

  -- Fonksiyon daha önce yamalanmışsa hicbir eslesme olmaz; bu bir hata degil.
  IF v_replaced = 0 THEN
    RAISE NOTICE 'admin_scan_fraud_signals zaten yamali, degisiklik yok';
    RETURN;
  END IF;

  IF v_replaced <> 4 THEN
    RAISE EXCEPTION
      'Beklenen 4 risk_score ifadesinden yalniz %s eslesti; gövde degismis olabilir. Migration durduruldu.',
      v_replaced;
  END IF;

  EXECUTE v_def;
  RAISE NOTICE 'admin_scan_fraud_signals: 4 risk_score ifadesi ::integer ile sarmalandi';
END $$;

NOTIFY pgrst, 'reload schema';
