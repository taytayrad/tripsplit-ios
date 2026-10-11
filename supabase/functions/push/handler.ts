import { activityCopy } from "./activity-copy.ts";
import { type APNsEnvironment, sendAPNs } from "./apns.ts";

export interface PushConfig {
  supabaseUrl: string;
  serviceRoleKey: string;
  webhookSecret: string;
  authorization: () => Promise<string>;
}

interface EventRow {
  id: string;
  kind: string;
  actor_id: string;
  subject: string | null;
  deltas: Record<string, number>;
  expense_payer_id: string | null;
  expense_amount_cents: number | null;
  expense_payer_share_cents: number | null;
  actor: { display_name: string } | null;
  trips: { name: string };
  payments: {
    payer_id: string;
    payee_id: string;
    amount_cents: number;
    payer: { display_name: string } | null;
    payee: { display_name: string } | null;
  } | null;
}

interface DeviceToken {
  user_id: string;
  token: string;
  updated_at: string;
  apns_environment: APNsEnvironment | null;
}

async function authorized(request: Request, secret: string) {
  if (!secret) return false;
  const digest = (s: string) =>
    crypto.subtle.digest("SHA-256", new TextEncoder().encode(s));
  const [a, b] = await Promise.all([
    digest(request.headers.get("authorization") ?? ""),
    digest(`Bearer ${secret}`),
  ]);
  const expected = new Uint8Array(b);
  let different = 0;
  new Uint8Array(a).forEach((byte, i) => different |= byte ^ expected[i]);
  return different === 0;
}

export async function handlePush(
  request: Request,
  config: PushConfig,
  fetcher: typeof fetch = fetch,
): Promise<Response> {
  if (request.method !== "POST") {
    return new Response("Method not allowed", { status: 405 });
  }
  if (!await authorized(request, config.webhookSecret)) {
    return new Response("Unauthorized", { status: 401 });
  }
  let eventId: string;
  try {
    const payload = await request.json();
    if (
      payload.type !== "INSERT" || payload.schema !== "public" ||
      payload.table !== "activity_events" ||
      !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(
        payload.record?.id ?? "",
      )
    ) {
      return new Response("Invalid activity webhook", { status: 400 });
    }
    eventId = payload.record.id;
  } catch {
    return new Response("Invalid JSON", { status: 400 });
  }

  async function db<T>(path: string, init: RequestInit = {}): Promise<T> {
    const response = await fetcher(`${config.supabaseUrl}/rest/v1/${path}`, {
      ...init,
      headers: {
        apikey: config.serviceRoleKey,
        authorization: `Bearer ${config.serviceRoleKey}`,
        "content-type": "application/json",
      },
      signal: AbortSignal.timeout(10000),
    });
    if (!response.ok) {
      throw new Error(`Database request failed (${response.status})`);
    }
    if (response.status === 204) return undefined as T;
    return await response.json() as T;
  }

  try {
    // Read the canonical row. A webhook supplies only its id; it cannot supply banner wording or recipients.
    const columns =
      "id,kind,actor_id,subject,deltas,expense_payer_id,expense_amount_cents,expense_payer_share_cents,actor:profiles!activity_events_actor_id_fkey(display_name),trips!activity_events_trip_id_fkey(name),payments(payer_id,payee_id,amount_cents,payer:profiles!payments_payer_id_fkey(display_name),payee:profiles!payments_payee_id_fkey(display_name))";
    const [[e], recipients] = await Promise.all([
      db<EventRow[]>(
        `activity_events?id=eq.${eventId}&select=${encodeURIComponent(columns)}`,
      ),
      db<string[]>("rpc/push_recipients", {
        method: "POST",
        body: JSON.stringify({ p_event: eventId }),
      }),
    ]);
    if (!e) return Response.json({ sent: 0 });
    // Actor exclusion is also enforced by the SQL function; retain it at the delivery boundary.
    const ids = recipients.filter((id) => id !== e.actor_id);
    if (!ids.length) return Response.json({ sent: 0 });
    const tokens = await db<DeviceToken[]>(
      `device_tokens?user_id=in.(${
        ids.join(",")
      })&select=user_id,token,updated_at,apns_environment`,
    );
    if (!tokens.length) return Response.json({ sent: 0 });
    const authorization = await config.authorization();
    const results = await Promise.allSettled(tokens.map(async (device) => {
      const copy = activityCopy({
        kind: e.kind,
        actorId: e.actor_id,
        actorName: e.actor?.display_name ?? "",
        tripName: e.trips.name,
        subject: e.subject,
        deltas: e.deltas,
        expensePayerId: e.expense_payer_id,
        expenseAmountCents: e.expense_amount_cents,
        viewerShareCents: e.expense_payer_id === device.user_id
          ? e.expense_payer_share_cents
          : null,
        payerId: e.payments?.payer_id,
        payeeId: e.payments?.payee_id,
        payerName: e.payments?.payer?.display_name,
        payeeName: e.payments?.payee?.display_name,
        amountCents: e.payments?.amount_cents,
      }, device.user_id);
      if (!copy.statement) return false;
      const alert = {
        title: copy.statement,
        ...(copy.dollarLine == null ? {} : { body: copy.dollarLine }),
      };
      let environment = device.apns_environment ?? "production";
      let result = await sendAPNs(
        device.token,
        environment,
        authorization,
        eventId,
        alert,
        fetcher,
      );
      // Wrong-host tokens get BadDeviceToken. Try the other host before deleting an unclassified token.
      if (
        device.apns_environment == null && result.status === 400 &&
        result.reason === "BadDeviceToken"
      ) {
        environment = "sandbox";
        result = await sendAPNs(
          device.token,
          environment,
          authorization,
          eventId,
          alert,
          fetcher,
        );
      }
      // A sign-out, account takeover, or registration during the APNs call must survive cleanup.
      const row = `device_tokens?user_id=eq.${device.user_id}&token=eq.${
        encodeURIComponent(device.token)
      }&updated_at=eq.${encodeURIComponent(device.updated_at)}`;
      if (result.status === 200) {
        if (device.apns_environment == null) {
          await db(row, {
            method: "PATCH",
            body: JSON.stringify({ apns_environment: environment }),
          });
        }
        return true;
      }
      if (
        (result.status === 410 && result.reason === "Unregistered") ||
        (result.status === 400 && result.reason === "BadDeviceToken")
      ) {
        // Apple's timestamp is when registration became invalid; never delete a later registration.
        if (
          result.timestamp == null ||
          Date.parse(device.updated_at) <= result.timestamp
        ) {
          // Postgres retains sub-millisecond precision that JavaScript's Date drops.
          const cutoff = result.timestamp == null
            ? ""
            : `&updated_at=lte.${
              encodeURIComponent(new Date(result.timestamp).toISOString())
            }`;
          await db(row + cutoff, { method: "DELETE" });
        }
        return false;
      }
      throw new Error(
        `APNs rejected notification (${result.status}, ${result.reason})`,
      );
    }));
    const failures = results.filter((r) => r.status === "rejected");
    for (const failure of failures) {
      if (failure.status === "rejected") {
        console.error("push", eventId, String(failure.reason));
      }
    }
    const sent = results.filter((r) =>
      r.status === "fulfilled" && r.value
    ).length;
    return Response.json({ sent, failed: failures.length }, {
      status: failures.length ? 502 : 200,
    });
  } catch (error) {
    console.error("push", eventId, String(error));
    return Response.json({ error: "Push delivery failed" }, { status: 502 });
  }
}
