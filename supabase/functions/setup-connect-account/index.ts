// setup-connect-account — Supabase Edge Function
// Creates (or retrieves) a Stripe Express Connect account for the current user
// and returns an account-link onboarding URL.
//
// Request body: { returnUrl: string, refreshUrl: string }
// Response:     { url: string }

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import Stripe from "https://esm.sh/stripe@14";
import { checkRateLimit, RL } from "../_shared/rateLimiter.ts";

const FUNCTION_NAME = "setup-connect-account";

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

    const rl = await checkRateLimit(supabaseAdmin, userId, RL.SETUP_CONNECT_ACCOUNT);
    if (!rl.allowed) return rl.response!;

    body = await req.json();
    const { returnUrl, refreshUrl } = body as { returnUrl: string; refreshUrl: string };

    // Look up existing Connect account ID from the profile
    const { data: profile } = await supabaseAdmin
      .from("profiles")
      .select("stripe_connect_id, name")
      .eq("id", userId)
      .single();

    let connectAccountId: string = profile?.stripe_connect_id ?? "";

    if (!connectAccountId) {
      // Create a new Stripe Express account
      const account = await stripe.accounts.create({
        type: "express",
        email: user.email,
        metadata: { supabase_user_id: userId },
      });
      connectAccountId = account.id;

      // Persist the Connect account ID
      await supabaseAdmin
        .from("profiles")
        .update({ stripe_connect_id: connectAccountId })
        .eq("id", userId);
    }

    // Generate a fresh account-link URL each time (links expire after a few minutes)
    const accountLink = await stripe.accountLinks.create({
      account: connectAccountId,
      return_url: returnUrl,
      refresh_url: refreshUrl,
      type: "account_onboarding",
    });

    return new Response(JSON.stringify({ url: accountLink.url }), {
      headers: { "Content-Type": "application/json" }, status: 200,
    });

  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    await logError(userId, message, "UNHANDLED_EXCEPTION", body);
    return errorResponse(500, "An unexpected error occurred");
  }
});

function errorResponse(status: number, message: string) {
  return new Response(JSON.stringify({ error: message }), {
    headers: { "Content-Type": "application/json" }, status,
  });
}
