-- =============================================================================
-- SUPABASE PERFORMANCE ADVISOR: auth_rls_initplan + multiple_permissive_policies
--                               + duplicate_index
-- =============================================================================
-- Bu migration Performance Advisor'in bildirdigi uc lint ailesini kapatir:
--
--   1) auth_rls_initplan            -> auth.<fn>() cagrilarini (SELECT ...) ile
--                                      sarmalayarak satir basina degil, sorgu
--                                      basina bir kez calismalarini saglar.
--   2) multiple_permissive_policies -> ayni (tablo, komut, rol) uclusune bakan
--                                      permissive policy'leri tek policy'de
--                                      OR ile birlestirir.
--   3) duplicate_index              -> ayni sutun setini indeksleyen ikiz
--                                      indekslerden fazlaligi dusurur.
--
-- NEDEN KATALOG UZERINDEN CALISIYOR
-- ---------------------------------
-- Canli veritabanindaki policy seti bu depodaki migration gecmisinden sapmis
-- durumda (ornegin Advisor'in raporladigi `orders."Users can view own orders"`
-- policy'si dosyalarda 2024'te DROP edilmis gorunuyor, ama canlida duruyor).
-- Bu yuzden ifadeler dosyalardan tahmin edilmiyor; her ifade calisma aninda
-- pg_policy katalogundan okunup ayni anlamla geri yaziliyor.
--
-- ANLAM KORUNUMU
-- --------------
-- PostgreSQL, bir (komut, rol) ciftine bakan permissive policy'leri OR ile
-- birlestirir:  izin = (q1 OR q2 OR ... OR qN) AND (restrictive'lerin AND'i)
-- Dolayisiyla N permissive policy'yi qual'i "q1 OR ... OR qN" olan tek bir
-- permissive policy ile degistirmek birebir ayni yetki kumesini verir.
-- Birlestirme yalnizca ROL KUMESI BIREBIR AYNI olan policy'ler arasinda
-- yapilir; farkli rol kumeleri (ornegin TO public + TO authenticated) asla
-- birlestirilmez, cunku bu erisimi genisletirdi.
--
-- FOR ALL POLICY'LERI
-- -------------------
-- `FOR ALL USING (q) WITH CHECK (c)` ile su dort policy birebir esdegerdir:
--   SELECT USING (q) / DELETE USING (q) / INSERT WITH CHECK (c)
--   UPDATE USING (q) WITH CHECK (c)
-- (WITH CHECK yazilmamissa c = q.) Bir ALL policy'si yalnizca boyle bolununce
-- bir birlestirme mumkun hale geliyorsa bolunur; aksi halde dokunulmaz.
--
-- KAPSAM DISI (bilerek)
-- ---------------------
-- Rol kumeleri farkli olan permissive policy ciftleri birlestirilmez. Bunlari
-- tek policy'de toplamak ifadeye `pg_has_role(...)` gibi bir rol muhafizi
-- eklemeyi gerektirir; kazanci kucuk, yetki hatasi riski buyuk oldugu icin
-- bilincli olarak yapilmadi. Kalan uyarilar migration sonunda NOTICE olarak
-- listelenir.
-- =============================================================================

SET LOCAL search_path = public;

-- -----------------------------------------------------------------------------
-- 0) Yardimci: auth.<fn>() cagrilarini InitPlan'e ceviren metin donusumu.
--    Once sarilmis olanlari acar, sonra hepsini tek tip sarar; boylece
--    migration tekrar calistirilsa bile sonuc ayni kalir (idempotent).
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.__advisor_wrap_auth_calls(expr text)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $fn$
  SELECT CASE
    WHEN expr IS NULL THEN NULL
    ELSE regexp_replace(
           regexp_replace(
             expr,
             -- "( SELECT auth.uid() AS uid)" -> "auth.uid()"
             '\(\s*SELECT\s+(auth\.(?:uid|role|jwt|email)\(\))\s+AS\s+[a-z_]+\s*\)',
             '\1',
             'gi'
           ),
           -- "auth.uid()" -> "(SELECT auth.uid())"
           '(auth\.(?:uid|role|jwt|email)\(\))',
           '(SELECT \1)',
           'g'
         )
  END
$fn$;

-- =============================================================================
-- 1) auth_rls_initplan
-- =============================================================================
DO $initplan$
DECLARE
  pol        record;
  new_qual   text;
  new_check  text;
  stmt       text;
  fixed      integer := 0;
BEGIN
  FOR pol IN
    SELECT
      c.relname::text                             AS tablename,
      p.polname::text                             AS policyname,
      pg_get_expr(p.polqual, p.polrelid)          AS qual,
      pg_get_expr(p.polwithcheck, p.polrelid)     AS with_check
    FROM pg_policy p
    JOIN pg_class     c ON c.oid = p.polrelid
    JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'public'
      -- Yalnizca HENUZ sarilmamis bir auth cagrisi iceren policy'ler. Negatif
      -- lookbehind, katalogdaki "( SELECT auth.uid() AS uid)" bicimini eler;
      -- boylece migration ikinci kez calistiginda gercek bir no-op olur.
      AND (
        coalesce(pg_get_expr(p.polqual, p.polrelid), '')
          ~ '(?<!SELECT )auth\.(?:uid|role|jwt|email)\(\)'
        OR coalesce(pg_get_expr(p.polwithcheck, p.polrelid), '')
          ~ '(?<!SELECT )auth\.(?:uid|role|jwt|email)\(\)'
      )
    ORDER BY c.relname, p.polname
  LOOP
    new_qual  := public.__advisor_wrap_auth_calls(pol.qual);
    new_check := public.__advisor_wrap_auth_calls(pol.with_check);

    CONTINUE WHEN new_qual  IS NOT DISTINCT FROM pol.qual
              AND new_check IS NOT DISTINCT FROM pol.with_check;

    -- Yalnizca policy'de zaten var olan cumleleri yeniden yaz. Boylece
    -- WITH CHECK'i olmayan bir UPDATE/ALL policy'sinde "WITH CHECK = USING"
    -- varsayilan davranisi bozulmaz.
    stmt := format('ALTER POLICY %I ON public.%I', pol.policyname, pol.tablename);
    IF pol.qual IS NOT NULL THEN
      stmt := stmt || format(' USING (%s)', new_qual);
    END IF;
    IF pol.with_check IS NOT NULL THEN
      stmt := stmt || format(' WITH CHECK (%s)', new_check);
    END IF;

    EXECUTE stmt;
    fixed := fixed + 1;
    RAISE NOTICE 'initplan: public.% -> %', pol.tablename, pol.policyname;
  END LOOP;

  RAISE NOTICE 'auth_rls_initplan: % policy yeniden yazildi.', fixed;
END
$initplan$;

-- =============================================================================
-- 2) multiple_permissive_policies
-- =============================================================================
DO $merge$
DECLARE
  grp        record;
  pol        record;
  merged_sql text;
  clash      text;
  merged_ct  integer := 0;
  dropped_ct integer := 0;
BEGIN
  -- ---------------------------------------------------------------------------
  -- 2a) Katalogdaki permissive policy'lerin anlik goruntusu.
  -- ---------------------------------------------------------------------------
  CREATE TEMP TABLE _advisor_src ON COMMIT DROP AS
  SELECT
    c.relname::text                          AS tablename,
    p.polname::text                          AS policyname,
    p.polcmd                                 AS polcmd,
    pg_get_expr(p.polqual, p.polrelid)       AS qual,
    pg_get_expr(p.polwithcheck, p.polrelid)  AS with_check,
    CASE
      WHEN p.polroles = '{0}'::oid[] THEN ARRAY['public']
      ELSE (
        SELECT array_agg(r.rolname::text ORDER BY r.rolname)
        FROM unnest(p.polroles) AS u(oid)
        JOIN pg_roles r ON r.oid = u.oid
      )
    END                                      AS roles
  FROM pg_policy p
  JOIN pg_class     c ON c.oid = p.polrelid
  JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'public'
    AND p.polpermissive;

  -- ---------------------------------------------------------------------------
  -- 2b) ALL policy'lerini dort komuta acarak "etkin policy" tablosu kur.
  --     eff_qual  : SELECT/UPDATE/DELETE icin USING ifadesi
  --     eff_check : INSERT/UPDATE icin WITH CHECK ifadesi
  --
  --     Iki NULL kurali dogrulanmis PostgreSQL davranisidir:
  --       1) WITH CHECK yazilmamissa kontrol USING'e duser.
  --          -> COALESCE(with_check, qual).  Bu atlanip yerine TRUE konursa
  --             `FOR ALL USING (admin)` gibi bir policy bolununce INSERT
  --             tarafi herkese acilir.
  --       2) USING yazilmamissa policy permissive OR'a HICBIR SEY katmaz;
  --          yani TRUE degil, etkisizdir (tek basina bile satir dondurmez).
  --          -> NULL oldugu gibi korunur, asagida OR'a alinmaz ve grubun
  --             tamami NULL ise ilgili cumle hic yazilmaz.
  -- ---------------------------------------------------------------------------
  CREATE TEMP TABLE _advisor_eff ON COMMIT DROP AS
  SELECT
    s.tablename,
    s.policyname,
    s.roles,
    x.cmd,
    (s.polcmd = '*')                                   AS from_all,
    CASE WHEN x.cmd IN ('SELECT', 'UPDATE', 'DELETE')
         THEN s.qual END                               AS eff_qual,
    CASE WHEN x.cmd IN ('INSERT', 'UPDATE')
         THEN COALESCE(s.with_check, s.qual) END       AS eff_check
  FROM _advisor_src s
  CROSS JOIN LATERAL unnest(
    CASE s.polcmd
      WHEN '*' THEN ARRAY['SELECT', 'INSERT', 'UPDATE', 'DELETE']
      WHEN 'r' THEN ARRAY['SELECT']
      WHEN 'a' THEN ARRAY['INSERT']
      WHEN 'w' THEN ARRAY['UPDATE']
      WHEN 'd' THEN ARRAY['DELETE']
    END
  ) AS x(cmd);

  -- ---------------------------------------------------------------------------
  -- 2c) Hangi ALL policy'si bolunmeli?  En az bir (tablo, komut, rol) grubunda
  --     baska bir policy ile cakisan ALL policy'leri.
  -- ---------------------------------------------------------------------------
  CREATE TEMP TABLE _advisor_split ON COMMIT DROP AS
  SELECT DISTINCT e.tablename, e.policyname
  FROM _advisor_eff e
  WHERE e.from_all
    AND EXISTS (
      SELECT 1
      FROM _advisor_eff o
      WHERE o.tablename = e.tablename
        AND o.cmd       = e.cmd
        AND o.roles     = e.roles
        AND o.policyname <> e.policyname
    );

  -- ---------------------------------------------------------------------------
  -- 2d) Bolunmeyecek ALL policy'lerini kapsam disina al.
  -- ---------------------------------------------------------------------------
  DELETE FROM _advisor_eff e
  WHERE e.from_all
    AND NOT EXISTS (
      SELECT 1 FROM _advisor_split s
      WHERE s.tablename = e.tablename AND s.policyname = e.policyname
    );

  -- ---------------------------------------------------------------------------
  -- 2e) Islenecek gruplar: birden fazla uyesi olanlar ve bolunen bir ALL
  --     policy'sinin tek basina kaldigi gruplar (bunlar da yeniden kurulmali,
  --     yoksa ALL policy'si dusunce o komuttaki yetki kaybolur).
  -- ---------------------------------------------------------------------------
  CREATE TEMP TABLE _advisor_grp ON COMMIT DROP AS
  SELECT
    e.tablename,
    e.cmd,
    e.roles,
    count(*)                                        AS member_count,
    bool_or(e.from_all)                             AS has_split_all,
    -- Ayni ifadeyi tekrar tekrar OR'lamamak icin tekillestir.
    array_agg(DISTINCT e.eff_qual)  FILTER (WHERE e.eff_qual  IS NOT NULL) AS quals,
    array_agg(DISTINCT e.eff_check) FILTER (WHERE e.eff_check IS NOT NULL) AS checks
  FROM _advisor_eff e
  GROUP BY e.tablename, e.cmd, e.roles
  HAVING count(*) > 1 OR bool_or(e.from_all);

  -- ---------------------------------------------------------------------------
  -- 2f) Birlestirilmis policy adlarini uret ve cakismalari yakala.
  -- ---------------------------------------------------------------------------
  ALTER TABLE _advisor_grp ADD COLUMN new_name text;

  UPDATE _advisor_grp g
  SET new_name = left(
        format('%s_%s_merged', g.tablename, lower(g.cmd))
        || CASE
             WHEN (SELECT count(DISTINCT g2.roles)
                   FROM _advisor_grp g2
                   WHERE g2.tablename = g.tablename AND g2.cmd = g.cmd) > 1
             THEN '_' || substr(md5(g.roles::text), 1, 8)
             ELSE ''
           END,
        63);

  SELECT string_agg(format('%s.%s', g.tablename, g.new_name), ', ')
  INTO clash
  FROM _advisor_grp g
  WHERE EXISTS (
    SELECT 1
    FROM _advisor_src s
    WHERE s.tablename = g.tablename
      AND s.policyname = g.new_name
      AND NOT EXISTS (
        SELECT 1 FROM _advisor_eff e
        WHERE e.tablename = g.tablename
          AND e.policyname = s.policyname
          AND e.cmd = g.cmd
          AND e.roles = g.roles
      )
  );

  IF clash IS NOT NULL THEN
    RAISE EXCEPTION 'Birlestirilmis policy adi mevcut bir policy ile cakisiyor: %', clash;
  END IF;

  -- ---------------------------------------------------------------------------
  -- 2g) Islenen gruplardaki tum policy'leri dusur.
  -- ---------------------------------------------------------------------------
  FOR pol IN
    SELECT DISTINCT e.tablename, e.policyname
    FROM _advisor_eff e
    JOIN _advisor_grp g
      ON g.tablename = e.tablename AND g.cmd = e.cmd AND g.roles = e.roles
    ORDER BY 1, 2
  LOOP
    EXECUTE format('DROP POLICY %I ON public.%I', pol.policyname, pol.tablename);
    dropped_ct := dropped_ct + 1;
    RAISE NOTICE 'merge: DROP public.%.%', pol.tablename, pol.policyname;
  END LOOP;

  -- ---------------------------------------------------------------------------
  -- 2h) Grup basina tek permissive policy kur.
  -- ---------------------------------------------------------------------------
  FOR grp IN
    SELECT * FROM _advisor_grp ORDER BY tablename, cmd, roles
  LOOP
    merged_sql := format(
      'CREATE POLICY %I ON public.%I AS PERMISSIVE FOR %s TO %s',
      grp.new_name,
      grp.tablename,
      grp.cmd,
      (SELECT string_agg(quote_ident(r), ', ' ORDER BY r) FROM unnest(grp.roles) AS r)
    );

    -- grp.quals / grp.checks yalnizca NULL olmayan ifadeleri tasir. Tamami
    -- NULL ise dizi de NULL olur ve ilgili cumle hic yazilmaz; boylece
    -- "USING yok" davranisi birebir korunur.
    IF grp.cmd IN ('SELECT', 'UPDATE', 'DELETE') AND grp.quals IS NOT NULL THEN
      merged_sql := merged_sql || format(
        ' USING (%s)',
        (SELECT string_agg(format('(%s)', q), ' OR ') FROM unnest(grp.quals) AS q)
      );
    END IF;

    IF grp.cmd IN ('INSERT', 'UPDATE') AND grp.checks IS NOT NULL THEN
      merged_sql := merged_sql || format(
        ' WITH CHECK (%s)',
        (SELECT string_agg(format('(%s)', c), ' OR ') FROM unnest(grp.checks) AS c)
      );
    END IF;

    EXECUTE merged_sql;
    merged_ct := merged_ct + 1;
    RAISE NOTICE 'merge: CREATE public.%.% (% policy -> 1, % icin)',
      grp.tablename, grp.new_name, grp.member_count, grp.cmd;
  END LOOP;

  RAISE NOTICE 'multiple_permissive_policies: % policy dusuruldu, % birlesik policy kuruldu.',
    dropped_ct, merged_ct;
END
$merge$;

-- =============================================================================
-- 3) duplicate_index
-- =============================================================================
-- Ayni sutun setini/predicate'ini indeksleyen ikizlerden birini dusur.
-- Constraint'e bagli indeks korunur; dusurulen daima cift olmayan taraftir.
-- =============================================================================
DO $dupidx$
DECLARE
  dup     record;
  dropped integer := 0;
BEGIN
  FOR dup IN
    WITH idx AS (
      SELECT
        i.indexrelid,
        c.relname::text  AS indexname,
        t.relname::text  AS tablename,
        i.indrelid,
        -- Ayniligi indeks tanimindan (isim haric) tespit et.
        regexp_replace(
          pg_get_indexdef(i.indexrelid),
          '^CREATE (UNIQUE )?INDEX \S+ ON ',
          ''
        )                AS shape,
        (con.oid IS NOT NULL) AS constraint_backed
      FROM pg_index i
      JOIN pg_class     c ON c.oid = i.indexrelid
      JOIN pg_class     t ON t.oid = i.indrelid
      JOIN pg_namespace n ON n.oid = t.relnamespace
      LEFT JOIN pg_constraint con
             ON con.conindid = i.indexrelid AND con.contype IN ('p', 'u', 'x')
      WHERE n.nspname = 'public'
    )
    SELECT indexname, tablename
    FROM (
      SELECT
        idx.*,
        row_number() OVER (
          PARTITION BY indrelid, shape
          -- Constraint'e bagli olan once gelir => o korunur.
          ORDER BY constraint_backed DESC, indexname
        ) AS rn
      FROM idx
    ) ranked
    WHERE rn > 1
      AND NOT constraint_backed
    ORDER BY tablename, indexname
  LOOP
    EXECUTE format('DROP INDEX IF EXISTS public.%I', dup.indexname);
    dropped := dropped + 1;
    RAISE NOTICE 'duplicate_index: DROP public.% (tablo: %)', dup.indexname, dup.tablename;
  END LOOP;

  RAISE NOTICE 'duplicate_index: % ikiz indeks dusuruldu.', dropped;
END
$dupidx$;

-- =============================================================================
-- 4) Kalan uyarilarin raporu (rol kumesi farkli oldugu icin birlestirilmeyenler)
-- =============================================================================
DO $report$
DECLARE
  leftover text;
BEGIN
  SELECT string_agg(line, E'\n' ORDER BY line)
  INTO leftover
  FROM (
    SELECT format('  %s / %s / %s  (%s)',
                  e.tablename, e.cmd, e.rolname,
                  string_agg(DISTINCT e.policyname, ', ')) AS line
    FROM (
      SELECT
        c.relname::text AS tablename,
        p.polname::text AS policyname,
        x.cmd,
        r.rolname::text AS rolname
      FROM pg_policy p
      JOIN pg_class     c ON c.oid = p.polrelid
      JOIN pg_namespace n ON n.oid = c.relnamespace
      CROSS JOIN LATERAL unnest(
        CASE p.polcmd
          WHEN '*' THEN ARRAY['SELECT', 'INSERT', 'UPDATE', 'DELETE']
          WHEN 'r' THEN ARRAY['SELECT']
          WHEN 'a' THEN ARRAY['INSERT']
          WHEN 'w' THEN ARRAY['UPDATE']
          WHEN 'd' THEN ARRAY['DELETE']
        END
      ) AS x(cmd)
      -- Advisor uyarilari rol bazinda uretilir ve TO PUBLIC bir policy her role
      -- uygulanir. Bu yuzden 'public' burada, tabloda gercekten yetkisi olan
      -- somut rollere aciliyor -- aksi halde kalan uyarilar eksik sayilir.
      JOIN pg_roles r
        ON r.rolname NOT LIKE 'pg\_%'
       AND NOT r.rolsuper
       AND (
             p.polroles = '{0}'::oid[]
             OR r.oid = ANY (p.polroles)
           )
       AND has_table_privilege(r.oid, c.oid, 'SELECT, INSERT, UPDATE, DELETE')
      WHERE n.nspname = 'public' AND p.polpermissive
    ) e
    GROUP BY e.tablename, e.cmd, e.rolname
    HAVING count(DISTINCT e.policyname) > 1
  ) s;

  IF leftover IS NULL THEN
    RAISE NOTICE 'multiple_permissive_policies: kalan uyari yok.';
  ELSE
    RAISE NOTICE E'multiple_permissive_policies: rol kumeleri farkli oldugu icin birlestirilmeyenler:\n%',
      leftover;
  END IF;
END
$report$;

DROP FUNCTION IF EXISTS public.__advisor_wrap_auth_calls(text);
