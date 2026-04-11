-- ========================================
-- SUPABASE STORAGE SETUP
-- CizreApp - Story ve Post Görselleri için
-- ========================================

-- 1. STORIES Bucket Oluştur
insert into storage.buckets (id, name, public)
values ('stories', 'stories', true)
on conflict (id) do nothing;

-- 2. POSTS Bucket Oluştur
insert into storage.buckets (id, name, public)
values ('posts', 'posts', true)
on conflict (id) do nothing;

-- 3. AVATARS Bucket Oluştur (yoksa)
insert into storage.buckets (id, name, public)
values ('avatars', 'avatars', true)
on conflict (id) do nothing;

-- ========================================
-- RLS POLICIES - STORIES
-- ========================================

-- Story görüntüleme (herkes)
create policy "Stories are viewable by everyone"
on storage.objects for select
to public
using (bucket_id = 'stories');

-- Story yükleme (sadece giriş yapmış kullanıcılar)
create policy "Authenticated users can upload stories"
on storage.objects for insert
to authenticated
with check (bucket_id = 'stories');

-- Kendi story'sini silme
create policy "Users can delete own stories"
on storage.objects for delete
to authenticated
using (bucket_id = 'stories' and auth.uid()::text = (storage.foldername(name))[1]);

-- ========================================
-- RLS POLICIES - POSTS
-- ========================================

-- Post görsellerini görüntüleme (herkes)
create policy "Post images are viewable by everyone"
on storage.objects for select
to public
using (bucket_id = 'posts');

-- Post görseli yükleme (sadece giriş yapmış kullanıcılar)
create policy "Authenticated users can upload post images"
on storage.objects for insert
to authenticated
with check (bucket_id = 'posts');

-- Kendi post görselini silme
create policy "Users can delete own post images"
on storage.objects for delete
to authenticated
using (bucket_id = 'posts' and auth.uid()::text = (storage.foldername(name))[1]);

-- ========================================
-- KONTROL
-- ========================================

-- Bucket'ları listele
select id, name, public, file_size_limit, allowed_mime_types
from storage.buckets
where id in ('stories', 'posts', 'avatars');

-- ========================================
-- BAŞARIYLA TAMAMLANDI!
-- ========================================
