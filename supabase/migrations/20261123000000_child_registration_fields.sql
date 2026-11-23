-- Fields from the 2026-2027 re-registration form, kept on each child.
-- Parent names and phones are stored here too: parent logins are created separately in the app,
-- and children are linked to them through child_parents as before.

alter table public.children
  add column if not exists full_name_latin text,
  add column if not exists school_level text,
  add column if not exists residence text,
  add column if not exists returning_member boolean,
  add column if not exists has_chronic_condition boolean not null default false,
  add column if not exists medical_notes text,
  add column if not exists mother_name text,
  add column if not exists mother_phone text,
  add column if not exists father_name text,
  add column if not exists father_phone text,
  add column if not exists contact_email text,
  add column if not exists registration_notes text,
  add column if not exists registered_at timestamptz;
