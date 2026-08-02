-- claim_task RPC, kullanıcı göreve katılırken screenshot_url olmadan
-- task_submissions satırı oluşturuyor (status='pending'). Kanıt daha sonra
-- submit_task_with_proof ile eklenir. Bu nedenle screenshot_url NOT NULL
-- olamaz; sadece submit anında (submit_task_with_proof içinde) boş olamaz.
ALTER TABLE public.task_submissions ALTER COLUMN screenshot_url DROP NOT NULL;
