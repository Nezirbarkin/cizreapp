// Push worker'ın saf, ağ erişimi gerektirmeyen teslimat kuralları.

export const DEFAULT_CHANNEL_ID = 'high_importance_channel'

// Kullanıcı 'Bildirim sesi'ni kapattıysa bu kanal kullanılır. Kanalı istemci
// (push_notification_service.dart) sessiz olarak oluşturur; kanal sesi Android'de
// sonradan değiştirilemediği için ses tercihi ayrı bir kanalla taşınır.
export const SILENT_CHANNEL_ID = 'silent_notifications'

export interface FcmMessage {
  token: string
  notification: { title: string; body: string }
  data: Record<string, string>
  android: {
    priority: 'high'
    notification: { sound?: 'default'; channel_id: string }
  }
  apns: {
    payload: { aps: { sound?: 'default'; badge: number } }
  }
}

export interface FcmMessageOptions {
  /** true: ses çalmadan (sessiz kanal, APNs sesi yok) teslim et. */
  silent?: boolean
}

export function buildFcmMessage(
  token: string,
  title: string,
  body: string,
  data: Record<string, string>,
  options: FcmMessageOptions = {},
): FcmMessage {
  if (options.silent) {
    return {
      token,
      notification: { title, body },
      data,
      android: {
        priority: 'high',
        notification: { channel_id: SILENT_CHANNEL_ID },
      },
      apns: {
        payload: { aps: { badge: 1 } },
      },
    }
  }
  return {
    token,
    notification: { title, body },
    data,
    android: {
      priority: 'high',
      notification: {
        sound: 'default',
        channel_id: DEFAULT_CHANNEL_ID,
      },
    },
    apns: {
      payload: { aps: { sound: 'default', badge: 1 } },
    },
  }
}

/** Bildirim sesi açık mı? Yalnız açıkça false olan tercih sessize alır (fail-open). */
export function isPushSoundEnabled(
  preferences: Record<string, unknown> | null,
): boolean {
  return !preferences || preferences.notification_sound_enabled !== false
}

export interface ClassifiedFcmFailure {
  unregistered: boolean
  safeError: string
}

export function classifyFcmFailure(
  status: number,
  responseText: string,
): ClassifiedFcmFailure {
  const upper = responseText.toUpperCase()
  const unregistered = upper.includes('UNREGISTERED') ||
    upper.includes('REGISTRATION_TOKEN_NOT_REGISTERED')

  // INVALID_ARGUMENT bozuk payload/proje ayarı anlamına da gelebilir. Bu hata
  // token silme gerekçesi değildir; yalnız kesin UNREGISTERED temizlenir.
  return {
    unregistered,
    safeError: unregistered
      ? `FCM_${status}_UNREGISTERED`
      : `FCM_${status}_DELIVERY_ERROR`,
  }
}

const preferenceColumnByType: Record<string, string> = {
  like: 'likes_enabled',
  post_like: 'likes_enabled',
  comment: 'comments_enabled',
  post_comment: 'comments_enabled',
  comment_reply: 'comments_enabled',
  follow: 'followers_enabled',
  follower: 'followers_enabled',
  follow_request: 'followers_enabled',
  follow_accepted: 'followers_enabled',
  mention: 'mentions_enabled',
  post_mention: 'mentions_enabled',
  order: 'order_updates_enabled',
  order_update: 'order_updates_enabled',
  order_status: 'order_updates_enabled',
  order_confirmed: 'order_updates_enabled',
  order_ready: 'order_ready_enabled',
  delivered: 'delivery_enabled',
  order_delivered: 'delivery_enabled',
  group_join_request: 'group_join_requests_enabled',
  group_member_joined: 'group_member_joined_enabled',
  promotion: 'promotional_enabled',
  promotional: 'promotional_enabled',
  price_drop: 'promotional_enabled',
}

export function isPushEnabledForType(
  preferences: Record<string, unknown> | null,
  type: string,
): boolean {
  if (!preferences) return true

  // Bazı şema sürümlerindeki global anahtarları da geriye uyumlu destekle.
  if (preferences.push_notifications === false || preferences.push_enabled === false) {
    return false
  }

  const column = preferenceColumnByType[type]
  return column == null || preferences[column] !== false
}
