# RAEED OS

Internal mobile app for RAEED Academy: sessions, attendance, absence follow-up and parent schedules, in Arabic.

- Product definition and architecture: Claude Docs "RAEED OS Product Definition" and "RAEED OS Architecture".
- Stack: Flutter app (Android and iPhone) on Supabase (Postgres, sign-in, access rules, server functions), push through Firebase Cloud Messaging.

## Repository layout

| Path | What it holds |
|---|---|
| `supabase/migrations/` | Database schema, row-level security (who sees what, per role), triggers for absence alerts, offline sync and parent notifications |
| `supabase/tests/` | Access-rule tests that run on plain Postgres |
| `app/` | Flutter app: sign-in, first-sign-in password change, role switcher and each role's tabs (see `app/README.md`) |

## Testing the database locally

```sh
PGHOST=/tmp PGPORT=5432 PGUSER=postgres supabase/tests/run_local.sh
```

It creates a throwaway database, applies the migrations with small stand-ins for Supabase's `auth` schema, and checks each role's access. It prints `ALL ACCESS RULE TESTS PASSED` or stops at the first `FAIL`.

## End-to-end tests

`supabase/tests/e2e/` drives the whole backend the way the app does, as real signed-in advisor, instructor and parent accounts on a local Supabase: creating accounts through `manage-account`, first sign-in and password change, resets, roles and deletion; seasons, groups, children and parents; single sessions and weekly series, edits, cancellations and the parent notifications they queue; attendance, offline saves, absence alerts and their follow-up, notes, statistics and pilot metrics. Needs Docker and Node.

```sh
npx supabase start            # from the repository root; first run pulls the images
cd supabase/tests/e2e && npm install && npm test
npm test -- 03_sessions.test.mjs   # one file
npx supabase db reset         # back to an empty database
```

The tests refuse to run against anything but `localhost`. A local database has no `project_url` Vault secret, so it never wakes a `send-notifications` function: notifications stay in the outbox, where the tests read them.

## Push notifications on a project

The database wakes `send-notifications` at the URL in the Vault secret `project_url`. Set it once on each project that should send notifications (the hosted one, not branches or local copies):

```sql
select vault.create_secret('https://<project-ref>.supabase.co', 'project_url');
```
