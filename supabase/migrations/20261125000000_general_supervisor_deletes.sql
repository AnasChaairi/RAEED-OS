-- Deleting children, categories (فئات), seasons and terms is for the مشرف عام (role
-- advisor) only. Children, seasons and terms already allow delete only to advisors through
-- their "for all" write policies, and their dependent rows cascade. A category does not
-- cascade (its sessions, schedules, memberships and absence alerts keep it), so it is
-- deleted through delete_group(), which removes those first. Staff and parent accounts
-- are deleted through the manage-account function, which already checks for an advisor.

-- Delete policies stated on their own, so a later change to the write policies cannot open
-- deletion to other roles by accident.
drop policy if exists children_write on public.children;
create policy children_insert on public.children for insert with check (has_role('advisor'));
create policy children_update on public.children for update using (has_role('advisor')) with check (has_role('advisor'));
create policy children_delete on public.children for delete using (has_role('advisor'));

drop policy if exists groups_write on public.groups;
create policy groups_insert on public.groups for insert with check (has_role('advisor'));
create policy groups_update on public.groups for update using (has_role('advisor')) with check (has_role('advisor'));
create policy groups_delete on public.groups for delete using (has_role('advisor'));

drop policy if exists seasons_write on public.seasons;
create policy seasons_insert on public.seasons for insert with check (has_role('advisor'));
create policy seasons_update on public.seasons for update using (has_role('advisor')) with check (has_role('advisor'));
create policy seasons_delete on public.seasons for delete using (has_role('advisor'));

drop policy if exists terms_write on public.terms;
create policy terms_insert on public.terms for insert with check (has_role('advisor'));
create policy terms_update on public.terms for update using (has_role('advisor')) with check (has_role('advisor'));
create policy terms_delete on public.terms for delete using (has_role('advisor'));

-- Deletes a category with its activities (and their attendance, materials, picked
-- instructors and observations), schedules, absence alerts and membership history.
-- Children in it stay, without a category. Returns the logo path, for the app to remove.
create or replace function public.delete_group(g uuid) returns text
language plpgsql security definer set search_path = public as $$
declare
  logo text;
begin
  if not has_role('advisor') then
    raise exception 'advisors only' using errcode = '42501';
  end if;
  select logo_path into logo from groups where id = g;
  if not found then return null; end if;
  delete from sessions where group_id = g;
  delete from session_series where group_id = g;
  delete from absence_alerts where group_id = g;
  delete from child_groups where group_id = g;
  delete from groups where id = g;
  return logo;
end $$;

-- Takes a staff member off every category and every activity from today on, before the
-- account is deleted (or anonymised, when their name is on attendance or notes).
create or replace function public.release_staff(p uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not has_role('advisor') then
    raise exception 'advisors only' using errcode = '42501';
  end if;
  delete from group_instructors where person_id = p;
  delete from group_supervisors where person_id = p;
  delete from session_instructors si using sessions s
    where si.session_id = s.id and si.person_id = p and s.session_date >= current_date;
end $$;

-- How much a category's deletion takes with it, for the confirmation.
create or replace function public.group_deletion_counts(g uuid)
returns table (sessions bigint, attendance bigint, children bigint)
language sql stable security definer set search_path = public as $$
  select
    (select count(*) from sessions where group_id = g),
    (select count(*) from attendance a join sessions s on s.id = a.session_id where s.group_id = g),
    (select count(*) from child_groups where group_id = g and to_date is null)
  where has_role('advisor')
$$;

revoke execute on function public.delete_group(uuid), public.release_staff(uuid), public.group_deletion_counts(uuid)
  from public, anon;
grant execute on function public.delete_group(uuid), public.release_staff(uuid), public.group_deletion_counts(uuid)
  to authenticated;
