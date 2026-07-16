-- Ustara: fix client cancellation (broken by sql/28) + add confirmed-cancel penalty
--
-- Two problems, one root cause and one new rule:
--
-- 1. BUG (regression from sql/28-security-hardening.sql): a client could no
--    longer cancel ANY booking, and — more quietly — could no longer submit
--    a review either. sql/28 revoked EXECUTE on tg_invoke() from regular
--    users to stop them hitting the Edge Function directly. But the two
--    triggers that call tg_invoke (tg_notify_cancellation on a booking
--    cancel, tg_notify_new_review on a review insert) were plain
--    SECURITY INVOKER functions, so they ran as the client and hit the
--    exact permission wall sql/28 put up — failing the whole statement with
--    "permission denied for function tg_invoke". Confirmed live. Fix: mark
--    both trigger functions SECURITY DEFINER so they call tg_invoke as the
--    function owner (who still has execute), regardless of who triggered.
--
-- 2. NEW RULE: cancelling a *confirmed* booking (one the barber already
--    accepted and is holding a chair for) now costs the client 500 points,
--    same penalty_points mechanism no-shows already use (sql/23) — it feeds
--    straight into the client dashboard's points total. Cancelling a merely
--    *pending* booking is still free, since the barber hadn't committed yet.
--    Done inside the same cancellation trigger so it can't be bypassed from
--    the client side.

-- ---------- review-broadcast trigger: run as owner so tg_invoke is allowed ----------
create or replace function tg_notify_new_review()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  perform tg_invoke(jsonb_build_object('action', 'broadcast_review', 'review_id', NEW.id));
  return NEW;
end;
$$;

-- ---------- cancellation trigger: notify barber + charge the confirmed-cancel penalty ----------
create or replace function tg_notify_cancellation()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if NEW.status = 'cancelled' and OLD.status is distinct from 'cancelled' and NEW.cancelled_by = 'client' then
    -- barber already committed to a confirmed slot → 500-point penalty;
    -- a still-pending booking costs nothing to drop
    if OLD.status = 'confirmed' and NEW.client_id is not null then
      update clients set penalty_points = penalty_points + 500 where id = NEW.client_id;
    end if;
    perform tg_invoke(jsonb_build_object('action', 'notify_cancellation', 'booking_id', NEW.id));
  end if;
  return NEW;
end;
$$;
