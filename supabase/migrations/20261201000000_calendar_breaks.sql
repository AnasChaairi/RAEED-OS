-- Request from the academy (2026-11-27): the month calendar also shows the school holidays,
-- Ramadan and the days the academy stops (توقف الأكاديمية), from the year's programme.
-- They are only shown: no حصة is cancelled or moved by them.
--
-- A row with no group_id is for every فئة; with one, only for that فئة.
-- Everyone signed in reads them; المشرف العام (role advisor) writes them.

create table if not exists public.calendar_breaks (
  id uuid primary key default gen_random_uuid(),
  -- holiday = عطلة (school or national), ramadan = رمضان, pause = توقف الأكاديمية.
  kind text not null check (kind in ('holiday', 'ramadan', 'pause')),
  title text not null check (btrim(title) <> ''),
  start_date date not null,
  end_date date not null,
  group_id uuid references public.groups (id) on delete cascade,
  created_at timestamptz not null default now(),
  check (end_date >= start_date)
);
create index if not exists calendar_breaks_dates on public.calendar_breaks (start_date, end_date);

alter table public.calendar_breaks enable row level security;

drop policy if exists calendar_breaks_read on public.calendar_breaks;
create policy calendar_breaks_read on public.calendar_breaks for select to authenticated using (true);

drop policy if exists calendar_breaks_write on public.calendar_breaks;
create policy calendar_breaks_write on public.calendar_breaks for all to authenticated
  using (has_role('advisor')) with check (has_role('advisor'));

grant select, insert, update, delete on public.calendar_breaks to authenticated;
