-- Zorunlu güncelleme: minimum versiyonu yükselt (1.2.6+25'in altındaki sürümler güncellemeye zorlanır)
UPDATE public.app_about_settings
SET
  min_version = '1.2.6',
  min_build_code = 25,
  current_version = '1.2.6',
  current_build_code = 25,
  force_update_enabled = true
WHERE id = 1;
