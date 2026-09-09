alter table public.application_forms
  add column if not exists workplace_slip_name text,
  add column if not exists workplace_slip_mime_type text,
  add column if not exists workplace_slip_storage_bucket text,
  add column if not exists workplace_slip_storage_path text,
  add column if not exists workplace_slip_url text,
  add column if not exists workplace_slip_uploaded_at timestamptz;
