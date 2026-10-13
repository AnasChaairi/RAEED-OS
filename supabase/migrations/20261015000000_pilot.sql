-- Stage 5: what the pilot measures, and account deletion requests.

-- Usage the pilot metrics need and the database cannot see otherwise: how long the
-- attendance sheet took, and when advisors opened the statistics.
create table public.usage_events (
  id uuid primary key default gen_random_uuid(),
  person_id uuid not null default auth.uid() references public.people (id) on delete cascade,
  kind text not null check (kind in ('attendance_sheet', 'stats_view')),
  session_id uuid references public.sessions (id) on delete cascade,
  seconds integer check (seconds between 0 and 86400),
  at timestamptz not null default now()
);
create index usage_events_kind_at on public.usage_events (kind, at);
alter table public.usage_events enable row level security;
create policy usage_insert_own on public.usage_events for insert with check (person_id = auth.uid());
create policy usage_advisor_read on public.usage_events for select using (has_role('advisor'));

-- Someone asking for their account and data to be deleted (an app store requirement).
-- The advisor sees the request in Setup and deletes the account.
create table public.account_deletion_requests (
  person_id uuid primary key default auth.uid() references public.people (id) on delete cascade,
  requested_at timestamptz not null default now()
);
alter table public.account_deletion_requests enable row level security;
create policy deletion_request_own on public.account_deletion_requests for insert with check (person_id = auth.uid());
create policy deletion_request_read on public.account_deletion_requests for select using (
  person_id = auth.uid() or has_role('advisor'));
create policy deletion_request_withdraw on public.account_deletion_requests for delete using (
  person_id = auth.uid() or has_role('advisor'));

-- The pilot's success metrics (product definition) between two days, for advisors.
create or replace function public.pilot_metrics(p_from date, p_to date)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public'
as $function$
declare
  result jsonb;
begin
  if not has_role('advisor') then
    raise exception 'advisors only' using errcode = '42501';
  end if;

  with held as (
    select s.id, s.group_id,
           (s.session_date + s.end_time) at time zone 'Africa/Casablanca' as ended_at
    from sessions s
    where s.status <> 'cancelled' and s.session_date between p_from and p_to
      and (s.session_date + s.end_time) at time zone 'Africa/Casablanca' <= now()
  ),
  recorded as (
    select h.id, h.group_id, h.ended_at, min(a.recorded_at) as first_saved
    from held h left join attendance a on a.session_id = h.id
    group by h.id, h.group_id, h.ended_at
  ),
  alerts as (
    select a.id,
           least(a.closed_at, a.last_attempt_at) <= a.created_at + interval '7 days' as followed_up
    from absence_alerts a
    where (a.created_at at time zone 'Africa/Casablanca')::date between p_from and p_to
      and (a.created_at <= now() - interval '7 days' or a.closed_at is not null or a.last_attempt_at is not null)
  ),
  families as (
    select c.id, bool_or(not p.must_change_password) as signed_in
    from children c
    join child_parents cp on cp.child_id = c.id
    join people p on p.id = cp.parent_id
    group by c.id
  )
  select jsonb_build_object(
    'sessions_held', (select count(*) from recorded),
    'recorded_within_24h', (select count(*) from recorded where first_saved <= ended_at + interval '24 hours'),
    'recorded_late', (select count(*) from recorded where first_saved > ended_at + interval '24 hours'),
    'by_group', coalesce((
      select jsonb_agg(jsonb_build_object('group_id', group_id, 'held', held, 'on_time', on_time))
      from (
        select group_id, count(*) as held,
               count(*) filter (where first_saved <= ended_at + interval '24 hours') as on_time
        from recorded group by group_id
      ) g), '[]'::jsonb),
    'median_sheet_seconds', (
      select percentile_cont(0.5) within group (order by seconds)
      from usage_events
      where kind = 'attendance_sheet' and seconds is not null
        and (at at time zone 'Africa/Casablanca')::date between p_from and p_to),
    'sheets_timed', (
      select count(*) from usage_events
      where kind = 'attendance_sheet' and seconds is not null
        and (at at time zone 'Africa/Casablanca')::date between p_from and p_to),
    'alerts_due', (select count(*) from alerts),
    'alerts_followed_up', (select count(*) from alerts where followed_up),
    'families', (select count(*) from families),
    'families_signed_in', (select count(*) from families where signed_in),
    'advisors', coalesce((
      select jsonb_agg(jsonb_build_object(
        'full_name', p.full_name,
        'weeks_opened', (
          select count(distinct date_trunc('week', (u.at at time zone 'Africa/Casablanca')::date + 1))
          from usage_events u
          where u.person_id = p.id and u.kind = 'stats_view'
            and (u.at at time zone 'Africa/Casablanca')::date between p_from and p_to),
        'last_opened', (
          select max(u.at) from usage_events u where u.person_id = p.id and u.kind = 'stats_view'))
        order by p.full_name)
      from people p join person_roles r on r.person_id = p.id and r.role = 'advisor'), '[]'::jsonb)
  ) into result;
  return result;
end $function$;
revoke execute on function public.pilot_metrics(date, date) from public, anon;
grant execute on function public.pilot_metrics(date, date) to authenticated;
