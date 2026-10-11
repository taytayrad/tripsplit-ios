import { deepStrictEqual as equal, ok, rejects } from "node:assert/strict";
import { providerToken } from "./apns.ts";

Deno.test("APNs JWT has an ES256 signature, key id, team id, and epoch iat; cached for 50 minutes", async () => {
  const keys = await crypto.subtle.generateKey(
    { name: "ECDSA", namedCurve: "P-256" },
    true,
    ["sign", "verify"],
  );
  const der = new Uint8Array(
    await crypto.subtle.exportKey("pkcs8", keys.privateKey),
  );
  const pem = `-----BEGIN PRIVATE KEY-----\n${
    btoa(String.fromCharCode(...der))
  }\n-----END PRIVATE KEY-----`;
  let now = 1800000000000;
  const token = providerToken(pem, "KEY1234567", "TEAM123456", () => now);
  const jwt = await token();
  const [header, claims, signature] = jwt.split(".");
  const decode = (part: string) =>
    Uint8Array.from(
      atob(part.replaceAll("-", "+").replaceAll("_", "/")),
      (c) => c.charCodeAt(0),
    );
  equal(JSON.parse(new TextDecoder().decode(decode(header))), {
    alg: "ES256",
    kid: "KEY1234567",
  });
  equal(JSON.parse(new TextDecoder().decode(decode(claims))), {
    iss: "TEAM123456",
    iat: now / 1000,
  });
  equal(decode(signature).length, 64);
  ok(
    await crypto.subtle.verify(
      { name: "ECDSA", hash: "SHA-256" },
      keys.publicKey,
      decode(signature),
      new TextEncoder().encode(`${header}.${claims}`),
    ),
  );
  now += 49 * 60000;
  equal(await token(), jwt);
  now += 60000;
  ok(await token() !== jwt);
  equal(
    await providerToken(
      pem.replaceAll("\n", "\\n"),
      "KEY1234567",
      "TEAM123456",
      () => 1800000000000,
    )(),
    jwt,
  );
});

Deno.test("an invalid private key rejects the awaited send, without starting a background import", async () => {
  const token = providerToken("AA==", "KEY1234567", "TEAM123456");
  await rejects(token());
});
