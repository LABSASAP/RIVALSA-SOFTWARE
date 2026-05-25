/*
  Rollback for 20260524103000_vehicle_catalog_pricing.sql.
  Run manually if this Supabase SQL migration must be reverted.
*/

DROP FUNCTION IF EXISTS vehicles_nearby(double precision, double precision, integer);
CREATE FUNCTION vehicles_nearby(p_lat double precision, p_lng double precision, p_radius integer)
RETURNS TABLE (
  id uuid,
  code text,
  type text,
  status text,
  battery_level integer,
  lat double precision,
  lng double precision,
  distance_m double precision
)
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    v.id, v.code, v.type, v.status, v.battery_level,
    ST_Y(v.location::geometry) AS lat,
    ST_X(v.location::geometry) AS lng,
    ST_Distance(v.location, ST_SetSRID(ST_MakePoint(p_lng, p_lat), 4326)::geography) AS distance_m
  FROM vehicles v
  WHERE v.status = 'available'
    AND ST_DWithin(v.location, ST_SetSRID(ST_MakePoint(p_lng, p_lat), 4326)::geography, p_radius)
  ORDER BY distance_m ASC;
$$;

CREATE OR REPLACE FUNCTION ride_end(p_ride_id uuid, p_lat double precision, p_lng double precision)
RETURNS json
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user uuid := auth.uid();
  v_ride rides;
  v_duration integer;
  v_cost numeric(10,2);
  v_method payment_methods;
  v_payment payments;
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'not authenticated';
  END IF;

  SELECT * INTO v_ride FROM rides WHERE id = p_ride_id FOR UPDATE;
  IF v_ride IS NULL THEN
    RAISE EXCEPTION 'ride not found';
  END IF;
  IF v_ride.user_id <> v_user THEN
    RAISE EXCEPTION 'ride not owned';
  END IF;
  IF v_ride.status <> 'active' THEN
    RAISE EXCEPTION 'ride not active';
  END IF;

  SELECT * INTO v_method FROM payment_methods
  WHERE user_id = v_user AND is_default = true LIMIT 1;
  IF v_method IS NULL THEN
    SELECT * INTO v_method FROM payment_methods
    WHERE user_id = v_user ORDER BY created_at DESC LIMIT 1;
  END IF;
  IF v_method IS NULL THEN
    RAISE EXCEPTION 'no payment method on file';
  END IF;

  v_duration := GREATEST(1, CEIL(EXTRACT(EPOCH FROM (now() - v_ride.started_at)) / 60.0)::integer);
  v_cost := ROUND((1.00 + v_duration * 0.25)::numeric, 2);

  UPDATE rides
  SET ended_at = now(),
      end_location = ST_SetSRID(ST_MakePoint(p_lng, p_lat), 4326)::geography,
      duration_minutes = v_duration,
      final_cost = v_cost,
      status = 'completed'
  WHERE id = p_ride_id
  RETURNING * INTO v_ride;

  UPDATE vehicles
  SET status = 'available',
      location = ST_SetSRID(ST_MakePoint(p_lng, p_lat), 4326)::geography,
      updated_at = now()
  WHERE id = v_ride.vehicle_id;

  INSERT INTO payments (user_id, ride_id, payment_method_id, amount, status)
  VALUES (v_user, v_ride.id, v_method.id, v_cost, 'completed')
  RETURNING * INTO v_payment;

  RETURN json_build_object(
    'ride_id', v_ride.id,
    'duration_minutes', v_ride.duration_minutes,
    'final_cost', v_ride.final_cost,
    'end_lat', p_lat,
    'end_lng', p_lng,
    'payment_id', v_payment.id,
    'payment_status', v_payment.status,
    'payment_method_type', v_method.type,
    'payment_method_last4', v_method.last4
  );
END;
$$;

DROP FUNCTION IF EXISTS ride_end_details(uuid);
CREATE FUNCTION ride_end_details(p_ride_id uuid)
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

ALTER TABLE vehicles
  DROP CONSTRAINT IF EXISTS vehicles_vehicle_type_catalog_check,
  DROP CONSTRAINT IF EXISTS vehicles_category_catalog_check,
  DROP CONSTRAINT IF EXISTS vehicles_pricing_nonnegative_check,
  DROP CONSTRAINT IF EXISTS vehicles_range_km_nonnegative_check;

ALTER TABLE vehicles
  DROP COLUMN IF EXISTS brand,
  DROP COLUMN IF EXISTS model,
  DROP COLUMN IF EXISTS display_name,
  DROP COLUMN IF EXISTS vehicle_type,
  DROP COLUMN IF EXISTS category,
  DROP COLUMN IF EXISTS unlock_fee,
  DROP COLUMN IF EXISTS price_per_minute,
  DROP COLUMN IF EXISTS hourly_rate,
  DROP COLUMN IF EXISTS range_km,
  DROP COLUMN IF EXISTS icon_type;
