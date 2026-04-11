-- Enable Realtime for support_tickets table
-- This allows admin panel to receive live updates when users submit new support tickets

ALTER PUBLICATION supabase_realtime ADD TABLE support_tickets;

-- Grant SELECT permissions for realtime
GRANT SELECT ON support_tickets TO authenticated;
GRANT SELECT ON support_tickets TO anon;
