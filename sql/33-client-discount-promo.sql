-- Ustara: platform-funded client discount promo
--
-- A launch promo the founder funds directly: while active, clients see (and
-- pay) discount_percent% less than the listed service price, and barbers
-- owe only a flat discount_flat_commission per completed booking instead of
-- their usual flat+percent commission. The founder covers the gap out of
-- pocket — barbers end up with the same take-home they'd have gotten
-- without the promo (full price minus the usual commission), clients pay
-- less, and platform commission revenue drops accordingly. Toggle
-- discount_active off any time to fall back to normal per-barber
-- commission_flat/commission_percent.

alter table platform_settings add column if not exists discount_active boolean not null default true;
alter table platform_settings add column if not exists discount_percent numeric not null default 3;
alter table platform_settings add column if not exists discount_flat_commission integer not null default 1000;

create or replace function mark_booking_completed(p_booking_id uuid, p_price integer)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_booking bookings%rowtype;
  v_barber barbers%rowtype;
  v_settings platform_settings%rowtype;
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
  select * into v_settings from platform_settings where id = 1;

  if v_booking.client_id is null then
    v_commission := 0; -- walk-in: no commission, but still a real completed haircut
  elsif coalesce(v_settings.discount_active, false) then
    v_commission := coalesce(v_settings.discount_flat_commission, 1000);
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
