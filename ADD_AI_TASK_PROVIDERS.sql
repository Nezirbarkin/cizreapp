-- =====================================================
-- AI SETTINGS: GÖREVE ÖZEL SAĞLAYICI + POLLINATIONS/HUGGINGFACE
-- =====================================================
-- Geriye dönük uyumlu: mevcut tek "provider" değerini
-- text/vision/image sağlayıcılarına yayar, varsayılan pollinations.
-- Sadece kolon ekler; mevcut verilere dokunmaz.
-- =====================================================

-- 1) text_provider / vision_provider / image_provider kolonları
alter table ai_settings
  add column if not exists text_provider text;
alter table ai_settings
  add column if not exists vision_provider text;
alter table ai_settings
  add column if not exists image_provider text;

-- 2) Pollinations modelleri (ücretsiz, anahtarsız)
alter table ai_settings
  add column if not exists pollinations_text_model text default 'openai';
alter table ai_settings
  add column if not exists pollinations_image_model text default 'flux';

-- 3) HuggingFace inference modeli (ücretsiz)
alter table ai_settings
  add column if not exists huggingface_text_model text default 'meta-llama/Llama-3.2-3B-Instruct';
alter table ai_settings
  add column if not exists huggingface_api_key text;

-- 4) Eski "provider" değerini yeni kolonlara yayıla (sadece NULL satırlar)
--    Yeni satırlar için varsayılan pollinations.
do $$
begin
  if exists (select 1 from information_schema.columns
            where table_name = 'ai_settings' and column_name = 'provider') then
    -- text_provider null ise provider veya pollinations ata
    update ai_settings set text_provider = coalesce(text_provider, provider, 'pollinations')
      where text_provider is null;
    update ai_settings set vision_provider = coalesce(vision_provider, provider, 'pollinations')
      where vision_provider is null;
    update ai_settings set image_provider = coalesce(image_provider, provider, 'pollinations')
      where image_provider is null;

    -- Hiç satır yoksa seed ekle
    if not exists (select 1 from ai_settings where id = 1) then
      insert into ai_settings (
        id, enabled, provider,
        text_provider, vision_provider, image_provider,
        text_model, vision_model, image_model,
        groq_text_model, groq_vision_model,
        openrouter_text_model, openrouter_vision_model, openrouter_image_model,
        openai_text_model, openai_vision_model, openai_image_model,
        pollinations_text_model, pollinations_image_model,
        huggingface_text_model,
        daily_request_limit_per_user, daily_token_limit_per_user,
        max_messages_per_conversation,
        allow_image_upload, allow_image_generation, allow_camera_capture,
        system_prompt, temperature, max_output_tokens
      ) values (
        1, true, 'pollinations',
        'pollinations', 'pollinations', 'pollinations',
        'gemini-2.0-flash', 'gemini-2.0-flash', 'imagen-3.0-generate-002',
        'llama-3.3-70b-versatile', 'llama-3.2-90b-vision-preview',
        'google/gemini-2.0-flash-exp:free', 'google/gemini-2.0-flash-exp:free', 'stable-diffusion-xl',
        'gpt-4o-mini', 'gpt-4o-mini', 'dall-e-3',
        'openai', 'flux',
        'meta-llama/Llama-3.2-3B-Instruct',
        50, 100000, 100,
        true, true, true,
        '', 0.7, 2048
      );
    end if;
  end if;
end $$;

-- 5) provider kolonu artık opsiyonel - default pollinations
--    (varsa koru, yoksa dokunma)
do $$
begin
  if exists (select 1 from information_schema.columns
            where table_name = 'ai_settings' and column_name = 'provider'
            and column_default is null) then
    -- RLS/policy'ye dokunmadan sadece default ekle
    alter table ai_settings alter column provider set default 'pollinations';
  end if;
end $$;

-- Not: Bu migration mevcut RLS/policy/trigger/storage yapılarını bozmaz.
-- Sadece yeni kolon ekler ve (NULL ise) doldurur.