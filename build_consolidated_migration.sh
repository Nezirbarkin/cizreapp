#!/usr/bin/env bash
# =============================================================================
# build_consolidated_migration.sh
# =============================================================================
# 20260804000002_fill_app_contract_gaps.sql dosyasini, TESHIS raporundaki
# eksik nesneleri tanimlayan mevcut migration'lari (verbatim) birlestirerek
# ve 3 surgical duzeltmeyi uygulayarak olusturur:
#   (1) prepare_checkout_session / commit_cod_order / commit_balance_order
#       fonksiyonlarini `private` semasindan `public` semasina tasir, boylece
#       PostgREST onlari expose eder (GRANT/REVOKE/COMMENT dahil).
#   (2) cancel_order'un private.server_checkout_audit INSERT'ini olmayan
#       kolonlardan (order_id, payload) gercek kolonlara (detail) duzeltir.
#   (3) checkout semasindaki olmayan tabloya (server_checkout_session_items)
#       yapilan GRANT satirini kaldirir.
#
# Kullanim:  bash build_consolidated_migration.sh
# =============================================================================
set -euo pipefail
cd "$(dirname "$0")"

OUT="supabase/migrations/20260804000002_fill_app_contract_gaps.sql"

# --- Inline parcalar (Write ile hazirlandi) ---
COMMISSION_PART="supabase/migrations/_part_consolidated_commission_views.sql"
PROFILE_PART="supabase/migrations/_part_consolidated_profile_objects.sql"
NEWOBJ_PART="supabase/migrations/_part_consolidated_new_objects.sql"

# --- Verbatim kaynak migration'lar (dependency sirasiyla) ---
SRC_REWARD="supabase/migrations/20260730000002_admob_reward_points_system.sql"
SRC_OVERVIEW="supabase/migrations/20260801000001_admin_reward_points_overview.sql"
SRC_CHECKOUT_SCHEMA="supabase/migrations/20260802000005_server_authoritative_checkout_schema.sql"
SRC_PREPARE="supabase/migrations/20260802000006_prepare_checkout_session_rpc.sql"
SRC_COMMIT="supabase/migrations/20260802000007_commit_cod_and_balance_orders.sql"
SRC_ORDER_SM="supabase/migrations/20260802000010_order_state_machine_rpc.sql"

for f in "$COMMISSION_PART" "$PROFILE_PART" "$NEWOBJ_PART" \
         "$SRC_REWARD" "$SRC_OVERVIEW" "$SRC_CHECKOUT_SCHEMA" \
         "$SRC_PREPARE" "$SRC_COMMIT" "$SRC_ORDER_SM"; do
  if [ ! -f "$f" ]; then
    echo "EKSIK: $f" >&2
    exit 1
  fi
done

# ---------------------------------------------------------------------------
# 1) HEADER parcasini olustur (build script inline yazar; ayar dosyasi yok).
# ---------------------------------------------------------------------------
cat > "$OUT" <<'HEADER'
-- =============================================================================
-- 20260804000002_fill_app_contract_gaps.sql
-- =============================================================================
-- Tek dosyalik, KONSOLIDE uygulama kontrati duzeltmesi.
--
-- KAYNAK: CIZREAPP_TESHIS.sql raporunun isaret ettigi eksik nesneleri olusturur:
--   * 7 eksik RPC: admin_reward_points_overview, cancel_order,
--     commit_balance_order, commit_cod_order, ensure_my_profile,
--     prepare_checkout_session, set_my_presence
--   * Eksik tablo/view: user_point_accounts, reward_points_public_config,
--     my_point_ledger_entries, my_ad_reward_sessions, public_profiles_safe,
--     v_admin_commission_dashboard, v_debt_orders, api_keys
--   * RLS SELECT policy: news_views
--   * Yetki: smm_providers (kolon-bazli SELECT grant)
--
-- NOTLAR:
--   1) "EKSIK TABLO" sanilan avatars, covers, deals, public, task_images,
--      task_screenshots aslinda STORAGE BUCKET'tur; bu dosya tablo olusturmaz.
--   2) prepare_checkout_session / commit_cod_order / commit_balance_order
--      ORIJINAL migrationlarda `private` semasindaydi. PostgREST yalniz
--      `public` semasini expose ettigi icin uygulama cagiramazdi. Bu dosya
--      onlari `public` semasinda olusturur (SECURITY DEFINER; private
--      tablolara dahili erisir).
--   3) cancel_order, private.server_checkout_audit'e olmayan kolonlara
--      (order_id, payload) yaziyordu; gercek kolonlara (detail) duzeltildi.
--
-- UYGULAMA: Supabase Dashboard > SQL Editor > TAMAMINI yapistir > Run.
-- =============================================================================


-- BOLUM 0: order_number_seq (commit_*_order RPC'leri nextval kullanir)
CREATE SEQUENCE IF NOT EXISTS public.order_number_seq;


HEADER

# ---------------------------------------------------------------------------
# 2) Birlestir: header + verbatim kaynaklar + inline parcalar
# ---------------------------------------------------------------------------
cat "$SRC_REWARD"                     >> "$OUT"; printf '\n' >> "$OUT"
cat "$SRC_OVERVIEW"                   >> "$OUT"; printf '\n' >> "$OUT"
cat "$SRC_CHECKOUT_SCHEMA"            >> "$OUT"; printf '\n' >> "$OUT"
cat "$SRC_PREPARE"                    >> "$OUT"; printf '\n' >> "$OUT"
cat "$SRC_COMMIT"                     >> "$OUT"; printf '\n' >> "$OUT"
cat "$SRC_ORDER_SM"                   >> "$OUT"; printf '\n' >> "$OUT"
cat "$COMMISSION_PART"                >> "$OUT"; printf '\n' >> "$OUT"
cat "$PROFILE_PART"                   >> "$OUT"; printf '\n' >> "$OUT"
cat "$NEWOBJ_PART"                    >> "$OUT"; printf '\n' >> "$OUT"

# ---------------------------------------------------------------------------
# 3) Surgical duzeltmeler (alinan verbatim metin uzerinde)
# ---------------------------------------------------------------------------

# (3a/b) 3 RPC'yi private -> public semasina tasi. Bare-name degistirme,
#        CREATE/REVOKE/GRANT/COMMENT satirlarinin HEPSINI yakalar (COMMENT
#        satirinda parantez yoktur). Bu fonksiyon adlari govdede baska yerde
#        tablo referansi olarak gecmez (tablolar: private.server_checkout_sessions,
#        private.flash_sale_reservations, private.server_checkout_audit).
sed -i 's/private\.prepare_checkout_session/public.prepare_checkout_session/g' "$OUT"
sed -i 's/private\.commit_cod_order/public.commit_cod_order/g' "$OUT"
sed -i 's/private\.commit_balance_order/public.commit_balance_order/g' "$OUT"

# (3c) cancel_order: olmayan kolonlara (order_id, payload) yazan audit INSERT'ini
#      gercek kolonlara (detail) cevir. Iki benzersiz satir-bazli sed. Bu desenler
#      yalniz cancel_order'da gecer (prepare/commit (session_id, user_id, event_type, detail) kullanir).
sed -i 's/(event_type, user_id, order_id, payload)/(event_type, user_id, detail)/' "$OUT"
sed -i "s/('order_cancelled', v_user_id, p_order_id, v_audit);/('order_cancelled', v_user_id, v_audit);/" "$OUT"

# (3d) checkout semasi: olmayan tabloya (server_checkout_session_items) GRANT'i kaldir.
sed -i '/GRANT ALL ON private\.server_checkout_session_items TO service_role;/d' "$OUT"

echo "Olusturuldu: $OUT  ($(wc -l < "$OUT") satir)"
