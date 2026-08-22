// Nilvera e-Fatura/e-Arşiv adaptörü.
//
// Doğrulanan bilgiler (developer.nilvera.com, 2026-08 araştırması):
//   - Base URL: canlı https://api.nilvera.com, test https://apitest.nilvera.com
//   - Auth: Authorization: Bearer {API_KEY} (Nilvera portalından alınan opak token)
//   - Ortam bazlı ayrı API anahtarı gerekir (test hesabı != canlı hesap)
//   - İki profil var: TEMELFATURA (alıcı onayı gerekmez) / TİCARİFATURA (alıcı reddedebilir)
//
// DOĞRULANAMAYAN (canlıya almadan önce Nilvera portalından Swagger indirip teyit et):
//   - Gönderim endpoint'inin tam path'i ve request body alan isimleri
//   - KDV oranı/kalem şeması
//
// Aşağıdaki path ve body alanları Nilvera'nın dokümantasyon başlıklarından
// ("Faturayı Model Olarak Gönderir") çıkarılan EN İYİ TAHMİNDİR. Yanlışsa
// sağlayıcı 4xx döner, worker bunu invoices.error_message'a yazar — otomatik
// GİB gönderimi zaten yok (admin onayından sonra devreye girer), bu yüzden
// yanlış bir tahmin resmi bir fatura kesilmesine yol açmaz, sadece görünür
// bir hata üretir.

import type { InvoiceDraft, InvoiceProvider, InvoiceResult } from "./types.ts";

export class NilveraProvider implements InvoiceProvider {
  private readonly baseUrl: string;
  private readonly apiKey: string;

  constructor(environment: "test" | "live") {
    this.baseUrl = environment === "live"
      ? "https://api.nilvera.com"
      : "https://apitest.nilvera.com";
    this.apiKey = Deno.env.get("NILVERA_API_KEY") ?? "";
    if (!this.apiKey) {
      throw new Error("NILVERA_API_KEY tanımlı değil (Supabase secrets)");
    }
  }

  async createInvoice(draft: InvoiceDraft): Promise<InvoiceResult> {
    const profile = draft.invoiceType === "e-fatura" ? "TICARIFATURA" : "TEMELFATURA";

    // TODO(doğrula): Gerçek endpoint path'i ve gövde şeması Nilvera
    // Swagger'ından (developer.nilvera.com portal girişi ile) teyit
    // edilmeden bu satır güvenilir kabul edilmemeli.
    const endpoint = draft.invoiceType === "e-fatura"
      ? "/einvoice/Send/Model"
      : "/earchive/Send/Model";

    const body = {
      InvoiceProfile: profile,
      CurrencyCode: "TRY",
      InvoiceType: draft.invoiceType === "e-fatura" ? "SATIS" : undefined,
      Customer: {
        Name: draft.buyer.fullName,
        TaxNumber: draft.buyer.taxNumber || draft.buyer.tcNo || undefined,
        TaxOffice: draft.buyer.taxOffice || undefined,
        Address: draft.buyer.address || undefined,
        Email: draft.buyer.email || undefined,
      },
      Lines: draft.items.map((item) => ({
        Name: item.name,
        Quantity: item.quantity,
        UnitPrice: item.unitPrice,
      })),
      Note: draft.note,
    };

    const response = await fetch(`${this.baseUrl}${endpoint}`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${this.apiKey}`,
      },
      body: JSON.stringify(body),
    });

    if (!response.ok) {
      const errorText = await response.text();
      throw new Error(
        `nilvera_${response.status}: ${errorText.slice(0, 300)}`,
      );
    }

    const result = await response.json();
    const externalId = result?.InvoiceId ?? result?.UUID ?? result?.Id;
    if (!externalId) {
      throw new Error("nilvera_response_missing_id");
    }

    return {
      externalId: String(externalId),
      invoiceNumber: result?.InvoiceNumber ?? undefined,
      pdfUrl: result?.PdfUrl ?? undefined,
      ublXmlUrl: result?.XmlUrl ?? undefined,
    };
  }
}
