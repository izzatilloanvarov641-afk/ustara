-- ============ AUTOMATED CLIENT RE-VISIT REMINDERS ============
-- Barber-configurable: nudge past clients to rebook after N days of no visit.
-- Reuses the existing `notifications` table — whatever already forwards new
-- client notifications to Telegram (used today for booking confirmations)
-- picks these up the same way, no new delivery channel needed.
--
-- REQUIRES the pg_cron extension. In the Supabase dashboard:
--   Database -> Extensions -> enable "pg_cron"
-- then run this file in the SQL editor.

alter table barbers add column if not exists auto_reminders_enabled boolean not null default false;
alter table barbers add column if not exists auto_reminder_days integer not null default 21;

create or replace function send_due_rebook_reminders()
returns void
language plpgsql
security definer
as $$
begin
  insert into notifications (client_id, type, related_booking_id, message)
  select distinct on (b.client_id, b.barber_id)
    b.client_id,
    'rebook_reminder',
    b.id,
    coalesce(br.full_name, 'Your barber') || ' — it''s been a while, ready for another cut?'
  from bookings b
  join barbers br on br.id = b.barber_id
  where b.status = 'completed'
    and b.client_id is not null
    and br.auto_reminders_enabled = true
    and b.completed_at <= now() - (br.auto_reminder_days || ' days')::interval
    and not exists (
      select 1 from notifications n
      where n.client_id = b.client_id
        and n.type = 'rebook_reminder'
        and n.related_booking_id in (select id from bookings where barber_id = b.barber_id and client_id = b.client_id)
        and n.created_at >= now() - (br.auto_reminder_days || ' days')::interval
    )
  order by b.client_id, b.barber_id, b.completed_at desc;
end;
$$;

-- runs once a day; safe to re-run this file, it replaces the existing schedule
select cron.unschedule('send-rebook-reminders-daily') where exists (
  select 1 from cron.job where jobname = 'send-rebook-reminders-daily'
);
select cron.schedule('send-rebook-reminders-daily', '0 9 * * *', $$select send_due_rebook_reminders();$$);
