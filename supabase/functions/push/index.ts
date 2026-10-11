import { providerToken } from "./apns.ts";
import { handlePush, type PushConfig } from "./handler.ts";

function required(name: string): string {
  const value = Deno.env.get(name);
  if (!value) throw new Error(`Missing ${name}`);
  return value;
}

let config: PushConfig | undefined;
Deno.serve(async (request) => {
  try {
    config ??= {
      supabaseUrl: required("SUPABASE_URL"),
      serviceRoleKey: required("SUPABASE_SERVICE_ROLE_KEY"),
      webhookSecret: required("PUSH_WEBHOOK_SECRET"),
      authorization: providerToken(
        required("APNS_PRIVATE_KEY"),
        required("APNS_KEY_ID"),
        required("APNS_TEAM_ID"),
      ),
    };
  } catch (error) {
    console.error("push configuration", String(error));
    return Response.json({ error: "Push is not configured" }, { status: 503 });
  }
  try {
    return await handlePush(request, config);
  } catch (error) {
    console.error("push request", String(error));
    return Response.json({ error: "Push request failed" }, { status: 500 });
  }
});
