-- =============================================================================
-- 'driver' rolü ekleme (kompozit yaklaşım)
-- =============================================================================
-- Hem user_role ENUM tipine hem de profiles.role/users.role CHECK constraint'lerine
-- 'driver' ekler. Hangisi tabloda kullanılıyorsa o çalışır.

DO $$
BEGIN
  -- 1) Eğer user_role ENUM tipi varsa, 'driver' değerini ekle
  IF EXISTS (SELECT 1 FROM pg_type WHERE typname = 'user_role') THEN
    -- ALTER TYPE ... ADD VALUE transaction dışında çalışmalı
    BEGIN
      ALTER TYPE public.user_role ADD VALUE IF NOT EXISTS 'driver';
    EXCEPTION WHEN OTHERS THEN
      RAISE NOTICE 'user_role ENUM güncellenemedi: %', SQLERRM;
    END;
  END IF;
END $$;

-- 2) profiles.role CHECK constraint (eğer text üzerindeyse)
DO $$
DECLARE
  v_constraint TEXT;
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'profiles' AND column_name = 'role'
  ) THEN
    -- ENUM mı, text mi?
    IF EXISTS (
      SELECT 1 FROM information_schema.columns c
      JOIN pg_type t ON t.typname = c.udt_name
      WHERE c.table_schema = 'public' AND c.table_name = 'profiles' AND c.column_name = 'role'
        AND t.typtype = 'e'
    ) THEN
      -- ENUM: zaten yukarıda eklendi
      RAISE NOTICE 'profiles.role bir ENUM; user_role güncellendi.';
    ELSE
      -- TEXT: CHECK constraint güncelle
      SELECT conname INTO v_constraint
      FROM pg_constraint
      WHERE conrelid = 'public.profiles'::regclass
        AND contype = 'c'
        AND pg_get_constraintdef(oid) ILIKE '%role%';

      IF v_constraint IS NOT NULL THEN
        EXECUTE format('ALTER TABLE public.profiles DROP CONSTRAINT %I', v_constraint);
      END IF;

      ALTER TABLE public.profiles
        ADD CONSTRAINT profiles_role_check
        CHECK (role IN ('customer', 'seller', 'admin', 'courier', 'driver'));
      RAISE NOTICE 'profiles.role TEXT — CHECK constraint güncellendi.';
    END IF;
  END IF;
END $$;

-- 3) users.role (eğer Supabase auth.users değil de public.users ise)
DO $$
DECLARE
  v_constraint TEXT;
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'users' AND column_name = 'role'
      AND table_schema <> 'auth'
  ) THEN
    IF EXISTS (
      SELECT 1 FROM information_schema.columns c
      JOIN pg_type t ON t.typname = c.udt_name
      WHERE c.table_schema = 'public' AND c.table_name = 'users' AND c.column_name = 'role'
        AND t.typtype = 'e'
    ) THEN
      RAISE NOTICE 'public.users.role ENUM; user_role güncellendi.';
    ELSE
      SELECT conname INTO v_constraint
      FROM pg_constraint
      WHERE conrelid = 'public.users'::regclass
        AND contype = 'c'
        AND pg_get_constraintdef(oid) ILIKE '%role%';

      IF v_constraint IS NOT NULL THEN
        EXECUTE format('ALTER TABLE public.users DROP CONSTRAINT %I', v_constraint);
      END IF;

      ALTER TABLE public.users
        ADD CONSTRAINT users_role_check
        CHECK (role IN ('customer', 'seller', 'admin', 'courier', 'driver'));
      RAISE NOTICE 'public.users.role TEXT — CHECK constraint güncellendi.';
    END IF;
  END IF;
END $$;
