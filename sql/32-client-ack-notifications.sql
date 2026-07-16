-- Ustara: blocking "your booking was confirmed/cancelled" popup for clients
--
-- Whenever a barber confirms a booking, or cancels one themselves (not the
-- client cancelling their own — they already know that), the client should
-- see a popup on their next visit that they must acknowledge ("I
-- understand") before using the rest of the app. client_ack_needed flips
-- true automatically via a trigger on exactly those two transitions, and
-- the client clears it themselves via acknowledge_booking() — a narrow
-- SECURITY DEFINER RPC rather than a general client UPDATE grant on
-- bookings, so a client can only ever clear this one flag on their own row.

alter table bookings add column if not exists client_ack_needed boolean not null default false;

create or replace function tg_flag_client_ack()
returns trigger
language plpgsql
as $$
begin
  if NEW.status = 'confirmed' and OLD.status is distinct from 'confirmed' then
    NEW.client_ack_needed := true;
  elsif NEW.status = 'cancelled' and OLD.status is distinct from 'cancelled'
        and coalesce(NEW.cancelled_by, '') <> 'client' then
    NEW.client_ack_needed := true;
  end if;
  return NEW;
end;
$$;

drop trigger if exists trg_flag_client_ack on bookings;
create trigger trg_flag_client_ack
  before update of status on bookings
  for each row execute function tg_flag_client_ack();

create or replace function acknowledge_booking(p_booking_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update bookings set client_ack_needed = false
  where id = p_booking_id and client_id = auth.uid();
end;
$$;
grant execute on function acknowledge_booking(uuid) to authenticated;
