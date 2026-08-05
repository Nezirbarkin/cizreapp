-- ============================================================================
-- ADIM 1B - FONKSIYON IKIZLERI + MIGRATION DEFTERI (salt-okunur)
-- Tarih: 2026-08-05
-- ----------------------------------------------------------------------------
-- Adim 1 sonucu: checkout RPC'leri HEM public HEM private semasinda duruyor.
-- Bu sorgu, public kopyalarin ne oldugunu netlestirir:
--   - private'e delege eden ince bir wrapper mi?
--   - yoksa bagimsiz (muhtemelen eski) bir implementasyon mu?
-- Adim 2'de yazilacak duzeltme migration'inin sekli buna bagli.
--
-- KULLANIM: Supabase SQL Editor'de F ve G bloklarini calistir, ciktilari yapistir.
-- GUVENLIK: Sadece SELECT. Hicbir DDL/DML yok.
-- ============================================================================


-- ============================================================================
-- BLOK F - CHECKOUT RPC IKIZLERI (public vs private)
-- ============================================================================
SELECT
  p.proname                                    AS fonksiyon,
  n.nspname                                    AS sema,
  pg_get_function_identity_arguments(p.oid)    AS imza,
  CASE WHEN p.prosecdef THEN 'DEFINER' ELSE 'INVOKER' END AS security,
  CASE WHEN has_function_privilege('authenticated', p.oid, 'EXECUTE')
       THEN 'evet' ELSE 'HAYIR' END            AS auth_execute,
  length(p.prosrc)                             AS govde_uzunlugu,
  -- Govde private'e delege ediyorsa wrapper'dir:
  CASE WHEN p.prosrc ILIKE '%private.%' THEN 'private''e delege ediyor'
       ELSE 'bagimsiz implementasyon' END      AS tur,
  left(regexp_replace(p.prosrc, '\s+', ' ', 'g'), 180) AS govde_ilk_180
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname IN ('public', 'private')
  AND p.proname IN (
    'prepare_checkout_session',
    'commit_cod_order',
    'commit_balance_order',
    'commit_online_order',
    'use_coupon',
    'validate_coupon'
  )
ORDER BY p.proname, n.nspname;


-- ============================================================================
-- BLOK G - MIGRATION DEFTERINDE KAYITLI TUM SURUMLER
-- Adim 1'de "13 kayit / en son 20240123000009" cikti. Repoda 333 dosya var.
-- Defterin gercekte ne bildigini gormek icin tam liste:
-- ============================================================================
SELECT
  count(*)                                          AS kayitli_migration,
  min(version)                                      AS en_eski,
  max(version)                                      AS en_yeni,
  string_agg(version, ', ' ORDER BY version)        AS tum_surumler
FROM supabase_migrations.schema_migrations;
