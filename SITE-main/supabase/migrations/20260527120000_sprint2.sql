/*
  # ZooSmart Sprint 2

  Adds the public administration role, persistent Sprint 2 entities, role-scoped
  RPCs and RLS policies for credits, support, urban zones, ride pause/tracking,
  operator fleet tools and public administration reporting.
*/

CREATE EXTENSION IF NOT EXISTS postgis;
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- 1. Roles --------------------------------------------------------------------

ALTER TABLE profiles DROP CONSTRAINT IF EXISTS profiles_role_check;
ALTER TABLE profiles
  ADD CONSTRAINT profiles_role_check
  CHECK (role IN ('user', 'operator', 'public_admin'));

CREATE OR REPLACE FUNCTION current_profile_role()
RETURNS text
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public
AS $$
  SELECT role FROM profiles WHERE id = auth.uid();
$$;

CREATE OR REPLACE FUNCTION is_operator()
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'operator'
  );
$$;

CREATE OR REPLACE FUNCTION is_public_admin()
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'public_admin'
  );
$$;

CREATE OR REPLACE FUNCTION is_user_role()
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'user'
  );
$$;

CREATE OR REPLACE FUNCTION handle_new_user()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_role text := COALESCE(NEW.raw_user_meta_data->>'role', 'user');
BEGIN
  IF v_role NOT IN ('user', 'operator', 'public_admin') THEN
    v_role := 'user';
  END IF;

  INSERT INTO profiles (id, email, display_name, role, status)
  VALUES (
    NEW.id,
    COALESCE(NEW.email, ''),
    COALESCE(NEW.raw_user_meta_data->>'display_name', split_part(COALESCE(NEW.email, ''), '@', 1)),
    v_role,
    'active'
  )
  ON CONFLICT (id) DO NOTHING;
  RETURN NEW;
END;
$$;

-- 2. Persistent Sprint 2 tables ------------------------------------------------

CREATE TABLE IF NOT EXISTS urban_zones (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  description text NOT NULL DEFAULT '',
  type text NOT NULL CHECK (type IN ('road_work', 'restricted_area', 'sensitive_zone')),
  status text NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'inactive')),
  center_lat double precision NOT NULL CHECK (center_lat BETWEEN -90 AND 90),
  center_lng double precision NOT NULL CHECK (center_lng BETWEEN -180 AND 180),
  radius_meters integer NOT NULL CHECK (radius_meters > 0),
  starts_at timestamptz,
  ends_at timestamptz,
  created_by_user_id uuid REFERENCES profiles(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS urban_zones_status_idx ON urban_zones (status);
CREATE INDEX IF NOT EXISTS urban_zones_type_idx ON urban_zones (type);

CREATE TABLE IF NOT EXISTS user_credit_wallets (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL UNIQUE REFERENCES profiles(id) ON DELETE CASCADE,
  points_balance integer NOT NULL DEFAULT 0 CHECK (points_balance >= 0),
  credit_amount numeric(10,2) NOT NULL DEFAULT 0 CHECK (credit_amount >= 0),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS credit_transactions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  ride_id uuid REFERENCES rides(id) ON DELETE SET NULL,
  type text NOT NULL CHECK (type IN ('earned', 'redeemed')),
  points integer NOT NULL CHECK (points > 0),
  amount numeric(10,2) NOT NULL DEFAULT 0 CHECK (amount >= 0),
  description text NOT NULL DEFAULT '',
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS credit_transactions_user_idx ON credit_transactions (user_id, created_at DESC);

CREATE TABLE IF NOT EXISTS support_tickets (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  assigned_operator_id uuid REFERENCES profiles(id) ON DELETE SET NULL,
  subject text NOT NULL,
  status text NOT NULL DEFAULT 'open' CHECK (status IN ('open', 'in_progress', 'resolved', 'closed')),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS support_tickets_user_idx ON support_tickets (user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS support_tickets_status_idx ON support_tickets (status);

CREATE TABLE IF NOT EXISTS support_messages (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  ticket_id uuid NOT NULL REFERENCES support_tickets(id) ON DELETE CASCADE,
  sender_id uuid NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  sender_role text NOT NULL CHECK (sender_role IN ('user', 'operator')),
  message text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS support_messages_ticket_idx ON support_messages (ticket_id, created_at ASC);

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'support_tickets_subject_not_blank') THEN
    ALTER TABLE support_tickets
      ADD CONSTRAINT support_tickets_subject_not_blank CHECK (length(trim(subject)) > 0);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'support_messages_message_not_blank') THEN
    ALTER TABLE support_messages
      ADD CONSTRAINT support_messages_message_not_blank CHECK (length(trim(message)) > 0);
  END IF;
END $$;

CREATE OR REPLACE FUNCTION touch_support_ticket_updated_at()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  UPDATE support_tickets SET updated_at = now()
  WHERE id = NEW.ticket_id;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS support_messages_touch_ticket ON support_messages;
CREATE TRIGGER support_messages_touch_ticket
  AFTER INSERT ON support_messages
  FOR EACH ROW EXECUTE FUNCTION touch_support_ticket_updated_at();

CREATE TABLE IF NOT EXISTS ride_positions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  ride_id uuid NOT NULL REFERENCES rides(id) ON DELETE CASCADE,
  vehicle_id uuid NOT NULL REFERENCES vehicles(id) ON DELETE CASCADE,
  lat double precision NOT NULL CHECK (lat BETWEEN -90 AND 90),
  lng double precision NOT NULL CHECK (lng BETWEEN -180 AND 180),
  recorded_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS ride_positions_ride_idx ON ride_positions (ride_id, recorded_at DESC);
CREATE INDEX IF NOT EXISTS ride_positions_vehicle_idx ON ride_positions (vehicle_id, recorded_at DESC);

ALTER TABLE vehicles
  ADD COLUMN IF NOT EXISTS is_remote_locked boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS remote_lock_reason text,
  ADD COLUMN IF NOT EXISTS remote_locked_at timestamptz,
  ADD COLUMN IF NOT EXISTS remote_locked_by uuid REFERENCES profiles(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS vehicles_remote_locked_idx ON vehicles (is_remote_locked);

ALTER TABLE rides
  ADD COLUMN IF NOT EXISTS paused_at timestamptz,
  ADD COLUMN IF NOT EXISTS total_paused_seconds integer NOT NULL DEFAULT 0 CHECK (total_paused_seconds >= 0),
  ADD COLUMN IF NOT EXISTS pause_status text NOT NULL DEFAULT 'active' CHECK (pause_status IN ('active', 'paused')),
  ADD COLUMN IF NOT EXISTS original_cost numeric(10,2),
  ADD COLUMN IF NOT EXISTS credit_discount numeric(10,2) NOT NULL DEFAULT 0 CHECK (credit_discount >= 0);

-- 3. Updated user RPCs --------------------------------------------------------

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
  is_remote_locked boolean,
  remote_lock_reason text,
  lat double precision,
  lng double precision,
  distance_m double precision
)
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'not authenticated';
  END IF;
  IF NOT is_user_role() THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  RETURN QUERY
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
    v.is_remote_locked,
    v.remote_lock_reason,
    ST_Y(v.location::geometry) AS lat,
    ST_X(v.location::geometry) AS lng,
    ST_Distance(v.location, ST_SetSRID(ST_MakePoint(p_lng, p_lat), 4326)::geography) AS distance_m
  FROM vehicles v
  WHERE (v.status = 'available' OR v.is_remote_locked IS TRUE)
    AND ST_DWithin(v.location, ST_SetSRID(ST_MakePoint(p_lng, p_lat), 4326)::geography, p_radius)
  ORDER BY ST_Distance(v.location, ST_SetSRID(ST_MakePoint(p_lng, p_lat), 4326)::geography) ASC;
END;
$$;

CREATE OR REPLACE FUNCTION reservation_create(p_vehicle_id uuid)
RETURNS reservations
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_status text;
  v_locked boolean;
  v_user uuid := auth.uid();
  v_profile_status text;
  v_reservation reservations;
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'not authenticated';
  END IF;
  IF NOT is_user_role() THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  SELECT status INTO v_profile_status FROM profiles WHERE id = v_user;
  IF v_profile_status <> 'active' THEN
    RAISE EXCEPTION 'account % cannot reserve', v_profile_status;
  END IF;

  PERFORM reservation_expire_stale();

  SELECT status, is_remote_locked INTO v_status, v_locked
  FROM vehicles WHERE id = p_vehicle_id FOR UPDATE;
  IF v_status IS NULL THEN
    RAISE EXCEPTION 'vehicle not found';
  END IF;
  IF v_locked THEN
    RAISE EXCEPTION 'vehicle remotely locked';
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
  IF NOT is_user_role() THEN
    RAISE EXCEPTION 'forbidden';
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
  IF v_vehicle.is_remote_locked THEN
    RAISE EXCEPTION 'vehicle remotely locked';
  END IF;

  INSERT INTO rides (user_id, vehicle_id, reservation_id, start_location, status)
  VALUES (v_user, v_vehicle.id, v_res.id, v_vehicle.location, 'active')
  RETURNING * INTO v_ride;

  UPDATE reservations SET status = 'converted_to_ride', converted_ride_id = v_ride.id WHERE id = v_res.id;
  UPDATE vehicles SET status = 'in_use', updated_at = now() WHERE id = v_vehicle.id;

  RETURN v_ride;
END;
$$;

CREATE OR REPLACE FUNCTION credit_wallet_get()
RETURNS TABLE (
  id uuid,
  user_id uuid,
  points_balance integer,
  credit_amount numeric,
  created_at timestamptz,
  updated_at timestamptz
)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user uuid := auth.uid();
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'not authenticated';
  END IF;
  IF NOT is_user_role() THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  INSERT INTO user_credit_wallets (user_id)
  VALUES (v_user)
  ON CONFLICT (user_id) DO NOTHING;

  RETURN QUERY
  SELECT w.id, w.user_id, w.points_balance, w.credit_amount, w.created_at, w.updated_at
  FROM user_credit_wallets w
  WHERE w.user_id = v_user;
END;
$$;

CREATE OR REPLACE FUNCTION credit_redeem(p_points integer)
RETURNS user_credit_wallets
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user uuid := auth.uid();
  v_wallet user_credit_wallets;
  v_amount numeric(10,2);
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'not authenticated';
  END IF;
  IF NOT is_user_role() THEN
    RAISE EXCEPTION 'forbidden';
  END IF;
  IF p_points IS NULL OR p_points < 10 THEN
    RAISE EXCEPTION 'minimum redeem is 10 points';
  END IF;

  INSERT INTO user_credit_wallets (user_id)
  VALUES (v_user)
  ON CONFLICT (user_id) DO NOTHING;

  SELECT * INTO v_wallet
  FROM user_credit_wallets
  WHERE user_id = v_user
  FOR UPDATE;

  IF v_wallet.points_balance < p_points THEN
    RAISE EXCEPTION 'insufficient points';
  END IF;

  v_amount := ROUND((p_points::numeric / 10.0)::numeric, 2);

  UPDATE user_credit_wallets
  SET points_balance = points_balance - p_points,
      credit_amount = credit_amount + v_amount,
      updated_at = now()
  WHERE user_id = v_user
  RETURNING * INTO v_wallet;

  INSERT INTO credit_transactions (user_id, type, points, amount, description)
  VALUES (v_user, 'redeemed', p_points, v_amount, 'Conversione punti in credito promozionale');

  RETURN v_wallet;
END;
$$;

CREATE OR REPLACE FUNCTION ride_pause(p_ride_id uuid)
RETURNS rides
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user uuid := auth.uid();
  v_ride rides;
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'not authenticated';
  END IF;
  IF NOT is_user_role() THEN
    RAISE EXCEPTION 'forbidden';
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
  IF v_ride.pause_status = 'paused' THEN
    RETURN v_ride;
  END IF;

  UPDATE rides
  SET pause_status = 'paused', paused_at = now()
  WHERE id = p_ride_id
  RETURNING * INTO v_ride;

  RETURN v_ride;
END;
$$;

CREATE OR REPLACE FUNCTION ride_resume(p_ride_id uuid)
RETURNS rides
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user uuid := auth.uid();
  v_ride rides;
  v_pause_seconds integer;
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'not authenticated';
  END IF;
  IF NOT is_user_role() THEN
    RAISE EXCEPTION 'forbidden';
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
  IF v_ride.pause_status <> 'paused' OR v_ride.paused_at IS NULL THEN
    RETURN v_ride;
  END IF;

  v_pause_seconds := GREATEST(0, FLOOR(EXTRACT(EPOCH FROM (now() - v_ride.paused_at)))::integer);

  UPDATE rides
  SET pause_status = 'active',
      paused_at = NULL,
      total_paused_seconds = total_paused_seconds + v_pause_seconds
  WHERE id = p_ride_id
  RETURNING * INTO v_ride;

  RETURN v_ride;
END;
$$;

CREATE OR REPLACE FUNCTION ride_position_record(p_ride_id uuid, p_lat double precision, p_lng double precision)
RETURNS ride_positions
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user uuid := auth.uid();
  v_ride rides;
  v_position ride_positions;
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'not authenticated';
  END IF;
  IF NOT is_user_role() THEN
    RAISE EXCEPTION 'forbidden';
  END IF;
  IF p_lat < -90 OR p_lat > 90 OR p_lng < -180 OR p_lng > 180 THEN
    RAISE EXCEPTION 'invalid coordinates';
  END IF;

  SELECT * INTO v_ride FROM rides WHERE id = p_ride_id;
  IF v_ride IS NULL THEN
    RAISE EXCEPTION 'ride not found';
  END IF;
  IF v_ride.user_id <> v_user THEN
    RAISE EXCEPTION 'ride not owned';
  END IF;
  IF v_ride.status <> 'active' THEN
    RAISE EXCEPTION 'ride not active';
  END IF;

  INSERT INTO ride_positions (ride_id, vehicle_id, lat, lng)
  VALUES (v_ride.id, v_ride.vehicle_id, p_lat, p_lng)
  RETURNING * INTO v_position;

  UPDATE vehicles
  SET location = ST_SetSRID(ST_MakePoint(p_lng, p_lat), 4326)::geography,
      updated_at = now()
  WHERE id = v_ride.vehicle_id;

  RETURN v_position;
END;
$$;

DROP FUNCTION IF EXISTS ride_end(uuid, double precision, double precision);
DROP FUNCTION IF EXISTS ride_end(uuid, double precision, double precision, boolean);
CREATE FUNCTION ride_end(p_ride_id uuid, p_lat double precision, p_lng double precision, p_apply_credits boolean DEFAULT false)
RETURNS json
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user uuid := auth.uid();
  v_ride rides;
  v_vehicle vehicles;
  v_duration integer;
  v_billable_seconds integer;
  v_total_paused integer;
  v_original_cost numeric(10,2);
  v_discount numeric(10,2) := 0;
  v_final_cost numeric(10,2);
  v_method payment_methods;
  v_payment payments;
  v_points integer;
  v_wallet user_credit_wallets;
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'not authenticated';
  END IF;
  IF NOT is_user_role() THEN
    RAISE EXCEPTION 'forbidden';
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

  v_total_paused := v_ride.total_paused_seconds
    + CASE
        WHEN v_ride.pause_status = 'paused' AND v_ride.paused_at IS NOT NULL
          THEN GREATEST(0, FLOOR(EXTRACT(EPOCH FROM (now() - v_ride.paused_at)))::integer)
        ELSE 0
      END;
  v_billable_seconds := GREATEST(60, FLOOR(EXTRACT(EPOCH FROM (now() - v_ride.started_at)))::integer - v_total_paused);
  v_duration := GREATEST(1, CEIL(v_billable_seconds / 60.0)::integer);
  v_original_cost := ROUND((v_vehicle.unlock_fee + v_duration * v_vehicle.price_per_minute)::numeric, 2);

  INSERT INTO user_credit_wallets (user_id)
  VALUES (v_user)
  ON CONFLICT (user_id) DO NOTHING;

  IF COALESCE(p_apply_credits, false) THEN
    SELECT * INTO v_wallet
    FROM user_credit_wallets
    WHERE user_id = v_user
    FOR UPDATE;

    v_discount := LEAST(v_original_cost, COALESCE(v_wallet.credit_amount, 0));

    IF v_discount > 0 THEN
      UPDATE user_credit_wallets
      SET credit_amount = credit_amount - v_discount,
          updated_at = now()
      WHERE user_id = v_user;

      INSERT INTO credit_transactions (user_id, ride_id, type, points, amount, description)
      VALUES (v_user, v_ride.id, 'redeemed', GREATEST(1, ROUND(v_discount * 10)::integer), v_discount, 'Credito promozionale applicato alla corsa');
    END IF;
  END IF;

  v_final_cost := ROUND(GREATEST(0, v_original_cost - v_discount)::numeric, 2);

  UPDATE rides
  SET ended_at = now(),
      end_location = ST_SetSRID(ST_MakePoint(p_lng, p_lat), 4326)::geography,
      duration_minutes = v_duration,
      original_cost = v_original_cost,
      credit_discount = v_discount,
      final_cost = v_final_cost,
      status = 'completed',
      paused_at = NULL,
      pause_status = 'active',
      total_paused_seconds = v_total_paused
  WHERE id = p_ride_id
  RETURNING * INTO v_ride;

  INSERT INTO ride_positions (ride_id, vehicle_id, lat, lng, recorded_at)
  VALUES (v_ride.id, v_ride.vehicle_id, p_lat, p_lng, now());

  UPDATE vehicles
  SET status = CASE WHEN is_remote_locked THEN 'maintenance' ELSE 'available' END,
      location = ST_SetSRID(ST_MakePoint(p_lng, p_lat), 4326)::geography,
      updated_at = now()
  WHERE id = v_ride.vehicle_id;

  INSERT INTO payments (user_id, ride_id, payment_method_id, amount, status)
  VALUES (v_user, v_ride.id, v_method.id, v_final_cost, 'completed')
  RETURNING * INTO v_payment;

  v_points := FLOOR(v_final_cost)::integer;

  IF v_points > 0 THEN
    UPDATE user_credit_wallets
    SET points_balance = points_balance + v_points,
        updated_at = now()
    WHERE user_id = v_user;

    INSERT INTO credit_transactions (user_id, ride_id, type, points, amount, description)
    VALUES (v_user, v_ride.id, 'earned', v_points, 0, 'Punti maturati dalla corsa');
  END IF;

  RETURN json_build_object(
    'ride_id', v_ride.id,
    'duration_minutes', v_ride.duration_minutes,
    'final_cost', v_ride.final_cost,
    'original_cost', v_ride.original_cost,
    'credit_discount', v_ride.credit_discount,
    'vehicle_display_name', v_vehicle.display_name,
    'vehicle_category', v_vehicle.category,
    'unlock_fee', v_vehicle.unlock_fee,
    'price_per_minute', v_vehicle.price_per_minute,
    'points_earned', v_points,
    'paused_seconds', v_total_paused,
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
  original_cost numeric,
  credit_discount numeric,
  final_cost numeric,
  total_paused_seconds integer,
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
  IF NOT (is_user_role() OR is_operator()) THEN
    RAISE EXCEPTION 'forbidden';
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
    r.original_cost,
    r.credit_discount,
    r.final_cost,
    r.total_paused_seconds,
    CASE WHEN r.end_location IS NULL THEN NULL ELSE ST_Y(r.end_location::geometry) END,
    CASE WHEN r.end_location IS NULL THEN NULL ELSE ST_X(r.end_location::geometry) END
  FROM rides r
  JOIN vehicles v ON v.id = r.vehicle_id
  WHERE r.id = p_ride_id
    AND (r.user_id = v_caller OR is_operator());
END;
$$;

CREATE OR REPLACE FUNCTION support_ticket_close(p_ticket_id uuid)
RETURNS support_tickets
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user uuid := auth.uid();
  v_ticket support_tickets;
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'not authenticated';
  END IF;
  IF NOT is_user_role() THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  UPDATE support_tickets
  SET status = 'closed', updated_at = now()
  WHERE id = p_ticket_id
    AND user_id = v_user
    AND status <> 'closed'
  RETURNING * INTO v_ticket;

  IF v_ticket.id IS NULL THEN
    RAISE EXCEPTION 'ticket not found';
  END IF;

  RETURN v_ticket;
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
  IF NOT is_operator() THEN
    RAISE EXCEPTION 'forbidden';
  END IF;
  IF p_user_id = v_caller THEN
    RAISE EXCEPTION 'cannot change own status';
  END IF;
  IF p_status NOT IN ('active','suspended','blocked') THEN
    RAISE EXCEPTION 'invalid status';
  END IF;

  UPDATE profiles SET status = p_status, updated_at = now()
  WHERE id = p_user_id AND role = 'user'
  RETURNING * INTO v_profile;

  IF v_profile.id IS NULL THEN
    RAISE EXCEPTION 'target user not found';
  END IF;

  RETURN v_profile;
END;
$$;

-- 4. Operator RPCs ------------------------------------------------------------

CREATE OR REPLACE FUNCTION operator_set_vehicle_remote_lock(p_vehicle_id uuid, p_locked boolean, p_reason text DEFAULT NULL)
RETURNS vehicles
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_vehicle vehicles;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'not authenticated';
  END IF;
  IF NOT is_operator() THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  UPDATE vehicles
  SET is_remote_locked = COALESCE(p_locked, false),
      remote_lock_reason = CASE WHEN COALESCE(p_locked, false) THEN NULLIF(trim(COALESCE(p_reason, '')), '') ELSE NULL END,
      remote_locked_at = CASE WHEN COALESCE(p_locked, false) THEN now() ELSE NULL END,
      remote_locked_by = CASE WHEN COALESCE(p_locked, false) THEN auth.uid() ELSE NULL END,
      status = CASE
        WHEN COALESCE(p_locked, false) AND status = 'available' THEN 'maintenance'
        WHEN NOT COALESCE(p_locked, false) AND status = 'maintenance' THEN 'available'
        ELSE status
      END,
      updated_at = now()
  WHERE id = p_vehicle_id
  RETURNING * INTO v_vehicle;

  IF v_vehicle.id IS NULL THEN
    RAISE EXCEPTION 'vehicle not found';
  END IF;

  RETURN v_vehicle;
END;
$$;

CREATE OR REPLACE FUNCTION operator_update_vehicle_maintenance(p_vehicle_id uuid, p_status text, p_notes text DEFAULT NULL)
RETURNS vehicles
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_vehicle vehicles;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'not authenticated';
  END IF;
  IF NOT is_operator() THEN
    RAISE EXCEPTION 'forbidden';
  END IF;
  IF p_status NOT IN ('available', 'maintenance') THEN
    RAISE EXCEPTION 'invalid maintenance status';
  END IF;

  UPDATE vehicles
  SET status = CASE WHEN is_remote_locked AND p_status = 'available' THEN 'maintenance' ELSE p_status END,
      operator_notes = COALESCE(p_notes, operator_notes),
      last_maintenance_at = CASE WHEN p_status = 'maintenance' THEN now() ELSE last_maintenance_at END,
      updated_at = now()
  WHERE id = p_vehicle_id
  RETURNING * INTO v_vehicle;

  IF v_vehicle.id IS NULL THEN
    RAISE EXCEPTION 'vehicle not found';
  END IF;

  RETURN v_vehicle;
END;
$$;

CREATE OR REPLACE FUNCTION operator_fleet_snapshot()
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
  range_km integer,
  icon_type text,
  is_remote_locked boolean,
  remote_lock_reason text,
  remote_locked_at timestamptz,
  operator_notes text,
  lat double precision,
  lng double precision,
  updated_at timestamptz
)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'not authenticated';
  END IF;
  IF NOT is_operator() THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  RETURN QUERY
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
    v.range_km,
    v.icon_type,
    v.is_remote_locked,
    v.remote_lock_reason,
    v.remote_locked_at,
    v.operator_notes,
    ST_Y(v.location::geometry),
    ST_X(v.location::geometry),
    v.updated_at
  FROM vehicles v
  ORDER BY v.updated_at DESC, v.code ASC;
END;
$$;

CREATE OR REPLACE FUNCTION zone_availability_report()
RETURNS TABLE (
  zone_id uuid,
  area_name text,
  zone_type text,
  available_count integer,
  total_count integer,
  severity text
)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'not authenticated';
  END IF;
  IF NOT (is_operator() OR is_public_admin()) THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  RETURN QUERY
  SELECT
    z.id,
    z.name,
    z.type,
    COUNT(v.id) FILTER (WHERE v.status = 'available' AND v.is_remote_locked IS NOT TRUE)::integer,
    COUNT(v.id)::integer,
    CASE
      WHEN COUNT(v.id) FILTER (WHERE v.status = 'available' AND v.is_remote_locked IS NOT TRUE) = 0 THEN 'critical'
      WHEN COUNT(v.id) FILTER (WHERE v.status = 'available' AND v.is_remote_locked IS NOT TRUE) < 2 THEN 'warning'
      ELSE 'ok'
    END
  FROM urban_zones z
  LEFT JOIN vehicles v
    ON ST_DWithin(
      v.location,
      ST_SetSRID(ST_MakePoint(z.center_lng, z.center_lat), 4326)::geography,
      z.radius_meters
    )
  WHERE z.status = 'active'
  GROUP BY z.id, z.name, z.type
  ORDER BY available_count ASC, z.name ASC;
END;
$$;

CREATE OR REPLACE FUNCTION operator_ride_tracking()
RETURNS TABLE (
  ride_id uuid,
  vehicle_id uuid,
  vehicle_code text,
  user_name text,
  ride_status text,
  lat double precision,
  lng double precision,
  recorded_at timestamptz
)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'not authenticated';
  END IF;
  IF NOT is_operator() THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  RETURN QUERY
  WITH latest AS (
    SELECT DISTINCT ON (rp.ride_id)
      rp.ride_id,
      rp.vehicle_id,
      rp.lat,
      rp.lng,
      rp.recorded_at
    FROM ride_positions rp
    ORDER BY rp.ride_id, rp.recorded_at DESC
  )
  SELECT
    r.id,
    r.vehicle_id,
    v.code,
    p.display_name,
    r.status,
    COALESCE(l.lat, ST_Y(v.location::geometry)),
    COALESCE(l.lng, ST_X(v.location::geometry)),
    COALESCE(l.recorded_at, v.updated_at)
  FROM rides r
  JOIN vehicles v ON v.id = r.vehicle_id
  JOIN profiles p ON p.id = r.user_id
  LEFT JOIN latest l ON l.ride_id = r.id
  WHERE r.status = 'active'
     OR r.ended_at > now() - interval '24 hours'
  ORDER BY recorded_at DESC;
END;
$$;

-- 5. Public admin RPCs --------------------------------------------------------

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

-- 6. RLS ----------------------------------------------------------------------

ALTER TABLE urban_zones ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_credit_wallets ENABLE ROW LEVEL SECURITY;
ALTER TABLE credit_transactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE support_tickets ENABLE ROW LEVEL SECURITY;
ALTER TABLE support_messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE ride_positions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "urban zones select active" ON urban_zones;
CREATE POLICY "urban zones select active" ON urban_zones FOR SELECT TO authenticated
  USING (status = 'active' OR is_public_admin());
DROP POLICY IF EXISTS "urban zones insert admin" ON urban_zones;
CREATE POLICY "urban zones insert admin" ON urban_zones FOR INSERT TO authenticated
  WITH CHECK (is_public_admin());
DROP POLICY IF EXISTS "urban zones update admin" ON urban_zones;
CREATE POLICY "urban zones update admin" ON urban_zones FOR UPDATE TO authenticated
  USING (is_public_admin()) WITH CHECK (is_public_admin());
DROP POLICY IF EXISTS "urban zones delete admin" ON urban_zones;
CREATE POLICY "urban zones delete admin" ON urban_zones FOR DELETE TO authenticated
  USING (is_public_admin());

DROP POLICY IF EXISTS "wallet select own" ON user_credit_wallets;
CREATE POLICY "wallet select own" ON user_credit_wallets FOR SELECT TO authenticated
  USING (user_id = auth.uid());

DROP POLICY IF EXISTS "credit transactions select own" ON credit_transactions;
CREATE POLICY "credit transactions select own" ON credit_transactions FOR SELECT TO authenticated
  USING (user_id = auth.uid());

DROP POLICY IF EXISTS "support tickets select own or operator" ON support_tickets;
CREATE POLICY "support tickets select own or operator" ON support_tickets FOR SELECT TO authenticated
  USING (user_id = auth.uid() OR is_operator());
DROP POLICY IF EXISTS "support tickets insert own user" ON support_tickets;
CREATE POLICY "support tickets insert own user" ON support_tickets FOR INSERT TO authenticated
  WITH CHECK (user_id = auth.uid() AND is_user_role());
DROP POLICY IF EXISTS "support tickets update operator" ON support_tickets;
CREATE POLICY "support tickets update operator" ON support_tickets FOR UPDATE TO authenticated
  USING (is_operator()) WITH CHECK (is_operator());

DROP POLICY IF EXISTS "support messages select ticket actors" ON support_messages;
CREATE POLICY "support messages select ticket actors" ON support_messages FOR SELECT TO authenticated
  USING (
    is_operator()
    OR EXISTS (
      SELECT 1 FROM support_tickets t
      WHERE t.id = ticket_id AND t.user_id = auth.uid()
    )
  );
DROP POLICY IF EXISTS "support messages insert ticket actors" ON support_messages;
CREATE POLICY "support messages insert ticket actors" ON support_messages FOR INSERT TO authenticated
  WITH CHECK (
    sender_id = auth.uid()
    AND sender_role = current_profile_role()
    AND sender_role IN ('user', 'operator')
    AND (
      (sender_role = 'operator' AND is_operator())
      OR EXISTS (
        SELECT 1 FROM support_tickets t
        WHERE t.id = ticket_id AND t.user_id = auth.uid() AND t.status <> 'closed'
      )
    )
  );

DROP POLICY IF EXISTS "ride positions select owner or operator" ON ride_positions;
CREATE POLICY "ride positions select owner or operator" ON ride_positions FOR SELECT TO authenticated
  USING (
    is_operator()
    OR EXISTS (
      SELECT 1 FROM rides r
      WHERE r.id = ride_id AND r.user_id = auth.uid()
    )
  );
DROP POLICY IF EXISTS "ride positions insert owner" ON ride_positions;
CREATE POLICY "ride positions insert owner" ON ride_positions FOR INSERT TO authenticated
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM rides r
      WHERE r.id = ride_id AND r.user_id = auth.uid() AND r.status = 'active'
    )
  );

DROP POLICY IF EXISTS "profiles select public admin self" ON profiles;
CREATE POLICY "profiles select public admin self" ON profiles FOR SELECT TO authenticated
  USING (id = auth.uid());

-- Keep existing user/operator RLS policies in place for Sprint 1 tables.
