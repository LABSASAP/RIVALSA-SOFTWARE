/*
  Conservative rollback for 20260527200000_security_rls_grants.sql.

  This rollback removes the explicit authenticated Data API grants added by the
  hardening migration, but intentionally keeps RLS enabled and does not restore
  anonymous table or RPC access.
*/

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
      RAISE NOTICE 'Skipping SELECT revoke for missing table public.%', table_name;
    ELSE
      EXECUTE format('REVOKE SELECT ON TABLE %s FROM authenticated', table_ref);
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
    RAISE NOTICE 'Skipping write grant rollback for missing table public.payment_methods';
  ELSE
    EXECUTE format('REVOKE INSERT, UPDATE, DELETE ON TABLE %s FROM authenticated', table_ref);
  END IF;

  table_ref := to_regclass('public.vehicle_reports');
  IF table_ref IS NULL THEN
    RAISE NOTICE 'Skipping write grant rollback for missing table public.vehicle_reports';
  ELSE
    EXECUTE format('REVOKE INSERT, UPDATE ON TABLE %s FROM authenticated', table_ref);
  END IF;

  table_ref := to_regclass('public.support_tickets');
  IF table_ref IS NULL THEN
    RAISE NOTICE 'Skipping write grant rollback for missing table public.support_tickets';
  ELSE
    EXECUTE format('REVOKE INSERT ON TABLE %s FROM authenticated', table_ref);
  END IF;

  table_ref := to_regclass('public.support_messages');
  IF table_ref IS NULL THEN
    RAISE NOTICE 'Skipping write grant rollback for missing table public.support_messages';
  ELSE
    EXECUTE format('REVOKE INSERT ON TABLE %s FROM authenticated', table_ref);
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
      EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM authenticated', function_ref);
    END IF;
  END LOOP;
END;
$$;
