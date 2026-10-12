-- People could update any column of their own row (including phone). Replace that with one
-- narrow call the app makes after the first-sign-in password change.
drop policy people_self_update on public.people;

create function public.mark_password_changed() returns void
language sql security definer set search_path = public as $$
  update people set must_change_password = false where id = auth.uid()
$$;
revoke execute on function public.mark_password_changed() from public, anon;
grant execute on function public.mark_password_changed() to authenticated;
