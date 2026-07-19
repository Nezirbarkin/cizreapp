-- Güvenlik düzeltmesi: "Service can ..." politikaları TO belirtmediği için
-- tüm authenticated kullanıcılara uygulanıyordu. Bu, bir kullanıcının
-- PostgREST üzerinden doğrudan user_balances/balance_transactions
-- tablolarına yazarak kendi bakiyesini manipüle edebilmesine izin veriyordu.
-- Bu politikalar artık sadece service_role (Edge Functions) için geçerli.

DROP POLICY IF EXISTS "Service can update balances" ON user_balances;
CREATE POLICY "Service can update balances"
    ON user_balances FOR UPDATE
    TO service_role
    USING (true);

DROP POLICY IF EXISTS "Service can insert transactions" ON balance_transactions;
CREATE POLICY "Service can insert transactions"
    ON balance_transactions FOR INSERT
    TO service_role
    WITH CHECK (true);
