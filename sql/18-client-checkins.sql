-- Ustara: daily check-in columns for clients
--
-- client-dashboard.html has shipped a daily check-in feature (streak
-- counter, +10 pts/day toast, bonus points folded into the loyalty tier
-- bar) since the dashboard redesign, but these columns were never added
-- to the live schema — so every client visit fired a failing UPDATE
-- ("Check-in update failed" in console) and check-in points never
-- accrued. This adds the three columns the code already reads/writes.

alter table clients add column if not exists checkin_streak int not null default 0;
alter table clients add column if not exists last_checkin_date date;
alter table clients add column if not exists checkin_bonus_points int not null default 0;
