# Edge Functions: AdMob SSV ve karma dijital ödeme

## Deploy edilecek fonksiyonlar

- `admob-reward-session` (JWT zorunlu)
- `admob-ssv-callback` (yalnız bu callback için gateway JWT kapalı; Google ECDSA SSV zorunlu)
- `grant-ad-reward` (legacy, her zaman HTTP 410 ve kredi yok)
- `smm-order-create`, `smm-order-manual-status`, `smm-order-status-check`

## Deploy sirasi ve JWT matrisi

On kosul: additive [`20260730000002_admob_reward_points_system.sql`](../migrations/20260730000002_admob_reward_points_system.sql:1) hedef ortama uygulanmis, [`002_reward_points_security_invariants.test.sql`](../tests/database/002_reward_points_security_invariants.test.sql:1) local temiz DB'de gecmis ve asagidaki custom secret/allowlist sozlesmesi ilk durumda `ADMOB_SSV_MODE=disabled` olacak sekilde tamamlanmis olmalidir. Uzak uygulanma durumu `supabase migration list` ile dogrulanir; dokuman sayimindan varsayilmaz.

```powershell
supabase functions deploy admob-reward-session
supabase functions deploy admob-ssv-callback --no-verify-jwt
supabase functions deploy grant-ad-reward
supabase functions deploy smm-order-create
supabase functions deploy smm-order-manual-status
supabase functions deploy smm-order-status-check
```

| Function | Gateway JWT | Uygulama ici dogrulama |
|---|---|---|
| `admob-reward-session` | Acik | Kullanici JWT'si ve JWT'den turetilen user id |
| `admob-ssv-callback` | **Kapali; tek AdMob istisnasi** | Google ECDSA P-256/SHA-256, network, ad-unit allowlist, timestamp, key-id ve custom-data HMAC |
| `grant-ad-reward` | Varsayilan/acik kalabilir | Her durumda HTTP 410; ekonomik kredi yok |
| `smm-order-create` | Acik | Kullanici JWT'si; fiyat/composition server-side |
| `smm-order-manual-status` | Acik | Kullanici JWT'si + admin/provider sahibi kontrolu |
| `smm-order-status-check` | Acik | Kullanici JWT'si veya cron icin gecerli Supabase bearer; function ayrica `CRON_SECRET` kontrol eder |

Kanonik proje ayari [`config.toml`](../config.toml:13)'dir: yalniz `admob-ssv-callback.verify_jwt=false`, [`admob-reward-session`](../config.toml:16) icin `verify_jwt=true`. AdMob kapsaminda diger endpoint'lere `--no-verify-jwt` eklenmez.

## Secret/environment sözleşmesi

Gerçek değerler repoya yazılmaz. Supabase Edge runtime sistem değişkenleri ile custom secret'lar ayrıdır:

| Ad | Kullanım |
|---|---|
| `SUPABASE_URL` | Supabase Edge runtime tarafından sağlanan proje URL'si |
| `SUPABASE_SERVICE_ROLE_KEY` | Supabase Edge runtime tarafından sağlanır; istemciye verilmez veya custom secret olarak kopyalanmaz |
| `ADMOB_SSV_MODE` | `disabled`, `test` veya `production`; `test` ekonomik kredi yazmaz |
| `ADMOB_SSV_HASH_SECRET` | En az 32 karakter rastgele HMAC sırrı; nonce/provider pseudonym hash ve custom-data MAC |
| `ADMOB_SSV_PUBLIC_KEY_URL` | Resmi HTTPS key endpoint, varsayılan verilmez: `https://www.gstatic.com/admob/reward/verifier-keys.json` açıkça set edilmelidir |
| `ADMOB_SSV_KEY_CACHE_TTL_SECONDS` | Pozitif TTL; örnek `21600` |
| `ADMOB_SSV_MAX_AGE_SECONDS` | Replay penceresi; örnek `86400` |
| `ADMOB_SSV_FUTURE_SKEW_SECONDS` | Gelecek saat toleransı; örnek `300` |
| `ADMOB_SSV_PRODUCTION_AD_UNITS` | Virgülle ayrılmış gerçek production rewarded ad-unit allowlist |
| `ADMOB_SSV_TEST_AD_UNITS` | Virgülle ayrılmış test/staging ad-unit allowlist |
| `CRON_SECRET` | `smm-order-status-check` cron kimlik doğrulaması; uzun rastgele değer |

Production modunda eksik/boş allowlist, key/network/parse/config/signature/timestamp/custom-data hataları fail-closed'dur ve kredi oluşturmaz. Callback raw query veya imza, JWT, API key, raw custom data ve provider user kimliğini loglamaz. Anahtarlar TTL ile process belleğinde cache edilir; bilinmeyen key-id ve başarısız imzada rotation için bir kez zorunlu refetch yapılır.

`ADMOB_SSV_*` ve `CRON_SECRET` custom secret'lari guvenli CI/Supabase secret yonetimiyle function deploy'undan once set edilir; yalniz custom adlar `supabase secrets list` ile dogrulanir. Degerler komut gecmisinde, dokumanda veya function logunda tutulmaz.

## RPC sözleşmeleri

- `create_ad_reward_session(uuid,text,text,text,text) -> jsonb`: JWT user id yalnız backend'den `p_user_id`; DB'ye HMAC nonce hash gönderilir.
- `grant_verified_ad_points(uuid,text,text,text,text,timestamptz,text,text) -> jsonb`: yalnız doğrulanmış production SSV ve service role; custom-data nonce HMAC'i session kaydıyla eşleşmelidir; provider transaction id'nin raw değeri yerine deterministik HMAC hem tekillik hem hash alanına verilir; duplicate sonucu başarılı/idempotent döner.
- `create_digital_order_with_points(uuid,uuid,text,integer,text,boolean) -> jsonb`: fiyat ve composition ürün/ayar/account verisinden server-side hesaplanır; önce puan sonra TL rezerve edilir.
- `refund_digital_order_payment(uuid,numeric,text,text,boolean) -> jsonb`: kümülatif gross hedef üzerinden puanı puana, TL'yi TL bakiyeye idempotent iade eder.
- `set_digital_order_reconciliation(uuid,text) -> void`: yalnız `pending_provider`, `reconciliation_pending`, `settled`; timeout/network/parse/belirsiz provider sonucunda iade yerine `reconciliation_pending` kullanılır.

## Test

Windows PowerShell:

```powershell
Push-Location .\supabase\functions
deno task test:reward
Pop-Location
```

DB katalog/RLS paketi proje kokunden:

```powershell
supabase start
supabase db reset
supabase test db
```

## Cutover ve kill-switch ozeti

1. Migration ve function deploy'u DB'de earn/spend kapaliyken tamamlanir.
2. Kontrollu testte DB mode=`observe`, earn/spend=false ve `ADMOB_SSV_MODE=test` kullanilir. Observe session olusturmaya izin verir; callback test modu tam imza protokolunu dogrular, grant RPC'sini cagirmadan 204 doner ve kredi yazmaz. Testten sonra mode tekrar `disabled` yapilir.
3. Production allowlist/key/retention ayarlari hazir olduktan sonra `ADMOB_SSV_MODE=production` yapilir.
4. Audit gerekceli admin config RPC'siyle once SSV+earn, daha sonra yalniz uygun dijital urunler ve spend acilir. `cohort` modu tek basina DB cohort uyeligi uygulamaz.
5. Acil durumda DB'de mode disabled + earn/spend/eligible-products false yapilir ve callback icin `ADMOB_SSV_MODE=disabled` kullanilir.
6. Legacy TL grant yeniden acilmaz. Append-only ledger silinmez; destructive rollback yerine ileri migration kullanilir.
7. Cutover oncesi TL reklam degeri grandfathered kalir; puan backfill'i yoktur.
8. Belirsiz SMM provider sonucu otomatik iade edilmez; `reconciliation_pending` mutabakatla kesinlestirilir. Kesin iadede puan puana, TL TL'ye doner.

`smm-order-status-check` gateway JWT'si acik kaldigi icin cron istegi gecerli Supabase bearer **ve** `CRON_SECRET` tasir. Yalniz cron header'i gateway'i gecmez; bu endpoint'e `--no-verify-jwt` verilmesi bu runbook'un kapsami disinda ayri bir guvenlik karari gerektirir.

Tam release/rollback kontrol listesi [`supabase/README.md`](../README.md:94)'dedir.
