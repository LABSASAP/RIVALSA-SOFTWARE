import type { NearbyVehicle, UrbanZone, VehicleCategory, VehicleType } from "@/lib/supabase"
import {
  criticalZones,
  estimateDurationMinutes,
  haversineDistanceKm,
  routeIntersectsZone,
  type LatLng,
  type PlannedRoute,
} from "@/lib/route-planning"

export type VehicleSuggestion = {
  suggestedVehicle: NearbyVehicle | null
  reason: string
  estimatedCost: number
  estimatedDurationMinutes: number
  estimatedDistanceKm: number
  alternatives: VehicleSuggestionAlternative[]
}

export type VehicleSuggestionAlternative = {
  vehicle: NearbyVehicle
  reason: string
  estimatedCost: number
  estimatedDurationMinutes: number
  estimatedDistanceKm: number
  score: number
}

const SPEED_BY_TYPE: Record<VehicleType, number> = {
  bike: 14,
  scooter: 18,
  car: 26,
}

const CATEGORY_WEIGHT: Record<VehicleCategory, number> = {
  bike: 4,
  scooter: 3,
  economy_car: 1,
  standard_car: 2,
  premium_car: 5,
}

export function suggestVehicleForTrip({
  start,
  end,
  vehicles,
  zones,
  route,
}: {
  start: LatLng
  end: LatLng
  vehicles: NearbyVehicle[]
  zones: UrbanZone[]
  route: PlannedRoute | null
}): VehicleSuggestion {
  const directRouteDistanceKm = route?.distanceKm ?? haversineDistanceKm(start, end)
  const eligibleVehicles = vehicles.filter((vehicle) => vehicle.status === "available" && !vehicle.is_remote_locked)
  const activeCriticalZones = criticalZones(zones)
  const ranked = eligibleVehicles
    .map((vehicle) => scoreVehicle(vehicle, start, end, activeCriticalZones, directRouteDistanceKm))
    .filter((item): item is VehicleSuggestionAlternative => item !== null)
    .sort((a, b) => a.score - b.score)

  const best = ranked[0] ?? null
  return {
    suggestedVehicle: best?.vehicle ?? null,
    reason: best?.reason ?? "Nessun mezzo disponibile ha autonomia sufficiente per questa destinazione.",
    estimatedCost: best?.estimatedCost ?? 0,
    estimatedDurationMinutes: best?.estimatedDurationMinutes ?? route?.durationMinutes ?? estimateDurationMinutes(directRouteDistanceKm),
    estimatedDistanceKm: best?.estimatedDistanceKm ?? directRouteDistanceKm,
    alternatives: ranked.slice(1, 4),
  }
}

function scoreVehicle(
  vehicle: NearbyVehicle,
  start: LatLng,
  end: LatLng,
  zones: UrbanZone[],
  tripDistanceKm: number
): VehicleSuggestionAlternative | null {
  const pickupDistanceKm = haversineDistanceKm(start, { lat: vehicle.lat, lng: vehicle.lng })
  const vehicleToDestinationKm = haversineDistanceKm({ lat: vehicle.lat, lng: vehicle.lng }, end)
  const totalDistanceKm = pickupDistanceKm + Math.max(tripDistanceKm, vehicleToDestinationKm)
  const autonomyKm = Math.max(0, vehicle.range_km ?? estimateRangeFromBattery(vehicle))
  const batteryRangeKm = autonomyKm * (vehicle.battery_level / 100)
  const requiredKm = totalDistanceKm * 1.2

  if (batteryRangeKm < requiredKm) return null

  const speed = SPEED_BY_TYPE[vehicle.vehicle_type ?? vehicle.type]
  const estimatedDurationMinutes = estimateDurationMinutes(totalDistanceKm, speed)
  const estimatedCost = Number((vehicle.unlock_fee + estimatedDurationMinutes * vehicle.price_per_minute).toFixed(2))
  const blockedZonePenalty = zones.some((zone) =>
    routeIntersectsZone([
      { lat: vehicle.lat, lng: vehicle.lng },
      end,
    ], zone)
  ) ? 4 : 0
  const reserveFactor = Math.max(0, batteryRangeKm - requiredKm)
  const categoryPenalty = CATEGORY_WEIGHT[vehicle.category] ?? 3
  const score =
    estimatedCost * 9 +
    estimatedDurationMinutes * 0.8 +
    pickupDistanceKm * 4 +
    blockedZonePenalty +
    categoryPenalty -
    Math.min(reserveFactor, 20) * 0.08

  const reason = buildReason(vehicle, estimatedCost, totalDistanceKm, estimatedDurationMinutes, pickupDistanceKm, reserveFactor, blockedZonePenalty > 0)

  return {
    vehicle,
    reason,
    estimatedCost,
    estimatedDurationMinutes,
    estimatedDistanceKm: Number(totalDistanceKm.toFixed(2)),
    score,
  }
}

function buildReason(
  vehicle: NearbyVehicle,
  estimatedCost: number,
  distanceKm: number,
  durationMinutes: number,
  pickupDistanceKm: number,
  reserveKm: number,
  crossesZone: boolean
) {
  const zoneText = crossesZone
    ? "richiede attenzione per le zone urbane attive"
    : "consente di evitare le zone critiche note"
  const convenience = vehicle.category === "premium_car"
    ? "resta adeguato se preferisci comfort e autonomia"
    : "ha un costo stimato competitivo"

  return `Consigliato per ${distanceKm.toFixed(1)} km: ${convenience}, autonomia sufficiente con circa ${Math.max(0, reserveKm).toFixed(0)} km di margine, mezzo a ${Math.round(pickupDistanceKm * 1000)} m e tempo stimato ${durationMinutes} min; ${zoneText}. Costo stimato ${estimatedCost.toFixed(2)} EUR.`
}

function estimateRangeFromBattery(vehicle: NearbyVehicle) {
  if (vehicle.type === "bike") return 70
  if (vehicle.type === "scooter") return 35
  return 220
}
