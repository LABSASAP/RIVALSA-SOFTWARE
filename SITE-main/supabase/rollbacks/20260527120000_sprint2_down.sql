/*
  Rollback for 20260527120000_sprint2.sql.
  Run manually only when Sprint 2 schema changes must be reverted.
*/

DROP FUNCTION IF EXISTS public_admin_top_routes();
DROP FUNCTION IF EXISTS public_admin_mobility_report();
DROP FUNCTION IF EXISTS operator_ride_tracking();
DROP FUNCTION IF EXISTS zone_availability_report();
DROP FUNCTION IF EXISTS operator_fleet_snapshot();
DROP FUNCTION IF EXISTS operator_update_vehicle_maintenance(uuid, text, text);
DROP FUNCTION IF EXISTS operator_set_vehicle_remote_lock(uuid, boolean, text);
DROP FUNCTION IF EXISTS ride_position_record(uuid, double precision, double precision);
DROP FUNCTION IF EXISTS ride_resume(uuid);
DROP FUNCTION IF EXISTS ride_pause(uuid);
DROP FUNCTION IF EXISTS ride_end(uuid, double precision, double precision, boolean);
DROP FUNCTION IF EXISTS credit_redeem(integer);
DROP FUNCTION IF EXISTS credit_wallet_get();
DROP FUNCTION IF EXISTS support_ticket_close(uuid);
DO $$
BEGIN
  IF to_regclass('public.support_messages') IS NOT NULL THEN
    DROP TRIGGER IF EXISTS support_messages_touch_ticket ON support_messages;
  END IF;
END $$;
DROP FUNCTION IF EXISTS touch_support_ticket_updated_at();
DROP FUNCTION IF EXISTS is_public_admin();
DROP FUNCTION IF EXISTS is_user_role();
DROP FUNCTION IF EXISTS current_profile_role();

DROP TABLE IF EXISTS ride_positions;
DROP TABLE IF EXISTS support_messages;
DROP TABLE IF EXISTS support_tickets;
DROP TABLE IF EXISTS credit_transactions;
DROP TABLE IF EXISTS user_credit_wallets;
DROP TABLE IF EXISTS urban_zones;

DROP INDEX IF EXISTS vehicles_remote_locked_idx;

ALTER TABLE vehicles
  DROP COLUMN IF EXISTS remote_locked_by,
  DROP COLUMN IF EXISTS remote_locked_at,
  DROP COLUMN IF EXISTS remote_lock_reason,
  DROP COLUMN IF EXISTS is_remote_locked;

ALTER TABLE rides
  DROP COLUMN IF EXISTS credit_discount,
  DROP COLUMN IF EXISTS original_cost,
  DROP COLUMN IF EXISTS pause_status,
  DROP COLUMN IF EXISTS total_paused_seconds,
  DROP COLUMN IF EXISTS paused_at;

UPDATE profiles SET role = 'user' WHERE role = 'public_admin';
ALTER TABLE profiles DROP CONSTRAINT IF EXISTS profiles_role_check;
ALTER TABLE profiles
  ADD CONSTRAINT profiles_role_check
  CHECK (role IN ('user', 'operator'));

CREATE OR REPLACE FUNCTION is_operator()
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'operator'
  );
$$;

CREATE OR REPLACE FUNCTION handle_new_user()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO profiles (id, email, display_name, role, status)
  VALUES (
    NEW.id,
    COALESCE(NEW.email, ''),
    COALESCE(NEW.raw_user_meta_data->>'display_name', split_part(NEW.email, '@', 1)),
    COALESCE(NEW.raw_user_meta_data->>'role', 'user'),
    'active'
  )
  ON CONFLICT (id) DO NOTHING;
  RETURN NEW;
END;
$$;

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

CREATE OR REPLACE FUNCTION reservation_create(p_vehicle_id uuid)
RETURNS reservations
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_status text;
  v_user uuid := auth.uid();
  v_profile_status text;
  v_reservation reservations;
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'not authenticated';
  END IF;

  SELECT status INTO v_profile_status FROM profiles WHERE id = v_user;
  IF v_profile_status <> 'active' THEN
    RAISE EXCEPTION 'account % cannot reserve', v_profile_status;
  END IF;

  PERFORM reservation_expire_stale();

  SELECT status INTO v_status FROM vehicles WHERE id = p_vehicle_id FOR UPDATE;
  IF v_status IS NULL THEN
    RAISE EXCEPTION 'vehicle not found';
  END IF;
  IF v_status <> 'available' THEN
    RAISE EXCEPTION 'vehicle not available';
  END IF;

  INSERT INTO reservations (user_id, vehicle_id)
  VALUES (v_user, p_vehicle_id)
  RETURNING * INTO v_reservation;

  UPDATE vehicles SET status = 'reserved', updated_at = now() WHERE id = p_vehicle_id;

  RETURN v_reservation;
END;
$$;

CREATE OR REPLACE FUNCTION ride_unlock(p_reservation_id uuid)
RETURNS rides
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user uuid := auth.uid();
  v_profile_status text;
  v_res reservations;
  v_vehicle vehicles;
  v_ride rides;
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'not authenticated';
  END IF;

  SELECT status INTO v_profile_status FROM profiles WHERE id = v_user;
  IF v_profile_status <> 'active' THEN
    RAISE EXCEPTION 'account % cannot unlock', v_profile_status;
  END IF;

  PERFORM reservation_expire_stale();

  SELECT * INTO v_res FROM reservations WHERE id = p_reservation_id FOR UPDATE;
  IF v_res IS NULL THEN
    RAISE EXCEPTION 'reservation not found';
  END IF;
  IF v_res.user_id <> v_user THEN
    RAISE EXCEPTION 'reservation not owned';
  END IF;
  IF v_res.status <> 'active' THEN
    RAISE EXCEPTION 'reservation not active';
  END IF;

  SELECT * INTO v_vehicle FROM vehicles WHERE id = v_res.vehicle_id FOR UPDATE;
  IF v_vehicle.status <> 'reserved' THEN
    RAISE EXCEPTION 'vehicle not reserved';
  END IF;

  INSERT INTO rides (user_id, vehicle_id, reservation_id, start_location, status)
  VALUES (v_user, v_vehicle.id, v_res.id, v_vehicle.location, 'active')
  RETURNING * INTO v_ride;

  UPDATE reservations SET status = 'converted_to_ride', converted_ride_id = v_ride.id WHERE id = v_res.id;
  UPDATE vehicles SET status = 'in_use', updated_at = now() WHERE id = v_vehicle.id;

  RETURN v_ride;
END;
$$;

CREATE OR REPLACE FUNCTION update_user_status(p_user_id uuid, p_status text)
RETURNS profiles
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller uuid := auth.uid();
  v_profile profiles;
BEGIN
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'not authenticated';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM profiles WHERE id = v_caller AND role = 'operator') THEN
    RAISE EXCEPTION 'forbidden';
  END IF;
  IF p_user_id = v_caller THEN
    RAISE EXCEPTION 'cannot change own status';
  END IF;
  IF p_status NOT IN ('active','suspended','blocked') THEN
    RAISE EXCEPTION 'invalid status';
  END IF;

  UPDATE profiles SET status = p_status, updated_at = now()
  WHERE id = p_user_id RETURNING * INTO v_profile;
  RETURN v_profile;
END;
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
  IF v_vehicle.unlock_fee IS NULL OR v_vehicle.price_per_minute IS NULL THEN
    RAISE EXCEPTION 'vehicle pricing missing';
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
    'vehicle_display_name', v_vehicle.display_name,
    'vehicle_category', v_vehicle.category,
    'unlock_fee', v_vehicle.unlock_fee,
    'price_per_minute', v_vehicle.price_per_minute,
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
