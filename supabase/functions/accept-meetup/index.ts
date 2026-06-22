// accept-meetup — Supabase Edge Function
// The party who did NOT propose the meetup accepts the current proposal,
// flipping the order from 'seller_accepted' to 'meetup_agreed'.
//
// Request body: { orderId: string }

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { checkRateLimit, RL } from "../_shared/rateLimiter.ts";

const FUNCTION_NAME = "accept-meetup";

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

    let callerUserId: string | null = null;
    if (callerToken) {
      const { data: { user } } = await supabaseAdmin.auth.getUser(callerToken);
      callerUserId = user?.id ?? null;
    }
    userId = callerUserId;

    if (!callerUserId) return errorResponse(401, "Unauthorized");

    const rl = await checkRateLimit(supabaseAdmin, callerUserId, RL.ACCEPT_MEETUP);
    if (!rl.allowed) return rl.response!;

    body = await req.json();
    const { orderId } = body as { orderId: string };
    if (!orderId) return errorResponse(400, "Missing orderId");

    const { data: order, error: orderError } = await supabaseAdmin
      .from("orders").select("*").eq("id", orderId).single();

    if (orderError || !order) return errorResponse(404, "Order not found");

    const isBuyer  = callerUserId === order.buyer_id;
    const isSeller = callerUserId === order.seller_id;
    if (!isBuyer && !isSeller) {
      await logError(callerUserId, "Unauthorised meetup acceptance", "FORBIDDEN", { orderId });
      return errorResponse(403, "You are not a party to this order");
    }

    // A proposal can be accepted from:
    //   • seller_accepted → the counter-party accepts the seller's (or a
    //     re-issued) proposal, OR
    //   • pending → the seller accepts a meetup the buyer suggested before the
    //     seller had formally accepted the order (this one step does both).
    if (order.status !== "seller_accepted" && order.status !== "pending") {
      return errorResponse(400, `Order in state '${order.status}' has no meetup to accept`);
    }
    if (!order.meetup_proposed_by || !order.meetup_location || !order.meetup_date) {
      return errorResponse(400, "No meetup has been proposed yet");
    }

    // The accepter must be the counter-party — you cannot accept your own proposal.
    const callerRole = isBuyer ? "buyer" : "seller";
    if (order.meetup_proposed_by === callerRole) {
      return errorResponse(400, "You proposed this meetup; the other party must accept it");
    }
    // From pending, only the seller can accept (the buyer is the proposer).
    if (order.status === "pending" && callerRole !== "seller") {
      return errorResponse(400, "The seller must accept the order first");
    }

    const now = new Date().toISOString();
    const { error: updateError } = await supabaseAdmin.from("orders").update({
      status:             "meetup_agreed",
      meetup_agreed_at:   now,
      // Record the seller-accepted moment even when we jump straight from
      // pending → meetup_agreed.
      seller_accepted_at: order.seller_accepted_at ?? now,
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
    console.error("[accept-meetup] UNHANDLED_EXCEPTION:", message, err);
    await logError(userId, message, "UNHANDLED_EXCEPTION", body);
    return errorResponse(500, "An unexpected error occurred");
  }
});

function errorResponse(status: number, message: string) {
  return new Response(JSON.stringify({ error: message }), {
    headers: { "Content-Type": "application/json" }, status,
  });
}
