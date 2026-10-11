export type APNsEnvironment = "production" | "sandbox";

function base64url(bytes: Uint8Array): string {
  return btoa(String.fromCharCode(...bytes)).replaceAll("+", "-").replaceAll(
    "/",
    "_",
  ).replace(/=+$/, "");
}

// Web Crypto produces the 64-byte r||s signature required by ES256, not OpenSSL's DER encoding.
export function providerToken(
  pem: string,
  keyId: string,
  teamId: string,
  now = () => Date.now(),
) {
  const der = Uint8Array.from(
    atob(pem.replace(/-----[^-]+-----|\s|\\n/g, "")),
    (c) => c.charCodeAt(0),
  );
  const key = crypto.subtle.importKey(
    "pkcs8",
    der,
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"],
  );
  let cached: { issued: number; value: Promise<string> } | undefined;
  return () => {
    const issued = Math.floor(now() / 1000);
    if (
      !cached || issued - cached.issued >= 50 * 60 || issued < cached.issued
    ) {
      const value = (async () => {
        const encode = (json: object) =>
          base64url(new TextEncoder().encode(JSON.stringify(json)));
        const unsigned = `${encode({ alg: "ES256", kid: keyId })}.${
          encode({ iss: teamId, iat: issued })
        }`;
        const signature = await crypto.subtle.sign(
          { name: "ECDSA", hash: "SHA-256" },
          await key,
          new TextEncoder().encode(unsigned),
        );
        return `${unsigned}.${base64url(new Uint8Array(signature))}`;
      })();
      cached = { issued, value };
    }
    return cached.value;
  };
}

export async function sendAPNs(
  token: string,
  environment: APNsEnvironment,
  authorization: string,
  eventId: string,
  alert: { title: string; body?: string },
  fetcher: typeof fetch = fetch,
) {
  const host = environment === "sandbox"
    ? "api.sandbox.push.apple.com"
    : "api.push.apple.com";
  const response = await fetcher(
    `https://${host}/3/device/${encodeURIComponent(token)}`,
    {
      method: "POST",
      headers: {
        authorization: `bearer ${authorization}`,
        "apns-topic": "com.taylor.tripsplit",
        "apns-push-type": "alert",
        "apns-priority": "10",
        "apns-id": eventId,
        "apns-collapse-id": eventId,
        "apns-expiration": String(Math.floor(Date.now() / 1000) + 86400),
        "content-type": "application/json",
      },
      body: JSON.stringify({ aps: { alert, sound: "default" } }),
      signal: AbortSignal.timeout(10000),
    },
  );
  if (response.ok) {
    await response.body?.cancel();
    return { status: response.status, reason: "", timestamp: undefined };
  }
  const error = await response.json() as {
    reason?: string;
    timestamp?: number;
  };
  return {
    status: response.status,
    reason: error.reason ?? "Unknown",
    timestamp: error.timestamp,
  };
}
