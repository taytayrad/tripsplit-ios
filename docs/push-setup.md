# Activity push setup (TRIP-25)

After each committed activity insert, `push` reads the saved event, calls `push_recipients` with the service
role, and sends each recipient's Activity statement and dollar line. Nothing is sent until the secrets and
Vault entries below are configured. Existing activity is not replayed.

## Store secrets

In the project's **Edge Functions → Secrets**, save:

| Name | Value |
|---|---|
| `APNS_PRIVATE_KEY` | The entire `.p8` file, including BEGIN/END lines. Actual newlines or literal `\n` both work. |
| `APNS_KEY_ID` | The key's 10-character Key ID from Apple Developer. |
| `APNS_TEAM_ID` | Apple Team ID (`PHVU622P3U` in the current Xcode project; confirm it owns the key). |
| `PUSH_WEBHOOK_SECRET` | A new random secret, at least 32 random bytes, used only for this webhook. |

Generate the webhook secret in your password manager and save it there too: Vault needs the same value.
Do not paste keys into a PR, Linear, or chat. Supabase supplies `SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY`
automatically; the service role stays on the server.

The APNs key must authorize `com.taylor.tripsplit` on both sandbox and production. Confirm Push Notifications
is enabled on this App ID. Xcode installs and TestFlight need different hosts: the first send tries production,
and only `400 BadDeviceToken` on an unknown token tries sandbox. Success saves the accepted environment.
Registration clears it so a reinstall can be classified again. No build-configuration guess is needed.

## Deploy the function and migration

From the repo root after merge, replace `<project-ref>` with the project's ref:

```sh
supabase functions deploy push --project-ref <project-ref> --no-verify-jwt
supabase db push --project-ref <project-ref> --dry-run
supabase db push --project-ref <project-ref>
```

Review the dry run: prerequisite migrations, including `push_recipients`, must be present on the hosted
project. The disabled gateway JWT check is intentional: the handler requires the dedicated webhook secret
and rejects signed-in client tokens. Deploying this function does not give users a push API.

## Enable the webhook in Vault

In **Database → Vault**, create these named secrets:

| Name | Value |
|---|---|
| `push_function_url` | `https://<project-ref>.supabase.co/functions/v1/push` |
| `push_webhook_secret` | Exactly the same value as Edge Function secret `PUSH_WEBHOOK_SECRET`. |

The migration installs the trigger. Do not add another Dashboard webhook: that would send each event twice.
Enable Vault entries last, after the sender and APNs credentials are ready. Missing Vault configuration leaves
expense/payment saves working and skips pushes. To pause pushes, remove `push_function_url` from Vault.

For local development, use `http://host.docker.internal:54321/functions/v1/push` as the Vault URL and put Edge
Function secrets in git-ignored `supabase/functions/.env`. Ordinary tests need no APNs credentials.

## Verify on two iPhones

Use two different signed-in members with notifications allowed; keep the receiving app in the background.

1. A adds an expense paid by A and split with B. B receives the Activity title and dollar line; A gets nothing.
2. B turns off **Expenses that affect you**. A adds another shared expense. B gets nothing. Turn it back on.
3. With a third member C, log a payment between A and C. B gets nothing; the payee gets the banner unless they
   were the person who logged it.
4. A deletes the trip, then restores it from Activity. B receives both statements, with no dollar body.
5. Check an Xcode-installed build and a TestFlight build. After a successful send, `device_tokens.apns_environment`
   is `sandbox` and `production` respectively. A fresh registration clears it until the next send.

6. Tap each N1–N9 notification and check its destination in `events.md`. Check a background tap and a tap after quitting the app. Expense-deleted taps must show the deleted expense’s details; trip-deleted taps must open Activity. Repeat a tap while another detail/form is open and after a trip is no longer accessible. Use new notifications: older banners have no routing ID.

Record results in TRIP-25 before marking it complete. CI cannot establish these device results.

## Tests and troubleshooting

```sh
supabase test db
deno check supabase/functions/push/index.ts
deno test supabase/functions/push
```

Database tests cover recipients, preferences, token ownership, and the webhook queue; they roll back queued
requests. Sender tests mirror `ActivityCopyTests` and stub every database/APNs HTTP request. CI uses no live keys.

Check **Edge Functions → push → Logs** and `net._http_response` for webhook status. `401` means the Vault and
Edge Function webhook secrets disagree; `503` means a function secret is missing; `502` means a database or
APNs call failed. APNs `403` commonly means a wrong key, Team ID, or topic. Token and secret values are never
included in the function's logs.

`410 Unregistered` and `400 BadDeviceToken` remove only the token's still-matching owner/registration. An
unknown token must be rejected by both hosts as BadDeviceToken before cleanup. An invalidation timestamp
older than registration does not remove it. Credential errors, rate limits, and network failures retain tokens
and surface a failure; other devices are still attempted.

This beta sender makes one webhook delivery attempt per event, with no durable retry queue. Check failures
during the device pass. Replaying an event calls the recipient function again and uses its event id as the
APNs collapse id. APNs acceptance does not guarantee the device showed a banner.

References: [Supabase webhooks](https://supabase.com/docs/guides/database/webhooks),
[Vault](https://supabase.com/docs/guides/database/vault),
[Edge Function secrets](https://supabase.com/docs/guides/functions/secrets),
[Apple APNs requests and responses](https://developer.apple.com/library/archive/documentation/NetworkingInternet/Conceptual/RemoteNotificationsPG/CommunicatingwithAPNs.html).
