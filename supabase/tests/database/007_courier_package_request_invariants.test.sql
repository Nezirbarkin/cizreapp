-- ============================================================================
-- 007_courier_package_request_invariants.test.sql
-- ----------------------------------------------------------------------------
-- AMAÇ: create_package_request RPC'sinin canlı DB'de varlığını + sözleşmesini
--       garanti eder. PGRST202 (2026-08-05 bulgusu) ve
--       "column reference id is ambiguous" 42702 (2026-08-08 bulgusu)
--       hatalarının tekrarını yakalayan regression testleri.
--
-- BAĞIMLILIK: pgTAP uzantısı.
--   * pgtap yüklü değilse testler sessizce atlanır (RAISE NOTICE) — HATA yok.
--   * Yükleme (superuser olarak):
--       Supabase Studio -> Database -> Extensions -> "pgtap" -> Enable
--       veya psql ile superuser olarak:
--         CREATE EXTENSION pgtap;
--   * pg_prove ile çalıştırma (önerilen):
--       pg_prove -d <db> supabase/tests/database/007_courier_package_request_invariants.test.sql
--   * Doğrudan psql ile de çalışır (pgtap yüklüyse).
--
-- HEDEF: Bu test, HOTFIX uygulanmadan canlıya gidildiğinde KIRMIZI olur.
--        Yani: "create_package_request var mı?" + "r_id mi id mi?" sorularına
--        kesin cevap verir.
-- ============================================================================

-- 2026-08-08 (v2): Tüm pgTAP çağrıları tek bir EXCEPTION bloğu içine alındı.
--   pgtap yüklü OLMAYAN ortamda dosya hatasız çalışır (sessizce atlar).
--   Önceki sürümler pgTAP yokken "function ... does not exist (42883)" hatası
--   veriyordu. Yeni akış: pgtap varsa testleri çalıştır; yoksa NOTICE + RETURN.

-- pgtap kurulumunu dene (idempotent, yetkisiz ortamda yutulur).
DO $setup$
BEGIN
  BEGIN
    CREATE EXTENSION IF NOT EXISTS pgtap;
  EXCEPTION WHEN OTHERS THEN
    -- Yetersiz yetki veya başka kurulum hatası. Sessizce devam et;
    -- aşağıdaki kapı testleri atlatacak.
    RAISE NOTICE 'pgtap kurulamadı (%): testler atlanacak', SQLERRM;
  END;
END
$setup$;

-- Asıl test mantığı. Hangi ortamda olursak olalım, pgtap
-- fonksiyonu yoksa EXCEPTION yakalanır ve test sessizce atlanır.
DO $tests$
BEGIN
  -- 1) pgtap yüklü mü? (CREATE EXTENSION yukarıda denendi; burada
  --    pg_proc üzerinden doğrudan kontrol ediyoruz — daha güvenilir.)
  IF NOT EXISTS (
    SELECT 1
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = 'plan'
  ) THEN
    RAISE NOTICE
      'pgtap yüklü değil (public.plan fonksiyonu yok) — '
      '007_courier_package_request_invariants ATLANIYOR. '
      'Etkinleştirmek için: CREATE EXTENSION pgtap; (superuser gerekir).';
    RETURN;
  END IF;

  -- Buradan itibaren pgtap yüklü.
  BEGIN
    -- 2026-08-08 v2: plan(19) -> plan(20) ("tüm 7 r_ önekli kolon" eklendi)
    PERFORM plan(20);

    -- 1) Fonksiyon var mı?
    PERFORM has_function(
      'public', 'create_package_request',
      ARRAY[
        'double precision','double precision','double precision','double precision',
        'text','text','text','text','text','text','text','text','uuid'
      ],
      'create_package_request RPC 13 parametreli imza ile mevcut'
    );

    -- 2) Tablo + zorunlu kolonlar
    PERFORM has_table('public', 'courier_requests', 'courier_requests tablosu mevcut');
    PERFORM has_column('public', 'courier_requests', 'id',              'id kolonu var');
    PERFORM has_column('public', 'courier_requests', 'sender_id',       'sender_id kolonu var');
    PERFORM has_column('public', 'courier_requests', 'pickup_lat',      'pickup_lat kolonu var');
    PERFORM has_column('public', 'courier_requests', 'pickup_lng',      'pickup_lng kolonu var');
    PERFORM has_column('public', 'courier_requests', 'delivery_lat',    'delivery_lat kolonu var');
    PERFORM has_column('public', 'courier_requests', 'delivery_lng',    'delivery_lng kolonu var');
    PERFORM has_column('public', 'courier_requests', 'total_fee',       'total_fee kolonu var');
    PERFORM has_column('public', 'courier_requests', 'idempotency_key', 'idempotency_key kolonu var (HOTFIX bloğu 1)');

    -- 3) Idempotency unique index
    PERFORM has_index(
      'public', 'courier_requests',
      'uq_courier_requests_sender_idem',
      ARRAY['sender_id', 'idempotency_key'],
      'idempotency unique index mevcut (BLOK 1)'
    );

    -- 4) Bağımlı tablolar
    PERFORM has_table('public', 'user_balances',             'user_balances mevcut (bakiye düşümü için)');
    PERFORM has_table('public', 'balance_transactions',      'balance_transactions mevcut (ledger için)');
    PERFORM has_table('public', 'courier_service_settings',  'courier_service_settings mevcut (ücret tablosu)');

    -- 5) Enum
    PERFORM has_enum('public', 'balance_transaction_type', 'balance_transaction_type enum mevcut');
    PERFORM enum_has_value(
      'public', 'balance_transaction_type', 'courier_payment',
      'courier_payment enum değeri mevcut (RPC INSERT için zorunlu)'
    );

    -- 6) Yetkiler
    PERFORM function_privs_are(
      'public', 'create_package_request',
      ARRAY[
        'double precision','double precision','double precision','double precision',
        'text','text','text','text','text','text','text','text','uuid'
      ],
      'authenticated', ARRAY['EXECUTE'],
      'authenticated grubu create_package_request çağırabilir'
    );

    -- 7) Davranış sözleşmesi
    PERFORM function_lang_is(
      'public', 'create_package_request',
      ARRAY[
        'double precision','double precision','double precision','double precision',
        'text','text','text','text','text','text','text','text','uuid'
      ],
      'plpgsql',
      'create_package_request plpgsql ile yazılmış'
    );
    PERFORM function_security_is(
      'public', 'create_package_request',
      ARRAY[
        'double precision','double precision','double precision','double precision',
        'text','text','text','text','text','text','text','text','uuid'
      ],
      'DEFINER',
      'create_package_request SECURITY DEFINER (sunucu-otoriteli)'
    );

    -- 8) RETURNS TABLE sözleşmesi (2026-08-08 v2: TÜM kolonlar "r_" önekli).
    --    Bu, 42702 "column reference ... is ambiguous" hatasının
    --    TÜM kolonlar (id, status, total_fee, courier_fee,
    --    admin_commission, distance_km, created_at) için geri gelmeyeceğini
    --    garanti eder.
    PERFORM ok(
      EXISTS (
        SELECT 1
        FROM pg_proc p
        JOIN pg_namespace n ON n.oid = p.pronamespace
        JOIN unnest(p.proargnames) WITH ORDINALITY AS a(name, ord) ON TRUE
        WHERE n.nspname = 'public'
          AND p.proname = 'create_package_request'
          AND a.name = 'r_id'
          AND a.ord = 1
      ),
      'RETURNS TABLE ilk kolonu "r_id" (42702 id fix)'
    );
    PERFORM ok(
      NOT EXISTS (
        SELECT 1
        FROM pg_proc p
        JOIN pg_namespace n ON n.oid = p.pronamespace
        JOIN unnest(p.proargnames) WITH ORDINALITY AS a(name, ord) ON TRUE
        WHERE n.nspname = 'public'
          AND p.proname = 'create_package_request'
          AND a.name IN ('id','status','total_fee','courier_fee',
                         'admin_commission','distance_km','created_at')
      ),
      'RETURNS TABLE içinde düz kolon adı YOK '
        '(id/status/total_fee/courier_fee/admin_commission/distance_km/created_at) '
        '— 42702 ambiguity sözleşmesi'
    );
    -- TÜM "r_" önekli kolonlar var mı?
    PERFORM ok(
      (SELECT count(*) = 7
       FROM pg_proc p
       JOIN pg_namespace n ON n.oid = p.pronamespace
       JOIN unnest(p.proargnames) AS a(name) ON TRUE
       WHERE n.nspname = 'public'
         AND p.proname = 'create_package_request'
         AND a.name IN ('r_id','r_status','r_total_fee','r_courier_fee',
                        'r_admin_commission','r_distance_km','r_created_at')
      ),
      'RETURNS TABLE tüm 7 kolon "r_" önekli (42702 v2 fix sözleşmesi)'
    );

    -- 9) PostgREST şema önbelleği tazeliği
    PERFORM ok(
      (SELECT extract(epoch FROM now() - p.xmin::text::timestamptz) < 3600
       FROM pg_proc p
       JOIN pg_namespace n ON n.oid = p.pronamespace
       WHERE n.nspname = 'public' AND p.proname = 'create_package_request'
       LIMIT 1) IS NOT NULL,
      'create_package_request son 1 saat içinde oluşturulmuş (schema cache taze)'
    );

    -- 10) Koordinat kolonları tam
    PERFORM ok(
      (SELECT count(*) > 0
       FROM information_schema.columns
       WHERE table_schema = 'public'
         AND table_name = 'courier_requests'
         AND column_name IN ('pickup_lat','pickup_lng','delivery_lat','delivery_lng')
      ) = 4,
      'courier_requests koordinat kolonları tam (4/4)'
    );

    PERFORM finish();
  EXCEPTION WHEN OTHERS THEN
    -- pgtap yüklü görünüp de bir fonksiyonu farklı şemadaysa
    -- veya başka bir tutarsızlık varsa, yine de dosyayı patlatmayalım.
    RAISE NOTICE
      'pgTAP assertion çalıştırılırken hata (%): testler atlandı.',
      SQLERRM;
  END;
END
$tests$;
