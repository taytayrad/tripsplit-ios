-- Supabase grants new functions to anon by default. Signed-out callers get nothing: every RPC needs a user.
-- Functions the app calls are granted to authenticated explicitly in their own migrations.
revoke execute on all functions in schema public from public, anon;
revoke execute on all functions in schema private from public, anon;
alter default privileges for role postgres in schema public revoke execute on functions from public, anon;
alter default privileges for role postgres in schema private revoke execute on functions from public, anon;
