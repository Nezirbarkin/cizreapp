-- =============================================================================
-- Ücretsiz profil özelliği sayısını 2 ile sınırla
-- =============================================================================
-- 20260819000001 katalogdaki ücretsiz (is_user_claimable) satır sayısını 2'ye
-- indirdi. Ancak admin panelindeki "Kullanıcı talebine aç" anahtarı
-- (admin_set_profile_feature_claimable) sınırsız satırı ücretsiz yapabiliyor —
-- yani kural tek seferlik bir veri düzeltmesi olarak kalıyor, değişmez bir
-- kısıt değil.
--
-- Bu migration kuralı fonksiyonun içine taşır: 3. satırı ücretsiz yapma
-- girişimi net bir hata ile reddedilir. Admin hâlâ HANGİ 2 özelliğin ücretsiz
-- olacağını seçebilir (önce birini kapat, sonra diğerini aç).
--
-- Neden CHECK constraint değil: kısıt tablo genelinde bir sayıma bakıyor;
-- satır-bazlı CHECK bunu ifade edemez. Trigger da olurdu ama tek yazma yolu
-- zaten bu SECURITY DEFINER fonksiyonu (tabloya doğrudan yazma yetkisi
-- authenticated'da yok), dolayısıyla kontrolü burada tutmak hem yeterli hem
-- daha anlaşılır bir hata mesajı veriyor.
-- =============================================================================

begin;

create or replace function public.admin_set_profile_feature_claimable(
  p_feature_id uuid,
  p_claimable boolean,
  p_duration_days integer default null
)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_kind text;
  v_already boolean;
  v_free_count integer;
begin
  if not private.current_user_is_admin() then
    raise exception 'admin_set_profile_feature_claimable: not admin'
      using errcode = '42501';
  end if;

  select c.kind, coalesce(c.is_user_claimable, false)
  into v_kind, v_already
  from public.profile_feature_catalog c
  where c.id = p_feature_id;

  if not found then
    raise exception 'Özellik bulunamadı' using errcode = 'P0002';
  end if;

  if coalesce(p_claimable, false) then
    if v_kind = 'badge' then
      raise exception 'Rozet ve tikler ücretsiz olarak açılamaz'
        using errcode = '42501';
    end if;

    -- Zaten ücretsizse sayacı artırmıyor; yalnız yeni ekleme sınıra takılır.
    if not v_already then
      select count(*)::integer into v_free_count
      from public.profile_feature_catalog
      where is_user_claimable = true;

      if v_free_count >= 2 then
        raise exception
          'En fazla 2 ücretsiz özellik olabilir. Önce mevcut ücretsiz özelliklerden birini kapat.'
          using errcode = '23514';
      end if;
    end if;
  end if;

  update public.profile_feature_catalog
  set is_user_claimable = coalesce(p_claimable, false),
      -- Ücretsiz özellik varsayılan olarak SÜRESİZDİR (bkz. 20260819000001);
      -- admin yine de açıkça bir süre verirse ona uyulur.
      claim_duration_days = case
        when coalesce(p_claimable, false) then p_duration_days
        else null end,
      -- Ücretsiz yapılan satırın sipariş eşiği ve puan fiyatı kalkar;
      -- ücretsizlikten çıkarılan satır ise fiyatsız/eşiksiz kalmasın diye
      -- admin tarafından yeniden fiyatlandırılmalıdır.
      unlock_after_orders = case
        when coalesce(p_claimable, false) then null
        else unlock_after_orders end,
      points_price_monthly = case
        when coalesce(p_claimable, false) then null
        else points_price_monthly end,
      points_price_yearly = case
        when coalesce(p_claimable, false) then null
        else points_price_yearly end,
      updated_at = now()
  where id = p_feature_id;
end;
$$;

revoke all on function public.admin_set_profile_feature_claimable(uuid, boolean, integer) from public;
grant execute on function public.admin_set_profile_feature_claimable(uuid, boolean, integer)
  to authenticated, service_role;

commit;

-- Kontrol:
--   select count(*) from public.profile_feature_catalog where is_user_claimable;
--   -- Beklenen: 2 (ve 3.'yü açma girişimi 23514 ile reddedilmeli)
