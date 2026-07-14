// Ustara Click.uz payment webhook — confirms the 20% booking deposit.
//
// Deploy once via Supabase Dashboard -> Edge Functions -> New Function
// (name it exactly "click-payment") -> paste this file's contents -> Deploy.
// Then set one function secret (Edge Functions -> click-payment -> Secrets):
//   CLICK_SECRET_KEY   — issued by Click when your merchant account is approved
// SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY are injected automatically.
//
// You'll also need to put your CLICK_MERCHANT_ID and CLICK_SERVICE_ID into
// platform_settings (admin.html -> Payments -> Click settings) — those two
// aren't secret, they go straight into the public checkout link the client
// is sent to: https://my.click.uz/services/pay?service_id=...&merchant_id=...
//
// Click calls THIS endpoint's URL twice per payment (as its "Prepare" and
// "Complete" webhook), form-encoded, signed with CLICK_SECRET_KEY. Nothing
// else calls this function — there's no "create invoice" step, Click's
// checkout link is enough to start a payment.
//
// Set this function's URL as both the Prepare and Complete webhook URL in
// Click's merchant cabinet — this file dispatches on the `action` field
// (0 = Prepare, 1 = Complete) the same way the real Click docs describe.

import { createClient } from "npm:@supabase/supabase-js@2";

const SECRET_KEY = Deno.env.get("CLICK_SECRET_KEY") ?? "";

const supabase = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
);

// Click error codes, per their Shop API v2 docs.
const ERR = {
  SUCCESS: 0,
  SIGN_FAILED: -1,
  AMOUNT_MISMATCH: -2,
  ACTION_NOT_FOUND: -3,
  ALREADY_PAID: -4,
  TRANSACTION_NOT_FOUND: -6,
  TRANSACTION_CANCELLED: -9,
};

async function md5(input: string): Promise<string> {
  const buf = await crypto.subtle.digest("MD5", new TextEncoder().encode(input));
  return Array.from(new Uint8Array(buf)).map((b) => b.toString(16).padStart(2, "0")).join("");
}

function jsonResponse(body: Record<string, unknown>) {
  return new Response(JSON.stringify(body), {
    status: 200,
    headers: { "Content-Type": "application/json" },
  });
}

Deno.serve(async (req) => {
  try {
    const ct = req.headers.get("content-type") ?? "";
    const raw = ct.includes("application/json") ? await req.json() : Object.fromEntries(await req.formData());

    const clickTransId = String(raw.click_trans_id ?? "");
    const serviceId = String(raw.service_id ?? "");
    const merchantTransId = String(raw.merchant_trans_id ?? ""); // = booking.id
    const amount = parseFloat(String(raw.amount ?? "0"));
    const action = String(raw.action ?? "");
    const signTime = String(raw.sign_time ?? "");
    const signString = String(raw.sign_string ?? "");
    const merchantPrepareId = String(raw.merchant_prepare_id ?? "");

    const expectedSign =
      action === "0"
        ? await md5(`${clickTransId}${serviceId}${SECRET_KEY}${merchantTransId}${amount}${action}${signTime}`)
        : await md5(`${clickTransId}${serviceId}${SECRET_KEY}${merchantTransId}${merchantPrepareId}${amount}${action}${signTime}`);

    if (!SECRET_KEY || signString !== expectedSign) {
      return jsonResponse({ click_trans_id: clickTransId, merchant_trans_id: merchantTransId, error: ERR.SIGN_FAILED, error_note: "Sign check failed" });
    }

    const { data: booking } = await supabase
      .from("bookings")
      .select("id, deposit_amount, deposit_status")
      .eq("id", merchantTransId)
      .maybeSingle();

    if (!booking) {
      return jsonResponse({ click_trans_id: clickTransId, merchant_trans_id: merchantTransId, error: ERR.TRANSACTION_NOT_FOUND, error_note: "Booking not found" });
    }
    if (Math.round((booking.deposit_amount ?? 0) * 100) !== Math.round(amount * 100)) {
      return jsonResponse({ click_trans_id: clickTransId, merchant_trans_id: merchantTransId, error: ERR.AMOUNT_MISMATCH, error_note: "Incorrect amount" });
    }

    if (action === "0") {
      // Prepare: reserve the transaction, don't mark paid yet.
      if (booking.deposit_status === "paid") {
        return jsonResponse({ click_trans_id: clickTransId, merchant_trans_id: merchantTransId, error: ERR.ALREADY_PAID, error_note: "Already paid" });
      }
      await supabase.from("bookings").update({ click_trans_id: clickTransId }).eq("id", booking.id);
      return jsonResponse({
        click_trans_id: clickTransId,
        merchant_trans_id: merchantTransId,
        merchant_prepare_id: booking.id,
        error: ERR.SUCCESS,
        error_note: "Success",
      });
    }

    if (action === "1") {
      // Complete: money has moved, mark the deposit paid.
      if (booking.deposit_status === "paid") {
        return jsonResponse({ click_trans_id: clickTransId, merchant_trans_id: merchantTransId, merchant_confirm_id: booking.id, error: ERR.ALREADY_PAID, error_note: "Already paid" });
      }
      const clickError = parseInt(String(raw.error ?? "0"), 10);
      if (clickError < 0) {
        return jsonResponse({ click_trans_id: clickTransId, merchant_trans_id: merchantTransId, merchant_confirm_id: booking.id, error: ERR.TRANSACTION_CANCELLED, error_note: "Transaction cancelled" });
      }
      await supabase.from("bookings").update({
        deposit_status: "paid",
        deposit_paid_at: new Date().toISOString(),
        click_trans_id: clickTransId,
      }).eq("id", booking.id);
      return jsonResponse({
        click_trans_id: clickTransId,
        merchant_trans_id: merchantTransId,
        merchant_confirm_id: booking.id,
        error: ERR.SUCCESS,
        error_note: "Success",
      });
    }

    return jsonResponse({ click_trans_id: clickTransId, merchant_trans_id: merchantTransId, error: ERR.ACTION_NOT_FOUND, error_note: "Action not found" });
  } catch (e) {
    console.error("click-payment error:", e);
    return jsonResponse({ error: ERR.TRANSACTION_NOT_FOUND, error_note: String(e) });
  }
});
