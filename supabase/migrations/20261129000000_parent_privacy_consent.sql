-- Request from anas (2026-11-27): on their first sign-in, parents read the Law 09-08
-- personal data statement and accept it in the app. The acceptance is kept on their
-- people row: which version of the text they accepted, and when. When the text changes,
-- the app raises its version and parents are asked again.

alter table public.people add column if not exists privacy_consent_version integer;
alter table public.people add column if not exists privacy_consent_at timestamptz;

-- The app calls this once the parent taps أوافق. People cannot update their own row
-- directly (see 20261012020000_own_profile_updates.sql), so this is the only way in.
create or replace function public.accept_privacy_terms(p_version integer) returns void
language sql security definer set search_path = public as $$
  update people
     set privacy_consent_version = p_version,
         privacy_consent_at = now()
   where id = auth.uid()
     and p_version > 0
$$;
revoke execute on function public.accept_privacy_terms(integer) from public, anon;
grant execute on function public.accept_privacy_terms(integer) to authenticated;
