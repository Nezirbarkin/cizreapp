# Plan: Ödeme Yöntemleri Admin Aktif/Pasif Kontrolü

Tarih: 2026-07-05
Mod: Architect → Code

## 1) Mevcut Durum (Kod Analizi Sonucu)

### 1.1 Bakiye Yükleme (topup)
[`lib/features/wallet/screens/topup_screen.dart`](lib/features/wallet/screens/topup_screen.dart:30) ekranında:
- `_selectedMethod` = `'card'` | `'transfer'`
- `_cardTopupEnabled` ayarı [`app_about_settings.card_topup_enabled`](lib/features/wallet/screens/topup_screen.dart:47) kolonundan okunuyor
- Kart pasifse → kart seçeneği gizleniyor, uyarı gösteriliyor, `transfer`'e yönlendiriliyor
- **SONUÇ:** Bakiye yüklemesinde "kredi kartı/banka kartı" aktif/pasif kontrolü ZATEN MEVCUT. İstek-1 zaten karşılanıyor. Yine de admin paneli kontrol edildi, mevcut toggle korunduğu için dokunulmuyor (regresyon riski yok).

### 1.2 Sipariş Ödeme Yöntemleri (checkout)
[`lib/core/models/order_model.dart`](lib/core/models/order_model.dart:54) `PaymentMethod` enum:
- `cash` → Kapıda Nakit
- `cardOnDelivery` → Kapıda Kart (POS ile) — UI'da "Kapıda Banka/Kredi Kartı"
- `online` → Online Ödeme (iyzico)
- `balance` → Bakiye ile Ödeme

3 ayrı checkout ekranı, her biri benzer `RadioListTile<PaymentMethod>` yapısı:
- [`lib/features/market/screens/checkout_screen.dart`](lib/features/market/screens/checkout_screen.dart:44) (tek dükkan, market)
- [`lib/features/market/screens/multi_shop_checkout_screen.dart`](lib/features/market/screens/multi_shop_checkout_screen.dart:44) (çoklu dükkan)
- [`lib/features/shop/screens/checkout_screen.dart`](lib/features/shop/screens/checkout_screen.dart:54) (satıcı paneli)

Bu ekranlarda **sıfır** ödeme yöntemi filtresi yok; tüm yöntemler her zaman gösteriliyor. **İstek-2 karşılanmamış** — eklenecek.

### 1.3 Admin Paneli (wallet settings)
[`lib/features/admin/screens/admin_dashboard_screen.dart`](lib/features/admin/screens/admin_dashboard_screen.dart:16181) `_WalletSettingsTabWidgetState`:
- `card_topup_enabled`, `balance_enabled`, `min_topup_amount`, `max_topup_amount`, `withdrawal_fee_percent`, `min_withdrawal_amount` okunup kaydediliyor
- SELECT → `.maybeSingle()` (tek satır), UPDATE → `eq('id', existing['id'])`
- **İstek-1 ve İstek-2 için buraya yeni toggle'lar eklenecek.**

### 1.4 SQL Şeması
[`app_about_settings`](PROJE_HAVIZA_SCHEMA.md:75) kolonları (önceden ADD COLUMN IF NOT EXISTS ile idempotent eklenmiş):
- `online_payment_enabled` (online ödeme master — ZATEN VAR)
- `card_topup_enabled` (bakiye yüklemesinde kart — ZATEN VAR)
- `balance_enabled` (bakiye sistemi — ZATEN VAR)
- EKSİK: sipariş ödeme yöntemi toggle'ları (`order_cod_enabled`, `order_card_on_delivery_enabled`, `order_balance_enabled`)

`payment_method` enum (supabase_schema.sql:151 + 20260623000000_ADD_PAYMENT_METHOD_BALANCE.sql:21): `('cash', 'card_on_delivery', 'online', 'balance')`.

### 1.5 RLS / Güvenlik Notları (PROJE_HAVIZA_RLS.md)
- `app_about_settings` UPDATE sadece admin (mevcut policy). Yeni kolonlar aynı policy'den yararlanır — yeni policy GEREKMEZ.
- Topup/checkout ekranları sadece SELECT yapıyor (anon/authenticated genelde select izni var). Yeni kolonlar yalnızca SELECT edilecek.
- PostgREST şema reload: her migration sonrası `NOTIFY pgrst, 'reload schema'` çağrılır (20260703_ABOUT_SETTINGS_MISSING_COLUMNS.sql pattern'i).

## 2) Çözüm Planı

### 2.1 SQL Migration (Code modunda)
Yeni dosya: `20260705_PAYMENT_METHOD_TOGGLES.sql`
- `app_about_settings`'a 3 yeni kolon (idempotent `ADD COLUMN IF NOT EXISTS`, `NOT NULL DEFAULT TRUE`):
  - `order_cod_enabled` → Kapıda Nakit
  - `order_card_on_delivery_enabled` → Kapıda Kart
  - `order_balance_enabled` → Bakiye ile Ödeme
- `online` için **yeni kolon eklenmez**; mevcut `online_payment_enabled` kullanılır (tek gerçek kaynak prensibi, PROJE_HAVIZA'da öğrenilen tekrarlayan-kolon tuzağı).
- `NOTIFY pgrst, 'reload schema'`
- `UPDATE ... COALESCE(..., TRUE)` ile mevcut satırı garantiye al
- COMMENT ON COLUMN (dokümantasyon)
- BEGIN/COMMIT transaction
- PROJE_HAVIZA_SCHEMA.md §2.10'a yeni kolonlar eklenecek

### 2.2 Flutter — Checkout Ekranlarına Filtreleme (Code modunda)
3 checkout ekranına ortak bir yardımcı: `lib/core/services/payment_method_settings_service.dart` (yeni, küçük):
```dart
class PaymentMethodSettings {
  final bool codEnabled;            // cash
  final bool cardOnDeliveryEnabled; // cardOnDelivery
  final bool onlineEnabled;         // online (online_payment_enabled)
  final bool balanceEnabled;        // balance
  // static Future<PaymentMethodSettings> load() → tek sorgu
  // bool isAvailable(PaymentMethod m)
}
```
- Her checkout ekranında `initState`'te `PaymentMethodSettings.load()` çağrılır, state'e yazılır.
- `_selectedPaymentMethod`'ın default değeri pasifse ilk aktif yönteme kaydırılır (ör. `cash` pasifse `cardOnDelivery`).
- RadioListTile'lar `if (settings.isAvailable(PaymentMethod.x))` ile sarmalanır.
- Mevcut tüm mantık (online ödeme akışı, bakiye düşümü, onay kodu, commission) **dokunulmaz** — yalnızca görünürlük filtrelenir.
- Hata/Geri çekilme: ayar yüklenemezse tüm yöntemler görünür (varsayılan `true` → mevcut davranış).

### 2.3 Flutter — Admin Wallet Settings (Code modunda)
[`admin_dashboard_screen.dart`](lib/features/admin/screens/admin_dashboard_screen.dart:16181) `_WalletSettingsTabWidgetState`:
- SELECT listesine yeni kolonlar eklenir
- 3 yeni `SwitchListTile` (Kapıda Nakit / Kapıda Kart / Bakiye ile Ödeme) + mevcut "Online Ödeme" `online_payment_enabled` toggle'ı (bu zaten app_about_service tarafında var ama wallet sekmesinde görünmüyor; kullanıcı isteğiyle eklenir).
- `_saveSettings` UPDATE map'ine yeni kolonlar eklenir.
- Mevcut kayıt mantığı (`eq('id', existing['id'])`) korunur.

### 2.4 Dokümantasyon Güncellemeleri (Code modunda — .md)
- `PROJE_HAVIZA_SCHEMA.md` §2.10'a yeni kolonlar
- `PROJE_HAVIZA_CHANGELOG.md`'e kayıt (standart format)

## 3) Risk ve Regresyon Kontrolü

| Risk | Önlem |
|------|-------|
| Mevcut checkout mantığı bozulur | Yalnızca görünürlük filtrelenir, sipariş/ödeme akışı dokunulmaz |
| Online ödeme için iki kolon çakışır | `online_payment_enabled` tek kaynak, yeni kolon eklenmez |
| Eski client + yeni DB | Yeni kolon DEFAULT TRUE → eski davranış devam |
| Yeni client + eski DB (migration çalışmamış) | `.maybeSingle()` null/eksik kolon → `?? true` → tüm yöntemler görünür |
| RLS engeli | SELECT geniş, UPDATE admin-only; yeni kolonlar aynı policy |
| PostgREST 204 (eksik kolon) | `NOTIFY pgrst, 'reload schema'` |

## 4) Uygulama Sırası (Code modunda)

1. `20260705_PAYMENT_METHOD_TOGGLES.sql` (SQL migration)
2. `lib/core/services/payment_method_settings_service.dart` (yeni helper)
3. 3 checkout ekranı entegrasyonu (topup_screen.dart zaten hazır, kontrol edilecek)
4. admin_dashboard_screen.dart `_WalletSettingsTabWidgetState` güncellemesi
5. PROJE_HAVIZA_SCHEMA.md + PROJE_HAVIZA_CHANGELOG.md güncellemesi
6. `flutter analyze` ile hata kontrolü

## 5) Akış Diyagramı

```mermaid
flowchart TD
    A[Admin: Wallet Settings Sekmesi] --> B[Toggle: Kapida Nakit / Kapida Kart / Online / Bakiye]
    B --> C[app_about_settings UPDATE]
    C --> D[PostgREST reload schema]
    E[Musteri: Checkout Ekrani] --> F[PaymentMethodSettings.load - tek SELECT]
    F --> G{Yontem aktif mi?}
    G -->|Evet| H[RadioListTile goster]
    G -->|Hayir| I[RadioListTile gizle]
    H --> J[Siparis olustur - mevcut akis ayni]
    I --> J
    K[Topup Screen] --> L[card_topup_enabled - mevcut, degismedi]