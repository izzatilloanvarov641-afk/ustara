-- Ustara waitlist table
create table if not exists waitlist (
  id uuid primary key default gen_random_uuid(),
  contact text not null,
  role text not null check (role in ('client', 'barber')),
  lang text default 'en',
  created_at timestamptz default now()
);

-- prevent exact duplicate signups
create unique index if not exists waitlist_contact_role_idx
  on waitlist (lower(contact), role);

-- Row Level Security: allow anyone to insert (public signup form),
-- but nobody can read/update/delete from the client side.
alter table waitlist enable row level security;

create policy "Allow public insert"
  on waitlist for insert
  to anon
  with check (true);

-- No select/update/delete policy for anon = those stay locked down.
-- You (as project owner) can still see everything in the Supabase Table Editor.
