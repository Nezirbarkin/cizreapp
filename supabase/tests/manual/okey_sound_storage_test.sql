-- =============================================================================
-- 101 Okey Plus — SES DEPOSU: .m4a desteği, boyut sınırı, silerken temizlik
--   supabase db query --linked --file supabase/tests/manual/okey_sound_storage_test.sql
--
-- BU TESTİN KOVALADIĞI HATALAR (ikisi de sessizce başarısız oluyordu):
--
--   1) .m4a YÜKLENEMİYORDU. Dosya seçici .m4a'ya izin veriyor ama bucket'ın
--      izinli MIME listesinde audio/mp4 ve audio/x-m4a yoktu; sunucu yüklemeyi
--      reddediyor, kullanıcı sebebini anlayamıyordu.
--
--   2) BOYUT SINIRI ÇELİŞİYORDU. Admin arayüzü şarkı için 8 MB'a izin
--      veriyordu ama bucket 2 MB'da kesiyordu.
--
--   3) SİLİNEN DOSYA DEPODA KALIYORDU. admin_okey_clear_sound yalnızca
--      veritabanı kaydını siliyordu; dosya sonsuza kadar kota tüketiyordu.
--      Artık silinen kaydın yolunu döner ve istemci dosyayı da kaldırır.
-- =============================================================================

BEGIN;

DO $$
DECLARE
  v_types text[];
  v_limit bigint;
  v_admin uuid;
  v_returned text;
  v_left int;
BEGIN
  ----------------------------------------------------------------------------
  -- [1] Bucket .m4a'nın MIME türlerini KABUL ETMELİ
  ----------------------------------------------------------------------------
  SELECT allowed_mime_types, file_size_limit
  INTO v_types, v_limit
  FROM storage.buckets WHERE id = 'okey-sounds';

  IF v_types IS NULL THEN
    RAISE EXCEPTION 'TEST_FAIL[1]: okey-sounds bucket bulunamadi';
  END IF;

  IF NOT ('audio/mp4' = ANY(v_types)) THEN
    RAISE EXCEPTION
      'TEST_FAIL[1]: audio/mp4 izinli degil — .m4a yuklenemez (%)', v_types;
  END IF;
  IF NOT ('audio/x-m4a' = ANY(v_types)) THEN
    RAISE EXCEPTION
      'TEST_FAIL[1]: audio/x-m4a izinli degil — .m4a yuklenemez';
  END IF;
  RAISE NOTICE 'TEST_OK[1]: bucket .m4a MIME turlerini kabul ediyor';

  ----------------------------------------------------------------------------
  -- [2] Boyut sınırı arka plan şarkısına YETMELİ (arayüz 10 MB vaat ediyor)
  ----------------------------------------------------------------------------
  IF COALESCE(v_limit, 0) < 10485760 THEN
    RAISE EXCEPTION
      'TEST_FAIL[2]: boyut siniri % byte — arayuzdeki 10 MB vaadi tutulamaz',
      v_limit;
  END IF;
  RAISE NOTICE 'TEST_OK[2]: boyut siniri sarki icin yeterli (% byte)', v_limit;

  ----------------------------------------------------------------------------
  -- [3] Eski efekt uzantıları da izinli KALMALI (gerileme olmasın)
  ----------------------------------------------------------------------------
  IF NOT ('audio/mpeg' = ANY(v_types)) THEN
    RAISE EXCEPTION 'TEST_FAIL[3]: audio/mpeg (mp3) artik izinli degil!';
  END IF;
  IF NOT ('audio/wav' = ANY(v_types)) OR NOT ('audio/ogg' = ANY(v_types)) THEN
    RAISE EXCEPTION 'TEST_FAIL[3]: wav/ogg destegi kayboldu';
  END IF;
  RAISE NOTICE 'TEST_OK[3]: mp3/wav/ogg destegi korunuyor';

  ----------------------------------------------------------------------------
  -- [4] admin_okey_clear_sound SİLİNEN KAYDIN YOLUNU DÖNMELİ
  --     (istemci dosyayı depodan bu yolla kaldırıyor)
  ----------------------------------------------------------------------------
  SELECT id INTO v_admin FROM public.profiles ORDER BY created_at ASC LIMIT 1;
  IF v_admin IS NULL THEN
    RAISE EXCEPTION 'TEST_SKIP: profil yok';
  END IF;
  PERFORM set_config('request.jwt.claim.sub', v_admin::text, true);

  IF NOT public.is_admin() THEN
    RAISE NOTICE 'TEST_SKIP[4]: calistiran kullanici admin degil';
  ELSE
    PERFORM public.admin_okey_set_sound(
      'test_key_tmp',
      'test_key_tmp/12345.m4a',
      'https://example.invalid/test.m4a'
    );

    SELECT public.admin_okey_clear_sound('test_key_tmp') INTO v_returned;

    IF v_returned IS DISTINCT FROM 'test_key_tmp/12345.m4a' THEN
      RAISE EXCEPTION
        'TEST_FAIL[4]: silme depo yolunu dondurmedi (%) — dosya depoda kalir',
        v_returned;
    END IF;

    SELECT count(*)::int INTO v_left FROM public.okey_sound_assets
    WHERE sound_key = 'test_key_tmp';
    IF v_left <> 0 THEN
      RAISE EXCEPTION 'TEST_FAIL[4]: kayit silinmedi';
    END IF;
    RAISE NOTICE 'TEST_OK[4]: silme hem kaydi siliyor hem depo yolunu donuyor';

    ------------------------------------------------------------------------
    -- [5] Olmayan bir anahtar silinirse NULL döner (istemci patlamamalı)
    ------------------------------------------------------------------------
    SELECT public.admin_okey_clear_sound('yok_boyle_bir_key') INTO v_returned;
    IF v_returned IS NOT NULL THEN
      RAISE EXCEPTION 'TEST_FAIL[5]: olmayan kayit icin yol dondu (%)',
        v_returned;
    END IF;
    RAISE NOTICE 'TEST_OK[5]: olmayan kayitta NULL donuyor';

    ------------------------------------------------------------------------
    -- [6] Yükleme öncesi ESKİ dosyanın yolu okunabilmeli (temizlik için)
    ------------------------------------------------------------------------
    PERFORM public.admin_okey_set_sound(
      'test_key_tmp2', 'test_key_tmp2/1.m4a', 'https://example.invalid/1.m4a');

    SELECT public.admin_okey_previous_sound_path('test_key_tmp2')
    INTO v_returned;

    IF v_returned IS DISTINCT FROM 'test_key_tmp2/1.m4a' THEN
      RAISE EXCEPTION
        'TEST_FAIL[6]: onceki dosya yolu okunamadi (%) — eski dosyalar birikir',
        v_returned;
    END IF;
    RAISE NOTICE 'TEST_OK[6]: onceki dosya yolu okunabiliyor';
  END IF;

  RAISE NOTICE '=== SES DEPOSU TESTLERI GECTI ===';
END $$;

ROLLBACK;
