-- RAEED OS: initial schema, access rules and server-side triggers.
-- Matches the RAEED OS Architecture doc (data model, access control, offline attendance).

create extension if not exists pgcrypto;

-- Types ---------------------------------------------------------------------

create type public.app_role as enum ('advisor', 'instructor', 'parent');
create type public.attendance_status as enum ('present', 'late', 'absent', 'excused');
create type public.session_place as enum ('samae', 'away');
create type public.session_status as enum ('planned', 'changed', 'cancelled');
create type public.alert_status as enum ('open', 'closed');
create type public.material_kind as enum ('youtube', 'drive', 'other');

-- People and roles ------------------------------------------------------------

create table public.people (
  id uuid primary key references auth.users (id) on delete cascade,
  full_name text not null,
  phone text not null unique,
  must_change_password boolean not null default true,
  created_at timestamptz not null default now()
);

create table public.person_roles (
  person_id uuid not null references public.people (id) on delete cascade,
  role public.app_role not null,
  primary key (person_id, role)
);

-- Seasons and terms -----------------------------------------------------------

create table public.seasons (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  starts_on date not null,
  ends_on date not null,
  check (ends_on > starts_on)
);

create table public.terms (
  id uuid primary key default gen_random_uuid(),
  season_id uuid not null references public.seasons (id) on delete cascade,
  name text not null,
  starts_on date not null,
  ends_on date not null,
  check (ends_on > starts_on)
);

-- Groups (فئات) -----------------------------------------------------------------

create table public.groups (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  logo_letter text not null check (char_length(logo_letter) between 1 and 2),
  logo_color smallint not null default 1 check (logo_color between 1 and 8),
  logo_path text, -- optional uploaded image in storage bucket "group-logos"
  age_min smallint check (age_min between 3 and 20),
  age_max smallint check (age_max between 3 and 20),
  archived boolean not null default false,
  check (age_min is null or age_max is null or age_max >= age_min)
);

create table public.group_instructors (
  group_id uuid not null references public.groups (id) on delete cascade,
  person_id uuid not null references public.people (id) on delete cascade,
  primary key (group_id, person_id)
);

-- Children and parents ----------------------------------------------------------

create table public.children (
  id uuid primary key default gen_random_uuid(),
  full_name text not null,
  birth_date date,
  consent_recorded_at timestamptz,
  consent_recorded_by uuid references public.people (id),
  created_at timestamptz not null default now()
);

create table public.child_groups (
  id uuid primary key default gen_random_uuid(),
  child_id uuid not null references public.children (id) on delete cascade,
  group_id uuid not null references public.groups (id),
  from_date date not null default current_date,
  to_date date,
  check (to_date is null or to_date >= from_date)
);
-- A child is in at most one group at a time.
create unique index child_groups_one_current on public.child_groups (child_id) where to_date is null;

create table public.child_parents (
  child_id uuid not null references public.children (id) on delete cascade,
  parent_id uuid not null references public.people (id) on delete cascade,
  primary key (child_id, parent_id)
);

create function public.limit_two_parents() returns trigger language plpgsql as $$
begin
  if (select count(*) from public.child_parents where child_id = new.child_id) >= 2 then
    raise exception 'A child can have at most two parents';
  end if;
  return new;
end $$;

create trigger child_parents_max_two before insert on public.child_parents
  for each row execute function public.limit_two_parents();

-- Sessions ------------------------------------------------------------------------

create table public.session_series (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.groups (id),
  weekdays smallint[] not null check (weekdays <@ array[0,1,2,3,4,5,6]::smallint[] and cardinality(weekdays) > 0),
  start_date date not null,
  end_date date not null,
  check (end_date >= start_date),
  created_by uuid references public.people (id),
  created_at timestamptz not null default now()
);

create table public.sessions (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.groups (id),
  series_id uuid references public.session_series (id) on delete set null,
  title text not null,
  session_date date not null,
  start_time time not null,
  end_time time not null,
  place public.session_place not null default 'samae',
  floor smallint check (floor between -1 and 4), -- -1 basement, 0 ground, 1..4
  address text,
  map_url text,
  dropoff_place text,
  dropoff_time time,
  pickup_place text,
  pickup_time time,
  status public.session_status not null default 'planned',
  cancel_reason text,
  created_by uuid references public.people (id),
  updated_at timestamptz not null default now(),
  check (end_time > start_time),
  check (place = 'away' or floor is not null),
  check (place = 'samae' or (address is not null and pickup_place is not null and pickup_time is not null))
);
create index sessions_group_date on public.sessions (group_id, session_date);

create table public.materials (
  id uuid primary key default gen_random_uuid(),
  session_id uuid not null references public.sessions (id) on delete cascade,
  kind public.material_kind not null default 'other',
  url text not null check (url ~* '^https://'),
  label text not null
);

-- Attendance, notes, alerts --------------------------------------------------------

create table public.attendance (
  id uuid primary key, -- generated on the phone, so re-sending is harmless
  session_id uuid not null references public.sessions (id) on delete cascade,
  child_id uuid not null references public.children (id) on delete cascade,
  status public.attendance_status not null,
  recorded_by uuid not null references public.people (id),
  recorded_at timestamptz not null, -- time on the phone when it was saved
  received_at timestamptz not null default now(),
  unique (session_id, child_id)
);

create table public.notes (
  id uuid primary key default gen_random_uuid(),
  child_id uuid not null references public.children (id) on delete cascade,
  author_id uuid not null references public.people (id),
  body text not null check (char_length(body) between 1 and 2000),
  created_at timestamptz not null default now()
);

create table public.absence_alerts (
  id uuid primary key default gen_random_uuid(),
  child_id uuid not null references public.children (id) on delete cascade,
  group_id uuid not null references public.groups (id),
  session_ids uuid[] not null,
  status public.alert_status not null default 'open',
  reached_parent boolean,
  reason text,
  closed_by uuid references public.people (id),
  closed_at timestamptz,
  created_at timestamptz not null default now()
);
create unique index absence_alerts_one_open on public.absence_alerts (child_id) where status = 'open';

-- Notifications ------------------------------------------------------------------------

create table public.devices (
  id uuid primary key default gen_random_uuid(),
  person_id uuid not null references public.people (id) on delete cascade,
  push_token text not null unique,
  platform text not null check (platform in ('android', 'ios')),
  updated_at timestamptz not null default now()
);

-- Outbox read by the send-notifications server function; one row per recipient.
create table public.notification_outbox (
  id uuid primary key default gen_random_uuid(),
  recipient_id uuid not null references public.people (id) on delete cascade,
  kind text not null check (kind in ('session_created', 'session_changed', 'session_cancelled', 'absence_alert')),
  title text not null,
  body text not null,
  data jsonb not null default '{}',
  created_at timestamptz not null default now(),
  sent_at timestamptz
);
create index notification_outbox_unsent on public.notification_outbox (created_at) where sent_at is null;

-- Access helpers (security definer so policies can call them without recursion) --------

create function public.has_role(r public.app_role) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from person_roles where person_id = auth.uid() and role = r)
$$;

create function public.teaches_group(g uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from group_instructors where group_id = g and person_id = auth.uid())
$$;

create function public.teaches_child(c uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from child_groups cg join group_instructors gi on gi.group_id = cg.group_id
    where cg.child_id = c and cg.to_date is null and gi.person_id = auth.uid())
$$;

create function public.parent_of_child(c uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from child_parents where child_id = c and parent_id = auth.uid())
$$;

create function public.parent_in_group(g uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from child_groups cg join child_parents cp on cp.child_id = cg.child_id
    where cg.group_id = g and cg.to_date is null and cp.parent_id = auth.uid())
$$;

-- Row-level security ---------------------------------------------------------------------

alter table public.people enable row level security;
alter table public.person_roles enable row level security;
alter table public.seasons enable row level security;
alter table public.terms enable row level security;
alter table public.groups enable row level security;
alter table public.group_instructors enable row level security;
alter table public.children enable row level security;
alter table public.child_groups enable row level security;
alter table public.child_parents enable row level security;
alter table public.session_series enable row level security;
alter table public.sessions enable row level security;
alter table public.materials enable row level security;
alter table public.attendance enable row level security;
alter table public.notes enable row level security;
alter table public.absence_alerts enable row level security;
alter table public.devices enable row level security;
alter table public.notification_outbox enable row level security; -- server only: no policies

-- People: advisors manage everyone; staff see parents of their groups' children and
-- co-instructors; everyone sees themselves. Accounts are created by a server function.
create policy people_read on public.people for select using (
  id = auth.uid()
  or has_role('advisor')
  or (has_role('instructor') and exists (
        select 1 from child_parents cp where cp.parent_id = people.id and teaches_child(cp.child_id)))
  or exists (select 1 from group_instructors gi where gi.person_id = people.id and (teaches_group(gi.group_id)))
);
create policy people_advisor_write on public.people for update using (has_role('advisor'));
create policy people_self_update on public.people for update using (id = auth.uid());

create policy roles_read on public.person_roles for select using (person_id = auth.uid() or has_role('advisor'));

create policy seasons_read on public.seasons for select using (auth.uid() is not null);
create policy seasons_write on public.seasons for all using (has_role('advisor')) with check (has_role('advisor'));
create policy terms_read on public.terms for select using (auth.uid() is not null);
create policy terms_write on public.terms for all using (has_role('advisor')) with check (has_role('advisor'));

create policy groups_read on public.groups for select using (
  has_role('advisor') or teaches_group(id) or parent_in_group(id));
create policy groups_write on public.groups for all using (has_role('advisor')) with check (has_role('advisor'));

create policy gi_read on public.group_instructors for select using (
  has_role('advisor') or teaches_group(group_id) or parent_in_group(group_id));
create policy gi_write on public.group_instructors for all using (has_role('advisor')) with check (has_role('advisor'));

create policy children_read on public.children for select using (
  has_role('advisor') or teaches_child(id) or parent_of_child(id));
create policy children_write on public.children for all using (has_role('advisor')) with check (has_role('advisor'));

create policy cg_read on public.child_groups for select using (
  has_role('advisor') or teaches_child(child_id) or parent_of_child(child_id));
create policy cg_write on public.child_groups for all using (has_role('advisor')) with check (has_role('advisor'));

create policy cp_read on public.child_parents for select using (
  has_role('advisor') or teaches_child(child_id) or parent_id = auth.uid());
create policy cp_write on public.child_parents for all using (has_role('advisor')) with check (has_role('advisor'));

create policy series_read on public.session_series for select using (
  has_role('advisor') or teaches_group(group_id));
create policy series_write on public.session_series for all using (teaches_group(group_id)) with check (teaches_group(group_id));

create policy sessions_read on public.sessions for select using (
  has_role('advisor') or teaches_group(group_id) or parent_in_group(group_id));
create policy sessions_write on public.sessions for all using (teaches_group(group_id)) with check (teaches_group(group_id));

create policy materials_read on public.materials for select using (exists (
  select 1 from sessions s where s.id = session_id
  and (has_role('advisor') or teaches_group(s.group_id) or parent_in_group(s.group_id))));
create policy materials_write on public.materials for all using (exists (
  select 1 from sessions s where s.id = session_id and teaches_group(s.group_id)))
  with check (exists (select 1 from sessions s where s.id = session_id and teaches_group(s.group_id)));

-- Attendance: no parent access in version 1.
create policy attendance_read on public.attendance for select using (
  has_role('advisor') or teaches_child(child_id));
create policy attendance_insert on public.attendance for insert with check (
  recorded_by = auth.uid() and teaches_child(child_id)
  and exists (select 1 from sessions s where s.id = session_id and teaches_group(s.group_id)));
create policy attendance_update on public.attendance for update using (teaches_child(child_id))
  with check (recorded_by = auth.uid() and teaches_child(child_id));

-- Notes: staff only, never parents.
create policy notes_read on public.notes for select using (has_role('advisor') or teaches_child(child_id));
create policy notes_insert on public.notes for insert with check (
  author_id = auth.uid() and (has_role('advisor') or teaches_child(child_id)));

create policy alerts_read on public.absence_alerts for select using (has_role('advisor') or teaches_group(group_id));
create policy alerts_close on public.absence_alerts for update using (has_role('advisor') or teaches_group(group_id));

create policy devices_own on public.devices for all using (person_id = auth.uid()) with check (person_id = auth.uid());

-- Offline sync: last save wins, judged by the time on the phone -------------------------

create function public.attendance_keep_latest() returns trigger language plpgsql as $$
begin
  if new.recorded_at < old.recorded_at then
    return old; -- an older offline record arriving late must not overwrite a newer one
  end if;
  new.received_at := now();
  return new;
end $$;

create trigger attendance_latest_wins before update on public.attendance
  for each row execute function public.attendance_keep_latest();

-- Absence alert: two unexcused absences in a row in the child's group ------------------

create function public.raise_absence_alert() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  g uuid;
  last_two record;
begin
  if new.status <> 'absent' then
    return new;
  end if;
  select group_id into g from sessions where id = new.session_id;

  select array_agg(id order by session_date desc, start_time desc) as ids,
         bool_and(st = 'absent') as both_absent, count(*) as n
    into last_two
    from (
      select s.id, s.session_date, s.start_time, a.status as st
      from sessions s join attendance a on a.session_id = s.id and a.child_id = new.child_id
      where s.group_id = g and s.status <> 'cancelled'
      order by s.session_date desc, s.start_time desc
      limit 2
    ) recent;

  if last_two.n = 2 and last_two.both_absent then
    insert into absence_alerts (child_id, group_id, session_ids)
    values (new.child_id, g, last_two.ids)
    on conflict (child_id) where status = 'open' do nothing;
  end if;
  return new;
end $$;

create trigger attendance_absence_alert after insert or update of status on public.attendance
  for each row execute function public.raise_absence_alert();

-- Parent notifications: one outbox row per parent per child, naming the child ----------

create function public.queue_session_notification() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  kind text;
  verb text;
begin
  if tg_op = 'INSERT' then
    kind := 'session_created'; verb := 'حصة جديدة';
  elsif new.status = 'cancelled' and old.status <> 'cancelled' then
    kind := 'session_cancelled'; verb := 'حصة ملغاة';
  elsif (new.session_date, new.start_time, new.end_time, new.place, new.floor, new.address, new.pickup_time, new.pickup_place)
        is distinct from
        (old.session_date, old.start_time, old.end_time, old.place, old.floor, old.address, old.pickup_time, old.pickup_place) then
    kind := 'session_changed'; verb := 'تغيير موعد';
  else
    return new;
  end if;

  insert into notification_outbox (recipient_id, kind, title, body, data)
  select cp.parent_id, kind,
         verb || ' · ' || split_part(c.full_name, ' ', 1),
         new.title || ' · ' || to_char(new.session_date, 'DD/MM') || ' · ' || to_char(new.start_time, 'HH24:MI')
           || case when tg_op = 'UPDATE' and kind = 'session_changed' and new.start_time <> old.start_time
                   then ' بدل ' || to_char(old.start_time, 'HH24:MI') else '' end,
         jsonb_build_object('session_id', new.id, 'child_id', c.id)
  from child_groups cg
  join children c on c.id = cg.child_id
  join child_parents cp on cp.child_id = c.id
  where cg.group_id = new.group_id and cg.to_date is null;

  return new;
end $$;

create trigger sessions_notify after insert or update on public.sessions
  for each row execute function public.queue_session_notification();

-- Advisor statistics: attendance rate per group and term (late counts as attended) -------

create view public.group_term_attendance with (security_invoker = true) as
select s.group_id, t.id as term_id,
       count(*) filter (where a.status in ('present', 'late')) as attended,
       count(*) filter (where a.status = 'absent') as absent,
       count(*) filter (where a.status = 'excused') as excused,
       round(100.0 * count(*) filter (where a.status in ('present', 'late'))
             / nullif(count(*) filter (where a.status <> 'excused'), 0), 1) as rate
from attendance a
join sessions s on s.id = a.session_id
join terms t on s.session_date between t.starts_on and t.ends_on
group by s.group_id, t.id;

-- Instructor names for a group, for parents' session detail (names only, no phone numbers).
create function public.group_staff_names(g uuid) returns table (full_name text)
language sql stable security definer set search_path = public as $$
  select p.full_name from group_instructors gi join people p on p.id = gi.person_id
  where gi.group_id = g and (has_role('advisor') or teaches_group(g) or parent_in_group(g))
  order by p.full_name
$$;
