-- Ustara: close the real hole behind sql/28's tg_invoke() lockdown
--
-- sql/28-security-hardening.sql revoked public EXECUTE on the Postgres
-- function tg_invoke() so a client couldn't call it via /rest/v1/rpc/
-- anymore. That fixed the RPC path, but the actual network endpoint —
-- the deployed Edge Function at .../functions/v1/telegram-bot — was
-- never protected at all. Every Supabase Edge Function accepts the
-- public anon key as a valid caller (that's normal platform behavior,
-- not a misconfiguration), and the function's own code never checked
-- who was calling it. Confirmed live: a plain curl with only the public
-- anon key successfully triggered poll_updates with no session, no
-- login, nothing.
--
-- Fix: a shared secret. tg_invoke() sends it as a custom header; the
-- Edge Function (see supabase/functions/telegram-bot/index.ts) rejects
-- any request where that header doesn't match its CRON_SECRET env var.
-- This is the standard way to lock down a webhook-style endpoint that
-- has no real "calling user" to check RLS/roles against.
--
-- IMPORTANT — before running this file:
-- 1. Pick your own random secret (32+ random characters — anything works,
--    e.g. generate one at random.org or run `openssl rand -hex 32`
--    locally). Do NOT reuse a secret from anywhere else in this project.
-- 2. Replace REPLACE_WITH_YOUR_OWN_RANDOM_SECRET below with that value.
-- 3. Set the exact same value as the Edge Function's CRON_SECRET secret
--    (Dashboard → Edge Functions → telegram-bot → Secrets), then redeploy
--    supabase/functions/telegram-bot/index.ts.
-- This file only ever exists with the placeholder in git — the real
-- value lives solely in your own edited copy and in Supabase's secret
-- manager, never committed.

create or replace function tg_invoke(p_body jsonb)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  perform net.http_post(
    url := 'https://gbvfesorkmsxugpvcuqy.supabase.co/functions/v1/telegram-bot',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer sb_publishable_k7wdvlBvnpPHPNCrl9i_eg_ktsfJAst',
      'x-cron-secret', 'REPLACE_WITH_YOUR_OWN_RANDOM_SECRET'
    ),
    body := p_body
  );
exception when others then
  -- never let a Telegram/network hiccup break the booking/review flow
  -- that triggered this call
  raise warning 'tg_invoke failed: %', sqlerrm;
end;
$$;
