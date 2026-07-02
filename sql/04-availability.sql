-- Adds working-hours configuration to barbers, so we can generate
-- available time slots on the fly instead of pre-creating thousands of rows.

alter table barbers add column if not exists work_days text[] default '{}';
-- e.g. '{"Mon","Tue","Wed","Thu","Fri","Sat"}'

alter table barbers add column if not exists work_start time default '09:00';
alter table barbers add column if not exists work_end time default '20:00';
alter table barbers add column if not exists slot_duration_minutes int default 30;

-- Prevent two active bookings landing on the exact same barber + time
-- (cancelled bookings don't count, so a freed-up slot can be rebooked)
create unique index if not exists bookings_no_double_book
  on bookings (barber_id, start_time)
  where status in ('pending', 'confirmed');

