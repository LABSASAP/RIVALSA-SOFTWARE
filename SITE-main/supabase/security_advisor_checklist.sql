/*
  ZooSmart Supabase Security Advisor checklist

  Run each section in Supabase SQL Editor after applying the Sprint 2 migrations.
  This file is intentionally operational documentation: keep sections separate so
  you can inspect each result before moving to the next step.
*/

-- 1. Apply ZooSmart application table hardening.
-- Paste and run the content of:
-- supabase/migrations/20260527200000_security_rls_grants.sql

-- 2. Verify ZooSmart application tables without RLS.
-- Expected result: zero rows.
select
  n.nspname as schema_name,
  c.relname as table_name,
  c.relrowsecurity as rls_enabled
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public'
  and c.relkind in ('r', 'p')
  and c.relrowsecurity = false
  and c.relname <> 'spatial_ref_sys'
order by c.relname;

-- 3. Verify Data API grants on ZooSmart application tables.
-- Expected: no PUBLIC rows, no anon rows; authenticated only where needed;
-- service_role rows are acceptable.
select
  table_schema,
  table_name,
  grantee,
  privilege_type
from information_schema.role_table_grants
where table_schema = 'public'
  and table_name in (
    'profiles',
    'vehicles',
    'reservations',
    'rides',
    'payment_methods',
    'payments',
    'vehicle_reports',
    'urban_zones',
    'user_credit_wallets',
    'credit_transactions',
    'support_tickets',
    'support_messages',
    'ride_positions'
  )
  and grantee in ('PUBLIC', 'anon', 'authenticated', 'service_role')
order by table_name, grantee, privilege_type;

-- 4. Apply PostGIS spatial_ref_sys Data API hardening.
-- This is a best-effort revoke. If spatial_ref_sys is owned by supabase_admin
-- and current_user cannot assume supabase_admin, residual privileges may remain
-- outside application migration control.
-- Paste and run the content of:
-- supabase/migrations/20260527201000_postgis_spatial_ref_sys_api_revoke.sql

-- 5. Verify residual grants on spatial_ref_sys.
-- Expected: no PUBLIC rows, no anon rows, no authenticated rows;
-- service_role rows are acceptable.
select
  table_schema,
  table_name,
  grantee,
  privilege_type
from information_schema.role_table_grants
where table_schema = 'public'
  and table_name = 'spatial_ref_sys'
  and grantee in ('PUBLIC', 'anon', 'authenticated', 'service_role')
order by grantee, privilege_type;

-- 6. If anon/authenticated still have privileges, inspect owner and current role.
select
  n.nspname as schema_name,
  c.relname as table_name,
  pg_get_userbyid(c.relowner) as table_owner,
  c.relrowsecurity as rls_enabled
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public'
  and c.relname = 'spatial_ref_sys';

select
  current_user,
  session_user,
  pg_has_role(current_user, 'supabase_admin', 'member') as can_set_supabase_admin,
  pg_has_role(current_user, 'supabase_admin', 'usage') as can_use_supabase_admin;

-- 7. Inspect grantor and effective role membership.
select
  grantor.rolname as grantor,
  grantee.rolname as grantee,
  acl.privilege_type::text as privilege_type,
  acl.is_grantable
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
join aclexplode(coalesce(c.relacl, acldefault('r', c.relowner))) acl on true
join pg_roles grantor on grantor.oid = acl.grantor
join pg_roles grantee on grantee.oid = acl.grantee
where n.nspname = 'public'
  and c.relname = 'spatial_ref_sys'
order by grantee.rolname, acl.privilege_type::text;

select
  member_role.rolname as member,
  parent_role.rolname as inherited_from
from pg_auth_members m
join pg_roles member_role on member_role.oid = m.member
join pg_roles parent_role on parent_role.oid = m.roleid
where member_role.rolname in ('anon', 'authenticated', 'service_role')
   or parent_role.rolname in ('anon', 'authenticated', 'service_role')
order by member, inherited_from;

-- 8. Only if can_set_supabase_admin is true, run these statements in one session.
-- Do not run ALTER TABLE public.spatial_ref_sys ENABLE ROW LEVEL SECURITY.
-- If can_set_supabase_admin is false, stop here for spatial_ref_sys and handle
-- it as a separate Supabase/PostGIS extension-schema task or support request.
-- begin;
-- set local role supabase_admin;
-- revoke all privileges on table public.spatial_ref_sys from public;
-- revoke all privileges on table public.spatial_ref_sys from anon;
-- revoke all privileges on table public.spatial_ref_sys from authenticated;
-- commit;

-- 9. Verify effective table privileges.
-- Expected: anon/authenticated all false; service_role may remain true.
select
  role_name,
  has_table_privilege(role_name, 'public.spatial_ref_sys', 'SELECT') as can_select,
  has_table_privilege(role_name, 'public.spatial_ref_sys', 'INSERT') as can_insert,
  has_table_privilege(role_name, 'public.spatial_ref_sys', 'UPDATE') as can_update,
  has_table_privilege(role_name, 'public.spatial_ref_sys', 'DELETE') as can_delete
from (values ('anon'), ('authenticated'), ('service_role')) as roles(role_name);

-- 10. Verify all public tables still reported without RLS.
-- Expected for ZooSmart closure: zero application rows. If only spatial_ref_sys
-- remains and can_set_supabase_admin is false, ZooSmart tables are secure and
-- the remaining item is a Supabase/PostGIS extension-schema issue.
select
  n.nspname as schema_name,
  c.relname as table_name,
  c.relrowsecurity as rls_enabled
from pg_class c
join pg_namespace n on n.oid = c.relnamespace
where n.nspname = 'public'
  and c.relkind in ('r', 'p')
  and c.relrowsecurity = false
order by c.relname;

-- 11. Verify exposed public RPC grants.
select
  n.nspname as schema_name,
  p.proname as function_name,
  pg_get_function_identity_arguments(p.oid) as args,
  r.rolname as grantee,
  p.proacl
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
left join aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a on true
left join pg_roles r on r.oid = a.grantee
where n.nspname = 'public'
  and r.rolname in ('anon', 'authenticated', 'service_role')
order by p.proname, args, grantee;
