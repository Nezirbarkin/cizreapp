-- =============================================================================
-- purchase_avatar_photo_flame_overlay_b üzerindeki başıboş unlock_after_orders
-- değerini temizle
-- =============================================================================
-- 20260818000001 çalıştırılmadan ÖNCE bu satırda zaten unlock_after_orders = 1
-- yazılıydı (muhtemelen migration history desync'i nedeniyle daha önce local
-- dosyaya hiç yansımamış ayrı bir deneme). Bu, 30'luk küratörlü avatar
-- listesinde #1 numarasında (purchase_avatar_snake_coil_a ile) çakışmaya
-- neden oluyordu: total_items=31 dönüyordu ve order #1'de kullanıcı iki
-- avatar efekti birden kazanıyordu. Bu satır 20260818000001'in küratörlü
-- 30'luk listesinde YOK; değeri null'a çekiyoruz.
-- =============================================================================

begin;

update public.profile_feature_catalog
set unlock_after_orders = null, updated_at = now()
where code = 'purchase_avatar_photo_flame_overlay_b'
  and unlock_after_orders = 1;

commit;

-- Kontrol:
-- select kind, count(*) from public.profile_feature_catalog
-- where unlock_after_orders is not null group by kind order by kind;
-- Beklenen: avatar_effect = 30, cover_effect = 23.
