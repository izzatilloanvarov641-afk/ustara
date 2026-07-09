-- Ustara: Telegram bot — account linking, booking reminders, review broadcasts
--
-- How this fits together: this file only stores state and schedules calls;
-- every actual Telegram/Gemini API call happens in one Supabase Edge
-- Function ("telegram-bot", see supabase/functions/telegram-bot/index.ts)
-- which must be deployed separately (Dashboard → Edge Functions). Postgres
-- reaches it via pg_net (already used elsewhere in this project's cron
-- jobs) with a tiny JSON body saying which action to run:
--   { action: "poll_updates" }        -- picks up /start <code> messages
--   { action: "send_reminders" }      -- 24h / 2h booking reminders
--   { action: "broadcast_review", review_id }  -- new review fan-out
--
-- NOTE: the two RPCs below (get_telegram_link_code, get_telegram_status)
-- already existed live in this project without a matching migration file
-- checked in — they're recreated here from what the frontend expects them
-- to do, since the "linking" half worked but nothing ever consumed the
-- link codes or sent an actual message. This file makes both halves real.

-- enables outbound HTTP calls from Postgres (net.http_post below) — this
-- is what lets pg_cron/triggers reach the Edge Function
create extension if not exists pg_net;

-- ---------- account linking ----------
alter table barbers add column if not exists telegram_chat_id bigint;
alter table clients add column if not exists telegram_chat_id bigint;

create unique index if not exists barbers_telegram_chat_id_idx
  on barbers(telegram_chat_id) where telegram_chat_id is not null;
create unique index if not exists clients_telegram_chat_id_idx
  on clients(telegram_chat_id) where telegram_chat_id is not null;

create table if not exists telegram_link_codes (
  code text primary key,
  role text not null check (role in ('client','barber')),
  user_id uuid not null,
  created_at timestamptz default now()
);
alter table telegram_link_codes enable row level security;
-- Deliberately no client-facing policies: only SECURITY DEFINER functions
-- below (get_telegram_link_code) and the service-role Edge Function touch
-- this table.

create or replace function get_telegram_link_code(p_role text)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_code text;
begin
  if p_role not in ('client','barber') then
    raise exception 'invalid role: %', p_role;
  end if;
  delete from telegram_link_codes where user_id = auth.uid();
  v_code := upper(substr(md5(random()::text || clock_timestamp()::text), 1, 8));
  insert into telegram_link_codes (code, role, user_id) values (v_code, p_role, auth.uid());
  return v_code;
end;
$$;
grant execute on function get_telegram_link_code(text) to authenticated;

create or replace function get_telegram_status()
returns boolean
language sql
security definer
set search_path = public
as $$
  select exists(select 1 from barbers where id = auth.uid() and telegram_chat_id is not null)
      or exists(select 1 from clients where id = auth.uid() and telegram_chat_id is not null);
$$;
grant execute on function get_telegram_status() to authenticated;

-- one-row table tracking the Telegram getUpdates offset, so polling never
-- re-processes the same message twice
create table if not exists telegram_poll_state (
  id smallint primary key default 1 check (id = 1),
  last_update_id bigint not null default 0
);
alter table telegram_poll_state enable row level security;
-- No policies here either — same reasoning as telegram_link_codes above,
-- only the service-role Edge Function needs to touch this.
insert into telegram_poll_state (id, last_update_id) values (1, 0)
  on conflict (id) do nothing;

-- ---------- booking reminders ----------
-- reuses bookings.reminded_24h / reminded_2h, which already existed in
-- this project's live schema (set by nothing, until now)
alter table bookings alter column reminded_24h set default false;
alter table bookings alter column reminded_2h set default false;
update bookings set reminded_24h = false where reminded_24h is null;
update bookings set reminded_2h = false where reminded_2h is null;

-- ---------- generic "call the edge function" helper ----------
create or replace function tg_invoke(p_body jsonb)
returns void
language plpgsql
security definer
as $$
begin
  perform net.http_post(
    url := 'https://gbvfesorkmsxugpvcuqy.supabase.co/functions/v1/telegram-bot',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer sb_publishable_k7wdvlBvnpPHPNCrl9i_eg_ktsfJAst'
    ),
    body := p_body
  );
exception when others then
  -- never let a Telegram/network hiccup break the booking/review flow
  -- that triggered this call
  raise warning 'tg_invoke failed: %', sqlerrm;
end;
$$;

-- ---------- review broadcast (fires immediately on a new review) ----------
create or replace function tg_notify_new_review()
returns trigger
language plpgsql
as $$
begin
  perform tg_invoke(jsonb_build_object('action', 'broadcast_review', 'review_id', NEW.id));
  return NEW;
end;
$$;

drop trigger if exists trg_tg_notify_new_review on reviews;
create trigger trg_tg_notify_new_review
  after insert on reviews
  for each row execute function tg_notify_new_review();

-- ---------- scheduled jobs ----------
-- unschedule first so re-running this file doesn't error on "already exists"
select cron.unschedule(jobid) from cron.job where jobname = 'tg-poll-updates';
select cron.unschedule(jobid) from cron.job where jobname = 'tg-send-reminders';

-- poll for /start <code> messages roughly every minute (matches the
-- ~2 min the dashboards already poll get_telegram_status for)
select cron.schedule(
  'tg-poll-updates', '* * * * *',
  $$select tg_invoke(jsonb_build_object('action','poll_updates'));$$
);

-- check for due 24h/2h booking reminders every 10 minutes
select cron.schedule(
  'tg-send-reminders', '*/10 * * * *',
  $$select tg_invoke(jsonb_build_object('action','send_reminders'));$$
);
