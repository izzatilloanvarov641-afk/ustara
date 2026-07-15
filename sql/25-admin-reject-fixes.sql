-- Ustara: fix admin.html's "Reject" (barber) button doing nothing visible
--
-- admin.html's reject handler only ever set is_published = false, but
-- loadPending() filters strictly on is_approved = false — since reject
-- never touched is_approved, a rejected barber never left the pending
-- queue and the button looked broken (click it, card just sits there).
-- Adding a real is_rejected flag lets the query exclude them properly.

alter table barbers add column if not exists is_rejected boolean not null default false;
