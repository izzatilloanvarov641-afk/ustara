-- Ustara: barber commission payment — payout account + proof-of-payment review
--
-- Flow: admin sets a payout card (platform_settings, single row) that every
-- barber sees on their Payments tab. A barber pays that card externally
-- (Payme/Click/bank transfer) and uploads a screenshot as proof. Admin
-- reviews the screenshot against the live owed amount and either marks it
-- paid (resets barbers.last_settled_at, zeroing the owed total) or rejects
-- it. This is the same trust-based settlement admin.html already had
-- (a plain "Mark as paid" button with a confirm() dialog) — this just adds
-- evidence to that decision instead of removing the manual step.

-- ---------- payout account (single row, admin-editable) ----------
create table if not exists platform_settings (
  id smallint primary key default 1 check (id = 1),
  payout_card_number text,
  payout_card_name text,
  updated_at timestamptz default now()
);
insert into platform_settings (id) values (1) on conflict (id) do nothing;

alter table platform_settings enable row level security;

create policy "Anyone can view payout settings"
  on platform_settings for select
  to anon, authenticated
  using (true);

create policy "Founder can update payout settings"
  on platform_settings for update
  to authenticated
  using (auth.jwt() ->> 'email' = 'izzatilloanvarov641@gmail.com');

create trigger platform_settings_set_updated_at
  before update on platform_settings
  for each row execute function set_updated_at();

-- ---------- proof-of-payment submissions ----------
create table if not exists payment_proofs (
  id uuid primary key default gen_random_uuid(),
  barber_id uuid not null references barbers(id) on delete cascade,
  screenshot_path text not null,
  amount_owed numeric not null default 0,
  status text not null default 'pending' check (status in ('pending','approved','rejected')),
  admin_note text,
  created_at timestamptz default now(),
  reviewed_at timestamptz
);

alter table payment_proofs enable row level security;

create policy "Barbers can view own payment proofs"
  on payment_proofs for select
  to authenticated
  using (auth.uid() = barber_id);

create policy "Barbers can submit own payment proofs"
  on payment_proofs for insert
  to authenticated
  with check (auth.uid() = barber_id);

create policy "Founder can view all payment proofs"
  on payment_proofs for select
  to authenticated
  using (auth.jwt() ->> 'email' = 'izzatilloanvarov641@gmail.com');

create policy "Founder can update payment proofs"
  on payment_proofs for update
  to authenticated
  using (auth.jwt() ->> 'email' = 'izzatilloanvarov641@gmail.com');

-- ---------- storage for the screenshots (private — not public like barber-media) ----------
insert into storage.buckets (id, name, public)
  values ('payment-proofs', 'payment-proofs', false)
  on conflict (id) do nothing;

create policy "Barbers can upload own payment proof screenshots"
  on storage.objects for insert
  to authenticated
  with check (bucket_id = 'payment-proofs' and (storage.foldername(name))[1] = auth.uid()::text);

create policy "Barbers can view own payment proof screenshots"
  on storage.objects for select
  to authenticated
  using (bucket_id = 'payment-proofs' and (storage.foldername(name))[1] = auth.uid()::text);

create policy "Founder can view all payment proof screenshots"
  on storage.objects for select
  to authenticated
  using (bucket_id = 'payment-proofs' and auth.jwt() ->> 'email' = 'izzatilloanvarov641@gmail.com');
