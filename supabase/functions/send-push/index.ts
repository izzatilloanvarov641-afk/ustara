// Ustara: deliver a notification row as a web push
//
// Wired to a Supabase Database Webhook on `notifications` INSERT, so anything
// that writes a notification — the new-booking trigger, the confirm/decline
// trigger, or future code — reaches the device without extra work.
//
// A notification row addresses either a barber or a client, and in both cases
// that id IS the auth user id (barbers.id and clients.id both reference
// auth.users), so one lookup against push_subscriptions covers both.
//
// Secrets this needs (set with `supabase secrets set`):
//   VAPID_PUBLIC_KEY, VAPID_PRIVATE_KEY, VAPID_SUBJECT (mailto:you@ustara.org)
// SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are injected automatically.

import webpush from 'npm:web-push@3.6.7';
import { createClient } from 'jsr:@supabase/supabase-js@2';

const VAPID_PUBLIC = Deno.env.get('VAPID_PUBLIC_KEY') ?? '';
const VAPID_PRIVATE = Deno.env.get('VAPID_PRIVATE_KEY') ?? '';
const VAPID_SUBJECT = Deno.env.get('VAPID_SUBJECT') ?? 'mailto:hello@ustara.org';

const supabase = createClient(
  Deno.env.get('SUPABASE_URL')!,
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
);

// What each notification type looks like on the lock screen. Uzbek, matching
// the app default; the in-app list localises separately from `type`.
function present(type: string, message: string) {
  switch (type) {
    case 'booking_inquiry':
      return {
        title: 'Yangi so\'rov',
        body: message || 'Sizga yangi band so\'rovi keldi.',
        url: '/barber-dashboard.html?view=bookings',
        tag: 'inquiry'
      };
    case 'booking_confirmed':
      return {
        title: 'Band tasdiqlandi',
        body: message || 'Sartarosh bandingizni tasdiqladi.',
        url: '/client-dashboard.html?view=bookings',
        tag: 'booking'
      };
    case 'booking_cancelled_by_barber':
      return {
        title: 'Band bekor qilindi',
        body: message || 'Bandingiz bekor qilindi.',
        url: '/client-dashboard.html?view=bookings',
        tag: 'booking'
      };
    default:
      return { title: 'Ustara', body: message || '', url: '/client-dashboard.html', tag: 'ustara' };
  }
}

Deno.serve(async (req) => {
  if (req.method !== 'POST') return new Response('Method not allowed', { status: 405 });

  if (!VAPID_PUBLIC || !VAPID_PRIVATE) {
    // Loud but non-fatal: the notification row already exists and shows in the
    // app, so a missing key must not make the webhook look like a DB failure.
    console.error('VAPID keys not configured — skipping push');
    return new Response(JSON.stringify({ skipped: 'no vapid keys' }), { status: 200 });
  }
  webpush.setVapidDetails(VAPID_SUBJECT, VAPID_PUBLIC, VAPID_PRIVATE);

  let row: Record<string, unknown>;
  try {
    const payload = await req.json();
    row = payload.record ?? payload;           // webhook shape, or a direct call
  } catch {
    return new Response('Bad JSON', { status: 400 });
  }

  const userId = (row.barber_id ?? row.client_id) as string | null;
  if (!userId) return new Response(JSON.stringify({ skipped: 'no recipient' }), { status: 200 });

  const { data: subs, error } = await supabase
    .from('push_subscriptions')
    .select('id, endpoint, p256dh, auth')
    .eq('user_id', userId);

  if (error) {
    console.error('subscription lookup failed:', error.message);
    return new Response(JSON.stringify({ error: error.message }), { status: 500 });
  }
  if (!subs || subs.length === 0) {
    return new Response(JSON.stringify({ skipped: 'no subscriptions' }), { status: 200 });
  }

  const note = present(String(row.type ?? ''), String(row.message ?? ''));
  const body = JSON.stringify(note);

  let sent = 0;
  const dead: string[] = [];

  await Promise.all(subs.map(async (s) => {
    try {
      await webpush.sendNotification(
        { endpoint: s.endpoint, keys: { p256dh: s.p256dh, auth: s.auth } },
        body
      );
      sent++;
    } catch (e) {
      const status = (e as { statusCode?: number }).statusCode;
      // 404/410 mean the browser threw the subscription away (uninstalled,
      // permission revoked). Keeping it would retry forever, so drop it.
      if (status === 404 || status === 410) dead.push(s.id);
      else console.error('push failed:', status, (e as Error).message);
    }
  }));

  if (dead.length) {
    await supabase.from('push_subscriptions').delete().in('id', dead);
  }

  return new Response(JSON.stringify({ sent, pruned: dead.length }), {
    status: 200,
    headers: { 'Content-Type': 'application/json' }
  });
});
