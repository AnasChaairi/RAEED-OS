// Accounts: the advisor creates them, people sign in by phone number with a temporary
// password and must change it, and advisors reset, re-role and delete accounts.
import { test, before } from "node:test";
import assert from "node:assert/strict";
import {
  anonClient, bootstrapAdvisor, createPerson, day, emailFor, inSamae, manage, must, newPhone, normalizePhone,
  service, signIn, tag,
} from "./helpers.mjs";

let advisor;
before(async () => {
  advisor = await bootstrapAdvisor();
});

test("signed-out callers and non-advisors cannot manage accounts", async () => {
  const signedOut = await manage(null, { action: "create", full_name: "x", phone: newPhone(), roles: ["parent"] });
  assert.equal(signedOut.status, 401);

  const teacher = await createPerson(advisor, `أستاذ ${tag()}`, ["instructor"]);
  const asTeacher = await manage(teacher, { action: "create", full_name: "x", phone: newPhone(), roles: ["parent"] });
  assert.deepEqual([asTeacher.status, asTeacher.body.error], [403, "advisors_only"]);
});

test("the advisor creates a parent account with a temporary password", async () => {
  const phone = newPhone();
  const { status, body } = await manage(advisor, { action: "create", full_name: "  فاطمة الزهراء  ", phone, roles: ["parent"] });
  assert.equal(status, 200);
  assert.match(body.temporary_password, /^[abcdefghjkmnpqrstuvwxyz23456789]{8}$/, "8 characters, no look-alikes");

  const person = await must(advisor.from("people").select("full_name, phone, must_change_password, person_roles(role)").eq("id", body.person_id).single());
  assert.equal(person.full_name, "فاطمة الزهراء", "name is trimmed");
  assert.equal(person.phone, `+${normalizePhone(phone)}`);
  assert.equal(person.must_change_password, true);
  assert.deepEqual(person.person_roles.map((r) => r.role), ["parent"]);
});

test("phone numbers are accepted in the forms people type them", async () => {
  for (const shape of [(n) => `06 ${n.slice(2, 4)} ${n.slice(4, 6)} ${n.slice(6, 8)} ${n.slice(8)}`, (n) => `+212${n.slice(1)}`, (n) => `212-${n.slice(1)}`]) {
    const phone = newPhone();
    const { status, body } = await manage(advisor, { action: "create", full_name: `ولي ${tag()}`, phone: shape(phone), roles: ["parent"] });
    assert.equal(status, 200, JSON.stringify(body));
    await signIn(phone, body.temporary_password); // signs in with the plain 06… form
  }
});

test("bad input is refused with a clear reason", async () => {
  const cases = [
    [{ full_name: "x", phone: "0812345678", roles: ["parent"] }, "invalid_phone"],
    [{ full_name: "x", phone: "0612", roles: ["parent"] }, "invalid_phone"],
    [{ full_name: "   ", phone: newPhone(), roles: ["parent"] }, "full_name_required"],
    [{ full_name: "x", phone: newPhone(), roles: [] }, "invalid_roles"],
    [{ full_name: "x", phone: newPhone(), roles: ["admin"] }, "invalid_roles"],
  ];
  for (const [fields, error] of cases) {
    const { status, body } = await manage(advisor, { action: "create", ...fields });
    assert.deepEqual([status, body.error], [400, error], JSON.stringify(fields));
  }
  const unknown = await manage(advisor, { action: "explode" });
  assert.equal(unknown.body.error, "unknown_action");
});

test("first sign-in: temporary password, forced change, then the new password only", async () => {
  const phone = newPhone();
  const { body } = await manage(advisor, { action: "create", full_name: `ولي ${tag()}`, phone, roles: ["parent"] });
  const client = await signIn(phone, body.temporary_password);
  const me = await must(client.from("people").select("must_change_password").eq("id", client.userId).single());
  assert.equal(me.must_change_password, true, "the app sends them to the change-password screen");

  await must(client.auth.updateUser({ password: "my-new-password-1" }));
  await must(client.rpc("mark_password_changed"));
  const after = await must(client.from("people").select("must_change_password").eq("id", client.userId).single());
  assert.equal(after.must_change_password, false);

  const old = await anonClient().auth.signInWithPassword({ email: emailFor(phone), password: body.temporary_password });
  assert.equal(old.error?.code, "invalid_credentials");
  await signIn(phone, "my-new-password-1");
});

test("a wrong password and an unknown number give the same answer", async () => {
  const parent = await createPerson(advisor, `ولي ${tag()}`, ["parent"]);
  const wrong = await anonClient().auth.signInWithPassword({ email: emailFor(parent.phone), password: "not-it" });
  const unknown = await anonClient().auth.signInWithPassword({ email: emailFor(newPhone()), password: "not-it" });
  assert.equal(wrong.error?.code, "invalid_credentials");
  assert.equal(unknown.error?.code, "invalid_credentials");
});

test("the same phone number again adds the role and keeps the password", async () => {
  const teacher = await createPerson(advisor, `أستاذة ${tag()}`, ["instructor"]);
  const again = await manage(advisor, { action: "create", full_name: "اسم آخر", phone: teacher.phone, roles: ["parent"] });
  assert.equal(again.status, 200);
  assert.deepEqual(again.body, { person_id: teacher.userId, temporary_password: null, existing: true });

  const roles = await must(advisor.from("person_roles").select("role").eq("person_id", teacher.userId).order("role"));
  assert.deepEqual(roles.map((r) => r.role).sort(), ["instructor", "parent"]);
  await signIn(teacher.phone, teacher.password); // password unchanged
});

test("people cannot change their own phone number or roles", async () => {
  const parent = await createPerson(advisor, `ولي ${tag()}`, ["parent"]);
  await parent.from("people").update({ phone: "+212600000000", full_name: "hacker" }).eq("id", parent.userId);
  const me = await must(service.from("people").select("phone, full_name").eq("id", parent.userId).single());
  assert.equal(me.phone, `+${normalizePhone(parent.phone)}`);
  assert.notEqual(me.full_name, "hacker");

  const { error } = await parent.from("person_roles").insert({ person_id: parent.userId, role: "advisor" });
  assert.ok(error, "a parent cannot make themselves an advisor");
});

test("password reset gives a new temporary password and forces a change again", async () => {
  const parent = await createPerson(advisor, `ولي ${tag()}`, ["parent"]);
  const { status, body } = await manage(advisor, { action: "reset", person_id: parent.userId });
  assert.equal(status, 200);
  const old = await anonClient().auth.signInWithPassword({ email: emailFor(parent.phone), password: parent.password });
  assert.ok(old.error, "the old password stops working");
  const again = await signIn(parent.phone, body.temporary_password);
  const me = await must(again.from("people").select("must_change_password").eq("id", again.userId).single());
  assert.equal(me.must_change_password, true);
});

test("set_roles replaces roles; an advisor cannot drop their own advisor role", async () => {
  const person = await createPerson(advisor, `شخص ${tag()}`, ["parent"]);
  const set = await manage(advisor, { action: "set_roles", person_id: person.userId, roles: ["instructor", "advisor"] });
  assert.equal(set.status, 200);
  const roles = await must(service.from("person_roles").select("role").eq("person_id", person.userId));
  assert.deepEqual(roles.map((r) => r.role).sort(), ["advisor", "instructor"]);

  const self = await manage(advisor, { action: "set_roles", person_id: advisor.userId, roles: ["parent"] });
  assert.deepEqual([self.status, self.body.error], [400, "cannot_remove_own_advisor_role"]);
  const missing = await manage(advisor, { action: "set_roles", person_id: crypto.randomUUID(), roles: ["parent"] });
  assert.equal(missing.status, 404);
});

test("deleting an unused account removes it completely", async () => {
  const parent = await createPerson(advisor, `ولي ${tag()}`, ["parent"]);
  const { status, body } = await manage(advisor, { action: "delete", person_id: parent.userId });
  assert.equal(status, 200);
  assert.equal(body.deleted, true);
  assert.equal(body.anonymised, undefined);
  const left = await must(service.from("people").select("id").eq("id", parent.userId));
  assert.equal(left.length, 0);
  const signInAgain = await anonClient().auth.signInWithPassword({ email: emailFor(parent.phone), password: parent.password });
  assert.ok(signInAgain.error);
});

test("deleting someone whose name is on attendance anonymises them instead", async () => {
  const t = tag();
  const teacher = await createPerson(advisor, `أستاذ ${t}`, ["instructor"]);
  const g = await must(advisor.from("groups").insert({ name: `فئة ${t}`, logo_letter: "ف" }).select("id").single());
  await must(advisor.from("group_instructors").insert({ group_id: g.id, person_id: teacher.userId }));
  const c = await must(advisor.from("children").insert({ full_name: `طفل ${t}` }).select("id").single());
  await must(advisor.from("child_groups").insert({ child_id: c.id, group_id: g.id }));
  const sessionId = await must(teacher.rpc("create_sessions", { p_group: g.id, p_fields: inSamae("ورشة", day(-1)), p_dates: [day(-1)], p_weekdays: null }));
  await must(teacher.from("attendance").insert({
    id: crypto.randomUUID(), session_id: sessionId, child_id: c.id, status: "present",
    recorded_by: teacher.userId, recorded_at: new Date().toISOString(),
  }));

  const { status, body } = await manage(advisor, { action: "delete", person_id: teacher.userId });
  assert.equal(status, 200, JSON.stringify(body));
  assert.equal(body.anonymised, true);
  const person = await must(service.from("people").select("full_name, phone").eq("id", teacher.userId).single());
  assert.equal(person.full_name, "حساب محذوف");
  assert.equal(person.phone, `deleted-${teacher.userId}`);
  const roles = await must(service.from("person_roles").select("role").eq("person_id", teacher.userId));
  assert.equal(roles.length, 0);
  const attendance = await must(service.from("attendance").select("id").eq("session_id", sessionId));
  assert.equal(attendance.length, 1, "the academy keeps the record");
  const signInAgain = await anonClient().auth.signInWithPassword({ email: emailFor(teacher.phone), password: teacher.password });
  assert.ok(signInAgain.error, "they can no longer sign in");

  // The number is free again for a new account.
  const reuse = await manage(advisor, { action: "create", full_name: `أستاذ جديد ${t}`, phone: teacher.phone, roles: ["instructor"] });
  assert.equal(reuse.status, 200, JSON.stringify(reuse.body));
  assert.notEqual(reuse.body.person_id, teacher.userId);
});

test("an advisor cannot delete their own account", async () => {
  const { status, body } = await manage(advisor, { action: "delete", person_id: advisor.userId });
  assert.deepEqual([status, body.error], [400, "cannot_delete_self"]);
});

test("a deletion request reaches the advisor and nobody else", async () => {
  const parent = await createPerson(advisor, `ولي ${tag()}`, ["parent"]);
  const stranger = await createPerson(advisor, `ولي ${tag()}`, ["parent"]);
  await must(parent.from("account_deletion_requests").upsert({ person_id: parent.userId }, { ignoreDuplicates: true }));
  await must(parent.from("account_deletion_requests").upsert({ person_id: parent.userId }, { ignoreDuplicates: true })); // twice is harmless

  const seen = await must(advisor.from("account_deletion_requests").select("person_id").eq("person_id", parent.userId));
  assert.equal(seen.length, 1);
  const hidden = await must(stranger.from("account_deletion_requests").select("person_id").eq("person_id", parent.userId));
  assert.equal(hidden.length, 0);
  const { error } = await stranger.from("account_deletion_requests").insert({ person_id: parent.userId });
  assert.ok(error, "nobody can ask on someone else's behalf");
});
