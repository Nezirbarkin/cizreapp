-- =============================================================================
-- Registration OTP RPC: authorization and behavior regression tests (pgTAP)
--
-- The RPC is intentionally callable before authentication.  These tests cover
-- the production 42501 regression and the one-time/expiry behavior together.
-- =============================================================================

begin;

create extension if not exists pgtap with schema extensions;

select plan(11);

select ok(
  has_function_privilege(
    'anon',
    'public.verify_registration_otp(text,text)',
    'EXECUTE'
  ),
  'anon has explicit/effective EXECUTE for pre-sign-up verification'
);

select ok(
  not has_function_privilege(
    'public',
    'public.verify_registration_otp(text,text)',
    'EXECUTE'
  ),
  'implicit PUBLIC EXECUTE remains revoked'
);

-- Seed data as the test owner.  The transaction is rolled back at the end.
insert into public.registration_otps (
  email,
  code,
  verified,
  created_at,
  expires_at
) values
  (
    'pgtap-registration-valid@example.invalid',
    '135790',
    false,
    now(),
    now() + interval '5 minutes'
  ),
  (
    'pgtap-registration-expired@example.invalid',
    '246802',
    false,
    now() - interval '10 minutes',
    now() - interval '5 minutes'
  );

set local role anon;

select lives_ok(
  $$select public.verify_registration_otp(
      'pgtap-registration-missing@example.invalid',
      '000000'
    )$$,
  'anon call reaches the function instead of failing with SQLSTATE 42501'
);

select is(
  (public.verify_registration_otp(
    'pgtap-registration-missing@example.invalid',
    '000000'
  ) ->> 'success')::boolean,
  false,
  'unknown OTP is rejected'
);

select is(
  (public.verify_registration_otp(
    'pgtap-registration-valid@example.invalid',
    '999999'
  ) ->> 'success')::boolean,
  false,
  'wrong OTP code is rejected'
);

select is(
  (public.verify_registration_otp(
    'PGTAP-REGISTRATION-VALID@EXAMPLE.INVALID',
    '135790'
  ) ->> 'success')::boolean,
  true,
  'valid OTP is accepted with normalized email matching'
);

select is(
  (public.verify_registration_otp(
    'pgtap-registration-valid@example.invalid',
    '135790'
  ) ->> 'success')::boolean,
  false,
  'a consumed OTP cannot be reused'
);

select is(
  (public.verify_registration_otp(
    'pgtap-registration-expired@example.invalid',
    '246802'
  ) ->> 'success')::boolean,
  false,
  'expired OTP is rejected'
);

reset role;

select ok(
  (
    select verified and used_at is not null
    from public.registration_otps
    where email = 'pgtap-registration-valid@example.invalid'
      and code = '135790'
  ),
  'successful verification marks the OTP verified and records used_at'
);

select ok(
  (
    select not verified and used_at is null
    from public.registration_otps
    where email = 'pgtap-registration-expired@example.invalid'
      and code = '246802'
  ),
  'rejected expired OTP remains unused'
);

select ok(
  (
    select p.prosecdef
      and coalesce(
        array_position(p.proconfig, 'search_path=public, pg_temp') is not null,
        false
      )
    from pg_proc p
    where p.oid = 'public.verify_registration_otp(text,text)'::regprocedure
  ),
  'SECURITY DEFINER function has a fixed search_path'
);

select * from finish();

rollback;
