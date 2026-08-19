#!/usr/bin/env bash
# =============================================================================
# Edge Function RPC/şema sözleşme denetimi
#
# NEDEN VAR:
#   iyzico-payment-callback dört çağrı yerinde
#     supabase.rpc("private.atomic_finalize_payment_transaction", {...})
#   biçimini kullanıyordu. Bu sessizce bozuk bir çağrıdır:
#     - supabase-js .rpc() çıplak fonksiyon adı bekler; nokta içeren ad
#       PostgREST'te public."private.foo" olarak aranır ve PGRST202 döner.
#     - Doğru sözdizimi (.schema('private')) kullanılsa bile private şeması
#       PostgREST'e expose edilmemiş durumda; PGRST106 döner.
#   Sonuç: online ödeme akışı derlenir, lint'ten geçer, deploy edilir ve
#   çalışma zamanında tamamen kırılır.
#
#   Aynı sınıftan ikinci hata: .from("server_checkout_sessions") — şema
#   niteliği olmadan private tablo okumaya çalışmak. Sorgu her zaman boş
#   döner, hata da vermez.
#
# BU BETİK bu iki kalıbı CI'da yakalar, böylece bir daha canlıya gidemez.
# =============================================================================

set -uo pipefail

FUNCTIONS_DIR="${1:-supabase/functions}"
status=0

# Yorum satirlarini ele (aciklama metinlerinde kalibi anlatiyoruz).
strip_comments() {
  grep -vE '^[^:]*:[0-9]+:[[:space:]]*(//|\*|/\*)'
}

fail() {
  status=1
  echo "❌ $1"
}

echo "🔍 Edge Function RPC sözleşmesi denetleniyor: $FUNCTIONS_DIR"
echo

# ---------------------------------------------------------------------------
# 1) rpc("private.foo") / rpc('private.foo') — geçersiz supabase-js kullanımı
# ---------------------------------------------------------------------------
if hits=$(grep -rnE '\.rpc\(\s*["'"'"']private\.' "$FUNCTIONS_DIR" 2>/dev/null | strip_comments) && [ -n "$hits" ]; then
  fail 'rpc() içinde şema nitelikli ad kullanılmış (PGRST202 ile kırılır):'
  echo "$hits" | sed 's/^/     /'
  echo
  echo '   Düzeltme: fonksiyonu public şemada oluşturup EXECUTE yetkisini'
  echo '   yalnızca service_role'"'"'e verin, sonra çıplak adla çağırın:'
  echo '     supabase.rpc("commit_online_order", { ... })'
  echo
fi

# ---------------------------------------------------------------------------
# 2) .schema("private") — PostgREST'e expose edilmemiş şema
# ---------------------------------------------------------------------------
if hits=$(grep -rnE '\.schema\(\s*["'"'"']private["'"'"']\s*\)' "$FUNCTIONS_DIR" 2>/dev/null | strip_comments) && [ -n "$hits" ]; then
  fail '.schema("private") kullanılmış (PGRST106 ile kırılır):'
  echo "$hits" | sed 's/^/     /'
  echo
  echo '   private şeması PostgREST tarafından expose edilmiyor.'
  echo '   Erişim için service_role'"'"'e açık bir public RPC yazın'
  echo '   (örnek: public.link_checkout_session_payment).'
  echo
fi

# ---------------------------------------------------------------------------
# 3) private tabloları şema niteliği olmadan .from() ile okumak
#    Sessizce boş döner; hata vermez.
# ---------------------------------------------------------------------------
PRIVATE_TABLES=(
  "server_checkout_sessions"
  "server_checkout_session_items"
  "flash_sale_reservations"
  "server_checkout_audit"
)

for table in "${PRIVATE_TABLES[@]}"; do
  if hits=$(grep -rnE "\.from\(\s*[\"']${table}[\"']\s*\)" "$FUNCTIONS_DIR" 2>/dev/null | strip_comments) && [ -n "$hits" ]; then
    fail "private.${table} şema niteliği olmadan .from() ile okunuyor (her zaman boş döner):"
    echo "$hits" | sed 's/^/     /'
    echo
  fi
done

echo
if [ "$status" -eq 0 ]; then
  echo "✅ Edge Function RPC sözleşmesi temiz"
else
  echo "💥 Denetim başarısız — yukarıdaki çağrılar çalışma zamanında kırılır."
fi

exit "$status"
