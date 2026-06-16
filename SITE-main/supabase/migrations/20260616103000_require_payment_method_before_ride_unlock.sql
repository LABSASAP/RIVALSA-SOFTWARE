/*
  # Require payment method before ride unlock

  Users can still reserve vehicles without a payment method, but they must have
  at least one saved payment method before converting a reservation into a ride.
*/

CREATE OR REPLACE FUNCTION public.ride_unlock(p_reservation_id uuid)
RETURNS public.rides
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user uuid := auth.uid();
  v_profile_status text;
  v_res public.reservations;
  v_vehicle public.vehicles;
  v_ride public.rides;
  v_has_payment_method boolean;
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'not authenticated';
  END IF;
  IF NOT public.is_user_role() THEN
    RAISE EXCEPTION 'forbidden';
  END IF;

  SELECT status INTO v_profile_status FROM public.profiles WHERE id = v_user;
  IF v_profile_status <> 'active' THEN
    RAISE EXCEPTION 'account % cannot unlock', v_profile_status;
  END IF;

  PERFORM public.reservation_expire_stale();

  SELECT * INTO v_res FROM public.reservations WHERE id = p_reservation_id FOR UPDATE;
  IF v_res IS NULL THEN
    RAISE EXCEPTION 'reservation not found';
  END IF;
  IF v_res.user_id <> v_user THEN
    RAISE EXCEPTION 'reservation not owned';
  END IF;
  IF v_res.status <> 'active' THEN
    RAISE EXCEPTION 'reservation not active';
  END IF;

  SELECT * INTO v_vehicle FROM public.vehicles WHERE id = v_res.vehicle_id FOR UPDATE;
  IF v_vehicle.status <> 'reserved' THEN
    RAISE EXCEPTION 'vehicle not reserved';
  END IF;
  IF v_vehicle.is_remote_locked THEN
    RAISE EXCEPTION 'vehicle remotely locked';
  END IF;

  SELECT EXISTS (
    SELECT 1
    FROM public.payment_methods
    WHERE user_id = v_user
  ) INTO v_has_payment_method;

  IF NOT v_has_payment_method THEN
    RAISE EXCEPTION 'missing payment method';
  END IF;

  INSERT INTO public.rides (user_id, vehicle_id, reservation_id, start_location, status)
  VALUES (v_user, v_vehicle.id, v_res.id, v_vehicle.location, 'active')
  RETURNING * INTO v_ride;

  UPDATE public.reservations
  SET status = 'converted_to_ride', converted_ride_id = v_ride.id
  WHERE id = v_res.id;

  UPDATE public.vehicles
  SET status = 'in_use', updated_at = now()
  WHERE id = v_vehicle.id;

  RETURN v_ride;
END;
$$;
