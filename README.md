# Ustara

Barber booking platform — Tashkent. Reputation belongs to the barber, not the shop.

## Structure

- `index.html` — landing page + waitlist signup
- `browse.html` — client-facing barber search
- `barber-signup.html` — new barber signup (creates account + profile)
- `barber-login.html` — returning barber login
- `barber-dashboard.html` — barber's private panel (edit profile, publish toggle, bookings)
- `client-auth.html` — client signup/login
- `client-dashboard.html` — client's private panel (account, bookings)
- `sql/` — run these in the Supabase SQL Editor, **in order** (01, then 02, then 03)

## Stack

- Plain HTML/CSS/JS, no build step — deploy as static files
- [Supabase](https://supabase.com) — auth, database
- [Vercel](https://vercel.com) — hosting

## Supabase project

Project URL and anon key are already wired into the pages. Project: `gbvfesorkmsxugpvcuqy`.

Before barber/client signup works, in the Supabase dashboard:
**Authentication → Providers → Email → turn OFF "Confirm email"** (MVP setting — revisit before real launch).

## Local dev

Just open `index.html` in a browser — no server or build needed. All pages link to each other by relative filename, so keep them in the same folder.

## Deploying

Push to GitHub, then import the repo in Vercel (Framework Preset: **Other** — it's static HTML, no build command needed). Every push to `main` auto-redeploys.

## Status

Working: waitlist capture, barber signup/login/dashboard, client signup/login/dashboard, browse + search/filter, full EN/UZ/RU localization, responsive layout.

Not yet built: the actual booking flow (barber-defined time slots → client picks a slot → confirmation). The `bookings` table and RLS policies exist and both dashboards already read from it — this is the next feature to build.
