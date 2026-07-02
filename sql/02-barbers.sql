-- Ustara: barbers table
-- Each barber has a Supabase Auth account (for login) and a matching row here (their public profile).

create table if not exists barbers (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null,
  phone text not null,
  district text,                          -- e.g. Yunusabad, Chorsu — where they currently work
  bio text,
  specialties text[] default '{}',        -- e.g. {'Skin fade','Beard shaping'}
  years_experience int,
  avatar_url text,                        -- Supabase Storage path once photo upload is added
  is_published boolean default false,     -- barber controls when their profile goes live
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

alter table barbers enable row level security;

-- Anyone can view published barber profiles (for the client browse page, later)
create policy "Public can view published barbers"
  on barbers for select
  to anon, authenticated
  using (is_published = true);

-- A barber can view and edit their own row even if unpublished
create policy "Barbers can view own profile"
  on barbers for select
  to authenticated
  using (auth.uid() = id);

create policy "Barbers can insert own profile"
  on barbers for insert
  to authenticated
  with check (auth.uid() = id);

create policy "Barbers can update own profile"
  on barbers for update
  to authenticated
  using (auth.uid() = id);

-- keep updated_at fresh
create or replace function set_updated_at()
returns trigger as $$
begin
  new.updated_at = now();
  return new;
end;
$$ language plpgsql;

create trigger barbers_set_updated_at
  before update on barbers
  for each row execute function set_updated_at();
