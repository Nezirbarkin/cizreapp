-- 2) Her dükkan için ürün sayısı
SELECT s.id, s.name, COUNT(p.id) as product_count
FROM shops s
LEFT JOIN products p ON p.shop_id = s.id
GROUP BY s.id, s.name
ORDER BY s.name;
