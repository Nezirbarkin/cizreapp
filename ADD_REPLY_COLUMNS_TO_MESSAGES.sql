-- Mesaj yanıtları için gerekli kolonları ekle
-- Bu dosyayı Supabase SQL Editor'de çalıştırın

ALTER TABLE messages
ADD COLUMN IF NOT EXISTS reply_to_id TEXT,
ADD COLUMN IF NOT EXISTS reply_to_content TEXT,
ADD COLUMN IF NOT EXISTS reply_to_sender_name TEXT;

-- Kolonlar eklendikten sonra RLS politikalarını güncelleyin
-- (Mevcut politikalar zaten okuma/yazma izni veriyor, ek bir değişiklik gerekmez)
