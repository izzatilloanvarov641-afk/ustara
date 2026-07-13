-- Ustara: Telegram bot — name personalization, daily reminders, cancel notify
--
-- Builds on sql/15-telegram-bot.sql. Three additions, matched to the Edge
-- Function code in supabase/functions/telegram-bot/index.ts:
--   1. telegram_display_name — the name the bot asks for right after linking
--      (distinct from the formal full_name collected at signup), used to
--      address the person directly in reminders and review broadcasts.
--   2. Daily booking reminders for clients (new 'daily_reminders' action +
--      cron job), replacing the old one-shot 24h reminder.
--   3. A trigger that notifies a barber via the bot the moment a client
--      cancels one of their bookings.
-- The 2h-before reminder becomes a 3h-before reminder (client + barber) —
-- same 'send_reminders' action/cron job, new column, new window in code.

alter table clients add column if not exists telegram_display_name text;
alter table barbers add column if not exists telegram_display_name text;

alter table bookings add column if not exists last_daily_reminder_date date;
alter table bookings add column if not exists reminded_3h boolean not null default false;

-- Defensive, same reasoning as sql/15's note on reminded_24h/reminded_2h:
-- these two already exist live (set by client-dashboard.html's cancel
-- flow) but were never checked into a migration file.
alter table bookings add column if not exists cancelled_by text;
alter table bookings add column if not exists barber_seen_cancellation boolean default false;

-- ---------- cancellation notify (client cancels → tell their barber) ----------
create or replace function tg_notify_cancellation()
returns trigger
language plpgsql
as $$
begin
  if NEW.status = 'cancelled' and OLD.status is distinct from 'cancelled' and NEW.cancelled_by = 'client' then
    perform tg_invoke(jsonb_build_object('action', 'notify_cancellation', 'booking_id', NEW.id));
  end if;
  return NEW;
end;
$$;

drop trigger if exists trg_tg_notify_cancellation on bookings;
create trigger trg_tg_notify_cancellation
  after update of status on bookings
  for each row execute function tg_notify_cancellation();

-- ---------- scheduled job: daily reminders (once a day, client only) ----------
select cron.unschedule(jobid) from cron.job where jobname = 'tg-daily-reminders';

-- 04:00 UTC ≈ 09:00 Tashkent (UTC+5, no DST) — a reasonable morning nudge
select cron.schedule(
  'tg-daily-reminders', '0 4 * * *',
  $$select tg_invoke(jsonb_build_object('action','daily_reminders'));$$
);
