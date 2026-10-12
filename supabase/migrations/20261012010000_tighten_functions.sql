-- Address Supabase security advisors on the initial schema.

-- Fixed search_path on the two trigger functions that lacked it.
alter function public.limit_two_parents() set search_path = public;
alter function public.attendance_keep_latest() set search_path = public;

-- Nobody signed out may call any of these functions.
revoke execute on function public.has_role(public.app_role), public.teaches_group(uuid), public.teaches_child(uuid),
  public.parent_of_child(uuid), public.parent_in_group(uuid), public.group_staff_names(uuid),
  public.queue_session_notification(), public.raise_absence_alert(),
  public.limit_two_parents(), public.attendance_keep_latest()
  from public, anon;

-- Trigger functions are only ever called by their triggers.
revoke execute on function public.queue_session_notification(), public.raise_absence_alert(),
  public.limit_two_parents(), public.attendance_keep_latest()
  from authenticated;

-- Access helpers stay callable by signed-in users: row-level security policies run them
-- as the caller. Each only answers a question about the caller themselves.
grant execute on function public.has_role(public.app_role), public.teaches_group(uuid), public.teaches_child(uuid),
  public.parent_of_child(uuid), public.parent_in_group(uuid), public.group_staff_names(uuid)
  to authenticated;
