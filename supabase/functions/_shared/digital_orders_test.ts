import {
  assertEquals,
  assertThrows,
} from "https://deno.land/std@0.224.0/assert/mod.ts";
import {
  cumulativeRefund,
  mapProviderStatus,
  refundEventKey,
} from "./digital_orders.ts";

Deno.test("kısmi iade server gross ve remains ile kümülatif hesaplanır", () => {
  assertEquals(cumulativeRefund(123.45, 1000, 250, false), 30.86);
  assertEquals(cumulativeRefund(123.45, 1000, 250, true), 123.45);
  assertThrows(() => cumulativeRefund(10, 5, 6, false));
});

Deno.test("manuel ve otomatik yollar aynı deterministik refund key üretir", () => {
  assertEquals(
    refundEventKey("order", "partial", 30.86),
    "provider-outcome:order:partial:3086",
  );
});

Deno.test("belirsiz provider statüsü pending kalır ve refund terminali sayılmaz", () => {
  assertEquals(mapProviderStatus("unknown"), "pending");
  assertEquals(mapProviderStatus("Canceled"), "canceled");
});
