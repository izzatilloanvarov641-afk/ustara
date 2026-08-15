-- Ustara: stop gating barbers behind profile approval
--
-- Reviewing every new barber profile by hand was a bottleneck that bought
-- little: the checks that actually protect clients are the location pin (is
-- this a real, findable shop?) and the payment proofs. Those two stay. Profile
-- approval goes.
--
-- A barber still cannot appear publicly until they flip themselves Live, and
-- the dashboard refuses to let them do that without a verified location, a
-- name, a phone number and a photo — so "approved" was never the thing keeping
-- half-finished profiles off the map.

-- new barbers are approved on arrival
alter table barbers alter column is_approved set default true;

-- ...and everyone currently sitting in the old pending queue is let through,
-- except anyone previously rejected, who stays rejected
update barbers
   set is_approved = true
 where is_approved = false
   and coalesce(is_rejected, false) = false;

-- Owners were never gated by is_approved (there's no such column on owners);
-- they've always been usable straight after signup. Nothing to change there.

notify pgrst, 'reload schema';
