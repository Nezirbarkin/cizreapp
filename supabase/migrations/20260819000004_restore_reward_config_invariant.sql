-- =============================================================================
-- DÜZELTME: test_mode + earn_enabled birlikte açılamaz (invariant ihlali geri alınır)
-- =============================================================================
-- HATA: 20260819000001'in 7. bölümü ad_settings'i doğrudan UPDATE ile
--   is_enabled = true, reward_points_earn_enabled = true
-- yaptı. Ancak test_mode = true idi ve sistem bu kombinasyonu AÇIKÇA yasaklıyor:
--
--   * DB: admin_update_reward_points_config()
--       IF p_test_mode AND p_earn_enabled THEN
--         RAISE EXCEPTION 'TEST_MODE_CANNOT_EARN' USING ERRCODE = '22023';
--   * Dart: ad_settings_service.dart:102
--       if (earnEnabled && testMode) return 'Test modunda ekonomik puan kazanımı açılamaz.';
--
-- Yani düz UPDATE, admin panelinin ve RPC'nin uyguladığı invariant'ı atladı ve
-- ad_settings'i sistemin geçersiz saydığı bir duruma soktu.
--
-- AYRICA bu ayar tek başına puan kazandırmıyordu. Kazanç zincirinin TAMAMI
-- doğrulandı ve şu an kredi yazacak hiçbir yol yok:
--   1. Puanı yazan tek fonksiyon grant_verified_ad_points; onu çağıran tek yer
--      admob-ssv-callback Edge Function'ı (prosrc taraması ile doğrulandı).
--   2. O callback ADMOB_SSV_MODE = "test" iken grant RPC'sine HİÇ ulaşmadan
--      204 döner ("test environment ... can never create economic credit").
--      Canlı secret hash'i sha256("test") ile birebir eşleşiyor.
--   3. Callback'in requireEnv listesindeki 8 değişkenden 6'sı canlıda TANIMSIZ
--      (yalnız ADMOB_SSV_MODE ve ADMOB_SSV_HASH_SECRET set): ADMOB_SSV_PUBLIC_KEY_URL,
--      ADMOB_SSV_KEY_CACHE_TTL_SECONDS, ADMOB_SSV_MAX_AGE_SECONDS,
--      ADMOB_SSV_FUTURE_SKEW_SECONDS, ADMOB_SSV_PRODUCTION_AD_UNITS,
--      ADMOB_SSV_TEST_AD_UNITS. Bu haliyle callback zaten INVALID_CONFIG atar.
--   4. ad_reward_sessions tablosu boş — akış hiç çalışmamış.
--
-- Sonuç: ayarları açık bırakmak kullanıcıya reklam izletip KARŞILIĞINDA HİÇBİR
-- ŞEY vermek demekti. Ayarlar geri alınıyor; puan kazanımı ancak AdMob konsolu
-- tarafındaki SSV kurulumu bittikten sonra (bkz. dosya sonundaki kontrol
-- listesi) ve admin panelindeki RPC üzerinden açılmalıdır.
--
-- Puanla HARCAMA (reward_points_spend_enabled) açık kalır: mevcut puanı olan
-- bir kullanıcı profil özelliği satın alabilmelidir ve 20260819000003 ile o yol
-- artık gerçekten çalışıyor.
-- =============================================================================

begin;

update public.ad_settings
set is_enabled = false,
    reward_points_earn_enabled = false,
    updated_at = now()
where id = 1;

-- AdMob iOS App ID canlıda NULL'dı; native Info.plist'te ise tanımlı
-- (ca-app-pub-3604161523594294~4530200113). Bu alan çalışma anında
-- kullanılmıyor (SDK değeri plist/manifest'ten okur, admin ekranı NULL ise
-- "yok (native plist)" gösterir), ancak admin_update_reward_points_config
-- production'a geçerken ad-unit/identifier doğrulaması yaptığı için alanın
-- native değerle tutarlı olması gerekiyor. Android tarafı zaten manifest ile
-- birebir aynı (ca-app-pub-3604161523594294~7253632038, doğrulandı).
update public.ad_settings
set admob_app_id_ios = 'ca-app-pub-3604161523594294~4530200113',
    updated_at = now()
where id = 1
  and coalesce(nullif(trim(admob_app_id_ios), ''), '') = '';

commit;

-- =============================================================================
-- Kontrol:
--   select is_enabled, test_mode, reward_points_earn_enabled,
--          reward_points_spend_enabled, admob_app_id_ios
--   from public.ad_settings where id = 1;
--   -- Beklenen: false, true, false, true, ca-app-pub-...~4530200113
--
-- PUAN KAZANIMINI GERÇEKTEN AÇMAK İÇİN (sırayla, hiçbiri atlanamaz):
--   1. AdMob konsolunda rewarded ad unit'lerine SSV callback URL'i tanımla:
--        https://<project-ref>.supabase.co/functions/v1/admob-ssv-callback
--   2. Eksik 6 Edge Function secret'ını set et (değerler için
--      supabase/functions/README.md:42-49):
--        ADMOB_SSV_PUBLIC_KEY_URL=https://www.gstatic.com/admob/reward/verifier-keys.json
--        ADMOB_SSV_KEY_CACHE_TTL_SECONDS / ADMOB_SSV_MAX_AGE_SECONDS /
--        ADMOB_SSV_FUTURE_SKEW_SECONDS / ADMOB_SSV_PRODUCTION_AD_UNITS /
--        ADMOB_SSV_TEST_AD_UNITS
--   3. README.md:85 runbook'una göre önce ADMOB_SSV_MODE=test ile protokolü
--      doğrula (kredi yazmaz), sonra ADMOB_SSV_MODE=production yap.
--   4. Ayarları DÜZ UPDATE ile değil, admin panelinden
--      admin_update_reward_points_config RPC'si ile değiştir: test_mode=false,
--      ssv_enabled=true, feature_mode='enabled', earn_enabled=true.
--      (RPC invariant'ları uygular; düz UPDATE uygulamaz — bu migration'ın
--      düzelttiği hatanın sebebi tam olarak buydu.)
-- =============================================================================
