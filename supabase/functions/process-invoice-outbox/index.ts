// E-fatura gönderim kuyruğu worker'ı.
//
// TETİKLEYİCİLER: (1) invoice_outbox INSERT'ünde pg_net poke trigger'ı
// (20260820000001_invoice_infrastructure.sql), (2) yedek pg_cron (kurulursa).
// Kuyruğa satır, YALNIZCA admin panelden "Onayla ve Gönder" ile
// approve_invoice_and_enqueue() çağrıldığında girer — taslak (draft)
// faturalar bu worker'ın hiç görmediği bir durumdur.
//
// Auth: Kullanıcı JWT'si yok. INTERNAL_WORKER_SECRET zorunlu (mevcut
// outbox worker'larıyla aynı desen).

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { getInvoiceProvider } from "../_shared/invoice_providers/factory.ts";
import type { InvoiceDraft } from "../_shared/invoice_providers/types.ts";

interface InvoiceClaim {
  outbox_id: string;
  invoice_id: string;
  order_id: string;
  provider: string;
  environment: string;
  invoice_type: "e-fatura" | "e-arsiv";
  attempt_number: number;
}

const workerId = `invoice-${crypto.randomUUID()}`;
const maxAttempts = 6;

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

interface OrderItem {
  product_name: string;
  quantity: number;
  price: number;
}

async function buildInvoiceDraft(
  admin: any,
  claim: InvoiceClaim,
): Promise<InvoiceDraft> {
  const { data: order, error } = await admin
    .from("orders")
    .select(
      "id, total_amount, items, invoice_type, invoice_full_name, invoice_tax_number, invoice_tc_no, invoice_tax_office, invoice_address, invoice_email",
    )
    .eq("id", claim.order_id)
    .maybeSingle();

  if (error) throw new Error("order_lookup_failed");
  if (!order) throw new Error("order_not_found");

  if (!order.invoice_full_name) {
    // Fatura bilgisi opsiyonel toplandığı için (20260710000001) sipariş
    // anında girilmemiş olabilir — bu durumda gönderim admin'e görünür
    // biçimde 'error' düşer, admin siparişten fatura bilgisini tamamlatır.
    throw new Error("invoice_info_missing");
  }

  const invoiceType: "individual" | "corporate" = order.invoice_type === "corporate"
    ? "corporate"
    : "individual";

  const items: OrderItem[] = Array.isArray(order.items) ? order.items : [];
  if (items.length === 0) throw new Error("order_items_missing");

  return {
    orderId: order.id,
    invoiceType: claim.invoice_type,
    buyer: {
      invoiceType,
      fullName: order.invoice_full_name,
      taxNumber: order.invoice_tax_number,
      tcNo: order.invoice_tc_no,
      taxOffice: order.invoice_tax_office,
      address: order.invoice_address,
      email: order.invoice_email,
    },
    items: items.map((item) => ({
      name: item.product_name,
      quantity: item.quantity,
      unitPrice: item.price,
    })),
    grossAmount: Number(order.total_amount ?? 0),
    note: `CizreApp sipariş #${order.id}`,
  };
}

serve(async (req: Request) => {
  if (req.method !== "POST") {
    return jsonResponse({ error: "method_not_allowed" }, 405);
  }
  if (!isAuthorized(req)) return jsonResponse({ error: "unauthorized" }, 401);

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !serviceRoleKey) {
    return jsonResponse({ error: "server_not_configured" }, 500);
  }

  const admin = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  try {
    await admin.rpc("release_stale_invoice_outbox", { p_max_age: "5 minutes" });
    const { data, error } = await admin.rpc("claim_invoice_outbox", {
      p_limit: 10,
      p_worker_id: workerId,
    });
    if (error) throw new Error("invoice_claim_failed");

    const claims = (data ?? []) as InvoiceClaim[];
    let sent = 0;
    let failed = 0;

    for (const claim of claims) {
      try {
        const draft = await buildInvoiceDraft(admin, claim);
        const provider = getInvoiceProvider(claim.provider, claim.environment);
        const result = await provider.createInvoice(draft);

        await admin.rpc("mark_invoice_sent", {
          p_outbox_id: claim.outbox_id,
          p_external_id: result.externalId,
          p_invoice_number: result.invoiceNumber ?? null,
          p_pdf_url: result.pdfUrl ?? null,
          p_ubl_xml_url: result.ublXmlUrl ?? null,
        });
        sent++;
      } catch (error) {
        const safeError = error instanceof Error ? error.message : "unknown";
        await admin.rpc("mark_invoice_failed", {
          p_outbox_id: claim.outbox_id,
          p_error: safeError.slice(0, 500),
          p_max_attempts: maxAttempts,
        });
        failed++;
      }
    }

    return jsonResponse({ processed: claims.length, sent, failed });
  } catch (error) {
    const safeError = error instanceof Error ? error.message : "unknown";
    console.error(`invoice_outbox_worker_error=${safeError.slice(0, 200)}`);
    return jsonResponse({ error: "worker_error" }, 500);
  }
});
