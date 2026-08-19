-- =============================================================================
-- Restore the pre-authentication registration OTP RPC contract.
--
-- Registration verification runs before sign-up, therefore PostgREST executes
-- this function as `anon`.  The original function migration relied on
-- PostgreSQL's implicit PUBLIC EXECUTE default instead of declaring the client
-- roles explicitly.  Security hardening removed that implicit privilege in
-- production, causing SQLSTATE 42501 before the function body was entered.
-- =============================================================================

DO $migration$
BEGIN
  IF to_regprocedure('public.verify_registration_otp(text,text)') IS NULL THEN
    RAISE EXCEPTION
      'Required function public.verify_registration_otp(text,text) is missing';
  END IF;
END
$migration$;

-- SECURITY DEFINER functions must not inherit a caller-controlled search_path.
ALTER FUNCTION public.verify_registration_otp(text, text)
  SET search_path = public, pg_temp;

-- Keep the function off the implicit PUBLIC surface and declare every intended
-- caller explicitly.  `anon` is required because verification precedes sign-up.
REVOKE ALL ON FUNCTION public.verify_registration_otp(text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.verify_registration_otp(text, text)
  TO anon, authenticated, service_role;

COMMENT ON FUNCTION public.verify_registration_otp(text, text) IS
  'Verifies a registration OTP before sign-up; intentionally executable by anon.';

NOTIFY pgrst, 'reload schema';
