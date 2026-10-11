import { deepStrictEqual as equal, ok } from "node:assert/strict";
import { handlePush, type PushConfig } from "./handler.ts";

const actor = "00000000-0000-0000-0000-000000000001";
const viewer = "00000000-0000-0000-0000-000000000002";
const eventId = "00000000-0000-0000-0000-000000000003";
const config: PushConfig = {
  supabaseUrl: "https://project.test",
  serviceRoleKey: "service-role",
  webhookSecret: "webhook-secret",
  authorization: () => Promise.resolve("provider-token"),
};
const event = {
  id: eventId,
  kind: "expense_added",
  actor_id: actor,
  subject: "Airbnb",
  deltas: { [viewer]: -3600 },
  actor: { display_name: "Connor Smith" },
  trips: { name: "Coast Road" },
  payments: null,
  expense_payer_id: actor,
  expense_amount_cents: 7200,
  expense_payer_share_cents: 3600,
};
const device = {
  user_id: viewer,
  token: "aabb",
  updated_at: "2026-10-10T00:00:00+00:00",
  apns_environment: null as "production" | "sandbox" | null,
};
const payload = {
  type: "INSERT",
  schema: "public",
  table: "activity_events",
  record: { id: eventId },
};
const request = (
  body: unknown = payload,
  authorization = "Bearer webhook-secret",
) =>
  new Request("https://function.test/push", {
    method: "POST",
    headers: { authorization },
    body: JSON.stringify(body),
  });

function stub(
  options: {
    e?: object | null;
    recipients?: string[];
    devices?: typeof device[];
    responses?: { status: number; reason?: string; timestamp?: number }[];
    reject?: boolean;
    failDb?: boolean;
  } = {},
) {
  const calls: { url: URL; init: RequestInit }[] = [];
  const responses = [...(options.responses ?? [{ status: 200 }])];
  const responseFor = (input: RequestInfo | URL, init: RequestInit = {}) => {
    const url = new URL(String(input));
    calls.push({ url, init });
    if (url.hostname.endsWith("push.apple.com")) {
      if (options.reject) throw new TypeError("Network error");
      const r = responses.shift()!;
      return r.status === 200
        ? new Response(null, { status: 200 })
        : Response.json({ reason: r.reason, timestamp: r.timestamp }, {
          status: r.status,
        });
    }
    equal(new Headers(init.headers).get("apikey"), "service-role");
    equal(
      new Headers(init.headers).get("authorization"),
      "Bearer service-role",
    );
    if (options.failDb) return new Response(null, { status: 500 });
    if (url.pathname.endsWith("/activity_events")) {
      return Response.json(options.e === null ? [] : [options.e ?? event]);
    }
    if (url.pathname.endsWith("/rpc/push_recipients")) {
      equal(JSON.parse(String(init.body)), { p_event: eventId });
      return Response.json(options.recipients ?? [viewer]);
    }
    if (url.pathname.endsWith("/device_tokens") && !init.method) {
      return Response.json(options.devices ?? [device]);
    }
    if (
      url.pathname.endsWith("/device_tokens") &&
      ["PATCH", "DELETE"].includes(init.method!)
    ) return new Response(null, { status: 204 });
    throw new Error(`Unexpected request: ${url}`);
  };
  const fetcher: typeof fetch = (input, init) =>
    Promise.resolve(responseFor(input, init));
  return {
    calls,
    fetcher,
    apple: () => calls.filter((c) => c.url.hostname.endsWith("push.apple.com")),
    mutations: () =>
      calls.filter((c) => ["PATCH", "DELETE"].includes(c.init.method!)),
  };
}

Deno.test("webhook rejects client JWTs, missing credentials, wrong table, invalid UUID, and bad JSON before any database call", async () => {
  const s = stub();
  for (const auth of ["", "Bearer client-jwt", "Bearer service-role"]) {
    equal(
      (await handlePush(request(payload, auth), config, s.fetcher)).status,
      401,
    );
  }
  equal(
    (await handlePush(request(), { ...config, webhookSecret: "" }, s.fetcher))
      .status,
    401,
  );
  for (
    const bad of [
      { ...payload, type: "UPDATE" },
      { ...payload, table: "profiles" },
      { ...payload, record: { id: "x&select=*" } },
      null,
    ]
  ) equal((await handlePush(request(bad), config, s.fetcher)).status, 400);
  equal(
    (await handlePush(
      new Request("https://function.test", {
        method: "POST",
        headers: { authorization: "Bearer webhook-secret" },
        body: "{",
      }),
      config,
      s.fetcher,
    )).status,
    400,
  );
  equal(
    (await handlePush(new Request("https://function.test"), config, s.fetcher))
      .status,
    405,
  );
  equal(s.calls.length, 0);
});

Deno.test("expense delivers canonical recipient copy with APNs alert headers and learns production", async () => {
  const s = stub();
  const response = await handlePush(
    request({
      ...payload,
      record: { ...payload.record, subject: "forged wording" },
    }),
    config,
    s.fetcher,
  );
  equal(await response.json(), { sent: 1, failed: 0 });
  const call = s.apple()[0];
  equal(call.url.href, "https://api.push.apple.com/3/device/aabb");
  const headers = new Headers(call.init.headers);
  equal(headers.get("apns-topic"), "com.taylor.tripsplit");
  equal(headers.get("apns-push-type"), "alert");
  equal(headers.get("authorization"), "bearer provider-token");
  equal(headers.get("apns-id"), eventId);
  equal(headers.get("apns-collapse-id"), eventId);
  equal(JSON.parse(String(call.init.body)), {
    aps: {
      alert: {
        title: 'Connor S. added "Airbnb" in "Coast Road"',
        body: "You owe $36",
      },
      sound: "default",
    },
    activity_event_id: eventId,
  });
  equal(JSON.parse(String(s.mutations()[0].init.body)), {
    apns_environment: "production",
  });
});

Deno.test("unknown Xcode token retries sandbox before it can be removed", async () => {
  const s = stub({
    responses: [{ status: 400, reason: "BadDeviceToken" }, { status: 200 }],
  });
  equal((await handlePush(request(), config, s.fetcher)).status, 200);
  equal(s.apple().map((c) => c.url.hostname), [
    "api.push.apple.com",
    "api.sandbox.push.apple.com",
  ]);
  equal(JSON.parse(String(s.mutations()[0].init.body)), {
    apns_environment: "sandbox",
  });
  ok(!s.mutations().some((c) => c.init.method === "DELETE"));
});

Deno.test("a known sandbox token goes straight to sandbox, with no dollar body for a trip event", async () => {
  const s = stub({
    devices: [{ ...device, apns_environment: "sandbox" }],
    e: { ...event, kind: "trip_deleted" },
  });
  equal((await handlePush(request(), config, s.fetcher)).status, 200);
  equal(s.apple()[0].url.hostname, "api.sandbox.push.apple.com");
  equal(JSON.parse(String(s.apple()[0].init.body)).aps.alert, {
    title: 'Connor S. deleted the trip "Coast Road"',
  });
  equal(s.mutations().length, 0);
});

Deno.test("all N1–N9 pushes carry the canonical activity id for tap routing", async () => {
  for (const kind of [
    "member_joined",
    "expense_added",
    "expense_updated",
    "expense_deleted",
    "expense_restored",
    "payment_logged",
    "payment_deleted",
    "trip_deleted",
    "trip_undeleted",
  ]) {
    const s = stub({ e: { ...event, kind } });
    const forged = {
      ...payload,
      record: { id: eventId, trip_id: "untrusted", expense_id: "untrusted" },
    };
    equal((await handlePush(request(forged), config, s.fetcher)).status, 200);
    equal(JSON.parse(String(s.apple()[0].init.body)).activity_event_id, eventId);
  }
});

Deno.test("payment copy is addressed to the payee, and only selected tokens receive it", async () => {
  const s = stub({
    e: {
      ...event,
      kind: "payment_logged",
      payments: {
        payer_id: actor,
        payee_id: viewer,
        amount_cents: 51844,
        payer: { display_name: "Sammy" },
        payee: { display_name: "Connor" },
      },
    },
  });
  equal((await handlePush(request(), config, s.fetcher)).status, 200);
  equal(JSON.parse(String(s.apple()[0].init.body)).aps.alert, {
    title: 'Sammy paid you in "Coast Road"',
    body: "You received $518.44",
  });
  equal(
    s.calls.find((c) => c.url.pathname.endsWith("/device_tokens"))!.url
      .searchParams.get("user_id"),
    `in.(${viewer})`,
  );
});

for (
  const options of [{ e: null }, { recipients: [] }, { recipients: [actor] }, {
    devices: [],
  }]
) {
  Deno.test(`no delivery when event, eligible recipient, or token is absent: ${JSON.stringify(options)}`, async () => {
    const s = stub(options);
    equal(await (await handlePush(request(), config, s.fetcher)).json(), {
      sent: 0,
    });
    equal(s.apple().length, 0);
  });
}

for (
  const r of [{
    status: 410,
    reason: "Unregistered",
    timestamp: Date.parse(device.updated_at),
  }, { status: 400, reason: "BadDeviceToken" }]
) {
  Deno.test(`removes rejected ${r.reason} only if owner and registration still match`, async () => {
    const s = stub({
      devices: [{ ...device, apns_environment: "production" }],
      responses: [r],
    });
    equal((await handlePush(request(), config, s.fetcher)).status, 200);
    const deletion = s.mutations()[0];
    equal(deletion.init.method, "DELETE");
    equal(deletion.url.searchParams.get("user_id"), `eq.${viewer}`);
    equal(deletion.url.searchParams.get("token"), "eq.aabb");
    equal(
      deletion.url.searchParams.get("updated_at"),
      `eq.${device.updated_at}`,
    );
  });
}

Deno.test("unknown token invalid on both hosts is removed", async () => {
  const s = stub({
    responses: [{ status: 400, reason: "BadDeviceToken" }, {
      status: 400,
      reason: "BadDeviceToken",
    }],
  });
  equal((await handlePush(request(), config, s.fetcher)).status, 200);
  equal(s.apple().length, 2);
  equal(s.mutations()[0].init.method, "DELETE");
});

Deno.test("APNs cleanup preserves registrations made later within the same millisecond", async () => {
  const registered = "2026-10-10T00:00:00.000999+00:00";
  const s = stub({
    devices: [{ ...device, updated_at: registered }],
    responses: [{
      status: 410,
      reason: "Unregistered",
      timestamp: Date.parse(device.updated_at),
    }],
  });
  equal((await handlePush(request(), config, s.fetcher)).status, 200);
  equal(s.mutations()[0].url.searchParams.getAll("updated_at"), [
    `eq.${registered}`,
    "lte.2026-10-10T00:00:00.000Z",
  ]);
});

Deno.test("an APNs invalidation older than the registration never deletes it", async () => {
  const s = stub({
    responses: [{
      status: 410,
      reason: "Unregistered",
      timestamp: Date.parse(device.updated_at) - 1,
    }],
  });
  equal((await handlePush(request(), config, s.fetcher)).status, 200);
  equal(s.mutations().length, 0);
});

for (const status of [403, 429, 500, 503]) {
  Deno.test(`APNs ${status} surfaces failure without deleting tokens`, async () => {
    const s = stub({
      responses: [{ status, reason: "ServerOrCredentialError" }],
    });
    equal((await handlePush(request(), config, s.fetcher)).status, 502);
    equal(s.mutations().length, 0);
  });
}

Deno.test("network and database failures are surfaced; independent devices still send", async () => {
  for (const options of [{ reject: true }, { failDb: true }]) {
    const s = stub(options);
    equal((await handlePush(request(), config, s.fetcher)).status, 502);
    equal(s.mutations().length, 0);
  }
  const s = stub({
    devices: [{ ...device, apns_environment: "production" }, {
      ...device,
      token: "ccdd",
      apns_environment: "production",
    }],
    responses: [{ status: 503, reason: "Shutdown" }, { status: 200 }],
  });
  equal(await (await handlePush(request(), config, s.fetcher)).json(), {
    sent: 1,
    failed: 1,
  });
  equal(s.apple().length, 2);
});
