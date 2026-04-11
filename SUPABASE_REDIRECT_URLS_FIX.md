# 🔴 Supabase Redirect URLs Sorunu - ÇÖZÜM

## Sorun
Linkiniz: `https://xsbukxkgtmdyickknqzf.supabase.co/auth/v1/verify?token=...&type=signup&redirect_to=cizreapp://verify`

`redirect_to=cizreapp://verify` OLACAK! → **Yanlış!** Gmail bunu engeller.

## ✅ Doğru Olması Gereken
`redirect_to=https://www.cizreapp.com/verify` → **Doğru!** HTTPS çalışır.

---

## 🔧 HEMEN YAPIN

### Adım 1: Supabase Redirect URLs Güncelle

1. https://supabase.com/dashboard'a gidin
2. Projenizi seçin
3. **Authentication** > **URL Configuration** sekmesine tıklayın
4. **Redirect URLs** bölümüne ekleyin:

```
https://www.cizreapp.com/verify
https://cizreapp.com/verify
https://www.cizreapp.com/recovery
https://cizreapp.com/recovery
https://www.cizreapp.com/auth/callback
https://cizreapp.com/auth/callback
```

5. **Save** butonuna tıklayın!

### Adım 2: Eski redirect URL'lerini kaldırın (VARSAlarsa)

Eğer `cizreapp://verify` gibi custom scheme URL'ler varsa, SİLİN.
Sadece HTTPS URL'leri kalsın.

### Adım 3: Uygulamayı tekrar derleyin

```bash
flutter clean
flutter pub get
flutter build apk
```

### Adım 4: Yeni kayıt oluşturup test edin

1. Uygulamayı silin ve yeniden yükleyin
2. Yeni bir e-posta ile kayıt olun
3. Gelen e-postadaki linkte `redirect_to=https://www.cizreapp.com/verify` görmeniz gerekiyor
4. Linke tıklayın → web sayfası açılacak → uygulama açılacak

---

## ❓ Neden Böyle Oluyor?

Supabase, `emailRedirectTo` parametresini kullanır ama EĞER redirect URL whitelist'te (Redirect URLs) yoksa, Supabase bunu görmezden gelir ve varsayılan değeri kullanır.

Siz kodda `emailRedirectTo: 'https://www.cizreapp.com/verify'` yazsanız bile, Supabase Dashboard'da bu URL ekli değilse çalışmaz!

---

## 🧿 Supabase Redirect URLs Kontrol Listesi

- [ ] `https://www.cizreapp.com/verify` → EKLE
- [ ] `https://www.cizreapp.com/recovery` → EKLE
- [ ] `https://www.cizreapp.com/auth/callback` → EKLE
- [ ] `cizreapp://verify` → SİL (Gmail engeller)
- [ ] `cizreapp://recovery` → SİL (Gmail engeller)
