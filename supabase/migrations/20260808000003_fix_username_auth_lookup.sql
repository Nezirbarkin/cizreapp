-- Kullanıcı adıyla giriş / şifre kurtarma düzeltmesi.
--
-- profiles.email doğrudan anon/authenticated erişimine kapalıdır. İstemci bu
-- dar RPC üzerinden kullanıcı adını e-postaya çevirir. E-posta auth.users'tan
-- okunur; böylece kullanıcı e-postasını değiştirdiyse profiles içindeki eski
-- kopya nedeniyle giriş bozulmaz.

CREATE OR REPLACE FUNCTION public.lookup_email_by_username(p_username text)
RETURNS text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT LOWER(u.email)
  FROM public.profiles AS p
  JOIN auth.users AS u ON u.id = p.id
  WHERE LOWER(p.username) = LOWER(TRIM(p_username))
    AND u.email IS NOT NULL
  LIMIT 1;
$$;

REVOKE ALL ON FUNCTION public.lookup_email_by_username(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.lookup_email_by_username(text)
  TO anon, authenticated, service_role;

