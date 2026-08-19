-- =============================================================================
-- İlanlar: varsayılan onay akışını kapat — yeni ilanlar doğrudan yayınlansın
-- =============================================================================
-- İSTEK: Kullanıcılar ilan verdiğinde admin onayı beklemeden direkt paylaşım
-- yapabilsin. validate_ilan_write() trigger'ı (20260817000006_ilanlar_system.sql
-- satır ~192-206, 213-215) zaten ilan_settings.require_approval bayrağına göre
-- status'ü 'pending' ya da 'published' olarak seçiyor — trigger mantığına
-- dokunmaya gerek yok, sadece bayrağın varsayılanını değiştiriyoruz.
--
-- Admin moderasyon altyapısı (reddet/arşivle/onayı geri al, admin panelindeki
-- "Yönetici onayı zorunlu" switch'i) YAPISAL olarak değişmiyor — admin isterse
-- bu ayarı panelden tekrar true yapabilir, kötüye kullanım durumunda yayından
-- sonra da reddedip/arşivleyebilir.
-- =============================================================================

BEGIN;

ALTER TABLE public.ilan_settings
  ALTER COLUMN require_approval SET DEFAULT false;

-- ilan_settings tekil satırlı (id=1) bir ayar tablosu; sadece DEFAULT
-- değiştirmek yeni satır eklenmediği sürece etkisiz kalır. Mevcut satırı da
-- yeni davranışa (onaysız yayın) taşıyoruz.
UPDATE public.ilan_settings
SET require_approval = false,
    updated_at = now()
WHERE id = 1;

COMMENT ON COLUMN public.ilan_settings.require_approval IS
  'Varsayılan false: yeni ilanlar doğrudan published olur. Admin Ayarlar sekmesinden tekrar true yapabilir.';

COMMIT;

-- =============================================================================
-- DOĞRULAMA:
--   SELECT require_approval FROM public.ilan_settings WHERE id = 1;
--   -- Beklenen: false
-- =============================================================================
