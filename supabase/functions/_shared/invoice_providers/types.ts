// E-fatura sağlayıcı adaptör sözleşmesi. Nilvera ve Paraşüt birbirinin
// alternatifi olduğu için worker (process-invoice-outbox) hangi sağlayıcının
// aktif olduğunu bilmeden yalnızca bu arayüzle konuşur.
//
// ÖNEMLİ: Nilvera (developer.nilvera.com) ve Paraşüt (apidocs.parasut.com)
// dokümantasyon sayfaları JS ile render ediliyor; otomatik araştırmada tam
// alan-seviyesi şema doğrulanamadı. Aşağıdaki tipler ve nilvera.ts/parasut.ts
// içindeki request body eşlemesi BEST-EFFORT'tur — canlıya (environment=live)
// almadan önce hesap sahibi portale girip gerçek şemayı (Nilvera: Swagger,
// Paraşüt: apidocs.parasut.com) teyit etmeli.

export interface InvoiceLineItem {
  name: string;
  quantity: number;
  /** KDV hariç birim fiyat varsayımı — gerçek KDV oranı kaynağı henüz yok, bkz. TODO'lar. */
  unitPrice: number;
}

export interface InvoiceBuyer {
  invoiceType: "individual" | "corporate";
  fullName: string;
  /** VKN — kurumsal alıcı */
  taxNumber?: string | null;
  /** TCKN — bireysel alıcı */
  tcNo?: string | null;
  taxOffice?: string | null;
  address?: string | null;
  email?: string | null;
}

export interface InvoiceDraft {
  orderId: string;
  invoiceType: "e-fatura" | "e-arsiv";
  buyer: InvoiceBuyer;
  items: InvoiceLineItem[];
  grossAmount: number;
  note?: string;
}

export interface InvoiceResult {
  externalId: string;
  invoiceNumber?: string;
  pdfUrl?: string;
  ublXmlUrl?: string;
}

export interface InvoiceProvider {
  createInvoice(draft: InvoiceDraft): Promise<InvoiceResult>;
}
