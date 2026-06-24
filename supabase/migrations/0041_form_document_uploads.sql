alter table public.scrap_forms
  add column if not exists document_name text,
  add column if not exists document_mime_type text,
  add column if not exists document_storage_bucket text,
  add column if not exists document_storage_path text,
  add column if not exists document_url text,
  add column if not exists document_uploaded_at timestamptz;

alter table public.fault_forms
  add column if not exists document_name text,
  add column if not exists document_mime_type text,
  add column if not exists document_storage_bucket text,
  add column if not exists document_storage_path text,
  add column if not exists document_url text,
  add column if not exists document_uploaded_at timestamptz;

alter table public.transfer_forms
  add column if not exists document_name text,
  add column if not exists document_mime_type text,
  add column if not exists document_storage_bucket text,
  add column if not exists document_storage_path text,
  add column if not exists document_url text,
  add column if not exists document_uploaded_at timestamptz;
