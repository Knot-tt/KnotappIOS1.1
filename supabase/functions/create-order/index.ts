// create-order — Supabase Edge Function
// Called when a buyer confirms purchase. Creates the Stripe PaymentIntent
// (with capture_method: manual for escrow) and inserts the order row.
//
// Request body:
//   { listingId: string, fulfilment: "meetup" | "delivery", deliveryAddress?: string }
//
// Response:
//   { orderId: string, clientSecret: string, error?: string }

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import Stripe from "https://esm.sh/stripe@14";
import { checkRateLimit, RL } from "../_shared/rateLimiter.ts";

const FUNCTION_NAME = "create-order";
const KNOT_FEE_RATE = 0.10;

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

    // ── Rate limit ─────────────────────────────────────────────────────────────
    const rl = await checkRateLimit(supabaseAdmin, userId, RL.CREATE_ORDER);
    if (!rl.allowed) return rl.response!;

    body = await req.json();
    const { listingId, fulfilment, deliveryAddress = "" } = body as {
      listingId: string; fulfilment: string; deliveryAddress?: string;
    };
    console.log("[create-order] listingId:", listingId, "fulfilment:", fulfilment);

    // Fetch listing
    const { data: listing, error: listingError } = await supabaseAdmin
      .from("shop_listings")
      .select("id, seller_id, price_cents, name, is_active")
      .eq("id", listingId)
      .single();
    console.log("[create-order] listing query - error:", listingError, "found:", !!listing);

    if (listingError || !listing) return errorResponse(404, "Listing not found");
    if (!listing.is_active)        return errorResponse(400, "Listing is no longer active");
    if (listing.seller_id === userId) return errorResponse(400, "Cannot buy your own listing");

    // Fetch/create Stripe customer for buyer
    const { data: buyerProfile } = await supabaseAdmin
      .from("profiles")
      .select("stripe_customer_id, name")
      .eq("id", userId)
      .single();

    let customerId = buyerProfile?.stripe_customer_id;
    if (!customerId) {
      const customer = await stripe.customers.create({
        email: user.email,
        name: buyerProfile?.name ?? "",
        metadata: { supabase_user_id: userId },
      });
      customerId = customer.id;
      await supabaseAdmin.from("profiles").update({ stripe_customer_id: customerId }).eq("id", userId);
    }

    const subtotalCents = listing.price_cents;
    console.log("[create-order] creating PaymentIntent for:", subtotalCents, "cents");

    // Create Stripe PaymentIntent with manual capture (escrow)
    const paymentIntent = await stripe.paymentIntents.create({
      amount:         subtotalCents,
      currency:       "sgd",
      customer:       customerId,
      capture_method: "manual",
      metadata: { listing_id: listingId, buyer_id: userId, seller_id: listing.seller_id },
    });
    console.log("[create-order] PaymentIntent created:", paymentIntent.id);

    const orderId = "#KN-" + Math.random().toString(36).slice(2, 7).toUpperCase();
    console.log("[create-order] orderId:", orderId);

    const { error: insertError } = await supabaseAdmin.from("orders").insert({
      id:                       orderId,
      listing_id:               listingId,
      buyer_id:                 userId,
      seller_id:                listing.seller_id,
      subtotal_cents:           subtotalCents,
      knot_fee_rate:            KNOT_FEE_RATE,
      fulfilment,
      delivery_address:         deliveryAddress,
      status:                   "pending",
      escrow_status:            "held",
      pending_at:               new Date().toISOString(),
      stripe_payment_intent_id: paymentIntent.id,
    });

    if (insertError) {
      await stripe.paymentIntents.cancel(paymentIntent.id);
      await logError(userId, insertError.message, "DB_INSERT_FAILED", { listingId });
      return errorResponse(500, "An unexpected error occurred");
    }

    return new Response(
      JSON.stringify({ orderId, clientSecret: paymentIntent.client_secret }),
      { headers: { "Content-Type": "application/json" }, status: 200 }
    );

  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    console.error("[create-order] UNHANDLED_EXCEPTION:", message, err);
    await logError(userId, message, "UNHANDLED_EXCEPTION", body);
    return errorResponse(500, "An unexpected error occurred");
  }
});

function errorResponse(status: number, message: string) {
  return new Response(JSON.stringify({ error: message }), {
    headers: { "Content-Type": "application/json" }, status,
  });
}
