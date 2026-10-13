-- The hosted project's URL was written into the outbox trigger and the cron job, so every
-- other copy of the database (a local one, a Supabase branch) woke production's
-- send-notifications function. The URL now comes from the Vault secret "project_url",
-- set once on each project that should send notifications:
--   select vault.create_secret('https://<project-ref>.supabase.co', 'project_url');
-- Without it nothing is called and notifications stay in the outbox.

create or replace function public.notification_sender_url()
returns text
language plpgsql
stable
security definer
set search_path to 'public'
as $function$
declare
  base text;
begin
  if to_regclass('vault.decrypted_secrets') is null then
    return null; -- plain Postgres, as in supabase/tests/run_local.sh
  end if;
  execute $q$select decrypted_secret from vault.decrypted_secrets where name = 'project_url' limit 1$q$ into base;
  return case when base is null or base = '' then null
              else rtrim(base, '/') || '/functions/v1/send-notifications' end;
end $function$;
revoke execute on function public.notification_sender_url() from public, anon, authenticated;

create or replace function public.wake_notification_sender()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  url text := notification_sender_url();
begin
  if url is not null and exists (select 1 from pg_extension where extname = 'pg_net') then
    execute $q$select net.http_post(url := $1, body := '{}'::jsonb,
      headers := '{"Content-Type": "application/json"}'::jsonb)$q$ using url;
  end if;
  return null;
end $function$;
revoke execute on function public.wake_notification_sender() from public, anon, authenticated;

do $$ begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.unschedule(jobid) from cron.job where jobname = 'send-notifications';
    perform cron.schedule('send-notifications', '*/5 * * * *', $q$
      select net.http_post(
        url := public.notification_sender_url(),
        body := '{}'::jsonb,
        headers := '{"Content-Type": "application/json"}'::jsonb)
      where public.notification_sender_url() is not null
        and exists (select 1 from public.notification_outbox where sent_at is null)$q$);
  end if;
end $$;
