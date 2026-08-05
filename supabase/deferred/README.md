# Ertelenmis Migration'lar

**Olusturma:** 2026-08-05

Bu dizindeki dosyalar **gecerli ve gelecekte uygulanacak** migration'lardir.
Arsiv **degildir** — [`../archive/`](../archive/) "bir daha asla calistirilmayacak"
demektir, burasi "henuz calistirilamaz" demektir.

`supabase/migrations/` disinda tutulmalarinin tek sebebi: `supabase db push`
komutunun bunlari **yanlislikla** uygulamasini engellemek. Su anki canli
durumda calistirilirlarsa uygulamayi aninda kirarlar.

---

## Neden ertelendiler?

2026-08-02 "server-authoritative checkout" refaktoru **yarim** durumda:

| Katman | Durum |
|---|---|
| `private.*` implementasyonlari | Canliya elle uygulanmis, calisiyor |
| `public.*` uyumluluk wrapper'lari | Canlida elle olusturulmus, calisiyor |
| Flutter yeni katmani (`lib/services/`, `lib/screens/`) | Yazilmis ama **hicbir ekrandan cagrilmiyor** |
| Flutter canli akisi (`lib/features/**`) | Hala eski client-otoriteli yolu kullaniyor |

Yani uygulama su an **eski yuzeye** bagimli. Bu iki migration ise tam olarak
o eski yuzeyi yok ediyor.

---

## Dosyalar

### `20260802000008_revoke_legacy_writes.sql`

Tamamen yikici — hicbir sey olusturmaz, yalniz siler ve yetki geri alir.

| Ne yapiyor | Kirdigi canli cagri |
|---|---|
| `DROP public.use_coupon` | `market/checkout_screen.dart:744,1030` · `shop/checkout_screen.dart:408` |
| `DROP public.validate_coupon` | `shop/cart_screen.dart:209` · `market/providers/cart_provider.dart:168` |
| `DROP public.claim_flash_sale` / `release_flash_sale` | `market/services/flash_sale_service.dart:76,94` |
| `REVOKE INSERT ON orders FROM authenticated` | `shop/services/order_service.dart:88,725` — siparis olusturma tamamen durur |
| `REVOKE INSERT ON order_items` | `shop/services/order_service.dart:149,780` |
| `REVOKE UPDATE ON payment_transactions` | `core/services/payment_service.dart:148` |

Ayrica sildigi `public.use_coupon` / `public.validate_coupon`, canlida
uygulamayi ayakta tutan **uyumluluk wrapper'larinin ta kendisidir**.

### `20260802000013_coupon_limit_enforcement_strict.sql`

`private` bolumu canliya **zaten uygulanmis** (`private.use_coupon` ve
`private.validate_coupon` canlida mevcut). Geriye kalan etkisi yikici:

```sql
DROP FUNCTION IF EXISTS public.validate_coupon(UUID, TEXT, NUMERIC, UUID);
DROP FUNCTION IF EXISTS public.use_coupon(UUID, UUID, UUID, NUMERIC);
```

Bu iki imza, canlidaki public wrapper'larin imzalariyla **birebir aynidir**.
Yeniden calistirilirsa wrapper'lar silinir, yerine bir sey konmaz.

---

## Ne zaman uygulanabilir?

Asagidakilerin **hepsi** dogru olduktan sonra:

1. Flutter ekranlari `lib/services/checkout_service.dart` uzerinden
   `prepare_checkout_session` + `commit_cod_order` / `commit_balance_order`
   akisina gecmis olmali. (Bugun `lib/services/` ve `lib/screens/` altindaki
   yeni katmani import eden **tek bir satir yok**.)
2. `lib/features/shop/services/order_service.dart` icindeki dogrudan
   `orders` / `order_items` INSERT'leri kaldirilmis olmali.
3. `lib/features/market/services/flash_sale_service.dart` icindeki
   `claim_flash_sale` / `release_flash_sale` cagrilari kaldirilmis olmali.
4. `iyzico-payment-callback` Edge Function'i calisir hale getirilmis olmali
   (bkz. asagidaki not).
5. Yeni surum kullanicilarin cogunlugunda yayinda olmali — eski surumdeki
   kullanicilar bu migration sonrasi siparis veremez.

**Uygulama sekli:** bu dosyalari `migrations/` altina geri tasima. Bunun
yerine o gunun tarihiyle **yeni** bir migration olustur ve iceriklerini
oraya kopyala. Boylece kronoloji ve `schema_migrations` tutarli kalir.

---

## Ilgili acik konu: `iyzico-payment-callback`

Bu dizinle dogrudan ilgili degil ama ayni refaktorun parcasi ve ayni sekilde
yarim kalmis. [`../functions/iyzico-payment-callback/index.ts`](../functions/iyzico-payment-callback/index.ts)
su cagrilari yapiyor:

```ts
supabase.rpc("private.atomic_finalize_payment_transaction", { ... })  // 3 yer
supabase.rpc("private.commit_online_order", { ... })                  // 1 yer
```

Uc ayri sorun var:

1. **Yanlis API kullanimi.** supabase-js `.rpc()` cikplak fonksiyon adi bekler;
   sema `.schema('private').rpc('...')` ile verilir. `"private.foo"` seklinde
   gecmek PostgREST'te `public."private.foo"` aranmasina ve PGRST202'ye yol acar.
2. **Sema expose degil.** Dogru sozdizimi kullanilsa bile `private`, PostgREST'in
   expose ettigi semalar arasinda degil (canlida `pgrst.db_schemas` ayari yok,
   varsayilan `public, graphql_public`). `.schema('private')` PGRST106 doner.
3. **Hedef fonksiyonlar canlida yok.** `private.commit_online_order` ve
   `private.atomic_finalize_payment_transaction` yalniz
   [`../migrations/20260802000009_lock_payment_finalizer_to_backend.sql`](../migrations/20260802000009_lock_payment_finalizer_to_backend.sql)
   ile olusuyor; o migration canliya uygulanmamis.

Bu Edge Function'in bu hali deploy edilirse **online (iyzico) odeme tamamen
durur**. Deploy edilmeden once ya `public` wrapper'lara cevrilmeli ya da
20260802000009 uygulanip cagrilar `.schema('private')` ile duzeltilmeli.
