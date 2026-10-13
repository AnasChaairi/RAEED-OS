// Setup: the advisor's seasons, terms, groups, children and parents, and who may change them.
import { test, before } from "node:test";
import assert from "node:assert/strict";
import { academy, createPerson, day, must, service, tag } from "./helpers.mjs";

let a;
before(async () => {
  a = await academy();
});

test("the advisor creates a season with its terms; everyone signed in can read them", async () => {
  const season = await must(a.advisor.from("seasons").insert({ name: `موسم ${a.t}`, starts_on: day(-30), ends_on: day(300) }).select("id").single());
  await must(a.advisor.from("terms").insert([
    { season_id: season.id, name: "الدورة الأولى", starts_on: day(-30), ends_on: day(120) },
    { season_id: season.id, name: "الدورة الثانية", starts_on: day(121), ends_on: day(300) },
  ]));
  for (const who of [a.teacherA, a.mom]) {
    const s = await must(who.from("seasons").select("name, terms(name)").eq("id", season.id).single());
    assert.equal(s.terms.length, 2);
  }
  const { error } = await a.advisor.from("seasons").insert({ name: "مقلوب", starts_on: day(10), ends_on: day(5) });
  assert.equal(error?.code, "23514", "a season must end after it starts");
});

test("only the advisor writes setup data", async () => {
  for (const who of [a.teacherA, a.mom]) {
    for (const [table, row] of [
      ["seasons", { name: "x", starts_on: day(0), ends_on: day(10) }],
      ["groups", { name: `x ${tag()}`, logo_letter: "x" }],
      ["children", { full_name: "x" }],
      ["child_parents", { child_id: a.sara, parent_id: who.userId }],
      ["group_instructors", { group_id: a.groupB, person_id: who.userId }],
    ]) {
      const { error } = await who.from(table).insert(row);
      assert.equal(error?.code, "42501", `${table} insert by non-advisor`);
    }
  }
  // Updates by others match no rows, so nothing changes.
  await a.teacherA.from("groups").update({ name: "مخترق" }).eq("id", a.groupA);
  const g = await must(service.from("groups").select("name").eq("id", a.groupA).single());
  assert.notEqual(g.name, "مخترق");
});

test("group names are unique, and logos and ages are checked", async () => {
  const { data: g } = await service.from("groups").select("name").eq("id", a.groupA).single();
  const dup = await a.advisor.from("groups").insert({ name: g.name, logo_letter: "د" });
  assert.equal(dup.error?.code, "23505", "the app shows 'a group already has this name'");
  const ages = await a.advisor.from("groups").insert({ name: `أعمار ${a.t}`, logo_letter: "ع", age_min: 12, age_max: 8 });
  assert.equal(ages.error?.code, "23514");
  const color = await a.advisor.from("groups").insert({ name: `لون ${a.t}`, logo_letter: "ل", logo_color: 9 });
  assert.equal(color.error?.code, "23514");
});

test("a child has at most two parents", async () => {
  const third = await createPerson(a.advisor, `جدة ${a.t}`, ["parent"]);
  const { error } = await a.advisor.from("child_parents").insert({ child_id: a.yasmine, parent_id: third.userId });
  assert.match(error?.message ?? "", /at most two parents/);
});

test("a child is in one group at a time; moving keeps the history", async () => {
  const c = await must(a.advisor.from("children").insert({ full_name: `متنقل ${a.t}` }).select("id").single());
  await must(a.advisor.from("child_groups").insert({ child_id: c.id, group_id: a.groupA, from_date: day(-60) }));
  const second = await a.advisor.from("child_groups").insert({ child_id: c.id, group_id: a.groupB });
  assert.equal(second.error?.code, "23505", "two current groups are refused");

  // What SetupRepository.moveChild does: close the current membership today, open the new one.
  await must(a.advisor.from("child_groups").update({ to_date: day(0) }).eq("child_id", c.id).is("to_date", null));
  await must(a.advisor.from("child_groups").insert({ child_id: c.id, group_id: a.groupB, from_date: day(0) }));
  const rows = await must(a.advisor.from("child_groups").select("group_id, to_date").eq("child_id", c.id).order("from_date"));
  assert.deepEqual(rows.map((r) => [r.group_id, r.to_date]), [[a.groupA, day(0)], [a.groupB, null]]);

  // The old group's instructor no longer sees the child; the new one does.
  assert.equal((await must(a.teacherA.from("children").select("id").eq("id", c.id))).length, 0);
  assert.equal((await must(a.teacherB.from("children").select("id").eq("id", c.id))).length, 1);
});

test("each role sees only its own part of the academy", async () => {
  const childrenSeen = async (who) => (await must(who.from("children").select("id").in("id", [a.yasmine, a.omar, a.sara]))).map((c) => c.id).sort();
  assert.deepEqual(await childrenSeen(a.advisor), [a.yasmine, a.omar, a.sara].sort());
  assert.deepEqual(await childrenSeen(a.teacherA), [a.yasmine, a.omar].sort());
  assert.deepEqual(await childrenSeen(a.teacherB), [a.sara]);
  assert.deepEqual(await childrenSeen(a.mom), [a.yasmine]);
  assert.deepEqual(await childrenSeen(a.other), [a.sara]);

  // Instructors see the phone numbers of their children's parents, not other families'.
  const people = await must(a.teacherA.from("people").select("id").in("id", [a.mom.userId, a.dad.userId, a.mom2.userId, a.other.userId]));
  assert.deepEqual(people.map((p) => p.id).sort(), [a.mom.userId, a.dad.userId, a.mom2.userId].sort());
  // Parents see nobody else's details, not even the other parent of their child.
  const forMom = await must(a.mom.from("people").select("id, phone").neq("id", a.mom.userId));
  assert.equal(forMom.length, 0);
  // But the account screen lists both parents of the child, by name only.
  const parents = await must(a.mom.rpc("my_children_parents"));
  assert.deepEqual(parents.map((p) => p.parent_id).sort(), [a.mom.userId, a.dad.userId].sort());
  assert.ok(parents.every((p) => !("phone" in p)));
});
