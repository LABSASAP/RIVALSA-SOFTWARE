import { useEffect, useMemo, useRef } from "react"
import { divIcon, type Map as LeafletMap } from "leaflet"
import { Circle, CircleMarker, MapContainer, Marker, TileLayer, Tooltip, useMap, useMapEvents } from "react-leaflet"
import { Bike, CarFront, CircleDot, LocateFixed, Minus, Navigation, Plus, X } from "lucide-react"
import {
  BatteryMeter,
  StatusChip,
  VehicleCategoryLabel,
  VehicleDisplayName,
  VehicleModelLabel,
  VehiclePricingLabel,
  formatVehicleHourlyRate,
} from "@/components/vehicle-card"
import { Button } from "@/components/ui/button"
import { Spinner } from "@/components/ui/spinner"
import { cn } from "@/lib/utils"
import type { NearbyVehicle } from "@/lib/supabase"

export type MapCenter = {
  lat: number
  lng: number
}

export type VehicleFilter = "all" | NearbyVehicle["type"]

type VehicleMapProps = {
  center: MapCenter
  vehicles: NearbyVehicle[]
  radiusM: number
  loading: boolean
  filter: VehicleFilter
  selectedVehicleId: string | null
  onFilterChange: (filter: VehicleFilter) => void
  onCenterChange: (center: MapCenter, forceRefresh?: boolean) => void
  onUseMyLocation: () => void
  onSelectVehicle: (id: string | null) => void
  onOpenVehicle: (id: string) => void
}

type VehicleDetailCardProps = {
  vehicle: NearbyVehicle
  onClose?: () => void
  onOpenVehicle: (id: string) => void
  className?: string
}

const DEFAULT_TILE_URL = "https://tile.openstreetmap.org/{z}/{x}/{y}.png"
const DEFAULT_ATTRIBUTION = '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors'
const MOVE_DEBOUNCE_MS = 600
const CENTER_EPSILON = 0.00001

const tileUrl = (import.meta.env.VITE_MAP_TILE_URL as string | undefined)?.trim() || (import.meta.env.DEV ? DEFAULT_TILE_URL : "")
const tileAttribution = (import.meta.env.VITE_MAP_ATTRIBUTION as string | undefined)?.trim() || DEFAULT_ATTRIBUTION

const filterItems: Array<{ value: VehicleFilter; label: string }> = [
  { value: "all", label: "Tutti" },
  { value: "bike", label: "Bici" },
  { value: "scooter", label: "Mono" },
  { value: "car", label: "Auto" },
]

const markerLabels: Record<NearbyVehicle["type"], string> = {
  bike: "BI",
  scooter: "MO",
  car: "EV",
}

function createVehicleIcon(type: NearbyVehicle["type"], selected: boolean) {
  return divIcon({
    className: `vehicle-map-marker ${selected ? "vehicle-map-marker-selected" : ""}`,
    html: `<div class="vehicle-map-marker-inner vehicle-map-marker-${type}"><span>${markerLabels[type]}</span></div>`,
    iconSize: selected ? [58, 58] : [48, 48],
    iconAnchor: selected ? [29, 52] : [24, 43],
  })
}

function centersAreClose(a: MapCenter, b: MapCenter) {
  return Math.abs(a.lat - b.lat) < CENTER_EPSILON && Math.abs(a.lng - b.lng) < CENTER_EPSILON
}

function FilterIcon({ filter }: { filter: VehicleFilter }) {
  if (filter === "bike") return <Bike className="size-4" />
  if (filter === "scooter") return <CircleDot className="size-4" />
  if (filter === "car") return <CarFront className="size-4" />
  return <Navigation className="size-4" />
}

function MapCenterSync({ center }: { center: MapCenter }) {
  const map = useMap()

  useEffect(() => {
    const current = map.getCenter()
    const currentCenter = { lat: current.lat, lng: current.lng }

    if (!centersAreClose(currentCenter, center)) {
      map.setView([center.lat, center.lng], map.getZoom(), { animate: true })
    }
  }, [center.lat, center.lng, map])

  return null
}

function SelectedVehicleSync({ vehicle }: { vehicle: NearbyVehicle | null }) {
  const map = useMap()
  const vehicleId = vehicle?.id

  useEffect(() => {
    if (!vehicle) return
    map.flyTo([vehicle.lat, vehicle.lng], Math.max(map.getZoom(), 16), { animate: true, duration: 0.45 })
  }, [map, vehicle, vehicleId])

  return null
}

function MapViewportEvents({
  center,
  onCenterChange,
}: {
  center: MapCenter
  onCenterChange: (center: MapCenter, forceRefresh?: boolean) => void
}) {
  const timerRef = useRef<number | null>(null)
  const centerRef = useRef(center)

  useEffect(() => {
    centerRef.current = center
  }, [center])

  const scheduleReport = (map: LeafletMap, forceRefresh = false) => {
    if (timerRef.current !== null) {
      window.clearTimeout(timerRef.current)
    }

    timerRef.current = window.setTimeout(() => {
      const next = map.getCenter()
      const nextCenter = { lat: next.lat, lng: next.lng }

      if (!forceRefresh && centersAreClose(nextCenter, centerRef.current)) {
        return
      }

      onCenterChange(nextCenter, forceRefresh)
    }, MOVE_DEBOUNCE_MS)
  }

  useMapEvents({
    moveend(event) {
      scheduleReport(event.target, false)
    },
    zoomend(event) {
      scheduleReport(event.target, true)
    },
  })

  useEffect(() => {
    return () => {
      if (timerRef.current !== null) {
        window.clearTimeout(timerRef.current)
      }
    }
  }, [])

  return null
}

function MapZoomControls() {
  const map = useMap()

  return (
    <div className="vehicle-map-zoom">
      <button
        type="button"
        aria-label="Aumenta zoom"
        title="Aumenta zoom"
        onClick={(event) => {
          event.stopPropagation()
          map.zoomIn()
        }}
      >
        <Plus className="size-4" />
      </button>
      <button
        type="button"
        aria-label="Riduci zoom"
        title="Riduci zoom"
        onClick={(event) => {
          event.stopPropagation()
          map.zoomOut()
        }}
      >
        <Minus className="size-4" />
      </button>
    </div>
  )
}

export function VehicleDetailCard({ vehicle, onClose, onOpenVehicle, className }: VehicleDetailCardProps) {
  return (
    <div className={cn("vehicle-selection-card", className)}>
      <div className="flex items-start justify-between gap-3">
        <div>
          <p className="label-sm text-[var(--muted-foreground)]">{vehicle.code}</p>
          <h3 className="mt-1 font-display text-xl font-extrabold leading-tight">
            {VehicleDisplayName(vehicle)}
          </h3>
          <p className="mt-1 text-sm font-semibold text-[var(--muted-foreground)]">{VehicleModelLabel(vehicle)}</p>
        </div>
        <div className="flex items-center gap-2">
          <StatusChip status={vehicle.status} />
          {onClose && (
            <button
              type="button"
              aria-label="Chiudi dettaglio mezzo"
              className="vehicle-selection-close"
              onClick={onClose}
            >
              <X className="size-4" />
            </button>
          )}
        </div>
      </div>

      <div className="mt-4 rounded-3xl bg-[var(--surface-low)] p-4">
        <BatteryMeter level={vehicle.battery_level} />
      </div>

      <div className="mt-4 grid grid-cols-2 gap-2">
        <div className="vehicle-selection-field">
          <span>Categoria</span>
          <strong>{VehicleCategoryLabel(vehicle)}</strong>
        </div>
        <div className="vehicle-selection-field">
          <span>Distanza</span>
          <strong>{Math.round(vehicle.distance_m)} m</strong>
        </div>
        <div className="vehicle-selection-field">
          <span>Tariffa</span>
          <strong>{VehiclePricingLabel(vehicle)}</strong>
        </div>
        <div className="vehicle-selection-field">
          <span>Oraria</span>
          <strong>{formatVehicleHourlyRate(vehicle.hourly_rate)}</strong>
        </div>
        <div className="vehicle-selection-field">
          <span>Autonomia</span>
          <strong>{vehicle.range_km ? `${vehicle.range_km} km` : "n/d"}</strong>
        </div>
        <div className="vehicle-selection-field">
          <span>Coordinate</span>
          <strong>{vehicle.lat.toFixed(4)}, {vehicle.lng.toFixed(4)}</strong>
        </div>
      </div>

      <Button
        type="button"
        onClick={() => onOpenVehicle(vehicle.id)}
        className="mt-4 h-12 w-full rounded-2xl btn-primary-grad font-bold text-base"
      >
        Vedi dettaglio
      </Button>
    </div>
  )
}

export function VehicleMap({
  center,
  vehicles,
  radiusM,
  loading,
  filter,
  selectedVehicleId,
  onFilterChange,
  onCenterChange,
  onUseMyLocation,
  onSelectVehicle,
  onOpenVehicle,
}: VehicleMapProps) {
  const mapCenter = useMemo<[number, number]>(() => [center.lat, center.lng], [center.lat, center.lng])
  const selectedVehicle = vehicles.find((vehicle) => vehicle.id === selectedVehicleId) ?? null

  if (!tileUrl) {
    return (
      <div className="mb-5 rounded-3xl bg-[var(--surface-low)] p-5">
        <div className="rounded-3xl bg-[var(--surface-lowest)] p-5 text-center shadow-[0_12px_32px_rgba(25,28,29,0.04)]">
          <p className="label-sm text-[var(--muted-foreground)]">MAPPA</p>
          <h2 className="mt-1 text-xl font-extrabold">Mappa non configurata</h2>
          <p className="mt-2 text-sm leading-relaxed text-[var(--muted-foreground)]">
            Imposta VITE_MAP_TILE_URL per abilitare le tile in produzione.
          </p>
        </div>
      </div>
    )
  }

  return (
    <section className="vehicle-map">
      <div className="vehicle-map-frame">
        <MapContainer
          center={mapCenter}
          zoom={15}
          minZoom={12}
          maxZoom={19}
          scrollWheelZoom
          zoomControl={false}
          className="h-full w-full"
        >
          <TileLayer attribution={tileAttribution} url={tileUrl} />
          <Circle
            center={mapCenter}
            radius={radiusM}
            pathOptions={{
              color: "#0040a1",
              fillColor: "#0056d2",
              fillOpacity: 0.05,
              opacity: 0.16,
              weight: 2,
            }}
          />
          <CircleMarker
            center={mapCenter}
            radius={8}
            pathOptions={{
              color: "#ffffff",
              fillColor: "#0040a1",
              fillOpacity: 1,
              opacity: 0.86,
              weight: 5,
            }}
          />
          {vehicles.map((vehicle) => {
            const selected = vehicle.id === selectedVehicleId

            return (
              <Marker
                key={`${vehicle.id}-${selected ? "selected" : "idle"}`}
                position={[vehicle.lat, vehicle.lng]}
                icon={createVehicleIcon(vehicle.vehicle_type ?? vehicle.type, selected)}
                title={VehicleDisplayName(vehicle)}
                zIndexOffset={selected ? 1000 : 0}
                eventHandlers={{
                  click: () => onSelectVehicle(vehicle.id),
                }}
              >
                <Tooltip direction="top" offset={[0, -34]} opacity={0.95}>
                  {VehicleDisplayName(vehicle)}
                </Tooltip>
              </Marker>
            )
          })}
          <MapCenterSync center={center} />
          <SelectedVehicleSync vehicle={selectedVehicle} />
          <MapViewportEvents center={center} onCenterChange={onCenterChange} />
          <MapZoomControls />
        </MapContainer>

        <div className="vehicle-map-topbar">
          <div className="vehicle-map-filter-bar" aria-label="Filtra veicoli">
            {filterItems.map((item) => (
              <button
                key={item.value}
                type="button"
                className={cn("vehicle-map-filter-chip", filter === item.value && "vehicle-map-filter-chip-active")}
                onClick={() => onFilterChange(item.value)}
              >
                <FilterIcon filter={item.value} />
                <span>{item.label}</span>
              </button>
            ))}
          </div>

          <button
            type="button"
            aria-label="Usa la mia posizione"
            title="Usa la mia posizione"
            className="vehicle-map-round-control"
            onClick={onUseMyLocation}
          >
            <LocateFixed className="size-5" />
          </button>
        </div>

        <div className="vehicle-map-count-pill">
          {loading ? <Spinner className="size-4" /> : <Navigation className="size-4 text-[var(--primary)]" />}
          <span>{vehicles.length}</span>
          <span className="text-[var(--muted-foreground)]">disponibili</span>
        </div>
      </div>

      {selectedVehicle && (
        <div className="vehicle-map-mobile-sheet md:hidden">
          <VehicleDetailCard
            vehicle={selectedVehicle}
            onClose={() => onSelectVehicle(null)}
            onOpenVehicle={onOpenVehicle}
          />
        </div>
      )}
    </section>
  )
}
