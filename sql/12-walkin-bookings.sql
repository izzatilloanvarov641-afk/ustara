-- ============ WALK-IN BOOKINGS ============
-- Lets a barber record a booking for someone who doesn't have (or isn't
-- using) an Ustara client account — e.g. a walk-in customer. client_name /
-- client_phone are already stored directly on the row (see 03-clients-bookings.sql),
-- so a walk-in booking just omits client_id entirely instead of requiring a
-- real clients row.

alter table bookings alter column client_id drop not null;

create policy "Barbers can create walk-in bookings for themselves"
  on bookings for insert
  to authenticated
  with check (auth.uid() = barber_id and client_id is null);
