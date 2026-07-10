-- Ustara: self-service account deletion (Play Store requires this — an
-- in-app way for a user to delete their account and data, not just a
-- support-email request).
--
-- Deleting auth.users cascades to barbers/clients (on delete cascade) and
-- from there to bookings, services, portfolio_photos, payment_proofs
-- (all "references barbers(id) on delete cascade" per their migrations).
-- favorites, reviews, notifications, and telegram_link_codes were created
-- ad hoc directly in Supabase (no migration file ever defined them, same
-- gap the Telegram bot work found earlier) so their FK/cascade behavior
-- isn't guaranteed here — deleted explicitly first to be certain.

create or replace function delete_own_account()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
begin
  if uid is null then
    raise exception 'not authenticated';
  end if;

  delete from favorites where client_id = uid or barber_id = uid;
  delete from reviews where client_id = uid or barber_id = uid;
  delete from notifications where client_id = uid;
  delete from telegram_link_codes where user_id = uid;

  -- Removing the auth user cascades through barbers/clients and everything
  -- FK'd to them (bookings, services, portfolio_photos, payment_proofs) —
  -- this is also what actually revokes login access.
  delete from auth.users where id = uid;
end;
$$;

grant execute on function delete_own_account() to authenticated;
