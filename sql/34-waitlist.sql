-- Ustara: pre-launch waitlist
--
-- People who want in before they're ready to make a full account. Anyone can
-- add themselves (that's the whole point — it's a public form on the landing
-- page), but only the founder can read the list back, since it's a pile of
-- names and phone numbers. Same founder-email check the payout settings and
-- admin page already use.
--
-- Written to be re-runnable and self-correcting: a `waitlist` table already
-- existed in the live database carrying only id/created_at, which meant a
-- plain `create table if not exists` silently did nothing and every insert
-- failed with "Could not find the 'full_name' column". So the columns are
-- added separately, then backfilled, then constrained.

create table if not exists waitlist (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now()
);

alter table waitlist add column if not exists full_name text;
alter table waitlist add column if not exists phone text;
alter table waitlist add column if not exists city text;

-- any legacy rows would block the not-null constraints below
update waitlist set full_name = coalesce(full_name, '—');
update waitlist set phone = coalesce(phone, 'unknown-' || id::text);

alter table waitlist alter column full_name set not null;
alter table waitlist alter column phone set not null;

-- phone is unique so a double-tap on the form doesn't create two rows; the
-- landing page catches the resulting 23505 and shows "you're already on the
-- list" instead of an error
create unique index if not exists waitlist_phone_key on waitlist (phone);
create index if not exists waitlist_created_at_idx on waitlist (created_at desc);

alter table waitlist enable row level security;

-- anyone can put themselves on the list
drop policy if exists "Anyone can join the waitlist" on waitlist;
create policy "Anyone can join the waitlist"
  on waitlist for insert
  to anon, authenticated
  with check (true);

-- ...but only the founder can read it back
drop policy if exists "Founder can read the waitlist" on waitlist;
create policy "Founder can read the waitlist"
  on waitlist for select
  to authenticated
  using (auth.jwt() ->> 'email' = 'izzatilloanvarov641@gmail.com');

-- and only the founder can remove entries
drop policy if exists "Founder can delete waitlist entries" on waitlist;
create policy "Founder can delete waitlist entries"
  on waitlist for delete
  to authenticated
  using (auth.jwt() ->> 'email' = 'izzatilloanvarov641@gmail.com');

-- PostgREST caches the schema; after adding columns it needs a nudge or the
-- API keeps reporting the new columns as missing
notify pgrst, 'reload schema';
