-- Ustara: founder approval via admin.html
-- Builds on is_approved (already added in 05-barber-approval.sql, which currently
-- can only be flipped via the Supabase Table Editor, since the postgres role used
-- there bypasses RLS). This migration lets ONE specific founder email approve or
-- reject barbers through the client API from admin.html, while barbers still
-- cannot set their own is_approved.

-- Safety net in case this ever runs against a database that skipped 05-barber-approval.sql
alter table barbers add column if not exists is_approved boolean default false;

-- Replace the self-approve guard: block is_approved changes from any authenticated
-- user EXCEPT the founder's own account (matched by email on their JWT).
create or replace function prevent_barber_self_approve()
returns trigger as $$
begin
  if auth.role() = 'authenticated' and coalesce(auth.jwt() ->> 'email', '') <> 'izzatilloanvarov641@gmail.com' then
    new.is_approved := old.is_approved;
  end if;
  return new;
end;
$$ language plpgsql;

-- Founder needs to see ALL barbers (including unapproved ones) to review them in admin.html
create policy "Founder can view all barbers"
  on barbers for select
  to authenticated
  using (coalesce(auth.jwt() ->> 'email', '') = 'izzatilloanvarov641@gmail.com');

-- Founder needs to update any barber row to approve/reject, not just their own
create policy "Founder can update any barber"
  on barbers for update
  to authenticated
  using (coalesce(auth.jwt() ->> 'email', '') = 'izzatilloanvarov641@gmail.com')
  with check (coalesce(auth.jwt() ->> 'email', '') = 'izzatilloanvarov641@gmail.com');

-- Public browse page should only ever surface barbers who are both published AND approved
drop policy if exists "Public can view published barbers" on barbers;
create policy "Public can view published and approved barbers"
  on barbers for select
  to anon, authenticated
  using (is_published = true and is_approved = true);
