/*
  Rollback for 20260527201000_postgis_spatial_ref_sys_api_revoke.sql.

  Use only if legacy API access to public.spatial_ref_sys is explicitly needed.
  ZooSmart does not require this access from PUBLIC/anon/authenticated clients.
*/

DO $$
BEGIN
  IF to_regclass('public.spatial_ref_sys') IS NULL THEN
    RAISE NOTICE 'Skipping spatial_ref_sys grant rollback because public.spatial_ref_sys is missing';
  ELSE
    GRANT ALL PRIVILEGES ON TABLE public.spatial_ref_sys TO PUBLIC, anon, authenticated;
  END IF;
END;
$$;
