/*
  ZooSmart Sprint 2 demo seed.

  Run after 20260527120000_sprint2.sql. Auth users must already exist in
  Supabase Auth before role promotion by email can take effect.
*/

UPDATE profiles
SET role = 'operator', updated_at = now()
WHERE email = 'operator@zoosmart.test';

UPDATE profiles
SET role = 'public_admin', updated_at = now()
WHERE email = 'admin@zoosmart.test';

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM urban_zones WHERE name = 'Cantiere Via Sparano') THEN
    INSERT INTO urban_zones (name, description, type, status, center_lat, center_lng, radius_meters, starts_at, ends_at)
    VALUES (
      'Cantiere Via Sparano',
      'Lavori urbani con corsia ridotta e attraversamenti pedonali temporanei.',
      'road_work',
      'active',
      41.1180,
      16.8718,
      260,
      now() - interval '1 day',
      now() + interval '14 days'
    );
  END IF;

  IF NOT EXISTS (SELECT 1 FROM urban_zones WHERE name = 'Area Sensibile Ateneo') THEN
    INSERT INTO urban_zones (name, description, type, status, center_lat, center_lng, radius_meters, starts_at, ends_at)
    VALUES (
      'Area Sensibile Ateneo',
      'Zona con alta presenza pedonale: suggerire velocita moderata e soste ordinate.',
      'sensitive_zone',
      'active',
      41.1204,
      16.8754,
      420,
      now() - interval '7 days',
      now() + interval '60 days'
    );
  END IF;

  IF NOT EXISTS (SELECT 1 FROM urban_zones WHERE name = 'Area Interdetta Porto Vecchio') THEN
    INSERT INTO urban_zones (name, description, type, status, center_lat, center_lng, radius_meters, starts_at, ends_at)
    VALUES (
      'Area Interdetta Porto Vecchio',
      'Accesso temporaneamente interdetto ai mezzi condivisi durante evento pubblico.',
      'restricted_area',
      'active',
      41.1276,
      16.8714,
      520,
      now() - interval '2 hours',
      now() + interval '3 days'
    );
  END IF;
END $$;

UPDATE urban_zones z
SET created_by_user_id = p.id,
    updated_at = now()
FROM profiles p
WHERE p.email = 'admin@zoosmart.test'
  AND z.created_by_user_id IS NULL
  AND z.name IN ('Cantiere Via Sparano', 'Area Sensibile Ateneo', 'Area Interdetta Porto Vecchio');
