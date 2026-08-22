# Online Ödeme + Satıcı Kazançları — Uygulama Sırası

Tarih: 2026-08-17

Bu değişiklik seti **canlı ödeme sistemine** dokunuyor. Sıra önemli.
Migration'lar `supabase db push` ile **uygulanmamalı** (migration geçmişi
remote ile senkron değil); `supabase db query --linked --file` kullanın.

---

## Neden bu değişiklikler gerekti

İki ayrı sorun kümesi vardı.

**A) Sunucu-otoriteli online ödeme akışı hiçbir zaman çalışmadı.**
2026-08-02'de yazılan akış tasarım olarak doğru, ama üç bağımsız kusur
onu çalışamaz hâlde bırakmış:

1. `20260802000009` migration'ı 42P13 ile patlıyor (varsayılanlı parametreden
   sonra varsayılansız parametre) → `commit_online_order` hiç oluşmadı.
2. Edge Function'lar `rpc("private.foo")` ve `.schema("private")` kullanıyor;
   ikisi de PostgREST'te çalışmaz (PGRST202 / PGRST106).
3. `nextval('order_number_seq')` `search_path=''` altında çözülemez.

Bugün canlıda çalışan şey, **eski (v35, ~Haziran) callback sürümü** ve
istemci-otoriteli akış. Yani fiyatı Dart hesaplayıp gönderiyor.

**B) Üç canlı para deliği.** Bunlar A'dan bağımsız ve şu anda açık:

| Delik | Etki |
|---|---|
| `payment_transactions` UPDATE policy'sinde WITH CHECK yok | Kullanıcı kendi ödemesini `success` yapabilir |
| `seller_earnings` `FOR ALL USING (true)` | Herhangi bir kullanıcı kendine kazanç yazabilir |
| `shops` finansal sütunları satır-düzeyi RLS ile korunuyor | Satıcı `admin_credit`'ini yazıp geçerli payout talebi açabilir |

---

## Uygulama sırası

### Adım 1 — Güvenlik migration'ları (bağımsız, hemen uygulanabilir)

Bunlar mevcut akışı bozmaz; yalnızca istemci yazma yetkilerini kaldırır.

```bash
supabase db query --linked --file supabase/migrations/20260817000038_secure_payment_transactions_writes.sql
supabase db query --linked --file supabase/migrations/20260817000039_secure_seller_earnings_and_shop_financials.sql
supabase db query --linked --file supabase/migrations/20260817000042_fix_seller_earnings_summary_service_role.sql
```

> **Not:** 38 uygulandıktan sonra eski Flutter sürümlerindeki
> `cancelPaymentTransaction` doğrudan UPDATE'i başarısız olur. Bu çağrı zaten
> try/catch içinde ve "kritik değil" olarak işaretli, dolayısıyla kullanıcı
> etkisi yok. Yeni sürüm RPC kullanıyor.

### Adım 2 — Ödeme backend'ini oluştur

```bash
supabase db query --linked --file supabase/migrations/20260817000040_online_payment_finalizer_repair.sql
```

Bu migration `complete_online_payment`'ı **kaldırmaz** — canlıdaki v35
callback hâlâ onu çağırıyor. Eski 15 parametreli
`atomic_finalize_payment_transaction` düşürülüp 16 parametreli sürümle
değiştirilir; yeni parametrenin (`p_md_status`) varsayılanı olduğu için
**eski callback'in 15 adlandırılmış parametreli çağrısı çalışmaya devam
eder** (a97a422 sürümünden doğrulandı).

Yeni finalizer'daki mutabakat kontrolleri (tutar/kur/ortam/fraud) yalnızca
`checkout_session_id` dolu olan kayıtlarda çalışır. Eski akışla oluşan
kayıtlarda bu alan NULL'dur, dolayısıyla eski davranış birebir korunur.
Bu özellikle fraud kontrolü için önemli: eski callback `fraudStatus=1`
şartını sadece production'da uyguluyordu ("sandbox'ta fraudStatus 0
olabiliyor"), koşulsuz uygulansaydı meşru ödemeler failure işaretlenirdi.

### Adım 3 — Edge Function'ları deploy et

```bash
supabase functions deploy iyzico-payment-init
supabase functions deploy iyzico-payment-callback
supabase functions deploy use-balance-for-order
supabase functions deploy request-withdrawal
```

### Adım 4 — Eski finalizer'ı kaldır (yalnızca Adım 3'ten SONRA)

```bash
supabase db query --linked --file supabase/migrations/20260817000041_drop_legacy_complete_online_payment.sql
```

Migration başında `commit_online_order` var mı diye kontrol eder; yoksa
hata verip durur.

> ⚠️ Bu adımı Adım 3'ten önce çalıştırırsanız, yeni callback deploy edilene
> kadar alınan ödemeler için **sipariş oluşmaz** (para çekilir, sipariş yok).

---

## Doğrulama

```bash
# pgTAP değişmezleri (yerel)
supabase test db supabase/tests/database

# Edge Function RPC sözleşmesi
bash scripts/check_edge_function_rpc_contract.sh
```

Canlıda hızlı kontrol:

```sql
-- Finalizer'lar yalnız service_role'e açık olmalı (üçü de false dönmeli)
select p.proname,
       has_function_privilege('authenticated', p.oid, 'EXECUTE') as authenticated_erisebilir
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname in ('atomic_finalize_payment_transaction',
                    'commit_online_order',
                    'link_checkout_session_payment',
                    'get_checkout_session_for_payment');

-- Istemci artık bu tablolara yazamamalı (hepsi false)
select tablename,
       has_table_privilege('authenticated', 'public.'||tablename, 'UPDATE') as yazabilir
from (values ('payment_transactions'),('seller_earnings'),('seller_withdrawals')) t(tablename);
```

---

## Kapsam dışı bırakılanlar

Bu set **backend'i onarır ve güvenli hâle getirir**; checkout ekranlarını
sunucu-otoriteli akışa bağlamaz. Yani:

- `lib/services/checkout_service.dart` hâlâ hiçbir ekran tarafından
  import edilmiyor (ölü kod).
- Canlı checkout ekranları (`lib/features/market/screens/checkout_screen.dart`,
  `lib/features/shop/screens/checkout_screen.dart`) fiyatı hâlâ Dart'ta
  hesaplayıp gönderiyor.
- `lib/core/services/payment_service.dart:110-114` — `isOrphanSuccess`
  hâlâ sabit `false`; `payment_status='success'` ama `order_id IS NULL`
  durumu kullanıcıya başarılı sipariş olarak gösteriliyor.
- Sepetteki sahte TCKN fallback'i (`'11111111111'`) canlı checkout
  ekranlarında duruyor.
- Çok mağazalı online ödeme hâlâ UI'da engelli.

Bunlar UI kesişi (Flow A cutover) işidir ve ayrı ele alınmalıdır.
