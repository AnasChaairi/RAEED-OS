-- Request from the academy (2026-11-27): الواجبات (homework).
--
-- The مشرف الفئة (and المشرف العام) gives homework to a whole فئة or to some of its
-- children. They pick a ready template and fill its own fields:
--   review       مراجعة المحفوظ          السورة، من، إلى
--   wird         ورد قرآني               المقدار
--   reading      قراءة مقطع من كتاب      الكتاب، من الصفحة، إلى الصفحة
--   summary      تلخيص مقطع              المصدر، من، إلى
--   presentation إعداد عرض               حول
--   research     إنجاز وتقديم بحث        حول
--   custom       واجب آخر                الواجب، المقدار
-- Every homework has a موعد التسليم and optional details (تفصيل).
--
-- The children's parents are notified and see it in their واجبات tab, where they mark it
-- تم or لم يتم for each child. The supervisor sees, per child, what the parents marked.

-- Tables --------------------------------------------------------------------------------------

create table if not exists public.homework (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.groups (id) on delete cascade,
  template text not null check (template in ('review', 'wird', 'reading', 'summary', 'presentation', 'research', 'custom')),
  -- The template's own fields, by key: surah, from, to, amount, book, topic, title.
  fields jsonb not null default '{}'::jsonb check (jsonb_typeof(fields) = 'object'),
  details text check (char_length(details) <= 2000),
  due_date date not null,
  -- True: every child in the فئة now. False: the children in homework_children.
  whole_group boolean not null default true,
  created_by uuid references public.people (id) on delete set null,
  created_at timestamptz not null default now(),
  check (template <> 'custom' or btrim(coalesce(fields ->> 'title', '')) <> '')
);
create index if not exists homework_group on public.homework (group_id, due_date desc);

create table if not exists public.homework_children (
  homework_id uuid not null references public.homework (id) on delete cascade,
  child_id uuid not null references public.children (id) on delete cascade,
  primary key (homework_id, child_id)
);
create index if not exists homework_children_child on public.homework_children (child_id);

-- What a parent (or the supervisor) marked for one child: done = تم, false = لم يتم.
create table if not exists public.homework_status (
  homework_id uuid not null references public.homework (id) on delete cascade,
  child_id uuid not null references public.children (id) on delete cascade,
  done boolean not null,
  marked_by uuid references public.people (id) on delete set null,
  marked_at timestamptz not null default now(),
  primary key (homework_id, child_id)
);
create index if not exists homework_status_child on public.homework_status (child_id);

-- Access --------------------------------------------------------------------------------------

-- Homework [h] is for child [c]: the child is in its فئة now (whole فئة), or was picked.
create or replace function public.homework_has_child(h uuid, c uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from homework x
    where x.id = h and case
      when x.whole_group then exists (
        select 1 from child_groups cg where cg.child_id = c and cg.group_id = x.group_id and cg.to_date is null)
      else exists (select 1 from homework_children hc where hc.homework_id = h and hc.child_id = c)
    end)
$$;

-- Plans the فئة's homework: its supervisor, or an advisor.
create or replace function public.assigns_homework(g uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select has_role('advisor') or supervises_group(g)
$$;

-- Reads homework [h]: whoever assigns or teaches in its فئة, and the parents of a child it is for.
create or replace function public.reads_homework(h uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from homework x
    where x.id = h and (
      assigns_homework(x.group_id) or teaches_group(x.group_id)
      or exists (
        select 1 from child_parents cp
        where cp.parent_id = auth.uid() and homework_has_child(x.id, cp.child_id))))
$$;

-- Reads what concerns child [c] in homework [h]: the فئة's staff, or the child's parents.
create or replace function public.reads_homework_child(h uuid, c uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select parent_of_child(c) or exists (
    select 1 from homework x where x.id = h and (assigns_homework(x.group_id) or teaches_group(x.group_id)))
$$;

revoke execute on function public.homework_has_child(uuid, uuid), public.assigns_homework(uuid),
  public.reads_homework(uuid), public.reads_homework_child(uuid, uuid) from public, anon;
grant execute on function public.homework_has_child(uuid, uuid), public.assigns_homework(uuid),
  public.reads_homework(uuid), public.reads_homework_child(uuid, uuid) to authenticated;

alter table public.homework enable row level security;
alter table public.homework_children enable row level security;
alter table public.homework_status enable row level security;

drop policy if exists homework_read on public.homework;
create policy homework_read on public.homework for select using (reads_homework(id));
drop policy if exists homework_delete on public.homework;
create policy homework_delete on public.homework for delete using (assigns_homework(group_id));
-- Created and changed through create_homework / update_homework.

drop policy if exists homework_children_read on public.homework_children;
create policy homework_children_read on public.homework_children for select
  using (reads_homework_child(homework_id, child_id));

drop policy if exists homework_status_read on public.homework_status;
create policy homework_status_read on public.homework_status for select
  using (reads_homework_child(homework_id, child_id));
-- Written through set_homework_status.

grant select, delete on public.homework to authenticated;
grant select on public.homework_children, public.homework_status to authenticated;

-- Notifications -------------------------------------------------------------------------------

alter table public.notification_outbox drop constraint if exists notification_outbox_kind_check;
alter table public.notification_outbox add constraint notification_outbox_kind_check check (kind in (
  'session_created', 'session_changed', 'session_cancelled', 'absence_alert',
  'child_message', 'child_message_reply', 'child_message_like', 'instructor_absence',
  'session_reminder', 'activity_created', 'activity_changed', 'activity_cancelled', 'activity_reminder',
  'child_absence', 'homework_assigned'));

-- "مراجعة المحفوظ: سورة الملك من الآية 1 إلى 15"
create or replace function public.homework_summary(h homework) returns text
language sql immutable as $$
  select case h.template
    when 'review' then 'مراجعة المحفوظ: ' || coalesce(nullif(btrim(h.fields ->> 'surah'), ''), '')
      || coalesce(' من ' || nullif(btrim(h.fields ->> 'from'), ''), '')
      || coalesce(' إلى ' || nullif(btrim(h.fields ->> 'to'), ''), '')
    when 'wird' then 'ورد قرآني: ' || coalesce(nullif(btrim(h.fields ->> 'amount'), ''), '')
    when 'reading' then 'قراءة مقطع من ' || coalesce(nullif(btrim(h.fields ->> 'book'), ''), 'كتاب')
      || coalesce(' من الصفحة ' || nullif(btrim(h.fields ->> 'from'), ''), '')
      || coalesce(' إلى الصفحة ' || nullif(btrim(h.fields ->> 'to'), ''), '')
    when 'summary' then 'تلخيص مقطع' || coalesce(' من ' || nullif(btrim(h.fields ->> 'book'), ''), '')
      || coalesce(' من ' || nullif(btrim(h.fields ->> 'from'), ''), '')
      || coalesce(' إلى ' || nullif(btrim(h.fields ->> 'to'), ''), '')
    when 'presentation' then 'إعداد عرض حول ' || coalesce(nullif(btrim(h.fields ->> 'topic'), ''), '')
    when 'research' then 'إنجاز وتقديم بحث حول ' || coalesce(nullif(btrim(h.fields ->> 'topic'), ''), '')
    else btrim(h.fields ->> 'title') || coalesce(' (' || nullif(btrim(h.fields ->> 'amount'), '') || ')', '')
  end
$$;
revoke execute on function public.homework_summary(homework) from public, anon;

-- One notification to each parent, per child the homework is for.
create or replace function public.queue_homework_notification(p_homework uuid) returns void
language plpgsql security definer set search_path = public as $$
declare
  h homework;
begin
  select * into h from homework where id = p_homework;
  insert into notification_outbox (recipient_id, kind, title, body, data)
  select distinct cp.parent_id, 'homework_assigned', 'واجب جديد · ' || split_part(c.full_name, ' ', 1),
         left(homework_summary(h), 160) || ' · التسليم: ' || to_char(h.due_date, 'DD/MM'),
         jsonb_build_object('homework_id', h.id, 'child_id', c.id)
  from children c join child_parents cp on cp.child_id = c.id
  where homework_has_child(h.id, c.id) and cp.parent_id is distinct from auth.uid();
end $$;
revoke all on function public.queue_homework_notification(uuid) from public, anon, authenticated;

-- Assigning -----------------------------------------------------------------------------------

-- Checks and writes [p_children] for homework [h]: empty means the whole فئة; each child
-- must be in it now.
create or replace function public.set_homework_children(h homework, p_children uuid[]) returns void
language plpgsql security definer set search_path = public as $$
begin
  delete from homework_children where homework_id = h.id;
  if h.whole_group then
    return;
  end if;
  if exists (
    select 1 from unnest(p_children) c
    where not exists (
      select 1 from child_groups cg where cg.child_id = c and cg.group_id = h.group_id and cg.to_date is null)) then
    raise exception 'child_not_in_group' using errcode = '22023';
  end if;
  insert into homework_children (homework_id, child_id) select h.id, c from unnest(p_children) c on conflict do nothing;
end $$;
revoke all on function public.set_homework_children(homework, uuid[]) from public, anon, authenticated;

-- New homework. [p_fields]: group_id, template, fields, details, due_date. [p_children]:
-- empty or null for the whole فئة. Notifies the parents.
create or replace function public.create_homework(p_fields jsonb, p_children uuid[] default null)
returns uuid
language plpgsql security definer set search_path = public as $$
declare
  h homework;
  g uuid := (p_fields ->> 'group_id')::uuid;
begin
  if g is null or not assigns_homework(g) then
    raise exception 'not_allowed' using errcode = '42501';
  end if;
  insert into homework (group_id, template, fields, details, due_date, whole_group, created_by)
  values (g, p_fields ->> 'template', coalesce(p_fields -> 'fields', '{}'::jsonb),
          nullif(btrim(p_fields ->> 'details'), ''), (p_fields ->> 'due_date')::date,
          coalesce(array_length(p_children, 1), 0) = 0, auth.uid())
  returning * into h;
  perform set_homework_children(h, p_children);
  perform queue_homework_notification(h.id);
  return h.id;
end $$;

-- Changes homework [p_id] (same fields as create_homework, the فئة stays). Children who
-- are no longer concerned lose their marks. Nobody is notified again.
create or replace function public.update_homework(p_id uuid, p_fields jsonb, p_children uuid[] default null)
returns void
language plpgsql security definer set search_path = public as $$
declare
  h homework;
begin
  select * into h from homework where id = p_id;
  if h.id is null or not assigns_homework(h.group_id) then
    raise exception 'not_allowed' using errcode = '42501';
  end if;
  update homework set
    template = p_fields ->> 'template',
    fields = coalesce(p_fields -> 'fields', '{}'::jsonb),
    details = nullif(btrim(p_fields ->> 'details'), ''),
    due_date = (p_fields ->> 'due_date')::date,
    whole_group = coalesce(array_length(p_children, 1), 0) = 0
  where id = p_id
  returning * into h;
  perform set_homework_children(h, p_children);
  delete from homework_status s where s.homework_id = p_id and not homework_has_child(p_id, s.child_id);
end $$;

-- A parent of [p_child] (or the فئة's supervisor) marks homework [p_homework]: true = تم,
-- false = لم يتم, null = clears the mark.
create or replace function public.set_homework_status(p_homework uuid, p_child uuid, p_done boolean)
returns void
language plpgsql security definer set search_path = public as $$
declare
  g uuid;
begin
  select group_id into g from homework where id = p_homework;
  if g is null or not homework_has_child(p_homework, p_child)
     or not (parent_of_child(p_child) or assigns_homework(g)) then
    raise exception 'not_allowed' using errcode = '42501';
  end if;
  if p_done is null then
    delete from homework_status where homework_id = p_homework and child_id = p_child;
  else
    insert into homework_status (homework_id, child_id, done, marked_by, marked_at)
    values (p_homework, p_child, p_done, auth.uid(), now())
    on conflict (homework_id, child_id)
      do update set done = excluded.done, marked_by = excluded.marked_by, marked_at = excluded.marked_at;
  end if;
end $$;

revoke execute on function public.create_homework(jsonb, uuid[]), public.update_homework(uuid, jsonb, uuid[]),
  public.set_homework_status(uuid, uuid, boolean) from public, anon;
grant execute on function public.create_homework(jsonb, uuid[]), public.update_homework(uuid, jsonb, uuid[]),
  public.set_homework_status(uuid, uuid, boolean) to authenticated;
