// confirm-knot-membership — Supabase Edge Function
// Called by the client after the Stripe PaymentSheet completes.
// Verifies the PaymentIntent succeeded in Stripe, then inserts the
// user into knot_members using the admin client (bypasses RLS).
//
// Request body:  { payment_intent_id: string, knot_id: string }
// Response:      { success: true }

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import Stripe from "https://esm.sh/stripe@14";
import { checkRateLimit, RL } from "../_shared/rateLimiter.ts";

const FUNCTION_NAME = "confirm-knot-membership";

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
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) return errorResponse(401, "Missing auth header");

    const { data: { user }, error: authError } = await supabaseAdmin.auth.getUser(
      authHeader.replace("Bearer ", "")
    );
    if (authError || !user) return errorResponse(401, "Unauthorized");
    userId = user.id;

    // Rate limit (reuse CREATE_KNOT_PAYMENT bucket — same user, same knot)
    const rl = await checkRateLimit(supabaseAdmin, userId, RL.CREATE_KNOT_PAYMENT);
    if (!rl.allowed) return rl.response!;

    body = await req.json();
    const { payment_intent_id, knot_id } = body as {
      payment_intent_id: string;
      knot_id: string;
    };
    if (!payment_intent_id) return errorResponse(400, "Missing payment_intent_id");
    if (!knot_id) return errorResponse(400, "Missing knot_id");

    // 1. Verify the PaymentIntent in Stripe
    const pi = await stripe.paymentIntents.retrieve(payment_intent_id);
    if (pi.status !== "succeeded") {
      return errorResponse(400, `Payment not confirmed (status: ${pi.status})`);
    }

    // 2. Guard: metadata must match to prevent cross-knot abuse
    if (pi.metadata?.knot_id !== knot_id || pi.metadata?.user_id !== userId) {
      await logError(userId, "Metadata mismatch on PaymentIntent", "METADATA_MISMATCH", body);
      return errorResponse(403, "Payment does not match this Knot or user");
    }

    // 3. Guard: not already a member
    const { data: existing } = await supabaseAdmin
      .from("knot_members")
      .select("id")
      .eq("knot_id", knot_id)
      .eq("user_id", userId)
      .maybeSingle();
    if (existing) {
      // Idempotent — already a member is fine
      return new Response(JSON.stringify({ success: true }), {
        headers: { "Content-Type": "application/json" }, status: 200,
      });
    }

    // 4. Insert member (admin client bypasses RLS)
    const { error: insertError } = await supabaseAdmin
      .from("knot_members")
      .insert({ knot_id, user_id: userId, role: "member" });

    if (insertError) {
      await logError(userId, insertError.message, "INSERT_FAILED", body);
      return errorResponse(500, "Could not add you as a member");
    }

    console.log(`[${FUNCTION_NAME}] User ${userId} joined knot ${knot_id} after payment ${payment_intent_id}`);

    return new Response(
      JSON.stringify({ success: true }),
      { headers: { "Content-Type": "application/json" }, status: 200 }
    );

  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    console.error(`[${FUNCTION_NAME}] UNHANDLED_EXCEPTION:`, message);
    await logError(userId, message, "UNHANDLED_EXCEPTION", body);
    return errorResponse(500, "An unexpected error occurred");
  }
});

function errorResponse(status: number, message: string) {
  return new Response(JSON.stringify({ error: message }), {
    headers: { "Content-Type": "application/json" }, status,
  });
}
