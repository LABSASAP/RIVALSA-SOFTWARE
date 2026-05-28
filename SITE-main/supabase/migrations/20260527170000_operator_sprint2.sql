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
