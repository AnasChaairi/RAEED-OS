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
