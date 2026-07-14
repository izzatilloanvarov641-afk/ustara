-- Ustara: 20% booking deposit (paid by client to barber via Click.uz)
--
-- Flow: barber confirms a pending booking -> we snapshot deposit_amount as
-- 20% of the already-snapshotted service_price and set deposit_status
-- 'pending'. Client pays it either through Click.uz (checkout link built
-- client-side from platform_settings.click_merchant_id/click_service_id,
-- confirmed server-side by supabase/functions/click-payment webhook) or,
-- until Click credentials exist, by uploading a screenshot the barber
-- reviews manually (same trust pattern as sql/16 payment_proofs, but here
-- it's client -> barber, not barber -> founder).
--
-- Cancellation: if the deposit was already paid, a client cancellation
-- 24h+ before start_time marks it 'refund_due' (barber owes it back);
-- inside 24h or a no-show, it's 'forfeited' (barber keeps it). A barber
-- cancellation always marks 'refund_due' regardless of timing, since the
-- client didn't cause it.

alter table bookings add column if not exists deposit_amount numeric;
alter table bookings add column if not exists deposit_status text not null default 'not_required'
  check (deposit_status in ('not_required','pending','paid','refund_due','refunded','forfeited'));
alter table bookings add column if not exists deposit_paid_at timestamptz;
alter table bookings add column if not exists deposit_proof_path text;
alter table bookings add column if not exists click_trans_id text;

alter table platform_settings add column if not exists click_merchant_id text;
alter table platform_settings add column if not exists click_service_id text;

-- ---------- storage for manual deposit-proof screenshots ----------
insert into storage.buckets (id, name, public)
  values ('deposit-proofs', 'deposit-proofs', false)
  on conflict (id) do nothing;

create policy "Clients can upload own deposit proof screenshots"
  on storage.objects for insert
  to authenticated
  with check (bucket_id = 'deposit-proofs' and (storage.foldername(name))[1] = auth.uid()::text);

create policy "Clients can view own deposit proof screenshots"
  on storage.objects for select
  to authenticated
  using (bucket_id = 'deposit-proofs' and (storage.foldername(name))[1] = auth.uid()::text);

create policy "Barbers can view deposit proofs for their own bookings"
  on storage.objects for select
  to authenticated
  using (
    bucket_id = 'deposit-proofs'
    and exists (
      select 1 from bookings
      where bookings.deposit_proof_path = storage.objects.name
        and bookings.barber_id = auth.uid()
    )
  );
