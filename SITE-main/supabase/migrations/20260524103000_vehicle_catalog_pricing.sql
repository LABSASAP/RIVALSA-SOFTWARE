/*
  # Vehicle Catalog and Pricing

  Adds persistent catalog and pricing fields to vehicles, updates nearby vehicle
  RPC output, and calculates ride final cost from per-vehicle pricing.
*/

ALTER TABLE vehicles
  ADD COLUMN IF NOT EXISTS brand text,
  ADD COLUMN IF NOT EXISTS model text,
  ADD COLUMN IF NOT EXISTS display_name text,
  ADD COLUMN IF NOT EXISTS vehicle_type text,
  ADD COLUMN IF NOT EXISTS category text,
  ADD COLUMN IF NOT EXISTS unlock_fee numeric(10,2),
  ADD COLUMN IF NOT EXISTS price_per_minute numeric(10,2),
  ADD COLUMN IF NOT EXISTS hourly_rate numeric(10,2),
  ADD COLUMN IF NOT EXISTS range_km integer,
  ADD COLUMN IF NOT EXISTS icon_type text;

UPDATE vehicles
SET
  brand = COALESCE(NULLIF(trim(brand), ''), 'ZooSmart'),
  model = COALESCE(NULLIF(trim(model), ''), 'Shared Vehicle'),
  display_name = COALESCE(
    NULLIF(trim(display_name), ''),
    code || ' ' ||
      CASE type
        WHEN 'bike' THEN 'E-Bike'
        WHEN 'scooter' THEN 'E-Scooter'
        ELSE 'Electric Car'
      END
  ),
  vehicle_type = CASE WHEN type IN ('bike', 'scooter', 'car') THEN type ELSE 'bike' END,
  category = CASE
    WHEN type = 'bike' THEN 'bike'
    WHEN type = 'scooter' THEN 'scooter'
    WHEN category IN ('economy', 'standard', 'premium') THEN category
    ELSE 'standard'
  END,
  unlock_fee = CASE
    WHEN unlock_fee IS NOT NULL THEN unlock_fee
    WHEN type = 'bike' THEN 0.50
    WHEN type = 'scooter' THEN 1.00
    ELSE 3.00
  END,
  price_per_minute = CASE
    WHEN price_per_minute IS NOT NULL THEN price_per_minute
    WHEN type = 'bike' THEN 0.12
    WHEN type = 'scooter' THEN 0.22
    ELSE 0.45
  END,
  hourly_rate = CASE
    WHEN hourly_rate IS NOT NULL THEN hourly_rate
    WHEN type = 'bike' THEN 6.00
    WHEN type = 'scooter' THEN 10.00
    ELSE 26.00
  END,
  range_km = COALESCE(
    range_km,
    CASE type
      WHEN 'bike' THEN 90
      WHEN 'scooter' THEN 45
      ELSE 260
    END
  ),
  icon_type = COALESCE(NULLIF(trim(icon_type), ''), type),
  updated_at = now();

ALTER TABLE vehicles
  ALTER COLUMN brand SET DEFAULT 'ZooSmart',
  ALTER COLUMN brand SET NOT NULL,
  ALTER COLUMN model SET DEFAULT 'Shared Vehicle',
  ALTER COLUMN model SET NOT NULL,
  ALTER COLUMN display_name SET DEFAULT 'ZooSmart Vehicle',
  ALTER COLUMN display_name SET NOT NULL,
  ALTER COLUMN vehicle_type SET DEFAULT 'bike',
  ALTER COLUMN vehicle_type SET NOT NULL,
  ALTER COLUMN category SET DEFAULT 'standard',
  ALTER COLUMN category SET NOT NULL,
  ALTER COLUMN unlock_fee SET DEFAULT 1.00,
  ALTER COLUMN unlock_fee SET NOT NULL,
  ALTER COLUMN price_per_minute SET DEFAULT 0.25,
  ALTER COLUMN price_per_minute SET NOT NULL,
  ALTER COLUMN hourly_rate SET DEFAULT 15.00,
  ALTER COLUMN hourly_rate SET NOT NULL,
  ALTER COLUMN icon_type SET DEFAULT 'vehicle',
  ALTER COLUMN icon_type SET NOT NULL;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'vehicles_vehicle_type_catalog_check'
  ) THEN
    ALTER TABLE vehicles
      ADD CONSTRAINT vehicles_vehicle_type_catalog_check
      CHECK (vehicle_type IN ('bike', 'scooter', 'car'));
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'vehicles_category_catalog_check'
  ) THEN
    ALTER TABLE vehicles
      ADD CONSTRAINT vehicles_category_catalog_check
      CHECK (category IN ('bike', 'scooter', 'economy', 'standard', 'premium'));
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'vehicles_pricing_nonnegative_check'
  ) THEN
    ALTER TABLE vehicles
      ADD CONSTRAINT vehicles_pricing_nonnegative_check
      CHECK (unlock_fee >= 0 AND price_per_minute >= 0 AND hourly_rate >= 0);
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'vehicles_range_km_nonnegative_check'
  ) THEN
    ALTER TABLE vehicles
      ADD CONSTRAINT vehicles_range_km_nonnegative_check
      CHECK (range_km IS NULL OR range_km >= 0);
  END IF;
END $$;

DROP FUNCTION IF EXISTS vehicles_nearby(double precision, double precision, integer);
CREATE FUNCTION vehicles_nearby(p_lat double precision, p_lng double precision, p_radius integer)
RETURNS TABLE (
  id uuid,
  code text,
  type text,
  vehicle_type text,
  category text,
  brand text,
  model text,
  display_name text,
  status text,
  battery_level integer,
  unlock_fee numeric,
  price_per_minute numeric,
  hourly_rate numeric,
  range_km integer,
  icon_type text,
  lat double precision,
  lng double precision,
  distance_m double precision
)
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    v.id,
    v.code,
    v.type,
    v.vehicle_type,
    v.category,
    v.brand,
    v.model,
    v.display_name,
    v.status,
    v.battery_level,
    v.unlock_fee,
    v.price_per_minute,
    v.hourly_rate,
    v.range_km,
    v.icon_type,
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
  v_vehicle vehicles;
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

  SELECT * INTO v_vehicle FROM vehicles WHERE id = v_ride.vehicle_id FOR UPDATE;
  IF v_vehicle IS NULL THEN
    RAISE EXCEPTION 'vehicle not found';
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
  v_cost := ROUND((v_vehicle.unlock_fee + v_duration * v_vehicle.price_per_minute)::numeric, 2);

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
    'unlock_fee', v_vehicle.unlock_fee,
    'price_per_minute', v_vehicle.price_per_minute,
    'vehicle_category', v_vehicle.category,
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
  vehicle_brand text,
  vehicle_model text,
  vehicle_display_name text,
  vehicle_category text,
  unlock_fee numeric,
  price_per_minute numeric,
  hourly_rate numeric,
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
    v.vehicle_type,
    v.brand,
    v.model,
    v.display_name,
    v.category,
    v.unlock_fee,
    v.price_per_minute,
    v.hourly_rate,
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
