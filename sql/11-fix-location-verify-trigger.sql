-- Fix: the self-verify-protection trigger from 09-location-pricing.sql
-- reverts is_location_verified to its old value for ANY non-founder
-- update, not just attempts to set it to true. That means when a barber
-- moves their pin and barber-dashboard.html tries to reset
-- is_location_verified to false (so a moved pin needs re-approval before
-- it shows on the public map), the trigger was silently reverting that
-- reset back to true — defeating the whole point of the reset.
--
-- Fix: only intervene when a non-founder tries to set the value to true
-- (self-approval). Setting it to false is always allowed, from anyone.

create or replace function prevent_barber_self_verify_location()
returns trigger as $$
begin
  if auth.role() = 'authenticated'
     and coalesce(auth.jwt() ->> 'email', '') <> 'izzatilloanvarov641@gmail.com'
     and new.is_location_verified = true then
    new.is_location_verified := old.is_location_verified;
  end if;
  return new;
end;
$$ language plpgsql;
