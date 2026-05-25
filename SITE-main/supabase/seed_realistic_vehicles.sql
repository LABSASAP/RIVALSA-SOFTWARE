/*
  ZooSmart realistic vehicle catalog seed/update.

  Run after the vehicle catalog/pricing migration. Existing rows keep id,
  status, battery_level and location; only catalog/pricing fields are updated.
*/

WITH catalog(vehicle_type, idx, brand, model, display_name, category, unlock_fee, price_per_minute, hourly_rate, range_km, icon_type) AS (
  VALUES
    ('bike', 0, 'Decathlon', 'Riverside 500E', 'Decathlon Riverside 500E', 'bike', 0.50::numeric, 0.10::numeric, 5.00::numeric, 90, 'bike'),
    ('bike', 1, 'Nilox', 'X8', 'Nilox X8', 'bike', 0.50::numeric, 0.10::numeric, 5.00::numeric, 70, 'bike'),
    ('bike', 2, 'Fiido', 'D4S', 'Fiido D4S', 'bike', 0.50::numeric, 0.10::numeric, 5.00::numeric, 80, 'bike'),
    ('scooter', 0, 'Xiaomi', 'Electric Scooter 4', 'Xiaomi Electric Scooter 4', 'scooter', 1.00::numeric, 0.18::numeric, 9.00::numeric, 35, 'scooter'),
    ('scooter', 1, 'Ninebot', 'Max G30', 'Ninebot Max G30', 'scooter', 1.00::numeric, 0.18::numeric, 9.00::numeric, 65, 'scooter'),
    ('scooter', 2, 'Segway-Ninebot', 'F2 Pro', 'Segway-Ninebot F2 Pro', 'scooter', 1.00::numeric, 0.18::numeric, 9.00::numeric, 55, 'scooter'),
    ('car', 0, 'Fiat', '500e', 'Fiat 500e', 'economy_car', 2.00::numeric, 0.35::numeric, 18.00::numeric, 320, 'car-economy'),
    ('car', 1, 'Fiat', 'Grande Panda Electric', 'Fiat Grande Panda Electric', 'economy_car', 2.00::numeric, 0.35::numeric, 18.00::numeric, 320, 'car-economy'),
    ('car', 2, 'Dacia', 'Spring Electric', 'Dacia Spring Electric', 'economy_car', 2.00::numeric, 0.35::numeric, 18.00::numeric, 230, 'car-economy'),
    ('car', 3, 'Citroën', 'ë-C3', 'Citroën ë-C3', 'economy_car', 2.00::numeric, 0.35::numeric, 18.00::numeric, 320, 'car-economy'),
    ('car', 4, 'Peugeot', 'e-208', 'Peugeot e-208', 'standard_car', 3.00::numeric, 0.50::numeric, 28.00::numeric, 362, 'car-standard'),
    ('car', 5, 'Opel', 'Corsa Electric', 'Opel Corsa Electric', 'standard_car', 3.00::numeric, 0.50::numeric, 28.00::numeric, 354, 'car-standard'),
    ('car', 6, 'Volkswagen', 'ID.3', 'Volkswagen ID.3', 'standard_car', 3.00::numeric, 0.50::numeric, 28.00::numeric, 426, 'car-standard'),
    ('car', 7, 'Hyundai', 'Kona Electric', 'Hyundai Kona Electric', 'standard_car', 3.00::numeric, 0.50::numeric, 28.00::numeric, 514, 'car-standard'),
    ('car', 8, 'BMW', 'i4', 'BMW i4', 'premium_car', 5.00::numeric, 0.80::numeric, 45.00::numeric, 590, 'car-premium'),
    ('car', 9, 'BMW', 'iX1', 'BMW iX1', 'premium_car', 5.00::numeric, 0.80::numeric, 45.00::numeric, 438, 'car-premium'),
    ('car', 10, 'Tesla', 'Model 3', 'Tesla Model 3', 'premium_car', 5.00::numeric, 0.80::numeric, 45.00::numeric, 513, 'car-premium'),
    ('car', 11, 'Mercedes', 'EQA', 'Mercedes EQA', 'premium_car', 5.00::numeric, 0.80::numeric, 45.00::numeric, 560, 'car-premium')
),
ranked AS (
  SELECT
    id,
    type,
    (row_number() OVER (PARTITION BY type ORDER BY created_at, code) - 1)::integer AS rn
  FROM vehicles
  WHERE type IN ('bike', 'scooter', 'car')
),
type_counts AS (
  SELECT vehicle_type, count(*)::integer AS item_count
  FROM catalog
  GROUP BY vehicle_type
),
assignments AS (
  SELECT r.id, c.*
  FROM ranked r
  JOIN type_counts tc ON tc.vehicle_type = r.type
  JOIN catalog c ON c.vehicle_type = r.type AND c.idx = (r.rn % tc.item_count)
)
UPDATE vehicles v
SET
  brand = a.brand,
  model = a.model,
  display_name = a.display_name,
  vehicle_type = a.vehicle_type,
  category = a.category,
  unlock_fee = a.unlock_fee,
  price_per_minute = a.price_per_minute,
  hourly_rate = a.hourly_rate,
  range_km = a.range_km,
  icon_type = a.icon_type,
  updated_at = now()
FROM assignments a
WHERE v.id = a.id;

INSERT INTO vehicles (
  code,
  type,
  status,
  battery_level,
  location,
  brand,
  model,
  display_name,
  vehicle_type,
  category,
  unlock_fee,
  price_per_minute,
  hourly_rate,
  range_km,
  icon_type
)
VALUES
  ('BK-101', 'bike', 'available', 94, ST_SetSRID(ST_MakePoint(16.8718, 41.1174), 4326)::geography, 'Decathlon', 'Riverside 500E', 'Decathlon Riverside 500E', 'bike', 'bike', 0.50, 0.10, 5.00, 90, 'bike'),
  ('BK-102', 'bike', 'available', 82, ST_SetSRID(ST_MakePoint(16.8751, 41.1182), 4326)::geography, 'Nilox', 'X8', 'Nilox X8', 'bike', 'bike', 0.50, 0.10, 5.00, 70, 'bike'),
  ('BK-103', 'bike', 'available', 76, ST_SetSRID(ST_MakePoint(16.8689, 41.1167), 4326)::geography, 'Fiido', 'D4S', 'Fiido D4S', 'bike', 'bike', 0.50, 0.10, 5.00, 80, 'bike'),
  ('SC-201', 'scooter', 'available', 88, ST_SetSRID(ST_MakePoint(16.8735, 41.1191), 4326)::geography, 'Xiaomi', 'Electric Scooter 4', 'Xiaomi Electric Scooter 4', 'scooter', 'scooter', 1.00, 0.18, 9.00, 35, 'scooter'),
  ('SC-202', 'scooter', 'available', 71, ST_SetSRID(ST_MakePoint(16.8763, 41.1169), 4326)::geography, 'Ninebot', 'Max G30', 'Ninebot Max G30', 'scooter', 'scooter', 1.00, 0.18, 9.00, 65, 'scooter'),
  ('SC-203', 'scooter', 'available', 63, ST_SetSRID(ST_MakePoint(16.8702, 41.1196), 4326)::geography, 'Segway-Ninebot', 'F2 Pro', 'Segway-Ninebot F2 Pro', 'scooter', 'scooter', 1.00, 0.18, 9.00, 55, 'scooter'),
  ('EC-301', 'car', 'available', 91, ST_SetSRID(ST_MakePoint(16.8678, 41.1158), 4326)::geography, 'Fiat', '500e', 'Fiat 500e', 'car', 'economy_car', 2.00, 0.35, 18.00, 320, 'car-economy'),
  ('EC-302', 'car', 'available', 84, ST_SetSRID(ST_MakePoint(16.8794, 41.1176), 4326)::geography, 'Fiat', 'Grande Panda Electric', 'Fiat Grande Panda Electric', 'car', 'economy_car', 2.00, 0.35, 18.00, 320, 'car-economy'),
  ('EC-303', 'car', 'available', 69, ST_SetSRID(ST_MakePoint(16.8729, 41.1148), 4326)::geography, 'Dacia', 'Spring Electric', 'Dacia Spring Electric', 'car', 'economy_car', 2.00, 0.35, 18.00, 230, 'car-economy'),
  ('EC-304', 'car', 'available', 73, ST_SetSRID(ST_MakePoint(16.8659, 41.1188), 4326)::geography, 'Citroën', 'ë-C3', 'Citroën ë-C3', 'car', 'economy_car', 2.00, 0.35, 18.00, 320, 'car-economy'),
  ('ST-401', 'car', 'available', 87, ST_SetSRID(ST_MakePoint(16.8811, 41.1194), 4326)::geography, 'Peugeot', 'e-208', 'Peugeot e-208', 'car', 'standard_car', 3.00, 0.50, 28.00, 362, 'car-standard'),
  ('ST-402', 'car', 'available', 78, ST_SetSRID(ST_MakePoint(16.8777, 41.1211), 4326)::geography, 'Opel', 'Corsa Electric', 'Opel Corsa Electric', 'car', 'standard_car', 3.00, 0.50, 28.00, 354, 'car-standard'),
  ('ST-403', 'car', 'available', 66, ST_SetSRID(ST_MakePoint(16.8648, 41.1161), 4326)::geography, 'Volkswagen', 'ID.3', 'Volkswagen ID.3', 'car', 'standard_car', 3.00, 0.50, 28.00, 426, 'car-standard'),
  ('ST-404', 'car', 'available', 89, ST_SetSRID(ST_MakePoint(16.8691, 41.1210), 4326)::geography, 'Hyundai', 'Kona Electric', 'Hyundai Kona Electric', 'car', 'standard_car', 3.00, 0.50, 28.00, 514, 'car-standard'),
  ('PR-501', 'car', 'available', 92, ST_SetSRID(ST_MakePoint(16.8831, 41.1157), 4326)::geography, 'BMW', 'i4', 'BMW i4', 'car', 'premium_car', 5.00, 0.80, 45.00, 590, 'car-premium'),
  ('PR-502', 'car', 'available', 81, ST_SetSRID(ST_MakePoint(16.8627, 41.1192), 4326)::geography, 'BMW', 'iX1', 'BMW iX1', 'car', 'premium_car', 5.00, 0.80, 45.00, 438, 'car-premium'),
  ('PR-503', 'car', 'available', 74, ST_SetSRID(ST_MakePoint(16.8758, 41.1139), 4326)::geography, 'Tesla', 'Model 3', 'Tesla Model 3', 'car', 'premium_car', 5.00, 0.80, 45.00, 513, 'car-premium'),
  ('PR-504', 'car', 'available', 86, ST_SetSRID(ST_MakePoint(16.8668, 41.1134), 4326)::geography, 'Mercedes', 'EQA', 'Mercedes EQA', 'car', 'premium_car', 5.00, 0.80, 45.00, 560, 'car-premium')
ON CONFLICT (code) DO UPDATE
SET
  type = EXCLUDED.type,
  brand = EXCLUDED.brand,
  model = EXCLUDED.model,
  display_name = EXCLUDED.display_name,
  vehicle_type = EXCLUDED.vehicle_type,
  category = EXCLUDED.category,
  unlock_fee = EXCLUDED.unlock_fee,
  price_per_minute = EXCLUDED.price_per_minute,
  hourly_rate = EXCLUDED.hourly_rate,
  range_km = EXCLUDED.range_km,
  icon_type = EXCLUDED.icon_type,
  updated_at = now();
