alter table public.licenses
  drop constraint if exists licenses_license_type_check;

alter table public.licenses
  add constraint licenses_license_type_check
  check (license_type in ('gmp3', 'iresto'));
