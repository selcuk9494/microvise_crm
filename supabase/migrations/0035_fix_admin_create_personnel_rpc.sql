drop function if exists public.admin_create_personnel(
  text,
  text,
  text,
  text,
  text[]
);

drop function if exists public.admin_create_personnel(
  text,
  text,
  text,
  text,
  text[],
  text[]
);

create function public.admin_create_personnel(
  p_email text,
  p_password text,
  p_full_name text,
  p_role text default 'personel',
  p_page_permissions text[] default null,
  p_action_permissions text[] default null
)
returns uuid
language plpgsql
security definer
set search_path = public, auth, extensions
as $$
declare
  v_user_id uuid := gen_random_uuid();
  v_email text := lower(trim(coalesce(p_email, '')));
  v_full_name text := trim(coalesce(p_full_name, ''));
  v_role text := coalesce(nullif(trim(p_role), ''), 'personel');
  v_page_permissions text[] := coalesce(
    p_page_permissions,
    array[
      'panel',
      'musteriler',
      'formlar',
      'is_emirleri',
      'servis',
      'raporlar',
      'urunler',
      'faturalama'
    ]::text[]
  );
  v_action_permissions text[] := coalesce(
    p_action_permissions,
    case
      when v_role = 'admin' then array['duzenleme', 'pasife_alma', 'kalici_silme']::text[]
      else array['duzenleme', 'pasife_alma']::text[]
    end
  );
begin
  if not public.is_admin() then
    raise exception 'Bu işlem için admin yetkisi gerekir.';
  end if;

  if v_email = '' or position('@' in v_email) = 0 then
    raise exception 'Geçerli bir e-posta adresi girin.';
  end if;

  if length(coalesce(p_password, '')) < 6 then
    raise exception 'Şifre en az 6 karakter olmalıdır.';
  end if;

  if v_full_name = '' then
    raise exception 'Ad soyad gereklidir.';
  end if;

  if v_role not in ('admin', 'personel') then
    raise exception 'Geçersiz rol.';
  end if;

  if exists(select 1 from auth.users where email = v_email) then
    raise exception 'Bu e-posta ile kayıtlı kullanıcı zaten var.';
  end if;

  insert into auth.users (
    instance_id,
    id,
    aud,
    role,
    email,
    encrypted_password,
    email_confirmed_at,
    raw_app_meta_data,
    raw_user_meta_data,
    created_at,
    updated_at,
    confirmation_token,
    email_change,
    email_change_token_new,
    recovery_token
  )
  values (
    '00000000-0000-0000-0000-000000000000',
    v_user_id,
    'authenticated',
    'authenticated',
    v_email,
    extensions.crypt(p_password, extensions.gen_salt('bf')),
    now(),
    jsonb_build_object('provider', 'email', 'providers', array['email']),
    jsonb_build_object('full_name', v_full_name),
    now(),
    now(),
    '',
    '',
    '',
    ''
  );

  insert into auth.identities (
    id,
    user_id,
    identity_data,
    provider,
    provider_id,
    last_sign_in_at,
    created_at,
    updated_at
  )
  values (
    gen_random_uuid(),
    v_user_id,
    jsonb_build_object(
      'sub', v_user_id::text,
      'email', v_email,
      'email_verified', true
    ),
    'email',
    v_email,
    now(),
    now(),
    now()
  );

  insert into public.users (
    id,
    full_name,
    role,
    email,
    page_permissions,
    action_permissions
  )
  values (
    v_user_id,
    v_full_name,
    v_role,
    v_email,
    v_page_permissions,
    v_action_permissions
  )
  on conflict (id) do update
    set
      full_name = excluded.full_name,
      role = excluded.role,
      email = excluded.email,
      page_permissions = excluded.page_permissions,
      action_permissions = excluded.action_permissions;

  return v_user_id;
end;
$$;

grant execute on function public.admin_create_personnel(
  text,
  text,
  text,
  text,
  text[],
  text[]
) to authenticated;
