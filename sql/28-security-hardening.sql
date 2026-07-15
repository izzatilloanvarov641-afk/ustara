-- Ustara: security hardening — found during an adversarial self-review
--
-- Three real issues, all verified live before this migration was written:
--
-- 1. platform_settings.payout_card_number/payout_card_name (the founder's
--    real bank card) was readable by `anon` — literally anyone on the
--    internet, no login required, confirmed with a plain unauthenticated
--    curl against the REST API. Restrict select to authenticated users;
--    barbers legitimately need this to know where to send commission.
--
-- 2. tg_invoke() and send_due_rebook_reminders() are meant to be called
--    only by pg_cron/triggers, but neither had an explicit grant — so
--    Postgres's default PUBLIC execute privilege applied, and ANY
--    authenticated user (a normal client account) could call them
--    directly via /rest/v1/rpc/. Confirmed live: an ordinary client
--    token successfully invoked tg_invoke with an arbitrary action body,
--    letting them re-trigger Telegram broadcasts / reminder blasts
--    (and burn the Gemini API quota) on demand. Revoke public execute;
--    only the function owner (which cron/triggers run as) can call them.
--
-- 3. Neither function set search_path, the standard SECURITY DEFINER
--    hardening (prevents a schema-search-path hijack from redirecting
--    an unqualified table/function reference inside the function body).

revoke execute on function tg_invoke(jsonb) from public, anon, authenticated;
revoke execute on function send_due_rebook_reminders() from public, anon, authenticated;

alter function tg_invoke(jsonb) set search_path = public;
alter function send_due_rebook_reminders() set search_path = public;

drop policy if exists "Anyone can view payout settings" on platform_settings;
create policy "Authenticated users can view payout settings"
  on platform_settings for select
  to authenticated
  using (true);
