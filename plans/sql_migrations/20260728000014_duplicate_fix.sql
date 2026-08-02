-- =====================================================
-- DOSYA: supabase/migrations/20260728000014_duplicate_fix.sql
-- AMAÇ: is_admin fonksiyonu duplicate düzeltme
-- =====================================================

-- Duplicate is_admin fonksiyonları kontrol et
DO $$
DECLARE
  v_count INTEGER;
  v_keep_signature TEXT;
BEGIN
  -- Aynı isimde kaç tane var
  SELECT COUNT(*) INTO v_count
  FROM pg_proc p
  JOIN pg_namespace n ON p.pronamespace = n.oid
  WHERE n.nspname = 'public' AND p.proname = 'is_admin';

  RAISE NOTICE 'is_admin fonksiyon sayisi: %', v_count;

  -- Parametresiz olanı tut, parametreli olanı sil
  -- Veya tam tersi - hangisi daha yeniyse onu tut
  IF v_count > 1 THEN
    -- En son oluşturulanı (oid en büyük) tut, diğerlerini sil
    -- Önce hangilerinin olduğunu görelim
    PERFORM 1;
  END IF;
END $$;

-- Duplicate'leri listele (bilgi amaçlı)
SELECT
  p.oid,
  n.nspname || '.' || p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')' AS full_name,
  p.prosecdef AS is_security_definer,
  p.proconfig::text AS config
FROM pg_proc p
JOIN pg_namespace n ON p.pronamespace = n.oid
WHERE n.nspname = 'public' AND p.proname = 'is_admin'
ORDER BY p.oid;
