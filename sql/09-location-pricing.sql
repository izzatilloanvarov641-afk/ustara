-- Ustara: barber location (for map view) and per-service pricing
-- Location is set by the barber themselves (drag-pin map in their dashboard).
-- Price is per service, set alongside duration in the Services section.
-- Both are nullable: existing barbers/services rows aren't broken, and the
-- UI treats "not set yet" as a distinct state (e.g. hide from map until a
-- barber sets their location; show "price not set" until they add one).

alter table barbers add column if not exists latitude double precision;
alter table barbers add column if not exists longitude double precision;

alter table services add column if not exists price integer;

-- Location verification gate: a barber can drop a pin and name their shop,
-- but it does not appear on the public map until the founder has manually
-- confirmed (offline / by contract) that the shop is real. Separate from
-- is_approved (profile-level approval) since a barber can be approved to
-- log in and manage their profile before their location is verified.
alter table barbers add column if not exists shop_name text;
alter table barbers add column if not exists is_location_verified boolean default false;

-- Same self-approve protection pattern as is_approved (05/07-*.sql): only the
-- founder account can flip is_location_verified, never the barber themselves.
create or replace function prevent_barber_self_verify_location()
returns trigger as $$
begin
  if auth.role() = 'authenticated' and coalesce(auth.jwt() ->> 'email', '') <> 'izzatilloanvarov641@gmail.com' then
    new.is_location_verified := old.is_location_verified;
  end if;
  return new;
end;
$$ language plpgsql;

drop trigger if exists barbers_prevent_self_verify_location on barbers;
create trigger barbers_prevent_self_verify_location
  before update on barbers
  for each row execute function prevent_barber_self_verify_location();

-- Public map/browse view should only ever show verified locations.
-- (is_published/is_approved already gate the browse list itself via
-- policy 07; this additionally hides the pin/coords until verified.)
