/*
  Rollback for 20260527153000_public_admin_reports.sql.
  Restores the no-argument public admin report RPCs from Sprint 2 base.
*/

DROP FUNCTION IF EXISTS public_admin_urban_zone_set_status(uuid, text);
DROP FUNCTION IF EXISTS public_admin_urban_zone_save(text, text, text, text, double precision, double precision, integer, timestamptz, timestamptz, uuid);
DROP FUNCTION IF EXISTS public_admin_vehicle_usage_frequency(timestamptz, timestamptz);
DROP FUNCTION IF EXISTS public_admin_fleet_status();
DROP FUNCTION IF EXISTS public_admin_mobility_report(timestamptz, timestamptz);
DROP FUNCTION IF EXISTS public_admin_top_routes(timestamptz, timestamptz);

CREATE OR REPLACE FUNCTION public_admin_mobility_report()
RETURNS json
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_report json;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'not authenticated';
  END IF;
  IF NOT is_public_admin() THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  SELECT json_build_object(
    'rides_total', (SELECT COUNT(*) FROM rides),
    'rides_active', (SELECT COUNT(*) FROM rides WHERE status = 'active'),
    'rides_completed', (SELECT COUNT(*) FROM rides WHERE status = 'completed'),
    'revenue_total', COALESCE((SELECT SUM(final_cost) FROM rides WHERE status = 'completed'), 0),
    'avg_duration_minutes', COALESCE((SELECT ROUND(AVG(duration_minutes)::numeric, 1) FROM rides WHERE status = 'completed'), 0),
    'fleet_total', (SELECT COUNT(*) FROM vehicles),
    'fleet_available', (SELECT COUNT(*) FROM vehicles WHERE status = 'available' AND is_remote_locked IS NOT TRUE),
    'fleet_in_use', (SELECT COUNT(*) FROM vehicles WHERE status = 'in_use'),
    'fleet_maintenance', (SELECT COUNT(*) FROM vehicles WHERE status = 'maintenance' OR is_remote_locked IS TRUE),
    'urban_zones_active', (SELECT COUNT(*) FROM urban_zones WHERE status = 'active'),
    'daily_rides', (
      SELECT COALESCE(json_agg(row_to_json(d)), '[]'::json)
      FROM (
        SELECT to_char(day, 'YYYY-MM-DD') AS day, ride_count
        FROM (
          SELECT date_trunc('day', started_at)::date AS day, COUNT(*)::integer AS ride_count
          FROM rides
          WHERE started_at >= now() - interval '14 days'
          GROUP BY 1
          ORDER BY 1
        ) s
      ) d
    ),
    'fleet_by_status', (
      SELECT COALESCE(json_agg(row_to_json(s)), '[]'::json)
      FROM (
        SELECT status, COUNT(*)::integer AS count
        FROM vehicles
        GROUP BY status
        ORDER BY status
      ) s
    ),
    'fleet_by_type', (
      SELECT COALESCE(json_agg(row_to_json(t)), '[]'::json)
      FROM (
        SELECT vehicle_type AS type, COUNT(*)::integer AS count
        FROM vehicles
        GROUP BY vehicle_type
        ORDER BY vehicle_type
      ) t
    )
  ) INTO v_report;

  RETURN v_report;
END;
$$;

CREATE OR REPLACE FUNCTION public_admin_top_routes()
RETURNS TABLE (
  route_label text,
  ride_count integer,
  start_lat double precision,
  start_lng double precision,
  end_lat double precision,
  end_lng double precision
)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'not authenticated';
  END IF;
  IF NOT is_public_admin() THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  RETURN QUERY
  SELECT
    concat(
      ROUND(ST_Y(r.start_location::geometry)::numeric, 3), ',',
      ROUND(ST_X(r.start_location::geometry)::numeric, 3),
      ' -> ',
      ROUND(ST_Y(r.end_location::geometry)::numeric, 3), ',',
      ROUND(ST_X(r.end_location::geometry)::numeric, 3)
    ) AS route_label,
    COUNT(*)::integer AS ride_count,
    ROUND(AVG(ST_Y(r.start_location::geometry))::numeric, 6)::double precision AS start_lat,
    ROUND(AVG(ST_X(r.start_location::geometry))::numeric, 6)::double precision AS start_lng,
    ROUND(AVG(ST_Y(r.end_location::geometry))::numeric, 6)::double precision AS end_lat,
    ROUND(AVG(ST_X(r.end_location::geometry))::numeric, 6)::double precision AS end_lng
  FROM rides r
  WHERE r.status = 'completed'
    AND r.end_location IS NOT NULL
  GROUP BY
    ROUND(ST_Y(r.start_location::geometry)::numeric, 3),
    ROUND(ST_X(r.start_location::geometry)::numeric, 3),
    ROUND(ST_Y(r.end_location::geometry)::numeric, 3),
    ROUND(ST_X(r.end_location::geometry)::numeric, 3)
  ORDER BY ride_count DESC
  LIMIT 10;
END;
$$;
