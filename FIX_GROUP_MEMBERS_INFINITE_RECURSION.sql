-- ============================================================================
-- FIX: group_members Tablosu Sonsuz Özyineleme Hatası
-- ============================================================================
-- Problem: INSERT/SELECT/DELETE/UPDATE RLS politikaları group_members tablosunu
--          sorguluyor, bu da SELECT RLS politikasını tetikliyor → sonsuz döngü
-- 
-- Çözüm: SECURITY DEFINER fonksiyonlar ile RLS bypass + trigger kullanımı
-- ============================================================================

-- ╔══════════════════════════════════════════════════════════════╗
-- ║  ADIM 1: SECURITY DEFINER Yardımcı Fonksiyonları Oluştur  ║
-- ╚══════════════════════════════════════════════════════════════╝

-- Admin kontrolü için güvenli fonksiyon (RLS'yi bypass eder)
CREATE OR REPLACE FUNCTION public.is_group_admin(
    p_group_id UUID,
    p_user_id UUID
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
SET search_path = ''
AS $$
BEGIN
    RETURN EXISTS (
        SELECT 1 
        FROM public.group_members gm
        WHERE gm.group_id = p_group_id
        AND gm.user_id = p_user_id
        AND gm.role = 'admin'
    );
END;
$$;

-- Grup üyesi kontrolü için güvenli fonksiyon (RLS'yi bypass eder)
CREATE OR REPLACE FUNCTION public.is_group_member(
    p_group_id UUID,
    p_user_id UUID
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
SET search_path = ''
AS $$
BEGIN
    RETURN EXISTS (
        SELECT 1 
        FROM public.group_members gm
        WHERE gm.group_id = p_group_id
        AND gm.user_id = p_user_id
    );
END;
$$;

-- Grup oluşturulduğunda yaratıcıyı admin olarak ekleyen trigger fonksiyonu
CREATE OR REPLACE FUNCTION public.add_group_creator_as_admin()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
    INSERT INTO public.group_members (group_id, user_id, role, joined_at)
    VALUES (NEW.id, NEW.created_by, 'admin', NOW())
    ON CONFLICT (group_id, user_id) DO NOTHING;
    RETURN NEW;
END;
$$;

-- Admin tarafından başka bir kullanıcıyı gruba ekleyen RPC fonksiyonu
CREATE OR REPLACE FUNCTION public.admin_add_group_member(
    p_group_id UUID,
    p_user_id UUID,
    p_added_by UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
    -- Ekleyen kişinin admin olup olmadığını kontrol et
    IF NOT EXISTS (
        SELECT 1 FROM public.group_members gm
        WHERE gm.group_id = p_group_id
        AND gm.user_id = p_added_by
        AND gm.role = 'admin'
    ) THEN
        RAISE EXCEPTION 'Only group admins can add members';
    END IF;
    
    -- Kullanıcı zaten üye mi kontrol et
    IF EXISTS (
        SELECT 1 FROM public.group_members gm
        WHERE gm.group_id = p_group_id
        AND gm.user_id = p_user_id
    ) THEN
        RAISE EXCEPTION 'User is already a member of this group';
    END IF;
    
    -- Üyeyi ekle
    INSERT INTO public.group_members (group_id, user_id, role, joined_at)
    VALUES (p_group_id, p_user_id, 'member', NOW());
END;
$$;

-- Fonksiyonlar için GRANT
GRANT EXECUTE ON FUNCTION public.is_group_admin(UUID, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_group_member(UUID, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.add_group_creator_as_admin() TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_add_group_member(UUID, UUID, UUID) TO authenticated;

-- ╔══════════════════════════════════════════════════════════════╗
-- ║  ADIM 2: Trigger'ı Oluştur (eski trigger'ları temizle)    ║
-- ╚══════════════════════════════════════════════════════════════╝

-- Eski trigger'ları sil (çakışma önleme)
DROP TRIGGER IF EXISTS on_group_created ON public.groups;
DROP TRIGGER IF EXISTS on_group_created_add_admin ON public.groups;

-- Tek bir trigger oluştur
CREATE TRIGGER on_group_created_add_admin
    AFTER INSERT ON public.groups
    FOR EACH ROW
    EXECUTE FUNCTION public.add_group_creator_as_admin();

-- ╔══════════════════════════════════════════════════════════════╗
-- ║  ADIM 3: Eski Politikaları Sil                             ║
-- ╚══════════════════════════════════════════════════════════════╝

DROP POLICY IF EXISTS "Users can view group members" ON public.group_members;
DROP POLICY IF EXISTS "System can insert group members" ON public.group_members;
DROP POLICY IF EXISTS "Users can insert group members" ON public.group_members;
DROP POLICY IF EXISTS "Admins and self can delete members" ON public.group_members;
DROP POLICY IF EXISTS "Admins can update members" ON public.group_members;

-- ╔══════════════════════════════════════════════════════════════╗
-- ║  ADIM 4: Yeni Güvenli Politikaları Oluştur                ║
-- ╚══════════════════════════════════════════════════════════════╝

-- SELECT: Kendi kaydı veya üye olduğu gruptaki kayıtları görebilir
-- is_group_member() SECURITY DEFINER olduğu için RLS döngüsü oluşmaz
CREATE POLICY "Users can view group members"
    ON public.group_members FOR SELECT
    USING (
        user_id = (select auth.uid())
        OR public.is_group_member(group_id, (select auth.uid()))
    );

-- INSERT: Sadece kendi user_id'si ile kayıt ekleyebilir
-- NOT: Grup oluşturanın admin kaydı trigger ile oluşturulur (SECURITY DEFINER)
CREATE POLICY "Users can insert group members"
    ON public.group_members FOR INSERT
    WITH CHECK (
        user_id = (select auth.uid())
    );

-- DELETE: Kendi kaydını silebilir veya admin başkalarını çıkartabilir
CREATE POLICY "Admins and self can delete members"
    ON public.group_members FOR DELETE
    USING (
        user_id = (select auth.uid())
        OR public.is_group_admin(group_id, (select auth.uid()))
    );

-- UPDATE: Kendi kaydını güncelleyebilir (mute/unmute) veya admin güncelleyebilir
CREATE POLICY "Admins can update members"
    ON public.group_members FOR UPDATE
    USING (
        user_id = (select auth.uid())
        OR public.is_group_admin(group_id, (select auth.uid()))
    );

-- ╔══════════════════════════════════════════════════════════════╗
-- ║  ADIM 5: RLS Etkin Olduğundan Emin Ol                     ║
-- ╚══════════════════════════════════════════════════════════════╝

ALTER TABLE public.group_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.groups ENABLE ROW LEVEL SECURITY;

-- ╔══════════════════════════════════════════════════════════════╗
-- ║  ADIM 6: groups Tablosu İçin Politikaları Düzelt           ║
-- ╚══════════════════════════════════════════════════════════════╝

-- groups tablosu politikaları da group_members tablosunu sorguladığı
-- için aynı sorun oluşabilir. SECURITY DEFINER fonksiyonlar kullanıyoruz.

-- Eski politikaları sil (hem yeni hem eski isimleri)
DROP POLICY IF EXISTS "Users can view groups" ON public.groups;
DROP POLICY IF EXISTS "Anyone can view public groups" ON public.groups;
DROP POLICY IF EXISTS "Users can create groups" ON public.groups;
DROP POLICY IF EXISTS "Authenticated users can create groups" ON public.groups;
DROP POLICY IF EXISTS "Admins can update groups" ON public.groups;
DROP POLICY IF EXISTS "Group admins can update groups" ON public.groups;
DROP POLICY IF EXISTS "Admins can delete groups" ON public.groups;
DROP POLICY IF EXISTS "Group admins can delete groups" ON public.groups;

-- Tüm authenticated kullanıcılar tüm grupları görebilir (gizli/açık fark etmez)
CREATE POLICY "Users can view groups"
    ON public.groups FOR SELECT
    USING (
        (select auth.role()) = 'authenticated'
    );

-- Authenticated kullanıcılar grup oluşturabilir
CREATE POLICY "Users can create groups"
    ON public.groups FOR INSERT
    WITH CHECK (
        created_by = (select auth.uid())
    );

-- Sadece grup adminleri güncelleyebilir
CREATE POLICY "Admins can update groups"
    ON public.groups FOR UPDATE
    USING (
        public.is_group_admin(id, (select auth.uid()))
    );

-- Sadece grup adminleri silebilir
CREATE POLICY "Admins can delete groups"
    ON public.groups FOR DELETE
    USING (
        public.is_group_admin(id, (select auth.uid()))
    );

-- ╔══════════════════════════════════════════════════════════════╗
-- ║  ADIM 7: group_messages Tablosu Politikalarını Düzelt      ║
-- ╚══════════════════════════════════════════════════════════════╝

DROP POLICY IF EXISTS "Group members can view messages" ON public.group_messages;
DROP POLICY IF EXISTS "Group members can send messages" ON public.group_messages;

-- Grup üyeleri mesajları görebilir
CREATE POLICY "Group members can view messages"
    ON public.group_messages FOR SELECT
    USING (
        public.is_group_member(group_id, (select auth.uid()))
    );

-- Grup üyeleri mesaj gönderebilir
CREATE POLICY "Group members can send messages"
    ON public.group_messages FOR INSERT
    WITH CHECK (
        sender_id = (select auth.uid())
        AND public.is_group_member(group_id, (select auth.uid()))
    );

ALTER TABLE public.group_messages ENABLE ROW LEVEL SECURITY;

-- group_messages tablosuna sender_id FK ilişkisi ekle (profiles ile)
-- Bu ilişki PostgREST'in join yapabilmesi için gerekli
DO $$
BEGIN
    -- FK yoksa ekle
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.table_constraints
        WHERE constraint_name = 'group_messages_sender_id_fkey'
        AND table_name = 'group_messages'
    ) THEN
        ALTER TABLE public.group_messages
        ADD CONSTRAINT group_messages_sender_id_fkey
        FOREIGN KEY (sender_id) REFERENCES auth.users(id) ON DELETE CASCADE;
    END IF;
END;
$$;

-- group_messages tablosuna group_id FK ilişkisi ekle (groups ile)
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.table_constraints
        WHERE constraint_name = 'group_messages_group_id_fkey'
        AND table_name = 'group_messages'
    ) THEN
        ALTER TABLE public.group_messages
        ADD CONSTRAINT group_messages_group_id_fkey
        FOREIGN KEY (group_id) REFERENCES public.groups(id) ON DELETE CASCADE;
    END IF;
END;
$$;

-- ╔══════════════════════════════════════════════════════════════╗
-- ║  ADIM 8: member_count Düzeltmesi                           ║
-- ╚══════════════════════════════════════════════════════════════╝

-- member_count DEFAULT 0 olmalı (trigger artırıyor)
ALTER TABLE public.groups ALTER COLUMN member_count SET DEFAULT 0;

-- update_group_member_count fonksiyonunu güvenli hale getir
CREATE OR REPLACE FUNCTION public.update_group_member_count()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        UPDATE public.groups
        SET member_count = member_count + 1
        WHERE id = NEW.group_id;
    ELSIF TG_OP = 'DELETE' THEN
        UPDATE public.groups
        SET member_count = GREATEST(member_count - 1, 0)
        WHERE id = OLD.group_id;
    END IF;
    RETURN NULL;
END;
$$;

-- Mevcut grupların member_count'ını düzelt (gerçek üye sayısıyla senkronize et)
UPDATE public.groups g
SET member_count = (
    SELECT COUNT(*)
    FROM public.group_members gm
    WHERE gm.group_id = g.id
);

-- ╔══════════════════════════════════════════════════════════════╗
-- ║  ADIM 9: group_join_requests Tablosu RLS Politikaları       ║
-- ╚══════════════════════════════════════════════════════════════╝

-- Eski politikaları sil
DROP POLICY IF EXISTS "Users can view their requests and admins can view all" ON public.group_join_requests;
DROP POLICY IF EXISTS "Users can create join requests" ON public.group_join_requests;
DROP POLICY IF EXISTS "Admins can update join requests" ON public.group_join_requests;
DROP POLICY IF EXISTS "Users can delete their own requests" ON public.group_join_requests;

-- Kullanıcılar kendi isteklerini görebilir, adminler grubun tüm isteklerini görebilir
CREATE POLICY "Users can view their requests and admins can view all"
    ON public.group_join_requests FOR SELECT
    USING (
        user_id = (select auth.uid())
        OR public.is_group_admin(group_id, (select auth.uid()))
    );

-- Kullanıcılar istek oluşturabilir
CREATE POLICY "Users can create join requests"
    ON public.group_join_requests FOR INSERT
    WITH CHECK (user_id = (select auth.uid()));

-- Adminler istekleri güncelleyebilir (onaylama/reddetme)
CREATE POLICY "Admins can update join requests"
    ON public.group_join_requests FOR UPDATE
    USING (
        public.is_group_admin(group_id, (select auth.uid()))
    );

-- Kullanıcılar kendi isteklerini silebilir
CREATE POLICY "Users can delete their own requests"
    ON public.group_join_requests FOR DELETE
    USING (user_id = (select auth.uid()));

ALTER TABLE public.group_join_requests ENABLE ROW LEVEL SECURITY;

-- ╔══════════════════════════════════════════════════════════════╗
-- ║  ADIM 10: Storage Bucket ve Politikaları (grup profil için) ║
-- ╚══════════════════════════════════════════════════════════════╝

-- public bucket'ında group_images klasörü için storage politikaları
-- Bucket zaten mevcut olabilir, hata durumunda devam et
DO $$
BEGIN
    -- Bucket yoksa oluştur
    INSERT INTO storage.buckets (id, name, public)
    VALUES ('public', 'public', true)
    ON CONFLICT (id) DO NOTHING;
EXCEPTION
    WHEN OTHERS THEN
        -- Bucket zaten varsa sorun değil
        NULL;
END;
$$;

-- Storage politikaları - grup resimleri için
DROP POLICY IF EXISTS "Group images are publicly accessible" ON storage.objects;
DROP POLICY IF EXISTS "Authenticated users can upload group images" ON storage.objects;
DROP POLICY IF EXISTS "Group admins can update group images" ON storage.objects;
DROP POLICY IF EXISTS "Group admins can delete group images" ON storage.objects;

-- Herkes grup resimlerini görebilir
CREATE POLICY "Group images are publicly accessible"
    ON storage.objects FOR SELECT
    USING (bucket_id = 'public' AND (storage.foldername(name))[1] = 'group_images');

-- Authenticated kullanıcılar resim yükleyebilir
CREATE POLICY "Authenticated users can upload group images"
    ON storage.objects FOR INSERT
    WITH CHECK (
        bucket_id = 'public'
        AND (storage.foldername(name))[1] = 'group_images'
        AND (select auth.role()) = 'authenticated'
    );

-- Authenticated kullanıcılar resim güncelleyebilir
CREATE POLICY "Group admins can update group images"
    ON storage.objects FOR UPDATE
    USING (
        bucket_id = 'public'
        AND (storage.foldername(name))[1] = 'group_images'
        AND (select auth.role()) = 'authenticated'
    );

-- Authenticated kullanıcılar resim silebilir
CREATE POLICY "Group admins can delete group images"
    ON storage.objects FOR DELETE
    USING (
        bucket_id = 'public'
        AND (storage.foldername(name))[1] = 'group_images'
        AND (select auth.role()) = 'authenticated'
    );

-- ╔══════════════════════════════════════════════════════════════╗
-- ║  AÇIKLAMALAR                                               ║
-- ╚══════════════════════════════════════════════════════════════╝
--
-- 1. SECURITY DEFINER fonksiyonlar RLS'yi bypass eder → döngü yok
-- 2. INSERT politikası sadece user_id kontrolü yapar (EXISTS yok)
-- 3. Grup yaratıcısı TRIGGER ile otomatik admin olur (SECURITY DEFINER)
-- 4. Admin/üye kontrolleri güvenli fonksiyonlar üzerinden yapılır
-- 5. UPDATE politikası mute/unmute için kendi kaydını güncelleyebilir
-- 6. groups tablosu politikaları da güvenli fonksiyonlar kullanır
-- 7. member_count DEFAULT 0, trigger ile otomatik artar/azalır
-- 8. Mevcut grupların member_count'ı gerçek üye sayısına göre düzeltildi
-- 9. Eski trigger (on_group_created) silindi, çift tetikleme önlendi
-- 10. ON CONFLICT ile duplicate key hatası önlendi
-- 11. Storage politikaları: grup profil resmi yüklenebilir
-- ============================================================================
