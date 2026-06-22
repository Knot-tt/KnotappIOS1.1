// propose-meetup — Supabase Edge Function
// Either party (buyer or seller) proposes — or counter-proposes — a meetup
// location + time for an in-progress order. This only records the proposal;
// the order stays in 'seller_accepted' until the OTHER party accepts it
// (see accept-meetup), which is what flips it to 'meetup_agreed'.
//
// A counter-proposal made after a meetup was already agreed re-opens the
// negotiation: the order drops back to 'seller_accepted' so the other side
// must confirm the new details before it counts as agreed again.
//
// Request body: { orderId: string, location: string, dateISO: string, proposedBy: "buyer" | "seller" }

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { checkRateLimit, RL } from "../_shared/rateLimiter.ts";

const FUNCTION_NAME = "propose-meetup";

const supabaseAdmin = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
);

// A meetup can be proposed while the order is still pending (the seller's first
// proposal doubles as accepting the order; the buyer may also suggest a spot
// before the seller has accepted) and while coordinating (counter-proposals).
const PROPOSABLE = new Set(["pending", "seller_accepted", "meetup_agreed"]);

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

    const rl = await checkRateLimit(supabaseAdmin, callerUserId, RL.PROPOSE_MEETUP);
    if (!rl.allowed) return rl.response!;

    body = await req.json();
    const { orderId, location, dateISO, proposedBy } =
      body as { orderId: string; location: string; dateISO: string; proposedBy: string };

    if (!orderId)                                    return errorResponse(400, "Missing orderId");
    if (!location || !location.trim())               return errorResponse(400, "Missing location");
    if (!dateISO)                                    return errorResponse(400, "Missing dateISO");
    if (proposedBy !== "buyer" && proposedBy !== "seller")
      return errorResponse(400, "proposedBy must be 'buyer' or 'seller'");

    const { data: order, error: orderError } = await supabaseAdmin
      .from("orders").select("*").eq("id", orderId).single();

    if (orderError || !order) return errorResponse(404, "Order not found");

    // Only the buyer or seller may propose, and the claimed role must match.
    const isBuyer  = callerUserId === order.buyer_id;
    const isSeller = callerUserId === order.seller_id;
    if (!isBuyer && !isSeller) {
      await logError(callerUserId, "Unauthorised meetup proposal", "FORBIDDEN", { orderId });
      return errorResponse(403, "You are not a party to this order");
    }
    if ((proposedBy === "buyer" && !isBuyer) || (proposedBy === "seller" && !isSeller)) {
      return errorResponse(403, "proposedBy does not match the caller");
    }

    if (!PROPOSABLE.has(order.status)) {
      return errorResponse(400, `Order in state '${order.status}' cannot have a meetup proposed`);
    }

    // Decide the resulting status from WHO proposed:
    //   • seller proposing  → they're accepting the order, so → seller_accepted
    //   • buyer proposing while pending → seller hasn't accepted yet, stay pending
    //   • buyer counter-proposing after coordination began → back to seller_accepted
    //     so the proposal must be re-accepted (never silently stays agreed)
    const newStatus =
      proposedBy === "seller"
        ? "seller_accepted"
        : (order.status === "pending" ? "pending" : "seller_accepted");

    const update: Record<string, unknown> = {
      meetup_location:    location,
      meetup_date:        dateISO,
      meetup_proposed_by: proposedBy,
      status:             newStatus,
    };
    // Stamp the seller-accepted moment the first time we enter that state.
    if (newStatus === "seller_accepted" && !order.seller_accepted_at) {
      update.seller_accepted_at = new Date().toISOString();
    }

    const { error: updateError } = await supabaseAdmin.from("orders")
      .update(update).eq("id", orderId);

    if (updateError) {
      await logError(userId, updateError.message, "DB_UPDATE_FAILED", { orderId });
      return errorResponse(500, "An unexpected error occurred");
    }

    return new Response(JSON.stringify({ success: true }), {
      headers: { "Content-Type": "application/json" }, status: 200,
    });

  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    console.error("[propose-meetup] UNHANDLED_EXCEPTION:", message, err);
    await logError(userId, message, "UNHANDLED_EXCEPTION", body);
    return errorResponse(500, "An unexpected error occurred");
  }
});

function errorResponse(status: number, message: string) {
  return new Response(JSON.stringify({ error: message }), {
    headers: { "Content-Type": "application/json" }, status,
  });
}
