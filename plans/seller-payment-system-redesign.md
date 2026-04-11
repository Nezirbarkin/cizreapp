# Satıcı Ödeme Sistemi Yeniden Tasarım Planı

## 🔍 Mevcut Sistem Analizi

### SQL Trigger Mantığı (Şu an çalışan)

**Kuryesi OLAN Satıcı:**
| Ödeme Yöntemi | Komisyon | Teslimat | Net | Durum |
|---------------|----------|----------|-----|------|
| Kapıda (cash/card) | Borç olarak kaydedilir | Satıcı alır | total - komisyon | `debt` |
| Online | Satıcıya alacak | Admin alır | total - komisyon | `credit` |

**Kuryesi OLMAYAN Satıcı:**
| Ödeme Yöntemi | Komisyon | Teslimat | Net | Durum |
|---------------|----------|----------|-----|------|
| Her durum | Komisyon düşülür | Admin alır | subtotal - komisyon | `credit` |

### Şu anki Sorunlar
1. `commission_debt` ve `admin_credit` karmaşık takılıyor
2. Kuryesi olmayan satıcı için teslimat ücreti yanlış hesaplanıyor
3. Dashboard kartları karışık gösteriyor
4. Ödeme isteği mantığı anlaşılmıyor

---

## ✅ İstenen Yeni Mantık

### 1. Kuryesi OLAN Satıcı

**Kapıda Ödeme:**
- Satıcı parayı direkt müşteriden alır
- Komisyon borç olarak kaydedilir (daha sonra ödemeden düşülür)

**Online Ödeme:**
- Para admin'e gider
- Satıcıya alacak olarak kaydedilir

**Ödeme İsteği Hesaplama:**
```
Ödenebilir Tutar = Admin'den Alacak - Komisyon Borcu
Eğer Ödenebilir Tutar > 0 → Ödeme isteği oluşturulabilir
```

### 2. Kuryesi OLMAYAN Satıcı

**Her Ödeme Yönteminde:**
- Teslimat ücreti admin'den düşülür (platform kargosu kullandığı için)
- Komisyon düşülür
- Net alacak hesaplanır

**Ödeme İsteği Hesaplama:**
```
Toplam Alacak = (Kapıda ödeme kazancı + Online ödeme kazancı)
Toplam Kesinti = (Teslimat ücreti + Komisyon)
Ödenebilir Tutar = Toplam Alacak - Toplam Kesinti
```

---

## 📋 Değiştirilecek Dosyalar

### 1. SQL Trigger (`supabase/migrations/`)
- `calculate_order_commission()` - Sipariş komisyon hesaplama
- `update_shop_balance()` - Shop bakiye güncelleme
- `validate_payout_request()` - Ödeme isteği validasyonu

### 2. Flutter Dosyaları (`lib/features/seller/`)
- `services/payout_service.dart` - Ödeme hesaplama servisleri
- `widgets/balance_status_card.dart` - Bakiye gösterim kartı
- `screens/seller_dashboard_screen.dart` - Dashboard kartları

---

## 🗂️ Yeni Veri Yapısı

### `shops` Tablosu
| Kolon | Kullanım | Açıklama |
|-------|----------|----------|
| `admin_credit` | Kullanımda | Admin'den alacak (online ödemeler) |
| `commission_debt` | Kullanımda | Komisyon borcu (kapıda ödemeler) |
| `delivery_fee_credit` | EKLENECEK | Teslimat alacağı (kuryesi olmayan) |
| `total_collected_cash` | EKLENECEK | Toplam kapıda tahsilat |

### `orders` Tablosu
| Kolon | Kullanım | Açıklama |
|-------|----------|----------|
| `admin_commission` | Kullanımda | Komisyon tutarı |
| `admin_delivery_fee` | Kullanımda | Admin'in aldığı teslimat ücreti |
| `seller_net_amount` | Kullanımda | Satıcı net ödeme |
| `seller_cash_collected` | EKLENECEK | Kapıda tahsil edilen tutar |

---

## 🔄 Yeni Komisyon Mantığı

### calculate_order_commission() - YENİ

```sql
-- Kuryesi OLAN satıcı, KAPIDA ödeme
IF has_own_courier AND payment_method IN ('cash', 'card_on_delivery') THEN
    seller_cash_collected := total;  -- Satıcı parayı alır
    admin_commission := total * commission_rate;  -- Komisyon borç
    seller_net_amount := total - admin_commission;
    commission_status := 'cash_collected';  -- Yeni statü
    
-- Kuryesi OLAN satıcı, ONLINE ödeme  
ELSEIF has_own_courier AND payment_method = 'online' THEN
    seller_cash_collected := 0;
    admin_commission := total * commission_rate;
    seller_net_amount := total - admin_commission;  -- Admin'den alacak
    commission_status := 'admin_collects';
    
-- Kuryesi OLMAYAN satıcı (her durum)
ELSE
    seller_cash_collected := 0;  -- Kapıda olsa bile admin teslim ediyor
    admin_commission := total * commission_rate;
    admin_delivery_fee := delivery_fee;  -- Admin teslimat ücretini alır
    seller_net_amount := total - admin_commission;  -- Net alacak
    commission_status := 'admin_collects';
END IF;
```

### update_shop_balance() - YENİ

```sql
-- Shop bakiyesini güncelle
IF commission_status = 'cash_collected' THEN
    -- Kapıda tahsilat: Komisyon borcu artar, alacak artmaz
    UPDATE shops SET 
        commission_debt = commission_debt + admin_commission,
        total_collected_cash = total_collected_cash + seller_cash_collected
    WHERE id = NEW.shop_id;
ELSE
    -- Online/Admin collects: Alacak artar
    UPDATE shops SET 
        admin_credit = admin_credit + seller_net_amount
    WHERE id = NEW.shop_id;
END IF;
```

---

## 💰 Ödeme İsteği Mantığı

### createPayoutRequest() - YENİ

```dart
// Kuryesi OLAN satıcı
if (hasOwnCourier) {
  payableAmount = adminCredit - commissionDebt;
} 
// Kuryesi OLMAYAN satıcı  
else {
  // Kuryesi olmayan zaten alacak olarak çalışıyor
  // Ekstra bir hesaplama gerekmez
  payableAmount = adminCredit;
}
```

---

## 🎯 Dashboard Kartları (Yeni Tasarım)

### 1. Toplam Kazanç Kartı
```
Kapıda Ödeme Kazancı: ₺XXX
Online Ödeme Kazancı: ₺XXX
Teslimat Ücreti: -₺XXX (sadece kuryesi olmayan)
Komisyon Kesintisi: -₺XXX
─────────────────────────────
NET ÖDENECEK TUTAR: ₺XXX
```

### 2. Bakiye Durumu Kartı
```
Admin'den Alacak: ₺XXX
Komisyon Borcu: -₺XXX (sadece kuryesi olan)
─────────────────────────────
NET BAKİYE: ₺XXX
```

---

## 📊 Dashboard'da Gösterilecek Yeni Kartlar

1. **Gelir Dağılımı Kartı** - Kapıda vs Online ödeme kazancı
2. **Kesinti Detayı Kartı** - Komisyon + Teslimat ücreti ayrı ayrı
3. **Net Ödenecek Tutar Kartı** - Ödeme isteği için kullanılabilir tutar

---

## ⚠️ Dikkat Edilmesi Gerekenler

1. **Mevut siparişler bozulmamalı** - Backward compatible olmalı
2. **Trigger'lar atomik olmalı** - Ya hep ya da hiç
3. **Dashboard gerçek zamanlı olmalı** - SQL'den hesap gelmeli
4. **Ödeme isteği validasyonu doğru olmalı**

---

## 🚀 Uygulama Adımları

1. ✅ Analiz tamamlandı
2. ⏳ SQL trigger'ları yeniden yaz
3. ⏳ Flutter servislerini güncelle
4. ⏳ Dashboard widget'larını güncelle
5. ⏳ Test ve doğrula
