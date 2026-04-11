-- ============================================================================
-- ŞİFRE SIFIRLAMA APP REDIRECT AYARLARI REHBERİ
-- ============================================================================
-- Bu dosya sadece rehber içindir, SQL olarak çalıştırmanıza gerek yok
-- ============================================================================

/*
 * BURADA YAPILMASI GEREKENLER (Supabase Dashboard'da):
 * 
 * 1. Supabase Dashboard > Authentication > URL Configuration
 *    - Site URL: cizreapp://reset-password
 *    - Redirect URLs: cizreapp://reset-password
 * 
 * 2. Android Uygulamanız yüklü olmalı
 *    - Package Name: com.cizreapp.app
 * 
 * 3. Email Template'i Güncelleyin:
 *    - Supabase Dashboard > Authentication > Email Templates
 *    - Reset Password template'ini açın
 *    - Aşağıdaki HTML'i yapıştırın
 */

-- ============================================================================
-- EMAIL TEMPLATE (HTML) - Supabase Dashboard'a yapıştırın
-- ============================================================================

/*
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Şifre Sıfırlama - CizreApp</title>
    <style>
        body { font-family: Arial, sans-serif; max-width: 600px; margin: 0 auto; padding: 20px; }
        .btn { display: inline-block; background: #dc3545; color: white; padding: 15px 30px; 
               text-decoration: none; border-radius: 5px; font-weight: bold; }
    </style>
</head>
<body style="text-align: center;">
    <h1>CizreApp</h1>
    <h2>Şifre Sıfırlama</h2>
    <p>Şifrenizi sıfırlamak için aşağıdaki butona tıklayın.</p>
    
    <a href="{{ .ConfirmationURL }}" class="btn">🔐 Şifremi Sıfırla</a>
    
    <p style="color: #999; font-size: 12px;">Butona tıkladığınızda uygulama açılacaktır.</p>
    <p style="font-size: 12px;">
        Uygulamanız yok mu? 
        <a href="https://play.google.com/store/apps/details?id=com.cizreapp.app">Google Play'den İndir</a>
    </p>
</body>
</html>
*/

-- ============================================================================
-- TEST İÇİN: Kullanıcı ve token kontrolü
-- ============================================================================

-- Aktif kullanıcıları listele
-- SELECT id, email, created_at, last_sign_in_at 
-- FROM auth.users 
-- WHERE email_confirmed_at IS NOT NULL 
-- ORDER BY last_sign_in_at DESC;

-- ============================================================================
-- ANDROID MANIFEST KONTROLÜ (zaten yapıldı)
-- ============================================================================

/*
 * android/app/src/main/AndroidManifest.xml dosyasında zaten şu intent-filter var:
 * 
 * <intent-filter>
 *     <action android:name="android.intent.action.VIEW" />
 *     <category android:name="android.intent.category.DEFAULT" />
 *     <category android:name="android.intent.category.BROWSABLE" />
 *     <data android:scheme="cizreapp" android:host="reset-password" />
 * </intent-filter>
*/

-- ============================================================================
-- ÇALIŞMA PRENSİBİ:
-- ============================================================================

/*
 * 1. Kullanıcı "Şifremi Unuttum" butonuna tıklar
 * 2. Supabase kullanıcıya email gönderir
 * 3. Email'deki buton: {{ .ConfirmationURL }}
 * 4. Supabase bu URL'i oluştururken redirect_to parametresini ekler:
 *    - https://[PROJECT].supabase.co/auth/v1/verify?token=xxx&type=recovery&redirect_to=cizreapp://reset-password
 * 5. Kullanıcı linke tıklar
 * 6. Tarayıcı Supabase sayfasına gider, token'ı doğrular
 * 7. Supabase kullanıcıyı redirect_to URL'ine (cizreapp://reset-password) yönlendirir
 * 8. Android cizreapp:// scheme'ini tanır ve CizreApp'i açar
 * 9. Uygulama deep link'i yakalar ve şifre sıfırlama ekranını gösterir
 */

COMMENT ON COLUMN auth.users.email_confirmed_at IS 'Email doğrulama tarihi';
COMMENT ON COLUMN auth.users.last_sign_in_at IS 'Son giriş tarihi';
