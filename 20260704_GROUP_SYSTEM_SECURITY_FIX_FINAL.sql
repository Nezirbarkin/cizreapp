-- =====================================================================
-- GRUP SİSTEMİ GÜVENLİK DÜZELTMESİ (NİHAİ / TEK DOSYA)
-- =====================================================================
-- Geçmiş dosyalarda (GROUP_CHAT_SETUP, GROUP_CHAT_LINTER_FIX,
-- FIX_GROUP_MEMBERS_INFINITE_RECURSION, FIX_OPEN_GROUP_JOIN,
-- FIX_GROUP_MEMBERS_RLS_FINAL, FIX_GROUP_RLS_CLEAN_POLICIES,
-- FIX_GROUP_MEMBERS_RLS_BYPASS) birbiriyle çelişen / birbirini geçersiz
-- kılan group_members politikaları biriktirildi. FIX_GROUP_MEMBERS_RLS_BYPASS.sql
-- hatta RLS'yi tamamen KAPATIYOR - bu dosya en son çalıştırılmışsa şu anda
-- group_members tablosu RLS korumasız durumda (herkes her satırı okuyup
-- yazabilir). Bu dosya, hangi sıra ile çalıştırılmış olursa olsun son
-- (kazanan) ve tutarlı durumu garanti eder. İdempotenttir, tekrar tekrar
-- çalıştırılabilir.
--
-- Kapatılan açıklar:
-- 1) RLS kapalıysa yeniden AÇILIYOR.
-- 2) Bir üyenin kendi rolünü 'admin' yaparak yetki yükseltmesi ENGELLENDİ
--    (trigger ile - RLS USING/WITH CHECK kolon bazlı fark göremediği için).
-- 3) group_members INSERT: private gruba kendini ekleyerek üyelik
--    kontrolünü atlatma (join request akışını bypass) ENGELLENDİ.
-- 4) admin_add_group_member RPC: p_added_by parametresi client tarafından
--    taklit edilebiliyordu (sahte admin ID'si göndererek). Artık
--    auth.uid() kullanılıyor, parametre yok sayılıyor.
-- =====================================================================

-- ── 1. Yardımcı fonksiyonlar (varsa yeniden oluştur, RLS bypass eder) ──
CREATE OR REPLACE FUNCTION public.is_group_admin(p_group_id UUID, p_user_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
BEGIN
    RETURN EXISTS (
        SELECT 1 FROM public.group_members gm
        WHERE gm.group_id = p_group_id
        AND gm.user_id = p_user_id
        AND gm.role IN ('admin', 'owner', 'moderator')
    );
END;
$$;

CREATE OR REPLACE FUNCTION public.is_group_member(p_group_id UUID, p_user_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
BEGIN
    RETURN EXISTS (
        SELECT 1 FROM public.group_members gm
        WHERE gm.group_id = p_group_id
        AND gm.user_id = p_user_id
    );
END;
$$;

GRANT EXECUTE ON FUNCTION public.is_group_admin(UUID, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_group_member(UUID, UUID) TO authenticated;

-- ── 2. RLS'yi zorla aç (FIX_GROUP_MEMBERS_RLS_BYPASS.sql onu kapatmış olabilir) ──
ALTER TABLE public.group_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.groups ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.group_join_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.group_messages ENABLE ROW LEVEL SECURITY;

-- ── 3. group_members: tüm eski/çakışan politikaları temizle ──
DROP POLICY IF EXISTS "Users can view group members" ON public.group_members;
DROP POLICY IF EXISTS "Anyone can view group members" ON public.group_members;
DROP POLICY IF EXISTS "Group members select policy" ON public.group_members;

DROP POLICY IF EXISTS "System can insert group members" ON public.group_members;
DROP POLICY IF EXISTS "Users can insert group members" ON public.group_members;
DROP POLICY IF EXISTS "Unified group members insert" ON public.group_members;
DROP POLICY IF EXISTS "Admins can insert group members" ON public.group_members;
DROP POLICY IF EXISTS "Group admins can add members" ON public.group_members;
DROP POLICY IF EXISTS "Group members insert policy" ON public.group_members;
DROP POLICY IF EXISTS "Users can join open groups" ON public.group_members;
DROP POLICY IF EXISTS "Group creators can add themselves" ON public.group_members;

DROP POLICY IF EXISTS "Admins and self can delete members" ON public.group_members;
DROP POLICY IF EXISTS "Members can leave groups" ON public.group_members;
DROP POLICY IF EXISTS "Group members delete policy" ON public.group_members;

DROP POLICY IF EXISTS "Admins can update members" ON public.group_members;

-- ── 4. group_members: kanonik politikalar ──

-- SELECT: kendi üyeliği veya üyesi olduğu grubun diğer üyeleri
CREATE POLICY "Users can view group members"
    ON public.group_members FOR SELECT
    USING (
        user_id = (select auth.uid())
        OR public.is_group_member(group_id, (select auth.uid()))
    );

-- INSERT: kendini ekliyorsa (yalnızca açık gruba veya kendi kurduğu gruba)
-- YA DA bir admin başka bir kullanıcıyı ekliyorsa
CREATE POLICY "Group members insert"
    ON public.group_members FOR INSERT
    WITH CHECK (
        (
            user_id = (select auth.uid())
            AND (
                EXISTS (
                    SELECT 1 FROM public.groups g
                    WHERE g.id = group_members.group_id
                    AND COALESCE(g.is_private, false) = false
                )
                OR EXISTS (
                    SELECT 1 FROM public.groups g
                    WHERE g.id = group_members.group_id
                    AND g.created_by = (select auth.uid())
                )
            )
        )
        OR public.is_group_admin(group_id, (select auth.uid()))
    );

-- DELETE: kendisi ayrılabilir veya admin başkasını çıkarabilir
CREATE POLICY "Group members delete"
    ON public.group_members FOR DELETE
    USING (
        user_id = (select auth.uid())
        OR public.is_group_admin(group_id, (select auth.uid()))
    );

-- UPDATE: kendi kaydını (mute vs.) veya admin herhangi bir kaydı güncelleyebilir
-- NOT: role sütununun kendi kendine yükseltilmesi aşağıdaki trigger ile engellenir
CREATE POLICY "Group members update"
    ON public.group_members FOR UPDATE
    USING (
        user_id = (select auth.uid())
        OR public.is_group_admin(group_id, (select auth.uid()))
    );

-- ── 5. Rol yükseltme koruması (trigger) ──
-- RLS politikaları kolon bazlı fark göremediği için (bir üye kendi satırını
-- güncelleyebilir ama 'role' alanını admin yapmasını RLS tek başına engelleyemez),
-- bunu bir BEFORE UPDATE trigger ile zorunlu kılıyoruz.
CREATE OR REPLACE FUNCTION public.prevent_group_member_role_self_escalation()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF NEW.role IS DISTINCT FROM OLD.role THEN
        IF NOT public.is_group_admin(OLD.group_id, auth.uid()) THEN
            RAISE EXCEPTION 'Yetkisiz: rolünüzü değiştiremezsiniz';
        END IF;
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_prevent_group_member_role_self_escalation ON public.group_members;
CREATE TRIGGER trg_prevent_group_member_role_self_escalation
    BEFORE UPDATE ON public.group_members
    FOR EACH ROW
    EXECUTE FUNCTION public.prevent_group_member_role_self_escalation();

-- ── 6. admin_add_group_member RPC: p_added_by artık güvenilmiyor ──
CREATE OR REPLACE FUNCTION public.admin_add_group_member(
    p_group_id UUID,
    p_user_id UUID,
    p_added_by UUID DEFAULT NULL -- geriye dönük uyumluluk için tutuldu, KULLANILMIYOR
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF NOT public.is_group_admin(p_group_id, auth.uid()) THEN
        RAISE EXCEPTION 'Only group admins can add members';
    END IF;

    IF EXISTS (
        SELECT 1 FROM public.group_members gm
        WHERE gm.group_id = p_group_id AND gm.user_id = p_user_id
    ) THEN
        RAISE EXCEPTION 'User is already a member of this group';
    END IF;

    INSERT INTO public.group_members (group_id, user_id, role, joined_at)
    VALUES (p_group_id, p_user_id, 'member', NOW());
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_add_group_member(UUID, UUID, UUID) TO authenticated;

-- ── 7. join_open_group: private grup kontrolü zaten var, değişmedi (referans) ──
-- FIX_OPEN_GROUP_JOIN.sql içindeki tanım doğru, burada tekrar yaratılmıyor.

-- ── 8. Şema cache yenile ──
NOTIFY pgrst, 'reload schema';
