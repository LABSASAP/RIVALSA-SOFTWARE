import type { UrbanZone } from "@/lib/supabase"

export type LatLng = {
  lat: number
  lng: number
}

export type PlannedRoute = {
  distanceKm: number
  durationMinutes: number
  polyline: LatLng[]
  avoidedZones: UrbanZone[]
  isSimulated: boolean
}

const routeApiUrl = (import.meta.env.VITE_ROUTE_API_URL as string | undefined)?.trim()
const routeApiKey = (import.meta.env.VITE_ROUTE_API_KEY as string | undefined)?.trim()

const AVOIDED_ZONE_TYPES: UrbanZone["type"][] = ["road_work", "restricted_area", "sensitive_zone"]
const FALLBACK_SPEED_KMH = 18
const DETOUR_PADDING_M = 180

export function haversineDistanceKm(a: LatLng, b: LatLng) {
  const earthKm = 6371
  const dLat = toRad(b.lat - a.lat)
  const dLng = toRad(b.lng - a.lng)
  const lat1 = toRad(a.lat)
  const lat2 = toRad(b.lat)
  const h =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(lat1) * Math.cos(lat2) * Math.sin(dLng / 2) ** 2
  return 2 * earthKm * Math.asin(Math.sqrt(h))
}

export function routeDistanceKm(points: LatLng[]) {
  return points.reduce((total, point, index) => {
    if (index === 0) return total
    return total + haversineDistanceKm(points[index - 1], point)
  }, 0)
}

export function estimateDurationMinutes(distanceKm: number, speedKmh = FALLBACK_SPEED_KMH) {
  return Math.max(1, Math.ceil((distanceKm / speedKmh) * 60))
}

export function criticalZones(zones: UrbanZone[]) {
  const now = Date.now()
  return zones.filter((zone) => {
    if (zone.status !== "active" || !AVOIDED_ZONE_TYPES.includes(zone.type)) return false
    const starts = zone.starts_at ? new Date(zone.starts_at).getTime() : null
    const ends = zone.ends_at ? new Date(zone.ends_at).getTime() : null
    return (starts == null || starts <= now) && (ends == null || ends >= now)
  })
}

export function segmentIntersectsZone(start: LatLng, end: LatLng, zone: UrbanZone) {
  const center = { lat: zone.center_lat, lng: zone.center_lng }
  const distanceM = distancePointToSegmentMeters(center, start, end)
  return distanceM <= zone.radius_meters + 40
}

export function routeIntersectsZone(polyline: LatLng[], zone: UrbanZone) {
  return polyline.some((point, index) => {
    if (index === 0) return false
    return segmentIntersectsZone(polyline[index - 1], point, zone)
  })
}

export async function planBestRoute(start: LatLng, end: LatLng, zones: UrbanZone[]): Promise<PlannedRoute> {
  const relevantZones = criticalZones(zones)

  if (routeApiUrl) {
    const providerRoute = await fetchProviderRoute(start, end, relevantZones).catch(() => null)
    if (providerRoute) return providerRoute
  }

  return buildSimulatedRoute(start, end, relevantZones)
}

export function buildSimulatedRoute(start: LatLng, end: LatLng, zones: UrbanZone[]): PlannedRoute {
  const avoidedZones = zones.filter((zone) => segmentIntersectsZone(start, end, zone))
  const detours = avoidedZones.map((zone) => detourPoint(start, end, zone))
  const polyline = [start, ...detours, end]
  const distanceKm = routeDistanceKm(polyline)

  return {
    distanceKm,
    durationMinutes: estimateDurationMinutes(distanceKm),
    polyline,
    avoidedZones,
    isSimulated: true,
  }
}

async function fetchProviderRoute(start: LatLng, end: LatLng, zones: UrbanZone[]): Promise<PlannedRoute | null> {
  const headers: Record<string, string> = { "Content-Type": "application/json" }
  if (routeApiKey) headers.Authorization = routeApiKey.startsWith("Bearer ") ? routeApiKey : `Bearer ${routeApiKey}`

  const response = await fetch(routeApiUrl!, {
    method: "POST",
    headers,
    body: JSON.stringify({
      startLat: start.lat,
      startLng: start.lng,
      endLat: end.lat,
      endLng: end.lng,
      avoidZones: zones.map((zone) => ({
        id: zone.id,
        type: zone.type,
        centerLat: zone.center_lat,
        centerLng: zone.center_lng,
        radiusMeters: zone.radius_meters,
      })),
    }),
  })

  if (!response.ok) return null
  const payload = await response.json()
  const parsed = parseProviderPayload(payload)
  if (!parsed) return null

  const directBlockedZones = zones.filter((zone) => segmentIntersectsZone(start, end, zone))
  const avoidedZones = directBlockedZones.filter((zone) => !routeIntersectsZone(parsed.polyline, zone))

  return {
    ...parsed,
    avoidedZones,
    isSimulated: false,
  }
}

function parseProviderPayload(payload: unknown): Omit<PlannedRoute, "avoidedZones" | "isSimulated"> | null {
  const data = payload as {
    distanceKm?: number
    durationMinutes?: number
    polyline?: LatLng[]
    routes?: Array<{ distance?: number; duration?: number; geometry?: { coordinates?: [number, number][] } }>
    features?: Array<{ properties?: { summary?: { distance?: number; duration?: number } }; geometry?: { coordinates?: [number, number][] } }>
  }

  if (Array.isArray(data.polyline) && Number.isFinite(data.distanceKm) && Number.isFinite(data.durationMinutes)) {
    return {
      distanceKm: Number(data.distanceKm),
      durationMinutes: Number(data.durationMinutes),
      polyline: data.polyline,
    }
  }

  const osrm = data.routes?.[0]
  if (osrm?.geometry?.coordinates?.length) {
    const distanceKm = Number(osrm.distance ?? 0) / 1000
    return {
      distanceKm,
      durationMinutes: Math.max(1, Math.ceil(Number(osrm.duration ?? 0) / 60)),
      polyline: osrm.geometry.coordinates.map(([lng, lat]) => ({ lat, lng })),
    }
  }

  const ors = data.features?.[0]
  if (ors?.geometry?.coordinates?.length) {
    const distanceKm = Number(ors.properties?.summary?.distance ?? 0) / 1000
    return {
      distanceKm,
      durationMinutes: Math.max(1, Math.ceil(Number(ors.properties?.summary?.duration ?? 0) / 60)),
      polyline: ors.geometry.coordinates.map(([lng, lat]) => ({ lat, lng })),
    }
  }

  return null
}

function detourPoint(start: LatLng, end: LatLng, zone: UrbanZone): LatLng {
  const midLat = (start.lat + end.lat) / 2
  const dx = (end.lng - start.lng) * Math.cos(toRad(midLat))
  const dy = end.lat - start.lat
  const length = Math.hypot(dx, dy) || 1
  const normalX = -dy / length
  const normalY = dx / length
  const offsetKm = (zone.radius_meters + DETOUR_PADDING_M) / 1000
  const latOffset = (normalY * offsetKm) / 111
  const lngOffset = (normalX * offsetKm) / (111 * Math.cos(toRad(zone.center_lat)) || 1)

  return {
    lat: zone.center_lat + latOffset,
    lng: zone.center_lng + lngOffset,
  }
}

function distancePointToSegmentMeters(point: LatLng, start: LatLng, end: LatLng) {
  const originLat = toRad(point.lat)
  const metersPerDegLat = 111_320
  const metersPerDegLng = 111_320 * Math.cos(originLat)
  const px = point.lng * metersPerDegLng
  const py = point.lat * metersPerDegLat
  const ax = start.lng * metersPerDegLng
  const ay = start.lat * metersPerDegLat
  const bx = end.lng * metersPerDegLng
  const by = end.lat * metersPerDegLat
  const abx = bx - ax
  const aby = by - ay
  const abLen2 = abx * abx + aby * aby
  const t = abLen2 === 0 ? 0 : Math.max(0, Math.min(1, ((px - ax) * abx + (py - ay) * aby) / abLen2))
  const closestX = ax + t * abx
  const closestY = ay + t * aby
  return Math.hypot(px - closestX, py - closestY)
}

function toRad(value: number) {
  return (value * Math.PI) / 180
}
