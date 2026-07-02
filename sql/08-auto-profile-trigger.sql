-- Ustara: auto-create the barbers/clients profile row at signup time
--
-- Root cause being fixed: the client-side code used to insert into barbers/
-- clients right after auth.signUp(). That only works if signUp() returns an
-- active session immediately. With "Confirm email" required, it doesn't --
-- signUp() returns a pending user with no session, so the follow-up insert
-- runs as the anon role and gets silently rejected by RLS. Two real barber
-- signups were lost this way.
--
-- Fix: a security-definer trigger on auth.users creates the profile row the
-- moment the account is created, regardless of email-confirmation state,
-- using metadata passed through signUp's `options.data`. This means we can
-- leave "Confirm email" ON (or OFF) without breaking profile creation.

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
  end if;
  return new;
exception when others then
  -- never let a profile-creation hiccup break account creation itself
  return new;
end;
$$ language plpgsql security definer set search_path = public;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function handle_new_user();
