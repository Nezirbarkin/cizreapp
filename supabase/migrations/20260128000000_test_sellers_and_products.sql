-- ============================================================================
-- CizreApp - Gerçek Satıcı ID'leri için Test Dükkanları ve Ürünleri
-- ============================================================================
-- Satıcı 1: a3623ff5-57fd-4529-b03e-44a68629926c
-- Satıcı 2: c399c2b7-bd00-4f4d-a3f9-5bbc1dd9bbd7
-- ============================================================================

-- Bu script verilen gerçek satıcı ID'leri için dükkanlar ve test ürünleri oluşturur
-- is_approved kolonu yok, sadece is_active ve is_verified kullanılır

-- Önce mevcut test verilerini temizle (isteğe bağlı)
-- DELETE FROM public.products WHERE shop_id IN (
--   SELECT id FROM public.shops WHERE owner_id IN ('a3623ff5-57fd-4529-b03e-44a68629926c', 'c399c2b7-bd00-4f4d-a3f9-5bbc1dd9bbd7')
-- );
-- DELETE FROM public.shops WHERE owner_id IN ('a3623ff5-57fd-4529-b03e-44a68629926c', 'c399c2b7-bd00-4f4d-a3f9-5bbc1dd9bbd7');

DO $$
DECLARE
  v_seller1_id uuid := 'a3623ff5-57fd-4529-b03e-44a68629926c';
  v_seller2_id uuid := 'c399c2b7-bd00-4f4d-a3f9-5bbc1dd9bbd7';
  
  v_shop1_id uuid;
  v_shop2_id uuid;
  
  v_cat_food uuid;
  v_cat_market uuid;
  v_cat_tech uuid;
  v_cat_bakery uuid;
  
  v_user1_exists boolean;
  v_user2_exists boolean;
BEGIN
  -- Kullanıcıların var olup olmadığını kontrol et
  SELECT EXISTS(SELECT 1 FROM auth.users WHERE id = v_seller1_id) INTO v_user1_exists;
  SELECT EXISTS(SELECT 1 FROM auth.users WHERE id = v_seller2_id) INTO v_user2_exists;
  
  IF NOT v_user1_exists THEN
    RAISE NOTICE 'UYARI: Satıcı 1 (a3623ff5-57fd-4529-b03e-44a68629926c) auth.users tablosunda bulunamadı!';
  END IF;
  
  IF NOT v_user2_exists THEN
    RAISE NOTICE 'UYARI: Satıcı 2 (c399c2b7-bd00-4f4d-a3f9-5bbc1dd9bbd7) auth.users tablosunda bulunamadı!';
  END IF;
  
  -- Kategorileri al veya oluştur
  -- Yemek & İçecek
  SELECT id INTO v_cat_food FROM public.categories WHERE slug = 'yemek-icecek' LIMIT 1;
  IF v_cat_food IS NULL THEN
    INSERT INTO public.categories (id, name, slug, description, icon, display_order)
    VALUES (gen_random_uuid(), 'Yemek & İçecek', 'yemek-icecek', 'Restoran ve yemek servisleri', 'utensils', 1)
    RETURNING id INTO v_cat_food;
  END IF;
  
  -- Market & Manav
  SELECT id INTO v_cat_market FROM public.categories WHERE slug = 'market-manav' LIMIT 1;
  IF v_cat_market IS NULL THEN
    INSERT INTO public.categories (id, name, slug, description, icon, display_order)
    VALUES (gen_random_uuid(), 'Market & Manav', 'market-manav', 'Gıda ve yiyecek ürünleri', 'shopping-bag', 2)
    RETURNING id INTO v_cat_market;
  END IF;
  
  -- Teknoloji
  SELECT id INTO v_cat_tech FROM public.categories WHERE slug = 'teknoloji' LIMIT 1;
  IF v_cat_tech IS NULL THEN
    INSERT INTO public.categories (id, name, slug, description, icon, display_order)
    VALUES (gen_random_uuid(), 'Teknoloji', 'teknoloji', 'Elektronik ve teknoloji ürünleri', 'zap', 3)
    RETURNING id INTO v_cat_tech;
  END IF;
  
  -- Fırın & Pastane
  SELECT id INTO v_cat_bakery FROM public.categories WHERE slug = 'firin-pastane' LIMIT 1;
  IF v_cat_bakery IS NULL THEN
    INSERT INTO public.categories (id, name, slug, description, icon, display_order)
    VALUES (gen_random_uuid(), 'Fırın & Pastane', 'firin-pastane', 'Ekmek, pasta ve tatlı ürünleri', 'cake', 4)
    RETURNING id INTO v_cat_bakery;
  END IF;
  
  RAISE NOTICE 'Kategoriler hazır: Yemek=%, Market=%, Teknoloji=%, Fırın=%', v_cat_food, v_cat_market, v_cat_tech, v_cat_bakery;
  
  -- ==============================
  -- SATICI 1 İÇİN DÜKKAN VE ÜRÜNLER
  -- ==============================
  
  -- Mevcut dükkanı kontrol et veya yeni oluştur
  SELECT id INTO v_shop1_id FROM public.shops WHERE owner_id = v_seller1_id LIMIT 1;
  
  IF v_shop1_id IS NULL THEN
    INSERT INTO public.shops (id, owner_id, name, slug, description, category_id, commission_rate, is_active, is_verified)
    VALUES (
      gen_random_uuid(),
      v_seller1_id,
      'Cizre Lezzet Dükkanı',
      'cizre-lezzet-dukkani',
      'En taze ve lezzetli yerel ürünler burada!',
      v_cat_food,
      10.0,
      true,
      true
    )
    RETURNING id INTO v_shop1_id;
    RAISE NOTICE 'Yeni dükkan oluşturuldu (Satıcı 1): %', v_shop1_id;
  ELSE
    RAISE NOTICE 'Mevcut dükkan kullanılıyor (Satıcı 1): %', v_shop1_id;
  END IF;
  
  -- Satıcı 1 için ürünler ekle
  INSERT INTO public.products (shop_id, name, slug, description, price, discount_price, stock_quantity, category_id, images, is_active)
  VALUES
    -- Ana Yemekler
    (v_shop1_id, 'Kebap Tabağı', 'kebap-tabagi', 'Özel sos ile servis edilmiş bir porsiyon kebap', 280.00, 250.00, 50, v_cat_food, ARRAY['https://images.unsplash.com/photo-1603360946369-dc9bb6258143?w=400'], true),
    (v_shop1_id, 'İskender', 'iskender', 'Döner eti, yoğurt, tereyağı ve domates sosu ile', 320.00, 280.00, 40, v_cat_food, ARRAY['https://images.unsplash.com/photo-1596797038530-2c107229654b?w=400'], true),
    (v_shop1_id, 'Adana Kebap', 'adana-kebap', 'Acılı özel harçtır, 5 adet', 200.00, 180.00, 60, v_cat_food, ARRAY['https://images.unsplash.com/photo-1555939594-58d7cb561ad1?w=400'], true),
    
    -- Yan Ürünler
    (v_shop1_id, 'Pilav', 'pilav', 'Tereyağlı yan pilav', 45.00, 40.00, 100, v_cat_food, ARRAY['https://images.unsplash.com/photo-1536304993881-ff6e9eefa2a6?w=400'], true),
    (v_shop1_id, 'Gözleme', 'gozleme', 'Peynirli veya patatesli', 70.00, 60.00, 30, v_cat_food, ARRAY['https://images.unsplash.com/photo-1601050690597-df0568f70950?w=400'], true),
    (v_shop1_id, 'Ayran', 'ayran', 'Ev yapımı doğal ayran', 25.00, 20.00, 80, v_cat_food, ARRAY['https://images.unsplash.com/photo-1571006682580-4eb60929cd63?w=400'], true),
    
    -- Tatlılar
    (v_shop1_id, 'Baklava', 'baklava', 'Fıstıklı special baklava (1 kg)', 400.00, 350.00, 25, v_cat_food, ARRAY['https://images.unsplash.com/photo-1519676867240-f03562e64548?w=400'], true),
    (v_shop1_id, 'Künefe', 'kunefe', 'Sıcak servis, künefe', 140.00, 120.00, 35, v_cat_food, ARRAY['https://images.unsplash.com/photo-1488477181946-6428a0291777?w=400'], true)
  ON CONFLICT DO NOTHING;
  
  RAISE NOTICE 'Satıcı 1 için 8 ürün eklendi.';
  
  -- ==============================
  -- SATICI 2 İÇİN DÜKKAN VE ÜRÜNLER
  -- ==============================
  
  -- Mevcut dükkanı kontrol et veya yeni oluştur
  SELECT id INTO v_shop2_id FROM public.shops WHERE owner_id = v_seller2_id LIMIT 1;
  
  IF v_shop2_id IS NULL THEN
    INSERT INTO public.shops (id, owner_id, name, slug, description, category_id, commission_rate, is_active, is_verified)
    VALUES (
      gen_random_uuid(),
      v_seller2_id,
      'Cizre Fırın & Pastane',
      'cizre-firin-pastane',
      'Taptaze ekmekler ve tatlılar',
      v_cat_bakery,
      12.0,
      true,
      true
    )
    RETURNING id INTO v_shop2_id;
    RAISE NOTICE 'Yeni dükkan oluşturuldu (Satıcı 2): %', v_shop2_id;
  ELSE
    RAISE NOTICE 'Mevcut dükkan kullanılıyor (Satıcı 2): %', v_shop2_id;
  END IF;
  
  -- Satıcı 2 için ürünler ekle
  INSERT INTO public.products (shop_id, name, slug, description, price, discount_price, stock_quantity, category_id, images, is_active)
  VALUES
    -- Ekmekler
    (v_shop2_id, 'Tuzlu Ekmek', 'tuzlu-ekmek', 'Cizre ünlü tuzlu ekmek', 20.00, 15.00, 200, v_cat_bakery, ARRAY['https://images.unsplash.com/photo-1509440159596-0249088772ff?w=400'], true),
    (v_shop2_id, 'Somun Ekmek', 'somun-ekmek', 'Normal somun ekmek', 12.00, 10.00, 300, v_cat_bakery, ARRAY['https://images.unsplash.com/photo-1586444248902-2f64eddc13df?w=400'], true),
    (v_shop2_id, 'Kepekli Ekmek', 'kepekli-ekmek', 'Sağlıklı kepekli ekmek', 15.00, 12.00, 150, v_cat_bakery, ARRAY['https://images.unsplash.com/photo-1509440159596-0249088772ff?w=400'], true),
    
    -- Pastanelik
    (v_shop2_id, 'Çikolatalı Muffin', 'cikolatali-muffin', 'İkili paket', 50.00, 40.00, 40, v_cat_bakery, ARRAY['https://images.unsplash.com/photo-1607958996333-41aef7caefaa?w=400'], true),
    (v_shop2_id, 'Cheesecake', 'cheesecake', 'Limonlu cheesecake dilimi', 75.00, 65.00, 25, v_cat_bakery, ARRAY['https://images.unsplash.com/photo-1567327613485-fbc7bf196198?w=400'], true),
    (v_shop2_id, 'Tiramisu', 'tiramisu', 'İtalyan usulü tiramisu', 95.00, 80.00, 20, v_cat_bakery, ARRAY['https://images.unsplash.com/photo-1571877227200-a0d98ea607e9?w=400'], true),
    
    -- Börekler
    (v_shop2_id, 'Su Böreği', 'su-boregi', 'Yarım tepsi su böreği', 180.00, 150.00, 15, v_cat_bakery, ARRAY['https://images.unsplash.com/photo-1601000938257-93e7e7c8a41d?w=400'], true),
    (v_shop2_id, 'Spin Börek', 'spin-borek', '10lu paket', 70.00, 60.00, 30, v_cat_bakery, ARRAY['https://images.unsplash.com/photo-1601000938257-93e7e7c8a41d?w=400'], true),
    
    -- Kuruyemiş
    (v_shop2_id, 'Antep Fıstığı', 'antep-fistigi', '1 kg güneş kavrulmuş', 500.00, 450.00, 20, v_cat_market, ARRAY['https://images.unsplash.com/photo-1525201548942-d8732f6617a0?w=400'], true),
    (v_shop2_id, 'Ceviz İçi', 'ceviz-ici', '1 kg ceviz içi', 400.00, 350.00, 25, v_cat_market, ARRAY['https://images.unsplash.com/photo-1606722590582-2d9e5c160804?w=400'], true)
  ON CONFLICT DO NOTHING;
  
  RAISE NOTICE 'Satıcı 2 için 10 ürün eklendi.';
  
  RAISE NOTICE '================================================';
  RAISE NOTICE 'İŞLEM TAMAMLANDI!';
  RAISE NOTICE 'Satıcı 1 Dükkan ID: %', v_shop1_id;
  RAISE NOTICE 'Satıcı 2 Dükkan ID: %', v_shop2_id;
  RAISE NOTICE 'Toplam Ürün: 18 adet';
  RAISE NOTICE '================================================';

END $$;

-- Sonuçları görüntüle
SELECT 
  s.id as shop_id,
  s.name as shop_name,
  s.owner_id,
  p.username as owner_username,
  COUNT(pr.id) as product_count,
  s.commission_rate
FROM public.shops s
LEFT JOIN public.profiles p ON s.owner_id = p.id
LEFT JOIN public.products pr ON pr.shop_id = s.id
WHERE s.owner_id IN ('a3623ff5-57fd-4529-b03e-44a68629926c', 'c399c2b7-bd00-4f4d-a3f9-5bbc1dd9bbd7')
GROUP BY s.id, s.name, s.owner_id, p.username, s.commission_rate;
