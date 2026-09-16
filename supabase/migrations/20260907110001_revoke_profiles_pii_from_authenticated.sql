-- =============================================================================
-- profiles: authenticated rolünden PII sütun yetkilerini geri al (FAZ 1)
-- =============================================================================
-- SORUN
-- -----
-- 20260803000006_secure_profiles_privileges_and_pii.sql, `anon` VE
-- `authenticated` için base `public.profiles` tablosundaki hassas sütun
-- GRANT'lerini kaldırmayı amaçlıyordu. Canlı veritabanında bu yalnızca
-- `anon` için gerçekleşmiş: `anon` 15 güvenli sütun görürken,
-- `authenticated` hâlâ TABLO seviyesinde SELECT + 46 sütunun tamamına
-- sahip.
--
-- `profiles_select_public` politikası `TO {anon, authenticated} USING (true)`
-- olduğu için, ücretsiz açılan HERHANGİ bir hesap tüm kullanıcıların
-- şu alanlarını okuyabiliyordu:
--
--   invoice_tc_no          -> TC kimlik numarası
--   invoice_address        -> fatura adresi
--   invoice_email / *_tax_number / *_tax_office / *_full_name
--   fcm_token              -> push bildirim jetonu
--   delete_confirmation_code (+ expires_at) -> hesap silme onay kodu
--   is_suspicious / suspicious_reason / suspicious_flagged_at -> iç moderasyon
--   last_location_update / last_known_heading -> konum meta verisi
--   platform, is_admin
--
-- Uygulama kodu bu revoke'un ZATEN yapıldığını varsayıyor:
--   - lib/features/profile/services/profile_service.dart:17-22
--   - lib/features/admin/.../_part_data_loaders.dart:1194-1200
--     ("grant'i 20260803000006 ile kaldırıldı; doğrudan from('profiles')
--       çağrısı 42501 fırlatır")
-- Yani bu migration kodu bozmuyor, kodun zaten beklediği duruma getiriyor.
--
-- FAZ AYRIMI
-- ----------
-- FAZ 1 (bu migration): Mağazadaki v1.3.0+35 istemcisinin `profiles`
--   üzerinden HİÇ okumadığı 18 sütunun GRANT'i kaldırılır. Yayındaki
--   uygulama bu değişiklikten etkilenmez.
--
-- FAZ 2 (istemci güncellemesi yayınlandıktan sonra):
--   email, phone, last_known_lat, last_known_lng de kaldırılacak.
--   Bu dört sütun şu an yayındaki istemci tarafından okunuyor; şimdi
--   kaldırmak canlı kullanıcılarda ödeme/kurye/satıcı ekranlarını kırardı.
--   Bunların yerine gelen RPC'ler bu migration'da hazırlanıyor.
--
-- Doğrulanan durum (canlı DB, 2026-09-07):
--   anon          -> 15 sütun (zaten güvenli)
--   authenticated -> TABLO SELECT + 46 sütun  <-- kapatılan açık
-- =============================================================================

BEGIN;

-- -----------------------------------------------------------------------------
-- 1) Tablo seviyesindeki toptan SELECT yetkisini kaldır
-- -----------------------------------------------------------------------------
-- Tablo seviyesi GRANT, sütun seviyesi GRANT'leri gölgede bırakır; sütun
-- kısıtlamasının etkili olması için önce bunun gitmesi gerekir.
REVOKE ALL ON TABLE public.profiles FROM authenticated;

-- -----------------------------------------------------------------------------
-- 2) Yalnız güvenli sütunlara SELECT ver
-- -----------------------------------------------------------------------------
-- Bu liste, lib/ altındaki TÜM `from('profiles')` / `profiles!inner(...)`
-- çağrıları ile profiles okuyan 10 view'ın (hepsi security_invoker=true,
-- yani çağıranın sütun yetkisine tabi) taranmasıyla çıkarıldı.
GRANT SELECT (
  -- kimlik / görünen profil
  id,
  username,
  full_name,
  avatar_url,
  banner_url,
  cover_url,
  bio,
  website,
  location,
  gender,
  -- rol & durum (uygulama 5 dosyada `role` okuyor)
  role,
  status,
  is_verified,
  delivered_count,
  -- varlık / gizlilik tercihleri (chat & sosyal ekranlar okuyor)
  is_online,
  is_online_enabled,
  is_ghost_mode,
  show_last_seen,
  last_seen,
  profile_is_public,
  messages_enabled,
  allow_messages_from_non_followers,
  -- zaman damgaları (public_profiles_safe / public_profiles_chat kullanıyor)
  created_at,
  updated_at,
  -- ── FAZ 2'de kaldırılacak: yayındaki v1.3.0+35 hâlâ okuyor ──
  email,
  phone,
  last_known_lat,
  last_known_lng
) ON public.profiles TO authenticated;

-- Kaldırılan 18 sütun (artık authenticated okuyamaz):
--   fcm_token, delete_confirmation_code, delete_confirmation_expires_at,
--   is_admin, invoice_type, invoice_full_name, invoice_tax_number,
--   invoice_tc_no, invoice_tax_office, invoice_address, invoice_email,
--   invoice_saved_at, is_suspicious, suspicious_reason,
--   suspicious_flagged_at, last_location_update, last_known_heading,
--   platform
--
-- Bu sütunlara meşru erişim yolları (hepsi zaten canlıda mevcut):
--   kendi faturam        -> public.get_my_invoice_profile()
--   kendi tam profilim   -> public.get_my_profile()
--   admin kullanıcı list -> public.admin_list_users() / admin_user_list_with_stats()
--   edge function'lar    -> service_role (sütun kısıtlamasına tabi değil)

COMMIT;

-- PostgREST şema önbelleğini tazele; aksi halde yeni yetkiler
-- bir sonraki otomatik reload'a kadar yansımaz.
NOTIFY pgrst, 'reload schema';
