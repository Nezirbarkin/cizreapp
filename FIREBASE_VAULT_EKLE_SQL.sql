-- =====================================================
-- FIREBASE SERVICE ACCOUNT KEY - SUPABASE VAULT'A EKLE
-- DÜZELTİLMİŞ VERSİYON (İzin hatası düzeltildi)
-- =====================================================
-- Bu SQL'i Supabase SQL Editor'da çalıştırın
-- =====================================================

-- Vault secret'ı ekle (sadece INSERT)
-- Kontrol sorgusunu kaldırdık (SELECT izni yoksa hata veriyordu)

INSERT INTO vault.decrypted_secrets (name, secret, description)
VALUES (
    'firebase_service_account',
    '{"type":"service_account","project_id":"cizreapp-3b9a4","private_key_id":"03c6c22b403c178a634a92932315eb8210378ab2","private_key":"-----BEGIN PRIVATE KEY-----\\nMIIEvwIBADANBgkqhkiG9w0BAQEFAASCBKkwggSlAgEAAoIBAQDFnWWDBUISmuSn\\nn87Awa3OuFuWMtgEMpIfZ9+QAo/bOGp8Asn518y0N9cD5xDTmCSubm026rhIyoa+\\nUVt/21JOBOlHNAYmm7ogg776Oy3uxEtGLj8m29qADiV1PVFBlRSUPewetY8WcdVX\\nwUabn2cUg3AV7GlctN3KsliqUfYN7CZ3J1hEEpTh/YaTGDYHX9DokRWES4MSqh35\\nysiS3UC7qCW+A/ENt3YTDcKCcmy28CDFduoe8BKH5uECspy6adSmsV2OBjI6kujd\\n/HvHw/kFbrUwKCqQRh7WS7gsdQFSDPYnsOiNnXX0KKli4g7CPXFFMQ8NH1j6ZwM7\\nC/Z4htRDAgMBAAECggEANYCVPMFeL6pXENkQAZkOZSL9zO8MFCra6/zUBunip+Ag\\n2F1q8KVQC1T49loHcLpG6CEGmbE33qFSlNFzG+013eCvhfMcXTSZUndI6/e8ymHD\\n3Ybk2zD3+eaalqDY0JA7x5zyQig2ysVcFQvDgZvJLUEexhjBN/PR/rCFl+tj2kWk\\nM29ZirTOamwRkUpQw5e5HfvhukYBliNGMRXARaP1d4EmTjRF5/bvmaoOQud+JqM5\\naTWLxopg5kYa++QJh04KE1xiqOn3prMaR39Z23gajxemAkHJtePaP2lbSjMYlSza\\nhqSm+lOxscc2Tl1jWXx3ejiomqvhjyamiryr/vuMCQKBgQD+oIPMboRSr/3+uXq8\\nQhXhp5DCek2KAK5fFtV5XZqrnJPEr/9BvQ/oQ3ejFW2VFoktpMjTldCU71vZtvI4\\n/lG7Qs2IkbJ1/do7UyFt+YT4Js9z41QN39hXB+sZb77G2llnR0kH/dyqMnUSnz1Y\\n2mk6ev3lF1Yc5/o5Px/cCM+d+wKBgQDGri65ec3eezoOqI4WbeKg3VV7RM2//eFW\\nhmPi4rNmN5OMdKvM989udwpnoz4BJ7jzE/+kOQgu7uaVbn5PtDkIS2909tXhaHZ/\\nb9Z0G9M2d1SRaXTPQKQkfJWpObHH0fooYaPwPrAcHrgRSpdY6bM0JZdGGqCyRXtj\\nHYdfQT44WQKBgQDVBRy+bsctFid8b1gLH46G1lT5HrC3/5Hh44x8mJ7Ja5kEN+lo\\n6e7g9XClc0vWKqBhGzcYLIHv18AUCEXlAH8IFv80fg+7PsDQWN/izZk8sdtkrI6p\\nfNfVF77L7PzCB/I7wRuMIAn4KXZgOfBs4WyfjD3U5w0X6cshEXpp7sUi+QKBgQCg\\nLewjwwz0MvsiuEgd0yfks61oPZd4E5Jp9N1xHX6viV0e3y1nid8l2zl7RsQFoGXf\\nLB9t4kEzvY4Pqc6SKeXVRyQr85mKKnNm2N7YK1rEzb5Toeb39NChTgRHM+meBS8f\\nAWFvnsrTUPzri+yrVXcSMsBcV7l5IMWSqkrqxCoKuQKBgQDafwEBJqXah33mUv5u\\n9WRNn643x0otj1nkUZcEsZul0wj2KKv5aa8Dckk+2v43apyzCUc27PZws+PdXJfN\\n/hfU0+kkDdi+mgJyiYioRIQxbmuoOgYJb3qxZdlzNtuRdR7Xjloc01UUO+Q2Zoro\\nZBFKEHZKI0oAX6lQJUnbbZjyNw==\\n-----END PRIVATE KEY-----\\n","client_email":"firebase-adminsdk-fbsvc@cizreapp-3b9a4.iam.gserviceaccount.com","client_id":"104512470039956069367","auth_uri":"https://accounts.google.com/o/oauth2/auth","token_uri":"https://oauth2.googleapis.com/token","auth_provider_x509_cert_url":"https://www.googleapis.com/oauth2/v1/certs","client_x509_cert_url":"https://www.googleapis.com/robot/v1/metadata/x509/firebase-adminsdk-fbsvc%40cizreapp-3b9a4.iam.gserviceaccount.com","universe_domain":"googleapis.com"}'::jsonb,
    'Firebase FCM Service Account for Push Notifications'
)
ON CONFLICT (name) DO UPDATE SET 
    secret = EXCLUDED.secret,
    updated_at = NOW();

-- =====================================================
-- TAMAMLANDI!
-- =====================================================
-- Firebase Service Account Key vault'a eklendi.
-- Şimdi push notification fonksiyonu çalışacak!
-- 
-- Eğer yine hata verirse: Supabase Dashboard → 
-- SQL Editor → Hamburger Menu → "Vault" → Secrets
-- Oradan manuel olarak ekleyebilirsin.
