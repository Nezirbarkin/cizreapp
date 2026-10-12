-- storage.objects politikalarını sıkılaştırma.
--
-- Sorun 1 (yazma): avatars, covers, posts, products, profiles, public,
-- shop-images ve user_reports kovalarında <kova>_insert/_update/_delete
-- politikaları "TO anon, authenticated" ve tek koşulları bucket_id idi.
-- Uygulamaya gömülü anon anahtarıyla, oturum açmadan herkes bu kovalara dosya
-- yükleyebiliyor, var olan HERHANGİ bir dosyanın üzerine yazabiliyor ve
-- silebiliyordu. stories, news-images ve deals için aynı açıklık her oturum
-- açmış kullanıcıya açıktı.
--
-- Sorun 2 (listeleme): 14 herkese açık kovada "bucket_id = '...'" koşullu
-- SELECT politikası, anon anahtarıyla kovadaki tüm dosya yollarının
-- listelenmesine izin veriyordu (Security Advisor: Public Bucket Allows
-- Listing). Herkese açık kovada dosyaya URL ile erişim için bu politika
-- gerekmez.
--
-- Değişmeyen kural (bu göçün güvenlik gerekçesi): bir kullanıcının KENDİ
-- yüklediği dosyalar (owner_id = auth.uid()) ve adminler için her politikanın
-- sonucu öncekiyle aynıdır; yeni koşul her yerde "eski koşul VE (sahibi VEYA
-- kovanın mevcut yazma kuralı VEYA admin)" biçimindedir. Değişen yalnızca:
--   * anon çağıranlar (hiçbir istemci akışı oturumsuz yükleme yapmaz; kovalardaki
--     sahipsiz dosyaların tamamı test artığı ya da service_role betikleridir),
--   * başkasının dosyasına dokunan, admin olmayan kullanıcılar.
-- Git geçmişindeki hiçbir istemci sürümü bu kovalarda başkasının dosyasını
-- silmez/üzerine yazmaz (bütün yollar zaman damgalıdır) ve hiçbiri storage
-- list/download çağırmaz. Tek istisna eski sürümlerin sabit adlı grup
-- görselleridir (public/group_images): "Group admins can ..." politikalarına
-- DOKUNULMADI.
--
-- INSERT politikaları oturum açmış kullanıcı için aynen kalır.

begin;

-- 1) Yazma politikaları: anon kalkar; UPDATE/DELETE sahibine ya da admine daralır
alter policy avatars_insert on storage.objects to authenticated;
alter policy avatars_update on storage.objects to authenticated
  using (bucket_id = 'avatars' and (owner_id = (select auth.uid())::text or (select public.auth_is_admin())))
  with check (bucket_id = 'avatars' and (owner_id = (select auth.uid())::text or (select public.auth_is_admin())));
alter policy avatars_delete on storage.objects to authenticated
  using (bucket_id = 'avatars' and (owner_id = (select auth.uid())::text or (select public.auth_is_admin())));

alter policy covers_insert on storage.objects to authenticated;
alter policy covers_update on storage.objects to authenticated
  using (bucket_id = 'covers' and (owner_id = (select auth.uid())::text or (select public.auth_is_admin())))
  with check (bucket_id = 'covers' and (owner_id = (select auth.uid())::text or (select public.auth_is_admin())));
alter policy covers_delete on storage.objects to authenticated
  using (bucket_id = 'covers' and (owner_id = (select auth.uid())::text or (select public.auth_is_admin())));

alter policy posts_insert on storage.objects to authenticated;
alter policy posts_update on storage.objects to authenticated
  using (bucket_id = 'posts' and (owner_id = (select auth.uid())::text or (select public.auth_is_admin())))
  with check (bucket_id = 'posts' and (owner_id = (select auth.uid())::text or (select public.auth_is_admin())));
alter policy posts_delete on storage.objects to authenticated
  using (bucket_id = 'posts' and (owner_id = (select auth.uid())::text or (select public.auth_is_admin())));

alter policy products_insert on storage.objects to authenticated;
alter policy products_update on storage.objects to authenticated
  using (bucket_id = 'products' and (owner_id = (select auth.uid())::text or (select public.auth_is_admin())))
  with check (bucket_id = 'products' and (owner_id = (select auth.uid())::text or (select public.auth_is_admin())));
alter policy products_delete on storage.objects to authenticated
  using (bucket_id = 'products' and (owner_id = (select auth.uid())::text or (select public.auth_is_admin())));

alter policy profiles_insert on storage.objects to authenticated;
alter policy profiles_update on storage.objects to authenticated
  using (bucket_id = 'profiles' and (owner_id = (select auth.uid())::text or (select public.auth_is_admin())))
  with check (bucket_id = 'profiles' and (owner_id = (select auth.uid())::text or (select public.auth_is_admin())));
alter policy profiles_delete on storage.objects to authenticated
  using (bucket_id = 'profiles' and (owner_id = (select auth.uid())::text or (select public.auth_is_admin())));

alter policy public_insert on storage.objects to authenticated;
alter policy public_update on storage.objects to authenticated
  using (bucket_id = 'public' and (owner_id = (select auth.uid())::text or (select public.auth_is_admin())))
  with check (bucket_id = 'public' and (owner_id = (select auth.uid())::text or (select public.auth_is_admin())));
alter policy public_delete on storage.objects to authenticated
  using (bucket_id = 'public' and (owner_id = (select auth.uid())::text or (select public.auth_is_admin())));

alter policy shop_images_insert on storage.objects to authenticated;
alter policy shop_images_update on storage.objects to authenticated
  using (bucket_id = 'shop-images' and (owner_id = (select auth.uid())::text or (select public.auth_is_admin())))
  with check (bucket_id = 'shop-images' and (owner_id = (select auth.uid())::text or (select public.auth_is_admin())));
alter policy shop_images_delete on storage.objects to authenticated
  using (bucket_id = 'shop-images' and (owner_id = (select auth.uid())::text or (select public.auth_is_admin())));

alter policy user_reports_insert on storage.objects to authenticated;
alter policy user_reports_delete on storage.objects to authenticated
  using (bucket_id = 'user_reports' and (owner_id = (select auth.uid())::text or (select public.auth_is_admin())));

-- Aynı kovalardaki eş anlamlı geniş politikalar (yalnız auth.role() denetliyordu).
-- TO public idiler; koşulları zaten yalnız authenticated için doğruydu. Role
-- daraltılmazsa anon sorguları auth_is_admin() için "permission denied" alır.
alter policy "Users can update their avatars" on storage.objects to authenticated
  using (bucket_id = 'avatars' and auth.role() = 'authenticated' and (owner_id = (select auth.uid())::text or (select public.auth_is_admin())));
alter policy "Users can delete their avatars" on storage.objects to authenticated
  using (bucket_id = 'avatars' and auth.role() = 'authenticated' and (owner_id = (select auth.uid())::text or (select public.auth_is_admin())));
alter policy "Users can update their covers" on storage.objects to authenticated
  using (bucket_id = 'covers' and auth.role() = 'authenticated' and (owner_id = (select auth.uid())::text or (select public.auth_is_admin())));
alter policy "Users can delete their covers" on storage.objects to authenticated
  using (bucket_id = 'covers' and auth.role() = 'authenticated' and (owner_id = (select auth.uid())::text or (select public.auth_is_admin())));

-- Her oturum açmış kullanıcıya açık UPDATE/DELETE politikaları
alter policy stories_update_v2 on storage.objects
  using (bucket_id = 'stories' and (owner_id = (select auth.uid())::text or (select public.auth_is_admin())))
  with check (bucket_id = 'stories' and (owner_id = (select auth.uid())::text or (select public.auth_is_admin())));
alter policy stories_delete_v2 on storage.objects
  using (bucket_id = 'stories' and (owner_id = (select auth.uid())::text or (select public.auth_is_admin())));
alter policy news_images_update_v2 on storage.objects
  using (bucket_id = 'news-images' and (owner_id = (select auth.uid())::text or (select public.auth_is_admin())))
  with check (bucket_id = 'news-images' and (owner_id = (select auth.uid())::text or (select public.auth_is_admin())));
alter policy news_images_delete_v2 on storage.objects
  using (bucket_id = 'news-images' and (owner_id = (select auth.uid())::text or (select public.auth_is_admin())));
alter policy deals_delete on storage.objects
  using (bucket_id = 'deals' and (owner_id = (select auth.uid())::text or (select public.auth_is_admin())));

-- 2) Listeleme: geniş SELECT yerine "sahibi / kovanın yazma kuralı / admin".
-- Eski adlar ("public_read", "herkese açık") artık yanıltıcı olacağından politika
-- aynı işlem içinde düşürülüp yeni adla yaratılır (storage.objects üzerinde
-- ALTER POLICY ... RENAME yetkisi yok).
drop policy artist_music_public_read on storage.objects;
create policy artist_music_select_own_or_admin on storage.objects for select to authenticated
  using (bucket_id = 'artist-music' and (owner_id = (select auth.uid())::text or (storage.foldername(name))[1] = (select auth.uid())::text or (select public.is_admin())));
drop policy post_music_public_read on storage.objects;
create policy post_music_select_own_or_admin on storage.objects for select to authenticated
  using (bucket_id = 'post-music' and (owner_id = (select auth.uid())::text or (storage.foldername(name))[1] = (select auth.uid())::text or (select public.is_admin())));
drop policy avatars_select_public on storage.objects;
create policy avatars_select_own_or_admin on storage.objects for select to authenticated
  using (bucket_id = 'avatars' and (owner_id = (select auth.uid())::text or name like 'avatar_' || (select auth.uid())::text || '-%' or (select public.auth_is_admin())));
drop policy covers_select_public on storage.objects;
create policy covers_select_own_or_admin on storage.objects for select to authenticated
  using (bucket_id = 'covers' and (owner_id = (select auth.uid())::text or name like 'cover_' || (select auth.uid())::text || '-%' or (select public.auth_is_admin())));
drop policy ilan_storage_public_read on storage.objects;
create policy ilan_storage_select_own_or_admin on storage.objects for select to authenticated
  using (bucket_id = 'ilan-images' and (owner_id = (select auth.uid())::text or (storage.foldername(name))[1] = (select auth.uid())::text or (select public.ilan_is_admin())));
drop policy news_images_select_v2 on storage.objects;
create policy news_images_select_own_or_admin on storage.objects for select to authenticated
  using (bucket_id = 'news-images' and (owner_id = (select auth.uid())::text or (select public.auth_is_admin())));
drop policy stories_select_v2 on storage.objects;
create policy stories_select_own_or_admin on storage.objects for select to authenticated
  using (bucket_id = 'stories' and (owner_id = (select auth.uid())::text or (select public.auth_is_admin())));
drop policy okey_backgrounds_public_read on storage.objects;
create policy okey_backgrounds_select_own_or_admin on storage.objects for select to authenticated
  using (bucket_id = 'okey-backgrounds' and (owner_id = (select auth.uid())::text or (select public.is_admin())));
drop policy okey_bot_avatars_public_read on storage.objects;
create policy okey_bot_avatars_select_own_or_admin on storage.objects for select to authenticated
  using (bucket_id = 'okey-bot-avatars' and (owner_id = (select auth.uid())::text or (select public.is_admin())));
drop policy okey_sounds_public_read on storage.objects;
create policy okey_sounds_select_own_or_admin on storage.objects for select to authenticated
  using (bucket_id = 'okey-sounds' and (owner_id = (select auth.uid())::text or (select public.is_admin())));
drop policy promo_media_public_read on storage.objects;
create policy promo_media_select_own_or_admin on storage.objects for select to authenticated
  using (bucket_id = 'promo-media' and (owner_id = (select auth.uid())::text or (select public.is_admin())));
drop policy "Profil arka planları herkese açık" on storage.objects;
create policy profile_backgrounds_select_own_or_admin on storage.objects for select to authenticated
  using (bucket_id = 'profile-backgrounds' and (owner_id = (select auth.uid())::text or (select public.auth_is_admin())));
drop policy "Ürün görsel kütüphanesi herkese açık" on storage.objects;
create policy product_image_presets_select_own_or_admin on storage.objects for select to authenticated
  using (bucket_id = 'product-image-presets' and (owner_id = (select auth.uid())::text or (select public.auth_is_admin())));
drop policy "Şehiriçi ikonları herkese açık" on storage.objects;
create policy sehirici_icons_select_own_or_admin on storage.objects for select to authenticated
  using (bucket_id = 'sehirici-icons' and (owner_id = (select auth.uid())::text or (select public.auth_is_admin())));

-- Son durum denetimi: beklenmeyen bir durum varsa göç tümüyle geri alınır.
do $$
declare
  v_bad text;
begin
  -- anon'a yazma izni veren, yalnız bucket_id koşullu politika kalmamalı
  select string_agg(pol.policyname, ', ')
    into v_bad
    from pg_policies pol
   where pol.schemaname = 'storage' and pol.tablename = 'objects'
     and pol.cmd in ('INSERT', 'UPDATE', 'DELETE')
     and pol.roles && array['anon', 'public']::name[]
     and coalesce(pol.qual, pol.with_check) !~ 'auth\.(uid|role)\(\)';
  if v_bad is not null then
    raise exception 'storage hardening: anon yazma politikası kaldı: %', v_bad;
  end if;

  -- herkese açık kovada yalnız bucket_id koşullu SELECT/ALL politikası kalmamalı
  select string_agg(pol.policyname, ', ')
    into v_bad
    from pg_policies pol
    join storage.buckets b on b.public
   where pol.schemaname = 'storage' and pol.tablename = 'objects'
     and pol.cmd in ('SELECT', 'ALL')
     and pol.permissive = 'PERMISSIVE'
     and regexp_replace(lower(pol.qual), '[\s()]|::text', '', 'g') = 'bucket_id=''' || lower(b.id) || '''';
  if v_bad is not null then
    raise exception 'storage hardening: geniş SELECT politikası kaldı: %', v_bad;
  end if;
end;
$$;

commit;
