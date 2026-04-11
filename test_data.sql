-- =====================================================
-- CizreApp Test Verileri
-- User ID: 78665f8b-6a07-40f3-b13d-d4b5a29296c6
-- =====================================================

-- 0. Önce profil oluştur (eğer yoksa)
INSERT INTO profiles (id, email, full_name, role, status)
VALUES
('78665f8b-6a07-40f3-b13d-d4b5a29296c6',
 'test@cizreapp.com',
 'Test Kullanıcı',
 'seller',
 'active')
ON CONFLICT (id) DO NOTHING;

-- 1. Dükkan 1: Pizza Palace
INSERT INTO shops (owner_id, category_id, name, slug, description, is_open, rating, total_orders, is_active) 
VALUES 
('78665f8b-6a07-40f3-b13d-d4b5a29296c6', 
 (SELECT id FROM categories WHERE slug = 'yemek' LIMIT 1), 
 'Pizza Palace', 'pizza-palace', 'Şehrin en lezzetli pizzaları', true, 4.5, 120, true);

-- 2. Dükkan 2: Fresh Market
INSERT INTO shops (owner_id, category_id, name, slug, description, is_open, rating, total_orders, is_active) 
VALUES 
('78665f8b-6a07-40f3-b13d-d4b5a29296c6', 
 (SELECT id FROM categories WHERE slug = 'market' LIMIT 1), 
 'Fresh Market', 'fresh-market', 'Taze sebze, meyve ve bakkal ürünleri', true, 4.2, 85, true);

-- 3. Dükkan 3: Doner King
INSERT INTO shops (owner_id, category_id, name, slug, description, is_open, rating, total_orders, is_active)
VALUES
('78665f8b-6a07-40f3-b13d-d4b5a29296c6',
 (SELECT id FROM categories WHERE slug = 'yemek' LIMIT 1),
 'Doner King', 'doner-king', 'En meşhur döner ve kebablar', true, 4.7, 250, true);

-- 4. Ürünler - Pizza Palace
INSERT INTO products (shop_id, category_id, name, slug, price, discount_price, stock_quantity, rating, total_reviews, images, is_active) 
VALUES
((SELECT id FROM shops WHERE slug = 'pizza-palace'), 
 (SELECT id FROM categories WHERE slug = 'yemek'), 
 'Margarita Pizza', 'margarita-pizza-1', 150.00, 120.00, 25, 4.8, 45, 
 ARRAY['https://images.unsplash.com/photo-1574071318508-1cdbab80d002?w=500&h=500&fit=crop'], true),

((SELECT id FROM shops WHERE slug = 'pizza-palace'), 
 (SELECT id FROM categories WHERE slug = 'yemek'), 
 'Pepperoni Pizza', 'pepperoni-pizza-1', 160.00, 130.00, 15, 4.9, 52, 
 ARRAY['https://images.unsplash.com/photo-1628840042765-356cda07504e?w=500&h=500&fit=crop'], true),

((SELECT id FROM shops WHERE slug = 'pizza-palace'), 
 (SELECT id FROM categories WHERE slug = 'yemek'), 
 'Veggie Pizza', 'veggie-pizza-1', 140.00, NULL, 30, 4.6, 38, 
 ARRAY['https://images.unsplash.com/photo-1563504755-efb243c7f4f0?w=500&h=500&fit=crop'], true),

((SELECT id FROM shops WHERE slug = 'pizza-palace'), 
 (SELECT id FROM categories WHERE slug = 'yemek'), 
 'BBQ Chicken Pizza', 'bbq-chicken-pizza-1', 170.00, 140.00, 20, 4.7, 41, 
 ARRAY['https://images.unsplash.com/photo-1595521624512-dba4ad36a48c?w=500&h=500&fit=crop'], true);

-- 5. Ürünler - Fresh Market
INSERT INTO products (shop_id, category_id, name, slug, price, discount_price, stock_quantity, rating, total_reviews, images, is_active) 
VALUES
((SELECT id FROM shops WHERE slug = 'fresh-market'), 
 (SELECT id FROM categories WHERE slug = 'market'), 
 'Organik Domates', 'organik-domates-1', 15.00, 12.00, 100, 4.7, 30, 
 ARRAY['https://images.unsplash.com/photo-1592924357228-91a4daadcfea?w=500&h=500&fit=crop'], true),

((SELECT id FROM shops WHERE slug = 'fresh-market'), 
 (SELECT id FROM categories WHERE slug = 'market'), 
 'Muz Demeti', 'muz-demeti-1', 20.00, 15.00, 50, 4.5, 22, 
 ARRAY['https://images.unsplash.com/photo-1571019614242-c5c5dee9f50b?w=500&h=500&fit=crop'], true),

((SELECT id FROM shops WHERE slug = 'fresh-market'), 
 (SELECT id FROM categories WHERE slug = 'market'), 
 'Taze Salata', 'taze-salata-1', 25.00, 20.00, 40, 4.4, 18, 
 ARRAY['https://images.unsplash.com/photo-1540189549336-e6e99c3679fe?w=500&h=500&fit=crop'], true),

((SELECT id FROM shops WHERE slug = 'fresh-market'), 
 (SELECT id FROM categories WHERE slug = 'market'), 
 'Tavuk Göğsü', 'tavuk-gogsu-1', 45.00, 40.00, 60, 4.8, 56, 
 ARRAY['https://images.unsplash.com/photo-1598103442097-8b74394b95c6?w=500&h=500&fit=crop'], true);

-- 6. Ürünler - Doner King
INSERT INTO products (shop_id, category_id, name, slug, price, discount_price, stock_quantity, rating, total_reviews, images, is_active) 
VALUES
((SELECT id FROM shops WHERE slug = 'doner-king'), 
 (SELECT id FROM categories WHERE slug = 'yemek'), 
 'Tavuk Döner', 'tavuk-doener-1', 50.00, 40.00, 80, 4.8, 145, 
 ARRAY['https://images.unsplash.com/photo-1565299585323-38d6b0865b47?w=500&h=500&fit=crop'], true),

((SELECT id FROM shops WHERE slug = 'doner-king'), 
 (SELECT id FROM categories WHERE slug = 'yemek'), 
 'Kuzu Döner', 'kuzu-doener-1', 60.00, 50.00, 50, 4.9, 167, 
 ARRAY['https://images.unsplash.com/photo-1529193591184-fad821121184?w=500&h=500&fit=crop'], true),

((SELECT id FROM shops WHERE slug = 'doner-king'), 
 (SELECT id FROM categories WHERE slug = 'yemek'), 
 'Adana Kebab', 'adana-kebab-1', 55.00, 45.00, 70, 4.7, 98, 
 ARRAY['https://images.unsplash.com/photo-1599974579688-403dbee266b0?w=500&h=500&fit=crop'], true),

((SELECT id FROM shops WHERE slug = 'doner-king'), 
 (SELECT id FROM categories WHERE slug = 'yemek'), 
 'Falafel Wrap', 'falafel-wrap-1', 35.00, 28.00, 100, 4.6, 72, 
 ARRAY['https://images.unsplash.com/photo-1565299585323-38d6b0865b47?w=500&h=500&fit=crop'], true);
