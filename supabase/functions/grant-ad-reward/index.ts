import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { json, options } from "../_shared/http.ts";

// Legacy client callback is deliberately non-crediting. New clients must use
// admob-reward-session and wait for the independently verified SSV callback.
serve((req: Request) => {
  if (req.method === "OPTIONS") return options("POST, OPTIONS");
  if (req.method !== "POST") {
    return json({ error_code: "METHOD_NOT_ALLOWED" }, 405, {
      Allow: "POST, OPTIONS",
    });
  }
  return json(
    {
      status: 410,
      error_code: "LEGACY_AD_REWARD_ENDPOINT_RETIRED",
      minimum_contract: "admob-ssv-v1",
      credit_created: false,
    },
    410,
    { "Cache-Control": "no-store" },
  );
});
