import type { NearbyVehicle, Vehicle } from "@/lib/supabase"

type ShareVehicleLike = (Vehicle | NearbyVehicle) & {
  lat?: number
  lng?: number
}

export function buildVehicleShareText(vehicle: ShareVehicleLike, detailUrl?: string) {
  const type = vehicle.vehicle_type ?? vehicle.type
  const position = vehicle.lat != null && vehicle.lng != null
    ? ` vicino a ${vehicle.lat.toFixed(4)}, ${vehicle.lng.toFixed(4)}`
    : ""
  const tariff = `${Number(vehicle.price_per_minute).toFixed(2)} EUR/min`
  const range = vehicle.range_km ? `, autonomia ${vehicle.range_km} km` : ""
  const link = detailUrl ? ` Link: ${detailUrl}` : ""

  return `Ho trovato questo mezzo su ZooSmart: ${vehicle.display_name || vehicle.code}, ${type}, categoria ${vehicle.category}, batteria ${vehicle.battery_level}%, tariffa ${tariff}${range}, disponibile${position}.${link}`
}

export async function copyText(value: string) {
  if (navigator.clipboard?.writeText) {
    await navigator.clipboard.writeText(value)
    return true
  }

  const textarea = document.createElement("textarea")
  textarea.value = value
  textarea.setAttribute("readonly", "true")
  textarea.style.position = "fixed"
  textarea.style.left = "-9999px"
  document.body.appendChild(textarea)
  textarea.select()
  const ok = document.execCommand("copy")
  document.body.removeChild(textarea)
  return ok
}

export async function copyVehicleDetails(vehicle: ShareVehicleLike, detailUrl?: string) {
  return copyText(buildVehicleShareText(vehicle, detailUrl))
}
