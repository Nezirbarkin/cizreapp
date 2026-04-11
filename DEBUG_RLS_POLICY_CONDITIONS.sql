-- RLS Policy Debug - Policy'nin koşullarını kontrol et

-- Değişkenler:
-- Shop ID: c569e5cd-ef0d-4241-a8d5-7395e22aa1de
-- Auth UID: a3623ff5-57fd-4529-b03e-44a68629926c
-- Path: shops/c569e5cd-ef0d-4241-a8d5-7395e22aa1de/logo_1769873799213.jpg

-- Test 1: Path split_part kontrol
SELECT 
  'shops/c569e5cd-ef0d-4241-a8d5-7395e22aa1de/logo_1769873799213.jpg'::text as full_path,
  split_part('shops/c569e5cd-ef0d-4241-a8d5-7395e22aa1de/logo_1769873799213.jpg', '/', 1) as part1,
  split_part('shops/c569e5cd-ef0d-4241-a8d5-7395e22aa1de/logo_1769873799213.jpg', '/', 2) as part2,
  split_part('shops/c569e5cd-ef0d-4241-a8d5-7395e22aa1de/logo_1769873799213.jpg', '/', 3) as part3;

-- Test 2: LIKE kontrol
SELECT 
  'shops/c569e5cd-ef0d-4241-a8d5-7395e22aa1de/logo_1769873799213.jpg' LIKE 'shops/%' as matches_pattern;

-- Test 3: Shops query
SELECT 1 FROM shops 
WHERE id::text = 'c569e5cd-ef0d-4241-a8d5-7395e22aa1de' 
AND owner_id::text = 'a3623ff5-57fd-4529-b03e-44a68629926c';

-- Test 4: RLS Policy'nin tam koşulunu test et
SELECT 
  (
    'shop-images' = 'shop-images' AND 
    'shops/c569e5cd-ef0d-4241-a8d5-7395e22aa1de/logo_1769873799213.jpg' LIKE 'shops/%' AND
    EXISTS (
      SELECT 1 FROM shops 
      WHERE id::text = split_part('shops/c569e5cd-ef0d-4241-a8d5-7395e22aa1de/logo_1769873799213.jpg', '/', 2) 
      AND owner_id::text = 'a3623ff5-57fd-4529-b03e-44a68629926c'
    )
  ) as policy_condition_result;
