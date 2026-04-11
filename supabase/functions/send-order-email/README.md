# Sipariş E-posta Bildirimi Kurulum Rehberi

Bu rehber, yeni sipariş geldiğinde admin ve satıcıya otomatik e-posta bildirimi gönderme özelliğini aktif etmek için gerekli adımları açıklar.

## Gereksinimler

1. **Supabase CLI** (Edge Function deploy etmek için)
2. **Resend Hesabı** (E-posta servisi) - https://resend.com

## Adım 1: Resend Hesabı Oluşturun

1. https://resend.com adresine gidin
2. Ücretsiz hesap oluşturun (3000 email/ay ücretsiz)
3. API Key oluşturun
4. Domain doğrulaması yapın (opsiyonel, ama önerilir)

## Adım 2: Supabase Edge Function'ı Deploy Edin

### Lokal'den Deploy:
```bash
# Supabase CLI'ı yükleyin (eğer yüklü değilse)
npm install -g supabase

# Supabase projenize login olun
supabase login

# Projeyi link edin
supabase link --project-ref <your-project-ref>

# Environment variables set edin
supabase secrets set RESEND_API_KEY=re_xxxxxx

# Edge Function'ı deploy edin
supabase functions deploy send-order-email
```

### Supabase Dashboard'dan:
1. Supabase Dashboard'a gidin
2. Edge Functions bölümüne gidin
3. "send-order-email" function'ı oluşturun
4. `supabase/functions/send-order-email/index.ts` içeriğini kopyalayın
5. Settings > Secrets bölümüne gidin ve `RESEND_API_KEY` ekleyin

## Adım 3: Database Trigger'ı Oluşturun

Supabase SQL Editor'da aşağıdaki SQL'i çalıştırın:

```sql
-- pg_net extension'ı aktif edin (eğer değilse)
CREATE EXTENSION IF NOT EXISTS pg_net;

-- Supabase URL ve Key ayarlayın
ALTER DATABASE postgres SET "app.supabase_url" = 'https://<your-project-ref>.supabase.co';
ALTER DATABASE postgres SET "app.supabase_anon_key" = '<your-anon-key>';

-- Migration dosyasını çalıştırın
-- supabase/migrations/20260204000000_order_email_notification_trigger.sql içeriği
```

Veya migration dosyasını otomatik çalıştırmak için:
```bash
supabase db push
```

## Adım 4: Test Edin

1. Uygulamadan yeni bir sipariş oluşturun
2. Supabase Dashboard > Edge Functions > send-order-email loglarını kontrol edin
3. Admin ve satıcı e-postalarını kontrol edin

## Sorun Giderme

### E-postalar Gitmiyor
1. Resend API Key'in doğru olduğundan emin olun
2. Edge Function loglarını kontrol edin
3. pg_net extension'ın aktif olduğundan emin olun

### Trigger Çalışmıyor
1. Database Settings'te app.supabase_url ayarlandığından emin olun
2. Trigger'ın enabled olduğunu kontrol edin:
   ```sql
   SELECT * FROM pg_trigger WHERE tgname = 'on_order_created_send_email';
   ```

### Domain Doğrulama (Önerilen)
Resend'de kendi domain'inizi doğrularsanız:
- `from` adresini `noreply@yourdomain.com` olarak güncelleyin
- Edge Function'daki `from` alanını değiştirin

## E-posta Şablonu Özelleştirme

E-posta tasarımını değiştirmek için:
1. `supabase/functions/send-order-email/index.ts` dosyasını açın
2. `createOrderEmailHtml` fonksiyonunu düzenleyin
3. Function'ı tekrar deploy edin

## Alternatif: Flutter'dan Direkt Çağırma

Database trigger yerine Flutter'dan direkt çağırmak isterseniz, OrderService'e şu kodu ekleyin:

```dart
// Sipariş oluşturulduktan sonra
await Supabase.instance.client.functions.invoke(
  'send-order-email',
  body: {
    'order_id': order.id,
    'shop_id': order.shopId,
    'total': order.totalAmount,
    'order_number': order.orderNumber,
    'customer_name': customerName,
    'delivery_address': deliveryAddress,
  },
);
```

## Maliyetler

- **Resend Free Tier**: 3000 email/ay ücretsiz
- **Supabase Edge Functions**: 500K invocation/ay ücretsiz
- **pg_net**: Supabase'de ücretsiz

## Güvenlik Notları

1. `RESEND_API_KEY` secret olarak saklanmalıdır
2. Edge Function `SECURITY DEFINER` ile çalışır
3. Trigger sadece INSERT'te çalışır (UPDATE'te çalışmaz)
