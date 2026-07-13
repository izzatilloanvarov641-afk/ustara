-- ============ ONE ACTIVE BOOKING PER CLIENT ============
-- A client may hold only one pending/confirmed booking dated today or later
-- at a time. They can book again once that booking is marked completed,
-- they cancel it, or its date has passed. Enforced server-side (not just in
-- the UI) by rewriting the client-insert policy so a client can never create
-- a second active booking, no matter which client-facing page they use.

drop policy if exists "Clients can create bookings for themselves" on bookings;

create policy "Clients can create bookings for themselves"
  on bookings for insert
  to authenticated
  with check (
    auth.uid() = client_id
    and not exists (
      select 1 from bookings b
      where b.client_id = auth.uid()
        and b.status in ('pending', 'confirmed')
        and b.start_time >= date_trunc('day', now())
    )
  );
