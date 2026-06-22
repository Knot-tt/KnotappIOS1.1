// confirm-knot-payment-request
// Step 2 of paying a knot creator's payment request.
// Called by the iOS app after the Stripe PaymentSheet completes successfully.
// Verifies the PaymentIntent in Stripe, transfers payout to the creator's
// Connect account, and updates knot_members.last_paid_at.
//
// Request body:  { paymentIntentId: string, paymentRequestId: string }
// Response:      { success: true }

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import Stripe from "https://esm.sh/stripe@14";
import { checkRateLimit, RL } from "../_shared/rateLimiter.ts";

const FUNCTION_NAME = "confirm-knot-payment-request";

const stripe = new Stripe(Deno.env.get("STRIPE_SECRET_KEY")!, {
  apiVersion: "2023-10-16",
  httpClient: Stripe.createFetchHttpClient(),
});
const supabaseAdmin = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
);

serve(async (req) => {
  try {
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) return err(401, "Missing auth header");
    const { data: { user }, error: authErr } = await supabaseAdmin.auth.getUser(
      authHeader.replace("Bearer ", "")
    );
    if (authErr || !user) return err(401, "Unauthorized");

    const rl = await checkRateLimit(supabaseAdmin, user.id, RL.CREATE_ORDER);
    if (!rl.allowed) return rl.response!;

    const { paymentIntentId, paymentRequestId } = await req.json() as {
      paymentIntentId: string;
      paymentRequestId: string;
    };
    if (!paymentIntentId) return err(400, "Missing paymentIntentId");
    if (!paymentRequestId) return err(400, "Missing paymentRequestId");

    // 1. Verify PaymentIntent succeeded in Stripe
    const pi = await stripe.paymentIntents.retrieve(paymentIntentId);
    if (pi.status !== "succeeded") {
      return err(400, `Payment not confirmed (status: ${pi.status})`);
    }

    // 2. Verify metadata — prevents cross-user/cross-request abuse
    if (pi.metadata?.payment_request_id !== paymentRequestId || pi.metadata?.member_id !== user.id) {
      console.error(`[${FUNCTION_NAME}] Metadata mismatch — PI ${paymentIntentId}, user ${user.id}`);
      return err(403, "Payment does not match this request or user");
    }

    // 3. Load the payment request
    const { data: payReq } = await supabaseAdmin
      .from("knot_payment_requests")
      .select("knot_id, creator_id, amount_cents")
      .eq("id", paymentRequestId)
      .single();
    if (!payReq) return err(404, "Payment request not found");

    // 4. Get creator's Connect account
    const { data: creatorProfile } = await supabaseAdmin
      .from("profiles")
      .select("stripe_connect_id")
      .eq("id", payReq.creator_id)
      .single();
    if (!creatorProfile?.stripe_connect_id) {
      return err(400, "Creator has not set up payouts");
    }

    // 5. Transfer payout to creator (10% platform fee retained)
    const KNOT_FEE_RATE = 0.10;
    const payoutCents = Math.floor(payReq.amount_cents * (1 - KNOT_FEE_RATE));
    await stripe.transfers.create({
      amount: payoutCents,
      currency: "sgd",
      destination: creatorProfile.stripe_connect_id,
      metadata: { payment_request_id: paymentRequestId, member_id: user.id },
    });

    // 6. Update knot_members.last_paid_at
    await supabaseAdmin
      .from("knot_members")
      .update({ last_paid_at: new Date().toISOString() })
      .eq("knot_id", payReq.knot_id)
      .eq("user_id", user.id);

    console.log(`[${FUNCTION_NAME}] Member ${user.id} paid request ${paymentRequestId} via PI ${paymentIntentId}`);

    return new Response(
      JSON.stringify({ success: true }),
      { headers: { "Content-Type": "application/json" }, status: 200 }
    );

  } catch (e) {
    console.error(`[${FUNCTION_NAME}]`, e instanceof Error ? e.message : e);
    return err(500, "An unexpected error occurred");
  }
});

function err(status: number, message: string) {
  return new Response(JSON.stringify({ error: message }), {
    headers: { "Content-Type": "application/json" }, status,
  });
}
