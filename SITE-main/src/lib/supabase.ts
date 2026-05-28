import { createClient } from "@supabase/supabase-js"

const url = import.meta.env.VITE_SUPABASE_URL as string
const key = import.meta.env.VITE_SUPABASE_ANON_KEY as string

if (!url || !key) {
  throw new Error("Missing VITE_SUPABASE_URL or VITE_SUPABASE_ANON_KEY")
}

export const supabase = createClient(url, key, {
  auth: {
    persistSession: true,
    autoRefreshToken: true,
    detectSessionInUrl: false,
  },
})

export type Role = "user" | "operator" | "public_admin"

export type Profile = {
  id: string
  email: string
  display_name: string
  role: Role
  status: "active" | "suspended" | "blocked"
  created_at: string
  updated_at: string
}

export type VehicleType = "bike" | "scooter" | "car"
export type VehicleCategory = "bike" | "scooter" | "economy_car" | "standard_car" | "premium_car"

export type Vehicle = {
  id: string
  code: string
  type: VehicleType
  vehicle_type: VehicleType
  category: VehicleCategory
  brand: string
  model: string
  display_name: string
  status: "available" | "reserved" | "in_use" | "maintenance"
  battery_level: number
  unlock_fee: number
  price_per_minute: number
  hourly_rate: number
  range_km: number | null
  icon_type: string
  is_remote_locked?: boolean
  remote_lock_reason?: string | null
  remote_locked_at?: string | null
  remote_locked_by?: string | null
  location?: unknown
  last_maintenance_at?: string | null
  operator_notes?: string | null
  created_at: string
  updated_at: string
}

export type NearbyVehicle = {
  id: string
  code: string
  type: VehicleType
  vehicle_type: VehicleType
  category: VehicleCategory
  brand: string
  model: string
  display_name: string
  status: Vehicle["status"]
  battery_level: number
  unlock_fee: number
  price_per_minute: number
  hourly_rate: number
  range_km: number | null
  icon_type: string
  is_remote_locked?: boolean
  remote_lock_reason?: string | null
  lat: number
  lng: number
  distance_m: number
}

export type Reservation = {
  id: string
  user_id: string
  vehicle_id: string
  status: "active" | "expired" | "cancelled" | "converted_to_ride"
  created_at: string
  expires_at: string
  converted_ride_id: string | null
}

export type Ride = {
  id: string
  user_id: string
  vehicle_id: string
  reservation_id: string
  started_at: string
  ended_at: string | null
  duration_minutes: number | null
  original_cost?: number | null
  credit_discount?: number | null
  final_cost: number | null
  status: "active" | "completed"
  paused_at?: string | null
  total_paused_seconds?: number
  pause_status?: "active" | "paused"
}

export type RideEndDetails = {
  ride_id: string
  vehicle_id: string
  vehicle_code: string
  vehicle_type: VehicleType
  vehicle_brand: string
  vehicle_model: string
  vehicle_display_name: string
  vehicle_category: VehicleCategory
  unlock_fee: number
  price_per_minute: number
  hourly_rate: number
  ended_at: string
  duration_minutes: number | null
  original_cost?: number | null
  credit_discount?: number | null
  final_cost: number | null
  total_paused_seconds?: number | null
  end_lat: number | null
  end_lng: number | null
}

export type PaymentMethod = {
  id: string
  user_id: string
  type: "card" | "paypal" | "apple_pay"
  last4: string
  is_default: boolean
  created_at: string
}

export type VehicleReport = {
  id: string
  user_id: string
  vehicle_id: string
  issue_type: string
  description: string
  status: "open" | "in_progress" | "resolved"
  created_at: string
  updated_at: string
}

export type UrbanZone = {
  id: string
  name: string
  description: string
  type: "road_work" | "restricted_area" | "sensitive_zone"
  status: "active" | "inactive"
  center_lat: number
  center_lng: number
  radius_meters: number
  starts_at: string | null
  ends_at: string | null
  created_by_user_id: string | null
  created_at: string
  updated_at: string
}

export type CreditWallet = {
  id: string
  user_id: string
  points_balance: number
  credit_amount: number
  created_at: string
  updated_at: string
}

export type CreditTransaction = {
  id: string
  user_id: string
  ride_id: string | null
  type: "earned" | "redeemed"
  points: number
  amount: number
  description: string
  created_at: string
}

export type SupportTicket = {
  id: string
  user_id: string
  assigned_operator_id: string | null
  subject: string
  status: "open" | "in_progress" | "resolved" | "closed"
  created_at: string
  updated_at: string
}

export type SupportMessage = {
  id: string
  ticket_id: string
  sender_id: string
  sender_role: "user" | "operator"
  message: string
  created_at: string
}

export type RidePosition = {
  id: string
  ride_id: string
  vehicle_id: string
  lat: number
  lng: number
  recorded_at: string
}

export type FleetVehicle = Vehicle & {
  lat: number
  lng: number
  updated_at: string
}

export type OperatorFleetDistributionVehicle = {
  id: string
  code: string
  type: VehicleType
  vehicle_type: VehicleType
  category: VehicleCategory
  brand: string
  model: string
  display_name: string
  status: Vehicle["status"]
  battery_level: number
  range_km: number | null
  icon_type: string
  is_remote_locked: boolean
  remote_lock_reason: string | null
  remote_locked_at: string | null
  operator_notes: string | null
  last_maintenance_at: string | null
  lat: number
  lng: number
  updated_at: string
  open_reports_count: number
  active_ride_id: string | null
}

export type ZoneAvailability = {
  zone_id: string
  area_name: string
  zone_type: UrbanZone["type"]
  available_count: number
  total_count: number
  severity: "ok" | "warning" | "critical"
}

export type OperatorLowAvailabilityAlert = {
  area_id: string
  area_name: string
  area_type: UrbanZone["type"]
  center_lat: number
  center_lng: number
  radius_meters: number
  available_vehicles: number
  total_vehicles: number
  low_battery_vehicles: number
  maintenance_vehicles: number
  in_use_vehicles: number
  threshold: number
  severity: "ok" | "warning" | "critical"
  message: string
}

export type OperatorMaintenanceVehicle = {
  id: string
  code: string
  type: VehicleType
  vehicle_type: VehicleType
  category: VehicleCategory
  brand: string
  model: string
  display_name: string
  status: Vehicle["status"]
  battery_level: number
  is_remote_locked: boolean
  remote_lock_reason: string | null
  last_maintenance_at: string | null
  operator_notes: string | null
  lat: number
  lng: number
  open_reports_count: number
  days_since_maintenance: number | null
  priority: "critical" | "high" | "medium" | "low"
  reasons: string[]
}

export type OperatorRideTracking = {
  ride_id: string
  vehicle_id: string
  vehicle_code: string
  user_name: string
  ride_status: Ride["status"]
  lat: number
  lng: number
  recorded_at: string
  stale_minutes?: number
  position_count?: number
}

export type OperatorActiveRide = {
  ride_id: string
  vehicle_id: string
  vehicle_code: string
  vehicle_display_name: string
  user_id: string
  user_name: string
  ride_status: Ride["status"]
  pause_status: "active" | "paused"
  started_at: string
  lat: number
  lng: number
  recorded_at: string
  stale_minutes: number
  position_count: number
}

export type OperatorRidePosition = RidePosition

export type OperatorParkingBonus = {
  id: string
  user_id: string
  user_name: string
  user_email: string
  ride_id: string
  vehicle_id: string | null
  vehicle_code: string | null
  vehicle_display_name: string | null
  points: number
  amount: number
  description: string
  created_at: string
}

export type OperatorSupportTicket = SupportTicket & {
  user_name: string
  user_email: string
  message_count: number
  last_message_at: string | null
}

export type PublicAdminVehicleUsage = {
  vehicle_type: VehicleType
  category: VehicleCategory
  rides_count: number
  percentage: number
}

export type PublicAdminDailyRide = {
  day: string
  ride_count: number
}

export type PublicAdminHourlyUsage = {
  hour: string
  ride_count: number
}

export type PublicAdminCategoryUsage = {
  vehicle_type: VehicleType
  category: VehicleCategory
  ride_count: number
  percentage: number
}

export type PublicAdminMobilityReport = {
  period: {
    from: string | null
    to: string | null
  }
  rides_total: number
  rides_active: number
  rides_completed: number
  revenue_total: number
  avg_duration_minutes: number
  avg_distance_km: number
  avg_cost: number
  active_users: number
  vehicles_used: number
  hourly_usage: PublicAdminHourlyUsage[]
  category_usage: PublicAdminCategoryUsage[]
  daily_rides: PublicAdminDailyRide[]
}

export type PublicAdminFleetStatus = {
  fleet_total: number
  available_count: number
  in_use_count: number
  reserved_count: number
  maintenance_count: number
  remote_locked_count: number
  avg_battery_level: number
  low_battery_percentage: number
  operational_percentage: number
  open_reports_count: number
  fleet_by_status: Array<{ status: string; count: number }>
  battery_by_category: Array<{ category: VehicleCategory; avg_battery_level: number; vehicle_count: number }>
}

export type PublicAdminRoute = {
  route_label: string
  ride_count: number
  start_lat: number
  start_lng: number
  end_lat: number
  end_lng: number
  dominant_category: VehicleCategory
  avg_duration_minutes: number
  avg_cost: number
  avg_distance_km: number
}

export type PublicAdminReport = PublicAdminMobilityReport
