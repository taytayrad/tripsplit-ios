// Sign in with Apple tokens (TRIP-28). Two callers:
// - the app, right after sign-in, with its JWT and the authorization code: exchange it for a refresh token and store it;
// - delete_account, after its commit, with the webhook secret and a user id: revoke that token at Apple, then forget it.
// Setup and retry: docs/apple-revoke-setup.md.
import { authorized } from "../push/handler.ts";

const env = (name: string) => {
  const value = Deno.env.get(name);
  if (!value) throw new Error(`Missing ${name}`);
  return value;
};
const b64url = (bytes: Uint8Array) =>
  btoa(String.fromCharCode(...bytes)).replaceAll("+", "-").replaceAll("/", "_").replace(/=+$/, "");

// Apple's client secret: an ES256 JWT signed with the Sign in with Apple key (not the APNs key).
async function clientSecret(): Promise<string> {
  const der = Uint8Array.from(atob(env("APPLE_SIGNIN_KEY").replace(/-----[^-]+-----|\s|\\n/g, "")), (c) => c.charCodeAt(0));
  const key = await crypto.subtle.importKey("pkcs8", der, { name: "ECDSA", namedCurve: "P-256" }, false, ["sign"]);
  const now = Math.floor(Date.now() / 1000);
  const part = (json: object) => b64url(new TextEncoder().encode(JSON.stringify(json)));
  const unsigned = `${part({ alg: "ES256", kid: env("APPLE_SIGNIN_KEY_ID") })}.${
    part({ iss: env("APPLE_TEAM_ID"), iat: now, exp: now + 300, aud: "https://appleid.apple.com", sub: env("APPLE_CLIENT_ID") })
  }`;
  const sig = await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, key, new TextEncoder().encode(unsigned));
  return `${unsigned}.${b64url(new Uint8Array(sig))}`;
}

async function apple(path: string, fields: Record<string, string>) {
  return await fetch(`https://appleid.apple.com/auth/${path}`, {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({ client_id: env("APPLE_CLIENT_ID"), client_secret: await clientSecret(), ...fields }),
    signal: AbortSignal.timeout(10000),
  });
}

async function db(path: string, init: RequestInit = {}) {
  const key = env("SUPABASE_SERVICE_ROLE_KEY");
  const response = await fetch(`${env("SUPABASE_URL")}/rest/v1/${path}`, {
    ...init,
    headers: { apikey: key, authorization: `Bearer ${key}`, "content-type": "application/json", prefer: "resolution=merge-duplicates" },
    signal: AbortSignal.timeout(10000),
  });
  if (!response.ok) throw new Error(`Database request failed (${response.status})`);
  return response.status === 204 ? undefined : await response.json();
}

Deno.serve(async (request) => {
  if (request.method !== "POST") return new Response("Method not allowed", { status: 405 });
  try {
    const body = await request.json();

    // Revoke: only delete_account's queued request carries the webhook secret.
    if (typeof body.revoke === "string") {
      if (!await authorized(request, env("APPLE_WEBHOOK_SECRET"))) return new Response("Unauthorized", { status: 401 });
      const id = encodeURIComponent(body.revoke);
      const [row] = await db(`apple_tokens?user_id=eq.${id}&select=refresh_token`) as { refresh_token: string }[];
      if (!row) return Response.json({ revoked: false, reason: "no token stored" });  // nothing to retry
      const response = await apple("revoke", { token: row.refresh_token, token_type_hint: "refresh_token" });
      if (!response.ok) return Response.json({ error: `Apple revoke failed (${response.status})` }, { status: 502 });
      await db(`apple_tokens?user_id=eq.${id}`, { method: "DELETE" });
      return Response.json({ revoked: true });
    }

    // Exchange: the signed-in person's own code. Their id comes from their JWT, never the body.
    if (typeof body.code !== "string") return new Response("Invalid request", { status: 400 });
    const user = await fetch(`${env("SUPABASE_URL")}/auth/v1/user`, {
      headers: { apikey: env("SUPABASE_SERVICE_ROLE_KEY"), authorization: request.headers.get("authorization") ?? "" },
    });
    if (!user.ok) return new Response("Unauthorized", { status: 401 });
    const { id } = await user.json();
    const response = await apple("token", { code: body.code, grant_type: "authorization_code" });
    const token = await response.json();
    if (!response.ok || !token.refresh_token) {
      return Response.json({ error: `Apple token exchange failed (${response.status})` }, { status: 502 });
    }
    await db("apple_tokens", { method: "POST", body: JSON.stringify({ user_id: id, refresh_token: token.refresh_token, updated_at: new Date().toISOString() }) });
    return Response.json({ stored: true });
  } catch (error) {
    console.error("apple", String(error));
    return Response.json({ error: "Apple request failed" }, { status: 500 });
  }
});
