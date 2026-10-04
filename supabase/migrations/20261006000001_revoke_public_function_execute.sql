-- Postgres grants EXECUTE on every new function to PUBLIC, and the schema-scoped default-privilege revokes in
-- earlier migrations can't remove that. The one-off revoke in 20261003000007 covered only the functions that
-- existed then, so add_member and invite_preview (created later) were callable by anon.
-- pgTAP (005_access) now fails if anything but invite_preview is callable signed out, so a new function that
-- forgets this revoke is caught in CI. (A global default revoke would break the tests' pg_temp helpers.)
revoke execute on all functions in schema public from public, anon;
-- The one function signed-out people may call: the invite preview on the sign-in screen.
grant execute on function public.invite_preview(text) to anon, authenticated;
