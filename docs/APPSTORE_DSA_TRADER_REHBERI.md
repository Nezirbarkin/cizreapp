# App Store DSA (Dijital Hizmetler Yasası) Trader Uyumluluğu - CizreApp

## Bu Rehber Neden Gerekli?

Apple, App Store Connect'te **"Manage compliance information / Manage European Union Digital Services Act trader requirements"** başlıklı bir bildirim gösteriyorsa, bu rehber sizin içindir.

DSA'nın 30. ve 31. maddeleri, AB'de uygulama dağıtan tüm trader (tacir)ların **iletişim bilgilerinin** (adres, telefon, e-posta) App Store ürün sayfasında yayınlanmasını zorunlu kılar.

> ⚠️ **Önemli:** Bu rehber bilgilendirme amaçlıdır, hukuk tavsiyesi değildir. Karar vermeden önce bir hukuk danışmanına başvurmanız önerilir (Apple da bunu açıkça belirtir).

---

## CizreApp İçin Alınan Karar (güncel)

**CizreApp, Cizre/Şırnak'a özel lokal bir uygulamadır. AB pazarına hizmet verilmemektedir.**

Bu nedenle **en temiz çözüm: AB'nin 27 ülkesini App Store'da "Not Available" (kullanılamaz) olarak kapatmak** ve DSA trader bildirimini bu şekilde çözmektir.

Bu yol seçildiğinde:
- AB'de uygulama dağıtılmadığı için DSA trader bilgisi **girmek zorunda değilsiniz**
- Adres/telefon/e-posta bilgilerinizi Apple'a vermek zorunda kalmazsınız
- Apple'ın doğrulama süreciyle uğraşmazsınız
- AB kullanıcıları uygulamayı göremez (zaten onlara hizmet vermiyorsunuz)

> 💡 **Mevcut durum:** App Store Connect'te 27 AB ülkesi "Trader Status Not Provided" uyarısı veriyor. AB'yi kapatınca bu uyarılar ortadan kalkar.

---

## Adım Adım: AB'yi Kapatma İşlemi

### Adım 1: Pricing and Availability'a gidin

1. [App Store Connect](https://appstoreconnect.apple.com)'e giriş yapın
2. **My Apps** → **CizreApp**
3. Sol menüden **Pricing and Availability**

### Adım 2: App Availability'yi yönetin

1. **App Availability** bölümünde **"Manage"** butonuna tıklayın
2. Açılan sayfada ülke/bölge listesi gelecek
3. **Europe** veya ülke bazında filtreleyin

### Adım 3: 27 AB Ülkesini Kapatın

Aşağıdaki 27 ülkenin **her birini "Not Available"** olarak işaretleyin (checkbox'ı kaldırın veya "Remove" deyin):

**AB'nin 27 Ülkesi (tam liste):**
1. Austria (Avusturya)
2. Belgium (Belçika)
3. Bulgaria (Bulgaristan)
4. Croatia (Hırvatistan)
5. Cyprus (Güney Kıbrıs)
6. Czech Republic (Çekya)
7. Denmark (Danimarka)
8. Estonia (Estonya)
9. Finland (Finlandiya)
10. France (Fransa)
11. Germany (Almanya)
12. Greece (Yunanistan)
13. Hungary (Macaristan)
14. Ireland (İrlanda)
15. Italy (İtalya)
16. Latvia (Letonya)
17. Lithuania (Litvanya)
18. Luxembourg (Lüksemburg)
19. Malta
20. Netherlands (Hollanda)
21. Poland (Polonya)
22. Portugal (Portekiz)
23. Romania (Romanya)
24. Slovakia (Slovakya)
25. Slovenia (Slovenya)
26. Spain (İspanya)
27. Sweden (İsveç)

> ⚠️ **Dikkat:** Aşağıdaki ülkeler AB'ye **üye değildir** ama Avrupa'dadır — bunları **kapatmanız gerekmez** (zorunlu değil): Birleşik Krallık (UK), İsviçre, Norveç, İzlanda. Sadece yukarıdaki 27'sini kapatmanız yeterli.

### Adım 4: Kaydedin ve Onaylayın

1. Tüm 27 AB ülkesini kapattıktan sonra **"Done"** veya **"Save"** tıklayın
2. Apple değişikliği işler (genellikle anında veya birkaç saat içinde)

### Adım 5: DSA Trader Bildirimini Yanıtlayın

AB'yi kapattıktan sonra **Manage compliance information** sayfasına gidin:

1. Sol menüden **Manage compliance information** (veya banner bildirimi)
2. Trader self-assessment sorusu: **"I am not a trader"** seçin
3. Sebep/şart olarak: AB'de uygulama dağıtmadığınız için trader değilsiniz
4. Onaylayın

> Apple'ın bildiriminde de yazdığı gibi: *"If you don't distribute apps on the App Store in the EU, you're not acting as a trader on the App Store."* — Yani AB'de dağıtım yapmıyorsanız trader değilsiniz.

---

## Bu Çözümün Sonucu

✅ **Kazanımlar:**
- Adres/telefon/e-posta bilgilerinizi Apple'a vermek zorunda kalmazsınız
- Apple'ın doğrulama süreciyle uğraşmazsınız
- AB kullanıcılarından artık yüklenme/geliştirme talebi gelmez (zaten hizmet vermiyorsunuz)
- DSA trader bildirimi çözülmüş olur
- Türkiye ve diğer pazarlarda **hiçbir şey değişmez** — uygulama orada kullanılmaya devam eder

⚠️ **Sonuçlar (önemli değildir):**
- AB'deki 27 ülkede uygulama listeden kalkar (ama zaten onlara hizmet vermiyorsunuz)
- Eğer ileride AB'ye açılmak isterseniz, o zaman trader bilgisi eklemeniz gerekir

---

## Hızlı Aksiyon Planı

| Adım | İşlem | Tahmini Süre |
|------|-------|--------------|
| 1 | App Store Connect → My Apps → CizreApp → Pricing and Availability | 2 dk |
| 2 | App Availability → Manage | 1 dk |
| 3 | 27 AB ülkesini "Not Available" işaretle | 15 dk |
| 4 | Done/Save ile kaydet | 1 dk |
| 5 | Manage compliance information → "I am not a trader" → onayla | 5 dk |
| 6 | Apple işler (birkaç saat) | otomatik |

**Toplam:** ~25 dakika

---

## İlgili Proje Dosyaları

- Gizlilik politikası: [`docs/PRIVACY_POLICY_APPSTORE.html`](docs/PRIVACY_POLICY_APPSTORE.html)
- Destek sayfası: [`docs/SUPPORT.html`](docs/SUPPORT.html)
- Genel gönderim rehberi: [`docs/APPSTORE_SUBMISSION_GUIDE.md`](docs/APPSTORE_SUBMISSION_GUIDE.md)
- Doldurulacak bilgiler: [`docs/APPSTORE_CONNECT_BILGILERI.txt`](docs/APPSTORE_CONNECT_BILGILERI.txt)
- iOS dağıtım rehberi: [`docs/IOS_APPSTORE_DEPLOYMENT.md`](docs/IOS_APPSTORE_DEPLOYMENT.md)

---

## Sık Sorulan Sorular

**S: AB'yi kapatırsam Türkiye'deki kullanıcılara zarar verir mi?**
C: Hayır. Türkiye ve diğer açık ülkelerde uygulama normal çalışmaya devam eder. Sadece AB'de 27 ülkede kapanır.

**S: AB'yi kapatınca App Store incelemesini geçemez miyim?**
C: Geçersiniz. AB'yi kapatmak DSA gereksinimini çözer. Apple "AB'de dağıtmıyor → trader değil" der.

**S: İleride AB'ye açılmak istersem ne olur?**
C: O zaman tekrar AB ülkelerini açıp trader bilgisi (adres/telefon/e-posta) girmeniz gerekir. Şimdilik kapalı tutmak esneklik sağlar.

**S: "I am not a trader" seçince ne olur?**
C: AB'de dağıtım kapalı olduğundan hiçbir uyarı gösterilmez. (Eğer AB açıkken "Not a trader" seçseydiniz, "tüketici hakları geçerli değildir" uyarısı çıkardı — ama AB kapalıyken bu sorun olmaz.)

**S: AB'yi kapatmak için her ülkeyi tek tek mi seçmem lazım?**
C: Evet, Apple şu an ülke bazlı seçim istiyor. 27 ülkeyi tek tek kapatmanız gerekir (~15 dk).

**S: Tek bir tıklamayla tüm AB'yi kapatamaz mıyım?**
C: Maalesef Apple'ın arayüzünde genelde ülke bazlı seçim yapılır. Listeyi filtreleyip hızlıca kapatabilirsiniz.

---

## Önemli Uyarılar

- Bu belge **hukuk tavsiyesi değildir**. Belirsizlik durumunda bir hukuk danışmanına başvurun.
- AB'yi kapatmak en temiz çözümdür çünkü CizreApp Cizre'ye özel bir uygulamadır ve AB'ye hizmet vermemektedir.
- Türkiye ve diğer açık pazarlarda herhangi bir değişiklik olmaz.
- İleride AB'ye açılmak isterseniz trader bilgisi eklemeniz gerekeceğini unutmayın.