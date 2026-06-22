// cancel-order — Supabase Edge Function
// Called when the buyer cancels an in-progress order, or when the seller
// declines, or automatically when a listing is deleted with active orders.
//
// Because orders use manual-capture escrow, the buyer's money is only an
// authorisation HOLD until receipt is confirmed. Cancelling therefore:
//   • cancels the uncaptured PaymentIntent  → releases the hold (no charge), OR
//   • refunds the PaymentIntent             → if it was somehow already captured.
//
// Request body: { orderId: string }

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import Stripe from "https://esm.sh/stripe@14";
import { checkRateLimit, RL } from "../_shared/rateLimiter.ts";

const FUNCTION_NAME = "cancel-order";

const stripe = new Stripe(Deno.env.get("STRIPE_SECRET_KEY")!, {
  apiVersion: "2023-10-16",
  httpClient: Stripe.createFetchHttpClient(),
});

const supabaseAdmin = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
);

// States from which an order may still be cancelled. Once an order is
// complete/disputed/already-cancelled, this function refuses.
const CANCELLABLE = new Set([
  "pending",
  "seller_accepted",
  "meetup_agreed",
  "awaiting_confirmation",
]);

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

    // Caller may be an authenticated user (buyer or seller) OR the internal
    // cron/service path (used when a listing deletion cascades cancellations).
    let callerUserId: string | null = null;
    const cronSecret   = Deno.env.get("CRON_SECRET");
    const incomingCron = req.headers.get("X-Cron-Secret");
    const isCron       = cronSecret != null && incomingCron === cronSecret;

    if (!isCron && callerToken) {
      const { data: { user } } = await supabaseAdmin.auth.getUser(callerToken);
      callerUserId = user?.id ?? null;
    }
    userId = callerUserId;

    if (!isCron && !callerUserId) return errorResponse(401, "Unauthorized");

    // Rate limit user-initiated cancellations (skip for the internal cron path)
    if (callerUserId) {
      const rl = await checkRateLimit(supabaseAdmin, callerUserId, RL.CANCEL_ORDER);
      if (!rl.allowed) return rl.response!;
    }

    body = await req.json();
    const { orderId } = body as { orderId: string };
    if (!orderId) return errorResponse(400, "Missing orderId");

    const { data: order, error: orderError } = await supabaseAdmin
      .from("orders").select("*").eq("id", orderId).single();

    if (orderError || !order) return errorResponse(404, "Order not found");

    // Only the buyer or the seller (or the internal cron) may cancel.
    if (!isCron && callerUserId !== order.buyer_id && callerUserId !== order.seller_id) {
      await logError(callerUserId, "Unauthorised cancel attempt", "FORBIDDEN", { orderId });
      return errorResponse(403, "You are not a party to this order");
    }

    // Idempotent: already cancelled → succeed without touching Stripe again.
    if (order.status === "cancelled") {
      return new Response(JSON.stringify({ success: true, alreadyCancelled: true }), {
        headers: { "Content-Type": "application/json" }, status: 200,
      });
    }

    if (!CANCELLABLE.has(order.status)) {
      return errorResponse(400, `Order in state '${order.status}' can no longer be cancelled`);
    }

    // ── Release the buyer's money ───────────────────────────────────────────
    if (order.stripe_payment_intent_id) {
      const pi = await stripe.paymentIntents.retrieve(order.stripe_payment_intent_id);

      if (pi.status === "succeeded") {
        // Funds were captured (edge case) — issue a full refund.
        await stripe.refunds.create({
          payment_intent: order.stripe_payment_intent_id,
          metadata: { order_id: orderId, reason: "order_cancelled" },
        });
      } else if (pi.status !== "canceled") {
        // Uncaptured authorisation hold — cancelling releases it, no charge made.
        await stripe.paymentIntents.cancel(order.stripe_payment_intent_id);
      }
      // pi.status === "canceled" → nothing to do
    }

    // ── Mark the order cancelled ────────────────────────────────────────────
    const { error: updateError } = await supabaseAdmin.from("orders").update({
      status:        "cancelled",
      escrow_status: "released",
      cancelled_at:  new Date().toISOString(),
    }).eq("id", orderId);

    if (updateError) {
      await logError(userId, updateError.message, "DB_UPDATE_FAILED", { orderId });
      return errorResponse(500, "An unexpected error occurred");
    }

    return new Response(JSON.stringify({ success: true }), {
      headers: { "Content-Type": "application/json" }, status: 200,
    });

  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    console.error("[cancel-order] UNHANDLED_EXCEPTION:", message, err);
    await logError(userId, message, "UNHANDLED_EXCEPTION", body);
    return errorResponse(500, "An unexpected error occurred");
  }
});

function errorResponse(status: number, message: string) {
  return new Response(JSON.stringify({ error: message }), {
    headers: { "Content-Type": "application/json" }, status,
  });
}
