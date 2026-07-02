-- ============ CLIENTS ============
create table if not exists clients (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null,
  phone text,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

alter table clients enable row level security;

create policy "Clients can view own row"
  on clients for select
  to authenticated
  using (auth.uid() = id);

create policy "Clients can insert own row"
  on clients for insert
  to authenticated
  with check (auth.uid() = id);

create policy "Clients can update own row"
  on clients for update
  to authenticated
  using (auth.uid() = id);

create trigger clients_set_updated_at
  before update on clients
  for each row execute function set_updated_at();


-- ============ BOOKINGS ============
-- client_name / client_phone are stored directly on the row (not joined from `clients`)
-- so a barber can see who booked with them without needing read access to the clients table.
create table if not exists bookings (
  id uuid primary key default gen_random_uuid(),
  barber_id uuid not null references barbers(id) on delete cascade,
  client_id uuid not null references clients(id) on delete cascade,
  client_name text not null,
  client_phone text,
  start_time timestamptz not null,
  status text not null default 'pending' check (status in ('pending','confirmed','cancelled','completed')),
  created_at timestamptz default now()
);

alter table bookings enable row level security;

create policy "Barbers can view own bookings"
  on bookings for select
  to authenticated
  using (auth.uid() = barber_id);

create policy "Clients can view own bookings"
  on bookings for select
  to authenticated
  using (auth.uid() = client_id);

create policy "Clients can create bookings for themselves"
  on bookings for insert
  to authenticated
  with check (auth.uid() = client_id);

create policy "Barbers can update status of own bookings"
  on bookings for update
  to authenticated
  using (auth.uid() = barber_id);
