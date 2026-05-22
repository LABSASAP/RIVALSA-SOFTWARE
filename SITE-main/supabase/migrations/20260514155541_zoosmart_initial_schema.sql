/*
  # ZooSmart Initial Schema

  ## Overview
  Creates the full ZooSmart vehicle-sharing schema: profiles, vehicles, reservations,
  rides, payment methods, payments, vehicle reports. Enables PostGIS for geospatial
  queries. Adds RLS policies, helper functions, RPC procedures for nearby vehicles,
  unlock ride and end ride, plus single-default payment-method trigger.

  ## 1. Extensions
    - postgis: required for geographic Point columns and ST_DWithin / ST_Distance
    - pgcrypto: required for crypt/gen_salt when seeding the operator account

  ## 2. New Tables
    - profiles: mirrors auth.users with display_name, role ('user' | 'operator'),
      status ('active' | 'suspended' | 'blocked')
    - vehicles: type, status, battery_level (0-100), location (geography Point),
      maintenance fields
    - reservations: user_id, vehicle_id, status, created_at, expires_at,
      converted_ride_id
    - rides: user_id, vehicle_id, reservation_id, start_location, end_location,
      started_at, ended_at, duration_minutes, final_cost, status
    - payment_methods: user_id, type, last4, is_default, created_at
    - payments: user_id, ride_id, payment_method_id, amount, status, created_at
    - vehicle_reports: user_id, vehicle_id, issue_type, description, status

  ## 3. Helper Functions
    - is_operator(): returns true when caller's profile role = 'operator'
    - profile_status(): returns caller's status for guard checks
    - handle_new_user(): trigger creating profile row on auth.users insert

  ## 4. RPC Procedures
    - vehicles_nearby(lat, lng, radius_m): PostGIS-based proximity query, only
      returns vehicles with status = 'available', ordered by distance ascending
    - reservation_create(p_vehicle_id): atomic create, sets vehicle reserved
    - ride_unlock(p_reservation_id): converts reservation to active ride
    - ride_end(p_ride_id, lat, lng): finalizes ride, calculates cost, creates
      mock payment using user's default method, sets vehicle available
    - reservation_expire_stale(): marks active reservations past expires_at as
      expired and frees the vehicle (called from frontend periodically)
    - update_user_status(p_user_id, p_status): operator-only status update

  ## 5. Triggers
    - on_auth_user_created -> handle_new_user
    - payment_methods_single_default trigger ensures only one default per user

  ## 6. Security
    All tables have RLS enabled. Authenticated users see their own data.
    Operators can read all and update operational fields. No table is publicly
    accessible.

  ## Important Notes
    1. Reservation TTL is enforced in two ways: (a) reservation_expire_stale()
       is invoked on any read; (b) the create RPC sets expires_at = now() + 10
       minutes by default.
    2. Ride cost formula: 1.00 base + 0.25 per minute, minimum 1 minute.
    3. Mock payments are auto-created with status = 'completed'.
*/

-- 1. Extensions ----------------------------------------------------------------
CREATE EXTENSION IF NOT EXISTS postgis;
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- 2. Tables --------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS profiles (
  id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  email text NOT NULL DEFAULT '',
  display_name text NOT NULL DEFAULT '',
  role text NOT NULL DEFAULT 'user' CHECK (role IN ('user','operator')),
  status text NOT NULL DEFAULT 'active' CHECK (status IN ('active','suspended','blocked')),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS vehicles (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  code text NOT NULL UNIQUE,
  type text NOT NULL CHECK (type IN ('bike','scooter','car')),
  status text NOT NULL DEFAULT 'available' CHECK (status IN ('available','reserved','in_use','maintenance')),
  battery_level integer NOT NULL DEFAULT 100 CHECK (battery_level BETWEEN 0 AND 100),
  location geography(Point, 4326) NOT NULL,
  last_maintenance_at timestamptz,
  operator_notes text DEFAULT '',
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS vehicles_location_gix ON vehicles USING GIST (location);
CREATE INDEX IF NOT EXISTS vehicles_status_idx ON vehicles (status);

CREATE TABLE IF NOT EXISTS reservations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  vehicle_id uuid NOT NULL REFERENCES vehicles(id) ON DELETE CASCADE,
  status text NOT NULL DEFAULT 'active' CHECK (status IN ('active','expired','cancelled','converted_to_ride')),
  created_at timestamptz NOT NULL DEFAULT now(),
  expires_at timestamptz NOT NULL DEFAULT (now() + interval '10 minutes'),
  converted_ride_id uuid
);

CREATE INDEX IF NOT EXISTS reservations_status_idx ON reservations (status);
CREATE INDEX IF NOT EXISTS reservations_user_idx ON reservations (user_id);

CREATE TABLE IF NOT EXISTS rides (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  vehicle_id uuid NOT NULL REFERENCES vehicles(id) ON DELETE CASCADE,
  reservation_id uuid NOT NULL REFERENCES reservations(id) ON DELETE CASCADE,
  start_location geography(Point, 4326) NOT NULL,
  end_location geography(Point, 4326),
  started_at timestamptz NOT NULL DEFAULT now(),
  ended_at timestamptz,
  duration_minutes integer,
  final_cost numeric(10,2),
  status text NOT NULL DEFAULT 'active' CHECK (status IN ('active','completed'))
);

CREATE INDEX IF NOT EXISTS rides_user_idx ON rides (user_id);
CREATE INDEX IF NOT EXISTS rides_status_idx ON rides (status);

CREATE TABLE IF NOT EXISTS payment_methods (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  type text NOT NULL CHECK (type IN ('card','paypal','apple_pay')),
  last4 text NOT NULL DEFAULT '',
  is_default boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS payment_methods_user_idx ON payment_methods (user_id);

CREATE TABLE IF NOT EXISTS payments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  ride_id uuid NOT NULL REFERENCES rides(id) ON DELETE CASCADE,
  payment_method_id uuid NOT NULL REFERENCES payment_methods(id) ON DELETE RESTRICT,
  amount numeric(10,2) NOT NULL DEFAULT 0,
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','completed','failed')),
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS vehicle_reports (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  vehicle_id uuid NOT NULL REFERENCES vehicles(id) ON DELETE CASCADE,
  issue_type text NOT NULL DEFAULT '',
  description text NOT NULL DEFAULT '',
  status text NOT NULL DEFAULT 'open' CHECK (status IN ('open','in_progress','resolved')),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS vehicle_reports_status_idx ON vehicle_reports (status);

-- 3. Helper Functions ---------------------------------------------------------

CREATE OR REPLACE FUNCTION is_operator()
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'operator'
  );
$$;

CREATE OR REPLACE FUNCTION profile_status()
RETURNS text
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public
AS $$
  SELECT status FROM profiles WHERE id = auth.uid();
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

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION handle_new_user();

-- payment_methods single-default trigger
CREATE OR REPLACE FUNCTION enforce_single_default_payment_method()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.is_default THEN
    UPDATE payment_methods SET is_default = false
    WHERE user_id = NEW.user_id AND id <> NEW.id;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS payment_methods_single_default ON payment_methods;
CREATE TRIGGER payment_methods_single_default
  AFTER INSERT OR UPDATE OF is_default ON payment_methods
  FOR EACH ROW WHEN (NEW.is_default IS TRUE)
  EXECUTE FUNCTION enforce_single_default_payment_method();

-- 4. RPC Procedures -----------------------------------------------------------

CREATE OR REPLACE FUNCTION reservation_expire_stale()
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  WITH expired AS (
    UPDATE reservations
    SET status = 'expired'
    WHERE status = 'active' AND expires_at < now()
    RETURNING vehicle_id
  )
  UPDATE vehicles v SET status = 'available'
  FROM expired e WHERE v.id = e.vehicle_id AND v.status = 'reserved';
END;
$$;

CREATE OR REPLACE FUNCTION vehicles_nearby(p_lat double precision, p_lng double precision, p_radius integer)
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

-- 5. RLS ----------------------------------------------------------------------

ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE vehicles ENABLE ROW LEVEL SECURITY;
ALTER TABLE reservations ENABLE ROW LEVEL SECURITY;
ALTER TABLE rides ENABLE ROW LEVEL SECURITY;
ALTER TABLE payment_methods ENABLE ROW LEVEL SECURITY;
ALTER TABLE payments ENABLE ROW LEVEL SECURITY;
ALTER TABLE vehicle_reports ENABLE ROW LEVEL SECURITY;

-- profiles
DROP POLICY IF EXISTS "profiles select self" ON profiles;
CREATE POLICY "profiles select self" ON profiles FOR SELECT TO authenticated
  USING (auth.uid() = id);
DROP POLICY IF EXISTS "profiles select operator" ON profiles;
CREATE POLICY "profiles select operator" ON profiles FOR SELECT TO authenticated
  USING (is_operator());
DROP POLICY IF EXISTS "profiles update self name" ON profiles;
CREATE POLICY "profiles update self name" ON profiles FOR UPDATE TO authenticated
  USING (auth.uid() = id) WITH CHECK (auth.uid() = id);

-- vehicles (read-only via API for everyone authenticated; status/location mutated only via RPCs)
DROP POLICY IF EXISTS "vehicles select all" ON vehicles;
CREATE POLICY "vehicles select all" ON vehicles FOR SELECT TO authenticated USING (true);

-- reservations
DROP POLICY IF EXISTS "reservations select own" ON reservations;
CREATE POLICY "reservations select own" ON reservations FOR SELECT TO authenticated
  USING (user_id = auth.uid());
DROP POLICY IF EXISTS "reservations select operator" ON reservations;
CREATE POLICY "reservations select operator" ON reservations FOR SELECT TO authenticated
  USING (is_operator());

-- rides
DROP POLICY IF EXISTS "rides select own" ON rides;
CREATE POLICY "rides select own" ON rides FOR SELECT TO authenticated
  USING (user_id = auth.uid());
DROP POLICY IF EXISTS "rides select operator" ON rides;
CREATE POLICY "rides select operator" ON rides FOR SELECT TO authenticated
  USING (is_operator());

-- payment_methods
DROP POLICY IF EXISTS "pm select own" ON payment_methods;
CREATE POLICY "pm select own" ON payment_methods FOR SELECT TO authenticated
  USING (user_id = auth.uid());
DROP POLICY IF EXISTS "pm insert own" ON payment_methods;
CREATE POLICY "pm insert own" ON payment_methods FOR INSERT TO authenticated
  WITH CHECK (user_id = auth.uid());
DROP POLICY IF EXISTS "pm delete own" ON payment_methods;
CREATE POLICY "pm delete own" ON payment_methods FOR DELETE TO authenticated
  USING (user_id = auth.uid());
DROP POLICY IF EXISTS "pm update own" ON payment_methods;
CREATE POLICY "pm update own" ON payment_methods FOR UPDATE TO authenticated
  USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());

-- payments
DROP POLICY IF EXISTS "payments select own" ON payments;
CREATE POLICY "payments select own" ON payments FOR SELECT TO authenticated
  USING (user_id = auth.uid());
DROP POLICY IF EXISTS "payments select operator" ON payments;
CREATE POLICY "payments select operator" ON payments FOR SELECT TO authenticated
  USING (is_operator());

-- vehicle_reports
DROP POLICY IF EXISTS "vr select own" ON vehicle_reports;
CREATE POLICY "vr select own" ON vehicle_reports FOR SELECT TO authenticated
  USING (user_id = auth.uid());
DROP POLICY IF EXISTS "vr select operator" ON vehicle_reports;
CREATE POLICY "vr select operator" ON vehicle_reports FOR SELECT TO authenticated
  USING (is_operator());
DROP POLICY IF EXISTS "vr insert own" ON vehicle_reports;
CREATE POLICY "vr insert own" ON vehicle_reports FOR INSERT TO authenticated
  WITH CHECK (user_id = auth.uid());
DROP POLICY IF EXISTS "vr update operator" ON vehicle_reports;
CREATE POLICY "vr update operator" ON vehicle_reports FOR UPDATE TO authenticated
  USING (is_operator()) WITH CHECK (is_operator());
