-- =============================================================================
-- Favori dükkânlar + ürün yorumu düzeltmeleri (2026-10-24)
--
-- 1) Favori dükkânlar: mevcut ama hiç kullanılmayan shop_subscribers tablosu
--    (0 satır, hiçbir fonksiyon okumuyor; unique(shop_id,user_id) ve yalnız
--    kendi satırı RLS'i hazır) favori listesi olarak kullanılır; sütunlar
--    NOT NULL yapılır.
-- 2) Ürün puanı HİÇ güncellenmiyordu: update_product_rating_on_review_change
--    INVOKER'dı → müşterinin yorumu products UPDATE RLS'ine takılıyor, 0 satır
--    güncelleniyordu (canlıda 2 üründe 5 yıldızlı yorum varken puan 0). DEFINER
--    yapılır ve tüm puanlar yeniden hesaplanır.
-- 3) "Yararlı" sayacı başkasının oyunda artmıyordu (update_helpful_count_on_vote
--    INVOKER, istemcinin _updateHelpfulCount yazımı da RLS'e takılıyordu) →
--    DEFINER + yeniden hesaplama. Kendi yorumuna oy verilemez.
-- 4) Yorum sahibi kendi satırında seller_reply / helpful_count / is_approved
--    yazabiliyordu → INVOKER koruma tetikleyicisi.
-- 5) Satıcı cevabı: satıcının UPDATE yetkisi yoktu (addSellerReply sessizce
--    başarısızdı) → seller_reply_product_review DEFINER RPC (dükkân sahibi /
--    admin), yorum sahibine 'product_review_reply' bildirimi.
-- =============================================================================

begin;

set local lock_timeout = '10s';

-- -----------------------------------------------------------------------------
-- 1) Favori dükkânlar
-- -----------------------------------------------------------------------------
delete from public.shop_subscribers where shop_id is null or user_id is null;
alter table public.shop_subscribers alter column shop_id set not null;
alter table public.shop_subscribers alter column user_id set not null;
alter table public.shop_subscribers alter column created_at set default now();

comment on table public.shop_subscribers is
  'Kullanıcının favori dükkânları (Favoriler > Dükkânlar). Yalnız kendi satırları.';

-- -----------------------------------------------------------------------------
-- 2) Ürün puanı tetikleyicisi DEFINER + yeniden hesaplama
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.update_product_rating_on_review_change()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    avg_rating FLOAT;
    total_count INTEGER;
    target_product_id UUID;
BEGIN
    IF TG_OP = 'DELETE' THEN
        target_product_id := OLD.product_id;
    ELSE
        target_product_id := NEW.product_id;
    END IF;

    SELECT COALESCE(AVG(rating), 0.0), COUNT(*)
    INTO avg_rating, total_count
    FROM public.product_reviews
    WHERE product_id = target_product_id
      AND is_approved = true;

    UPDATE public.products
    SET rating = avg_rating,
        total_reviews = total_count
    WHERE id = target_product_id;

    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    ELSE
        RETURN NEW;
    END IF;
END;
$function$;

update public.products p
   set rating = coalesce(s.avg_rating, 0), total_reviews = coalesce(s.n, 0)
  from (
    select r.product_id, avg(r.rating) as avg_rating, count(*) as n
    from public.product_reviews r
    where r.is_approved = true
    group by r.product_id
  ) s
 where s.product_id = p.id
   and (p.rating is distinct from s.avg_rating or p.total_reviews is distinct from s.n);

-- -----------------------------------------------------------------------------
-- 3) "Yararlı" sayacı DEFINER + yeniden hesaplama; kendi yorumuna oy yok
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.update_helpful_count_on_vote()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
    IF TG_OP = 'INSERT' THEN
        UPDATE public.product_reviews
        SET helpful_count = helpful_count + 1
        WHERE id = NEW.review_id;
        RETURN NEW;
    ELSIF TG_OP = 'DELETE' THEN
        UPDATE public.product_reviews
        SET helpful_count = GREATEST(helpful_count - 1, 0)
        WHERE id = OLD.review_id;
        RETURN OLD;
    END IF;
    RETURN NULL;
END;
$function$;

update public.product_reviews r
   set helpful_count = (select count(*) from public.product_review_helpful h where h.review_id = r.id)
 where r.helpful_count is distinct from
       (select count(*) from public.product_review_helpful h where h.review_id = r.id);

drop policy if exists "Kullanıcılar faydalı oyu verebilir" on public.product_review_helpful;
create policy "Kullanıcılar faydalı oyu verebilir" on public.product_review_helpful
  for insert to authenticated
  with check (
    user_id = (select auth.uid())
    and not exists (
      select 1 from public.product_reviews r
      where r.id = review_id and r.user_id = (select auth.uid())
    )
  );

-- -----------------------------------------------------------------------------
-- 4) Yorum sütun koruması (INVOKER; DEFINER tetikleyici/RPC'ler serbest)
-- -----------------------------------------------------------------------------
create or replace function public.guard_product_reviews_client_write()
returns trigger
language plpgsql
set search_path = ''
as $fn$
begin
  if current_user not in ('authenticated', 'anon') or public.auth_is_admin() then
    return NEW;
  end if;

  if TG_OP = 'INSERT' then
    NEW.seller_reply      := null;
    NEW.seller_replied_at := null;
    NEW.helpful_count     := 0;
  else
    NEW.seller_reply      := OLD.seller_reply;
    NEW.seller_replied_at := OLD.seller_replied_at;
    NEW.helpful_count     := OLD.helpful_count;
    NEW.is_approved       := OLD.is_approved;
    NEW.product_id        := OLD.product_id;
    NEW.user_id           := OLD.user_id;
    NEW.order_id          := OLD.order_id;
    NEW.created_at        := OLD.created_at;
  end if;
  return NEW;
end;
$fn$;

drop trigger if exists a_product_reviews_guard_client_write on public.product_reviews;
create trigger a_product_reviews_guard_client_write
  before insert or update on public.product_reviews
  for each row execute function public.guard_product_reviews_client_write();

-- -----------------------------------------------------------------------------
-- 5) Satıcı cevabı (boş metin = cevabı sil)
-- -----------------------------------------------------------------------------
create or replace function public.seller_reply_product_review(p_review_id uuid, p_reply text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $fn$
declare
  v_uid    uuid := auth.uid();
  v_reply  text := nullif(btrim(coalesce(p_reply, '')), '');
  v_review public.product_reviews%rowtype;
  v_shop   record;
begin
  if v_uid is null then
    raise exception 'Oturum açmanız gerekiyor' using errcode = '42501';
  end if;
  if v_reply is not null and char_length(v_reply) > 1000 then
    raise exception 'Cevap en fazla 1000 karakter olabilir' using errcode = '22000';
  end if;

  select * into v_review from public.product_reviews where id = p_review_id for update;
  if not found then
    raise exception 'Yorum bulunamadı' using errcode = 'P0002';
  end if;

  select s.id, s.owner_id, s.name, s.logo_url
    into v_shop
  from public.products p
  join public.shops s on s.id = p.shop_id
  where p.id = v_review.product_id;

  if v_shop.owner_id is distinct from v_uid and not public.auth_is_admin() then
    raise exception 'Yalnız dükkân sahibi cevap verebilir' using errcode = '42501';
  end if;

  update public.product_reviews
     set seller_reply      = v_reply,
         seller_replied_at = case when v_reply is null then null else now() end
   where id = p_review_id
  returning * into v_review;

  -- Yeni / değişen cevap: yorum sahibine bildirim (kendi dükkânına yorumsa yok).
  if v_reply is not null and v_review.user_id is distinct from v_uid then
    begin
      insert into public.notifications (
        user_id, type, title, content, actor_id, actor_name, actor_avatar,
        entity_id, metadata, is_read, created_at
      ) values (
        v_review.user_id, 'product_review_reply',
        coalesce(v_shop.name, 'Satıcı') || ' yorumuna cevap verdi',
        left(v_reply, 160),
        v_uid, v_shop.name, v_shop.logo_url,
        v_review.product_id::text,
        jsonb_build_object('review_id', v_review.id, 'shop_id', v_shop.id),
        false, now()
      );
    exception when others then
      raise warning 'seller_reply_product_review bildirim: % (%)', SQLERRM, SQLSTATE;
    end;
  end if;

  return to_jsonb(v_review);
end;
$fn$;

revoke all on function public.seller_reply_product_review(uuid, text) from public, anon;
grant execute on function public.seller_reply_product_review(uuid, text) to authenticated;

commit;

notify pgrst, 'reload schema';
