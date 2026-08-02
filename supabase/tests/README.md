# Supabase güvenlik testleri

Bu dizindeki pgTAP paketleri:

- [`001_critical_security_invariants.test.sql`](database/001_critical_security_invariants.test.sql): kritik finans ve operasyon tablolarının genel güvenlik değişmezlerini katalog düzeyinde doğrular.
- [`002_reward_points_security_invariants.test.sql`](database/002_reward_points_security_invariants.test.sql): [`20260730000002_admob_reward_points_system.sql`](../migrations/20260730000002_admob_reward_points_system.sql:1) için **26** ödül puanı/SSV/composition güvenlik assertion'ı çalıştırır.

## Çalıştırma

1. Docker Desktop'ı başlatın.
2. Proje kökünde `supabase start` çalıştırın.
3. Yerel veritabanını migration'larla kurmak için `supabase db reset` çalıştırın.
4. Testleri `supabase test db` ile çalıştırın.

Test paketi şu kontrolleri yapar:

- Kritik tabloların varlığı ve RLS durumları.
- `anon` rolünün finans tablolarına erişememesi.
- `authenticated` rolünün bakiye, dijital sipariş ve reklam ödülü tablolarına doğrudan yazamaması.
- Iyzico API ve secret kolonlarının istemci tarafından okunabilen ayarlar tablosundan kaldırılmış olması.
- `SECURITY DEFINER` fonksiyonlarının `PUBLIC` veya `anon` rolüne açık olmaması.

Ödül puanı paketi ayrıca şunları doğrular:

- Altı kritik operasyon tablosunun (`user_point_accounts`, `point_ledger_entries`, `ad_reward_sessions`, `ad_reward_ssv_events`, `ad_reward_daily_budgets`, `digital_order_refunds`) varlığı; account, ledger ve SSV event tablolarında RLS'nin açık olması.
- `anon` rolünün yeni tablolara okuyamaması; `authenticated` kullanıcının ledger veya ödül tablolarına doğrudan yazamaması.
- `service_role` rolünün bile append-only [`point_ledger_entries`](../migrations/20260730000002_admob_reward_points_system.sql:84) tablosunda doğrudan UPDATE/DELETE yapamaması ve immutable trigger'ların bulunması.
- Doğrulanmış SSV kredi RPC'sinin istemci rollerine kapalı, yalnız `service_role` rolüne açık olması.
- Legacy TL reklam grant imzası ile eski dijital checkout imzasının kapalı olması.
- Composition-aware iade RPC'sinin istemci rollerine kapalı olması.
- SSV/fraud tablolarında ham IP, cihaz kimliği, raw query veya imza kolonu bulunmaması.
- Puan tablolarından TL bakiye/işlem tablolarına FK bulunmaması.
- Geçmiş TL reklam kayıtlarından puan backfill'i yapılmaması.
- Testte listelenen SSV/session/composition/config güvenlik-definer RPC'lerinin sabit `search_path` kullanması.

Testler transaction sonunda rollback yapar. Her yeni finansal/puan tablosu veya yetkili RPC eklendiğinde ilgili katalog ve rol matrisi assertion'ları genişletilmelidir.

GitHub Actions üzerinde aynı akış [`security-database.yml`](../../.github/workflows/security-database.yml) tarafından çalıştırılır. Workflow, temiz bir yerel Supabase veritabanı kurduğu için migration zincirindeki eksik veya çakışan dosyaları da ortaya çıkarır.
