-- Ustara: live booking updates (no more "reload to see a cancellation")
--
-- Both dashboards only ever fetched bookings once at page load. A barber
-- confirming/cancelling, or a client cancelling, never reached the other
-- person's already-open tab until they manually reloaded. Supabase
-- Realtime can push postgres row changes straight to the browser over
-- the same connection — this just needs the table added to the
-- `supabase_realtime` publication; the actual subscription logic lives
-- in client-dashboard.html / barber-dashboard.html.

alter publication supabase_realtime add table bookings;
