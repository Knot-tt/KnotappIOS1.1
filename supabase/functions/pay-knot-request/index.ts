// pay-knot-request
// Step 1 of paying a knot creator's payment request.
// Creates a Stripe PaymentIntent and returns client_secret for the iOS PaymentSheet.
// After the sheet completes, call confirm-knot-payment-request to transfer funds.
//
// Request body:  { requestId: string }
// Response:      { clientSecret, customerId, ephemeralKey, paymentIntentId, paymentRequestId }

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import Stripe from "https://esm.sh/stripe@14";
import { checkRateLimit, RL } from "../_shared/rateLimiter.ts";

const FUNCTION_NAME = "pay-knot-request";

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

    const { requestId } = await req.json() as { requestId: string };
    if (!requestId) return err(400, "Missing requestId");

    // Load payment request
    const { data: payReq } = await supabaseAdmin
      .from("knot_payment_requests")
      .select("*, knots(name)")
      .eq("id", requestId)
      .single();
    if (!payReq) return err(404, "Payment request not found");

    // Guard: must be a member of this knot
    const { data: membership } = await supabaseAdmin
      .from("knot_members")
      .select("id")
      .eq("knot_id", payReq.knot_id)
      .eq("user_id", user.id)
      .maybeSingle();
    if (!membership) return err(403, "You are not a member of this Knot");

    // Guard: creator cannot pay their own request
    if (payReq.creator_id === user.id) return err(400, "You cannot pay your own payment request");

    // Guard: creator must have a Connect account so we can transfer
    const { data: creatorProfile } = await supabaseAdmin
      .from("profiles")
      .select("stripe_connect_id")
      .eq("id", payReq.creator_id)
      .single();
    if (!creatorProfile?.stripe_connect_id) {
      return err(400, "The knot creator hasn't set up payouts yet");
    }

    // Get or create Stripe customer for the member
    const { data: memberProfile } = await supabaseAdmin
      .from("profiles")
      .select("stripe_customer_id, name")
      .eq("id", user.id)
      .single();

    let customerId = memberProfile?.stripe_customer_id as string | null;
    if (!customerId) {
      const customer = await stripe.customers.create({
        email: user.email,
        name: memberProfile?.name ?? "",
        metadata: { supabase_user_id: user.id },
      });
      customerId = customer.id;
      await supabaseAdmin
        .from("profiles")
        .update({ stripe_customer_id: customerId })
        .eq("id", user.id);
    }

    // Ephemeral key so the PaymentSheet can display/save cards for this customer
    const ephemeralKey = await stripe.ephemeralKeys.create(
      { customer: customerId },
      { apiVersion: "2023-10-16" }
    );

    // Create PaymentIntent — not confirmed yet; iOS PaymentSheet does that
    const knotName = (payReq.knots as { name: string } | null)?.name ?? "Knot";
    const paymentIntent = await stripe.paymentIntents.create({
      amount: payReq.amount_cents,
      currency: "sgd",
      customer: customerId,
      automatic_payment_methods: { enabled: true },
      metadata: {
        payment_request_id: requestId,
        member_id: user.id,
        knot_id: payReq.knot_id,
      },
      description: `${payReq.title} — ${knotName}`,
    });

    console.log(`[${FUNCTION_NAME}] PaymentIntent ${paymentIntent.id} created for request ${requestId} by ${user.id}`);

    return new Response(
      JSON.stringify({
        clientSecret:     paymentIntent.client_secret,
        customerId,
        ephemeralKey:     ephemeralKey.secret,
        paymentIntentId:  paymentIntent.id,
        paymentRequestId: requestId,
      }),
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
