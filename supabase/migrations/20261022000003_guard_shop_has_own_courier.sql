-- =============================================================================
-- Dükkan kurye modeli satıcıya kapalı (2026-10-22)
--
-- shops.has_own_courier müşteriye dükkan kartında/sayfasında "Kendi kuryesi" /
-- "CizreApp kuryesi" rozeti olarak gösteriliyor ve teslimat para akışını
-- (komisyon, teslimat ücreti kimin) belirliyor. Satıcı ayar ekranı bu alanı
-- salt-okunur gösteriyordu ama veritabanı satıcının yazmasını engellemiyordu.
-- Artık guard_shop_financial_columns (INVOKER) satıcı yazımını sessizce eski
-- değere döndürür; admin ve sunucu bağlamı (kurye talebi onayı, admin paneli)
-- serbesttir. Gövde canlı tanımdan türetildi; yalnız işaretli satırlar eklendi.
-- =============================================================================

begin;

set local lock_timeout = '10s';

CREATE OR REPLACE FUNCTION public.guard_shop_financial_columns()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare
  -- Değişirse hata verilen finans sütunları. to_jsonb ile karşılaştırılıyor ki
  -- bir ortamda sütun yoksa fonksiyon patlamasın.
  c_protected constant text[] := array[
    'admin_credit',
    'commission_debt',
    'commission_rate',
    'digital_commission_rate',
    'total_paid',
    'pending_payout',
    'cash_payment_revenue',
    'online_payment_revenue',
    'total_collected_cash'
  ];
  v_old_row jsonb;
  v_new_row jsonb;
  v_col     text;
  v_changed text[] := '{}';
begin
  -- Sunucu bağlamı: SECURITY DEFINER RPC/tetikleyiciler (current_user = sahip)
  -- ve service_role serbest. Fonksiyon INVOKER olduğu için bu kontrol artık
  -- istemciden gelen yazımda gerçekten 'authenticated' görür.
  if current_user not in ('authenticated', 'anon') then
    return new;
  end if;

  -- Admin serbest (admin paneli bu sütunları doğrudan düzenliyor).
  if public.auth_is_admin() then
    return new;
  end if;

  -- Moderasyon / istatistik sütunları: sessizce eski değer. Hata yerine geri
  -- alma, bayat tam-satır yazımlarının (ör. puan arada değişti) kaydı
  -- kırmasını önler.
  new.owner_id          := old.owner_id;
  new.is_approved       := old.is_approved;
  new.is_verified       := old.is_verified;
  new.is_pinned         := old.is_pinned;
  new.is_active         := old.is_active;
  new.rating            := old.rating;
  new.review_count      := old.review_count;
  new.total_reviews     := old.total_reviews;
  new.total_orders      := old.total_orders;
  new.total_paid_amount := old.total_paid_amount;
  new.paid_at           := old.paid_at;
  -- Randevulu sipariş: dükkan bazlı yönetici engeli yalnız admin değiştirir.
  new.scheduled_orders_admin_blocked := old.scheduled_orders_admin_blocked;
  -- Kurye modeli müşteriye rozet olarak gösteriliyor ("Kendi kuryesi" /
  -- "CizreApp kuryesi") ve para akışını belirliyor: yalnız admin değiştirir
  -- (kurye talebi onayı, admin paneli). Satıcı yazarsa sessizce eski değer.
  new.has_own_courier := old.has_own_courier;

  v_old_row := to_jsonb(old);
  v_new_row := to_jsonb(new);

  foreach v_col in array c_protected loop
    if v_new_row ? v_col
       and (v_new_row -> v_col) is distinct from (v_old_row -> v_col) then
      v_changed := v_changed || v_col;
    end if;
  end loop;

  if array_length(v_changed, 1) > 0 then
    raise exception
      'Magaza finansal alanlari satici tarafindan degistirilemez: %',
      array_to_string(v_changed, ', ')
      using errcode = '42501';
  end if;

  return new;
end;
$function$;

commit;
