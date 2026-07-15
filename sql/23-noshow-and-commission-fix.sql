-- Ustara: no-show handling + walk-in commission fix
--
-- Three things, all enforced server-side (not just hidden in the UI, since
-- a barber calling the API directly could otherwise bypass a client-side
-- check the same way the one-active-booking rule could before it moved
-- into an RLS policy):
--   1. A barber can only mark a booking "completed" once its start_time
--      has actually passed.
--   2. A barber can mark a booking "client didn't come" (no_show) once its
--      start_time has passed — this docks the client 500 points and does
--      NOT block them from booking again (no_show isn't in the
--      pending/confirmed set the one-active-booking policy checks).
--   3. Walk-in bookings (client_id is null — no real client account) never
--      generate a commission, but still fully count toward the barber's
--      own analytics (service_price, completed count, etc. are unaffected).

alter table clients add column if not exists penalty_points integer not null default 0;

alter table bookings drop constraint if exists bookings_status_check;
alter table bookings add constraint bookings_status_check
  check (status in ('pending','confirmed','cancelled','completed','no_show'));

-- ---------- mark a booking completed (time-gated, walk-ins get no commission) ----------
create or replace function mark_booking_completed(p_booking_id uuid, p_price integer)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_booking bookings%rowtype;
  v_barber barbers%rowtype;
  v_commission integer;
begin
  select * into v_booking from bookings where id = p_booking_id;
  if v_booking.id is null then
    raise exception 'booking not found';
  end if;
  if v_booking.barber_id <> auth.uid() then
    raise exception 'not authorized';
  end if;
  if v_booking.status <> 'confirmed' then
    raise exception 'booking is not confirmed';
  end if;
  if v_booking.start_time > now() then
    raise exception 'booking time has not passed yet';
  end if;

  select * into v_barber from barbers where id = auth.uid();

  if v_booking.client_id is null then
    v_commission := 0; -- walk-in: no commission, but still a real completed haircut
  else
    v_commission := coalesce(v_barber.commission_flat, 1000)
      + round(p_price * coalesce(v_barber.commission_percent, 3) / 100.0);
  end if;

  update bookings set
    status = 'completed',
    service_price = p_price,
    commission_amount = v_commission,
    completed_at = now()
  where id = p_booking_id;
end;
$$;
grant execute on function mark_booking_completed(uuid, integer) to authenticated;

-- ---------- mark a booking as a no-show (time-gated, docks the client 500 points) ----------
create or replace function mark_no_show(p_booking_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_booking bookings%rowtype;
begin
  select * into v_booking from bookings where id = p_booking_id;
  if v_booking.id is null then
    raise exception 'booking not found';
  end if;
  if v_booking.barber_id <> auth.uid() then
    raise exception 'not authorized';
  end if;
  if v_booking.status <> 'confirmed' then
    raise exception 'booking is not confirmed';
  end if;
  if v_booking.start_time > now() then
    raise exception 'booking time has not passed yet';
  end if;

  update bookings set status = 'no_show' where id = p_booking_id;

  if v_booking.client_id is not null then
    update clients set penalty_points = penalty_points + 500 where id = v_booking.client_id;
  end if;
end;
$$;
grant execute on function mark_no_show(uuid) to authenticated;
