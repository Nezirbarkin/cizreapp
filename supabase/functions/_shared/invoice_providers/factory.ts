import type { InvoiceProvider } from "./types.ts";
import { NilveraProvider } from "./nilvera.ts";
import { ParasutProvider } from "./parasut.ts";

export function getInvoiceProvider(
  provider: string,
  environment: string,
): InvoiceProvider {
  const env = environment === "live" ? "live" : "test";
  switch (provider) {
    case "nilvera":
      return new NilveraProvider(env);
    case "parasut":
      return new ParasutProvider(env);
    default:
      throw new Error(`unknown_invoice_provider: ${provider}`);
  }
}
