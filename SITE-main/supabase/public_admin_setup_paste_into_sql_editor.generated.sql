/*
  ZooSmart public admin setup bundle.
  Generated locally for Supabase SQL Editor.
  Run after the initial/base ZooSmart migrations are already applied.
*/


-- ============================================================================
-- supabase\migrations\20260527120000_sprint2.sql
-- ============================================================================

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

CREATE OR REPLACE FUNCTION public.credit_wallet_get()
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

  INSERT INTO public.user_credit_wallets (user_id)
  VALUES (v_user)
  ON CONFLICT ON CONSTRAINT user_credit_wallets_user_id_key DO NOTHING;

  RETURN QUERY
  SELECT w.id, w.user_id, w.points_balance, w.credit_amount, w.created_at, w.updated_at
  FROM public.user_credit_wallets AS w
  WHERE w.user_id = v_user;
END;
$$;

CREATE OR REPLACE FUNCTION public.credit_redeem(p_points integer)
RETURNS public.user_credit_wallets
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user uuid := auth.uid();
  v_wallet public.user_credit_wallets;
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

  INSERT INTO public.user_credit_wallets (user_id)
  VALUES (v_user)
  ON CONFLICT ON CONSTRAINT user_credit_wallets_user_id_key DO NOTHING;

  SELECT w.* INTO v_wallet
  FROM public.user_credit_wallets AS w
  WHERE w.user_id = v_user
  FOR UPDATE;

  IF v_wallet.points_balance < p_points THEN
    RAISE EXCEPTION 'insufficient points';
  END IF;

  v_amount := ROUND((p_points::numeric / 10.0)::numeric, 2);

  UPDATE public.user_credit_wallets AS w
  SET points_balance = w.points_balance - p_points,
      credit_amount = w.credit_amount + v_amount,
      updated_at = now()
  WHERE w.user_id = v_user
  RETURNING w.id, w.user_id, w.points_balance, w.credit_amount, w.created_at, w.updated_at
  INTO v_wallet;

  INSERT INTO public.credit_transactions (user_id, type, points, amount, description)
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


-- ============================================================================
-- supabase\migrations\20260527153000_public_admin_reports.sql
-- ============================================================================

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


-- ============================================================================
-- supabase\migrations\20260527170000_operator_sprint2.sql
-- ============================================================================

/*
  ZooSmart Sprint 2 operator features.

  Incremental migration after 20260527153000_public_admin_reports.sql.
  It reuses existing Sprint 2 tables and adds operator-only RPCs for fleet
  distribution, low availability alerts, maintenance, tracking, parking bonuses
  and support ticket handling.
*/

CREATE EXTENSION IF NOT EXISTS postgis;

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

  SELECT * INTO v_vehicle FROM vehicles WHERE id = p_vehicle_id FOR UPDATE;
  IF v_vehicle.id IS NULL THEN
    RAISE EXCEPTION 'vehicle not found';
  END IF;
  IF COALESCE(p_locked, false) AND v_vehicle.status = 'in_use' THEN
    RAISE EXCEPTION 'cannot remote lock a vehicle in use';
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

  RETURN v_vehicle;
END;
$$;

CREATE OR REPLACE FUNCTION operator_fleet_distribution()
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
  last_maintenance_at timestamptz,
  lat double precision,
  lng double precision,
  updated_at timestamptz,
  open_reports_count integer,
  active_ride_id uuid
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
    v.last_maintenance_at,
    ST_Y(v.location::geometry),
    ST_X(v.location::geometry),
    v.updated_at,
    COALESCE(reports.open_reports_count, 0)::integer,
    active_ride.id
  FROM vehicles v
  LEFT JOIN LATERAL (
    SELECT COUNT(*)::integer AS open_reports_count
    FROM vehicle_reports vr
    WHERE vr.vehicle_id = v.id
      AND vr.status IN ('open', 'in_progress')
  ) reports ON true
  LEFT JOIN LATERAL (
    SELECT r.id
    FROM rides r
    WHERE r.vehicle_id = v.id
      AND r.status = 'active'
    ORDER BY r.started_at DESC
    LIMIT 1
  ) active_ride ON true
  ORDER BY v.updated_at DESC, v.code ASC;
END;
$$;

CREATE OR REPLACE FUNCTION operator_low_availability_alerts(p_threshold integer DEFAULT 3)
RETURNS TABLE (
  area_id uuid,
  area_name text,
  area_type text,
  center_lat double precision,
  center_lng double precision,
  radius_meters integer,
  available_vehicles integer,
  total_vehicles integer,
  low_battery_vehicles integer,
  maintenance_vehicles integer,
  in_use_vehicles integer,
  threshold integer,
  severity text,
  message text
)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_threshold integer := GREATEST(COALESCE(p_threshold, 3), 1);
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'not authenticated';
  END IF;
  IF NOT is_operator() THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  RETURN QUERY
  WITH zone_counts AS (
    SELECT
      z.id,
      z.name,
      z.type,
      z.center_lat,
      z.center_lng,
      z.radius_meters,
      COUNT(v.id) FILTER (WHERE v.status = 'available' AND v.is_remote_locked IS NOT TRUE)::integer AS available_count,
      COUNT(v.id)::integer AS total_count,
      COUNT(v.id) FILTER (WHERE v.battery_level < 25)::integer AS low_battery_count,
      COUNT(v.id) FILTER (WHERE v.status = 'maintenance' OR v.is_remote_locked IS TRUE)::integer AS maintenance_count,
      COUNT(v.id) FILTER (WHERE v.status = 'in_use')::integer AS in_use_count
    FROM urban_zones z
    LEFT JOIN vehicles v
      ON ST_DWithin(
        v.location,
        ST_SetSRID(ST_MakePoint(z.center_lng, z.center_lat), 4326)::geography,
        z.radius_meters
      )
    WHERE z.status = 'active'
      AND (z.starts_at IS NULL OR z.starts_at <= now())
      AND (z.ends_at IS NULL OR z.ends_at >= now())
    GROUP BY z.id, z.name, z.type, z.center_lat, z.center_lng, z.radius_meters
  )
  SELECT
    z.id,
    z.name,
    z.type,
    z.center_lat,
    z.center_lng,
    z.radius_meters,
    z.available_count,
    z.total_count,
    z.low_battery_count,
    z.maintenance_count,
    z.in_use_count,
    v_threshold,
    CASE
      WHEN z.available_count = 0 OR z.maintenance_count >= v_threshold THEN 'critical'
      WHEN z.available_count < v_threshold OR z.low_battery_count >= GREATEST(1, z.total_count) THEN 'warning'
      ELSE 'ok'
    END,
    CASE
      WHEN z.available_count = 0 THEN 'Nessun mezzo disponibile in zona ' || z.name
      WHEN z.available_count < v_threshold THEN 'Disponibilita bassa in zona ' || z.name
      WHEN z.maintenance_count >= v_threshold THEN 'Troppi mezzi in manutenzione in zona ' || z.name
      WHEN z.low_battery_count >= GREATEST(1, z.total_count) THEN 'Solo mezzi con batteria bassa in zona ' || z.name
      ELSE 'Disponibilita adeguata in zona ' || z.name
    END
  FROM zone_counts z
  WHERE z.available_count < v_threshold
     OR z.maintenance_count >= v_threshold
     OR z.low_battery_count >= GREATEST(1, z.total_count)
  ORDER BY
    CASE
      WHEN z.available_count = 0 OR z.maintenance_count >= v_threshold THEN 0
      WHEN z.available_count < v_threshold THEN 1
      ELSE 2
    END,
    z.available_count ASC,
    z.name ASC;
END;
$$;

CREATE OR REPLACE FUNCTION operator_maintenance_vehicles()
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
  is_remote_locked boolean,
  remote_lock_reason text,
  last_maintenance_at timestamptz,
  operator_notes text,
  lat double precision,
  lng double precision,
  open_reports_count integer,
  days_since_maintenance integer,
  priority text,
  reasons text[]
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
  WITH base AS (
    SELECT
      v.*,
      COALESCE((
        SELECT COUNT(*)::integer
        FROM vehicle_reports vr
        WHERE vr.vehicle_id = v.id
          AND vr.status IN ('open', 'in_progress')
      ), 0) AS open_reports_count,
      CASE
        WHEN v.last_maintenance_at IS NULL THEN NULL
        ELSE FLOOR(EXTRACT(EPOCH FROM (now() - v.last_maintenance_at)) / 86400)::integer
      END AS days_since_maintenance
    FROM vehicles v
  )
  SELECT
    b.id,
    b.code,
    b.type,
    b.vehicle_type,
    b.category,
    b.brand,
    b.model,
    b.display_name,
    b.status,
    b.battery_level,
    b.is_remote_locked,
    b.remote_lock_reason,
    b.last_maintenance_at,
    b.operator_notes,
    ST_Y(b.location::geometry),
    ST_X(b.location::geometry),
    b.open_reports_count,
    b.days_since_maintenance,
    CASE
      WHEN b.is_remote_locked IS TRUE OR b.status = 'maintenance' OR b.open_reports_count >= 2 THEN 'critical'
      WHEN b.battery_level < 25 OR b.open_reports_count > 0 THEN 'high'
      WHEN b.last_maintenance_at IS NULL OR b.days_since_maintenance > 30 OR b.battery_level < 35 THEN 'medium'
      ELSE 'low'
    END,
    array_remove(ARRAY[
      CASE WHEN b.is_remote_locked IS TRUE THEN 'Blocco remoto attivo' END,
      CASE WHEN b.status = 'maintenance' THEN 'Stato manutenzione' END,
      CASE WHEN b.battery_level < 25 THEN 'Batteria molto bassa' END,
      CASE WHEN b.battery_level >= 25 AND b.battery_level < 35 THEN 'Batteria bassa' END,
      CASE WHEN b.open_reports_count > 0 THEN b.open_reports_count::text || ' segnalazioni aperte' END,
      CASE WHEN b.last_maintenance_at IS NULL THEN 'Manutenzione mai registrata' END,
      CASE WHEN b.days_since_maintenance > 30 THEN 'Manutenzione oltre 30 giorni' END
    ], NULL)::text[]
  FROM base b
  WHERE b.is_remote_locked IS TRUE
     OR b.status = 'maintenance'
     OR b.battery_level < 35
     OR b.open_reports_count > 0
     OR b.last_maintenance_at IS NULL
     OR b.days_since_maintenance > 30
  ORDER BY
    CASE
      WHEN b.is_remote_locked IS TRUE OR b.status = 'maintenance' OR b.open_reports_count >= 2 THEN 0
      WHEN b.battery_level < 25 OR b.open_reports_count > 0 THEN 1
      WHEN b.last_maintenance_at IS NULL OR b.days_since_maintenance > 30 OR b.battery_level < 35 THEN 2
      ELSE 3
    END,
    b.updated_at DESC;
END;
$$;

CREATE OR REPLACE FUNCTION operator_active_rides()
RETURNS TABLE (
  ride_id uuid,
  vehicle_id uuid,
  vehicle_code text,
  vehicle_display_name text,
  user_id uuid,
  user_name text,
  ride_status text,
  pause_status text,
  started_at timestamptz,
  lat double precision,
  lng double precision,
  recorded_at timestamptz,
  stale_minutes integer,
  position_count integer
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
      rp.lat,
      rp.lng,
      rp.recorded_at
    FROM ride_positions rp
    ORDER BY rp.ride_id, rp.recorded_at DESC
  ),
  counts AS (
    SELECT rp.ride_id, COUNT(*)::integer AS position_count
    FROM ride_positions rp
    GROUP BY rp.ride_id
  )
  SELECT
    r.id,
    r.vehicle_id,
    v.code,
    COALESCE(v.display_name, trim(v.brand || ' ' || v.model), v.code),
    r.user_id,
    p.display_name,
    r.status,
    r.pause_status,
    r.started_at,
    COALESCE(l.lat, ST_Y(v.location::geometry)),
    COALESCE(l.lng, ST_X(v.location::geometry)),
    COALESCE(l.recorded_at, v.updated_at),
    FLOOR(EXTRACT(EPOCH FROM (now() - COALESCE(l.recorded_at, v.updated_at))) / 60)::integer,
    COALESCE(c.position_count, 0)::integer
  FROM rides r
  JOIN vehicles v ON v.id = r.vehicle_id
  JOIN profiles p ON p.id = r.user_id
  LEFT JOIN latest l ON l.ride_id = r.id
  LEFT JOIN counts c ON c.ride_id = r.id
  WHERE r.status = 'active'
  ORDER BY COALESCE(l.recorded_at, v.updated_at) DESC;
END;
$$;

CREATE OR REPLACE FUNCTION operator_ride_positions(p_ride_id uuid)
RETURNS TABLE (
  id uuid,
  ride_id uuid,
  vehicle_id uuid,
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

  IF NOT EXISTS (SELECT 1 FROM rides WHERE rides.id = p_ride_id) THEN
    RAISE EXCEPTION 'ride not found';
  END IF;

  RETURN QUERY
  SELECT rp.id, rp.ride_id, rp.vehicle_id, rp.lat, rp.lng, rp.recorded_at
  FROM ride_positions rp
  WHERE rp.ride_id = p_ride_id
  ORDER BY rp.recorded_at ASC;
END;
$$;

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
  v_parking_bonus_points integer := 0;
  v_is_restricted boolean := false;
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

  SELECT EXISTS (
    SELECT 1
    FROM urban_zones z
    WHERE z.type = 'restricted_area'
      AND z.status = 'active'
      AND (z.starts_at IS NULL OR z.starts_at <= now())
      AND (z.ends_at IS NULL OR z.ends_at >= now())
      AND ST_DWithin(
        ST_SetSRID(ST_MakePoint(p_lng, p_lat), 4326)::geography,
        ST_SetSRID(ST_MakePoint(z.center_lng, z.center_lat), 4326)::geography,
        z.radius_meters
      )
  ) INTO v_is_restricted;

  IF NOT v_is_restricted THEN
    v_parking_bonus_points := 5;

    UPDATE user_credit_wallets
    SET points_balance = points_balance + v_parking_bonus_points,
        updated_at = now()
    WHERE user_id = v_user;

    INSERT INTO credit_transactions (user_id, ride_id, type, points, amount, description)
    VALUES (v_user, v_ride.id, 'earned', v_parking_bonus_points, 0, 'Bonus parcheggio corretto');
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
    'parking_bonus_points', v_parking_bonus_points,
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

CREATE OR REPLACE FUNCTION operator_parking_bonuses()
RETURNS TABLE (
  id uuid,
  user_id uuid,
  user_name text,
  user_email text,
  ride_id uuid,
  vehicle_id uuid,
  vehicle_code text,
  vehicle_display_name text,
  points integer,
  amount numeric,
  description text,
  created_at timestamptz
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
    ct.id,
    ct.user_id,
    p.display_name,
    p.email,
    ct.ride_id,
    r.vehicle_id,
    v.code,
    COALESCE(v.display_name, trim(v.brand || ' ' || v.model), v.code),
    ct.points,
    ct.amount,
    ct.description,
    ct.created_at
  FROM credit_transactions ct
  JOIN profiles p ON p.id = ct.user_id
  LEFT JOIN rides r ON r.id = ct.ride_id
  LEFT JOIN vehicles v ON v.id = r.vehicle_id
  WHERE ct.type = 'earned'
    AND ct.description ILIKE 'Bonus parcheggio%'
  ORDER BY ct.created_at DESC;
END;
$$;

CREATE OR REPLACE FUNCTION operator_parking_bonus_award(
  p_ride_id uuid,
  p_points integer DEFAULT 5,
  p_reason text DEFAULT 'Bonus parcheggio corretto'
)
RETURNS credit_transactions
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_ride rides;
  v_tx credit_transactions;
  v_points integer := COALESCE(p_points, 5);
  v_reason text := NULLIF(trim(COALESCE(p_reason, '')), '');
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'not authenticated';
  END IF;
  IF NOT is_operator() THEN
    RAISE EXCEPTION 'forbidden';
  END IF;
  IF v_points <= 0 OR v_points > 100 THEN
    RAISE EXCEPTION 'invalid points';
  END IF;
  IF v_reason IS NULL THEN
    v_reason := 'Bonus parcheggio corretto';
  ELSIF v_reason !~* '^Bonus parcheggio' THEN
    v_reason := 'Bonus parcheggio corretto - ' || v_reason;
  END IF;

  SELECT * INTO v_ride FROM rides WHERE id = p_ride_id;
  IF v_ride.id IS NULL THEN
    RAISE EXCEPTION 'ride not found';
  END IF;
  IF v_ride.status <> 'completed' THEN
    RAISE EXCEPTION 'ride not completed';
  END IF;
  IF EXISTS (
    SELECT 1 FROM credit_transactions
    WHERE ride_id = p_ride_id
      AND type = 'earned'
      AND description ILIKE 'Bonus parcheggio%'
  ) THEN
    RAISE EXCEPTION 'parking bonus already assigned';
  END IF;

  INSERT INTO user_credit_wallets (user_id)
  VALUES (v_ride.user_id)
  ON CONFLICT (user_id) DO NOTHING;

  UPDATE user_credit_wallets
  SET points_balance = points_balance + v_points,
      updated_at = now()
  WHERE user_id = v_ride.user_id;

  INSERT INTO credit_transactions (user_id, ride_id, type, points, amount, description)
  VALUES (v_ride.user_id, v_ride.id, 'earned', v_points, 0, v_reason)
  RETURNING * INTO v_tx;

  RETURN v_tx;
END;
$$;

CREATE OR REPLACE FUNCTION operator_support_tickets()
RETURNS TABLE (
  id uuid,
  user_id uuid,
  assigned_operator_id uuid,
  subject text,
  status text,
  created_at timestamptz,
  updated_at timestamptz,
  user_name text,
  user_email text,
  message_count integer,
  last_message_at timestamptz
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
    t.id,
    t.user_id,
    t.assigned_operator_id,
    t.subject,
    t.status,
    t.created_at,
    t.updated_at,
    p.display_name,
    p.email,
    COALESCE(m.message_count, 0)::integer,
    m.last_message_at
  FROM support_tickets t
  JOIN profiles p ON p.id = t.user_id
  LEFT JOIN LATERAL (
    SELECT COUNT(*)::integer AS message_count, MAX(created_at) AS last_message_at
    FROM support_messages sm
    WHERE sm.ticket_id = t.id
  ) m ON true
  ORDER BY COALESCE(m.last_message_at, t.updated_at, t.created_at) DESC;
END;
$$;

CREATE OR REPLACE FUNCTION operator_support_messages(p_ticket_id uuid)
RETURNS TABLE (
  id uuid,
  ticket_id uuid,
  sender_id uuid,
  sender_role text,
  message text,
  created_at timestamptz
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
  IF NOT EXISTS (SELECT 1 FROM support_tickets WHERE support_tickets.id = p_ticket_id) THEN
    RAISE EXCEPTION 'ticket not found';
  END IF;

  RETURN QUERY
  SELECT sm.id, sm.ticket_id, sm.sender_id, sm.sender_role, sm.message, sm.created_at
  FROM support_messages sm
  WHERE sm.ticket_id = p_ticket_id
  ORDER BY sm.created_at ASC;
END;
$$;

CREATE OR REPLACE FUNCTION operator_support_send_message(p_ticket_id uuid, p_message text)
RETURNS support_messages
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_message support_messages;
  v_text text := NULLIF(trim(COALESCE(p_message, '')), '');
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'not authenticated';
  END IF;
  IF NOT is_operator() THEN
    RAISE EXCEPTION 'forbidden';
  END IF;
  IF v_text IS NULL THEN
    RAISE EXCEPTION 'message cannot be empty';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM support_tickets WHERE id = p_ticket_id AND status <> 'closed') THEN
    RAISE EXCEPTION 'ticket not found or closed';
  END IF;

  INSERT INTO support_messages (ticket_id, sender_id, sender_role, message)
  VALUES (p_ticket_id, auth.uid(), 'operator', v_text)
  RETURNING * INTO v_message;

  UPDATE support_tickets
  SET status = CASE WHEN status = 'open' THEN 'in_progress' ELSE status END,
      assigned_operator_id = auth.uid(),
      updated_at = now()
  WHERE id = p_ticket_id;

  RETURN v_message;
END;
$$;

CREATE OR REPLACE FUNCTION operator_support_update_status(p_ticket_id uuid, p_status text)
RETURNS support_tickets
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_ticket support_tickets;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'not authenticated';
  END IF;
  IF NOT is_operator() THEN
    RAISE EXCEPTION 'forbidden';
  END IF;
  IF p_status NOT IN ('open', 'in_progress', 'resolved', 'closed') THEN
    RAISE EXCEPTION 'invalid ticket status';
  END IF;

  UPDATE support_tickets
  SET status = p_status,
      assigned_operator_id = auth.uid(),
      updated_at = now()
  WHERE id = p_ticket_id
  RETURNING * INTO v_ticket;

  IF v_ticket.id IS NULL THEN
    RAISE EXCEPTION 'ticket not found';
  END IF;

  RETURN v_ticket;
END;
$$;


-- ============================================================================
-- supabase\migrations\20260527200000_security_rls_grants.sql
-- ============================================================================

/*
  # Supabase Security Advisor hardening

  Incremental migration after 20260527170000_operator_sprint2.sql.
  It keeps all application tables protected by RLS and adds explicit Data API
  grants for the authenticated role ahead of Supabase's public schema grant
  rollout. The anon role intentionally receives no table privileges.
*/

GRANT USAGE ON SCHEMA public TO anon, authenticated, service_role;

DO $$
DECLARE
  table_name text;
  table_ref regclass;
  application_tables text[] := ARRAY[
    'profiles',
    'vehicles',
    'reservations',
    'rides',
    'payment_methods',
    'payments',
    'vehicle_reports',
    'urban_zones',
    'user_credit_wallets',
    'credit_transactions',
    'support_tickets',
    'support_messages',
    'ride_positions'
  ];
BEGIN
  FOREACH table_name IN ARRAY application_tables LOOP
    table_ref := to_regclass('public.' || quote_ident(table_name));
    IF table_ref IS NULL THEN
      RAISE NOTICE 'Skipping security hardening for missing table public.%', table_name;
    ELSE
      EXECUTE format('ALTER TABLE %s ENABLE ROW LEVEL SECURITY', table_ref);
      EXECUTE format('REVOKE ALL ON TABLE %s FROM PUBLIC, anon, authenticated', table_ref);
      EXECUTE format('GRANT ALL PRIVILEGES ON TABLE %s TO service_role', table_ref);
    END IF;
  END LOOP;
END;
$$;

DO $$
DECLARE
  table_name text;
  table_ref regclass;
  select_tables text[] := ARRAY[
    'profiles',
    'vehicles',
    'reservations',
    'rides',
    'payment_methods',
    'payments',
    'vehicle_reports',
    'urban_zones',
    'credit_transactions',
    'support_tickets',
    'support_messages'
  ];
BEGIN
  FOREACH table_name IN ARRAY select_tables LOOP
    table_ref := to_regclass('public.' || quote_ident(table_name));
    IF table_ref IS NULL THEN
      RAISE NOTICE 'Skipping SELECT grant for missing table public.%', table_name;
    ELSE
      EXECUTE format('GRANT SELECT ON TABLE %s TO authenticated', table_ref);
    END IF;
  END LOOP;
END;
$$;

DO $$
DECLARE
  table_ref regclass;
BEGIN
  table_ref := to_regclass('public.payment_methods');
  IF table_ref IS NULL THEN
    RAISE NOTICE 'Skipping write grants for missing table public.payment_methods';
  ELSE
    EXECUTE format('GRANT INSERT, UPDATE, DELETE ON TABLE %s TO authenticated', table_ref);
  END IF;

  table_ref := to_regclass('public.vehicle_reports');
  IF table_ref IS NULL THEN
    RAISE NOTICE 'Skipping write grants for missing table public.vehicle_reports';
  ELSE
    EXECUTE format('GRANT INSERT, UPDATE ON TABLE %s TO authenticated', table_ref);
  END IF;

  table_ref := to_regclass('public.support_tickets');
  IF table_ref IS NULL THEN
    RAISE NOTICE 'Skipping write grants for missing table public.support_tickets';
  ELSE
    EXECUTE format('GRANT INSERT ON TABLE %s TO authenticated', table_ref);
  END IF;

  table_ref := to_regclass('public.support_messages');
  IF table_ref IS NULL THEN
    RAISE NOTICE 'Skipping write grants for missing table public.support_messages';
  ELSE
    EXECUTE format('GRANT INSERT ON TABLE %s TO authenticated', table_ref);
  END IF;
END;
$$;

DO $$
BEGIN
  IF to_regclass('public.support_tickets') IS NULL THEN
    RAISE NOTICE 'Skipping touch_support_ticket_updated_at recreation because public.support_tickets is missing';
  ELSE
    EXECUTE $function$
      CREATE OR REPLACE FUNCTION public.touch_support_ticket_updated_at()
      RETURNS trigger
      LANGUAGE plpgsql SECURITY DEFINER
      SET search_path = public
      AS $body$
      BEGIN
        UPDATE support_tickets SET updated_at = now()
        WHERE id = NEW.ticket_id;
        RETURN NEW;
      END;
      $body$;
    $function$;
  END IF;
END;
$$;

DO $$
DECLARE
  function_signature text;
  function_ref regprocedure;
  api_functions text[] := ARRAY[
    'public.current_profile_role()',
    'public.is_operator()',
    'public.is_public_admin()',
    'public.is_user_role()',
    'public.profile_status()',
    'public.reservation_expire_stale()',
    'public.vehicles_nearby(double precision,double precision,integer)',
    'public.reservation_create(uuid)',
    'public.ride_unlock(uuid)',
    'public.ride_pause(uuid)',
    'public.ride_resume(uuid)',
    'public.ride_position_record(uuid,double precision,double precision)',
    'public.ride_end(uuid,double precision,double precision)',
    'public.ride_end(uuid,double precision,double precision,boolean)',
    'public.ride_end_details(uuid)',
    'public.credit_wallet_get()',
    'public.credit_redeem(integer)',
    'public.support_ticket_close(uuid)',
    'public.update_user_status(uuid,text)',
    'public.operator_set_vehicle_remote_lock(uuid,boolean,text)',
    'public.operator_update_vehicle_maintenance(uuid,text,text)',
    'public.operator_fleet_snapshot()',
    'public.zone_availability_report()',
    'public.operator_ride_tracking()',
    'public.operator_fleet_distribution()',
    'public.operator_low_availability_alerts(integer)',
    'public.operator_maintenance_vehicles()',
    'public.operator_active_rides()',
    'public.operator_ride_positions(uuid)',
    'public.operator_parking_bonuses()',
    'public.operator_parking_bonus_award(uuid,integer,text)',
    'public.operator_support_tickets()',
    'public.operator_support_messages(uuid)',
    'public.operator_support_send_message(uuid,text)',
    'public.operator_support_update_status(uuid,text)',
    'public.public_admin_vehicle_usage_frequency(timestamp with time zone,timestamp with time zone)',
    'public.public_admin_mobility_report()',
    'public.public_admin_mobility_report(timestamp with time zone,timestamp with time zone)',
    'public.public_admin_fleet_status()',
    'public.public_admin_top_routes()',
    'public.public_admin_top_routes(timestamp with time zone,timestamp with time zone)',
    'public.public_admin_urban_zone_save(text,text,text,text,double precision,double precision,integer,timestamp with time zone,timestamp with time zone,uuid)',
    'public.public_admin_urban_zone_set_status(uuid,text)'
  ];
BEGIN
  FOREACH function_signature IN ARRAY api_functions LOOP
    function_ref := to_regprocedure(function_signature);
    IF function_ref IS NOT NULL THEN
      EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC, anon, authenticated', function_ref);
      EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO authenticated, service_role', function_ref);
    END IF;
  END LOOP;
END;
$$;

DO $$
DECLARE
  function_signature text;
  function_ref regprocedure;
  internal_functions text[] := ARRAY[
    'public.handle_new_user()',
    'public.enforce_single_default_payment_method()',
    'public.touch_support_ticket_updated_at()'
  ];
BEGIN
  FOREACH function_signature IN ARRAY internal_functions LOOP
    function_ref := to_regprocedure(function_signature);
    IF function_ref IS NOT NULL THEN
      EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC, anon, authenticated', function_ref);
      EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO service_role', function_ref);
    END IF;
  END LOOP;
END;
$$;


-- ============================================================================
-- supabase\seed_test_users_dev.generated.sql
-- ============================================================================

/*
  ZooSmart development test users seed.

  Generated by scripts/seed-test-users.mjs with bcryptjs (10 rounds).
  Development only. Plaintext demo passwords are not stored in this SQL file.

  Run after the ZooSmart migrations, including 20260527120000_sprint2.sql.
*/

begin;

create or replace function pg_temp.zoosmart_dev_upsert_email_identity(
  p_user_id uuid,
  p_email text,
  p_display_name text
)
returns void
language plpgsql
as $$
declare
  v_identity_data jsonb;
  v_has_provider_id boolean;
  v_id_type text;
begin
  if to_regclass('auth.identities') is null then
    return;
  end if;

  v_identity_data := jsonb_build_object(
    'sub', p_user_id::text,
    'email', p_email,
    'email_verified', true,
    'phone_verified', false,
    'display_name', p_display_name
  );

  select exists (
    select 1
    from information_schema.columns
    where table_schema = 'auth'
      and table_name = 'identities'
      and column_name = 'provider_id'
  )
  into v_has_provider_id;

  if v_has_provider_id then
    insert into auth.identities (
      provider_id,
      user_id,
      identity_data,
      provider,
      last_sign_in_at,
      created_at,
      updated_at
    )
    values (
      p_user_id::text,
      p_user_id,
      v_identity_data,
      'email',
      now(),
      now(),
      now()
    )
    on conflict (provider_id, provider) do update
    set user_id = excluded.user_id,
        identity_data = excluded.identity_data,
        updated_at = now();
    return;
  end if;

  select data_type
  into v_id_type
  from information_schema.columns
  where table_schema = 'auth'
    and table_name = 'identities'
    and column_name = 'id';

  if v_id_type = 'uuid' then
    insert into auth.identities (
      id,
      user_id,
      identity_data,
      provider,
      last_sign_in_at,
      created_at,
      updated_at
    )
    values (
      p_user_id,
      p_user_id,
      v_identity_data,
      'email',
      now(),
      now(),
      now()
    )
    on conflict (id) do update
    set user_id = excluded.user_id,
        identity_data = excluded.identity_data,
        updated_at = now();
  else
    insert into auth.identities (
      id,
      user_id,
      identity_data,
      provider,
      last_sign_in_at,
      created_at,
      updated_at
    )
    values (
      p_user_id::text,
      p_user_id,
      v_identity_data,
      'email',
      now(),
      now(),
      now()
    )
    on conflict (id) do update
    set user_id = excluded.user_id,
        identity_data = excluded.identity_data,
        updated_at = now();
  end if;
end;
$$;

create or replace function pg_temp.zoosmart_dev_upsert_test_user(
  p_default_id uuid,
  p_email text,
  p_password_hash text,
  p_role text,
  p_status text,
  p_display_name text
)
returns void
language plpgsql
as $$
declare
  v_user_id uuid;
begin
  if p_role not in ('user', 'operator', 'public_admin') then
    raise exception 'invalid ZooSmart role: %', p_role;
  end if;

  if p_status not in ('active', 'suspended', 'blocked') then
    raise exception 'invalid ZooSmart profile status: %', p_status;
  end if;

  select id
  into v_user_id
  from auth.users
  where lower(email) = lower(p_email)
  order by created_at asc
  limit 1;

  if v_user_id is null then
    select id
    into v_user_id
    from auth.users
    where id = p_default_id
    limit 1;
  end if;

  if v_user_id is null then
    v_user_id := p_default_id;

    insert into auth.users (
      instance_id,
      id,
      aud,
      role,
      email,
      encrypted_password,
      email_confirmed_at,
      confirmation_sent_at,
      raw_app_meta_data,
      raw_user_meta_data,
      is_super_admin,
      created_at,
      updated_at
    )
    values (
      '00000000-0000-0000-0000-000000000000',
      v_user_id,
      'authenticated',
      'authenticated',
      lower(p_email),
      p_password_hash,
      now(),
      now(),
      jsonb_build_object('provider', 'email', 'providers', array['email'], 'zoosmart_role', p_role),
      jsonb_build_object('display_name', p_display_name, 'role', p_role, 'status', p_status),
      false,
      now(),
      now()
    );
  else
    update auth.users
    set aud = 'authenticated',
        role = 'authenticated',
        email = lower(p_email),
        encrypted_password = p_password_hash,
        email_confirmed_at = coalesce(email_confirmed_at, now()),
        confirmation_sent_at = coalesce(confirmation_sent_at, now()),
        raw_app_meta_data = coalesce(raw_app_meta_data, '{}'::jsonb)
          || jsonb_build_object('provider', 'email', 'providers', array['email'], 'zoosmart_role', p_role),
        raw_user_meta_data = coalesce(raw_user_meta_data, '{}'::jsonb)
          || jsonb_build_object('display_name', p_display_name, 'role', p_role, 'status', p_status),
        updated_at = now()
    where id = v_user_id;
  end if;

  perform pg_temp.zoosmart_dev_upsert_email_identity(v_user_id, lower(p_email), p_display_name);

  insert into public.profiles (
    id,
    email,
    display_name,
    role,
    status,
    created_at,
    updated_at
  )
  values (
    v_user_id,
    lower(p_email),
    p_display_name,
    p_role,
    p_status,
    now(),
    now()
  )
  on conflict (id) do update
  set email = excluded.email,
      display_name = excluded.display_name,
      role = excluded.role,
      status = excluded.status,
      updated_at = now();
end;
$$;

SELECT pg_temp.zoosmart_dev_upsert_test_user(
  '10000000-0000-4000-8000-000000000001'::uuid,
  'user@zoosmart.local',
  '$2b$10$osLoyeMgqGUprNtM6FHvBebJ6C9iltF71or/PnfmHCN6/JKmJpL7C',
  'user',
  'active',
  'ZooSmart User Test'
);

SELECT pg_temp.zoosmart_dev_upsert_test_user(
  '10000000-0000-4000-8000-000000000002'::uuid,
  'operator@zoosmart.local',
  '$2b$10$R5bIR.qgHZnYxRMIuz.GP.nXoh6qzsgj.bAP5LeR3qUHVhun/bglG',
  'operator',
  'active',
  'ZooSmart Operator Test'
);

SELECT pg_temp.zoosmart_dev_upsert_test_user(
  '10000000-0000-4000-8000-000000000003'::uuid,
  'admin.comune@zoosmart.local',
  '$2b$10$wA5XuVMxSNZSndh9eRODTegR34w4gWVUISIyYvPq5lracWMXqbUVu',
  'public_admin',
  'active',
  'ZooSmart Comune Test'
);

commit;

select
  p.role,
  p.email,
  p.status,
  u.email_confirmed_at is not null as email_confirmed,
  u.raw_user_meta_data->>'role' as jwt_user_metadata_role,
  u.raw_app_meta_data->>'zoosmart_role' as jwt_app_metadata_zoosmart_role
from public.profiles p
join auth.users u on u.id = p.id
where p.email in ('user@zoosmart.local', 'operator@zoosmart.local', 'admin.comune@zoosmart.local')
order by case p.role
  when 'user' then 1
  when 'operator' then 2
  when 'public_admin' then 3
  else 4
end;

/*
  Sprint 2 final audit tables: ride pause history and maintenance tasks.
  Keep this block after the earlier RPC definitions so these versions are the
  final ones applied by the all-in-one setup script.
*/

CREATE TABLE IF NOT EXISTS public.ride_pauses (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  ride_id uuid NOT NULL REFERENCES public.rides(id) ON DELETE CASCADE,
  started_at timestamptz NOT NULL,
  ended_at timestamptz,
  duration_seconds integer NOT NULL DEFAULT 0 CHECK (duration_seconds >= 0),
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS ride_pauses_ride_idx ON public.ride_pauses (ride_id, started_at DESC);
CREATE UNIQUE INDEX IF NOT EXISTS ride_pauses_one_active_idx
  ON public.ride_pauses (ride_id)
  WHERE ended_at IS NULL;

CREATE TABLE IF NOT EXISTS public.maintenance_tasks (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  vehicle_id uuid NOT NULL REFERENCES public.vehicles(id) ON DELETE CASCADE,
  assigned_operator_id uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  vehicle_report_id uuid REFERENCES public.vehicle_reports(id) ON DELETE SET NULL,
  type text NOT NULL DEFAULT 'corrective' CHECK (type IN ('scheduled', 'corrective', 'inspection')),
  priority text NOT NULL DEFAULT 'medium' CHECK (priority IN ('low', 'medium', 'high', 'critical')),
  reason text NOT NULL,
  notes text,
  opened_at timestamptz NOT NULL DEFAULT now(),
  started_at timestamptz,
  closed_at timestamptz,
  status text NOT NULL DEFAULT 'open' CHECK (status IN ('open', 'in_progress', 'closed', 'cancelled')),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT maintenance_tasks_reason_not_blank CHECK (length(trim(reason)) > 0),
  CONSTRAINT maintenance_tasks_started_before_closed CHECK (started_at IS NULL OR closed_at IS NULL OR started_at <= closed_at)
);

CREATE INDEX IF NOT EXISTS maintenance_tasks_vehicle_idx ON public.maintenance_tasks (vehicle_id, status, opened_at DESC);
CREATE INDEX IF NOT EXISTS maintenance_tasks_operator_idx ON public.maintenance_tasks (assigned_operator_id, status);
CREATE INDEX IF NOT EXISTS maintenance_tasks_report_idx ON public.maintenance_tasks (vehicle_report_id);
CREATE UNIQUE INDEX IF NOT EXISTS maintenance_tasks_one_active_per_vehicle_idx
  ON public.maintenance_tasks (vehicle_id)
  WHERE status IN ('open', 'in_progress');

CREATE OR REPLACE FUNCTION public.touch_maintenance_task_updated_at()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS maintenance_tasks_touch_updated_at ON public.maintenance_tasks;
CREATE TRIGGER maintenance_tasks_touch_updated_at
  BEFORE UPDATE ON public.maintenance_tasks
  FOR EACH ROW EXECUTE FUNCTION public.touch_maintenance_task_updated_at();

ALTER TABLE public.ride_pauses ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.maintenance_tasks ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "ride pauses select owner or operator" ON public.ride_pauses;
CREATE POLICY "ride pauses select owner or operator" ON public.ride_pauses FOR SELECT TO authenticated
  USING (
    is_operator()
    OR EXISTS (
      SELECT 1 FROM public.rides r
      WHERE r.id = ride_id AND r.user_id = auth.uid()
    )
  );

DROP POLICY IF EXISTS "maintenance tasks select operator or admin" ON public.maintenance_tasks;
CREATE POLICY "maintenance tasks select operator or admin" ON public.maintenance_tasks FOR SELECT TO authenticated
  USING (is_operator() OR is_public_admin());

REVOKE ALL ON TABLE public.ride_pauses FROM PUBLIC, anon, authenticated;
GRANT SELECT ON TABLE public.ride_pauses TO authenticated;
GRANT ALL PRIVILEGES ON TABLE public.ride_pauses TO service_role;

REVOKE ALL ON TABLE public.maintenance_tasks FROM PUBLIC, anon, authenticated;
GRANT SELECT ON TABLE public.maintenance_tasks TO authenticated;
GRANT ALL PRIVILEGES ON TABLE public.maintenance_tasks TO service_role;

REVOKE ALL ON FUNCTION public.touch_maintenance_task_updated_at() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.touch_maintenance_task_updated_at() TO service_role;

CREATE OR REPLACE FUNCTION public.ride_pause(p_ride_id uuid)
RETURNS public.rides
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user uuid := auth.uid();
  v_ride public.rides;
  v_started_at timestamptz := now();
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'not authenticated';
  END IF;
  IF NOT is_user_role() THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  SELECT * INTO v_ride FROM public.rides WHERE id = p_ride_id FOR UPDATE;
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

  INSERT INTO public.ride_pauses (ride_id, started_at)
  VALUES (v_ride.id, v_started_at)
  ON CONFLICT (ride_id) WHERE ended_at IS NULL DO NOTHING;

  UPDATE public.rides
  SET pause_status = 'paused', paused_at = v_started_at
  WHERE id = p_ride_id
  RETURNING * INTO v_ride;

  RETURN v_ride;
END;
$$;

CREATE OR REPLACE FUNCTION public.ride_resume(p_ride_id uuid)
RETURNS public.rides
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user uuid := auth.uid();
  v_ride public.rides;
  v_ended_at timestamptz := now();
  v_pause_seconds integer;
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'not authenticated';
  END IF;
  IF NOT is_user_role() THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  SELECT * INTO v_ride FROM public.rides WHERE id = p_ride_id FOR UPDATE;
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

  v_pause_seconds := GREATEST(0, FLOOR(EXTRACT(EPOCH FROM (v_ended_at - v_ride.paused_at)))::integer);

  UPDATE public.ride_pauses
  SET ended_at = v_ended_at,
      duration_seconds = v_pause_seconds
  WHERE ride_id = v_ride.id
    AND ended_at IS NULL;

  IF NOT FOUND THEN
    INSERT INTO public.ride_pauses (ride_id, started_at, ended_at, duration_seconds)
    VALUES (v_ride.id, v_ride.paused_at, v_ended_at, v_pause_seconds);
  END IF;

  UPDATE public.rides
  SET pause_status = 'active',
      paused_at = NULL,
      total_paused_seconds = total_paused_seconds + v_pause_seconds
  WHERE id = p_ride_id
  RETURNING * INTO v_ride;

  RETURN v_ride;
END;
$$;

DROP FUNCTION IF EXISTS public.ride_end(uuid, double precision, double precision);
DROP FUNCTION IF EXISTS public.ride_end(uuid, double precision, double precision, boolean);
CREATE FUNCTION public.ride_end(p_ride_id uuid, p_lat double precision, p_lng double precision, p_apply_credits boolean DEFAULT false)
RETURNS json
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user uuid := auth.uid();
  v_ride public.rides;
  v_vehicle public.vehicles;
  v_duration integer;
  v_billable_seconds integer;
  v_total_paused integer;
  v_current_pause_seconds integer := 0;
  v_ended_at timestamptz := now();
  v_original_cost numeric(10,2);
  v_discount numeric(10,2) := 0;
  v_final_cost numeric(10,2);
  v_method public.payment_methods;
  v_payment public.payments;
  v_points integer;
  v_wallet public.user_credit_wallets;
  v_parking_bonus_points integer := 0;
  v_is_restricted boolean := false;
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'not authenticated';
  END IF;
  IF NOT is_user_role() THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  SELECT * INTO v_ride FROM public.rides WHERE id = p_ride_id FOR UPDATE;
  IF v_ride IS NULL THEN
    RAISE EXCEPTION 'ride not found';
  END IF;
  IF v_ride.user_id <> v_user THEN
    RAISE EXCEPTION 'ride not owned';
  END IF;
  IF v_ride.status <> 'active' THEN
    RAISE EXCEPTION 'ride not active';
  END IF;

  SELECT * INTO v_vehicle FROM public.vehicles WHERE id = v_ride.vehicle_id FOR UPDATE;
  IF v_vehicle IS NULL THEN
    RAISE EXCEPTION 'vehicle not found';
  END IF;
  IF v_vehicle.unlock_fee IS NULL OR v_vehicle.price_per_minute IS NULL THEN
    RAISE EXCEPTION 'vehicle pricing missing';
  END IF;

  SELECT * INTO v_method FROM public.payment_methods
  WHERE user_id = v_user AND is_default = true LIMIT 1;
  IF v_method IS NULL THEN
    SELECT * INTO v_method FROM public.payment_methods
    WHERE user_id = v_user ORDER BY created_at DESC LIMIT 1;
  END IF;
  IF v_method IS NULL THEN
    RAISE EXCEPTION 'no payment method on file';
  END IF;

  IF v_ride.pause_status = 'paused' AND v_ride.paused_at IS NOT NULL THEN
    v_current_pause_seconds := GREATEST(0, FLOOR(EXTRACT(EPOCH FROM (v_ended_at - v_ride.paused_at)))::integer);

    UPDATE public.ride_pauses
    SET ended_at = v_ended_at,
        duration_seconds = v_current_pause_seconds
    WHERE ride_id = v_ride.id
      AND ended_at IS NULL;

    IF NOT FOUND THEN
      INSERT INTO public.ride_pauses (ride_id, started_at, ended_at, duration_seconds)
      VALUES (v_ride.id, v_ride.paused_at, v_ended_at, v_current_pause_seconds);
    END IF;
  END IF;

  v_total_paused := v_ride.total_paused_seconds + v_current_pause_seconds;
  v_billable_seconds := GREATEST(60, FLOOR(EXTRACT(EPOCH FROM (v_ended_at - v_ride.started_at)))::integer - v_total_paused);
  v_duration := GREATEST(1, CEIL(v_billable_seconds / 60.0)::integer);
  v_original_cost := ROUND((v_vehicle.unlock_fee + v_duration * v_vehicle.price_per_minute)::numeric, 2);

  INSERT INTO public.user_credit_wallets (user_id)
  VALUES (v_user)
  ON CONFLICT ON CONSTRAINT user_credit_wallets_user_id_key DO NOTHING;

  IF COALESCE(p_apply_credits, false) THEN
    SELECT w.* INTO v_wallet
    FROM public.user_credit_wallets AS w
    WHERE w.user_id = v_user
    FOR UPDATE;

    v_discount := LEAST(v_original_cost, COALESCE(v_wallet.credit_amount, 0));

    IF v_discount > 0 THEN
      UPDATE public.user_credit_wallets AS w
      SET credit_amount = w.credit_amount - v_discount,
          updated_at = now()
      WHERE w.user_id = v_user;

      INSERT INTO public.credit_transactions (user_id, ride_id, type, points, amount, description)
      VALUES (v_user, v_ride.id, 'redeemed', GREATEST(1, ROUND(v_discount * 10)::integer), v_discount, 'Credito promozionale applicato alla corsa');
    END IF;
  END IF;

  v_final_cost := ROUND(GREATEST(0, v_original_cost - v_discount)::numeric, 2);

  UPDATE public.rides
  SET ended_at = v_ended_at,
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

  INSERT INTO public.ride_positions (ride_id, vehicle_id, lat, lng, recorded_at)
  VALUES (v_ride.id, v_ride.vehicle_id, p_lat, p_lng, v_ended_at);

  UPDATE public.vehicles
  SET status = CASE WHEN is_remote_locked THEN 'maintenance' ELSE 'available' END,
      location = ST_SetSRID(ST_MakePoint(p_lng, p_lat), 4326)::geography,
      updated_at = now()
  WHERE id = v_ride.vehicle_id;

  INSERT INTO public.payments (user_id, ride_id, payment_method_id, amount, status)
  VALUES (v_user, v_ride.id, v_method.id, v_final_cost, 'completed')
  RETURNING * INTO v_payment;

  v_points := FLOOR(v_final_cost)::integer;

  IF v_points > 0 THEN
    UPDATE public.user_credit_wallets AS w
    SET points_balance = w.points_balance + v_points,
        updated_at = now()
    WHERE w.user_id = v_user;

    INSERT INTO public.credit_transactions (user_id, ride_id, type, points, amount, description)
    VALUES (v_user, v_ride.id, 'earned', v_points, 0, 'Punti maturati dalla corsa');
  END IF;

  SELECT EXISTS (
    SELECT 1
    FROM public.urban_zones z
    WHERE z.type = 'restricted_area'
      AND z.status = 'active'
      AND (z.starts_at IS NULL OR z.starts_at <= v_ended_at)
      AND (z.ends_at IS NULL OR z.ends_at >= v_ended_at)
      AND ST_DWithin(
        ST_SetSRID(ST_MakePoint(p_lng, p_lat), 4326)::geography,
        ST_SetSRID(ST_MakePoint(z.center_lng, z.center_lat), 4326)::geography,
        z.radius_meters
      )
  ) INTO v_is_restricted;

  IF NOT v_is_restricted THEN
    v_parking_bonus_points := 5;

    UPDATE public.user_credit_wallets AS w
    SET points_balance = w.points_balance + v_parking_bonus_points,
        updated_at = now()
    WHERE w.user_id = v_user;

    INSERT INTO public.credit_transactions (user_id, ride_id, type, points, amount, description)
    VALUES (v_user, v_ride.id, 'earned', v_parking_bonus_points, 0, 'Bonus parcheggio corretto');
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
    'parking_bonus_points', v_parking_bonus_points,
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

CREATE OR REPLACE FUNCTION public.operator_update_vehicle_maintenance(p_vehicle_id uuid, p_status text, p_notes text DEFAULT NULL)
RETURNS public.vehicles
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_vehicle public.vehicles;
  v_reason text := NULLIF(trim(COALESCE(p_notes, '')), '');
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

  SELECT * INTO v_vehicle FROM public.vehicles WHERE id = p_vehicle_id FOR UPDATE;
  IF v_vehicle.id IS NULL THEN
    RAISE EXCEPTION 'vehicle not found';
  END IF;

  UPDATE public.vehicles
  SET status = CASE WHEN is_remote_locked AND p_status = 'available' THEN 'maintenance' ELSE p_status END,
      operator_notes = COALESCE(p_notes, operator_notes),
      last_maintenance_at = CASE WHEN p_status IN ('maintenance', 'available') THEN now() ELSE last_maintenance_at END,
      updated_at = now()
  WHERE id = p_vehicle_id
  RETURNING * INTO v_vehicle;

  IF p_status = 'maintenance' THEN
    INSERT INTO public.maintenance_tasks (
      vehicle_id,
      assigned_operator_id,
      type,
      priority,
      reason,
      notes,
      opened_at,
      started_at,
      status
    )
    VALUES (
      p_vehicle_id,
      auth.uid(),
      'corrective',
      'high',
      COALESCE(v_reason, 'Intervento manutenzione operatore'),
      p_notes,
      now(),
      now(),
      'in_progress'
    )
    ON CONFLICT (vehicle_id) WHERE status IN ('open', 'in_progress') DO NOTHING;

    UPDATE public.maintenance_tasks
    SET assigned_operator_id = COALESCE(assigned_operator_id, auth.uid()),
        notes = COALESCE(p_notes, notes),
        started_at = COALESCE(started_at, now()),
        status = CASE WHEN status = 'open' THEN 'in_progress' ELSE status END
    WHERE vehicle_id = p_vehicle_id
      AND status IN ('open', 'in_progress');
  ELSE
    UPDATE public.maintenance_tasks
    SET assigned_operator_id = COALESCE(assigned_operator_id, auth.uid()),
        notes = COALESCE(NULLIF(trim(COALESCE(p_notes, '')), ''), notes),
        closed_at = COALESCE(closed_at, now()),
        status = 'closed'
    WHERE vehicle_id = p_vehicle_id
      AND status IN ('open', 'in_progress');
  END IF;

  RETURN v_vehicle;
END;
$$;

REVOKE ALL ON FUNCTION public.ride_pause(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.ride_pause(uuid) TO authenticated, service_role;

REVOKE ALL ON FUNCTION public.ride_resume(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.ride_resume(uuid) TO authenticated, service_role;

REVOKE ALL ON FUNCTION public.ride_end(uuid, double precision, double precision, boolean) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.ride_end(uuid, double precision, double precision, boolean) TO authenticated, service_role;

REVOKE ALL ON FUNCTION public.operator_update_vehicle_maintenance(uuid, text, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.operator_update_vehicle_maintenance(uuid, text, text) TO authenticated, service_role;

