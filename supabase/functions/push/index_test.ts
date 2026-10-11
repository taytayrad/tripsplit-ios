import { deepStrictEqual as equal } from "node:assert/strict";

Deno.test("entrypoint distinguishes missing config from unexpected request errors", async () => {
  const serve = Object.getOwnPropertyDescriptor(Deno, "serve")!;
  const env = Deno.env.get;
  const digest = crypto.subtle.digest;
  let respond!: (request: Request) => Promise<Response>;
  let configured = false;
  Object.defineProperty(Deno, "serve", {
    value: (handler: typeof respond) => { respond = handler; },
    configurable: true,
  });
  Deno.env.get = () => configured ? "AA==" : undefined;
  try {
    await import("./index.ts");
    const request = () => new Request("https://function.test/push", { method: "POST" });
    const missing = await respond(request());
    equal(missing.status, 503);
    equal(await missing.json(), { error: "Push is not configured" });
    configured = true;
    crypto.subtle.digest = () => Promise.reject(new Error("simulated runtime failure"));
    const failed = await respond(request());
    equal(failed.status, 500);
    equal(await failed.json(), { error: "Push request failed" });
    crypto.subtle.digest = digest;
    equal((await respond(request())).status, 401);
  } finally {
    Object.defineProperty(Deno, "serve", serve);
    Deno.env.get = env;
    crypto.subtle.digest = digest;
  }
});
