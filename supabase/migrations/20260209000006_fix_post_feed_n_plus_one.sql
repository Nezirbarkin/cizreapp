-- Feed Performans İyileştirmesi
-- N+1 query problemini çözer - her post için ayrı ayrı sorgu yerine tek sorgu

-- Posts tablosuna likes_count ve comments_count kolonları zaten var
-- Bu migration sadece view'ları oluşturur

-- User bilgileri ile birlikte posts view (profil resmi ve isim için)
CREATE OR REPLACE VIEW posts_with_user AS
SELECT 
    p.*,
    pr.full_name as user_full_name,
    pr.username as user_username,
    pr.avatar_url as user_avatar
FROM posts p
LEFT JOIN profiles pr ON p.user_id = pr.id;
