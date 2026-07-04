-- Fix: PGRST204 "Could not find the 'company_account_holder' column of 'app_about_settings'"
-- app_about_settings.toJson() (Dart) tüm alanları update ediyor; şemada eksik olan
-- banka/bakiye/duyuru kolonlarını idempotent şekilde ekliyoruz.

ALTER TABLE public.app_about_settings
  ADD COLUMN IF NOT EXISTS company_bank_name              text,
  ADD COLUMN IF NOT EXISTS company_iban                   text,
  ADD COLUMN IF NOT EXISTS company_account_holder         text,
  ADD COLUMN IF NOT EXISTS online_payment_enabled         boolean DEFAULT true,
  ADD COLUMN IF NOT EXISTS global_orders_enabled          boolean DEFAULT true,
  ADD COLUMN IF NOT EXISTS balance_enabled                boolean DEFAULT true,
  ADD COLUMN IF NOT EXISTS card_topup_enabled             boolean DEFAULT true,
  ADD COLUMN IF NOT EXISTS min_topup_amount               numeric DEFAULT 10,
  ADD COLUMN IF NOT EXISTS max_topup_amount               numeric DEFAULT 10000,
  ADD COLUMN IF NOT EXISTS withdrawal_fee_percent         numeric DEFAULT 2,
  ADD COLUMN IF NOT EXISTS min_withdrawal_amount          numeric DEFAULT 50,
  ADD COLUMN IF NOT EXISTS iyzico_api_key                 text,
  ADD COLUMN IF NOT EXISTS iyzico_secret_key              text,
  ADD COLUMN IF NOT EXISTS iyzico_api_url                 text,
  ADD COLUMN IF NOT EXISTS support_phone                  text,
  ADD COLUMN IF NOT EXISTS google_maps_api_key            text,
  ADD COLUMN IF NOT EXISTS startup_announcement_enabled   boolean DEFAULT false,
  ADD COLUMN IF NOT EXISTS startup_announcement_title     text,
  ADD COLUMN IF NOT EXISTS startup_announcement_message   text,
  ADD COLUMN IF NOT EXISTS startup_announcement_type      text DEFAULT 'info',
  ADD COLUMN IF NOT EXISTS startup_announcement_button_text text DEFAULT 'Tamam',
  ADD COLUMN IF NOT EXISTS startup_announcement_updated_at timestamptz,
  ADD COLUMN IF NOT EXISTS animation_primary_duration_ms    integer DEFAULT 6000,
  ADD COLUMN IF NOT EXISTS animation_secondary_duration_ms  integer DEFAULT 3000,
  ADD COLUMN IF NOT EXISTS animation_transition_duration_ms integer DEFAULT 700;

-- PostgREST şema cache'ini yenile
NOTIFY pgrst, 'reload schema';
