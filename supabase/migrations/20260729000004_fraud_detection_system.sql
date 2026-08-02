-- CizreApp dolandırıcılık sinyali ve admin inceleme sistemi.
-- Sinyaller karar değil, insan incelemesine yardımcı olan risk göstergeleridir.

create table if not exists public.fraud_signals (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  signal_type text not null check (signal_type in (
    'multiple_accounts', 'unusual_returns', 'coupon_abuse', 'fake_reviews'
  )),
  severity text not null check (severity in ('low', 'medium', 'high', 'critical')),
  risk_score integer not null check (risk_score between 0 and 100),
  status text not null default 'open' check (status in (
    'open', 'reviewing', 'confirmed', 'dismissed'
  )),
  title text not null,
  description text not null,
  evidence jsonb not null default '{}'::jsonb,
  fingerprint text not null,
  first_detected_at timestamptz not null default now(),
  last_detected_at timestamptz not null default now(),
  occurrence_count integer not null default 1 check (occurrence_count > 0),
  reviewed_by uuid references public.profiles(id) on delete set null,
  reviewed_at timestamptz,
  admin_note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, signal_type, fingerprint)
);

create index if not exists idx_fraud_signals_status_score
  on public.fraud_signals (status, risk_score desc, last_detected_at desc);
create index if not exists idx_fraud_signals_user
  on public.fraud_signals (user_id, last_detected_at desc);
create index if not exists idx_fraud_signals_type
  on public.fraud_signals (signal_type, last_detected_at desc);

alter table public.fraud_signals enable row level security;

-- Tabloya doğrudan erişim yoktur; yalnızca rol kontrolü yapan RPC'ler kullanılır.
revoke all on table public.fraud_signals from anon, authenticated;

create or replace function public.is_fraud_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.profiles p
    where p.id = (select auth.uid()) and p.role = 'admin'
  );
$$;

revoke all on function public.is_fraud_admin() from public;
grant execute on function public.is_fraud_admin() to authenticated;

create or replace function public.upsert_fraud_signal(
  p_user_id uuid,
  p_signal_type text,
  p_severity text,
  p_risk_score integer,
  p_title text,
  p_description text,
  p_evidence jsonb,
  p_fingerprint text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.fraud_signals (
    user_id, signal_type, severity, risk_score, title, description,
    evidence, fingerprint
  ) values (
    p_user_id, p_signal_type, p_severity, p_risk_score, p_title,
    p_description, coalesce(p_evidence, '{}'::jsonb), p_fingerprint
  )
  on conflict (user_id, signal_type, fingerprint) do update set
    severity = excluded.severity,
    risk_score = greatest(public.fraud_signals.risk_score, excluded.risk_score),
    title = excluded.title,
    description = excluded.description,
    evidence = excluded.evidence,
    last_detected_at = now(),
    occurrence_count = public.fraud_signals.occurrence_count + 1,
    updated_at = now(),
    status = case
      when public.fraud_signals.status = 'dismissed' then 'open'
      else public.fraud_signals.status
    end;
end;
$$;

revoke all on function public.upsert_fraud_signal(uuid,text,text,integer,text,text,jsonb,text) from public;

create or replace function public.admin_scan_fraud_signals()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_detected integer := 0;
  v_row record;
begin
  if not public.is_fraud_admin() then
    raise exception 'Yetkiniz yok' using errcode = '42501';
  end if;

  -- 1) Aynı normalize telefon numarasını kullanan birden fazla profil.
  for v_row in
    with normalized as (
      select id, regexp_replace(coalesce(phone, ''), '\D', '', 'g') phone_key
      from public.profiles
    ), shared as (
      select phone_key, count(*) account_count, array_agg(id) account_ids
      from normalized
      where length(phone_key) >= 10
      group by phone_key
      having count(*) >= 2
    )
    select n.id user_id, s.phone_key, s.account_count, s.account_ids
    from normalized n join shared s using (phone_key)
  loop
    perform public.upsert_fraud_signal(
      v_row.user_id, 'multiple_accounts',
      case when v_row.account_count >= 4 then 'critical' when v_row.account_count = 3 then 'high' else 'medium' end,
      least(100, 40 + (v_row.account_count * 15)),
      'Aynı telefonla birden fazla hesap',
      format('Aynı telefon numarası %s farklı hesapta kullanılıyor.', v_row.account_count),
      jsonb_build_object('account_count', v_row.account_count, 'related_user_ids', v_row.account_ids),
      'phone:' || encode(digest(v_row.phone_key, 'sha256'), 'hex')
    );
    v_detected := v_detected + 1;
  end loop;

  -- 2) Son 90 günde en az 3 iade ve teslim edilmiş siparişlere göre yüksek oran.
  for v_row in
    with returns as (
      select user_id, count(*) return_count,
             count(*) filter (where status in ('approved', 'completed')) approved_count
      from public.return_requests
      where created_at >= now() - interval '90 days'
      group by user_id
    ), orders_90 as (
      select user_id, count(*) delivered_count
      from public.orders
      where created_at >= now() - interval '90 days' and status = 'delivered'
      group by user_id
    )
    select r.user_id, r.return_count, r.approved_count,
           coalesce(o.delivered_count, 0) delivered_count,
           r.return_count::numeric / greatest(coalesce(o.delivered_count, 0), 1) return_ratio
    from returns r left join orders_90 o using (user_id)
    where r.return_count >= 3
      and r.return_count::numeric / greatest(coalesce(o.delivered_count, 0), 1) >= 0.50
  loop
    perform public.upsert_fraud_signal(
      v_row.user_id, 'unusual_returns',
      case when v_row.return_ratio >= 0.80 or v_row.return_count >= 6 then 'high' else 'medium' end,
      least(100, 35 + (v_row.return_count * 7) + round(v_row.return_ratio * 20)::integer),
      'Sıra dışı iade davranışı',
      format('Son 90 günde %s iade; teslim edilen siparişlere oranı %s%%.',
        v_row.return_count, round(v_row.return_ratio * 100)),
      jsonb_build_object('window_days', 90, 'return_count', v_row.return_count,
        'approved_count', v_row.approved_count, 'delivered_count', v_row.delivered_count,
        'return_ratio', round(v_row.return_ratio, 3)),
      'returns:rolling-90d'
    );
    v_detected := v_detected + 1;
  end loop;

  -- 3) Kısa sürede yoğun kupon kullanımı veya indirimin sipariş tutarına aşırı yaklaşması.
  for v_row in
    select cu.user_id, count(*) usage_count,
           count(distinct cu.coupon_id) distinct_coupon_count,
           coalesce(sum(cu.discount_amount), 0) total_discount
    from public.coupon_usages cu
    where cu.used_at >= now() - interval '7 days'
    group by cu.user_id
    having count(*) >= 5 or coalesce(sum(cu.discount_amount), 0) >= 1000
  loop
    perform public.upsert_fraud_signal(
      v_row.user_id, 'coupon_abuse',
      case when v_row.usage_count >= 10 or v_row.total_discount >= 2500 then 'high' else 'medium' end,
      least(100, 30 + (v_row.usage_count * 5) + least(25, floor(v_row.total_discount / 100)::integer)),
      'Olağan dışı kupon kullanımı',
      format('Son 7 günde %s kupon kullanımı ve %s TL indirim tespit edildi.',
        v_row.usage_count, round(v_row.total_discount, 2)),
      jsonb_build_object('window_days', 7, 'usage_count', v_row.usage_count,
        'distinct_coupon_count', v_row.distinct_coupon_count,
        'total_discount', v_row.total_discount),
      'coupons:rolling-7d'
    );
    v_detected := v_detected + 1;
  end loop;

  -- 4) Çok kısa sürede yoğun ve tek yönlü ürün değerlendirmesi.
  for v_row in
    select pr.user_id, count(*) review_count,
           round(avg(pr.rating), 2) average_rating,
           count(*) filter (where pr.rating in (1, 5)) extreme_count
    from public.product_reviews pr
    where pr.created_at >= now() - interval '24 hours'
    group by pr.user_id
    having count(*) >= 5
       and count(*) filter (where pr.rating in (1, 5))::numeric / count(*) >= 0.80
  loop
    perform public.upsert_fraud_signal(
      v_row.user_id, 'fake_reviews',
      case when v_row.review_count >= 10 then 'high' else 'medium' end,
      least(100, 35 + (v_row.review_count * 5)),
      'Sahte değerlendirme olasılığı',
      format('24 saat içinde %s değerlendirme yapıldı; ortalama puan %s.',
        v_row.review_count, v_row.average_rating),
      jsonb_build_object('window_hours', 24, 'review_count', v_row.review_count,
        'average_rating', v_row.average_rating, 'extreme_rating_count', v_row.extreme_count),
      'reviews:rolling-24h'
    );
    v_detected := v_detected + 1;
  end loop;

  return jsonb_build_object('detected', v_detected, 'scanned_at', now());
end;
$$;

create or replace function public.admin_list_fraud_signals(
  p_status text default null,
  p_signal_type text default null,
  p_limit integer default 100,
  p_offset integer default 0
)
returns table (
  id uuid, user_id uuid, user_name text, user_email text,
  signal_type text, severity text, risk_score integer, status text,
  title text, description text, evidence jsonb, occurrence_count integer,
  first_detected_at timestamptz, last_detected_at timestamptz,
  reviewed_at timestamptz, admin_note text
)
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_fraud_admin() then
    raise exception 'Yetkiniz yok' using errcode = '42501';
  end if;
  return query
  select fs.id, fs.user_id, p.full_name, p.email, fs.signal_type,
    fs.severity, fs.risk_score, fs.status, fs.title, fs.description,
    fs.evidence, fs.occurrence_count, fs.first_detected_at,
    fs.last_detected_at, fs.reviewed_at, fs.admin_note
  from public.fraud_signals fs
  join public.profiles p on p.id = fs.user_id
  where (p_status is null or fs.status = p_status)
    and (p_signal_type is null or fs.signal_type = p_signal_type)
  order by
    case fs.status when 'open' then 0 when 'reviewing' then 1 else 2 end,
    fs.risk_score desc, fs.last_detected_at desc
  limit least(greatest(coalesce(p_limit, 100), 1), 250)
  offset greatest(coalesce(p_offset, 0), 0);
end;
$$;

create or replace function public.admin_review_fraud_signal(
  p_signal_id uuid,
  p_status text,
  p_admin_note text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_fraud_admin() then
    raise exception 'Yetkiniz yok' using errcode = '42501';
  end if;
  if p_status not in ('open', 'reviewing', 'confirmed', 'dismissed') then
    raise exception 'Geçersiz durum';
  end if;

  update public.fraud_signals
  set status = p_status,
      admin_note = nullif(btrim(p_admin_note), ''),
      reviewed_by = (select auth.uid()),
      reviewed_at = now(),
      updated_at = now()
  where id = p_signal_id;

  if not found then raise exception 'Sinyal bulunamadı'; end if;

  -- Onaylanmış sinyal kullanıcı profilindeki mevcut işaretle uyumlu tutulur.
  if p_status = 'confirmed' then
    update public.profiles p
    set is_suspicious = true,
        suspicious_reason = coalesce(p.suspicious_reason || '; ', '') ||
          (select title from public.fraud_signals where id = p_signal_id),
        suspicious_flagged_at = coalesce(p.suspicious_flagged_at, now())
    where p.id = (select user_id from public.fraud_signals where id = p_signal_id);
  end if;
end;
$$;

revoke all on function public.admin_scan_fraud_signals() from public;
revoke all on function public.admin_list_fraud_signals(text,text,integer,integer) from public;
revoke all on function public.admin_review_fraud_signal(uuid,text,text) from public;
grant execute on function public.admin_scan_fraud_signals() to authenticated;
grant execute on function public.admin_list_fraud_signals(text,text,integer,integer) to authenticated;
grant execute on function public.admin_review_fraud_signal(uuid,text,text) to authenticated;

comment on table public.fraud_signals is
  'Otomatik dolandırıcılık risk sinyalleri; nihai karar admin incelemesiyle verilir.';
