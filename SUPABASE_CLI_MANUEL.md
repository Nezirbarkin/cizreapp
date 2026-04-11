# Supabase CLI Manuel Kurulum (Scoop Çalışmazsa)

Scoop çalışmıyor, o yüzden **manuel indirme** yapalım!

---

## 🔽 Adım 1: Supabase CLI İndir

1. Bu linke git: **https://github.com/supabase/cli/releases**

2. En son version'u bul (örn: v1.x.x)

3. **Assets** bölümünden şu dosyayı indir:
   - **supabase_windows_amd64.zip** (veya supabase_1.x.x_windows_amd64.zip)

4. İndirdiğin ZIP dosyasını aç

5. İçinden `supabase.exe` dosyasını çıkar

---

## 📂 Adım 2: PATH'e Ekle

### Yöntem 1: Basit (Proje klasörüne koy)

1. `supabase.exe` dosyasını `C:\Users\lenovo\cizreapp\` klasörüne kopyala
2. CMD'de:
   ```bash
   cd C:\Users\lenovo\cizreapp
   supabase --version
   ```

### Yöntem 2: Kalıcı (PATH'e ekle)

1. `supabase.exe` dosyasını `C:\supabase\` klasörüne taşı

2. Windows Başlat → "Sistem ortam değişkenleri" ara → Aç

3. **Ortam Değişkenleri** butonuna tıkla

4. **Kullanıcı değişkenleri** bölümünde **Path** seç → **Düzenle**

5. **Yeni** → `C:\supabase` ekle → **Tamam**

6. **CMD'yi kapat ve yeniden aç**

7. Test et:
   ```bash
   supabase --version
   ```

---

## ✅ Adım 3: Kurulum Tamamlandı!

Artık şu komutları çalıştırabilirsin:

```bash
cd C:\Users\lenovo\cizreapp
supabase login
supabase link --project-ref xsbukxkgtmdyickknqzf
supabase secrets set FIREBASE_SERVICE_ACCOUNT_JSON="{JSON}"
supabase functions deploy send-push-notification
```

---

## 🎯 Alternatif: NPM ile Kur

Eğer Node.js yüklüyse:

```bash
npm install -g supabase
```

Sonra:

```bash
supabase --version
```

---

## 📞 Sorun Yaşarsan

1. `supabase.exe` dosyasını **doğrudan proje klasörüne** (`C:\Users\lenovo\cizreapp`) kopyala
2. CMD'de:
   ```bash
   cd C:\Users\lenovo\cizreapp
   .\supabase.exe --version
   ```
3. Bu çalışırsa, komutları `supabase` yerine `.\supabase.exe` ile çalıştır

---

İndirme linki: **https://github.com/supabase/cli/releases**
