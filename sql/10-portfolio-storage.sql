-- Ustara: barber media storage (profile photo + before/after portfolio photos)
-- Single public bucket, path convention "<barber_id>/avatar/..." and
-- "<barber_id>/portfolio/..." so RLS can check ownership via the first
-- path segment without a separate lookup table.

insert into storage.buckets (id, name, public)
values ('barber-media', 'barber-media', true)
on conflict (id) do nothing;

create policy "Public can view barber media"
  on storage.objects for select
  to public
  using (bucket_id = 'barber-media');

create policy "Barbers can upload their own media"
  on storage.objects for insert
  to authenticated
  with check (bucket_id = 'barber-media' and (storage.foldername(name))[1] = auth.uid()::text);

create policy "Barbers can update their own media"
  on storage.objects for update
  to authenticated
  using (bucket_id = 'barber-media' and (storage.foldername(name))[1] = auth.uid()::text);

create policy "Barbers can delete their own media"
  on storage.objects for delete
  to authenticated
  using (bucket_id = 'barber-media' and (storage.foldername(name))[1] = auth.uid()::text);

-- Portfolio: multiple before/after shots per barber, orderable, independent
-- of the single avatar_url column already on barbers (added in 02-barbers.sql).
create table if not exists portfolio_photos (
  id uuid primary key default gen_random_uuid(),
  barber_id uuid not null references barbers(id) on delete cascade,
  image_path text not null,
  position int not null default 0,
  created_at timestamptz default now()
);

alter table portfolio_photos enable row level security;

create policy "Public can view portfolio photos"
  on portfolio_photos for select
  to anon, authenticated
  using (true);

create policy "Barbers can insert own portfolio photos"
  on portfolio_photos for insert
  to authenticated
  with check (auth.uid() = barber_id);

create policy "Barbers can update own portfolio photos"
  on portfolio_photos for update
  to authenticated
  using (auth.uid() = barber_id);

create policy "Barbers can delete own portfolio photos"
  on portfolio_photos for delete
  to authenticated
  using (auth.uid() = barber_id);
