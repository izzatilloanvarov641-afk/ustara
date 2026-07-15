-- Ustara: fix "infinite recursion detected in policy for relation bookings"
--
-- sql/21-one-active-booking.sql's insert policy queried bookings from
-- inside a policy ON bookings itself. Postgres detects that self-reference
-- and refuses to evaluate it at all — every single insert into bookings
-- failed with error 42P17, not just genuine duplicates. Confirmed live:
-- a client with zero existing bookings still got this error on their very
-- first booking attempt, so no one has been able to book anything since
-- that migration went live.
--
-- Fix: move the "does this client already have an active booking" check
-- into a SECURITY DEFINER function. Its internal query runs outside the
-- policy-evaluates-policy cycle that caused the recursion, so referencing
-- bookings from there is safe.

create or replace function client_has_active_booking(p_client_id uuid)
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select exists (
    select 1 from bookings b
    where b.client_id = p_client_id
      and b.status in ('pending', 'confirmed')
      and b.start_time >= date_trunc('day', now())
  );
$$;
grant execute on function client_has_active_booking(uuid) to authenticated;

drop policy if exists "Clients can create bookings for themselves" on bookings;

create policy "Clients can create bookings for themselves"
  on bookings for insert
  to authenticated
  with check (
    auth.uid() = client_id
    and not client_has_active_booking(auth.uid())
  );
