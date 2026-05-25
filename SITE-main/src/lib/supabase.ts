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

export type Profile = {
  id: string
  email: string
  display_name: string
  role: "user" | "operator"
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
  final_cost: number | null
  status: "active" | "completed"
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
  final_cost: number | null
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
