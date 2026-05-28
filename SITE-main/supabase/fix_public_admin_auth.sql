/*
  ZooSmart public admin Auth repair.

  Run in Supabase SQL Editor if admin.comune@zoosmart.local exists in profiles
  but Supabase Auth login returns invalid credentials.
*/

begin;

create extension if not exists pgcrypto;

do $$
declare
  v_user_id uuid;
  v_email text := 'admin.comune@zoosmart.local';
  v_password text := 'Password123!';
begin
  select id
  into v_user_id
  from auth.users
  where lower(email) = v_email
  order by created_at asc
  limit 1;

  if v_user_id is null then
    v_user_id := '10000000-0000-4000-8000-000000000003'::uuid;

    insert into auth.users (
      instance_id,
      id,
      aud,
      role,
      email,
      encrypted_password,
      email_confirmed_at,
      confirmation_sent_at,
      raw_app_meta_data,
      raw_user_meta_data,
      is_super_admin,
      created_at,
      updated_at
    )
    values (
      '00000000-0000-0000-0000-000000000000',
      v_user_id,
      'authenticated',
      'authenticated',
      v_email,
      crypt(v_password, gen_salt('bf')),
      now(),
      now(),
      jsonb_build_object('provider', 'email', 'providers', array['email'], 'zoosmart_role', 'public_admin'),
      jsonb_build_object('display_name', 'ZooSmart Comune Test', 'role', 'public_admin', 'status', 'active'),
      false,
      now(),
      now()
    );
  else
    update auth.users
    set aud = 'authenticated',
        role = 'authenticated',
        email = v_email,
        encrypted_password = crypt(v_password, gen_salt('bf')),
        email_confirmed_at = coalesce(email_confirmed_at, now()),
        confirmation_sent_at = coalesce(confirmation_sent_at, now()),
        raw_app_meta_data = coalesce(raw_app_meta_data, '{}'::jsonb)
          || jsonb_build_object('provider', 'email', 'providers', array['email'], 'zoosmart_role', 'public_admin'),
        raw_user_meta_data = coalesce(raw_user_meta_data, '{}'::jsonb)
          || jsonb_build_object('display_name', 'ZooSmart Comune Test', 'role', 'public_admin', 'status', 'active'),
        updated_at = now()
    where id = v_user_id;
  end if;

  delete from auth.identities
  where provider = 'email'
    and (
      user_id = v_user_id
      or lower(identity_data->>'email') = v_email
    );

  insert into auth.identities (
    provider_id,
    user_id,
    identity_data,
    provider,
    last_sign_in_at,
    created_at,
    updated_at
  )
  values (
    v_user_id::text,
    v_user_id,
    jsonb_build_object(
      'sub', v_user_id::text,
      'email', v_email,
      'email_verified', true,
      'phone_verified', false,
      'display_name', 'ZooSmart Comune Test'
    ),
    'email',
    now(),
    now(),
    now()
  )
  on conflict (provider_id, provider) do update
  set user_id = excluded.user_id,
      identity_data = excluded.identity_data,
      updated_at = now();

  insert into public.profiles (
    id,
    email,
    display_name,
    role,
    status,
    created_at,
    updated_at
  )
  values (
    v_user_id,
    v_email,
    'ZooSmart Comune Test',
    'public_admin',
    'active',
    now(),
    now()
  )
  on conflict (id) do update
  set email = excluded.email,
      display_name = excluded.display_name,
      role = excluded.role,
      status = excluded.status,
      updated_at = now();
end $$;

commit;

select
  p.role,
  p.email,
  p.status,
  u.email_confirmed_at is not null as email_confirmed,
  u.encrypted_password is not null as has_password_hash,
  u.raw_user_meta_data->>'role' as jwt_user_metadata_role,
  u.raw_app_meta_data->>'zoosmart_role' as jwt_app_metadata_zoosmart_role
from public.profiles p
join auth.users u on u.id = p.id
where p.email = 'admin.comune@zoosmart.local';
