-- =============================================================================
-- Restore the minimum auth ACL required by reward_points_owner RPCs.
--
-- admin_update_reward_points_config is SECURITY DEFINER and owned by the
-- constrained NOLOGIN reward_points_owner role. Its admin gate calls auth.uid(),
-- so the owner needs both USAGE on the auth schema and EXECUTE on that function.
-- No auth table privilege is granted.
-- =============================================================================

GRANT USAGE ON SCHEMA auth TO reward_points_owner;
GRANT EXECUTE ON FUNCTION auth.uid() TO reward_points_owner;

NOTIFY pgrst, 'reload schema';

