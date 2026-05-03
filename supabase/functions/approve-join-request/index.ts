// approve-join-request — Supabase Edge Function
// Called by knot admin when approving a join request.
// Atomically: updates request status → inserts knot_member row.
//
// Request body: { requestId: string, knotId: string }

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { checkRateLimit, RL } from "../_shared/rateLimiter.ts";

const FUNCTION_NAME = "approve-join-request";

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
    const rl = await checkRateLimit(supabaseAdmin, userId, RL.APPROVE_JOIN_REQUEST);
    if (!rl.allowed) return rl.response!;

    body = await req.json();
    const { requestId, knotId } = body as { requestId: string; knotId: string };

    const { data: membership } = await supabaseAdmin
      .from("knot_members").select("role")
      .eq("knot_id", knotId).eq("user_id", userId).in("role", ["creator", "co_admin"]).single();

    if (!membership) {
      await logError(userId, "Non-admin attempted to approve join request", "FORBIDDEN", { knotId, requestId });
      return errorResponse(403, "Not an admin of this knot");
    }

    const { data: request, error: reqError } = await supabaseAdmin
      .from("knot_join_requests").select("*")
      .eq("id", requestId).eq("knot_id", knotId).eq("status", "pending").single();

    if (reqError || !request) return errorResponse(404, "Join request not found or already resolved");

    const { data: knot } = await supabaseAdmin
      .from("knots").select("max_members, member_count").eq("id", knotId).single();

    if (knot?.max_members && knot.member_count >= knot.max_members) {
      return errorResponse(400, "Knot is at capacity");
    }

    await supabaseAdmin.from("knot_join_requests").update({
      status: "approved", reviewed_at: new Date().toISOString(), reviewed_by: userId,
    }).eq("id", requestId);

    await supabaseAdmin.from("knot_members").insert({
      knot_id: knotId, user_id: request.applicant_id, role: "member",
    });

    return new Response(JSON.stringify({ success: true }), {
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
