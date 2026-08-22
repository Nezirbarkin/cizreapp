-- =============================================================================
-- CizreApp Supabase Performance Advisor değişmezleri
--
-- Çalıştırma:
--   supabase start
--   supabase db reset
--   supabase test db
--
-- Bu testler veri yazmaz. [`20260804000001_fix_advisor_performance_lints.sql`](../migrations/20260804000001_fix_advisor_performance_lints.sql:1)
-- ile kapatılan üç Advisor lint ailesinin geri gelmediğini katalog üzerinden
-- doğrular:
--   * auth_rls_initplan            (0003)
--   * multiple_permissive_policies (0006)
--   * duplicate_index              (0009)
--
-- Yeni bir policy veya indeks eklendiğinde bu paket kırmızıya döner; bu
-- kasıtlıdır. Yeni policy ya `(select auth.uid())` biçimini kullanmalı ya da
-- aynı (tablo, komut, rol) grubundaki policy ile birleştirilmelidir.
-- =============================================================================

begin;

create extension if not exists pgtap with schema extensions;

select plan(4);

-- -----------------------------------------------------------------------------
-- Yardımcı görünümler: Advisor kurallarının katalog karşılığı
-- -----------------------------------------------------------------------------

-- Bir policy ifadesinin, (select ...) ile sarılmamış auth.<fn>() çağrısı
-- içerip içermediğini bulur. Negatif lookbehind, katalogdaki
-- "( SELECT auth.uid() AS uid)" biçimini eler.
create or replace view pg_temp.lint_auth_initplan as
select c.relname::text as tablename, p.polname::text as policyname
from pg_policy p
join pg_class c on c.oid = p.polrelid
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public'
  and (
    coalesce(pg_get_expr(p.polqual, p.polrelid), '')
      ~ '(?<!SELECT )auth\.(?:uid|role|jwt|email)\(\)'
    or coalesce(pg_get_expr(p.polwithcheck, p.polrelid), '')
      ~ '(?<!SELECT )auth\.(?:uid|role|jwt|email)\(\)'
  );

-- Aynı (tablo, rol, komut) üçlüsüne bakan permissive policy sayısı > 1.
-- FOR ALL policy'leri dört komuta açılır; TO PUBLIC policy'ler ise tabloda
-- gerçekten yetkisi olan somut rollere açılır (Advisor da böyle raporlar).
create or replace view pg_temp.lint_multiple_permissive as
select tablename, rolname, cmd,
       string_agg(distinct policyname, ', ' order by policyname) as policies
from (
  select c.relname::text as tablename,
         p.polname::text as policyname,
         x.cmd,
         r.rolname::text as rolname
  from pg_policy p
  join pg_class c on c.oid = p.polrelid
  join pg_namespace n on n.oid = c.relnamespace
  cross join lateral unnest(
    case p.polcmd
      when '*' then array['SELECT', 'INSERT', 'UPDATE', 'DELETE']
      when 'r' then array['SELECT']
      when 'a' then array['INSERT']
      when 'w' then array['UPDATE']
      when 'd' then array['DELETE']
    end
  ) as x(cmd)
  join pg_roles r
    on r.rolname not like 'pg\_%'
   and not r.rolsuper
   and (p.polroles = '{0}'::oid[] or r.oid = any (p.polroles))
   and has_table_privilege(r.oid, c.oid, 'SELECT, INSERT, UPDATE, DELETE')
  where n.nspname = 'public'
    and p.polpermissive
) s
group by tablename, rolname, cmd
having count(distinct policyname) > 1;

-- Aynı tabloda aynı tanıma sahip (isim dışında) birden fazla indeks.
create or replace view pg_temp.lint_duplicate_index as
select t.relname::text as tablename,
       string_agg(c.relname::text, ', ' order by c.relname) as indexes
from pg_index i
join pg_class c on c.oid = i.indexrelid
join pg_class t on t.oid = i.indrelid
join pg_namespace n on n.oid = t.relnamespace
where n.nspname = 'public'
group by t.relname, i.indrelid,
         regexp_replace(pg_get_indexdef(i.indexrelid), '^CREATE (UNIQUE )?INDEX \S+ ON ', '')
having count(*) > 1;

-- -----------------------------------------------------------------------------
-- 1) auth_rls_initplan: satır başına yeniden değerlendirilen auth çağrısı yok
-- -----------------------------------------------------------------------------
select is(
  (select coalesce(string_agg(format('%s.%s', tablename, policyname), ', ' order by tablename, policyname), ''))::text,
  ''::text,
  'auth.<fn>() çağrısı (select ...) ile sarılmamış policy yok'
)
from pg_temp.lint_auth_initplan;

-- -----------------------------------------------------------------------------
-- 2) multiple_permissive_policies
--
-- Aşağıdaki iki grup bilinçli olarak birleştirilmedi: policy'lerin rol kümeleri
-- farklı (biri TO PUBLIC, diğeri tek role bakıyor). Tek policy'de toplamak
-- ifadeye pg_has_role(...) gibi bir rol muhafızı eklemeyi gerektirir; kazanç
-- küçük, yetki hatası riski büyük olduğu için kapsam dışı bırakıldı.
-- Yeni bir istisna eklemeden önce birleştirmenin gerçekten mümkün olmadığı
-- doğrulanmalıdır.
-- -----------------------------------------------------------------------------
select is(
  (
    select coalesce(
      string_agg(format('%s/%s/%s', tablename, cmd, rolname), ', ' order by tablename, cmd, rolname),
      ''
    )
    from pg_temp.lint_multiple_permissive
    where (tablename, cmd) not in (
      ('posts',    'SELECT'),
      ('profiles', 'SELECT')
    )
  )::text,
  ''::text,
  'bilinen rol-kümesi istisnaları dışında çoklu permissive policy yok'
);

-- Bilinen istisnalar da büyümemeli: yalnız SELECT tarafında kalabilirler.
select is(
  (
    select count(*)
    from pg_temp.lint_multiple_permissive
    where tablename in ('posts', 'profiles')
      and cmd <> 'SELECT'
  )::bigint,
  0::bigint,
  'posts/profiles istisnaları yalnız SELECT komutunda; yazma tarafına taşmadı'
);

-- -----------------------------------------------------------------------------
-- 3) duplicate_index
-- -----------------------------------------------------------------------------
select is(
  (select coalesce(string_agg(format('%s: %s', tablename, indexes), ' | ' order by tablename), ''))::text,
  ''::text,
  'aynı sütun setini indeksleyen ikiz indeks yok'
)
from pg_temp.lint_duplicate_index;

-- Sonuç
select * from finish();

rollback;
