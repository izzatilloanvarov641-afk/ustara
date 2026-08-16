-- Ustara: repair accounts that have no profile row, and re-assert the trigger
--
-- Symptom: confirming a signup email landed the barber on their dashboard,
-- which then said "Could not load your profile. Please contact support."
-- The account existed in auth.users; the matching public.barbers row did not.
--
-- Why it can happen silently: handle_new_user() (sql/08, body later replaced by
-- sql/26) ends with `exception when others then return new` so that a profile
-- hiccup can never block account creation. That is the right trade — nobody
-- should be unable to sign up because of a profile bug — but it means a failed
-- insert leaves no error, no log, and no row. The trigger binding itself lives
-- only in sql/08; sql/26 used `create or replace function`, which keeps an
-- existing binding but creates nothing if the binding was never there.
--
-- This migration does two things: backfill the rows that are missing now, and
-- make sure the trigger is actually attached for every signup from here on.
-- Both halves are idempotent — running it twice changes nothing the second time.

-- ---------- 1. backfill ----------
-- Every confirmed-or-not auth user whose metadata says they are a barber, but
-- who has no barbers row. Same column mapping the trigger uses.
insert into public.barbers (id, full_name, phone, district, bio, years_experience, specialties)
select
  u.id,
  coalesce(u.raw_user_meta_data ->> 'full_name', ''),
  coalesce(u.raw_user_meta_data ->> 'phone', ''),
  u.raw_user_meta_data ->> 'district',
  u.raw_user_meta_data ->> 'bio',
  nullif(u.raw_user_meta_data ->> 'years_experience', '')::int,
  case when u.raw_user_meta_data ? 'specialties'
    then array(select jsonb_array_elements_text(u.raw_user_meta_data -> 'specialties'))
    else '{}'::text[]
  end
from auth.users u
where u.raw_user_meta_data ->> 'role' = 'barber'
  and not exists (select 1 from public.barbers b where b.id = u.id)
on conflict (id) do nothing;

insert into public.clients (id, full_name, phone)
select
  u.id,
  coalesce(u.raw_user_meta_data ->> 'full_name', ''),
  u.raw_user_meta_data ->> 'phone'
from auth.users u
where u.raw_user_meta_data ->> 'role' = 'client'
  and not exists (select 1 from public.clients c where c.id = u.id)
on conflict (id) do nothing;

insert into public.owners (id, full_name, shop_name)
select
  u.id,
  coalesce(u.raw_user_meta_data ->> 'full_name', ''),
  u.raw_user_meta_data ->> 'shop_name'
from auth.users u
where u.raw_user_meta_data ->> 'role' = 'owner'
  and not exists (select 1 from public.owners o where o.id = u.id)
on conflict (id) do nothing;

-- ---------- 2. re-assert the trigger ----------
-- Safe whether or not it was already attached; the function body is whatever
-- sql/26 last defined (barber + client + owner branches).
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function handle_new_user();

notify pgrst, 'reload schema';

-- ---------- how to check it worked ----------
-- Should return no rows:
--   select u.id, u.email, u.raw_user_meta_data ->> 'role' as role
--     from auth.users u
--    where u.raw_user_meta_data ->> 'role' in ('barber','client','owner')
--      and not exists (select 1 from public.barbers b where b.id = u.id)
--      and not exists (select 1 from public.clients c where c.id = u.id)
--      and not exists (select 1 from public.owners  o where o.id = u.id);
