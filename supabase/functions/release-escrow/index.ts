// release-escrow — Supabase Edge Function
// Called when buyer confirms receipt, or automatically by cron after 48h.
//
// Request body: { orderId: string }

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import Stripe from "https://esm.sh/stripe@14";
import { checkRateLimit, RL } from "../_shared/rateLimiter.ts";

const FUNCTION_NAME = "release-escrow";

const stripe = new Stripe(Deno.env.get("STRIPE_SECRET_KEY")!, {
  apiVersion: "2023-10-16",
  httpClient: Stripe.createFetchHttpClient(),
});

const supabaseAdmin = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
);

async function logError(
  userId: string | null,
  errorMessage: string,
  errorCode: string,
  requestBody: Record<string, unknown>
) {
  try {
    await supabaseAdmin.from("api_error_log").insert({
      user_id: userId, function_name: FUNCTION_NAME,
      error_code: errorCode, error_message: errorMessage, request_body: requestBody,
    });
  } catch (_) { /* best-effort */ }
}

serve(async (req) => {
  let userId: string | null = null;
  let body: Record<string, unknown> = {};

  try {
    const authHeader  = req.headers.get("Authorization");
    const callerToken = authHeader?.replace("Bearer ", "");

    // Determine caller — authenticated user OR internal cron job.
    //
    // Cron auth: the pg_cron/scheduler sends a dedicated X-Cron-Secret header
    // containing CRON_SECRET (set in Supabase Dashboard → Edge Functions → Secrets).
    // This is separate from the service role key, which must NEVER travel over HTTP.
    let callerUserId: string | null = null;
    const cronSecret   = Deno.env.get("CRON_SECRET");
    const incomingCron = req.headers.get("X-Cron-Secret");
    const isCron       = cronSecret != null && incomingCron === cronSecret;

    if (!isCron && callerToken) {
      const { data: { user } } = await supabaseAdmin.auth.getUser(callerToken);
      callerUserId = user?.id ?? null;
    }
    userId = callerUserId;

    // Rate limit user-initiated releases (skip for authenticated cron)
    if (callerUserId) {
      const rl = await checkRateLimit(supabaseAdmin, callerUserId, RL.RELEASE_ESCROW);
      if (!rl.allowed) return rl.response!;
    }

    body = await req.json();
    const { orderId } = body as { orderId: string };

    const { data: order, error: orderError } = await supabaseAdmin
      .from("orders").select("*").eq("id", orderId).single();

    if (orderError || !order) return errorResponse(404, "Order not found");

    // Only the buyer (or the authenticated cron) can release
    if (!isCron && callerUserId && callerUserId !== order.buyer_id) {
      await logError(callerUserId, "Unauthorised escrow release attempt", "FORBIDDEN", { orderId });
      return errorResponse(403, "Only the buyer can release escrow");
    }

    if (order.status !== "awaiting_confirmation") {
      return errorResponse(400, `Order is in state '${order.status}', expected 'awaiting_confirmation'`);
    }

    const captured = await stripe.paymentIntents.capture(order.stripe_payment_intent_id);
    if (captured.status !== "succeeded") {
      await logError(userId, "Payment capture did not succeed", "STRIPE_CAPTURE_FAILED", { orderId, status: captured.status });
      return errorResponse(500, "An unexpected error occurred");
    }

    const { data: sellerProfile } = await supabaseAdmin
      .from("profiles").select("stripe_customer_id").eq("id", order.seller_id).single();

    let transferId: string | undefined;
    if (sellerProfile?.stripe_customer_id) {
      const transfer = await stripe.transfers.create({
        amount:      order.payout_cents,
        currency:    "sgd",
        destination: sellerProfile.stripe_customer_id,
        metadata:    { order_id: orderId },
      });
      transferId = transfer.id;
    }

    await supabaseAdmin.from("orders").update({
      status: "complete", escrow_status: "released",
      complete_at: new Date().toISOString(), stripe_transfer_id: transferId,
    }).eq("id", orderId);

    return new Response(JSON.stringify({ success: true }), {
      headers: { "Content-Type": "application/json" }, status: 200,
    });

  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    await logError(userId, message, "UNHANDLED_EXCEPTION", body);
    return errorResponse(500, "An unexpected error occurred");
  }
});

function errorResponse(status: number, message: string) {
  return new Response(JSON.stringify({ error: message }), {
    headers: { "Content-Type": "application/json" }, status,
  });
}
