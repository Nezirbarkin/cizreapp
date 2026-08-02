interface QueryResult {
  data: unknown;
  error: unknown;
}

interface QueryBuilder extends PromiseLike<QueryResult> {
  update(values: Record<string, unknown>): QueryBuilder;
  select(columns?: string): QueryBuilder;
  eq(column: string, value: unknown): QueryBuilder;
  maybeSingle(): Promise<QueryResult>;
  single(): Promise<QueryResult>;
}

interface SupabaseLike {
  rpc(name: string, params: Record<string, unknown>): PromiseLike<QueryResult>;
  from(table: string): QueryBuilder;
}

export interface DigitalOrderPayment {
  id: string;
  user_id: string;
  product_id: string;
  provider_id: string;
  quantity: number;
  gross_total_try: number;
  status: string;
  seller_credited: boolean;
  external_order_id?: string | null;
  start_count?: number | null;
  reconciliation_status: string;
}

export function cumulativeRefund(
  gross: number,
  quantity: number,
  remains: number,
  final: boolean,
): number {
  if (final) return money(gross);
  if (
    !Number.isInteger(remains) || remains < 0 || !Number.isInteger(quantity) ||
    quantity <= 0 || remains > quantity
  ) {
    throw new Error("INVALID_REMAINS");
  }
  return money(gross * remains / quantity);
}

export function refundEventKey(
  orderId: string,
  status: string,
  cumulative: number,
): string {
  return `provider-outcome:${orderId}:${status}:${
    Math.round(cumulative * 100)
  }`;
}

export async function refundComposition(
  supabase: unknown,
  order: Pick<DigitalOrderPayment, "id">,
  status: string,
  cumulative: number,
  reason: string,
  final: boolean,
): Promise<unknown> {
  const { data, error } = await asSupabase(supabase).rpc(
    "refund_digital_order_payment",
    {
      p_digital_order_id: order.id,
      p_cumulative_refund_try: cumulative,
      p_idempotency_key: refundEventKey(order.id, status, cumulative),
      p_reason: reason.slice(0, 1000),
      p_is_final: final,
    },
  );
  if (error) throw new Error("REFUND_RPC_FAILED");
  return data;
}

export async function setReconciliation(
  supabase: unknown,
  orderId: string,
  state: string,
): Promise<void> {
  const { error } = await asSupabase(supabase).rpc(
    "set_digital_order_reconciliation",
    {
      p_digital_order_id: orderId,
      p_state: state,
    },
  );
  if (error) throw new Error("RECONCILIATION_RPC_FAILED");
}

export async function creditSellerOnce(
  supabase: unknown,
  order: DigitalOrderPayment,
  deliveredRatio: number,
): Promise<void> {
  if (deliveredRatio <= 0) return;
  const { error } = await asSupabase(supabase).rpc(
    "credit_digital_order_seller",
    {
      p_digital_order_id: order.id,
      p_delivered_ratio: deliveredRatio,
    },
  );
  if (error) throw new Error("SELLER_CREDIT_FAILED");
}

export function mapProviderStatus(raw: unknown): string {
  const status = typeof raw === "string" ? raw.toLowerCase() : "";
  if (status.includes("complete")) return "completed";
  if (status.includes("partial")) return "partial";
  if (status.includes("cancel")) return "canceled";
  if (status.includes("refund")) return "refunded";
  if (status.includes("progress") || status.includes("processing")) {
    return "in_progress";
  }
  return "pending";
}

function money(value: number): number {
  return Math.round((value + Number.EPSILON) * 100) / 100;
}

function asSupabase(value: unknown): SupabaseLike {
  return value as SupabaseLike;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === "object";
}
