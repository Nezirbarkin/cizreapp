-- use_coupon: çağıran kimlik denetimi.
--
-- Fonksiyon p_user_id'yi istemciden alıyor ve yalnızca siparişin sahibiyle
-- karşılaştırıyordu; auth.uid() hiç denetlenmiyordu. Oturum açmış herhangi bir
-- kullanıcı, başkasının sipariş ve kullanıcı kimliğini bilirse onun adına kupon
-- kullanımı yazıp kuponun usage_count değerini şişirebiliyordu.
--
-- Tek değişiklik gövdenin başına eklenen denetimdir; geri kalan satırlar canlı
-- tanımla birebir aynıdır. İstemcinin bütün sürümleri (git geçmişindeki üç
-- ödeme ekranı dahil) p_user_id olarak auth.currentUser.id gönderir; veritabanı
-- içinden ya da edge function'lardan çağıran yoktur. Yetkiler değişmez
-- (CREATE OR REPLACE mevcut ACL'yi korur): authenticated + service_role.

begin;

-- Canlıdaki gövde bu göçün dayandığı sürüm değilse (başka bir oturum
-- değiştirdiyse) üzerine yazma.
do $$
declare
  v_md5 text;
begin
  select md5(p.prosrc) into v_md5
    from pg_proc p
   where p.oid = 'public.use_coupon(uuid,uuid,uuid,numeric)'::regprocedure;
  if v_md5 not in ('f46990528d6492a7288638c71793a2e2', '98ae64fe72948d925bde274e084e57fa') then
    raise exception 'use_coupon gövdesi beklenenden farklı (md5 %); göç uygulanmadı', v_md5;
  end if;
end;
$$;

CREATE OR REPLACE FUNCTION public.use_coupon(p_coupon_id uuid, p_order_id uuid, p_user_id uuid, p_discount_amount numeric)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_coupon RECORD;
    v_order RECORD;
    v_user_usage_count INT;
    v_computed_discount NUMERIC;
BEGIN
    -- Çağıran yalnızca kendi adına kupon kullanabilir. auth.uid() NULL ise
    -- çağıran service_role/postgres'tir (anon ve PUBLIC yetkisi yok).
    IF auth.uid() IS NOT NULL AND p_user_id IS DISTINCT FROM auth.uid() THEN
        RAISE EXCEPTION 'Yetkisiz işlem' USING ERRCODE = '42501';
    END IF;

    SELECT * INTO v_coupon FROM public.shop_coupons WHERE id = p_coupon_id FOR UPDATE;

    IF v_coupon.id IS NULL OR v_coupon.is_active = false THEN
        RAISE EXCEPTION 'Kupon artık geçerli değil';
    END IF;

    SELECT id, shop_id, subtotal, user_id INTO v_order
    FROM public.orders WHERE id = p_order_id;

    IF v_order.id IS NULL THEN
        RAISE EXCEPTION 'Sipariş bulunamadı';
    END IF;

    IF v_order.user_id != p_user_id THEN
        RAISE EXCEPTION 'Yetkisiz işlem';
    END IF;

    IF v_order.shop_id != v_coupon.shop_id THEN
        RAISE EXCEPTION 'Kupon bu siparişin mağazasına ait değil';
    END IF;

    IF v_coupon.usage_limit IS NOT NULL AND v_coupon.usage_count >= v_coupon.usage_limit THEN
        RAISE EXCEPTION 'Bu kuponun kullanım limiti doldu';
    END IF;

    IF v_coupon.usage_per_user IS NOT NULL THEN
        SELECT count(*) INTO v_user_usage_count FROM public.coupon_usages
        WHERE coupon_id = p_coupon_id AND user_id = p_user_id;

        IF v_user_usage_count >= v_coupon.usage_per_user THEN
            RAISE EXCEPTION 'Bu kuponu daha önce kullandınız';
        END IF;
    END IF;

    -- İndirimi istemciden gelen p_discount_amount'a güvenmeden sunucuda
    -- yeniden hesapla (Dart AppliedCoupon.discountFor ile birebir aynı mantık).
    IF v_coupon.discount_type = 'percentage' THEN
        v_computed_discount := v_order.subtotal * (v_coupon.discount_value / 100.0);
        IF v_coupon.maximum_discount_amount IS NOT NULL AND v_computed_discount > v_coupon.maximum_discount_amount THEN
            v_computed_discount := v_coupon.maximum_discount_amount;
        END IF;
    ELSE
        v_computed_discount := v_coupon.discount_value;
    END IF;

    IF v_computed_discount > v_order.subtotal THEN
        v_computed_discount := v_order.subtotal;
    END IF;
    IF v_computed_discount < 0 THEN
        v_computed_discount := 0;
    END IF;

    INSERT INTO public.coupon_usages (coupon_id, order_id, user_id, discount_amount)
    VALUES (p_coupon_id, p_order_id, p_user_id, v_computed_discount);

    UPDATE public.shop_coupons SET usage_count = usage_count + 1 WHERE id = p_coupon_id;
END;
$function$;

-- CREATE OR REPLACE yetkileri korur; yine de son durumu doğrula.
do $$
declare
  v_oid oid := 'public.use_coupon(uuid,uuid,uuid,numeric)'::regprocedure;
begin
  if has_function_privilege('anon', v_oid, 'EXECUTE')
     or not has_function_privilege('authenticated', v_oid, 'EXECUTE')
     or not has_function_privilege('service_role', v_oid, 'EXECUTE') then
    raise exception 'use_coupon: beklenmeyen yetki durumu';
  end if;
end;
$$;

commit;

notify pgrst, 'reload schema';
