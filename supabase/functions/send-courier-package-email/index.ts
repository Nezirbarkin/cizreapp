import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

const jsonResponse = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });

const escapeHtml = (value: unknown) => String(value ?? "-")
  .replaceAll("&", "&amp;")
  .replaceAll("<", "&lt;")
  .replaceAll(">", "&gt;")
  .replaceAll('"', "&quot;")
  .replaceAll("'", "&#039;");

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return jsonResponse({ error: "method_not_allowed" }, 405);

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const resendApiKey = Deno.env.get("RESEND_API_KEY");
  const authorization = req.headers.get("Authorization");

  if (!supabaseUrl || !anonKey || !serviceRoleKey || !resendApiKey) {
    console.error("send-courier-package-email: required secret is missing");
    return jsonResponse({ error: "server_not_configured" }, 500);
  }
  if (!authorization?.startsWith("Bearer ")) {
    return jsonResponse({ error: "authentication_required" }, 401);
  }

  try {
    const requestBody = await req.json();
    const requestId = requestBody?.request_id;
    if (typeof requestId !== "string" || requestId.length < 30) {
      return jsonResponse({ error: "invalid_request_id" }, 400);
    }

    const userClient = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: authorization } },
      auth: { persistSession: false },
    });
    const jwt = authorization.slice("Bearer ".length);
    const { data: userData, error: userError } = await userClient.auth.getUser(jwt);
    if (userError || !userData.user) return jsonResponse({ error: "invalid_token" }, 401);

    const admin = createClient(supabaseUrl, serviceRoleKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const { data: packageRequest, error: requestError } = await admin
      .from("courier_requests")
      .select("id, courier_id, status, pickup_address, delivery_address, courier_fee")
      .eq("id", requestId)
      .maybeSingle();

    if (requestError) throw requestError;
    if (!packageRequest) return jsonResponse({ error: "package_not_found" }, 404);
    if (packageRequest.status !== "accepted" || packageRequest.courier_id !== userData.user.id) {
      return jsonResponse({ error: "not_assigned_courier" }, 403);
    }

    const { data: delivery } = await admin
      .from("courier_package_email_deliveries")
      .select("status, attempted_at")
      .eq("request_id", requestId)
      .maybeSingle();
    if (delivery?.status === "sent") {
      return jsonResponse({ success: true, already_sent: true });
    }

    const { data: authUser, error: authUserError } =
      await admin.auth.admin.getUserById(userData.user.id);
    if (authUserError) throw authUserError;
    const courierEmail = authUser.user?.email;
    if (!courierEmail) return jsonResponse({ error: "courier_email_not_found" }, 422);

    const { data: profile } = await admin
      .from("profiles")
      .select("full_name, username")
      .eq("id", userData.user.id)
      .maybeSingle();
    const courierName = profile?.full_name || profile?.username || "Kurye";

    await admin.from("courier_package_email_deliveries").upsert({
      request_id: requestId,
      courier_id: userData.user.id,
      status: "pending",
      last_error: null,
      attempted_at: new Date().toISOString(),
    });

    const html = `<!doctype html><html><body style="font-family:Arial,sans-serif;color:#263238">
      <div style="max-width:600px;margin:auto;padding:24px">
        <h2 style="color:#e65100">📦 Paket kabul edildi</h2>
        <p>Merhaba ${escapeHtml(courierName)}, paket talebi hesabınıza atandı.</p>
        <table style="width:100%;border-collapse:collapse">
          <tr><td style="padding:8px;border-bottom:1px solid #eee"><b>Alım</b></td><td>${escapeHtml(packageRequest.pickup_address)}</td></tr>
          <tr><td style="padding:8px;border-bottom:1px solid #eee"><b>Teslim</b></td><td>${escapeHtml(packageRequest.delivery_address)}</td></tr>
          <tr><td style="padding:8px"><b>Kurye kazancı</b></td><td>₺${escapeHtml(packageRequest.courier_fee)}</td></tr>
        </table>
        <p style="color:#607d8b">Güncel detayları CizreApp kurye panelinden görüntüleyebilirsiniz.</p>
      </div></body></html>`;

    const resendResponse = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Authorization": `Bearer ${resendApiKey}`,
      },
      body: JSON.stringify({
        from: "CizreApp <noreply@cizreapp.com>",
        to: courierEmail,
        subject: "📦 Paket talebi hesabınıza atandı",
        html,
      }),
    });

    if (!resendResponse.ok) {
      const providerError = await resendResponse.text();
      await admin.from("courier_package_email_deliveries").upsert({
        request_id: requestId,
        courier_id: userData.user.id,
        status: "failed",
        last_error: providerError.slice(0, 1000),
        attempted_at: new Date().toISOString(),
      });
      console.error("Resend error:", providerError);
      return jsonResponse({ error: "email_provider_error" }, 502);
    }

    await admin.from("courier_package_email_deliveries").upsert({
      request_id: requestId,
      courier_id: userData.user.id,
      status: "sent",
      last_error: null,
      attempted_at: new Date().toISOString(),
      sent_at: new Date().toISOString(),
    });
    return jsonResponse({ success: true });
  } catch (error) {
    console.error("send-courier-package-email error:", error);
    return jsonResponse({ error: "internal_error" }, 500);
  }
});

