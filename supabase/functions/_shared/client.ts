// Module-scope service-role Supabase client (singleton).
//
// Deno isolate'ları warm istekler boyunca reuse edildiği için client'ı
// (auth + fetcher + storage adapter) modül scope'unda BİR kez yaratıp
// yeniden kullanmak, her istekte yeniden kurmaktan daha ucuzdur.
//
// Bu client SUPABASE_SERVICE_ROLE_KEY kullanır → RLS'i atlar. SADECE
// sunucu tarafında (edge function içinde) kullanın; asla istemciye döndürmeyin.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.38.4";

let _adminClient: ReturnType<typeof createClient> | null = null;

/**
 * Service-role admin client (RLS bypass). Module scope'ta cache'lenir.
 * Kullanıcının JWT'sini gerektiren işlemler için getAdminClient() KULLANMA —
 * onun yerine istek başına createClient(url, anonKey, { global: { headers }})
 * ile kullanıcı client'ı yarat.
 */
export function getAdminClient() {
  if (_adminClient) return _adminClient;

  const url = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !serviceKey) {
    throw new Error(
      "MISSING_CONFIG: SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY tanımlı değil",
    );
  }

  _adminClient = createClient(url, serviceKey, {
    auth: {
      persistSession: false,
      autoRefreshToken: false,
      detectSessionInUrl: false,
    },
  });
  return _adminClient;
}
