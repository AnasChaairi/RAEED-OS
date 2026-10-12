// manage-account: advisors create accounts, reset passwords and change roles.
//
// Sign-in is phone number + password with no SMS (NFR7). Supabase's phone sign-in needs an
// SMS provider, so each account uses an internal e-mail address derived from the phone
// number instead (212612345678@phone.raeed.app). The app does the same conversion, so people
// only ever type their phone number.
//
// POST { action: "create", full_name, phone, roles: ["parent" | "instructor" | "advisor"] }
//   Returns { person_id, temporary_password } for the advisor to hand over. If the phone
//   number already has an account (a staff member who is also a parent, say), the roles
//   are added to it and the reply is { person_id, temporary_password: null, existing: true }.
// POST { action: "reset", person_id }
//   Returns { person_id, temporary_password }.
// POST { action: "set_roles", person_id, roles }
//   Replaces the person's roles. Advisors cannot remove their own advisor role.

import { createClient } from "jsr:@supabase/supabase-js@2";

const ROLES = new Set(["advisor", "instructor", "parent"]);
// No look-alike characters (0/O, 1/l/I), so a password read aloud or written down works.
const ALPHABET = "abcdefghjkmnpqrstuvwxyz23456789";

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

// Accepts 06…, 07…, +2126…, 2126… with spaces or dashes; returns 2126XXXXXXXX or null.
export function normalizePhone(raw: string): string | null {
  const digits = String(raw).replace(/[\s\-().]/g, "").replace(/^\+/, "");
  const local = digits.startsWith("212") ? digits.slice(3) : digits.replace(/^0/, "");
  return /^[5-7]\d{8}$/.test(local) ? `212${local}` : null;
}

export const phoneToEmail = (phone: string) => `${phone}@phone.raeed.app`;

function temporaryPassword(length = 8) {
  const bytes = crypto.getRandomValues(new Uint8Array(length));
  return Array.from(bytes, (b) => ALPHABET[b % ALPHABET.length]).join("");
}

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  const admin = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  // Who is calling? The platform has already verified the JWT.
  const jwt = (req.headers.get("Authorization") ?? "").replace(/^Bearer /, "");
  const { data: caller, error: callerError } = await admin.auth.getUser(jwt);
  if (callerError || !caller.user) return json({ error: "not_signed_in" }, 401);

  const { data: isAdvisor } = await admin
    .from("person_roles")
    .select("role")
    .eq("person_id", caller.user.id)
    .eq("role", "advisor")
    .maybeSingle();
  if (!isAdvisor) return json({ error: "advisors_only" }, 403);

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return json({ error: "invalid_json" }, 400);
  }

  if (body.action === "create") {
    const fullName = String(body.full_name ?? "").trim();
    const phone = normalizePhone(String(body.phone ?? ""));
    const roles = Array.isArray(body.roles) ? body.roles.map(String) : [];
    if (!fullName) return json({ error: "full_name_required" }, 400);
    if (!phone) return json({ error: "invalid_phone" }, 400);
    if (roles.length === 0 || !roles.every((r) => ROLES.has(r))) {
      return json({ error: "invalid_roles" }, 400);
    }

    // Someone already registered with this number: add the roles, keep their password.
    const { data: existing } = await admin
      .from("people")
      .select("id")
      .eq("phone", `+${phone}`)
      .maybeSingle();
    if (existing) {
      const { error } = await admin
        .from("person_roles")
        .upsert(roles.map((role) => ({ person_id: existing.id, role })), { ignoreDuplicates: true });
      if (error) return json({ error: "create_failed" }, 500);
      return json({ person_id: existing.id, temporary_password: null, existing: true });
    }

    const password = temporaryPassword();
    const { data: created, error } = await admin.auth.admin.createUser({
      email: phoneToEmail(phone),
      password,
      email_confirm: true,
      user_metadata: { phone: `+${phone}` },
    });
    if (error || !created.user) {
      const exists = /already/i.test(error?.message ?? "");
      return json({ error: exists ? "phone_already_registered" : "create_failed" }, exists ? 409 : 500);
    }

    const id = created.user.id;
    const { error: personError } = await admin
      .from("people")
      .insert({ id, full_name: fullName, phone: `+${phone}`, must_change_password: true });
    const { error: rolesError } = personError ? { error: personError } : await admin
      .from("person_roles")
      .insert(roles.map((role) => ({ person_id: id, role })));
    if (personError || rolesError) {
      await admin.auth.admin.deleteUser(id); // leave nothing half-created
      return json({ error: "create_failed" }, 500);
    }
    return json({ person_id: id, temporary_password: password });
  }

  if (body.action === "reset") {
    const personId = String(body.person_id ?? "");
    const password = temporaryPassword();
    const { error } = await admin.auth.admin.updateUserById(personId, { password });
    if (error) return json({ error: "reset_failed" }, 400);
    await admin.from("people").update({ must_change_password: true }).eq("id", personId);
    return json({ person_id: personId, temporary_password: password });
  }

  if (body.action === "set_roles") {
    const personId = String(body.person_id ?? "");
    const roles = Array.isArray(body.roles) ? body.roles.map(String) : [];
    if (roles.length === 0 || !roles.every((r) => ROLES.has(r))) {
      return json({ error: "invalid_roles" }, 400);
    }
    if (personId === caller.user.id && !roles.includes("advisor")) {
      return json({ error: "cannot_remove_own_advisor_role" }, 400);
    }
    const { data: person } = await admin.from("people").select("id").eq("id", personId).maybeSingle();
    if (!person) return json({ error: "not_found" }, 404);
    const { error: deleteError } = await admin
      .from("person_roles")
      .delete()
      .eq("person_id", personId)
      .not("role", "in", `(${roles.join(",")})`);
    const { error: insertError } = deleteError ? { error: deleteError } : await admin
      .from("person_roles")
      .upsert(roles.map((role) => ({ person_id: personId, role })), { ignoreDuplicates: true });
    if (deleteError || insertError) return json({ error: "update_failed" }, 500);
    return json({ person_id: personId, roles });
  }

  return json({ error: "unknown_action" }, 400);
});
