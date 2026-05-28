/*
  Rollback for 20260527170000_operator_sprint2.sql.
  Drops operator Sprint 2 RPCs and restores the base Sprint 2 ride_end and
  remote-lock behavior.
*/

DROP FUNCTION IF EXISTS operator_support_update_status(uuid, text);
DROP FUNCTION IF EXISTS operator_support_send_message(uuid, text);
DROP FUNCTION IF EXISTS operator_support_messages(uuid);
DROP FUNCTION IF EXISTS operator_support_tickets();
DROP FUNCTION IF EXISTS operator_parking_bonus_award(uuid, integer, text);
DROP FUNCTION IF EXISTS operator_parking_bonuses();
DROP FUNCTION IF EXISTS operator_ride_positions(uuid);
DROP FUNCTION IF EXISTS operator_active_rides();
DROP FUNCTION IF EXISTS operator_maintenance_vehicles();
DROP FUNCTION IF EXISTS operator_low_availability_alerts(integer);
DROP FUNCTION IF EXISTS operator_fleet_distribution();

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
