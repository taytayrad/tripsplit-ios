# Sign in with Apple revoke setup (TRIP-28)

App Review requires that deleting an account also revokes Sign in with Apple. The `apple` Edge Function does both
halves:

- **At sign-in**, the app sends Apple's one-time authorization code with its own JWT. The function exchanges it at
  `https://appleid.apple.com/auth/token` and stores the refresh token in `public.apple_tokens`, which only the service
  role can read.
- **After `delete_account` commits**, pg_net calls the function with the webhook secret and the user's id. The
  function revokes the stored token at `https://appleid.apple.com/auth/revoke` and deletes the row once Apple accepts.

Until this is configured, nothing breaks: sign-in skips the exchange, and deletes skip the revoke. Accounts created
before TRIP-28 have no stored token, so they can't be revoked; deleting them still removes the sign-in.

## Create the key (Apple Developer)

1. **Certificates, Identifiers & Profiles › Keys › +.** Name it "TripSplit Sign in with Apple", tick **Sign in with
   Apple**, click **Configure**, and pick the primary App ID `com.taylor.tripsplit`. Save, Continue, Register.
2. Download the `.p8` (you can only download it once) and note the **Key ID**. The Team ID is `PHVU622P3U`.

This is a different key from the APNs key in `docs/push-setup.md`.

## Store the secrets

In the project's **Edge Functions › Secrets**:

| Name | Value |
|---|---|
| `APPLE_SIGNIN_KEY` | The whole `.p8` file, including the BEGIN/END lines. |
| `APPLE_SIGNIN_KEY_ID` | The key's 10-character Key ID. |
| `APPLE_TEAM_ID` | `PHVU622P3U` |
| `APPLE_CLIENT_ID` | `com.taylor.tripsplit` |
| `APPLE_WEBHOOK_SECRET` | A new random secret, at least 32 random bytes, used only for this webhook. |

Then in the SQL editor, add the Vault entries the database reads (the same webhook secret value):

```sql
select vault.create_secret('https://<project-ref>.supabase.co/functions/v1/apple', 'apple_function_url');
select vault.create_secret('<the APPLE_WEBHOOK_SECRET value>', 'apple_webhook_secret');
```

Never paste the key or the secret into the repo, Linear, or chat.

## Deploy

Apply all database migrations, including `20261016043147_delete_account_hardening.sql`, before distributing the updated app. It selects `profiles.deleted_at`; a backend without that column cannot load its profiles. The hardening migration also backfills deletion status for accounts already deleted.

```sh
supabase functions deploy apple --project-ref <project-ref> --no-verify-jwt
supabase db push --project-ref <project-ref>
```

The gateway JWT check is off on purpose: the function checks its own callers (the user's JWT for the exchange, the
webhook secret for the revoke).

## Check once

Sign out and back in with Apple on a real build, then confirm a row exists:
`select user_id, updated_at from public.apple_tokens;`. Delete that test account from Profile; the row disappears once
Apple accepts the revoke, and the app no longer appears under **Settings › Apple ID › Sign in with Apple** on the
phone.

## Retry a failed revoke

A failed revoke leaves the account deleted and the row in `apple_tokens`. Retry with the user id:

```sh
curl -X POST https://<project-ref>.supabase.co/functions/v1/apple \
  -H "Authorization: Bearer <APPLE_WEBHOOK_SECRET>" -H "Content-Type: application/json" \
  -d '{"revoke":"<user id>"}'
```

It only retries Apple; it never recreates the account. `{"revoked":false,"reason":"no token stored"}` means there is
nothing to revoke.
