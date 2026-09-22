-- İstemci (post_service.dart) created_at'i DateTime.now().toIso8601String() ile
-- (offset'siz, cihaz yerel saati) gönderiyordu; PostgREST oturumu UTC olduğu için
-- Postgres bu değeri UTC sanıp kaydediyordu. Sonuç: gerçek (bot olmayan) gönderi/
-- beğeni/yorum kayıtları gerçek ana göre 3 saat ileri (Europe/Istanbul = UTC+3)
-- kaymış durumda saklanmıştı. Bot gönderileri sunucu tarafında (.toUtc()/now())
-- zaten doğru yazılıyordu; hata yalnızca uygulama kodundaki bu dört insert'teydi.
--
-- Uygulama kodu düzeltildi (created_at artık gönderilmiyor, DEFAULT now()
-- kullanılıyor + ekran tarafı .toLocal() ile gösteriyor). Bu göç sadece daha
-- önce hatalı yazılmış geçmiş satırları düzeltir: bot_accounts'taki hesaplar
-- hariç, created_at'ten 3 saat çıkarılır. Geri alınabilir: interval'i '+3 hours'
-- yaparak tekrar çalıştırmak eski hâline döndürür.

update public.posts p
set created_at = p.created_at - interval '3 hours'
where not exists (
  select 1 from public.bot_accounts ba where ba.id = p.user_id
);

update public.post_likes pl
set created_at = pl.created_at - interval '3 hours'
where not exists (
  select 1 from public.bot_accounts ba where ba.id = pl.user_id
);

update public.post_comments pc
set created_at = pc.created_at - interval '3 hours'
where not exists (
  select 1 from public.bot_accounts ba where ba.id = pc.user_id
);
