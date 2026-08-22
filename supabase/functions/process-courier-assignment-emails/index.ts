import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

interface AssignmentEmailClaim {
  outbox_id: string;
  notification_id: string;
  courier_id: string;
  entity_type: "order" | "package";
  entity_id: string;
  notification_type: string;
  attempt_number: number;
}

const workerId = `courier-email-${crypto.randomUUID()}`;
const maxAttempts = 8;

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

function constantTimeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let result = 0;
  for (let i = 0; i < a.length; i++) {
    result |= a.charCodeAt(i) ^ b.charCodeAt(i);
  }
  return result === 0;
}

function isAuthorized(req: Request): boolean {
  const expected = Deno.env.get("INTERNAL_WORKER_SECRET") ?? "";
  if (!expected) return false;

  const workerSecret = req.headers.get("x-worker-secret") ?? "";
  const authorization = req.headers.get("authorization") ?? "";
  const bearer = authorization.toLowerCase().startsWith("bearer ")
    ? authorization.slice(7).trim()
    : "";

  return constantTimeEqual(workerSecret, expected) ||
    constantTimeEqual(bearer, expected);
}

function escapeHtml(value: unknown): string {
  return String(value ?? "-")
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#039;");
}

function money(value: unknown): string {
  const parsed = typeof value === "number" ? value : Number(value ?? 0);
  return Number.isFinite(parsed) ? parsed.toFixed(2) : "0.00";
}

async function sendEmail(
  apiKey: string,
  to: string,
  subject: string,
  html: string,
): Promise<void> {
  const response = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "Authorization": `Bearer ${apiKey}`,
    },
    body: JSON.stringify({
      from: "CizreApp <noreply@cizreapp.com>",
      to,
      subject,
      html,
    }),
  });

  if (!response.ok) {
    // Sağlayıcının ham yanıtını loglamıyoruz; PII veya sağlayıcı ayrıntısı
    // içerebilir. Retry için yalnız güvenli durum kodu tutulur.
    await response.text();
    throw new Error(`email_provider_${response.status}`);
  }
}

async function getCourierIdentity(admin: any, courierId: string) {
  const [{ data: authData, error: authError }, { data: profile }] =
    await Promise.all([
      admin.auth.admin.getUserById(courierId),
      admin
        .from("profiles")
        .select("full_name, username")
        .eq("id", courierId)
        .maybeSingle(),
    ]);

  if (authError) throw new Error("courier_auth_lookup_failed");
  const email = authData.user?.email?.trim();
  if (!email) throw new Error("courier_email_not_found");

  return {
    email,
    name: profile?.full_name || profile?.username || "Kurye",
  };
}

async function buildOrderEmail(admin: any, claim: AssignmentEmailClaim) {
  const { data: assignment, error } = await admin
    .from("courier_assignments")
    .select(
      "courier_id, status, fee_amount, orders!inner(id, total, delivery_address_text, shops!inner(name))",
    )
    .eq("order_id", claim.entity_id)
    .eq("courier_id", claim.courier_id)
    .in("status", ["assigned", "picked_up", "on_the_way"])
    .maybeSingle();

  if (error) throw new Error("order_assignment_lookup_failed");
  if (!assignment?.orders) throw new Error("assignment_no_longer_current");

  const order = assignment.orders as Record<string, any>;
  const shop = order.shops as Record<string, any> | null;
  const courier = await getCourierIdentity(admin, claim.courier_id);
  const heading = "🛵 Sipariş size atandı";

  return {
    to: courier.email,
    subject: `${heading} - #${escapeHtml(order.id)}`,
    html:
      `<!doctype html><html><body style="font-family:Arial,sans-serif;color:#263238">
      <div style="max-width:600px;margin:auto;padding:24px">
        <h2 style="color:#00897b">${heading}</h2>
        <p>Merhaba ${
        escapeHtml(courier.name)
      }, bir sipariş teslimatı hesabınıza atandı.</p>
        <table style="width:100%;border-collapse:collapse">
          <tr><td style="padding:8px;border-bottom:1px solid #eee"><b>Sipariş</b></td><td>#${
        escapeHtml(order.id)
      }</td></tr>
          <tr><td style="padding:8px;border-bottom:1px solid #eee"><b>Mağaza</b></td><td>${
        escapeHtml(shop?.name || "Mağaza")
      }</td></tr>
          <tr><td style="padding:8px;border-bottom:1px solid #eee"><b>Sipariş tutarı</b></td><td>₺${
        money(order.total)
      }</td></tr>
          <tr><td style="padding:8px;border-bottom:1px solid #eee"><b>Kurye kazancı</b></td><td>₺${
        money(assignment.fee_amount)
      }</td></tr>
          <tr><td style="padding:8px"><b>Teslimat adresi</b></td><td>${
        escapeHtml(order.delivery_address_text)
      }</td></tr>
        </table>
        <p style="color:#607d8b">Güncel detayları CizreApp kurye panelinin Siparişler bölümünde görüntüleyebilirsiniz.</p>
      </div></body></html>`,
  };
}

async function buildPackageEmail(admin: any, claim: AssignmentEmailClaim) {
  const [packageResult, latestRouteResult] = await Promise.all([
    admin
      .from("courier_requests")
      .select(
        "id, status, courier_id, pickup_address, delivery_address, total_fee, courier_fee",
      )
      .eq("id", claim.entity_id)
      .maybeSingle(),
    admin
      .from("notifications")
      .select("id, user_id")
      .eq("entity_id", claim.entity_id)
      .in("type", ["package_route", "new_package_request"])
      .order("created_at", { ascending: false })
      .limit(1)
      .maybeSingle(),
  ]);

  const { data: packageRequest, error } = packageResult;
  const { data: latestRoute, error: latestRouteError } = latestRouteResult;

  if (error) throw new Error("package_lookup_failed");
  if (latestRouteError) throw new Error("package_route_lookup_failed");
  if (!packageRequest || packageRequest.status !== "pending") {
    throw new Error("package_no_longer_pending");
  }
  // A kuryesinin reddinden sonra B kuryesi için yeni notification oluşur. Eski
  // A outbox kaydı henüz işlenmediyse artık ona e-posta göndermemeliyiz.
  if (
    latestRoute?.id !== claim.notification_id ||
    latestRoute?.user_id !== claim.courier_id
  ) {
    throw new Error("package_route_no_longer_current");
  }

  const courier = await getCourierIdentity(admin, claim.courier_id);
  const reassigned = claim.notification_type === "new_package_request";
  const heading = reassigned
    ? "📦 Paket talebi size yönlendirildi"
    : "📦 Yeni paket talebi";

  return {
    to: courier.email,
    subject: heading,
    html:
      `<!doctype html><html><body style="font-family:Arial,sans-serif;color:#263238">
      <div style="max-width:600px;margin:auto;padding:24px">
        <h2 style="color:#e65100">${heading}</h2>
        <p>Merhaba ${
        escapeHtml(courier.name)
      }, incelemeniz için bir Paket+ talebi yönlendirildi.</p>
        <table style="width:100%;border-collapse:collapse">
          <tr><td style="padding:8px;border-bottom:1px solid #eee"><b>Alım</b></td><td>${
        escapeHtml(packageRequest.pickup_address)
      }</td></tr>
          <tr><td style="padding:8px;border-bottom:1px solid #eee"><b>Teslim</b></td><td>${
        escapeHtml(packageRequest.delivery_address)
      }</td></tr>
          <tr><td style="padding:8px;border-bottom:1px solid #eee"><b>Toplam ücret</b></td><td>₺${
        money(packageRequest.total_fee)
      }</td></tr>
          <tr><td style="padding:8px"><b>Kurye kazancı</b></td><td>₺${
        money(packageRequest.courier_fee)
      }</td></tr>
        </table>
        <p style="color:#607d8b">Talep henüz kesin olarak atanmadı. CizreApp kurye panelinden kabul edebilirsiniz.</p>
      </div></body></html>`,
  };
}

function isTerminalSkip(error: unknown): boolean {
  const message = error instanceof Error ? error.message : "";
  return message === "assignment_no_longer_current" ||
    message === "package_no_longer_pending" ||
    message === "package_route_no_longer_current" ||
    message === "courier_email_not_found";
}

serve(async (req: Request) => {
  if (req.method !== "POST") {
    return jsonResponse({ error: "method_not_allowed" }, 405);
  }
  if (!isAuthorized(req)) return jsonResponse({ error: "unauthorized" }, 401);

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const resendApiKey = Deno.env.get("RESEND_API_KEY");
  if (!supabaseUrl || !serviceRoleKey || !resendApiKey) {
    return jsonResponse({ error: "server_not_configured" }, 500);
  }

  const admin = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  try {
    await admin.rpc("release_stale_courier_assignment_emails", {
      p_max_age: "5 minutes",
    });
    const { data, error } = await admin.rpc("claim_courier_assignment_emails", {
      p_limit: 25,
      p_worker_id: workerId,
    });
    if (error) throw new Error("email_claim_failed");

    const claims = (data ?? []) as AssignmentEmailClaim[];
    let sent = 0;
    let failed = 0;
    let skipped = 0;

    for (const claim of claims) {
      try {
        const message = claim.entity_type === "order"
          ? await buildOrderEmail(admin, claim)
          : await buildPackageEmail(admin, claim);
        await sendEmail(
          resendApiKey,
          message.to,
          message.subject,
          message.html,
        );
        await admin.rpc("mark_courier_assignment_email_sent", {
          p_outbox_id: claim.outbox_id,
        });
        sent++;
      } catch (error) {
        if (isTerminalSkip(error)) {
          // Atama bu sırada değişmişse eski kuryeye e-posta gönderme; kayıt
          // tamamlanmış sayılır. Yeni atamanın kendi notification/outbox kaydı vardır.
          await admin.rpc("mark_courier_assignment_email_sent", {
            p_outbox_id: claim.outbox_id,
          });
          skipped++;
          continue;
        }

        const safeError = error instanceof Error ? error.message : "unknown";
        await admin.rpc("mark_courier_assignment_email_failed", {
          p_outbox_id: claim.outbox_id,
          p_error: safeError.slice(0, 200),
          p_max_attempts: maxAttempts,
        });
        failed++;
      }
    }

    return jsonResponse({ processed: claims.length, sent, failed, skipped });
  } catch (error) {
    const safeError = error instanceof Error ? error.message : "unknown";
    console.error(
      `courier_assignment_email_worker_error=${safeError.slice(0, 120)}`,
    );
    return jsonResponse({ error: "worker_error" }, 500);
  }
});
