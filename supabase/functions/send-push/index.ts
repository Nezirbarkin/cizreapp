// =====================================================
// DEPRECATED — Bu fonksiyon artık kullanılmıyor.
// 2026-08-02 push pipeline refaktörü sonrası güvenli
// tek yol: public.notification_outbox + process-notification-outbox
// worker. Bu stub güvenlik nedeniyle tüm çağrıları 410 Gone
// ile reddeder. Deploy Supabase CLI ile kaldırılmalıdır:
//   supabase functions delete send-push --project-ref <ref>
// =====================================================

import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'

serve(async (_req: Request) => {
  return new Response(
    JSON.stringify({
      error: 'send-push is decommissioned',
      migration: '20260802000003_secure_push_notification_pipeline',
    }),
    {
      status: 410,
      headers: { 'Content-Type': 'application/json' },
    }
  )
})
