// apply-admin-action — Supabase Edge Function
// Called by knot creator to approve a co-admin's action request.
// Actions: make_admin | dismiss_admin | kick
//
// Request body: { actionRequestId: string, knotId: string }

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { checkRateLimit, RL } from "../_shared/rateLimiter.ts";

const FUNCTION_NAME = "apply-admin-action";

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
    const rl = await checkRateLimit(supabaseAdmin, userId, RL.APPLY_ADMIN_ACTION);
    if (!rl.allowed) return rl.response!;

    body = await req.json();
    const { actionRequestId, knotId } = body as { actionRequestId: string; knotId: string };

    const { data: membership } = await supabaseAdmin
      .from("knot_members").select("role")
      .eq("knot_id", knotId).eq("user_id", userId).eq("role", "creator").single();

    if (!membership) {
      await logError(userId, "Non-creator attempted to apply admin action", "FORBIDDEN", { knotId, actionRequestId });
      return errorResponse(403, "Only the knot creator can approve admin actions");
    }

    const { data: action, error: actionError } = await supabaseAdmin
      .from("knot_admin_action_requests").select("*")
      .eq("id", actionRequestId).eq("knot_id", knotId).eq("status", "pending").single();

    if (actionError || !action) return errorResponse(404, "Action request not found or already resolved");

    switch (action.action_type) {
      case "make_admin":
        await supabaseAdmin.from("knot_members")
          .update({ role: "co_admin" }).eq("knot_id", knotId).eq("user_id", action.target_member_id);
        break;

      case "dismiss_admin":
        await supabaseAdmin.from("knot_members")
          .update({ role: "member" }).eq("knot_id", knotId).eq("user_id", action.target_member_id);
        break;

      case "kick":
        await supabaseAdmin.from("knot_members")
          .delete().eq("knot_id", knotId).eq("user_id", action.target_member_id);

        const { data: groupChat } = await supabaseAdmin
          .from("conversations").select("id")
          .eq("source_knot_id", knotId).eq("is_group", true).single();

        if (groupChat) {
          await supabaseAdmin.from("conversation_participants")
            .update({ has_left: true })
            .eq("conversation_id", groupChat.id).eq("user_id", action.target_member_id);
        }
        break;

      default:
        await logError(userId, `Unknown action_type: ${action.action_type}`, "INVALID_ACTION", { actionRequestId });
        return errorResponse(400, "Unknown action type");
    }

    await supabaseAdmin.from("knot_admin_action_requests").update({
      status: "approved", resolved_at: new Date().toISOString(), resolved_by: userId,
    }).eq("id", actionRequestId);

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
