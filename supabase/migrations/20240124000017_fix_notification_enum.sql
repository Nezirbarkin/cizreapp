-- ============================================================================
-- NOTIFICATIONS - Fix ENUM Type
-- Mevcut notification_type enum'ına yeni değerler ekle
-- ============================================================================

-- Önce mevcut enum değerlerini görelim (comment out)
-- SELECT unnest(enum_range(NULL::notification_type));

-- Enum tipine yeni değerler ekle
ALTER TYPE notification_type ADD VALUE IF NOT EXISTS 'like';
ALTER TYPE notification_type ADD VALUE IF NOT EXISTS 'comment';
ALTER TYPE notification_type ADD VALUE IF NOT EXISTS 'follow';
ALTER TYPE notification_type ADD VALUE IF NOT EXISTS 'mention';
ALTER TYPE notification_type ADD VALUE IF NOT EXISTS 'order';
ALTER TYPE notification_type ADD VALUE IF NOT EXISTS 'shop';
