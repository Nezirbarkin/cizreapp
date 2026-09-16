-- =============================================================================
-- Web Tanıtım — DÖNEN TANITIM MADDELERİ
-- Tarih: 2026-09-08
-- =============================================================================
-- Kullanıcı isteği: tanıtım ekranında sloganın altında, sırayla değişen
-- tanıtım maddeleri olsun ("İlan ver alıcını bul" → "Alışveriş yap kapına
-- gelsin" → ...) ve maddeler admin panelinden eklenip çıkarılabilsin.
--
-- Saklama biçimi: TEK anahtarda, her satır bir madde. Diziyi ayrı satırlara
-- (web_promo_line_1, _2, ...) bölmedik; madde eklemek/çıkarmak o durumda
-- satır ekleyip silmeyi ve sıra numaralarını kaydırmayı gerektirirdi. Admin
-- panelinde alan çok satırlı bir metin kutusu, tanıtım ekranı da satırlara
-- bölerek okur.
--
-- Değerler, tablodaki mevcut konvansiyona uyarak JSON string olarak yazılır.
-- =============================================================================

INSERT INTO public.app_settings (key, value, description)
VALUES
  ('web_promo_rotating_lines',
   to_jsonb(
     E'İlan ver, alıcını bul\n'
     'Alışveriş yap, kapına gelsin\n'
     'Kurye çağır, paketin yola çıksın\n'
     'Şehiriçi otobüsü canlı takip et\n'
     'Komşunla paylaş, sohbete katıl'::text
   ),
   'Tanıtım ekranında sırayla dönen maddeler — her satır bir madde. Boş bırakılırsa şerit hiç gösterilmez.'),

  ('web_promo_rotate_ms', '"2600"',
   'Bir maddenin ekranda kalma süresi (milisaniye). 1200-10000 arası önerilir.')
ON CONFLICT (key) DO NOTHING;
