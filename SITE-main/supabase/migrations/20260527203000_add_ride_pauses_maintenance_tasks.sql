/*
  # Add auditable ride pauses and maintenance tasks

  Sprint 2 already tracks the current pause state on rides and the current
  maintenance state on vehicles. These tables add history without replacing the
  existing workflow or duplicating support tickets / vehicle reports.
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
