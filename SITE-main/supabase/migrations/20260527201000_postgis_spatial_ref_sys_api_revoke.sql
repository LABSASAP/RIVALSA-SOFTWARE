/*
  # PostGIS spatial_ref_sys Data API hardening

  Incremental migration after 20260527200000_security_rls_grants.sql.
  ZooSmart does not read public.spatial_ref_sys from the frontend. Revoke Data
  API table privileges from PUBLIC/anon/authenticated while leaving the PostGIS
  extension and service_role access intact.

  Best effort: hosted Supabase projects may own spatial_ref_sys as
  supabase_admin. If the current role cannot assume supabase_admin, this may not
  clear owner/extension-level effective privileges. Do not force RLS on this
  extension table from application migrations.
*/

DO $$
BEGIN
  IF to_regclass('public.spatial_ref_sys') IS NULL THEN
    RAISE NOTICE 'Skipping spatial_ref_sys API revoke because public.spatial_ref_sys is missing';
  ELSE
    REVOKE ALL ON TABLE public.spatial_ref_sys FROM PUBLIC, anon, authenticated;
  END IF;
END;
$$;
