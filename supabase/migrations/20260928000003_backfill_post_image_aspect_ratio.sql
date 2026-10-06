-- =============================================================================
-- 20260928000003_backfill_post_image_aspect_ratio.sql
-- -----------------------------------------------------------------------------
-- Görev 2.8 — mevcut fotoğraflı gönderilerin çerçeve oranı (image_aspect_ratio).
--
-- 2026-09-28 ölçümü: fotoğraflı 90 gönderinin İLK görseli indirilip
-- gerçek boyutu okundu (PIL; EXIF yönü uygulanmış — hiçbirinde döndürme yoktu).
-- Oran = genişlik/yükseklik, akışın çizdiği aralığa [0.8, 1.91] sıkıştırılmış.
-- Çoklu fotoğraflı gönderide çerçeveyi ilk fotoğraf belirler (akış da öyle çizer).
--
-- Yalnızca hâlâ NULL olan satırlar güncellenir (tekrar çalıştırmak güvenli).
-- updated_at DEĞİŞMESİN diye BEFORE UPDATE tetikleyicisi bu işlem boyunca
-- kapatılır; bu bir düzenleme değil, eksik ölçünün doldurulmasıdır.
-- =============================================================================

BEGIN;

SET LOCAL lock_timeout = '10s';

ALTER TABLE public.posts DISABLE TRIGGER update_posts_updated_at;

UPDATE public.posts AS p
   SET image_aspect_ratio = v.ratio
  FROM (VALUES
  ('fc2f4d81-a2f8-49be-9bf5-25e394ff70c2'::uuid, 1.0000::real), -- 1080x1080
  ('59e01d39-7a19-4e03-90c2-c9fec156e501'::uuid, 1.0000::real), -- 1080x1080
  ('a4f05f4d-c5a7-4788-aa3c-374a5d278ce7'::uuid, 1.0000::real), -- 1080x1080
  ('7a6dae5f-53ed-4be4-8780-5dcbb7b03056'::uuid, 1.0000::real), -- 1080x1080
  ('e9c543aa-edfc-4823-b0d9-b73661ca6fb7'::uuid, 1.0000::real), -- 1080x1080
  ('5026c2b8-e44e-4524-b414-186e0849ec0a'::uuid, 1.0000::real), -- 1080x1080
  ('30d064f7-9e88-41b6-9811-d7dfde30d0d8'::uuid, 1.0000::real), -- 1080x1080
  ('d6a9b337-f4ac-40b6-8053-669a9bb73897'::uuid, 1.0000::real), -- 1080x1080
  ('a4319c30-ba15-4847-9cbc-b6fe64c3d4da'::uuid, 1.0000::real), -- 1080x1080
  ('d6d21734-5499-4d01-89af-e13b7ace6606'::uuid, 1.0000::real), -- 1080x1080
  ('fb983b57-a64a-4682-9d43-2907697c0946'::uuid, 1.0000::real), -- 1080x1080
  ('9d11512d-3adf-487e-ad6f-84868695fa8a'::uuid, 1.0000::real), -- 1080x1080
  ('65673f88-1760-4780-8c5e-ed60843f420e'::uuid, 1.0000::real), -- 1080x1080
  ('46f93ba1-1585-4a0c-9439-ed36bf9c602d'::uuid, 1.0000::real), -- 1080x1080
  ('918169f6-4df7-4db7-8f19-d6a391a2fbc5'::uuid, 1.0000::real), -- 1080x1080
  ('03fa0e2a-0a4a-46eb-aa19-d5f510d34244'::uuid, 1.0000::real), -- 1080x1080
  ('1a567ba1-bc90-471c-a342-8ef0bd8939c5'::uuid, 1.0000::real), -- 1080x1080
  ('6503bcd2-e5f1-45a9-a85e-1cc75b1e50e0'::uuid, 0.8000::real), -- 1440x1920
  ('eae90200-46f5-43ea-bce3-ff772232e191'::uuid, 0.8000::real), -- 1440x1920
  ('2b33ab97-3681-4f71-b04d-b078da32cf62'::uuid, 1.0000::real), -- 1080x1080
  ('3fa6f4b7-91e8-4171-ad90-a0bdab8dbfdd'::uuid, 1.0000::real), -- 1080x1080
  ('652c495d-b5e7-46f9-b279-e7cb33ed7802'::uuid, 1.0000::real), -- 1080x1080
  ('efbb3301-2ae5-4491-b43b-7b6de36eadec'::uuid, 0.8000::real), -- 1440x1920
  ('ff4774ec-fed7-431c-b508-1574892d4557'::uuid, 0.8000::real), -- 1440x1920
  ('d564e1f2-a528-4c9e-b19a-805ed9558c46'::uuid, 0.8000::real), -- 1080x1920
  ('fbb70483-6e19-4e95-b042-05b3090ffa4d'::uuid, 1.0000::real), -- 1080x1080
  ('181ca831-4bd2-4f0a-83c5-590a4960bd55'::uuid, 0.8000::real), -- 720x931
  ('628fd3c9-9f08-4312-a49b-9686f5d6b35e'::uuid, 0.8000::real), -- 720x943
  ('f0eea5fa-6d80-4b8e-a47b-940f610de75e'::uuid, 0.8000::real), -- 720x1640
  ('87fce373-2228-455d-a7cf-27649282432b'::uuid, 0.8000::real), -- 720x1640
  ('092f72ad-2531-4908-95c5-aaf660235f10'::uuid, 0.8000::real), -- 720x1640
  ('cae5435e-0bcf-4b49-b7a5-4510136d9014'::uuid, 0.8385::real), -- 1220x1455
  ('38e91155-0223-4b66-aace-8e6a727a67f9'::uuid, 1.0000::real), -- 1080x1080
  ('9418c17b-bf3e-4859-8b1a-e2908cb1b4e5'::uuid, 1.9100::real), -- 1600x800
  ('10c3903b-dba7-4c0e-90c1-824baf2649a3'::uuid, 0.8000::real), -- 1320x1847
  ('7d4e2bf1-7400-4b69-9a4d-436a6e6751f3'::uuid, 0.8000::real), -- 1080x1920
  ('fff1d8a9-6ec9-4233-acde-f4b5f1d08066'::uuid, 0.8000::real), -- 1440x1920
  ('e0f55a93-c9ab-4a59-9554-288e3a18526e'::uuid, 1.0000::real), -- 1080x1080
  ('cbab1cc6-83ae-47c9-8c6a-f0bc38683e5c'::uuid, 0.8000::real), -- 1024x1536
  ('442d709b-85d7-4021-af94-e0b5ff2c2105'::uuid, 0.8000::real), -- 1080x1920
  ('881bf786-58ea-4679-84cc-c5f2478a597b'::uuid, 0.8725::real), -- 1129x1294
  ('c8e6d1fd-41da-43cd-a65f-5188509dacec'::uuid, 1.0511::real), -- 720x685
  ('258a1b43-6f74-41fb-8519-25dd9b0490a4'::uuid, 0.8000::real), -- 1440x1920
  ('bbb122d1-c5db-4dc7-a64c-2e15dffd323e'::uuid, 0.8000::real), -- 1440x1920
  ('5ea70acb-a28f-4f0c-840b-6025d6041b3c'::uuid, 0.8000::real), -- 1440x1920
  ('2012f65a-9882-44f1-87c8-0c9fb98ed81a'::uuid, 1.0000::real), -- 554x554
  ('9c381fa9-8db8-42a1-ac10-c0e089269d2a'::uuid, 1.4172::real), -- 890x628
  ('e8a1103f-00d4-4e6e-a40b-624b4fa9d1bb'::uuid, 1.0000::real), -- 1080x1080
  ('5bd32da6-fac1-4bff-84cd-8d509bde647c'::uuid, 0.8000::real), -- 720x1640
  ('2c6514e4-3720-4fe1-81f4-308dda7e6d6a'::uuid, 1.4802::real), -- 635x429
  ('236eba93-7276-4b71-9f2a-19e3a4b1ab7c'::uuid, 0.8649::real), -- 480x555
  ('86095235-4f55-4ea6-951c-f65845f092bf'::uuid, 0.8000::real), -- 720x1640
  ('1a77149b-f1c5-43b6-91f8-26d5d2b50ad8'::uuid, 1.0000::real), -- 1080x1080
  ('f5ac9a15-88cc-4411-87dd-273d214f5f78'::uuid, 1.0000::real), -- 1080x1080
  ('8a33f607-62e9-4883-9cad-97697d060d6d'::uuid, 1.0000::real), -- 1080x1080
  ('6e75f7a7-7889-4979-a5e6-799d539867f3'::uuid, 1.0000::real), -- 1080x1080
  ('8ba6a735-ea77-4505-a60d-e0404f90f4bc'::uuid, 1.0000::real), -- 1080x1080
  ('55f57fc8-89fa-4b79-addc-4c166f06730f'::uuid, 0.8000::real), -- 1080x1920
  ('59d7a37a-551e-4a7c-bfe0-733824791058'::uuid, 1.0000::real), -- 1080x1080
  ('d0947cf4-0b10-4d28-aa5a-26489582dd26'::uuid, 1.0000::real), -- 1080x1080
  ('9120ef7b-952b-4464-94ac-7a5afdfd0a18'::uuid, 1.0000::real), -- 1080x1080
  ('6bc73e5e-bd0d-4874-a1bf-b16654fbfc7a'::uuid, 1.0000::real), -- 1080x1080
  ('bdca3880-caca-4679-aed4-bf621a860b97'::uuid, 1.0000::real), -- 1080x1080
  ('f44e4488-3de8-47ca-ae84-8288cb31652f'::uuid, 1.0000::real), -- 1080x1080
  ('c31769fa-0e6f-43ff-92cc-22015733dcf8'::uuid, 1.0000::real), -- 1080x1080
  ('14f40294-b420-48d7-a599-3a394e8debbf'::uuid, 1.0000::real), -- 1080x1080
  ('9b658212-4963-448d-becb-f4777ff03e81'::uuid, 1.0000::real), -- 1080x1080
  ('ad7d92fd-e81a-4682-9df3-cc9fc26404a1'::uuid, 1.0000::real), -- 1080x1080
  ('ff9ce281-417e-4b46-b1e8-7e261f5d2210'::uuid, 1.0000::real), -- 1080x1080
  ('ade8c41b-256c-403a-aa0a-70961c2adf87'::uuid, 0.8000::real), -- 1020x1866
  ('b010cf66-d275-4c12-9997-6e7628011c35'::uuid, 0.8000::real), -- 1081x1920
  ('f9387db7-5fbe-4215-b4a1-1c55f0f9c2dc'::uuid, 1.0000::real), -- 1080x1080
  ('541d59f1-eca7-464f-a755-d73f2d58bd87'::uuid, 1.0000::real), -- 1080x1080
  ('3a02a069-a7ab-4b11-8d92-b873a95fcc49'::uuid, 1.6999::real), -- 1280x753
  ('be0be93a-e151-4260-9890-9d47fa834893'::uuid, 0.8000::real), -- 1440x1920
  ('b1a6c2ca-6c2d-49a3-aa1f-e04328dd7fcc'::uuid, 0.8000::real), -- 1440x1920
  ('eb67d227-f344-46bb-820a-69c519047b17'::uuid, 0.8000::real), -- 1440x1920
  ('cc9bd366-7846-4511-bc75-23c264d3bf16'::uuid, 0.8000::real), -- 1440x1920
  ('6557638c-6647-4f9d-b650-2653d6aa5324'::uuid, 0.8000::real), -- 1086x1448
  ('b9b09930-57cd-4bb5-9c8e-68fec41e47f7'::uuid, 0.8000::real), -- 1080x1920
  ('82aea08e-f076-437f-a3c2-0c1a42bcae66'::uuid, 0.8000::real), -- 1024x1820
  ('d73f6a1f-91fd-4031-8b3c-32f17795fe6b'::uuid, 0.8000::real), -- 1080x1920
  ('631f0784-5a64-474d-bf83-95a847db18a6'::uuid, 0.8000::real), -- 720x1280
  ('0fbc369c-11db-4812-9913-740acca71f1e'::uuid, 0.8000::real), -- 720x1280
  ('f2f1dadc-2155-439a-9998-111667dd3ce2'::uuid, 0.8000::real), -- 1080x1920
  ('7fdefa7c-8f1e-430a-bf68-49a3dad30506'::uuid, 0.8000::real), -- 720x1280
  ('54532079-92a8-4af5-a5b5-c664a7d01cce'::uuid, 0.8000::real), -- 1440x1920
  ('161e1a53-e4c2-4d08-879b-5cfafdebe960'::uuid, 0.8000::real), -- 1440x1920
  ('561e2c29-4fcd-4967-aece-0a74212784db'::uuid, 1.0000::real), -- 1920x1920
  ('61e1e758-8e6c-4c85-a74b-62a16bd221cd'::uuid, 0.8000::real) -- 1440x1920
  ) AS v(id, ratio)
 WHERE p.id = v.id
   AND p.image_aspect_ratio IS NULL;

ALTER TABLE public.posts ENABLE TRIGGER update_posts_updated_at;

COMMIT;
