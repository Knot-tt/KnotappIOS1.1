// delete-account — Supabase Edge Function
// Permanently deletes all data for the authenticated user.
//
// Deletion strategy (verified against live FK constraints):
//   1. Delete knot_payment_requests  — only table with NO ACTION on profiles.id
//   2. Delete profile row            — cascades everything else automatically
//                                      (connections, knots, members, messages,
//                                       listings, participants, blocked_users,
//                                       announcements, join requests, etc.)
//   3. Delete storage files          — not covered by DB cascade
//   4. Delete auth user              — last, after all data is gone
//
// Required for PDPA compliance and Apple App Store account-deletion policy.

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const FUNCTION_NAME = "delete-account";

const supabaseAdmin = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
);

async function logError(userId: string | null, message: string, code: string) {
  try {
    await supabaseAdmin.from("api_error_log").insert({
      user_id: userId, function_name: FUNCTION_NAME,
      error_code: code, error_message: message, request_body: {},
    });
  } catch (_) { /* best-effort */ }
}

async function safeDelete(table: string, column: string, value: string) {
  try {
    await supabaseAdmin.from(table).delete().eq(column, value);
  } catch (err) {
    console.error(`safeDelete ${table}.${column}=${value}:`, err);
  }
}

async function safeDeleteStorageFolder(bucket: string, userId: string) {
  try {
    const { data: files } = await supabaseAdmin.storage
      .from(bucket)
      .list(userId, { limit: 1000 });
    if (files && files.length > 0) {
      const paths = files.map((f: { name: string }) => `${userId}/${f.name}`);
      await supabaseAdmin.storage.from(bucket).remove(paths);
    }
  } catch (err) {
    console.error(`safeDeleteStorageFolder ${bucket}/${userId}:`, err);
  }
}

serve(async (req) => {
  let userId: string | null = null;

  try {
    // ── Authenticate ──────────────────────────────────────────────────────────
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) return errorResponse(401, "Missing auth header");

    const { data: { user }, error: authError } = await supabaseAdmin.auth.getUser(
      authHeader.replace("Bearer ", "")
    );
    if (authError || !user) return errorResponse(401, "Unauthorized");
    userId = user.id;

    // ── 1. Remove the one NO ACTION blocker first ─────────────────────────────
    // knot_payment_requests.creator_id → profiles is NO ACTION (not CASCADE).
    // Must be deleted manually before the profile row, or profile deletion fails.
    await safeDelete("knot_payment_requests", "creator_id", userId);

    // ── 2. Delete profile — cascades everything else ──────────────────────────
    // All other tables reference profiles with CASCADE or SET NULL, so this
    // single delete cleans up: connections, knots, knot_members, messages,
    // conversation_participants, shop_listings, announcements, blocked_users,
    // knot_join_requests, knot_paid_memberships, profile_address,
    // user_interests, user_settings, stripe_payment_methods, etc.
    const { error: profileError } = await supabaseAdmin
      .from("profiles")
      .delete()
      .eq("id", userId);

    if (profileError) throw new Error(`Profile deletion failed: ${profileError.message}`);

    // ── 3. Storage files (not covered by DB cascade) ──────────────────────────
    await safeDeleteStorageFolder("profile-images", userId);
    await safeDeleteStorageFolder("listing-images", userId);
    await safeDeleteStorageFolder("knot-images", userId);
    await safeDeleteStorageFolder("message-images", userId);

    // ── 4. Auth user — must be last ───────────────────────────────────────────
    const { error: authDeleteError } = await supabaseAdmin.auth.admin.deleteUser(userId);
    if (authDeleteError) throw new Error(`Auth deletion failed: ${authDeleteError.message}`);

    return new Response(JSON.stringify({ success: true }), {
      headers: { "Content-Type": "application/json" }, status: 200,
    });

  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    await logError(userId, message, "UNHANDLED_EXCEPTION");
    return errorResponse(500, "An unexpected error occurred");
  }
});

function errorResponse(status: number, message: string) {
  return new Response(JSON.stringify({ error: message }), {
    headers: { "Content-Type": "application/json" }, status,
  });
}
