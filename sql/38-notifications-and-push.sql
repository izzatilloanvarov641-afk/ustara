-- Ustara: barber inquiries, a shared notification inbox, and web push
--
-- Three gaps this closes:
--
-- 1. `notifications` only ever had a client_id, so barbers had no inbox at
--    all. A new booking just appeared silently in their Bookings list and
--    they had to go looking for it. Now every booking raises an "inquiry"
--    notification addressed to the barber.
-- 2. Confirming/declining already flipped bookings.client_ack_needed (sql/32)
--    which drives the client's blocking popup, but left nothing behind in the
--    client's notification list. Now it writes a real notification row too,
--    so there's a history rather than a popup you dismiss and lose.
-- 3. Nothing could reach a user with the app closed. push_subscriptions plus
--    the send-push Edge Function make that possible.
--
-- Notification text is stored in Uzbek — the DB doesn't know a user's chosen
-- language, and Uzbek is the default. The in-app list re-renders from `type`
-- so it localises properly; only the pushed text is fixed at write time.

-- ---------- 1. notifications gains a barber recipient ----------
alter table notifications add column if not exists barber_id uuid
  references barbers(id) on delete cascade;

-- client_id was NOT NULL when clients were the only recipient
alter table notifications alter column client_id drop not null;

-- exactly one recipient per row — never both, never neither
do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'notifications_one_recipient'
  ) then
    alter table notifications add constraint notifications_one_recipient
      check (num_nonnulls(client_id, barber_id) = 1);
  end if;
end $$;

create index if not exists notifications_barber_idx on notifications (barber_id, created_at desc);

-- Barbers can read and mark read their own notifications. These are additive:
-- RLS policies are OR'd, so the existing client policies are untouched.
drop policy if exists "Barbers read own notifications" on notifications;
create policy "Barbers read own notifications"
  on notifications for select to authenticated
  using (barber_id = auth.uid());

drop policy if exists "Barbers update own notifications" on notifications;
create policy "Barbers update own notifications"
  on notifications for update to authenticated
  using (barber_id = auth.uid());

-- ---------- 2. a booking raises an inquiry for the barber ----------
create or replace function tg_notify_barber_new_booking()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  when_txt text;
begin
  when_txt := to_char(NEW.start_time at time zone 'Asia/Tashkent', 'DD.MM HH24:MI');
  insert into notifications (barber_id, type, related_booking_id, message)
  values (
    NEW.barber_id,
    'booking_inquiry',
    NEW.id,
    'Yangi so''rov: ' || coalesce(NEW.service_label, 'xizmat') || ' — ' || when_txt
  );
  return NEW;
exception when others then
  -- a notification problem must never block the booking itself
  return NEW;
end;
$$;

drop trigger if exists trg_notify_barber_new_booking on bookings;
create trigger trg_notify_barber_new_booking
  after insert on bookings
  for each row execute function tg_notify_barber_new_booking();

-- ---------- 3. the barber's answer lands in the client's inbox ----------
create or replace function tg_notify_client_booking_answer()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  when_txt text;
begin
  when_txt := to_char(NEW.start_time at time zone 'Asia/Tashkent', 'DD.MM HH24:MI');

  if NEW.status = 'confirmed' and OLD.status is distinct from 'confirmed' then
    insert into notifications (client_id, type, related_booking_id, message)
    values (NEW.client_id, 'booking_confirmed', NEW.id,
            'Bandingiz tasdiqlandi — ' || when_txt);

  -- a client cancelling their own booking already knows; don't tell them
  elsif NEW.status = 'cancelled' and OLD.status is distinct from 'cancelled'
        and coalesce(NEW.cancelled_by, '') <> 'client' then
    insert into notifications (client_id, type, related_booking_id, message)
    values (NEW.client_id, 'booking_cancelled_by_barber', NEW.id,
            'Band bekor qilindi — ' || when_txt);
  end if;

  return NEW;
exception when others then
  return NEW;
end;
$$;

drop trigger if exists trg_notify_client_booking_answer on bookings;
create trigger trg_notify_client_booking_answer
  after update of status on bookings
  for each row execute function tg_notify_client_booking_answer();

-- ---------- 4. web push subscriptions ----------
-- One row per browser/device. endpoint is unique, so re-subscribing the same
-- browser updates rather than piling up duplicates that all fire at once.
create table if not exists push_subscriptions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  endpoint text not null unique,
  p256dh text not null,
  auth text not null,
  user_agent text,
  created_at timestamptz not null default now()
);

alter table push_subscriptions enable row level security;

drop policy if exists "Users manage own push subscriptions" on push_subscriptions;
create policy "Users manage own push subscriptions"
  on push_subscriptions for all to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

-- account deletion (sql/20) predates this table, so clean up here too
create index if not exists push_subscriptions_user_idx on push_subscriptions (user_id);

notify pgrst, 'reload schema';

-- ---------- check it worked ----------
-- Book something as a test client, then this should return one fresh row:
--   select type, message, barber_id, created_at
--     from notifications
--    where type = 'booking_inquiry'
--    order by created_at desc limit 1;
