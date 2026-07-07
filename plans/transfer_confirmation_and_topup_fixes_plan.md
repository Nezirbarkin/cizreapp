# Plan: Transfer Onayı + "Admine Bildir" + Bakiye Yükleme Hata Tespiti

Tarih: 2026-07-05
Mod: Architect → Code

## 1) İsteklerin Analizi

### 1.1 "Admine Bildir" → "Sisteme Bildir" (metin)
- **Yer:** `lib/features/wallet/screens/topup_screen.dart:685` (buton label)
- **Etki:** Sadece kullanıcı tarafı UI metni
- **Risk:** Yok (görsel metin)
- **Çözüm:** Tek satır değişiklik
- **Önemli:** "Admine Bildir" → "Sisteme Bildir" yerine, daha doğru etiket: "Bildirim Gönder" veya "Onaya Gönder". Kullanıcının istediği tam olarak buysa "Sisteme Bildir" kullanılacak.

### 1.2 Havale Bildirimi Onay Akışı (EKSİK)
**Mevcut durum:**
- `topup_screen.dart:117 _sendTransferNotification` → admin'lere `notifications` tablosuna `admin_notification` tipinde insert.
- Admin tarafı `notifications_content_v2.dart` admin_notification tipini OKUYOR ve gösteriyor.
- **AMA:** Admin için "onayla/reddet" butonu yok; kullanıcıya otomatik bildirim yok; bakiye otomatik eklenmiyor.

**Kök neden:** Havale bildirimi tek adımlı "bilgilendirme" olarak tasarlanmış, "onay akışı" olarak tasarlanmamış.

**Çözüm — 3 parçalı akış:**

#### A. SQL — Yeni tablo: `transfer_confirmations`
```sql
CREATE TABLE public.transfer_confirmations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  amount NUMERIC(10,2) NOT NULL CHECK (amount > 0),
  bank_account_id UUID REFERENCES public.bank_accounts(id), -- opsiyonel FK
  note TEXT, -- kullanıcının yazdığı dekont notu / açıklama
  status TEXT NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending','approved','rejected')),
  admin_id UUID REFERENCES auth.users(id), -- onaylayan admin
  admin_note TEXT, -- admin'in red gerekçesi veya onay notu
  user_notified BOOLEAN NOT NULL DEFAULT FALSE, -- kullanıcıya bildirim gitti mi
  balance_added BOOLEAN NOT NULL DEFAULT FALSE, -- bakiye eklendi mi (approved ise)
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  resolved_at TIMESTAMPTZ,
  -- idempotent approved → sadece bir kez balance eklenebilmesi için
  CONSTRAINT unique_pending_per_user_amount UNIQUE (user_id, amount, status)
);
CREATE INDEX idx_transfer_confirmations_pending ON public.transfer_confirmations(status, created_at DESC)
  WHERE status = 'pending';
```
- NOT: `unique_pending_per_user_amount` constraint'i — aynı kullanıcı aynı tutar için 2 pending kaydı olamaz (çift bildirim önleme).
- RLS:
  - SELECT: kendi kayıtları (user_id = auth.uid()) + admin SELECT all
  - INSERT: sadece user kendi user_id ile
  - UPDATE: sadece admin (admin_id set edebilir, status değiştirebilir)

#### B. Flutter — Kullanıcı tarafı
- `_sendTransferNotification` artık `transfer_confirmations` tablosuna INSERT eder (notifications tablosuna değil). Böylece onay akışı takip edilebilir.
- Yeni `TransferService` (basit): `submit(amount, bankAccountId, note)` → INSERT + admin'lere push notification gönderir (mevcut `notifications` akışı "havale bildirimi geldi" için kullanılabilir ama zorunlu değil).
- Cevap: kullanıcıya "Bildiriminiz alındı, onaylandığında bakiyenize yansıyacak" snackbar.

#### C. Flutter — Admin tarafı
- Yeni sekme/ekran: `transfer_confirmations_tab_widget.dart` — pending listesi.
- Her satırda: kullanıcı adı, tutar, tarih, banka, not, **"Onayla"** ve **"Reddet"** butonları.
- Onayla → RPC `approve_transfer_confirmation(p_id)` çağrılır (SQL tarafında):
  - INSERT to `transfer_confirmations` admin_id ile UPDATE
  - `add_to_balance(...)` RPC ile kullanıcıya bakiye ekleme (p_type='topup')
  - `balance_transactions` insert (payment_method='transfer', description='Havale onayı')
  - `user_notified=true`, `balance_added=true` flag'leri
  - Kullanıcıya push: "Havale bildiriminiz onaylandı, bakiyenize ₺X eklendi"
  - Kullanıcıya `notifications` insert (type='balance_topup')
- Reddet → UPDATE status='rejected', admin_note ile → kullanıcıya push: "Havale bildiriminiz reddedildi: [gerekçe]"
- Idempotent: aynı id ikinci kez onaylanırsa hata döner (zaten approved).

#### D. SQL — RPC: `approve_transfer_confirmation`
```sql
CREATE OR REPLACE FUNCTION public.approve_transfer_confirmation(
  p_confirmation_id UUID,
  p_admin_note TEXT DEFAULT NULL
) RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_admin UUID := auth.uid();
  v_is_admin BOOLEAN;
  v_conf RECORD;
  v_new_txn_id UUID;
BEGIN
  -- Admin kontrolü
  SELECT EXISTS (
    SELECT 1 FROM profiles WHERE id = v_admin AND role = 'admin'
  ) INTO v_is_admin;
  IF NOT v_is_admin THEN
    RAISE EXCEPTION 'Yetkisiz' USING ERRCODE = '42501';
  END IF;

  -- FOR UPDATE → race koruması
  SELECT * INTO v_conf FROM public.transfer_confirmations
   WHERE id = p_confirmation_id FOR UPDATE;

  IF v_conf IS NULL THEN
    RAISE EXCEPTION 'Kayıt bulunamadı';
  END IF;
  IF v_conf.status <> 'pending' THEN
    RAISE EXCEPTION 'Bu kayıt zaten %s olarak işlenmiş', v_conf.status;
  END IF;

  -- Bakiye ekleme (add_to_balance RPC)
  PERFORM public.add_to_balance(
    p_user_id := v_conf.user_id,
    p_amount := v_conf.amount,
    p_type := 'topup',
    p_description := COALESCE(p_admin_note, 'Havale onayı'),
    p_reference_type := 'transfer_confirmation',
    p_reference_id := v_conf.id
  );

  -- transfer_confirmations update
  UPDATE public.transfer_confirmations
  SET status = 'approved',
      admin_id = v_admin,
      admin_note = p_admin_note,
      balance_added = TRUE,
      resolved_at = NOW()
  WHERE id = p_confirmation_id;

  -- Kullanıcıya bildirim (DB trigger veya client çağrısı)
  -- Burada client tarafında çağrılması daha güvenli (push için Edge Function)
  RETURN json_build_object(
    'status', 'approved',
    'user_id', v_conf.user_id,
    'amount', v_conf.amount
  );
END;
$$;

-- Aynı yapıda reject_transfer_confirmation(p_id, p_admin_note)
```

#### E. Korunma — Mevcut sistem bozulmasın
- Mevcut `_sendTransferNotification` (notifications'a yazan) **dokunulmaz** (kod yolu silinmez, geriye dönük uyumluluk). Yeni `TransferService` eklenir; topup_screen.dart yeni servisi kullanacak.
- Mevcut `notifications` tablosu INSERT'i "havale geldi, kontrol et" admin bildirimi için korunur (admin panelde zaten görünüyor). Onay/reddet işlemi ayrı tablo üzerinden yürür.
- Eski `notifications` tablosunda bekleyen "havale bildirimi" admin_notification kayıtları varsa, admin yeni sekmeden yine de onaylayabilir mi? **HAYIR** — yeni akış `transfer_confirmations` kullanır. Eski kayıtlar "sadece bilgilendirme" olarak işlem görür (geriye dönük veri).
- Migration'da NOT: "Önceki `notifications` üzerinden gelen havale bildirimleri bilgilendirme amaçlıdır, otomatik bakiye yansımaz. Bu tarihten sonra gönderilen tüm bildirimler yeni tabloya yazılır ve admin onayı ile bakiyeye yansır."

### 1.3 Bakiye Yükle Hata: "oturumumuzun süresi dolmuş"

**Kök neden teşhisi:**
- Edge function `create-balance-topup/index.ts`:
  - Auth kontrolü → başarılı (admin'lere debugPrint göstermez ama hata kodu 500 dönmeliydi, "Geçersiz oturum" mesajıyla)
  - `settings` okunuyor — `iyzico_api_url` alanı `app_about_settings` tablosundan
  - iyzico API çağrısı → response.token + paymentPageUrl başarıyla alındı
  - DB insert başarılı → response döner
- **Eğer "oturumun süresi dolmuş" mesajı edge function hatası DEĞİLSE** (topup_screen.dart zaten "Kredi kartı sistemi yapılandırılmamış" diyor — farklı mesaj), bu iyzico'nun kendi ödeme sayfası mesajı.
- İyzico kendi sayfasında "Oturumunuzun süresi dolmuş" diyorsa 2 nedeni olabilir:
  1. **iyzico api_key/secret_key yanlış veya süresi dolmuş** → iyzico oturum açamıyor
  2. **iyzico api_url sandbox/prod uyumsuz** → sandbox anahtarıyla prod URL'e gidiyor (veya tam tersi)
  3. **token süresi dolmuş** — iyzico token'ları 30dk geçerli ama bu başlangıç token'ı, yeni istek olduğu için geçerli olmalı
  4. **WebView session/cookie sorunu** — iyzico ödeme form'u iframe/cookie kullanır, WebView'da cookie persistence sıkıntılı olabilir (ama ana sayfa yüklendiyse token zaten geçerli)

**Çözüm — savunma önlemleri:**
1. Edge function'a **iyzico response'u debug amaçlı tam döküm** — kullanıcının bize hata logunu gösterebilmesi için. Şu an sadece errorCode/errorMessage logluyoruz, tam response'u logla.
2. Edge function'da **iyzico_api_url validasyonu**: sandbox/prod uyumu kontrolü yok şu an. Ek: eğer `iyzico_api_url` içinde "sandbox" varsa sandbox anahtarı kullanılmalı (uyarı ver).
3. **Flutter'da yeni fallback mesajı**: Edge function error'unda "iyzico" kelimesi geçiyorsa, kullanıcıya "Ödeme sağlayıcısı şu an yanıt vermiyor" de, ham teknik mesajı gösterme.
4. **Admin "iyzico Test Et" butonu** — admin panelde yeni bir debug butonu: iyzico credentials ile ufak bir test (₺1.00 iyzico init denemesi, sonuç göster).
5. **EN KRİTİK: Asıl çözüm** — iyzico credentials (api_key, secret_key, api_url) prod/sandbox uyumlu olduğundan emin ol. Bu backend ayarı, kullanıcının kendisinin Supabase env veya `app_about_settings` tablosundan düzeltmesi gerekir. **AI tarafında otomatik çözemeyiz; kullanıcıya hangi değerlerin prod olduğunu sormalı ve net adım adım ne yapacağını söylemeliyiz.**

## 2) Değişiklik Planı (Sıralı)

### Adım 1 — Hızlı kazanım (5 dk)
1. `topup_screen.dart` "Admine Bildir" → "Sisteme Bildir"
2. Edge function `create-balance-topup` — iyzico response tam dökümünü console.log'a ekle
3. Flutter `topup_screen.dart` hata parser'ına yeni kalıplar: "session", "oturum", "expired" → "Ödeme sağlayıcısına bağlanılamıyor, lütfen daha sonra tekrar deneyin veya yönetici ile iletişime geçin."

### Adım 2 — Havale Onay Altyapısı (30-45 dk)
1. SQL migration `20260705_TRANSFER_CONFIRMATIONS.sql`:
   - `transfer_confirmations` tablosu (idempotent CREATE)
   - Index
   - RLS politikaları (kendi kaydı SELECT + admin all)
   - `approve_transfer_confirmation` RPC
   - `reject_transfer_confirmation` RPC
   - Trigger: kullanıcıya `notifications` insert (status değişince, onay/red için) → `user_notified=true`
   - NOTIFY pgrst reload
2. Flutter — `lib/core/services/transfer_service.dart` (yeni):
   - `submitTransferConfirmation(amount, note)` → INSERT to `transfer_confirmations`
   - `getPendingConfirmations()` (admin) → SELECT pending
   - `approveConfirmation(id, adminNote)` → RPC
   - `rejectConfirmation(id, adminNote)` → RPC
3. Flutter — `lib/features/wallet/screens/topup_screen.dart`:
   - `_sendTransferNotification` YERİNE `_submitTransferConfirmation` çağrılır
   - Buton label: "Admine Bildir" → "Sisteme Bildir" + "Onaya Gönder" alt başlık
4. Flutter — `lib/features/admin/widgets/transfer_confirmations_tab_widget.dart` (yeni):
   - Pending listesi
   - Onayla/Reddet butonları + dialog (admin note)
   - Onaylandığında bakiye ekleme sonucu snackbar
5. Flutter — `lib/features/admin/screens/admin_dashboard_screen.dart`:
   - Yeni sekme: "Havale Onayları" → TransferConfirmationsTabWidget
   - Veya mevcut Cüzdan Ayarları sekmesinin yanına bir badge (pending count)
6. CHANGELOG kaydı + PROJE_HAVIZA_SCHEMA.md §2.7'ye tablo eklemesi

### Adım 3 — Bakiye Yükle Hata Kalıcı Çözümü
1. ✅ Adım 1 zaten yapıldı (daha iyi hata mesajı + debug log)
2. Edge function `create-balance-topup` — `iyzico_api_url` prod/sandbox kontrolü
3. Admin "iyzico Bağlantı Testi" butonu (yeni edge function veya admin dashboard buton)
4. **Kullanıcıya sorulacak:** iyzico API key/secret sandbox mı prod mu? api_url ne? `app_about_settings` tablosunda iyzico_api_url kolonunda ne yazıyor?

## 3) Risk Analizi

| Risk | Önlem |
|------|-------|
| Mevcut `_sendTransferNotification` davranışı bozulur | Eski fonksiyon korunur, yeni `TransferService` paralel çalışır. Topup ekranı yeni servise geçer, eski fonksiyon başka yerden çağrılmıyor (search_files ile teyit edildi) |
| Havale onayında çift bakiye eklenir | RPC SELECT FOR UPDATE + status='pending' check + balance_added flag |
| Admin olmayan kişi onaylar | RPC içinde `profiles.role='admin'` kontrolü (SECURITY DEFINER + auth.uid) |
| iyzico credential değişikliği gerekir | Kullanıcıya net adım adım talimat + admin debug butonu |
| Mevcut notifications üzerinden gelen eski havale bildirimleri | Yeni akışa taşınmaz (geriye dönük veri), sadece yeni bildirimler yeni tabloya |
| Edge function değişikliği deploy gerekli | Açıkça belirtilecek |

## 4) Sorulacak Sorular (Kullanıcıya Onay)

1. "Sisteme Bildir" metni onay mı? (buton label değişikliği)
2. Havale onayı için yeni `transfer_confirmations` tablosu + admin sekmesi eklensin mi? (önerilen)
3. Onaylandığında **otomatik bakiye ekleme** olsun mu? (önerilen, admin "Onayla"ya basınca bakiye + bildirim gider)
4. Onaylandığında **hangi bildirim** gitsin? (önerilen: uygulama içi notification + push notification "Bakiyenize ₺X eklendi")
5. iyzico prod/sandbox — admin ayarları nasıl düzeltilir? (kullanıcıdan iyzico_api_key, iyzico_secret_key, iyzico_api_url bilgileri istenecek + Admin debug butonu eklenecek)
6. Havale bildiriminde kullanıcı **dekont/fotoğraf** ekleyebilsin mi? (yoksa sadece tutar + opsiyonel not mu?)
7. Havale onayı için **tek seferde birden fazla admin onayı** mı gerekir? (önerilen: tek admin onayı yeterli)

## 5) Beklenen Çıktı (Uygulama Sonrası)

**Havale akışı (yeni):**
1. Müşteri: Bakiye Yükle → Havale/EFT → banka seç → tutar gir → isteğe bağlı not → "Sisteme Bildir" butonu
2. `transfer_confirmations` tablosuna INSERT (status='pending')
3. Admin: "Havale Onayları" sekmesi → listede pending kayıt → "Onayla" → `approve_transfer_confirmation` RPC
4. RPC: bakiyeyi ekler + `balance_transactions` insert + kullanıcıya push + notifications insert
5. Kullanıcı: bakiye güncellenir + "Havale onaylandı" bildirimi alır

**İstek 1 ve 2 sırayla uygulanır**, **istek 3 (iyzico hata)** için kullanıcıdan ek bilgi alınmalı (iyzico credentials durumu).