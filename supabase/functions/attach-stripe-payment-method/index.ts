// attach-stripe-payment-method — Supabase Edge Function
// Called when user saves a card. Raw card data NEVER hits this function —
// the iOS Stripe SDK tokenises the card first.
//
// Request body: { paymentMethodId: string }  // "pm_xxx" from Stripe SDK

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import Stripe from "https://esm.sh/stripe@14";
import { checkRateLimit, RL } from "../_shared/rateLimiter.ts";

const FUNCTION_NAME = "attach-stripe-payment-method";

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

  try {
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) return errorResponse(401, "Missing auth header");

    const { data: { user }, error: authError } = await supabaseAdmin.auth.getUser(
      authHeader.replace("Bearer ", "")
    );
    if (authError || !user) return errorResponse(401, "Unauthorized");
    userId = user.id;

    // ── Rate limit ─────────────────────────────────────────────────────────────
    const rl = await checkRateLimit(supabaseAdmin, userId, RL.ATTACH_PAYMENT_METHOD);
    if (!rl.allowed) return rl.response!;

    const { paymentMethodId } = await req.json() as { paymentMethodId?: string };
    if (!paymentMethodId?.startsWith("pm_")) {
      await logError(userId, "Invalid paymentMethodId format", "INVALID_INPUT", {});
      return errorResponse(400, "Invalid paymentMethodId");
    }

    const { data: profile } = await supabaseAdmin
      .from("profiles").select("stripe_customer_id, name").eq("id", userId).single();

    let customerId = profile?.stripe_customer_id;
    if (!customerId) {
      const customer = await stripe.customers.create({
        email: user.email, name: profile?.name ?? "",
        metadata: { supabase_user_id: userId },
      });
      customerId = customer.id;
      await supabaseAdmin.from("profiles").update({ stripe_customer_id: customerId }).eq("id", userId);
    }

    await stripe.paymentMethods.attach(paymentMethodId, { customer: customerId });

    const pm   = await stripe.paymentMethods.retrieve(paymentMethodId);
    const card = pm.card;
    if (!card) {
      await logError(userId, "Retrieved PM is not a card type", "INVALID_PM_TYPE", { type: pm.type });
      return errorResponse(400, "Not a card payment method");
    }

    const { count } = await supabaseAdmin
      .from("stripe_payment_methods")
      .select("id", { count: "exact", head: true })
      .eq("user_id", userId);
    const isDefault = (count ?? 0) === 0;

    const { error: insertError } = await supabaseAdmin.from("stripe_payment_methods").insert({
      user_id:                  userId,
      stripe_payment_method_id: paymentMethodId,
      brand:    card.brand,
      last4:    card.last4,
      exp_month: card.exp_month,
      exp_year:  card.exp_year,
      is_default: isDefault,
    });

    if (insertError) {
      await logError(userId, insertError.message, "DB_INSERT_FAILED", {});
      return errorResponse(500, "An unexpected error occurred");
    }

    return new Response(
      JSON.stringify({ success: true, brand: card.brand, last4: card.last4 }),
      { headers: { "Content-Type": "application/json" }, status: 200 }
    );

  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    await logError(userId, message, "UNHANDLED_EXCEPTION", {});
    return errorResponse(500, "An unexpected error occurred");
  }
});

function errorResponse(status: number, message: string) {
  return new Response(JSON.stringify({ error: message }), {
    headers: { "Content-Type": "application/json" }, status,
  });
}
