// Paraşüt e-Fatura/e-Arşiv adaptörü.
//
// Doğrulanan bilgiler (2026-08 araştırması):
//   - Base URL: https://api.parasut.com/v4/{company_id}
//   - Auth: OAuth2, token endpoint https://api.parasut.com/oauth/token
//     (client_id/client_secret Paraşüt destek ekibinden e-posta ile alınır)
//   - Gövde formatı JSON:API (`{ data: { type, attributes, relationships } }`)
//   - Fatura oluşturma asenkron: sales_invoices -> e_invoices/e_archives ->
//     trackable_jobs/{id} polling ile sonuçlanır (~15 dk geçerli job id)
//
// DOĞRULANAMAYAN (canlıya almadan önce apidocs.parasut.com'dan, hesap
// sahibi girişiyle, teyit et — sayfa JS ile render olduğu için otomatik
// araştırmada çekilemedi):
//   - attributes içindeki tam alan isimleri (item_type, vat_rate vb.)
//   - e_invoices vs e_archives seçim kuralının tam response şekli
//
// Aynı gerekçeyle: yanlış alan ismi 4xx döner, worker error'a düşürür;
// admin onayı olmadan hiçbir gönderim gerçekleşmediği için risk sınırlı.

import type { InvoiceDraft, InvoiceProvider, InvoiceResult } from "./types.ts";

let cachedToken: string | null = null;
let tokenExpiry = 0;

async function getAccessToken(): Promise<string> {
  if (cachedToken && Date.now() < tokenExpiry) return cachedToken;

  const clientId = Deno.env.get("PARASUT_CLIENT_ID") ?? "";
  const clientSecret = Deno.env.get("PARASUT_CLIENT_SECRET") ?? "";
  const username = Deno.env.get("PARASUT_USERNAME") ?? "";
  const password = Deno.env.get("PARASUT_PASSWORD") ?? "";
  if (!clientId || !clientSecret || !username || !password) {
    throw new Error(
      "PARASUT_CLIENT_ID/PARASUT_CLIENT_SECRET/PARASUT_USERNAME/PARASUT_PASSWORD tanımlı değil (Supabase secrets)",
    );
  }

  const response = await fetch("https://api.parasut.com/oauth/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "password",
      client_id: clientId,
      client_secret: clientSecret,
      username,
      password,
    }),
  });

  if (!response.ok) {
    await response.text();
    throw new Error(`parasut_oauth_${response.status}`);
  }

  const data = await response.json();
  if (!data?.access_token) throw new Error("parasut_oauth_missing_token");

  cachedToken = data.access_token;
  tokenExpiry = Date.now() + (Number(data.expires_in ?? 7200) - 120) * 1000;
  return cachedToken!;
}

async function pollTrackableJob(
  baseUrl: string,
  token: string,
  jobId: string,
): Promise<string> {
  // TODO(doğrula): trackable_jobs response şekli third-party wrapper'lardan
  // çıkarıldı, resmi apidocs.parasut.com ile teyit edilmedi.
  for (let attempt = 0; attempt < 5; attempt++) {
    const response = await fetch(`${baseUrl}/trackable_jobs/${jobId}`, {
      headers: { Authorization: `Bearer ${token}` },
    });
    if (!response.ok) {
      await response.text();
      throw new Error(`parasut_job_poll_${response.status}`);
    }
    const data = await response.json();
    const status = data?.data?.attributes?.status;
    if (status === "finished") {
      const resultId = data?.data?.relationships?.result_data?.data?.id;
      if (!resultId) throw new Error("parasut_job_missing_result");
      return String(resultId);
    }
    if (status === "failed") {
      const errors = data?.data?.attributes?.errors;
      throw new Error(`parasut_job_failed: ${JSON.stringify(errors).slice(0, 300)}`);
    }
    await new Promise((resolve) => setTimeout(resolve, 2000));
  }
  throw new Error("parasut_job_timeout");
}

export class ParasutProvider implements InvoiceProvider {
  private readonly baseUrl: string;

  constructor(_environment: "test" | "live") {
    const companyId = Deno.env.get("PARASUT_COMPANY_ID") ?? "";
    if (!companyId) {
      throw new Error("PARASUT_COMPANY_ID tanımlı değil (Supabase secrets)");
    }
    // Paraşüt'te ortam ayrımı company_id/hesap seviyesinde yapılır (ayrı bir
    // staging hesabı Paraşüt destek ekibinden istenir), base URL sabittir.
    this.baseUrl = `https://api.parasut.com/v4/${companyId}`;
  }

  async createInvoice(draft: InvoiceDraft): Promise<InvoiceResult> {
    const token = await getAccessToken();

    const salesInvoiceBody = {
      data: {
        type: "sales_invoices",
        attributes: {
          item_type: "invoice",
          description: draft.note ?? `Sipariş ${draft.orderId}`,
          currency: "TRY",
          details: draft.items.map((item) => ({
            quantity: item.quantity,
            unit_price: item.unitPrice,
            // TODO(doğrula): vat_rate alanı ve satış kalemi ilişkisi
            // (product/relationships) resmi dokümanla teyit edilmeli.
            description: item.name,
          })),
        },
      },
    };

    const invoiceResponse = await fetch(`${this.baseUrl}/sales_invoices`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${token}`,
      },
      body: JSON.stringify(salesInvoiceBody),
    });

    if (!invoiceResponse.ok) {
      const errorText = await invoiceResponse.text();
      throw new Error(`parasut_sales_invoice_${invoiceResponse.status}: ${errorText.slice(0, 300)}`);
    }

    const invoiceData = await invoiceResponse.json();
    const salesInvoiceId = invoiceData?.data?.id;
    if (!salesInvoiceId) throw new Error("parasut_sales_invoice_missing_id");

    const eDocEndpoint = draft.invoiceType === "e-fatura" ? "e_invoices" : "e_archives";
    const eDocResponse = await fetch(`${this.baseUrl}/${eDocEndpoint}`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${token}`,
      },
      body: JSON.stringify({
        data: {
          type: eDocEndpoint,
          relationships: {
            sales_invoice: { data: { id: salesInvoiceId, type: "sales_invoices" } },
          },
        },
      }),
    });

    if (!eDocResponse.ok) {
      const errorText = await eDocResponse.text();
      throw new Error(`parasut_${eDocEndpoint}_${eDocResponse.status}: ${errorText.slice(0, 300)}`);
    }

    const eDocData = await eDocResponse.json();
    const jobId = eDocData?.data?.id;
    const externalId = jobId
      ? await pollTrackableJob(this.baseUrl, token, jobId)
      : salesInvoiceId;

    return { externalId: String(externalId) };
  }
}
