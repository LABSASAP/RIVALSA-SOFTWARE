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
