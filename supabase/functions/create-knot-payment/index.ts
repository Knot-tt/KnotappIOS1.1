// create-knot-payment — Supabase Edge Function
// Creates a Stripe PaymentIntent for a paid Knot membership fee.
//
// Request body:  { knotId: string }
// Response:      { client_secret: string, customer_id?: string }

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import Stripe from "https://esm.sh/stripe@14";
import { checkRateLimit, RL } from "../_shared/rateLimiter.ts";

const FUNCTION_NAME = "create-knot-payment";

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

    // Rate limit
    const rl = await checkRateLimit(supabaseAdmin, userId, RL.CREATE_KNOT_PAYMENT);
    if (!rl.allowed) return rl.response!;

    body = await req.json();
    const { knotId } = body as { knotId: string };
    if (!knotId) return errorResponse(400, "Missing knotId");

    // Guard: already a member?
    const { data: existing } = await supabaseAdmin
      .from("knot_members")
      .select("id")
      .eq("knot_id", knotId)
      .eq("user_id", userId)
      .maybeSingle();
    if (existing) return errorResponse(400, "Already a member of this Knot");

    // Fetch Knot
    const { data: knot, error: knotError } = await supabaseAdmin
      .from("knots")
      .select("id, price_cents, is_paid, creator_id")
      .eq("id", knotId)
      .single();

    if (knotError || !knot) return errorResponse(404, "Knot not found");
    if (!knot.is_paid || knot.price_cents <= 0) return errorResponse(400, "This Knot is free");
    if (knot.creator_id === userId) return errorResponse(400, "Cannot pay to join your own Knot");

    // Fetch or create Stripe customer
    const { data: profile } = await supabaseAdmin
      .from("profiles")
      .select("stripe_customer_id, name")
      .eq("id", userId)
      .single();

    let customerId = profile?.stripe_customer_id as string | null;
    if (!customerId) {
      const customer = await stripe.customers.create({
        email: user.email,
        name: profile?.name ?? "",
        metadata: { supabase_user_id: userId },
      });
      customerId = customer.id;
      await supabaseAdmin
        .from("profiles")
        .update({ stripe_customer_id: customerId })
        .eq("id", userId);
    }

    // Create PaymentIntent (automatic capture — no escrow for memberships)
    const paymentIntent = await stripe.paymentIntents.create({
      amount: knot.price_cents,
      currency: "sgd",
      customer: customerId,
      metadata: { knot_id: knotId, user_id: userId },
    });

    console.log(`[${FUNCTION_NAME}] PaymentIntent created: ${paymentIntent.id} for knot: ${knotId}`);

    return new Response(
      JSON.stringify({
        client_secret: paymentIntent.client_secret,
        customer_id: customerId,
        payment_intent_id: paymentIntent.id,
      }),
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
