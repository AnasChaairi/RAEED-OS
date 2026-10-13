-- Testers asked for each child's and each staff member's gender, and for an uploaded logo
-- per group. Gender stays empty on existing rows; the app asks for it on the next save.

alter table public.children add column gender text check (gender in ('male', 'female'));
alter table public.people add column gender text check (gender in ('male', 'female'));

-- groups.logo_path (from the first migration) names an image in the public bucket
-- "group-logos". Group logos are not personal data, so anyone may read them; only
-- advisors upload, replace or remove them.
do $$ begin
  if to_regclass('storage.buckets') is null then
    return; -- plain Postgres, as in supabase/tests/run_local.sh
  end if;

  insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
  values ('group-logos', 'group-logos', true, 1048576, array['image/jpeg', 'image/png', 'image/webp'])
  on conflict (id) do update set public = true, file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

  create policy group_logos_advisor_insert on storage.objects for insert to authenticated
    with check (bucket_id = 'group-logos' and public.has_role('advisor'));
  create policy group_logos_advisor_update on storage.objects for update to authenticated
    using (bucket_id = 'group-logos' and public.has_role('advisor'))
    with check (bucket_id = 'group-logos' and public.has_role('advisor'));
  create policy group_logos_advisor_delete on storage.objects for delete to authenticated
    using (bucket_id = 'group-logos' and public.has_role('advisor'));
end $$;
