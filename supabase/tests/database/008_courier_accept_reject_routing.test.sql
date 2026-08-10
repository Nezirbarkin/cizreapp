-- Kurye kabul/ret yönlendirme sözleşmesi için hafif regression kontrolleri.
DO $tests$
BEGIN
  IF to_regprocedure('public.accept_package_request(uuid)') IS NULL THEN
    RAISE EXCEPTION 'accept_package_request(uuid) eksik';
  END IF;
  IF to_regprocedure('public.reject_package_request(uuid)') IS NULL THEN
    RAISE EXCEPTION 'reject_package_request(uuid) eksik';
  END IF;
  IF to_regprocedure('public.reject_order_assignment(uuid)') IS NULL THEN
    RAISE EXCEPTION 'reject_order_assignment(uuid) eksik';
  END IF;
  IF to_regclass('public.courier_order_rejections') IS NULL THEN
    RAISE EXCEPTION 'courier_order_rejections tablosu eksik';
  END IF;
  IF to_regclass('public.courier_package_email_deliveries') IS NULL THEN
    RAISE EXCEPTION 'courier_package_email_deliveries tablosu eksik';
  END IF;
  IF NOT has_function_privilege(
    'authenticated', 'public.accept_package_request(uuid)', 'EXECUTE'
  ) THEN
    RAISE EXCEPTION 'authenticated accept_package_request EXECUTE yetkisi eksik';
  END IF;
  IF has_table_privilege(
    'authenticated', 'public.courier_package_email_deliveries', 'SELECT'
  ) THEN
    RAISE EXCEPTION 'email teslimat tablosu authenticated rolüne açık';
  END IF;
END
$tests$;

