-- =====================================================
-- SUPABASE SERVICE ROLE KEY VAULT'A EKLEME
-- =====================================================

INSERT INTO vault.secrets (name, secret, description)
VALUES (
    'supabase_service_role_key',
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InhzYnVreGtndG1keWlja2tucXpmIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc2ODkzMjczOCwiZXhwIjoyMDg0NTA4NzM4fQ.V7q1-B_i6f8F4PIUIl8eZ4kJzKKlThzyQU4sgPxrERE',
    'Supabase Service Role Key for internal Edge Function calls'
);

-- =====================================================
-- KONTROL
-- =====================================================
SELECT name, description FROM vault.secrets WHERE name = 'supabase_service_role_key';
