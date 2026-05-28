import { useEffect, useMemo, useRef, useState } from "react"
import { Link, useNavigate } from "react-router-dom"
import { Bike, CarFront, ChevronRight, CircleDot, Copy, MapPinned, Route, Sparkles } from "lucide-react"
import { toast } from "sonner"
import { AppShell } from "@/components/app-shell"
import { VehicleDetailCard, VehicleMap, type MapCenter, type VehicleFilter } from "@/components/vehicle-map"
import {
  BatteryBar,
  StatusChip,
  TonalCard,
  VehicleCategoryLabel,
  VehicleDisplayName,
  VehicleIconType,
  VehicleModelLabel,
  VehiclePricingLabel,
} from "@/components/vehicle-card"
import { Button } from "@/components/ui/button"
import { Spinner } from "@/components/ui/spinner"
import { supabase, type NearbyVehicle, type Reservation, type UrbanZone } from "@/lib/supabase"
import { useAuth } from "@/lib/auth-context"
import { cn } from "@/lib/utils"
import { copyVehicleDetails } from "@/lib/share-vehicle"
import { criticalZones, haversineDistanceKm, planBestRoute, routeIntersectsZone, type LatLng, type PlannedRoute } from "@/lib/route-planning"
import { suggestVehicleForTrip } from "@/lib/vehicle-suggestion"

const DEFAULT_LAT = 41.1175
const DEFAULT_LNG = 16.872
const DEFAULT_RADIUS = 5000

export function NearbyPage() {
  const { profile } = useAuth()
  const navigate = useNavigate()
  const [lat, setLat] = useState(DEFAULT_LAT)
  const [lng, setLng] = useState(DEFAULT_LNG)
  const [vehicles, setVehicles] = useState<NearbyVehicle[]>([])
  const [filter, setFilter] = useState<VehicleFilter>("all")
  const [selectedVehicleId, setSelectedVehicleId] = useState<string | null>(null)
  const [loading, setLoading] = useState(true)
  const [activeReservation, setActiveReservation] = useState<Reservation | null>(null)
  const [zones, setZones] = useState<UrbanZone[]>([])
  const [destinationLat, setDestinationLat] = useState("")
  const [destinationLng, setDestinationLng] = useState("")
  const [destination, setDestination] = useState<LatLng | null>(null)
  const [plannedRoute, setPlannedRoute] = useState<PlannedRoute | null>(null)
  const [routeLoading, setRouteLoading] = useState(false)
  const [suggestionLoadingId, setSuggestionLoadingId] = useState<string | null>(null)
  const loadSeq = useRef(0)

  const filteredVehicles = useMemo(() => {
    if (filter === "all") return vehicles
    return vehicles.filter((vehicle) => VehicleIconType(vehicle) === filter)
  }, [filter, vehicles])

  const selectedVehicle = filteredVehicles.find((vehicle) => vehicle.id === selectedVehicleId) ?? null
  const mobilityCriticalZones = useMemo(
    () => criticalZones(zones).filter((zone) => zone.type === "restricted_area" || zone.type === "sensitive_zone"),
    [zones]
  )
  const routeZoneAlerts = useMemo(() => {
    if (!plannedRoute) return []
    return mobilityCriticalZones
      .map((zone) => ({
        zone,
        status: plannedRoute.avoidedZones.some((item) => item.id === zone.id)
          ? "evitata"
          : routeIntersectsZone(plannedRoute.polyline, zone)
          ? "vicina al percorso"
          : null,
      }))
      .filter((item): item is { zone: UrbanZone; status: string } => item.status !== null)
  }, [mobilityCriticalZones, plannedRoute])
  const selectedVehicleZoneAlerts = useMemo(() => {
    if (!selectedVehicle) return []
    return mobilityCriticalZones.filter((zone) => {
      const meters = haversineDistanceKm(
        { lat: selectedVehicle.lat, lng: selectedVehicle.lng },
        { lat: zone.center_lat, lng: zone.center_lng }
      ) * 1000
      return meters <= zone.radius_meters + 150
    })
  }, [mobilityCriticalZones, selectedVehicle])
  const tripSuggestion = useMemo(() => {
    if (!destination) return null
    return suggestVehicleForTrip({
      start: { lat, lng },
      end: destination,
      vehicles,
      zones,
      route: plannedRoute,
    })
  }, [destination, lat, lng, plannedRoute, vehicles, zones])

  const load = async (targetLat = lat, targetLng = lng) => {
    const seq = ++loadSeq.current
    setLoading(true)
    await supabase.rpc("reservation_expire_stale")
    const [{ data }, resQ, zoneQ] = await Promise.all([
      supabase.rpc("vehicles_nearby", { p_lat: targetLat, p_lng: targetLng, p_radius: DEFAULT_RADIUS }),
      supabase.from("reservations").select("*").eq("status", "active").order("created_at", { ascending: false }).limit(1).maybeSingle(),
      supabase.from("urban_zones").select("*").eq("status", "active").order("starts_at", { ascending: true }),
    ])

    if (seq !== loadSeq.current) return

    setVehicles((data as NearbyVehicle[]) ?? [])
    setActiveReservation((resQ.data as Reservation) ?? null)
    setZones((zoneQ.data as UrbanZone[]) ?? [])
    setLoading(false)
  }

  useEffect(() => {
    void load()
  }, [lat, lng])

  useEffect(() => {
    if (!selectedVehicleId) return
    if (!filteredVehicles.some((vehicle) => vehicle.id === selectedVehicleId)) {
      setSelectedVehicleId(null)
    }
  }, [filteredVehicles, selectedVehicleId])

  const updateSearchCenter = (center: MapCenter, forceRefresh = false) => {
    const changed = Math.abs(center.lat - lat) > 0.00001 || Math.abs(center.lng - lng) > 0.00001

    if (changed) {
      setLat(center.lat)
      setLng(center.lng)
      return
    }

    if (forceRefresh) {
      void load(center.lat, center.lng)
    }
  }

  const useMyLocation = () => {
    if (!navigator.geolocation) return
    navigator.geolocation.getCurrentPosition(
      (pos) => {
        setLat(pos.coords.latitude)
        setLng(pos.coords.longitude)
      },
      () => {
        setLat(DEFAULT_LAT)
        setLng(DEFAULT_LNG)
      }
    )
  }

  const openVehicle = (id: string) => {
    navigate(`/vehicles/${id}`)
  }

  const copyVehicle = async (vehicle: NearbyVehicle) => {
    const ok = await copyVehicleDetails(vehicle, `${window.location.origin}/vehicles/${vehicle.id}`).catch(() => false)
    if (ok) toast.success("Dettagli copiati")
    else toast.error("Copia non disponibile")
  }

  const calculateRoute = async () => {
    const end = { lat: Number(destinationLat), lng: Number(destinationLng) }
    if (!Number.isFinite(end.lat) || !Number.isFinite(end.lng)) {
      toast.error("Coordinate destinazione non valide")
      return
    }
    setRouteLoading(true)
    const route = await planBestRoute({ lat, lng }, end, zones)
    setDestination(end)
    setPlannedRoute(route)
    setRouteLoading(false)
  }

  const useCenterAsDestination = () => {
    setDestinationLat(lat.toFixed(5))
    setDestinationLng(lng.toFixed(5))
  }

  const reserveSuggested = async (vehicle: NearbyVehicle) => {
    setSuggestionLoadingId(vehicle.id)
    const { error } = await supabase.rpc("reservation_create", { p_vehicle_id: vehicle.id })
    setSuggestionLoadingId(null)
    if (error) {
      toast.error(error.message)
      return
    }
    toast.success("Mezzo suggerito prenotato")
    navigate("/reservation")
  }

  return (
    <AppShell title="Mezzi vicini" variant="wide" mainClassName="nearby-main">
      <div className="nearby-layout">
        <section className="nearby-map-column">
          {profile?.status !== "active" && (
            <div className="mb-4 rounded-2xl bg-[#ffe5e5] p-4 text-sm text-[var(--destructive)]">
              Il tuo account e {profile?.status === "suspended" ? "sospeso" : "bloccato"}. Non puoi prenotare mezzi.
            </div>
          )}

          {activeReservation && (
            <Link to="/reservation" className="block mb-4">
              <div className="rounded-3xl btn-primary-grad p-5 text-white">
                <p className="label-sm opacity-80">PRENOTAZIONE ATTIVA</p>
                <p className="mt-1 text-lg font-bold">Hai un mezzo prenotato</p>
                <p className="mt-1 text-sm opacity-90">Tocca per sbloccare il mezzo</p>
              </div>
            </Link>
          )}

          <VehicleMap
            center={{ lat, lng }}
            vehicles={filteredVehicles}
            radiusM={DEFAULT_RADIUS}
            loading={loading}
            filter={filter}
            selectedVehicleId={selectedVehicleId}
            onFilterChange={setFilter}
            onCenterChange={updateSearchCenter}
            onUseMyLocation={useMyLocation}
            onSelectVehicle={setSelectedVehicleId}
            onOpenVehicle={openVehicle}
            zones={zones}
            destination={destination}
            plannedRoute={plannedRoute}
            onCopyVehicle={copyVehicle}
          />
        </section>

        <aside className="nearby-sidebar">
          <div className="nearby-sidebar-sticky">
            <div className="mb-4 flex items-end justify-between gap-3 px-1">
              <div>
                <p className="label-sm text-[var(--muted-foreground)]">Vicini</p>
                <h2 className="text-xl font-extrabold">Mezzi vicini</h2>
              </div>
              <span className="rounded-full bg-[var(--surface-high)] px-3 py-1 text-xs font-bold text-[var(--foreground)]">
                {filteredVehicles.length}
              </span>
            </div>

            {selectedVehicle ? (
              <VehicleDetailCard
                vehicle={selectedVehicle}
                onOpenVehicle={openVehicle}
                onCopyVehicle={copyVehicle}
                className="nearby-selected-panel hidden md:block"
              />
            ) : (
              <div className="nearby-selected-panel hidden rounded-3xl bg-[var(--surface-lowest)] p-5 md:block">
                <p className="label-sm text-[var(--muted-foreground)]">SELEZIONE</p>
                <p className="mt-2 text-sm leading-relaxed text-[var(--muted-foreground)]">
                  Tocca un marker o un mezzo nella lista per vedere i dettagli rapidi.
                </p>
              </div>
            )}

            <TonalCard className="mt-4">
              <div className="flex items-start gap-3">
                <div className="flex size-11 items-center justify-center rounded-2xl bg-[var(--surface-low)] text-[var(--primary)]">
                  <Route className="size-5" />
                </div>
                <div className="min-w-0 flex-1">
                  <p className="label-sm text-[var(--muted-foreground)]">PERCORSO MIGLIORE</p>
                  <h3 className="mt-1 font-bold">Destinazione</h3>
                  <div className="mt-3 grid grid-cols-2 gap-2">
                    <input
                      type="number"
                      step="0.00001"
                      value={destinationLat}
                      onChange={(event) => setDestinationLat(event.target.value)}
                      className="h-10 rounded-2xl bg-[var(--surface-low)] px-3 font-mono text-sm outline-none"
                      aria-label="Latitudine destinazione"
                      placeholder="41.1200"
                    />
                    <input
                      type="number"
                      step="0.00001"
                      value={destinationLng}
                      onChange={(event) => setDestinationLng(event.target.value)}
                      className="h-10 rounded-2xl bg-[var(--surface-low)] px-3 font-mono text-sm outline-none"
                      aria-label="Longitudine destinazione"
                      placeholder="16.8760"
                    />
                  </div>
                  <div className="mt-3 grid grid-cols-2 gap-2">
                    <Button type="button" variant="ghost" onClick={useCenterAsDestination} className="h-10 rounded-2xl bg-[var(--surface-high)] font-bold text-[var(--primary)]">
                      <MapPinned className="size-4" /> Usa centro
                    </Button>
                    <Button type="button" onClick={calculateRoute} disabled={routeLoading} className="h-10 rounded-2xl btn-primary-grad font-bold">
                      {routeLoading ? <Spinner /> : "Calcola"}
                    </Button>
                  </div>
                </div>
              </div>
            {plannedRoute && (
                <div className="mt-4 rounded-2xl bg-[var(--surface-low)] p-4">
                  <div className="flex items-center justify-between gap-3">
                    <p className="font-bold">{plannedRoute.distanceKm.toFixed(2)} km - {plannedRoute.durationMinutes} min</p>
                    <span className={cn(
                      "rounded-full px-3 py-1 text-[0.6875rem] font-bold uppercase",
                      plannedRoute.isSimulated ? "bg-[#fff3d6] text-[var(--warning)]" : "bg-[var(--secondary-container)] text-[var(--secondary-foreground)]"
                    )}>
                      {plannedRoute.isSimulated ? "Stimato" : "Provider"}
                    </span>
                  </div>
                  <p className="mt-2 text-xs leading-relaxed text-[var(--muted-foreground)]">
                    {plannedRoute.isSimulated
                      ? "Percorso stimato con fallback locale: devia le zone critiche note senza navigazione turn-by-turn."
                      : "Percorso calcolato tramite provider configurato."}
                  </p>
                  <p className="mt-2 text-xs font-semibold text-[var(--primary)]">
                    {plannedRoute.avoidedZones.length > 0
                      ? `Evita: ${plannedRoute.avoidedZones.map((zone) => zone.name).join(", ")}`
                      : "Nessuna zona critica rilevata sul percorso diretto."}
                  </p>
                </div>
              )}
            </TonalCard>

            {(routeZoneAlerts.length > 0 || selectedVehicleZoneAlerts.length > 0) && (
              <TonalCard className="mt-4 bg-[#fff3d6]">
                <p className="label-sm text-[var(--warning)]">AVVISI VIABILITA</p>
                <div className="mt-3 flex flex-col gap-2">
                  {routeZoneAlerts.map(({ zone, status }) => (
                    <div key={`route-${zone.id}`} className="rounded-2xl bg-white/65 p-3">
                      <p className="text-sm font-bold">{zone.name}</p>
                      <p className="text-xs font-semibold text-[var(--warning)]">
                        Zona {zone.type === "restricted_area" ? "interdetta" : "sensibile"} {status} dal percorso.
                      </p>
                    </div>
                  ))}
                  {selectedVehicleZoneAlerts.map((zone) => (
                    <div key={`vehicle-${zone.id}`} className="rounded-2xl bg-white/65 p-3">
                      <p className="text-sm font-bold">{zone.name}</p>
                      <p className="text-xs font-semibold text-[var(--warning)]">
                        Il mezzo selezionato e vicino a una zona {zone.type === "restricted_area" ? "interdetta" : "sensibile"}.
                      </p>
                    </div>
                  ))}
                </div>
              </TonalCard>
            )}

            {tripSuggestion?.suggestedVehicle && (
              <TonalCard className="mt-4 bg-[var(--secondary-container)]">
                <div className="flex items-start gap-3">
                  <div className="flex size-11 items-center justify-center rounded-2xl bg-white/70 text-[var(--secondary-foreground)]">
                    <Sparkles className="size-5" />
                  </div>
                  <div className="min-w-0 flex-1">
                    <p className="label-sm text-[var(--secondary-foreground)]">SUGGERIMENTO MEZZO</p>
                    <h3 className="mt-1 font-bold">{VehicleDisplayName(tripSuggestion.suggestedVehicle)}</h3>
                    <p className="mt-1 text-xs font-semibold leading-relaxed text-[var(--secondary-foreground)]">
                      {tripSuggestion.reason}
                    </p>
                    <div className="mt-3 grid grid-cols-3 gap-2 text-center text-xs font-bold text-[var(--secondary-foreground)]">
                      <span className="rounded-full bg-white/60 px-2 py-1">{tripSuggestion.estimatedDistanceKm.toFixed(1)} km</span>
                      <span className="rounded-full bg-white/60 px-2 py-1">{tripSuggestion.estimatedDurationMinutes} min</span>
                      <span className="rounded-full bg-white/60 px-2 py-1">{tripSuggestion.estimatedCost.toFixed(2)} EUR</span>
                    </div>
                    {tripSuggestion.alternatives.length > 0 && (
                      <div className="mt-3 flex flex-col gap-1">
                        {tripSuggestion.alternatives.map((item) => (
                          <button
                            key={item.vehicle.id}
                            type="button"
                            onClick={() => setSelectedVehicleId(item.vehicle.id)}
                            className="rounded-2xl bg-white/55 px-3 py-2 text-left text-xs font-semibold text-[var(--secondary-foreground)]"
                          >
                            Alternativa: {VehicleDisplayName(item.vehicle)} - {item.estimatedCost.toFixed(2)} EUR
                          </button>
                        ))}
                      </div>
                    )}
                  </div>
                </div>
                <div className="mt-4 grid grid-cols-2 gap-2">
                  <Button
                    type="button"
                    variant="ghost"
                    onClick={() => copyVehicle(tripSuggestion.suggestedVehicle!)}
                    className="h-11 rounded-2xl bg-white/65 font-bold text-[var(--primary)]"
                  >
                    <Copy className="size-4" /> Copia
                  </Button>
                  <Button
                    type="button"
                    disabled={suggestionLoadingId === tripSuggestion.suggestedVehicle.id || !!activeReservation}
                    className="h-11 rounded-2xl btn-primary-grad font-bold"
                    onClick={() => reserveSuggested(tripSuggestion.suggestedVehicle!)}
                  >
                    {suggestionLoadingId === tripSuggestion.suggestedVehicle.id ? <Spinner /> : "Prenota"}
                  </Button>
                </div>
              </TonalCard>
            )}

            {zones.length > 0 && (
              <TonalCard className="mt-4">
                <p className="label-sm text-[var(--muted-foreground)]">ZONE URBANE ATTIVE</p>
                <div className="mt-3 flex flex-col gap-2">
                  {zones.slice(0, 3).map((zone) => (
                    <div key={zone.id} className="rounded-2xl bg-[var(--surface-low)] p-3">
                      <p className="text-sm font-bold">{zone.name}</p>
                      <p className="text-xs text-[var(--muted-foreground)]">{zone.radius_meters} m - {zone.description}</p>
                    </div>
                  ))}
                </div>
              </TonalCard>
            )}

            <div className="mt-4">
              {loading ? (
                <div className="flex justify-center py-10"><Spinner /></div>
              ) : filteredVehicles.length === 0 ? (
                <TonalCard className="py-10 text-center">
                  <p className="text-[var(--muted-foreground)]">
                    {vehicles.length === 0 ? "Nessun mezzo disponibile nelle vicinanze." : "Nessun mezzo per questo filtro."}
                  </p>
                  {vehicles.length === 0 && (
                    <p className="mt-2 text-sm leading-relaxed text-[var(--muted-foreground)]">
                      Se e il primo avvio locale, esegui la migration <span className="font-mono">20260515170000_zoosmart_local_bootstrap.sql</span>.
                    </p>
                  )}
                </TonalCard>
              ) : (
                <div className="flex flex-col gap-3">
                  {filteredVehicles.map((vehicle) => (
                    <VehicleListCard
                      key={vehicle.id}
                      vehicle={vehicle}
                      active={vehicle.id === selectedVehicleId}
                      onSelect={() => setSelectedVehicleId(vehicle.id)}
                      onOpen={() => openVehicle(vehicle.id)}
                      onCopy={() => copyVehicle(vehicle)}
                    />
                  ))}
                </div>
              )}
            </div>
          </div>
        </aside>
      </div>
    </AppShell>
  )
}

function VehicleListIcon({ type }: { type: NearbyVehicle["type"] }) {
  if (type === "bike") return <Bike className="size-5" />
  if (type === "car") return <CarFront className="size-5" />
  return <CircleDot className="size-5" />
}

function VehicleListCard({
  vehicle,
  active,
  onSelect,
  onOpen,
  onCopy,
}: {
  vehicle: NearbyVehicle
  active: boolean
  onSelect: () => void
  onOpen: () => void
  onCopy: () => void
}) {
  return (
    <TonalCard active={active} onClick={onSelect} className="nearby-vehicle-card">
      <div className="flex items-start gap-3">
        <div className={cn("nearby-vehicle-icon", `nearby-vehicle-icon-${VehicleIconType(vehicle)}`)}>
          <VehicleListIcon type={VehicleIconType(vehicle)} />
        </div>
        <div className="min-w-0 flex-1">
          <div className="flex items-start justify-between gap-2">
            <div>
              <p className="label-sm text-[var(--muted-foreground)]">{vehicle.code} - {VehicleCategoryLabel(vehicle)}</p>
              <h3 className="mt-0.5 text-base font-bold leading-tight">{VehicleDisplayName(vehicle)}</h3>
              <p className="mt-0.5 text-xs font-semibold text-[var(--muted-foreground)]">{VehicleModelLabel(vehicle)}</p>
            </div>
            <StatusChip status={vehicle.is_remote_locked ? "remote_locked" : vehicle.status} />
          </div>
          {vehicle.is_remote_locked && (
            <p className="mt-2 rounded-2xl bg-[#ffe5e5] px-3 py-2 text-xs font-bold text-[var(--destructive)]">
              Bloccato da remoto - non utilizzabile
            </p>
          )}
          <div className="mt-3 flex items-center justify-between gap-3">
            <BatteryBar level={vehicle.battery_level} />
            <span className="text-xs font-semibold tabular-nums text-[var(--muted-foreground)]">
              {Math.round(vehicle.distance_m)} m
            </span>
          </div>
          <p className="mt-2 text-xs font-semibold text-[var(--primary)]">{VehiclePricingLabel(vehicle)}</p>
        </div>
        <div className="flex shrink-0 flex-col gap-2">
          <Button
            type="button"
            variant="ghost"
            size="icon-sm"
            aria-label={`Copia dettagli ${vehicle.code}`}
            className="rounded-full bg-[var(--surface-low)] text-[var(--primary)] hover:bg-[var(--surface-high)]"
            onClick={(event) => {
              event.stopPropagation()
              onCopy()
            }}
          >
            <Copy className="size-4" />
          </Button>
          <Button
            type="button"
            variant="ghost"
            size="icon-sm"
            aria-label={`Apri dettaglio ${vehicle.code}`}
            className="rounded-full bg-[var(--surface-low)] text-[var(--primary)] hover:bg-[var(--surface-high)]"
            onClick={(event) => {
              event.stopPropagation()
              onOpen()
            }}
          >
            <ChevronRight className="size-5" />
          </Button>
        </div>
      </div>
    </TonalCard>
  )
}
