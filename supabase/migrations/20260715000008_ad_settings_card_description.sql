-- Cüzdan ekranındaki "İzleyerek Kazan" kartının açıklama metnini admin panelden özelleştirilebilir yap.
ALTER TABLE ad_settings
    ADD COLUMN IF NOT EXISTS card_description TEXT;
