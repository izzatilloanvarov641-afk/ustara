-- Ustara: barber approval gate
-- Barbers can sign up and set a password, but must be manually approved
-- (by toggling is_approved in the Table Editor) before they can log in.

alter table barbers add column if not exists is_approved boolean default false;

-- Prevent barbers from approving themselves through the client (anon/authenticated) API.
-- Admin approval happens via the Supabase dashboard, which connects as a role other
-- than 'authenticated' and so is not affected by this trigger.
create or replace function prevent_barber_self_approve()
returns trigger as $$
begin
  if auth.role() = 'authenticated' then
    new.is_approved := old.is_approved;
  end if;
  return new;
end;
$$ language plpgsql;

create trigger barbers_prevent_self_approve
  before update on barbers
  for each row execute function prevent_barber_self_approve();
