# ÖDEME VE SİPARİŞ SİSTEMİ ANALİZİ

## Mevcut Sistem Durumu

### Kuryesi OLAN Satıcılar

**1. Kapıda Ödeme (cash, card_on_delivery):**
- Satıcı parayı müşteriden alır
- Komisyon borç olarak kaydedilir
- `seller_debt_amount = admin_commission`
- `commission_status = 'debt'`

**2. Online Ödeme:**
- Admin parayı alır, satıcıya alacak
- `seller_credit_amount = total - admin_commission`
- `commission_status = 'credit'`

**3. Ödeme İsteği Hesaplama:**
```
Ödeme İsteği = admin_credit - commission_debt
```

### Kuryesi OLMAYAN Satıcılar

**Her Durumda:**
- Admin tüm parayı alır (sipariş + teslimat ücreti)
- Komisyon + Teslimat ücreti kesilir
- `seller_credit_amount = subtotal - admin_commission`
- Ödeme isteği = `admin_credit`

## Kurye Durumu Değişikliği

Şu anda kurye durumu değiştiğinde otomatik bakiye düzeltme YOK.

### Beklenen Davranış:
Kuryeli → Kuryesiz geçişte, birikmiş borç alacaktan düşülmeli.

### Mevcut Davranış:
- Eski siparişler (değişiklik öncesi): Eski değerleri korur
- Yeni siparişler: Yeni mantıkla hesaplanır
- Borç/alacak manuel düzeltme gerekebilir

## Ödeme İsteği Mantığı

```
IF has_own_courier = FALSE THEN
    Ödeme = admin_credit
ELSE
    Ödeme = admin_credit - commission_debt
    (Eğer sonuç <= 0 ise hata verir)
```

## Sorunlar ve Çözümler

### Sorun 1: Kurye değişikliğinde bakiye düzeltme yok
**Çözüm:** `courier_status_change` trigger eklenebilir

### Sorun 2: Kuryesi olan satıcı kuryesize geçişte
- Eğer komisyon borcu varsa ve online ödeme alacağı varsa:
  - Borç alacaktan düşülmeli

## Kontrol Sorguları

```sql
-- Tüm satıcıların durumu
SELECT 
    id,
    name,
    has_own_courier,
    commission_debt,
    admin_credit,
    (admin_credit - commission_debt) as net_receivable
FROM shops
ORDER BY created_at DESC;

-- Kuryesi olan satıcıların detayı
SELECT 
    s.name,
    s.has_own_courier,
    o.payment_method,
    o.subtotal,
    o.total,
    o.admin_commission,
    o.seller_debt_amount,
    o.seller_credit_amount,
    o.commission_status
FROM orders o
JOIN shops s ON s.id = o.shop_id
WHERE s.has_own_courier = TRUE
ORDER BY o.created_at DESC
LIMIT 20;

-- Trigger kontrolü
SELECT 
    tgname,
    tgenabled
FROM pg_trigger
WHERE tgrelid IN (
    SELECT oid FROM pg_class WHERE relname IN ('orders', 'payout_requests', 'shops')
)
ORDER BY tgrelid, tgname;
```

## Sonuç

Mevcut sistem temel mantık olarak doğru çalışıyor:
- ✅ Kuryesi olan: Kapıda ödeme → Borç, Online → Alacak
- ✅ Kuryesi olmayan: Her zaman alacak (teslimat ücreti kesilir)
- ✅ Ödeme isteği: Alacak - Borç
- ⚠️ Kurye değişikliğinde manuel düzeltme gerekebilir
