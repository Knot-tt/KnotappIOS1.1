// dispute-order — Supabase Edge Function
// Either party flags a problem ("Report a Problem"). This FREEZES the order:
// the buyer's authorisation hold is intentionally left in place (not captured,
// not cancelled) so the Knot team can resolve it manually. No Stripe action is
// taken here — escrow stays 'held' and the money stays frozen on both sides.
//
// Request body: { orderId: string }

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { checkRateLimit, RL } from "../_shared/rateLimiter.ts";

const FUNCTION_NAME = "dispute-order";

const supabaseAdmin = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
);

// A dispute only makes sense while there is an active hold to fight over.
const DISPUTABLE = new Set([
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

    let callerUserId: string | null = null;
    if (callerToken) {
      const { data: { user } } = await supabaseAdmin.auth.getUser(callerToken);
      callerUserId = user?.id ?? null;
    }
    userId = callerUserId;

    if (!callerUserId) return errorResponse(401, "Unauthorized");

    const rl = await checkRateLimit(supabaseAdmin, callerUserId, RL.DISPUTE_ORDER);
    if (!rl.allowed) return rl.response!;

    body = await req.json();
    const { orderId } = body as { orderId: string };
    if (!orderId) return errorResponse(400, "Missing orderId");

    const { data: order, error: orderError } = await supabaseAdmin
      .from("orders").select("*").eq("id", orderId).single();

    if (orderError || !order) return errorResponse(404, "Order not found");

    // Only the buyer or the seller may open a dispute.
    if (callerUserId !== order.buyer_id && callerUserId !== order.seller_id) {
      await logError(callerUserId, "Unauthorised dispute attempt", "FORBIDDEN", { orderId });
      return errorResponse(403, "You are not a party to this order");
    }

    // Idempotent: already disputed → succeed without re-stamping.
    if (order.status === "disputed") {
      return new Response(JSON.stringify({ success: true, alreadyDisputed: true }), {
        headers: { "Content-Type": "application/json" }, status: 200,
      });
    }

    if (!DISPUTABLE.has(order.status)) {
      return errorResponse(400, `Order in state '${order.status}' can no longer be disputed`);
    }

    // Freeze the order. Escrow deliberately stays 'held' — funds remain frozen
    // until the Knot team resolves the dispute (refund or release, done manually).
    const { error: updateError } = await supabaseAdmin.from("orders").update({
      status:       "disputed",
      escrow_status: "held",
      disputed_at:  new Date().toISOString(),
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
    console.error("[dispute-order] UNHANDLED_EXCEPTION:", message, err);
    await logError(userId, message, "UNHANDLED_EXCEPTION", body);
    return errorResponse(500, "An unexpected error occurred");
  }
});

function errorResponse(status: number, message: string) {
  return new Response(JSON.stringify({ error: message }), {
    headers: { "Content-Type": "application/json" }, status,
  });
}
