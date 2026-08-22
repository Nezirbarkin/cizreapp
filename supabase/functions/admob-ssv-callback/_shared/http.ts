export const jsonHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, x-idempotency-key, x-cron-secret",
  "Access-Control-Allow-Methods": "POST, GET, OPTIONS",
  "Content-Type": "application/json",
};

export function json(
  body: unknown,
  status = 200,
  headers: HeadersInit = {},
): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...jsonHeaders, ...headers },
  });
}

export function options(methods = "POST, OPTIONS"): Response {
  return new Response(null, {
    status: 204,
    headers: { ...jsonHeaders, "Access-Control-Allow-Methods": methods },
  });
}

export function requireEnv(names: string[]): Record<string, string> {
  const values: Record<string, string> = {};
  for (const name of names) {
    const value = Deno.env.get(name)?.trim();
    if (!value) throw new Error(`MISSING_CONFIG:${name}`);
    values[name] = value;
  }
  return values;
}

export function bearerToken(req: Request): string | null {
  const value = req.headers.get("authorization") ?? "";
  const match = /^Bearer\s+(.+)$/i.exec(value);
  return match?.[1] ?? null;
}

export function safeErrorCode(error: unknown): string {
  const message = error instanceof Error ? error.message : "UNKNOWN_ERROR";
  return /^[A-Z0-9_:-]{3,100}$/.test(message) ? message : "INTERNAL_ERROR";
}
