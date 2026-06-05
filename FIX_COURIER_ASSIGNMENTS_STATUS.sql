-- courier_assignments tablosuna 'on_the_way' status ekle
-- Mevcut constraint'i kaldırıp yeniden oluştur

-- Önce mevcut constraint'i kontrol et
SELECT conname, pg_get_constraintdef(oid) 
FROM pg_constraint 
WHERE conname = 'courier_assignments_status_check';

-- Constraint'i kaldır (varsa)
ALTER TABLE courier_assignments DROP CONSTRAINT IF EXISTS courier_assignments_status_check;

-- Yeni constraint ekle (on_the_way dahil)
ALTER TABLE courier_assignments ADD CONSTRAINT courier_assignments_status_check 
CHECK (status IN ('assigned', 'picked_up', 'on_the_way', 'delivered', 'cancelled'));

-- Doğrulama
SELECT conname, pg_get_constraintdef(oid) 
FROM pg_constraint 
WHERE conname = 'courier_assignments_status_check';
