// The page an invite link opens: /functions/v1/invite/<token>.
// Tries to open the app at tripsplit://join/<token>; otherwise offers the App Store.
// Stands in for Universal Links until there's a domain (docs/architecture.md).

// ponytail: generic App Store link until the listing is live; set APP_STORE_URL then.
const appStoreURL = Deno.env.get("APP_STORE_URL") ?? "https://apps.apple.com/";

Deno.serve((req) => {
  const token = new URL(req.url).pathname.split("/").pop() ?? "";
  if (!/^[0-9a-f]{32}$/.test(token)) {
    return new Response("Invite link not found", { status: 404 });
  }
  const appURL = `tripsplit://join/${token}`;
  const html = `<!doctype html>
<html lang="en"><head>
<meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Join a trip on TripSplit</title>
<style>
  :root { color-scheme: light dark; font-family: -apple-system, system-ui, sans-serif; }
  body { margin: 0; min-height: 100vh; display: grid; place-items: center; background: Canvas; color: CanvasText; }
  main { max-width: 22rem; padding: 2rem 1.5rem; text-align: center; }
  h1 { font-size: 1.5rem; margin: 0 0 .5rem; }
  p { color: GrayText; margin: 0 0 1.5rem; }
  a.button { display: block; padding: .9rem; border-radius: .75rem; text-decoration: none; font-weight: 600; margin-bottom: .75rem; }
  .primary { background: #0062CC; color: #fff; }
  .secondary { border: 1px solid GrayText; color: CanvasText; }
</style>
</head><body><main>
<h1>You're invited to a trip</h1>
<p>Open TripSplit to join. New here? Get the app first, then tap the link again.</p>
<a class="button primary" href="${appURL}">Open TripSplit</a>
<a class="button secondary" href="${appStoreURL}">Get TripSplit</a>
</main>
<script>location.href = ${JSON.stringify(appURL)};</script>
</body></html>`;
  return new Response(html, { headers: { "content-type": "text/html; charset=utf-8" } });
});
