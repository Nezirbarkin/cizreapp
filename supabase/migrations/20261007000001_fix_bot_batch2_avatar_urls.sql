-- =============================================================================
-- 20261007000001_fix_bot_batch2_avatar_urls.sql
-- -----------------------------------------------------------------------------
-- Admin > Loglar > "Son Hatalar"daki açık ara en sık kayıt (30 günde 66 kez,
-- 13 farklı kullanıcı, hâlâ sürüyordu):
--   FlutterError: HTTP request failed, statusCode: 400,
--   .../storage/v1/object/public/avatars/_bot_avatars_batch2/avatar_char_NN.png
--
-- NEDEN: 20260922000001_bot_showcase_accounts_batch2.sql avatar dosyalarını
-- storage'a `_bot_avatars_batch2/<kullanıcı_adı>.png` adıyla yükledi, ama
-- profillere `_bot_avatars_batch2/avatar_char_NN.png` adresini yazdı. O
-- nesneler hiç var olmadı; Supabase Storage olmayan nesne için 400 döner ve
-- her bot avatarı çizilmeye çalışıldığında istemci hata kaydı düşüyordu. 50
-- botun 37'si hâlâ kırık adresteydi (kalan 13'ünün avatarı sonradan admin
-- panelinden değiştirilmiş). Doğrulandı: `<kullanıcı_adı>.png` 200/image/png,
-- `avatar_char_NN.png` 400 döner; dosya içerikleri göçteki eşlemeyle uyumlu.
--
-- DÜZELTME: kırık adres, aynı botun storage'da GERÇEKTEN var olan
-- `<kullanıcı_adı>.png` nesnesine çevrilir. Adresin kopyalandığı iki yer de
-- tazelenir:
--   * okey_bot_profiles.avatar_url — profiles'tan aynalanır, ama o senkron
--     (okey_internal_sync_bot_account_profiles) yalnız bir bot masaya
--     oturunca çalışır;
--   * notifications.actor_avatar — bildirim anındaki avatarın kopyası; bot
--     artık başka bir fotoğraf kullanıyorsa (13 bot) güncel avatarı alır.
--
-- Yan etki yok: trg_user_activity botlar için kayıt yazmaz
-- (private.log_user_activity is_bot'ta çıkar). Yalnız nesnesi bulunan
-- satırlar değişir; idempotent (ikinci çalıştırmada 0 satır).
-- =============================================================================

begin;

-- 1) Bot profilleri: kırık adres -> storage'da var olan <kullanıcı_adı>.png
update public.profiles as p
set avatar_url =
      'https://xsbukxkgtmdyickknqzf.supabase.co/storage/v1/object/public/avatars/_bot_avatars_batch2/'
      || p.username || '.png'
where p.is_bot
  and p.avatar_url like '%/avatars/\_bot\_avatars\_batch2/avatar\_char\_%'
  and exists (
    select 1
    from storage.objects as o
    where o.bucket_id = 'avatars'
      and o.name = '_bot_avatars_batch2/' || p.username || '.png'
  );

-- 2) Okey bot kimlikleri: bağlı bot hesabının (artık düzelmiş) avatarı
update public.okey_bot_profiles as bp
set avatar_url = nullif(btrim(coalesce(p.avatar_url, '')), '')
from public.profiles as p
where bp.bot_account_id = p.id
  and bp.avatar_url like '%/avatars/\_bot\_avatars\_batch2/avatar\_char\_%'
  and bp.avatar_url is distinct from nullif(btrim(coalesce(p.avatar_url, '')), '');

-- 3) Bildirimlerdeki avatar kopyası: eylemi yapan botun güncel avatarı
update public.notifications as n
set actor_avatar = p.avatar_url
from public.profiles as p
where n.actor_id = p.id
  and n.actor_avatar like '%/avatars/\_bot\_avatars\_batch2/avatar\_char\_%'
  and p.avatar_url is not null
  and p.avatar_url not like '%/avatars/\_bot\_avatars\_batch2/avatar\_char\_%';

commit;
