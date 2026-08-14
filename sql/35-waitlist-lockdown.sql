-- Ustara: lock down the waitlist table  ** SECURITY FIX — run this **
--
-- The waitlist table already existed in the live database (created outside
-- this branch) carrying columns contact/role/lang and, critically, policies
-- that let ANY anonymous visitor both READ and DELETE the whole list.
-- Verified live with the public anon key: a plain select returned real rows
-- and a delete succeeded. That is a data leak (names + contact details of
-- everyone who signed up) and a destructive-write hole (anyone could empty it).
--
-- Adding "founder only" policies in 34-waitlist.sql did NOT close this:
-- Postgres RLS policies are permissive and OR'd together, so a single
-- allow-everyone policy overrides every stricter one sitting beside it. The
-- only fix is to remove the loose policies, so this drops every policy on the
-- table and recreates exactly the three we want.
--
-- Existing rows are left completely untouched.

alter table waitlist enable row level security;

-- drop every existing policy by name, whatever it happens to be called
do $$
declare p record;
begin
  for p in
    select policyname from pg_policies
    where schemaname = 'public' and tablename = 'waitlist'
  loop
    execute format('drop policy %I on public.waitlist', p.policyname);
  end loop;
end $$;

-- anyone may add themselves — that's the point of a public waitlist form
create policy "waitlist_public_insert"
  on waitlist for insert
  to anon, authenticated
  with check (true);

-- ...but only the founder may read it back
create policy "waitlist_founder_select"
  on waitlist for select
  to authenticated
  using (auth.jwt() ->> 'email' = 'izzatilloanvarov641@gmail.com');

-- ...and only the founder may remove entries
create policy "waitlist_founder_delete"
  on waitlist for delete
  to authenticated
  using (auth.jwt() ->> 'email' = 'izzatilloanvarov641@gmail.com');

-- no update policy at all: a waitlist entry is append-only

notify pgrst, 'reload schema';
