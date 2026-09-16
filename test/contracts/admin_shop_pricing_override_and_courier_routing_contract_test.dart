import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Admin müdahalesi migration'ının sözleşmesi:
///   * satıcı teslimat ücreti / min. sepet tutarı override'ı + geri alma,
///   * siparişi istenen kuryenin paneline düşürme.
///
/// Bu testler davranışın canlıda doğrulanan üç kritik özelliğini SQL metninde
/// sabitler: (1) satıcının eski değeri gerçekten yedekleniyor ve geri
/// alınabiliyor, (2) satıcı override'ı kendi başına kuramıyor/delemiyor,
/// (3) admin yönlendirmesi kurye havuzundan çıkarıp yalnız hedef kuryeye
/// düşüren mevcut teklif altyapısını kullanıyor.
void main() {
  late String sql;
  late String code;

  setUpAll(() {
    sql = File(
      'supabase/migrations/20260915000001_admin_shop_pricing_override_and_courier_routing.sql',
    ).readAsStringSync();
    code = sql
        .split('\n')
        .where((l) => !l.trimLeft().startsWith('--'))
        .join('\n');
  });

  group('fiyat override şeması', () {
    test('yedek + denetim sütunları shops üzerinde eklenir', () {
      expect(code, contains('ALTER TABLE public.shops'));
      for (final column in const [
        'pre_override_delivery_fee',
        'pre_override_min_order_amount',
        'pre_override_delivery_time',
        'admin_pricing_override_at',
        'admin_pricing_override_by',
        'admin_pricing_override_note',
      ]) {
        expect(
          code,
          contains('ADD COLUMN IF NOT EXISTS $column'),
          reason: '$column sütunu migration\'da yok',
        );
      }
    });

    test('canlı alanlar shops.delivery_fee / min_order_amount / delivery_time kalır', () {
      // Tüm okuma yolları (sepet, checkout, mağaza kartı, mağaza detayı) bu üç
      // sütunu okur; override ayrı bir "efektif değer" sütununa taşınmamalı.
      expect(code, contains('delivery_fee = COALESCE(p_delivery_fee'));
      expect(code, contains('min_order_amount = COALESCE(p_min_order_amount'));
      expect(code, contains('delivery_time = COALESCE(v_delivery_time'));
    });
  });

  group('teslimat süresi override\'ı', () {
    test('nullable sütun için boş dize sentinel\'i kullanılır', () {
      // delivery_time NULL olabildiği için "yedek NULL = override yok"
      // değişmezini korumak adına satıcının boş değeri '' olarak yedeklenir.
      expect(
        code,
        contains(
          'WHEN s.pre_override_delivery_time IS NULL THEN COALESCE(s.delivery_time, \'\')',
        ),
      );
      expect(
        code,
        contains("WHEN s.pre_override_delivery_time = '' THEN NULL"),
      );
    });

    test('boş/whitespace girdi "dokunma" sayılır ve uzunluk sınırlanır', () {
      expect(
        code,
        contains("v_delivery_time text := NULLIF(btrim(COALESCE(p_delivery_time, '')), '')"),
      );
      expect(code, contains('APP:invalid_delivery_time'));
    });

    test('tek başına teslimat süresi müdahalesi geçerlidir', () {
      expect(
        code,
        contains('IF p_delivery_fee IS NULL\n'
            '     AND p_min_order_amount IS NULL\n'
            '     AND v_delivery_time IS NULL THEN'),
      );
    });

    test('trigger satıcının süre yazımını da yedeğe yönlendirir', () {
      expect(
        code,
        contains("NEW.pre_override_delivery_time := COALESCE(NEW.delivery_time, '');"),
      );
      expect(code, contains('NEW.delivery_time := OLD.delivery_time;'));
      expect(code, contains('NEW.pre_override_delivery_time := NULL;'));
    });

    test('eski 4 parametreli imza kaldırılır (PostgREST belirsizliği)', () {
      expect(
        code,
        contains(
          'DROP FUNCTION IF EXISTS public.admin_set_shop_pricing_override(uuid[], numeric, numeric, text);',
        ),
      );
      expect(
        code,
        contains(
          'CREATE FUNCTION public.admin_set_shop_pricing_override(\n'
          '  p_shop_ids uuid[] DEFAULT NULL,\n'
          '  p_delivery_fee numeric DEFAULT NULL,\n'
          '  p_min_order_amount numeric DEFAULT NULL,\n'
          '  p_delivery_time text DEFAULT NULL,\n'
          '  p_note text DEFAULT NULL\n'
          ')',
        ),
      );
    });
  });

  group('admin_set_shop_pricing_override', () {
    test('admin kontrolü ve auth zorunlu', () {
      expect(
        code,
        contains('CREATE FUNCTION public.admin_set_shop_pricing_override'),
      );
      expect(code, contains("RAISE EXCEPTION 'APP:auth_required'"));
      expect(code, contains("APP:forbidden | admin gerekli"));
      expect(code, contains('SECURITY DEFINER'));
    });

    test('yedek yalnız ilk ezmede yazılır (üst üste ezme yedeği bozmaz)', () {
      expect(
        code,
        contains('WHEN s.pre_override_delivery_fee IS NULL THEN s.delivery_fee'),
      );
      expect(
        code,
        contains(
          'WHEN s.pre_override_min_order_amount IS NULL THEN s.min_order_amount',
        ),
      );
    });

    test('shop_ids boş/NULL ise tüm dükkanlara uygulanır', () {
      expect(code, contains('p_shop_ids IS NULL'));
      expect(code, contains('cardinality(p_shop_ids) = 0'));
      expect(code, contains('s.id = ANY (p_shop_ids)'));
    });

    test('anon çağrı kapalı, authenticated açık', () {
      expect(
        code,
        contains(
          'REVOKE ALL ON FUNCTION public.admin_set_shop_pricing_override(uuid[], numeric, numeric, text, text)\n'
          '  FROM PUBLIC, anon;',
        ),
      );
      expect(
        code,
        contains(
          'GRANT EXECUTE ON FUNCTION public.admin_set_shop_pricing_override(uuid[], numeric, numeric, text, text)\n'
          '  TO authenticated, service_role;',
        ),
      );
    });
  });

  group('admin_clear_shop_pricing_override', () {
    test('satıcının değeri canlıya geri döner ve yedek temizlenir', () {
      expect(
        code,
        contains('CREATE FUNCTION public.admin_clear_shop_pricing_override'),
      );
      expect(
        code,
        contains(
          'delivery_fee = COALESCE(s.pre_override_delivery_fee, s.delivery_fee)',
        ),
      );
      expect(
        code,
        contains(
          'min_order_amount = COALESCE(s.pre_override_min_order_amount, s.min_order_amount)',
        ),
      );
      expect(code, contains('pre_override_delivery_fee = NULL'));
      expect(code, contains('pre_override_min_order_amount = NULL'));
      expect(code, contains('pre_override_delivery_time = NULL'));
      expect(code, contains('OR s.pre_override_delivery_time IS NOT NULL'));
    });
  });

  group('satıcı koruma trigger\'ı', () {
    test('shops üzerinde BEFORE UPDATE olarak kurulur', () {
      expect(
        code,
        contains('CREATE OR REPLACE FUNCTION public.shops_guard_admin_pricing_override()'),
      );
      expect(code, contains('BEFORE UPDATE ON public.shops'));
      expect(
        code,
        contains('EXECUTE FUNCTION public.shops_guard_admin_pricing_override()'),
      );
    });

    test('admin ve servis bağlamı serbest, satıcı yazımı yedeğe yönlenir', () {
      expect(code, contains('IF (SELECT auth.uid()) IS NULL OR public.is_admin() THEN'));
      expect(code, contains('NEW.pre_override_delivery_fee := NEW.delivery_fee;'));
      expect(code, contains('NEW.delivery_fee := OLD.delivery_fee;'));
      expect(
        code,
        contains('NEW.pre_override_min_order_amount := NEW.min_order_amount;'),
      );
      expect(code, contains('NEW.min_order_amount := OLD.min_order_amount;'));
    });

    test('satıcı override kuramaz ve denetim sütunlarını değiştiremez', () {
      expect(code, contains('NEW.pre_override_delivery_fee := NULL;'));
      expect(code, contains('NEW.pre_override_min_order_amount := NULL;'));
      expect(
        code,
        contains('NEW.admin_pricing_override_at := OLD.admin_pricing_override_at;'),
      );
      expect(
        code,
        contains('NEW.admin_pricing_override_by := OLD.admin_pricing_override_by;'),
      );
      expect(
        code,
        contains(
          'NEW.admin_pricing_override_note := OLD.admin_pricing_override_note;',
        ),
      );
    });
  });

  group('admin -> kurye yönlendirmesi', () {
    test('teklif kaydı admin bayrağı taşır', () {
      expect(code, contains('ALTER TABLE public.courier_work_offers'));
      expect(code, contains('ADD COLUMN IF NOT EXISTS routed_by_admin boolean'));
      expect(code, contains('ADD COLUMN IF NOT EXISTS routed_by uuid'));
    });

    test('admin_route_order_to_courier admin + kurye doğrulaması yapar', () {
      expect(
        code,
        contains('CREATE FUNCTION public.admin_route_order_to_courier'),
      );
      expect(code, contains("APP:forbidden | admin gerekli"));
      expect(code, contains('APP:not_a_courier'));
      expect(
        code,
        contains('IF NOT public.is_courier_document_approved(p_courier_id) THEN'),
      );
      expect(code, contains('APP:pickup_order'));
      // TOCTOU koruması: sipariş ve mevcut atama kilitlenir.
      expect(code, contains('FOR UPDATE'));
    });

    test('teslim alınmış sipariş devredilemez', () {
      expect(code, contains('APP:already_picked_up'));
      expect(code, contains('APP:already_assigned_to_courier'));
    });

    test('aktif atama + hedef kuryeye pending teklif oluşur', () {
      expect(code, contains('INSERT INTO public.courier_assignments'));
      expect(code, contains('INSERT INTO public.courier_work_offers'));
      expect(
        code,
        contains(
          "'order', p_order_id, v_assignment_id, p_courier_id, true, v_uid",
        ),
      );
    });

    test('adminin kararı kuryenin eski reddini geçersiz kılar', () {
      expect(code, contains('DELETE FROM public.courier_order_rejections'));
    });

    test(
      'aynı kuryeye yeniden yönlendirme UNIQUE(order_id, courier_id) kısıtına takılmaz',
      () {
        // Devir, atama satırının courier_id'sini değiştirerek değil; eski satır
        // iptal edilip hedef kuryenin satırı upsert edilerek yapılır.
        expect(code, contains('ON CONFLICT (order_id, courier_id) DO UPDATE'));
        expect(
          code,
          isNot(contains('SET courier_id = p_courier_id')),
          reason: 'courier_id devri benzersizlik kısıtını ihlal eder',
        );
      },
    );

    test('teslim edilmiş atama canlandırılmaz', () {
      expect(code, contains('APP:already_delivered_by_courier'));
      expect(code, contains("v_target_existing.status = 'delivered'"));
    });

    test('yönlendirme geri alınabilir (sipariş havuza döner)', () {
      expect(
        code,
        contains('CREATE FUNCTION public.admin_cancel_order_courier_routing'),
      );
      expect(code, contains("SET status = 'cancelled'"));
      expect(
        code,
        contains(
          "SET status = CASE WHEN status = 'on_the_way' THEN 'ready' ELSE status END",
        ),
      );
    });
  });

  group('teklif akışı durum kümesi', () {
    test('yönlendirilmiş teklif listesi havuzla aynı durumları kabul eder', () {
      // Admin confirmed/preparing siparişi de yönlendirebilmeli; aksi halde
      // teklif kuryede hiç görünmez.
      expect(
        code,
        contains("AND o.status IN ('confirmed', 'preparing', 'ready')"),
      );
      expect(code, contains('routed_by_admin boolean'));
    });

    test('kabul RPC\'si aynı durum kümesini kullanır', () {
      // Aksi halde admin'in yönlendirdiği confirmed sipariş kabul denemesinde
      // 'offer_stale' ile teklifi öldürürdü.
      expect(
        code,
        contains('CREATE OR REPLACE FUNCTION public.accept_routed_order_offer'),
      );
      expect(
        code,
        contains("OR v_order.status NOT IN ('confirmed', 'preparing', 'ready')"),
      );
      expect(code, isNot(contains("OR v_order.status <> 'ready' THEN")));
    });
  });
}
