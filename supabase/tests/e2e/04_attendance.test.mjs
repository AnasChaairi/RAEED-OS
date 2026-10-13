// Attendance, absence follow-up, notes and the advisor's statistics, on four past sessions.
import { test, before } from "node:test";
import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { academy, day, inSamae, must, refused } from "./helpers.mjs";

let a;
let S; // four past sessions of group A, oldest first
let clock = Date.now();
/** A phone time later than every earlier save, as a real sheet would have. */
const later = () => new Date((clock += 1000)).toISOString();

/** What InstructorRepository.pushAttendance sends. */
const record = (who, session, child, status, recordedAt = later(), id = randomUUID()) =>
  who.from("attendance").upsert(
    { id, session_id: session, child_id: child, status, recorded_by: who.userId, recorded_at: recordedAt },
    { onConflict: "session_id,child_id" },
  );
const statusOf = async (session, child) =>
  (await must(a.advisor.from("attendance").select("status").eq("session_id", session).eq("child_id", child).single())).status;
const alertsFor = (who, child) =>
  must(who.from("absence_alerts").select("id, status, session_ids, last_attempt_by, reason").eq("child_id", child).order("created_at"));

before(async () => {
  a = await academy();
  S = [];
  for (const offset of [-28, -21, -14, -7]) {
    S.push(await must(a.teacherA.rpc("create_sessions", {
      p_group: a.groupA, p_fields: inSamae("حصة أسبوعية", day(offset)), p_dates: [day(offset)], p_weekdays: null,
    })));
  }
});

test("sending the same sheet twice keeps one record per child", async () => {
  const id = randomUUID();
  const at = later();
  await must(record(a.teacherA, S[3], a.yasmine, "present", at, id));
  await must(record(a.teacherA, S[3], a.yasmine, "present", at, id));
  const rows = await must(a.advisor.from("attendance").select("id, recorded_by").eq("session_id", S[3]).eq("child_id", a.yasmine));
  assert.deepEqual(rows, [{ id, recorded_by: a.teacherA.userId }]);
});

test("offline: an older save arriving late does not overwrite a newer one", async () => {
  await must(record(a.teacherA, S[3], a.yasmine, "late", later()));
  const stale = new Date(clock - 60 * 60 * 1000).toISOString(); // saved an hour earlier on another phone
  await must(record(a.teacherA, S[3], a.yasmine, "absent", stale));
  assert.equal(await statusOf(S[3], a.yasmine), "late");
});

test("only the child's own instructor records attendance; parents never see it", async () => {
  await refused(record(a.teacherB, S[0], a.yasmine, "present"), "42501");
  await refused(record(a.mom, S[0], a.yasmine, "present"), "42501");
  // Recording in someone else's name is refused too.
  const forged = await a.teacherA.from("attendance").insert({
    id: randomUUID(), session_id: S[0], child_id: a.yasmine, status: "present",
    recorded_by: a.teacherB.userId, recorded_at: later(),
  });
  assert.equal(forged.error?.code, "42501");
  assert.deepEqual(await must(a.mom.from("attendance").select("id")), []);
  assert.deepEqual(await must(a.teacherB.from("attendance").select("id").eq("child_id", a.yasmine)), []);
});

test("absent, present, absent raises no alert", async () => {
  await must(record(a.teacherA, S[0], a.yasmine, "absent"));
  await must(record(a.teacherA, S[1], a.yasmine, "present"));
  await must(record(a.teacherA, S[2], a.yasmine, "absent"));
  assert.deepEqual(await alertsFor(a.advisor, a.yasmine), []);
});

test("two absences in a row raise one alert for the group's staff", async () => {
  await must(record(a.teacherA, S[0], a.omar, "absent"));
  assert.equal((await alertsFor(a.advisor, a.omar)).length, 0, "one absence is not enough");
  await must(record(a.teacherA, S[1], a.omar, "absent"));

  const [alert] = await alertsFor(a.teacherA, a.omar);
  assert.equal(alert.status, "open");
  assert.deepEqual(alert.session_ids, [S[1], S[0]], "latest first");
  assert.equal((await alertsFor(a.advisor, a.omar)).length, 1);
  assert.deepEqual(await alertsFor(a.teacherB, a.omar), [], "another group's instructor");
  assert.deepEqual(await alertsFor(a.mom2, a.omar), [], "parents do not see follow-ups");

  // Saving the sheet again does not raise a second one.
  await must(record(a.teacherA, S[1], a.omar, "absent"));
  assert.equal((await alertsFor(a.advisor, a.omar)).length, 1);
});

test("correcting the absence removes the alert nobody acted on yet", async () => {
  await must(record(a.teacherA, S[1], a.omar, "excused"));
  assert.deepEqual(await alertsFor(a.advisor, a.omar), []);
  await must(record(a.teacherA, S[1], a.omar, "absent")); // the correction was wrong after all
  assert.equal((await alertsFor(a.advisor, a.omar)).length, 1);
});

test("follow-up: an unanswered call keeps the alert open; reaching the parent closes it", async () => {
  const [alert] = await alertsFor(a.teacherA, a.omar);
  await must(a.teacherA.from("absence_alerts")
    .update({ last_attempt_at: new Date().toISOString(), last_attempt_by: a.teacherA.userId }).eq("id", alert.id));
  let [now] = await alertsFor(a.advisor, a.omar);
  assert.deepEqual([now.status, now.last_attempt_by], ["open", a.teacherA.userId]);

  // Someone already acted, so a correction no longer removes it.
  await must(record(a.teacherA, S[1], a.omar, "excused"));
  assert.equal((await alertsFor(a.advisor, a.omar)).length, 1);

  // Another group's instructor and the parent cannot close it.
  await a.teacherB.from("absence_alerts").update({ status: "closed" }).eq("id", alert.id);
  await a.mom2.from("absence_alerts").update({ status: "closed" }).eq("id", alert.id);
  [now] = await alertsFor(a.advisor, a.omar);
  assert.equal(now.status, "open");

  await must(a.teacherA.from("absence_alerts").update({
    status: "closed", reached_parent: true, reason: "مرض، يعود الأسبوع القادم",
    closed_by: a.teacherA.userId, closed_at: new Date().toISOString(),
  }).eq("id", alert.id));
  [now] = await alertsFor(a.advisor, a.omar);
  assert.deepEqual([now.status, now.reason], ["closed", "مرض، يعود الأسبوع القادم"]);

  // Re-saving the same two absences does not reopen it; a new absence starts a new one.
  await must(record(a.teacherA, S[1], a.omar, "absent"));
  assert.equal((await alertsFor(a.advisor, a.omar)).length, 1);
  await must(record(a.teacherA, S[2], a.omar, "absent"));
  const all = await alertsFor(a.advisor, a.omar);
  assert.deepEqual(all.map((x) => [x.status, x.session_ids]), [["closed", [S[1], S[0]]], ["open", [S[2], S[1]]]]);
});

test("a cancelled session does not count towards absences in a row", async () => {
  const c = await must(a.advisor.from("children").insert({ full_name: `حمزة ${a.t}` }).select("id").single());
  await must(a.advisor.from("child_groups").insert({ child_id: c.id, group_id: a.groupA, from_date: day(-60) }));
  await must(record(a.teacherA, S[0], c.id, "absent"));
  await must(record(a.teacherA, S[1], c.id, "present"));
  await must(record(a.teacherA, S[2], c.id, "absent"));
  // S[3] was cancelled after the sheet was filled: its absence must not pair with S[2]'s.
  const extra = await must(a.teacherA.rpc("create_sessions", {
    p_group: a.groupA, p_fields: inSamae("حصة ملغاة", day(-3)), p_dates: [day(-3)], p_weekdays: null,
  }));
  await must(a.teacherA.rpc("cancel_sessions", { p_session: extra, p_reason: "مطر", p_upcoming: false }));
  await must(record(a.teacherA, extra, c.id, "absent"));
  assert.deepEqual(await alertsFor(a.advisor, c.id), []);
});

test("notes are for staff, never parents", async () => {
  await must(a.teacherA.from("notes").insert({ child_id: a.yasmine, author_id: a.teacherA.userId, body: "تحسن ملحوظ في القراءة" }));
  const forAdvisor = await must(a.advisor.from("notes").select("body, people(full_name)").eq("child_id", a.yasmine));
  assert.equal(forAdvisor.length, 1);
  assert.match(forAdvisor[0].people.full_name, /^أستاذة أ/);
  assert.deepEqual(await must(a.mom.from("notes").select("id")), []);
  assert.deepEqual(await must(a.teacherB.from("notes").select("id").eq("child_id", a.yasmine)), []);
  const { error } = await a.teacherB.from("notes").insert({ child_id: a.yasmine, author_id: a.teacherB.userId, body: "x" });
  assert.equal(error?.code, "42501");
  const empty = await a.teacherA.from("notes").insert({ child_id: a.yasmine, author_id: a.teacherA.userId, body: "" });
  assert.equal(empty.error?.code, "23514");
});

test("statistics: attendance rate per group and term, late counting as attended", async () => {
  const season = await must(a.advisor.from("seasons").insert({ name: `موسم ${a.t}`, starts_on: day(-90), ends_on: day(90) }).select("id").single());
  const term = await must(a.advisor.from("terms").insert({ season_id: season.id, name: `دورة ${a.t}`, starts_on: day(-60), ends_on: day(60) }).select("id").single());

  const rows = await must(a.advisor.from("attendance").select("status, sessions!inner(group_id)").eq("sessions.group_id", a.groupA));
  const count = (...s) => rows.filter((r) => s.includes(r.status)).length;
  const attended = count("present", "late");
  const counted = rows.length - count("excused");

  const [stat] = await must(a.advisor.from("group_term_attendance").select("attended, absent, excused, rate").eq("group_id", a.groupA).eq("term_id", term.id));
  assert.deepEqual([stat.attended, stat.absent, stat.excused], [attended, count("absent"), count("excused")]);
  assert.equal(Number(stat.rate), Math.round((1000 * attended) / counted) / 10);
  assert.deepEqual(await must(a.mom.from("group_term_attendance").select("rate").eq("group_id", a.groupA)), [], "parents see no statistics");
});

test("pilot metrics: advisors only, counting sheets filled late", async () => {
  await must(a.teacherA.from("usage_events").insert({ kind: "attendance_sheet", session_id: S[3], seconds: 95 }));
  await refused(a.teacherA.rpc("pilot_metrics", { p_from: day(-30), p_to: day(0) }), "42501");
  await refused(a.mom.rpc("pilot_metrics", { p_from: day(-30), p_to: day(0) }), "42501");

  const m = await must(a.advisor.rpc("pilot_metrics", { p_from: day(-30), p_to: day(0) }));
  const mine = m.by_group.find((g) => g.group_id === a.groupA);
  // Four weekly sessions plus the cancelled one (not held); every sheet was filled today,
  // days after each session ended, so none counts as on time.
  assert.deepEqual(mine, { group_id: a.groupA, held: 4, on_time: 0 });
  assert.ok(m.sheets_timed >= 1 && m.median_sheet_seconds > 0);
  assert.ok(m.advisors.some((x) => x.full_name === "المستشار التجريبي"));
});
