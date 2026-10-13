// Shared set-up for the end-to-end tests: accounts made the way the advisor's Setup screen
// makes them (the manage-account server function), sign-in the way the app does it (phone
// number turned into the internal e-mail address), and a small academy to work in.
import { createClient } from "@supabase/supabase-js";
import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";

export const URL = process.env.SUPABASE_URL;
const ANON = process.env.SUPABASE_ANON_KEY;
const SERVICE = process.env.SUPABASE_SERVICE_ROLE_KEY;
if (!URL || !ANON || !SERVICE) throw new Error("Run the tests with `npm test`, which reads the local Supabase keys.");
// These tests create and delete accounts: never point them at the hosted project.
if (!/^http:\/\/(127\.0\.0\.1|localhost)(:\d+)?$/.test(URL)) throw new Error(`Refusing to run against ${URL}`);

// The local PostgREST's clock runs about a second behind the sign-in service's, with no
// leeway, so a token used the moment it was issued is now and then refused as "issued at
// future" (PGRST303). Wait and send it again, up to three times; each retry is logged, so a
// real clock problem would still show.
async function patientFetch(input, init) {
  for (let attempt = 1; ; attempt++) {
    const res = await fetch(input, init);
    if (res.status !== 401 || attempt > 3) return res;
    if (!(await res.clone().text()).includes("PGRST303")) return res;
    console.log(`# retry ${attempt} after PGRST303 (token issued at future): ${String(input).split("?")[0]}`);
    await new Promise((r) => setTimeout(r, 1000));
  }
}
const options = { auth: { persistSession: false, autoRefreshToken: false }, global: { fetch: patientFetch } };
export const service = createClient(URL, SERVICE, options);
export const anonClient = () => createClient(URL, ANON, options);

/** A fresh Moroccan mobile number as people type it, 06XXXXXXXX. */
export const newPhone = () => "06" + String(Math.floor(Math.random() * 1e8)).padStart(8, "0");
/** The same conversion as app/lib/auth/phone.dart and manage-account. */
export const normalizePhone = (raw) => {
  const digits = String(raw).replace(/[\s\-().]/g, "").replace(/^\+/, "");
  const local = digits.startsWith("212") ? digits.slice(3) : digits.replace(/^0/, "");
  return /^[5-7]\d{8}$/.test(local) ? `212${local}` : null;
};
export const emailFor = (phone) => `${normalizePhone(phone)}@phone.raeed.app`;
export const tag = () => randomUUID().slice(0, 8);

/** Signs in with a phone number and password, as the sign-in screen does. */
export async function signIn(phone, password) {
  const client = anonClient();
  const { data, error } = await client.auth.signInWithPassword({ email: emailFor(phone), password });
  if (error) throw error;
  client.userId = data.user.id;
  client.phone = phone;
  return client;
}

/** Calls manage-account as [client]; returns { status, body } instead of throwing. */
export async function manage(client, body) {
  const headers = { "Content-Type": "application/json", apikey: ANON };
  if (client) {
    const { data } = await client.auth.getSession();
    headers.Authorization = `Bearer ${data.session.access_token}`;
  } else {
    headers.Authorization = `Bearer ${ANON}`;
  }
  const res = await fetch(`${URL}/functions/v1/manage-account`, { method: "POST", headers, body: JSON.stringify(body) });
  return { status: res.status, body: await res.json() };
}

/** The first advisor has to exist before anyone can create accounts; made directly. */
export async function bootstrapAdvisor(fullName = "المستشار التجريبي") {
  const phone = newPhone();
  const password = `advisor-${tag()}`;
  const { data, error } = await service.auth.admin.createUser({ email: emailFor(phone), password, email_confirm: true });
  if (error) throw error;
  const id = data.user.id;
  await must(service.from("people").insert({ id, full_name: fullName, phone: `+${normalizePhone(phone)}`, must_change_password: false }));
  await must(service.from("person_roles").insert({ person_id: id, role: "advisor" }));
  return signIn(phone, password);
}

/**
 * Creates an account through manage-account as [advisor], then does the first sign-in:
 * temporary password, then a new password, as the app forces. Returns the signed-in client.
 */
export async function createPerson(advisor, fullName, roles, { phone = newPhone(), firstSignIn = true } = {}) {
  const { status, body } = await manage(advisor, { action: "create", full_name: fullName, phone, roles });
  assert.equal(status, 200, `create ${fullName}: ${JSON.stringify(body)}`);
  if (!firstSignIn) return { id: body.person_id, phone, temporaryPassword: body.temporary_password };
  const client = await signIn(phone, body.temporary_password);
  const password = `pass-${tag()}`;
  const { error } = await client.auth.updateUser({ password });
  if (error) throw error;
  await must(client.rpc("mark_password_changed"));
  client.password = password;
  return client;
}

/** Fails the test with the server's message when a call returned an error. */
export async function must(query) {
  const { data, error } = await query;
  if (error) assert.fail(`${error.code ?? ""} ${error.message}`);
  return data;
}

/** Expects the call to be refused; returns the error. */
export async function refused(query, code) {
  const { data, error } = await query;
  assert.ok(error, `expected an error, got ${JSON.stringify(data)}`);
  if (code) assert.equal(error.code, code, error.message);
  return error;
}

/** A day relative to today as the database stores it, YYYY-MM-DD. */
export function day(offset = 0, from = new Date()) {
  const d = new Date(Date.UTC(from.getFullYear(), from.getMonth(), from.getDate() + offset));
  return d.toISOString().slice(0, 10);
}

/** The next [count] dates falling on [weekday] (0 Sunday .. 6 Saturday), starting tomorrow. */
export function weekly(weekday, count) {
  const dates = [];
  for (let i = 1; dates.length < count; i++) {
    const d = new Date(day(i) + "T00:00:00Z");
    if (d.getUTCDay() === weekday) dates.push(day(i));
  }
  return dates;
}

/** Session fields the way SessionDraft.toFields() sends them. */
export const inSamae = (title, date, start = "17:00", end = "18:30", floor = 1) => ({
  title, session_date: date, start_time: start, end_time: end, place: "samae", floor,
  address: null, map_url: null, dropoff_place: null, dropoff_time: null, pickup_place: null, pickup_time: null,
});
export const away = (title, date, extra = {}) => ({
  title, session_date: date, start_time: "09:00", end_time: "12:00", place: "away", floor: null,
  address: "حديقة الجامعة العربية", map_url: "https://maps.google.com/?q=33.58,-7.62",
  dropoff_place: "جمعية سماء", dropoff_time: "08:45", pickup_place: "جمعية سماء", pickup_time: "12:30", ...extra,
});

/**
 * One academy: an advisor, two groups each with an instructor, and children with parents.
 * Group A: Yasmine (parents Mom + Dad) and Omar (parent Mom2). Group B: Sara (parent Other).
 */
export async function academy() {
  const t = tag();
  const advisor = await bootstrapAdvisor();
  const teacherA = await createPerson(advisor, `أستاذة أ ${t}`, ["instructor"]);
  const teacherB = await createPerson(advisor, `أستاذ ب ${t}`, ["instructor"]);
  const mom = await createPerson(advisor, `أم ياسمين ${t}`, ["parent"]);
  const dad = await createPerson(advisor, `أب ياسمين ${t}`, ["parent"]);
  const mom2 = await createPerson(advisor, `أم عمر ${t}`, ["parent"]);
  const other = await createPerson(advisor, `أب سارة ${t}`, ["parent"]);

  const group = async (name, letter, teacher) => {
    const g = await must(advisor.from("groups").insert({ name: `${name} ${t}`, logo_letter: letter, logo_color: 2 }).select("id").single());
    await must(advisor.from("group_instructors").insert({ group_id: g.id, person_id: teacher.userId }));
    return g.id;
  };
  const groupA = await group("الرواد", "ر", teacherA);
  const groupB = await group("المبدعون", "م", teacherB);

  const child = async (name, groupId, parents) => {
    const c = await must(advisor.from("children").insert({
      full_name: `${name} ${t}`, birth_date: "2017-03-01",
      consent_recorded_at: new Date().toISOString(), consent_recorded_by: advisor.userId,
    }).select("id").single());
    await must(advisor.from("child_groups").insert({ child_id: c.id, group_id: groupId }));
    await must(advisor.from("child_parents").insert(parents.map((p) => ({ child_id: c.id, parent_id: p.userId }))));
    return c.id;
  };
  const yasmine = await child("ياسمين العلوي", groupA, [mom, dad]);
  const omar = await child("عمر بناني", groupA, [mom2]);
  const sara = await child("سارة الإدريسي", groupB, [other]);

  return { t, advisor, teacherA, teacherB, mom, dad, mom2, other, groupA, groupB, yasmine, omar, sara };
}

/** Notifications queued about [sessionId], oldest first. The outbox is server-only, so read as service. */
export async function outboxAbout(sessionId) {
  return must(service.from("notification_outbox").select("recipient_id, kind, title, body, data")
    .contains("data", { session_id: sessionId }).order("created_at"));
}
