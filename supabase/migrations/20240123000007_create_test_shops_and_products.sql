-- ============================================================================
-- CizreApp - Test Satıcı, Ürünler ve Kategoriler
-- ============================================================================
-- Bu migration test amaçlı satıcı, ürünler ve kategorileri oluşturur
-- ============================================================================

-- 1. Kategoriler oluştur (gen_random_uuid() kullanarak)
DO $$
BEGIN
  -- Yemek & İçecek
  INSERT INTO public.categories (id, name, slug, description, icon)
  VALUES (gen_random_uuid(), 'Yemek & İçecek', 'yemek-icecek', 'Restoran ve yemek servisleri', 'utensils')
  ON CONFLICT DO NOTHING;
  
  -- Market & Manav
  INSERT INTO public.categories (id, name, slug, description, icon)
  VALUES (gen_random_uuid(), 'Market & Manav', 'market-manav', 'Gıda ve yiyecek ürünleri', 'shopping-bag')
  ON CONFLICT DO NOTHING;
  
  -- Teknoloji
  INSERT INTO public.categories (id, name, slug, description, icon)
  VALUES (gen_random_uuid(), 'Teknoloji', 'teknoloji', 'Elektronik ve teknoloji ürünleri', 'zap')
  ON CONFLICT DO NOTHING;
  
  -- Moda
  INSERT INTO public.categories (id, name, slug, description, icon)
  VALUES (gen_random_uuid(), 'Moda', 'moda', 'Giyim ve aksesuar', 'shopping-bag')
  ON CONFLICT DO NOTHING;
END $$;

-- 2. Test satıcılar oluştur
DO $$
DECLARE
  v_user_id uuid;
  v_cat_food uuid;
  v_cat_market uuid;
  v_cat_tech uuid;
BEGIN
  -- Mevcut kullanıcı varsa kullan, yoksa skip et
  SELECT id INTO v_user_id FROM auth.users LIMIT 1;
  
  IF v_user_id IS NULL THEN
    RAISE NOTICE 'No user found, skipping shop creation';
    RETURN;
  END IF;
  
  -- Kategori ID'lerini al
  SELECT id INTO v_cat_food FROM public.categories WHERE name = 'Yemek & İçecek' LIMIT 1;
  SELECT id INTO v_cat_market FROM public.categories WHERE name = 'Market & Manav' LIMIT 1;
  SELECT id INTO v_cat_tech FROM public.categories WHERE name = 'Teknoloji' LIMIT 1;
  
  -- Pizza Palace
  INSERT INTO public.shops (
    id, owner_id, category_id, name, slug, description, logo_url, banner_url,
    phone, address, is_open, rating, total_reviews, total_orders,
    working_hours, commission_rate, created_at, updated_at
  ) VALUES (
    gen_random_uuid(), v_user_id, v_cat_food,
    'Pizza Palace', 'pizza-palace', 'Cizre''nin en leziz pizzaları burada! 🍕',
    'https://images.unsplash.com/photo-1565299585323-38d6b0865b47?w=400',
    'https://images.unsplash.com/photo-1565299585323-38d6b0865b47?w=800',
    '+90 (384) 123-4567', 'Cizre, Yafes Mahallesi, Halkay Caddesi No: 45',
    true, 4.8, 245, 1280,
    '{"openTime": "11:00", "closeTime": "23:00", "days": ["Pazartesi", "Salı", "Çarşamba", "Perşembe", "Cuma", "Cumartesi", "Pazar"]}'::jsonb,
    15.0, NOW(), NOW()
  ) ON CONFLICT DO NOTHING;
  
  -- Cizre Kebapçısı
  INSERT INTO public.shops (
    id, owner_id, category_id, name, slug, description, logo_url, banner_url,
    phone, address, is_open, rating, total_reviews, total_orders,
    working_hours, commission_rate, created_at, updated_at
  ) VALUES (
    gen_random_uuid(), v_user_id, v_cat_food,
    'Cizre Kebapçısı', 'cizre-kebapcisi', 'Geleneksel Cizre kebapları ve mezeler 🔥',
    'https://images.unsplash.com/photo-1555939594-58d7cb561ad1?w=400',
    'https://images.unsplash.com/photo-1555939594-58d7cb561ad1?w=800',
    '+90 (384) 234-5678', 'Cizre, Sanat Sokağı No: 12',
    true, 4.9, 312, 2150,
    '{"openTime": "10:00", "closeTime": "23:30", "days": ["Pazartesi", "Salı", "Çarşamba", "Perşembe", "Cuma", "Cumartesi", "Pazar"]}'::jsonb,
    12.0, NOW(), NOW()
  ) ON CONFLICT DO NOTHING;
  
  -- Cizre Market
  INSERT INTO public.shops (
    id, owner_id, category_id, name, slug, description, logo_url, banner_url,
    phone, address, is_open, rating, total_reviews, total_orders,
    working_hours, commission_rate, created_at, updated_at
  ) VALUES (
    gen_random_uuid(), v_user_id, v_cat_market,
    'Cizre Market', 'cizre-market', 'Taze ve kaliteli market ürünleri 🛒',
    'https://images.unsplash.com/photo-1534723452862-a8a6d0f88505?w=400',
    'https://images.unsplash.com/photo-1534723452862-a8a6d0f88505?w=800',
    '+90 (384) 345-6789', 'Cizre, Gazipaşa Caddesi No: 78',
    true, 4.6, 189, 890,
    '{"openTime": "08:00", "closeTime": "22:00", "days": ["Pazartesi", "Salı", "Çarşamba", "Perşembe", "Cuma", "Cumartesi", "Pazar"]}'::jsonb,
    10.0, NOW(), NOW()
  ) ON CONFLICT DO NOTHING;
  
  -- Tekno Cizre
  INSERT INTO public.shops (
    id, owner_id, category_id, name, slug, description, logo_url, banner_url,
    phone, address, is_open, rating, total_reviews, total_orders,
    working_hours, commission_rate, created_at, updated_at
  ) VALUES (
    gen_random_uuid(), v_user_id, v_cat_tech,
    'Tekno Cizre', 'tekno-cizre', 'Teknoloji ve elektronik ürünleri 💻',
    'https://images.unsplash.com/photo-1505428346881-b72b27e84530?w=400',
    'https://images.unsplash.com/photo-1505428346881-b72b27e84530?w=800',
    '+90 (384) 456-7890', 'Cizre, Cumhuriyet Caddesi No: 34',
    true, 4.7, 156, 542,
    '{"openTime": "09:00", "closeTime": "21:00", "days": ["Pazartesi", "Salı", "Çarşamba", "Perşembe", "Cuma", "Cumartesi", "Pazar"]}'::jsonb,
    18.0, NOW(), NOW()
  ) ON CONFLICT DO NOTHING;
  
END $$;

-- 3. Ürünler oluştur
DO $$
DECLARE
  v_shop_pizza uuid;
  v_shop_kebab uuid;
  v_shop_market uuid;
  v_shop_tech uuid;
  v_cat_food uuid;
  v_cat_market uuid;
  v_cat_tech uuid;
BEGIN
  -- Shop ve kategori ID'lerini al
  SELECT id INTO v_shop_pizza FROM public.shops WHERE name = 'Pizza Palace' LIMIT 1;
  SELECT id INTO v_shop_kebab FROM public.shops WHERE name = 'Cizre Kebapçısı' LIMIT 1;
  SELECT id INTO v_shop_market FROM public.shops WHERE name = 'Cizre Market' LIMIT 1;
  SELECT id INTO v_shop_tech FROM public.shops WHERE name = 'Tekno Cizre' LIMIT 1;
  SELECT id INTO v_cat_food FROM public.categories WHERE name = 'Yemek & İçecek' LIMIT 1;
  SELECT id INTO v_cat_market FROM public.categories WHERE name = 'Market & Manav' LIMIT 1;
  SELECT id INTO v_cat_tech FROM public.categories WHERE name = 'Teknoloji' LIMIT 1;
  
  IF v_shop_pizza IS NULL THEN
    RAISE NOTICE 'No shops found, skipping product creation';
    RETURN;
  END IF;
  
  -- Pizza Palace ürünleri
  -- shop_id, name, slug, description, price, old_price, stock_quantity, image_url, category, is_available
  INSERT INTO public.products (id, shop_id, name, slug, description, price, old_price, stock_quantity, image_url, category, is_available, created_at, updated_at)
  VALUES
    (gen_random_uuid(), v_shop_pizza, 'Pizza Margarita', 'pizza-margarita', 'Mozzarella, domates, fesleğen', 200.0, 220.0, 50, 'https://images.unsplash.com/photo-1604068549290-dea0e4a305ca?w=600', 'Pizza', true, NOW(), NOW()),
    (gen_random_uuid(), v_shop_pizza, 'Pizza Pepperoni', 'pizza-pepperoni', 'Mozzarella, pepperoni, domates', 220.0, NULL, 40, 'https://images.unsplash.com/photo-1628840042765-356cda07f4ee?w=600', 'Pizza', true, NOW(), NOW()),
    (gen_random_uuid(), v_shop_pizza, 'Pizza Karışık Etler', 'pizza-karisik-etler', 'Sucuk, sosis, bacon, mozzarella', 280.0, 330.0, 35, 'https://images.unsplash.com/photo-1604068549290-dea0e4a305ca?w=600', 'Pizza', true, NOW(), NOW()),
    (gen_random_uuid(), v_shop_pizza, 'Pizza Vegetaryen', 'pizza-vegetaryen', 'Domates, biber, mantar, misır', 190.0, 240.0, 45, 'https://images.unsplash.com/photo-1511689534069-e773e4c5d564?w=600', 'Pizza', true, NOW(), NOW())
  ON CONFLICT DO NOTHING;
  
  -- Cizre Kebapçısı ürünleri
  INSERT INTO public.products (id, shop_id, name, slug, description, price, old_price, stock_quantity, image_url, category, is_available, created_at, updated_at)
  VALUES
    (gen_random_uuid(), v_shop_kebab, 'Beyti Kebabı', 'beyti-kebabi', 'Özel soslu, soğan ve domates eşliğinde', 320.0, NULL, 60, 'https://images.unsplash.com/photo-1555939594-58d7cb561ad1?w=600', 'Kebap', true, NOW(), NOW()),
    (gen_random_uuid(), v_shop_kebab, 'Adana Kebabı', 'adana-kebabi', 'Acılı, kırmızı et ve baharat karışımı', 280.0, NULL, 55, 'https://images.unsplash.com/photo-1529042410759-822ace1c3de5?w=600', 'Kebap', true, NOW(), NOW()),
    (gen_random_uuid(), v_shop_kebab, 'İskender Kebabı', 'iskender-kebabi', 'Döner, pide ve yoğurt', 300.0, 315.0, 50, 'https://images.unsplash.com/photo-1585238341710-4913a2e21c5d?w=600', 'Kebap', true, NOW(), NOW()),
    (gen_random_uuid(), v_shop_kebab, 'Karışık Izgara', 'karisik-izgara', 'Tavuk şiş, köfte, soğan', 380.0, 420.0, 40, 'https://images.unsplash.com/photo-1609501676725-7186f017a4b8?w=600', 'Kebap', true, NOW(), NOW())
  ON CONFLICT DO NOTHING;
  
  -- Cizre Market ürünleri
  INSERT INTO public.products (id, shop_id, name, slug, description, price, old_price, stock_quantity, image_url, category, is_available, created_at, updated_at)
  VALUES
    (gen_random_uuid(), v_shop_market, 'Süt (1 Litre)', 'sut-1-litre', 'Pastörize, tam yağlı süt', 45.0, NULL, 100, 'https://images.unsplash.com/photo-1563636619-e7db3814b5df?w=600', 'Süt Ürünleri', true, NOW(), NOW()),
    (gen_random_uuid(), v_shop_market, 'Beyaz Peynir (500g)', 'beyaz-peynir-500g', 'Taze, lezzetli beyaz peynir', 120.0, 140.0, 80, 'https://images.unsplash.com/photo-1589985643862-18443d7d4e15?w=600', 'Peynir', true, NOW(), NOW()),
    (gen_random_uuid(), v_shop_market, 'Ekmek (Taze Pide)', 'ekmek-taze-pide', 'Her sabah taze pişirilen pide', 15.0, NULL, 200, 'https://images.unsplash.com/photo-1599599810694-b5ac4dd77c86?w=600', 'Ekmek', true, NOW(), NOW()),
    (gen_random_uuid(), v_shop_market, 'Domates (1kg)', 'domates-1kg', 'Taze, kırmızı domates', 35.0, 40.0, 150, 'https://images.unsplash.com/photo-1592921870789-04563e271aff?w=600', 'Sebze', true, NOW(), NOW())
  ON CONFLICT DO NOTHING;
  
  -- Tekno Cizre ürünleri
  INSERT INTO public.products (id, shop_id, name, slug, description, price, old_price, stock_quantity, image_url, category, is_available, created_at, updated_at)
  VALUES
    (gen_random_uuid(), v_shop_tech, 'Smartphone XYZ 256GB', 'smartphone-xyz-256gb', '6.5" ekran, 5000mAh batarya', 8990.0, NULL, 20, 'https://images.unsplash.com/photo-1511707267537-b85faf00021e?w=600', 'Telefon', true, NOW(), NOW()),
    (gen_random_uuid(), v_shop_tech, 'Bluetooth Kulaklık', 'bluetooth-kulaklik', 'Gürültü iptal, 30 saat batarya', 450.0, 560.0, 35, 'https://images.unsplash.com/photo-1505740420928-5e560c06d30e?w=600', 'Kulaklık', true, NOW(), NOW()),
    (gen_random_uuid(), v_shop_tech, 'Power Bank 20000mAh', 'power-bank-20000mah', 'Hızlı şarj, kompakt tasarım', 280.0, NULL, 50, 'https://images.unsplash.com/photo-1609091839311-d5365f9ff1c5?w=600', 'Şarj Cihazı', true, NOW(), NOW()),
    (gen_random_uuid(), v_shop_tech, 'USB-C Kablo (2 Metre)', 'usb-c-kablo-2-metre', 'Dayanıklı, hızlı veri transferi', 45.0, 50.0, 100, 'https://images.unsplash.com/photo-1595612007812-4b8400ce2628?w=600', 'Kablo', true, NOW(), NOW())
  ON CONFLICT DO NOTHING;
  
END $$;

-- ============================================================================
-- MIGRATION COMPLETE
-- ============================================================================
-- Test satıcılar, ürünler ve kategoriler başarıyla oluşturuldu.
-- Kategorilere tıklanabilir ve o kategoriye ait satıcılar gösterilecektir.
-- ============================================================================
