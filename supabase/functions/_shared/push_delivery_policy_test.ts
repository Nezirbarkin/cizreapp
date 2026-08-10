import {
  assertEquals,
  assertFalse,
} from 'https://deno.land/std@0.168.0/assert/mod.ts'
import {
  buildFcmMessage,
  classifyFcmFailure,
  isPushEnabledForType,
} from './push_delivery_policy.ts'

Deno.test('FCM HTTP v1 hedef tokenı message içine yerleştirilir', () => {
  const message = buildFcmMessage('TEST_DEVICE_TOKEN', 'Başlık', 'İçerik', {
    type: 'test',
  })

  assertEquals(message.token, 'TEST_DEVICE_TOKEN')
  assertEquals(message.android.notification.channel_id, 'high_importance_channel')
  assertEquals(message.data, { type: 'test' })
})

Deno.test('yalnız kesin UNREGISTERED hatası token temizletir', () => {
  assertEquals(
    classifyFcmFailure(404, '{"error":{"status":"UNREGISTERED"}}'),
    { unregistered: true, safeError: 'FCM_404_UNREGISTERED' },
  )
  assertFalse(
    classifyFcmFailure(400, '{"error":{"status":"INVALID_ARGUMENT"}}')
      .unregistered,
  )
  assertFalse(classifyFcmFailure(500, 'internal').unregistered)
})

Deno.test('bildirim tercihi tür bazında ve global olarak uygulanır', () => {
  assertFalse(isPushEnabledForType({ likes_enabled: false }, 'post_like'))
  assertFalse(isPushEnabledForType({ order_updates_enabled: false }, 'order_status'))
  assertFalse(isPushEnabledForType({ push_notifications: false }, 'admin_notification'))
  assertEquals(isPushEnabledForType({ likes_enabled: true }, 'post_like'), true)
  assertEquals(isPushEnabledForType(null, 'order_status'), true)
})
