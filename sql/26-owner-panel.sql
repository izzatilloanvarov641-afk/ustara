-- Ustara: business owner panel
--
-- A shop owner (e.g. runs a barbershop with several chairs) gets their own
-- lightweight account. Each barber already has a persistent short code
-- (shown in their own dashboard) — the owner types that code into their
-- dashboard once to link the barber to their roster. From then on the
-- owner sees the same kind of analytics admin.html shows founder-wide,
-- scoped to only their own linked barbers: availability right now, booking
-- counts, completed cuts, revenue, ratings. A barber can be linked to at
-- most one owner at a time and isn't otherwise affected — they keep using
-- barber-dashboard.html exactly as before.

create table if not exists owners (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null,
  shop_name text,
  created_at timestamptz default now()
);
alter table owners enable row level security;

create policy "Owners can view their own profile"
  on owners for select to authenticated
  using (auth.uid() = id);

create policy "Owners can update their own profile"
  on owners for update to authenticated
  using (auth.uid() = id);

-- ---------- link barbers to an owner ----------
alter table barbers add column if not exists owner_id uuid references owners(id) on delete set null;
alter table barbers add column if not exists owner_link_code text unique;

-- backfill codes for barbers that existed before this migration, then make
-- sure every future barber row gets one automatically
update barbers set owner_link_code = upper(substr(md5(random()::text || clock_timestamp()::text || id::text), 1, 8))
  where owner_link_code is null;
alter table barbers alter column owner_link_code
  set default upper(substr(md5(random()::text || clock_timestamp()::text), 1, 8));
alter table barbers alter column owner_link_code set not null;

create policy "Owners can view their linked barbers"
  on barbers for select to authenticated
  using (owner_id = auth.uid());

-- Linking/unlinking go through SECURITY DEFINER RPCs rather than a broad
-- owner UPDATE policy on barbers, so an owner can only ever change owner_id
-- on a row — never anything else about a barber's profile.
create or replace function link_barber_to_owner(p_code text)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_barber barbers%rowtype;
begin
  select * into v_barber from barbers where owner_link_code = upper(trim(p_code));
  if v_barber.id is null then
    return 'not_found';
  end if;
  if v_barber.owner_id is not null and v_barber.owner_id <> auth.uid() then
    return 'already_linked';
  end if;
  update barbers set owner_id = auth.uid() where id = v_barber.id;
  return 'ok';
end;
$$;
grant execute on function link_barber_to_owner(text) to authenticated;

create or replace function unlink_barber_from_owner(p_barber_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update barbers set owner_id = null where id = p_barber_id and owner_id = auth.uid();
end;
$$;
grant execute on function unlink_barber_from_owner(uuid) to authenticated;

-- ---------- owners can read bookings/reviews for their own linked barbers ----------
create policy "Owners can view bookings for their linked barbers"
  on bookings for select to authenticated
  using (exists (select 1 from barbers where barbers.id = bookings.barber_id and barbers.owner_id = auth.uid()));

create policy "Owners can view reviews for their linked barbers"
  on reviews for select to authenticated
  using (exists (select 1 from barbers where barbers.id = reviews.barber_id and barbers.owner_id = auth.uid()));

-- ---------- auto-create the owners profile row at signup, same pattern as sql/08 ----------
create or replace function handle_new_user()
returns trigger as $$
declare
  meta jsonb := coalesce(new.raw_user_meta_data, '{}'::jsonb);
begin
  if meta ->> 'role' = 'barber' then
    insert into public.barbers (id, full_name, phone, district, bio, years_experience, specialties)
    values (
      new.id,
      coalesce(meta ->> 'full_name', ''),
      coalesce(meta ->> 'phone', ''),
      meta ->> 'district',
      meta ->> 'bio',
      nullif(meta ->> 'years_experience', '')::int,
      case when meta ? 'specialties'
        then array(select jsonb_array_elements_text(meta -> 'specialties'))
        else '{}'::text[]
      end
    )
    on conflict (id) do nothing;
  elsif meta ->> 'role' = 'client' then
    insert into public.clients (id, full_name, phone)
    values (
      new.id,
      coalesce(meta ->> 'full_name', ''),
      meta ->> 'phone'
    )
    on conflict (id) do nothing;
  elsif meta ->> 'role' = 'owner' then
    insert into public.owners (id, full_name, shop_name)
    values (
      new.id,
      coalesce(meta ->> 'full_name', ''),
      meta ->> 'shop_name'
    )
    on conflict (id) do nothing;
  end if;
  return new;
exception when others then
  -- never let a profile-creation hiccup break account creation itself
  return new;
end;
$$ language plpgsql security definer set search_path = public;
