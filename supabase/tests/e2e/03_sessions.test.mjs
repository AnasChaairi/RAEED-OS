// Scheduling: advisors create single sessions and weekly series, edit and cancel them,
// parents are notified once each, and every role sees only the sessions it should.
import { test, before } from "node:test";
import assert from "node:assert/strict";
import { academy, away, day, inSamae, must, outboxAbout, refused, service, weekly } from "./helpers.mjs";

let a;
before(async () => {
  a = await academy();
});

const create = (who, group, fields, dates, weekdays = null, materials = []) =>
  who.rpc("create_sessions", { p_group: group, p_fields: fields, p_dates: dates, p_weekdays: weekdays, p_materials: materials });

test("a single session notifies each parent of the group once, naming their child", async () => {
  const date = day(3);
  const id = await must(create(a.advisor, a.groupA, inSamae("ورشة الرسم", date), [date], null,
    [{ kind: "youtube", url: "https://youtu.be/abc", label: "فيديو التحضير" }]));

  const s = await must(a.teacherA.from("sessions").select("*, materials(kind, url, label)").eq("id", id).single());
  assert.equal(s.status, "planned");
  assert.equal(s.series_id, null);
  assert.equal(s.created_by, a.advisor.userId);
  assert.equal(s.materials.length, 1);

  const sent = await outboxAbout(id);
  // Group A: Yasmine (mom, dad) and Omar (mom2) → three parents, one row each.
  assert.deepEqual(sent.map((n) => n.recipient_id).sort(), [a.mom.userId, a.dad.userId, a.mom2.userId].sort());
  assert.ok(sent.every((n) => n.kind === "session_created"));
  const toMom = sent.find((n) => n.recipient_id === a.mom.userId);
  assert.equal(toMom.title, "حصة جديدة · ياسمين");
  assert.match(toMom.body, /^ورشة الرسم · \d\d\/\d\d · 17:00$/);
  assert.ok(!sent.some((n) => n.recipient_id === a.other.userId), "group B's parent hears nothing");
});

test("a weekly series makes one session per date and one notification per parent", async () => {
  const dates = weekly(3, 4); // four Wednesdays
  const first = await must(create(a.advisor, a.groupA, inSamae("نادي القراءة", dates[0], "15:00", "16:00", 2), dates, [3],
    [{ kind: "drive", url: "https://drive.google.com/x", label: "الكتاب" }]));

  const rows = await must(a.teacherA.from("sessions").select("id, session_date, series_id, materials(url)").eq("title", "نادي القراءة").eq("group_id", a.groupA).order("session_date"));
  assert.deepEqual(rows.map((r) => r.session_date), dates);
  assert.ok(rows.every((r) => r.series_id && r.series_id === rows[0].series_id));
  assert.equal(rows[0].id, first);
  assert.deepEqual(rows.map((r) => r.materials.length), [1, 0, 0, 0], "materials go on the first session");

  const series = await must(a.teacherA.from("session_series").select("weekdays, start_date, end_date").eq("id", rows[0].series_id).single());
  assert.deepEqual(series, { weekdays: [3], start_date: dates[0], end_date: dates[3] });

  const sent = await outboxAbout(first);
  assert.equal(sent.length, 3, "one per parent, not one per session");
  assert.ok(sent.every((n) => n.kind === "session_created" && n.title.startsWith("حصص جديدة")));
  assert.match(sent[0].body, /أسبوعياً من/);
  for (const r of rows.slice(1)) assert.equal((await outboxAbout(r.id)).length, 0);
});

test("an away trip needs an address and a pick-up; a session needs a floor and a sane time", async () => {
  const date = day(10);
  const trip = await must(create(a.advisor, a.groupA, away("رحلة إلى الحديقة", date), [date]));
  const s = await must(a.mom.from("sessions").select("place, address, pickup_place, pickup_time").eq("id", trip).single());
  assert.deepEqual(s, { place: "away", address: "حديقة الجامعة العربية", pickup_place: "جمعية سماء", pickup_time: "12:30:00" });

  await refused(create(a.advisor, a.groupA, away("بلا عنوان", date, { address: null }), [date]), "23514");
  await refused(create(a.advisor, a.groupA, away("بلا استلام", date, { pickup_time: null }), [date]), "23514");
  await refused(create(a.advisor, a.groupA, inSamae("بلا طابق", date, "17:00", "18:00", null), [date]), "23514");
  await refused(create(a.advisor, a.groupA, inSamae("مقلوبة", date, "18:00", "17:00"), [date]), "23514");
  await refused(create(a.advisor, a.groupA, inSamae("طابق خيالي", date, "17:00", "18:00", 9), [date]), "23514");
  await refused(create(a.advisor, a.groupA, inSamae("بلا تاريخ", date), []), "22023");
  await refused(create(a.advisor, a.groupA, inSamae("رابط", date), [date], null, [{ kind: "other", url: "http://insecure", label: "x" }]), "23514");
});

test("only advisors schedule: instructors, even the group's own, and parents cannot", async () => {
  const date = day(4);
  const asTeacher = await refused(create(a.teacherA, a.groupA, inSamae("أستاذة", date), [date]), "42501");
  assert.equal(asTeacher.message, "not_allowed");
  await refused(create(a.teacherB, a.groupA, inSamae("دخيل", date), [date]), "42501");
  await refused(create(a.mom, a.groupA, inSamae("ولي", date), [date]), "42501");
  // Writing to the table directly is held to the same rule.
  const direct = await a.teacherA.from("sessions").insert({ ...inSamae("مباشر", date), group_id: a.groupA });
  assert.equal(direct.error?.code, "42501");
  // The advisor schedules for any group.
  await must(create(a.advisor, a.groupB, inSamae("مستشار", date), [date]));
});

test("moving one session marks it changed, remembers the old time and tells parents", async () => {
  const date = day(5);
  const id = await must(create(a.advisor, a.groupA, inSamae("مسرح", date, "17:00", "18:00"), [date]));
  await must(a.advisor.rpc("update_sessions", { p_session: id, p_fields: inSamae("مسرح", date, "17:30", "18:30"), p_upcoming: false }));

  const s = await must(a.mom.from("sessions").select("status, start_time, original_start, original_date").eq("id", id).single());
  assert.deepEqual(s, { status: "changed", start_time: "17:30:00", original_start: "17:00:00", original_date: date });
  const changed = (await outboxAbout(id)).filter((n) => n.kind === "session_changed");
  assert.equal(changed.length, 3);
  assert.match(changed[0].body, /17:30 بدل 17:00$/, "parents see the new and the old time");

  // Renaming only is not a change parents are told about.
  await must(a.advisor.rpc("update_sessions", { p_session: id, p_fields: inSamae("مسرح العرائس", date, "17:30", "18:30"), p_upcoming: false }));
  assert.equal((await outboxAbout(id)).filter((n) => n.kind === "session_changed").length, 3);
  // A second move keeps the first planned time.
  await must(a.advisor.rpc("update_sessions", { p_session: id, p_fields: inSamae("مسرح العرائس", date, "16:00", "17:00"), p_upcoming: false }));
  const again = await must(a.mom.from("sessions").select("original_start").eq("id", id).single());
  assert.equal(again.original_start, "17:00:00");
});

test("changing 'this and the following' moves the rest of the series, not the earlier ones", async () => {
  const dates = weekly(6, 4); // four Saturdays
  await must(create(a.advisor, a.groupA, inSamae("رياضة", dates[0], "10:00", "11:00"), dates, [6]));
  const rows = await must(a.teacherA.from("sessions").select("id").eq("title", "رياضة").eq("group_id", a.groupA).order("session_date"));
  const before = (await must(service.from("notification_outbox").select("id").eq("kind", "session_changed"))).length;

  await must(a.advisor.rpc("update_sessions", { p_session: rows[1].id, p_fields: inSamae("رياضة", dates[1], "11:00", "12:00"), p_upcoming: true }));
  const after = await must(a.teacherA.from("sessions").select("session_date, start_time, status").eq("title", "رياضة").eq("group_id", a.groupA).order("session_date"));
  assert.deepEqual(after.map((r) => [r.session_date, r.start_time, r.status]), [
    [dates[0], "10:00:00", "planned"],
    [dates[1], "11:00:00", "changed"],
    [dates[2], "11:00:00", "changed"],
    [dates[3], "11:00:00", "changed"],
  ]);
  const notes = (await must(service.from("notification_outbox").select("id").eq("kind", "session_changed"))).length - before;
  assert.equal(notes, 3, "one notification per parent for the whole change");
});

test("cancelling one session, then the rest of a series", async () => {
  const date = day(6);
  const one = await must(create(a.advisor, a.groupA, inSamae("موسيقى", date), [date]));
  await must(a.advisor.rpc("cancel_sessions", { p_session: one, p_reason: "عطلة", p_upcoming: false }));
  const s = await must(a.dad.from("sessions").select("status, cancel_reason").eq("id", one).single());
  assert.deepEqual(s, { status: "cancelled", cancel_reason: "عطلة" });
  assert.equal((await outboxAbout(one)).filter((n) => n.kind === "session_cancelled").length, 3);

  const dates = weekly(0, 4); // four Sundays
  await must(create(a.advisor, a.groupA, inSamae("تجويد", dates[0], "11:00", "12:00"), dates, [0]));
  const rows = await must(a.teacherA.from("sessions").select("id").eq("title", "تجويد").eq("group_id", a.groupA).order("session_date"));
  await must(a.advisor.rpc("cancel_sessions", { p_session: rows[2].id, p_reason: "نهاية الدورة", p_upcoming: true }));
  const statuses = await must(a.teacherA.from("sessions").select("status").eq("title", "تجويد").eq("group_id", a.groupA).order("session_date"));
  assert.deepEqual(statuses.map((r) => r.status), ["planned", "planned", "cancelled", "cancelled"]);
  const cancelled = (await outboxAbout(rows[2].id)).filter((n) => n.kind === "session_cancelled");
  assert.equal(cancelled.length, 3);
  assert.ok(cancelled[0].title.startsWith("حصص ملغاة"));

  await refused(a.teacherA.rpc("cancel_sessions", { p_session: rows[0].id, p_reason: "x", p_upcoming: false }), "42501");
});

test("parents see their child's group's sessions and its instructors' names, nothing else", async () => {
  const date = day(7);
  const forA = await must(create(a.advisor, a.groupA, inSamae("لغة عربية", date), [date]));
  const forB = await must(create(a.teacherB, a.groupB, inSamae("علوم", date), [date]));

  const ids = async (who) => (await must(who.from("sessions").select("id").in("id", [forA, forB]))).map((r) => r.id).sort();
  assert.deepEqual(await ids(a.mom), [forA]);
  assert.deepEqual(await ids(a.other), [forB]);
  assert.deepEqual(await ids(a.teacherA), [forA]);
  assert.deepEqual(await ids(a.advisor), [forA, forB].sort());

  const staff = await must(a.mom.rpc("group_staff_names", { g: a.groupA }));
  assert.equal(staff.length, 1);
  assert.match(staff[0].full_name, /^أستاذة أ/);
  assert.deepEqual(await must(a.mom.rpc("group_staff_names", { g: a.groupB })), [], "not another group's staff");
  // Series details and the outbox are not for parents.
  assert.deepEqual(await must(a.mom.from("session_series").select("id")), []);
  assert.deepEqual(await must(a.mom.from("notification_outbox").select("id")), []);
});
