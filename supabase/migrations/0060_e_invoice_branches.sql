alter table public.e_invoice_settings
  add column if not exists seller_branch_name text,
  add column if not exists test_branch_code text,
  add column if not exists test_branch_name text,
  add column if not exists test_branch_code_2 text,
  add column if not exists test_branch_name_2 text,
  add column if not exists prod_branch_code text,
  add column if not exists prod_branch_name text,
  add column if not exists prod_branch_code_2 text,
  add column if not exists prod_branch_name_2 text;

update public.e_invoice_settings
set
  seller_branch_name = coalesce(nullif(btrim(seller_branch_name), ''), 'Merkez'),
  test_branch_code = coalesce(nullif(btrim(test_branch_code), ''), seller_branch_code, '1'),
  test_branch_name = coalesce(nullif(btrim(test_branch_name), ''), 'Merkez'),
  prod_branch_code = coalesce(nullif(btrim(prod_branch_code), ''), seller_branch_code, '1'),
  prod_branch_name = coalesce(nullif(btrim(prod_branch_name), ''), 'Merkez')
where is_active = true;
