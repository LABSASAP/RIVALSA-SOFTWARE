/*
  # ZooSmart Local Bootstrap

  Completes the hosted Supabase setup for local development after the initial
  schema migration has been applied.

  ## What this migration does
    - backfills `profiles` for users that already existed in `auth.users`
    - seeds a few nearby vehicles for the default map coordinates
    - adds `ride_end_details(p_ride_id uuid)` to expose stored end coordinates

  ## Notes
    - operator promotion is still an explicit manual step because the target
      email address depends on the account you create in Supabase Auth
    - the statements below are idempotent and safe to re-run
*/

-- Backfill profiles for auth users created before the trigger existed.
INSERT INTO profiles (id, email, display_name, role, status)
SELECT
  u.id,
  COALESCE(u.email, ''),
  COALESCE(u.raw_user_meta_data->>'display_name', split_part(COALESCE(u.email, ''), '@', 1)),
  COALESCE(u.raw_user_meta_data->>'role', 'user'),
  'active'
FROM auth.users u
LEFT JOIN profiles p ON p.id = u.id
WHERE p.id IS NULL;

-- Expose stored ride end coordinates to both the ride summary and operator UI.
CREATE OR REPLACE FUNCTION ride_end_details(p_ride_id uuid)
RETURNS TABLE (
  ride_id uuid,
  vehicle_id uuid,
  vehicle_code text,
  vehicle_type text,
  ended_at timestamptz,
  duration_minutes integer,
  final_cost numeric,
  end_lat double precision,
  end_lng double precision
)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller uuid := auth.uid();
BEGIN
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'not authenticated';
  END IF;

  RETURN QUERY
  SELECT
    r.id,
    v.id,
    v.code,
    v.type,
    r.ended_at,
    r.duration_minutes,
    r.final_cost,
    CASE WHEN r.end_location IS NULL THEN NULL ELSE ST_Y(r.end_location::geometry) END,
    CASE WHEN r.end_location IS NULL THEN NULL ELSE ST_X(r.end_location::geometry) END
  FROM rides r
  JOIN vehicles v ON v.id = r.vehicle_id
  WHERE r.id = p_ride_id
    AND (r.user_id = v_caller OR is_operator());
END;
$$;

-- Seed a few nearby vehicles for the default local demo area.
INSERT INTO vehicles (code, type, status, battery_level, location)
VALUES
  ('BK-001', 'bike', 'available', 92, ST_SetSRID(ST_MakePoint(16.8720, 41.1175), 4326)::geography),
  ('SC-014', 'scooter', 'available', 67, ST_SetSRID(ST_MakePoint(16.8742, 41.1189), 4326)::geography),
  ('CR-003', 'car', 'available', 81, ST_SetSRID(ST_MakePoint(16.8698, 41.1163), 4326)::geography)
ON CONFLICT (code) DO NOTHING;
