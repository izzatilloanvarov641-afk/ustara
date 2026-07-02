-- Ustara: services offered per barber
-- Barbers pick from a shared, fixed list of service types (for consistent
-- wording/translation across the app) and set their own duration for each.

create table if not exists services (
  id uuid primary key default gen_random_uuid(),
  barber_id uuid not null references barbers(id) on delete cascade,
  service_key text not null check (service_key in
    ('haircut','beard_trim','haircut_beard','kids_haircut','lineup','coloring')),
  duration_minutes int not null default 30,
  is_active boolean default true,
  created_at timestamptz default now(),
  updated_at timestamptz default now(),
  unique (barber_id, service_key)
);

alter table services enable row level security;

-- Anyone can see a barber's active services (browse/booking page)
create policy "Public can view active services"
  on services for select
  to anon, authenticated
  using (is_active = true);

-- A barber can see all of their own services, including inactive ones
create policy "Barbers can view own services"
  on services for select
  to authenticated
  using (auth.uid() = barber_id);

create policy "Barbers can insert own services"
  on services for insert
  to authenticated
  with check (auth.uid() = barber_id);

create policy "Barbers can update own services"
  on services for update
  to authenticated
  using (auth.uid() = barber_id);

create policy "Barbers can delete own services"
  on services for delete
  to authenticated
  using (auth.uid() = barber_id);

create trigger services_set_updated_at
  before update on services
  for each row execute function set_updated_at();


-- Snapshot which service (and its duration at time of booking) was picked,
-- same pattern already used for client_name/client_phone on this table.
alter table bookings add column if not exists service_key text;
alter table bookings add column if not exists service_duration_minutes int;
