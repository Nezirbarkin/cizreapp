-- =====================================================
-- Sosyal Medya Test Verileri
-- User ID: 78665f8b-6a07-40f3-b13d-d4b5a29296c6
-- =====================================================

-- 1. Test Gönderileri (Posts)
INSERT INTO posts (user_id, content, images, location, latitude, longitude, likes_count, comments_count, is_active)
VALUES
('78665f8b-6a07-40f3-b13d-d4b5a29296c6', 
 'Cizre''de harika bir gün! Şehrimizin güzellikleri 🌆', 
 ARRAY['https://images.unsplash.com/photo-1449824913935-59a10b8d2000?w=600'], 
 'Cizre, Şırnak', 37.3253, 42.1958, 15, 3, true),

('78665f8b-6a07-40f3-b13d-d4b5a29296c6', 
 'Yeni açılan Pizza Palace''tan harika pizza! Kesinlikle deneyin 🍕', 
 ARRAY['https://images.unsplash.com/photo-1574071318508-1cdbab80d002?w=600'], 
 'Pizza Palace, Cizre', 37.3253, 42.1958, 28, 8, true),

('78665f8b-6a07-40f3-b13d-d4b5a29296c6', 
 'Fresh Market''ten taze organik sebzeler aldım. Kalitesi çok iyi! 🥗🥕', 
 ARRAY['https://images.unsplash.com/photo-1540189549336-e6e99c3679fe?w=600', 'https://images.unsplash.com/photo-1592924357228-91a4daadcfea?w=600'], 
 'Fresh Market, Cizre', 37.3253, 42.1958, 12, 2, true),

('78665f8b-6a07-40f3-b13d-d4b5a29296c6', 
 'Bugün çok güzel bir gün geçirdim! Herkese mutlu günler 😊', 
 NULL, 
 NULL, NULL, NULL, 5, 1, true),

('78665f8b-6a07-40f3-b13d-d4b5a29296c6', 
 'Cizre''nin en lezzetli dönerini Doner King''de buldum! Herkese tavsiye ederim 🌯', 
 ARRAY['https://images.unsplash.com/photo-1565299585323-38d6b0865b47?w=600'], 
 'Doner King, Cizre', 37.3253, 42.1958, 32, 6, true);

-- 2. Beğeniler (Post Likes) - ilk gönderi için
INSERT INTO post_likes (post_id, user_id)
VALUES
((SELECT id FROM posts WHERE content LIKE '%Cizre%de harika%' LIMIT 1), '78665f8b-6a07-40f3-b13d-d4b5a29296c6');

-- 3. Yorumlar (Post Comments)
INSERT INTO post_comments (post_id, user_id, content)
VALUES
((SELECT id FROM posts WHERE content LIKE '%Pizza Palace%' LIMIT 1), 
 '78665f8b-6a07-40f3-b13d-d4b5a29296c6', 
 'Ben de denedim, gerçekten çok lezzetli! 👍'),

((SELECT id FROM posts WHERE content LIKE '%Pizza Palace%' LIMIT 1), 
 '78665f8b-6a07-40f3-b13d-d4b5a29296c6', 
 'Fiyatları uygun mu?'),

((SELECT id FROM posts WHERE content LIKE '%Fresh Market%' LIMIT 1), 
 '78665f8b-6a07-40f3-b13d-d4b5a29296c6', 
 'Organik ürünleri nereden buluyorlar?');

-- 4. Hikayeler (Stories) - 24 saat aktif
INSERT INTO stories (user_id, image_url, views_count)
VALUES
('78665f8b-6a07-40f3-b13d-d4b5a29296c6', 
 'https://images.unsplash.com/photo-1495474472287-4d71bcdd2085?w=400', 
 15),

('78665f8b-6a07-40f3-b13d-d4b5a29296c6', 
 'https://images.unsplash.com/photo-1504674900247-0877df9cc836?w=400', 
 22),

('78665f8b-6a07-40f3-b13d-d4b5a29296c6', 
 'https://images.unsplash.com/photo-1551024506-0bccd828d307?w=400', 
 8);

-- 5. Hikaye Görüntülemeleri (Story Views)
INSERT INTO story_views (story_id, user_id)
VALUES
((SELECT id FROM stories WHERE image_url LIKE '%1495474472287%' LIMIT 1), 
 '78665f8b-6a07-40f3-b13d-d4b5a29296c6');
