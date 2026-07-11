// Ustara Telegram bot — single Edge Function, action-routed.
//
// Deploy this once via Supabase Dashboard → Edge Functions → New Function
// (name it exactly "telegram-bot") → paste this file's contents → Deploy.
// Then set two function secrets (Edge Functions → telegram-bot → Secrets):
//   TELEGRAM_BOT_TOKEN   — from @BotFather
//   GEMINI_API_KEY       — from Google AI Studio (free tier)
// SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are injected automatically by
// Supabase into every Edge Function — nothing to set for those.
//
// Postgres never talks to Telegram/Gemini directly; it just calls this
// function with a small JSON body (see sql/15-telegram-bot.sql):
//   { action: "poll_updates" }                    — every ~1 min, cron
//   { action: "send_reminders" }                  — every 10 min, cron
//   { action: "broadcast_review", review_id }      — trigger, on new review

import { createClient } from "npm:@supabase/supabase-js@2";

// Base URL for the "View profile" / "Book now" buttons sent in Telegram messages.
const SITE_URL = "https://ustara-three.vercel.app";

const BOT_TOKEN = Deno.env.get("TELEGRAM_BOT_TOKEN") ?? "";
const GEMINI_KEY = Deno.env.get("GEMINI_API_KEY") ?? "";

const supabase = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
);

type TgButton = { text: string; url: string };

async function sendTelegramMessage(chatId: number, text: string, buttons?: TgButton[]) {
  if (!BOT_TOKEN) {
    console.error("TELEGRAM_BOT_TOKEN not set — cannot send message");
    return;
  }
  try {
    const body: Record<string, unknown> = {
      chat_id: chatId,
      text,
      parse_mode: "HTML",
      disable_web_page_preview: true,
    };
    if (buttons && buttons.length) {
      body.reply_markup = { inline_keyboard: [buttons.map((b) => ({ text: b.text, url: b.url }))] };
    }
    const res = await fetch(`https://api.telegram.org/bot${BOT_TOKEN}/sendMessage`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(body),
    });
    if (!res.ok) {
      console.error("sendMessage failed:", chatId, await res.text());
    }
  } catch (e) {
    console.error("sendMessage error:", chatId, e);
  }
}

// The review comment itself is always shown verbatim (real social proof,
// never rewritten). Gemini's job is only the closing invite line — one
// short, catchy call-to-action that reads differently almost every time.
// A random "angle" in the prompt plus high temperature gives the variety;
// if Gemini is down we fall back to a rotating set of prewritten lines.
const INVITE_ANGLES = [
  "urgency — good chairs fill up fast",
  "the feeling of walking out with a fresh cut",
  "complimenting this barber's craft",
  "getting ready for the weekend or a big day",
  "treating yourself, self-care",
  "no more queues — book a time and walk in",
  "your next haircut is overdue",
];

const FALLBACK_INVITES = [
  "💈 Book your slot — the barber is waiting.",
  "✂️ One tap and the chair is yours.",
  "🔥 Slots go fast — grab yours now.",
  "💈 Your next fresh cut is one tap away.",
  "✂️ Don't wait in line — book your time.",
];

async function generateInviteLine(barberName: string, rating: number, comment: string): Promise<string> {
  const fallback = FALLBACK_INVITES[Math.floor(Math.random() * FALLBACK_INVITES.length)];
  if (!GEMINI_KEY) return fallback;
  try {
    const angle = INVITE_ANGLES[Math.floor(Math.random() * INVITE_ANGLES.length)];
    const prompt =
      `You write closing lines for push notifications in a barber-booking app in Tashkent.\n` +
      `A client just left a ${rating}-star review for barber "${barberName}".` +
      (comment ? ` The review says: "${comment}".\n` : `\n`) +
      `Write ONE short invite line (under 90 characters) nudging other clients to book this barber.\n` +
      `Angle to use this time: ${angle}.\n` +
      `Write it in the same language as the review text; if there is no review text, use Uzbek.\n` +
      `You may start with one fitting emoji. No hashtags, no quotes around the line, ` +
      `no invented facts about the barber — just the invitation. Reply with the line only.`;
    const res = await fetch(
      `https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=${GEMINI_KEY}`,
      {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          contents: [{ parts: [{ text: prompt }] }],
          generationConfig: { temperature: 1.3, topP: 0.95, maxOutputTokens: 60 },
        }),
      },
    );
    if (!res.ok) {
      console.error("Gemini call failed:", await res.text());
      return fallback;
    }
    const json = await res.json();
    const out = json?.candidates?.[0]?.content?.parts?.[0]?.text?.trim()?.replace(/^["'«]|["'»]$/g, "");
    return out || fallback;
  } catch (e) {
    console.error("Gemini error:", e);
    return fallback;
  }
}

// ---------- action: poll_updates ----------
async function pollUpdates() {
  if (!BOT_TOKEN) return;
  const { data: state } = await supabase
    .from("telegram_poll_state")
    .select("last_update_id")
    .eq("id", 1)
    .single();
  const offset = (state?.last_update_id ?? 0) + 1;

  const res = await fetch(
    `https://api.telegram.org/bot${BOT_TOKEN}/getUpdates?offset=${offset}&timeout=0`,
  );
  if (!res.ok) {
    console.error("getUpdates failed:", await res.text());
    return;
  }
  const { result: updates } = await res.json();
  if (!Array.isArray(updates) || updates.length === 0) return;

  let maxUpdateId = offset - 1;
  for (const update of updates) {
    maxUpdateId = Math.max(maxUpdateId, update.update_id);
    const text: string | undefined = update?.message?.text;
    const chatId: number | undefined = update?.message?.chat?.id;
    if (!text || !chatId) continue;

    const match = text.match(/^\/start\s+(\S+)/);
    if (!match) continue;
    const code = match[1].toUpperCase();

    const { data: linkRow } = await supabase
      .from("telegram_link_codes")
      .select("*")
      .eq("code", code)
      .maybeSingle();
    if (!linkRow) {
      await sendTelegramMessage(chatId, "That link code has expired — go back to Ustara and tap Connect Telegram again.");
      continue;
    }

    const table = linkRow.role === "barber" ? "barbers" : "clients";
    const { error: updateErr } = await supabase
      .from(table)
      .update({ telegram_chat_id: chatId })
      .eq("id", linkRow.user_id);
    await supabase.from("telegram_link_codes").delete().eq("code", code);

    if (updateErr) {
      console.error("Failed to link telegram_chat_id:", updateErr);
      await sendTelegramMessage(chatId, "Something went wrong connecting your account — please try again.");
    } else {
      await sendTelegramMessage(
        chatId,
        linkRow.role === "barber"
          ? "✅ Connected! You'll get a reminder here before every confirmed booking."
          : "✅ Connected! You'll get a reminder here before your booking, plus the occasional great review from other barbers on Ustara.",
      );
    }
  }

  await supabase
    .from("telegram_poll_state")
    .update({ last_update_id: maxUpdateId })
    .eq("id", 1);
}

// ---------- action: send_reminders ----------
async function sendReminders() {
  const now = new Date();
  const in24h = new Date(now.getTime() + 24 * 3600_000);
  const in24hWindowStart = new Date(now.getTime() + 23.75 * 3600_000);
  const in2h = new Date(now.getTime() + 2 * 3600_000);
  const in2hWindowStart = new Date(now.getTime() + 1.75 * 3600_000);

  const selectCols =
    "id, start_time, service_key, barber_id, client_id, reminded_24h, reminded_2h, " +
    "barbers(full_name, telegram_chat_id), clients(full_name, telegram_chat_id)";

  const { data: due24h } = await supabase
    .from("bookings")
    .select(selectCols)
    .eq("status", "confirmed")
    .eq("reminded_24h", false)
    .gte("start_time", in24hWindowStart.toISOString())
    .lte("start_time", in24h.toISOString());

  const { data: due2h } = await supabase
    .from("bookings")
    .select(selectCols)
    .eq("status", "confirmed")
    .eq("reminded_2h", false)
    .gte("start_time", in2hWindowStart.toISOString())
    .lte("start_time", in2h.toISOString());

  for (const [batch, flag, label] of [
    [due24h ?? [], "reminded_24h", "tomorrow"],
    [due2h ?? [], "reminded_2h", "in about 2 hours"],
  ] as const) {
    for (const b of batch as any[]) {
      const when = new Date(b.start_time).toLocaleString("en-US", {
        weekday: "short", hour: "2-digit", minute: "2-digit",
      });
      if (b.clients?.telegram_chat_id) {
        await sendTelegramMessage(
          b.clients.telegram_chat_id,
          `✂️ Reminder: your haircut with <b>${escapeHtml(b.barbers?.full_name ?? "your barber")}</b> is ${label} (${when}).`,
          [{ text: "📅 View booking", url: `${SITE_URL}/client-dashboard.html` }],
        );
      }
      if (b.barbers?.telegram_chat_id) {
        await sendTelegramMessage(
          b.barbers.telegram_chat_id,
          `✂️ Reminder: you have a booking with <b>${escapeHtml(b.clients?.full_name ?? "a client")}</b> ${label} (${when}).`,
          [{ text: "📅 View bookings", url: `${SITE_URL}/barber-dashboard.html` }],
        );
      }
      await supabase.from("bookings").update({ [flag]: true }).eq("id", b.id);
    }
  }
}

// ---------- action: broadcast_review ----------
async function broadcastReview(reviewId: string) {
  const { data: review } = await supabase
    .from("reviews")
    .select("id, rating, comment, client_id, barber_id, barbers(full_name), clients(full_name)")
    .eq("id", reviewId)
    .single();
  if (!review) return;

  const barberName = (review as any).barbers?.full_name ?? "a barber";
  const rawComment = (review.comment ?? "").trim();
  const inviteLine = await generateInviteLine(barberName, review.rating, rawComment);

  // Real comment shown verbatim as social proof; Gemini only writes the
  // closing invite line. Layout: barber + stars, quoted review, invite.
  const stars = "⭐".repeat(review.rating);
  const header = `💈 <b>${escapeHtml(barberName)}</b>  ${stars}`;
  const quote = rawComment ? `\n\n<i>“${escapeHtml(rawComment)}”</i>` : "";
  const text = `${header}${quote}\n\n${escapeHtml(inviteLine)}`;

  const profileUrl = `${SITE_URL}/profile.html?id=${review.barber_id}`;

  // v1: fan out to every Telegram-linked client except the reviewer.
  // Fine at current volume — once there are many reviews/clients this
  // should add rate-limiting or opt-in targeting instead of a full blast.
  const { data: recipients } = await supabase
    .from("clients")
    .select("telegram_chat_id")
    .not("telegram_chat_id", "is", null)
    .neq("id", review.client_id);

  for (const r of recipients ?? []) {
    await sendTelegramMessage(r.telegram_chat_id, text, [
      { text: "👀 View profile", url: profileUrl },
      { text: "📅 Book now", url: profileUrl },
    ]);
  }
}

function escapeHtml(s: string) {
  return s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
}

Deno.serve(async (req) => {
  try {
    const body = await req.json().catch(() => ({}));
    const action = body?.action;

    if (action === "poll_updates") await pollUpdates();
    else if (action === "send_reminders") await sendReminders();
    else if (action === "broadcast_review" && body.review_id) await broadcastReview(body.review_id);
    else return new Response(JSON.stringify({ ok: false, error: "unknown action" }), { status: 400 });

    return new Response(JSON.stringify({ ok: true }), { status: 200 });
  } catch (e) {
    console.error("telegram-bot error:", e);
    // always 200 so pg_net doesn't pile up retries on a bad request
    return new Response(JSON.stringify({ ok: false, error: String(e) }), { status: 200 });
  }
});
