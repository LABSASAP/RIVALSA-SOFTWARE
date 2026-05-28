/*
  ZooSmart Sprint 2 public administration reports.

  Incremental migration after 20260527120000_sprint2.sql. It keeps the
  public_admin role model and adds report RPCs plus controlled urban zone
  write RPCs for AP.01-AP.06.
*/

DROP FUNCTION IF EXISTS public_admin_vehicle_usage_frequency(timestamptz, timestamptz);
CREATE OR REPLACE FUNCTION public_admin_vehicle_usage_frequency(p_from timestamptz DEFAULT NULL, p_to timestamptz DEFAULT NULL)
RETURNS TABLE (
  vehicle_type text,
  category text,
  rides_count integer,
  percentage numeric
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
  WITH expected(vehicle_type, category) AS (
    VALUES
      ('bike', 'bike'),
      ('scooter', 'scooter'),
      ('car', 'economy_car'),
      ('car', 'standard_car'),
      ('car', 'premium_car')
  ),
  filtered AS (
    SELECT v.vehicle_type, v.category
    FROM rides r
    JOIN vehicles v ON v.id = r.vehicle_id
    WHERE (p_from IS NULL OR r.started_at >= p_from)
      AND (p_to IS NULL OR r.started_at <= p_to)
  ),
  counted AS (
    SELECT f.vehicle_type, f.category, COUNT(*)::integer AS rides_count
    FROM filtered f
    GROUP BY f.vehicle_type, f.category
  ),
  totals AS (
    SELECT COUNT(*)::numeric AS total_count FROM filtered
  )
  SELECT
    e.vehicle_type,
    e.category,
    COALESCE(c.rides_count, 0)::integer,
    CASE
      WHEN t.total_count > 0 THEN ROUND((COALESCE(c.rides_count, 0)::numeric * 100.0 / t.total_count), 1)
      ELSE 0
    END AS percentage
  FROM expected e
  CROSS JOIN totals t
  LEFT JOIN counted c ON c.vehicle_type = e.vehicle_type AND c.category = e.category
  ORDER BY e.vehicle_type, e.category;
END;
$$;

DROP FUNCTION IF EXISTS public_admin_mobility_report();
DROP FUNCTION IF EXISTS public_admin_mobility_report(timestamptz, timestamptz);
CREATE OR REPLACE FUNCTION public_admin_mobility_report(p_from timestamptz DEFAULT NULL, p_to timestamptz DEFAULT NULL)
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

  WITH filtered AS (
    SELECT
      r.*,
      v.vehicle_type,
      v.category
    FROM rides r
    JOIN vehicles v ON v.id = r.vehicle_id
    WHERE (p_from IS NULL OR r.started_at >= p_from)
      AND (p_to IS NULL OR r.started_at <= p_to)
  ),
  completed AS (
    SELECT * FROM filtered WHERE status = 'completed'
  ),
  total AS (
    SELECT COUNT(*)::numeric AS total_count FROM filtered
  )
  SELECT json_build_object(
    'period', json_build_object('from', p_from, 'to', p_to),
    'rides_total', (SELECT COUNT(*) FROM filtered),
    'rides_active', (SELECT COUNT(*) FROM filtered WHERE status = 'active'),
    'rides_completed', (SELECT COUNT(*) FROM completed),
    'revenue_total', COALESCE((SELECT ROUND(SUM(final_cost)::numeric, 2) FROM completed), 0),
    'avg_duration_minutes', COALESCE((SELECT ROUND(AVG(duration_minutes)::numeric, 1) FROM completed WHERE duration_minutes IS NOT NULL), 0),
    'avg_distance_km', COALESCE((
      SELECT ROUND(AVG(ST_Distance(start_location, end_location) / 1000.0)::numeric, 2)
      FROM completed
      WHERE end_location IS NOT NULL
    ), 0),
    'avg_cost', COALESCE((SELECT ROUND(AVG(final_cost)::numeric, 2) FROM completed WHERE final_cost IS NOT NULL), 0),
    'active_users', (SELECT COUNT(DISTINCT user_id) FROM filtered),
    'vehicles_used', (SELECT COUNT(DISTINCT vehicle_id) FROM filtered),
    'hourly_usage', (
      SELECT COALESCE(json_agg(row_to_json(h)), '[]'::json)
      FROM (
        SELECT
          LPAD(EXTRACT(HOUR FROM started_at)::integer::text, 2, '0') || ':00' AS hour,
          COUNT(*)::integer AS ride_count
        FROM filtered
        GROUP BY 1
        ORDER BY 1
      ) h
    ),
    'category_usage', (
      SELECT COALESCE(json_agg(row_to_json(c)), '[]'::json)
      FROM (
        SELECT
          vehicle_type,
          category,
          COUNT(*)::integer AS ride_count,
          CASE
            WHEN (SELECT total_count FROM total) > 0
              THEN ROUND((COUNT(*)::numeric * 100.0 / (SELECT total_count FROM total)), 1)
            ELSE 0
          END AS percentage
        FROM filtered
        GROUP BY vehicle_type, category
        ORDER BY ride_count DESC, category
      ) c
    ),
    'daily_rides', (
      SELECT COALESCE(json_agg(row_to_json(d)), '[]'::json)
      FROM (
        SELECT
          to_char(date_trunc('day', started_at)::date, 'YYYY-MM-DD') AS day,
          COUNT(*)::integer AS ride_count
        FROM filtered
        GROUP BY 1
        ORDER BY 1
      ) d
    )
  ) INTO v_report;

  RETURN v_report;
END;
$$;

DROP FUNCTION IF EXISTS public_admin_fleet_status();
CREATE OR REPLACE FUNCTION public_admin_fleet_status()
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

  WITH fleet AS (
    SELECT * FROM vehicles
  ),
  totals AS (
    SELECT GREATEST(COUNT(*), 1)::numeric AS denominator FROM fleet
  )
  SELECT json_build_object(
    'fleet_total', (SELECT COUNT(*) FROM fleet),
    'available_count', (SELECT COUNT(*) FROM fleet WHERE status = 'available' AND is_remote_locked IS NOT TRUE),
    'in_use_count', (SELECT COUNT(*) FROM fleet WHERE status = 'in_use'),
    'reserved_count', (SELECT COUNT(*) FROM fleet WHERE status = 'reserved'),
    'maintenance_count', (SELECT COUNT(*) FROM fleet WHERE status = 'maintenance' OR is_remote_locked IS TRUE),
    'remote_locked_count', (SELECT COUNT(*) FROM fleet WHERE is_remote_locked IS TRUE),
    'avg_battery_level', COALESCE((SELECT ROUND(AVG(battery_level)::numeric, 1) FROM fleet), 0),
    'low_battery_percentage', COALESCE((
      SELECT ROUND((COUNT(*) FILTER (WHERE battery_level < 25)::numeric * 100.0 / t.denominator), 1)
      FROM fleet CROSS JOIN totals t
      GROUP BY t.denominator
    ), 0),
    'operational_percentage', COALESCE((
      SELECT ROUND((COUNT(*) FILTER (
        WHERE status IN ('available', 'reserved', 'in_use') AND is_remote_locked IS NOT TRUE
      )::numeric * 100.0 / t.denominator), 1)
      FROM fleet CROSS JOIN totals t
      GROUP BY t.denominator
    ), 0),
    'open_reports_count', (
      SELECT COUNT(*) FROM vehicle_reports WHERE status IN ('open', 'in_progress')
    ),
    'fleet_by_status', (
      SELECT COALESCE(json_agg(row_to_json(s)), '[]'::json)
      FROM (
        SELECT
          CASE WHEN is_remote_locked IS TRUE THEN 'remote_locked' ELSE status END AS status,
          COUNT(*)::integer AS count
        FROM fleet
        GROUP BY 1
        ORDER BY 1
      ) s
    ),
    'battery_by_category', (
      SELECT COALESCE(json_agg(row_to_json(b)), '[]'::json)
      FROM (
        SELECT
          category,
          ROUND(AVG(battery_level)::numeric, 1) AS avg_battery_level,
          COUNT(*)::integer AS vehicle_count
        FROM fleet
        GROUP BY category
        ORDER BY category
      ) b
    )
  ) INTO v_report;

  RETURN v_report;
END;
$$;

DROP FUNCTION IF EXISTS public_admin_top_routes();
DROP FUNCTION IF EXISTS public_admin_top_routes(timestamptz, timestamptz);
CREATE OR REPLACE FUNCTION public_admin_top_routes(p_from timestamptz DEFAULT NULL, p_to timestamptz DEFAULT NULL)
RETURNS TABLE (
  route_label text,
  ride_count integer,
  start_lat double precision,
  start_lng double precision,
  end_lat double precision,
  end_lng double precision,
  dominant_category text,
  avg_duration_minutes numeric,
  avg_cost numeric,
  avg_distance_km numeric
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
  WITH filtered AS (
    SELECT
      r.id,
      r.duration_minutes,
      r.final_cost,
      r.start_location,
      r.end_location,
      v.category,
      ROUND(ST_Y(r.start_location::geometry)::numeric, 3) AS start_lat_bucket,
      ROUND(ST_X(r.start_location::geometry)::numeric, 3) AS start_lng_bucket,
      ROUND(ST_Y(r.end_location::geometry)::numeric, 3) AS end_lat_bucket,
      ROUND(ST_X(r.end_location::geometry)::numeric, 3) AS end_lng_bucket
    FROM rides r
    JOIN vehicles v ON v.id = r.vehicle_id
    WHERE r.status = 'completed'
      AND r.end_location IS NOT NULL
      AND (p_from IS NULL OR r.started_at >= p_from)
      AND (p_to IS NULL OR r.started_at <= p_to)
  ),
  grouped AS (
    SELECT
      f.start_lat_bucket,
      f.start_lng_bucket,
      f.end_lat_bucket,
      f.end_lng_bucket,
      COUNT(*)::integer AS ride_count,
      ROUND(AVG(ST_Y(f.start_location::geometry))::numeric, 6)::double precision AS start_lat,
      ROUND(AVG(ST_X(f.start_location::geometry))::numeric, 6)::double precision AS start_lng,
      ROUND(AVG(ST_Y(f.end_location::geometry))::numeric, 6)::double precision AS end_lat,
      ROUND(AVG(ST_X(f.end_location::geometry))::numeric, 6)::double precision AS end_lng,
      ROUND(AVG(f.duration_minutes)::numeric, 1) AS avg_duration_minutes,
      ROUND(AVG(f.final_cost)::numeric, 2) AS avg_cost,
      ROUND(AVG(ST_Distance(f.start_location, f.end_location) / 1000.0)::numeric, 2) AS avg_distance_km
    FROM filtered f
    GROUP BY f.start_lat_bucket, f.start_lng_bucket, f.end_lat_bucket, f.end_lng_bucket
  )
  SELECT
    concat(g.start_lat_bucket, ',', g.start_lng_bucket, ' -> ', g.end_lat_bucket, ',', g.end_lng_bucket) AS route_label,
    g.ride_count,
    g.start_lat,
    g.start_lng,
    g.end_lat,
    g.end_lng,
    (
      SELECT f.category
      FROM filtered f
      WHERE f.start_lat_bucket = g.start_lat_bucket
        AND f.start_lng_bucket = g.start_lng_bucket
        AND f.end_lat_bucket = g.end_lat_bucket
        AND f.end_lng_bucket = g.end_lng_bucket
      GROUP BY f.category
      ORDER BY COUNT(*) DESC, f.category
      LIMIT 1
    ) AS dominant_category,
    g.avg_duration_minutes,
    g.avg_cost,
    g.avg_distance_km
  FROM grouped g
  ORDER BY g.ride_count DESC, g.avg_distance_km DESC
  LIMIT 15;
END;
$$;

DROP FUNCTION IF EXISTS public_admin_urban_zone_save(text, text, text, text, double precision, double precision, integer, timestamptz, timestamptz, uuid);
CREATE OR REPLACE FUNCTION public_admin_urban_zone_save(
  p_name text,
  p_description text,
  p_type text,
  p_status text,
  p_center_lat double precision,
  p_center_lng double precision,
  p_radius_meters integer,
  p_starts_at timestamptz DEFAULT NULL,
  p_ends_at timestamptz DEFAULT NULL,
  p_zone_id uuid DEFAULT NULL
)
RETURNS urban_zones
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_zone urban_zones;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'not authenticated';
  END IF;
  IF NOT is_public_admin() THEN
    RAISE EXCEPTION 'forbidden';
  END IF;
  IF NULLIF(trim(COALESCE(p_name, '')), '') IS NULL THEN
    RAISE EXCEPTION 'zone name is required';
  END IF;
  IF p_type NOT IN ('road_work', 'restricted_area', 'sensitive_zone') THEN
    RAISE EXCEPTION 'invalid zone type';
  END IF;
  IF p_status NOT IN ('active', 'inactive') THEN
    RAISE EXCEPTION 'invalid zone status';
  END IF;
  IF p_center_lat IS NULL OR p_center_lat < -90 OR p_center_lat > 90 THEN
    RAISE EXCEPTION 'invalid latitude';
  END IF;
  IF p_center_lng IS NULL OR p_center_lng < -180 OR p_center_lng > 180 THEN
    RAISE EXCEPTION 'invalid longitude';
  END IF;
  IF p_radius_meters IS NULL OR p_radius_meters <= 0 THEN
    RAISE EXCEPTION 'invalid radius';
  END IF;
  IF p_starts_at IS NOT NULL AND p_ends_at IS NOT NULL AND p_ends_at < p_starts_at THEN
    RAISE EXCEPTION 'end date must be after start date';
  END IF;

  IF p_zone_id IS NULL THEN
    INSERT INTO urban_zones (
      name,
      description,
      type,
      status,
      center_lat,
      center_lng,
      radius_meters,
      starts_at,
      ends_at,
      created_by_user_id
    )
    VALUES (
      trim(p_name),
      trim(COALESCE(p_description, '')),
      p_type,
      p_status,
      p_center_lat,
      p_center_lng,
      p_radius_meters,
      p_starts_at,
      p_ends_at,
      auth.uid()
    )
    RETURNING * INTO v_zone;
  ELSE
    UPDATE urban_zones
    SET name = trim(p_name),
        description = trim(COALESCE(p_description, '')),
        type = p_type,
        status = p_status,
        center_lat = p_center_lat,
        center_lng = p_center_lng,
        radius_meters = p_radius_meters,
        starts_at = p_starts_at,
        ends_at = p_ends_at,
        updated_at = now()
    WHERE id = p_zone_id
    RETURNING * INTO v_zone;

    IF v_zone.id IS NULL THEN
      RAISE EXCEPTION 'zone not found';
    END IF;
  END IF;

  RETURN v_zone;
END;
$$;

DROP FUNCTION IF EXISTS public_admin_urban_zone_set_status(uuid, text);
CREATE OR REPLACE FUNCTION public_admin_urban_zone_set_status(p_zone_id uuid, p_status text)
RETURNS urban_zones
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_zone urban_zones;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'not authenticated';
  END IF;
  IF NOT is_public_admin() THEN
    RAISE EXCEPTION 'forbidden';
  END IF;
  IF p_status NOT IN ('active', 'inactive') THEN
    RAISE EXCEPTION 'invalid zone status';
  END IF;

  UPDATE urban_zones
  SET status = p_status,
      updated_at = now()
  WHERE id = p_zone_id
  RETURNING * INTO v_zone;

  IF v_zone.id IS NULL THEN
    RAISE EXCEPTION 'zone not found';
  END IF;

  RETURN v_zone;
END;
$$;
