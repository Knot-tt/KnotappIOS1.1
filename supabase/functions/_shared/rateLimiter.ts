// _shared/rateLimiter.ts
// Centralised rate-limiting helper for all Knot edge functions.
// Backed by the public.check_rate_limit() Postgres function, which implements
// a sliding-window counter stored in public.rate_limit_log.
//
// Usage:
//   import { checkRateLimit, RL } from "../_shared/rateLimiter.ts";
//   const result = await checkRateLimit(supabaseAdmin, userId, RL.CREATE_ORDER);
//   if (!result.allowed) return result.response!;

import { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2";

// ── Per-endpoint limit definitions ────────────────────────────────────────────

export const RL = {
  // Financial operations — tight limits
  CREATE_ORDER:             { endpoint: "create-order",              maxRequests: 5,  windowSeconds: 300  },
  RELEASE_ESCROW:           { endpoint: "release-escrow",            maxRequests: 10, windowSeconds: 300  },
  ATTACH_PAYMENT_METHOD:    { endpoint: "attach-stripe-payment-method", maxRequests: 3, windowSeconds: 600 },

  // Moderation operations — moderate limits
  APPROVE_JOIN_REQUEST:     { endpoint: "approve-join-request",      maxRequests: 20, windowSeconds: 60   },
  APPLY_ADMIN_ACTION:       { endpoint: "apply-admin-action",        maxRequests: 20, windowSeconds: 60   },

  // Auth operations (used from iOS, not edge functions)
  SIGN_IN:                  { endpoint: "sign-in",                   maxRequests: 10, windowSeconds: 900  },
  SIGN_UP:                  { endpoint: "sign-up",                   maxRequests: 5,  windowSeconds: 3600 },
  PASSWORD_RESET:           { endpoint: "password-reset",            maxRequests: 3,  windowSeconds: 3600 },
} as const;

export type RLConfig = { endpoint: string; maxRequests: number; windowSeconds: number };

// ── Core helper ───────────────────────────────────────────────────────────────

export interface RateLimitResult {
  allowed: boolean;
  response?: Response;   // pre-built 429 response — return this immediately if !allowed
}

export async function checkRateLimit(
  supabaseAdmin: SupabaseClient,
  identifier: string,
  config: RLConfig,
): Promise<RateLimitResult> {
  let allowed = true;

  try {
    const { data, error } = await supabaseAdmin.rpc("check_rate_limit", {
      p_identifier:  identifier,
      p_endpoint:    config.endpoint,
      p_max:         config.maxRequests,
      p_window_secs: config.windowSeconds,
    });

    if (error) {
      // Fail open — a broken rate limiter must not block legitimate users
      console.error(`[RateLimiter] RPC error on ${config.endpoint}:`, error.message);
      return { allowed: true };
    }

    allowed = Boolean(data);
  } catch (err) {
    console.error(`[RateLimiter] Unexpected error on ${config.endpoint}:`, err);
    return { allowed: true };
  }

  if (!allowed) {
    return {
      allowed: false,
      response: new Response(
        JSON.stringify({
          error: "Too many requests. Please wait before trying again.",
          retryAfterSeconds: config.windowSeconds,
        }),
        {
          status: 429,
          headers: {
            "Content-Type": "application/json",
            "Retry-After":  String(config.windowSeconds),
          },
        },
      ),
    };
  }

  return { allowed: true };
}
