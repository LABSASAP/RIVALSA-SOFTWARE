import { useEffect, useMemo, useState } from "react"
import { CircleMarker, MapContainer, Polyline, TileLayer, Tooltip, useMap } from "react-leaflet"
import { MapPin, RefreshCw } from "lucide-react"
import { StatusChip, TonalCard } from "@/components/vehicle-card"
import { Button } from "@/components/ui/button"
import { Spinner } from "@/components/ui/spinner"
import { supabase, type OperatorActiveRide, type OperatorRidePosition } from "@/lib/supabase"
import { PageBody, PageHeader, StatCard } from "@/pages/operator/_shared"

const DEFAULT_CENTER = { lat: 41.1175, lng: 16.872 }
const DEFAULT_TILE_URL = "https://tile.openstreetmap.org/{z}/{x}/{y}.png"
const DEFAULT_ATTRIBUTION = '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors'
const tileUrl = (import.meta.env.VITE_MAP_TILE_URL as string | undefined)?.trim() || (import.meta.env.DEV ? DEFAULT_TILE_URL : "")
const tileAttribution = (import.meta.env.VITE_MAP_ATTRIBUTION as string | undefined)?.trim() || DEFAULT_ATTRIBUTION
const STALE_THRESHOLD_MINUTES = 5

function normalizeRides(data: unknown): OperatorActiveRide[] {
  return ((data as OperatorActiveRide[] | null) ?? []).map((ride) => ({
    ...ride,
    lat: Number(ride.lat ?? DEFAULT_CENTER.lat),
    lng: Number(ride.lng ?? DEFAULT_CENTER.lng),
    stale_minutes: Number(ride.stale_minutes ?? 0),
    position_count: Number(ride.position_count ?? 0),
  }))
}

function normalizePositions(data: unknown): OperatorRidePosition[] {
  return ((data as OperatorRidePosition[] | null) ?? []).map((position) => ({
    ...position,
    lat: Number(position.lat ?? 0),
    lng: Number(position.lng ?? 0),
  }))
}

export function OperatorTrackingPage() {
  const [rides, setRides] = useState<OperatorActiveRide[]>([])
  const [selectedRideId, setSelectedRideId] = useState<string | null>(null)
  const [positions, setPositions] = useState<OperatorRidePosition[]>([])
  const [loading, setLoading] = useState(true)
  const [positionsLoading, setPositionsLoading] = useState(false)

  const selectedRide = useMemo(
    () => rides.find((ride) => ride.ride_id === selectedRideId) ?? rides[0] ?? null,
    [rides, selectedRideId]
  )

  const mapCenter = selectedRide ? { lat: selectedRide.lat, lng: selectedRide.lng } : DEFAULT_CENTER

  const load = async () => {
    setLoading(true)
    const { data } = await supabase.rpc("operator_active_rides")
    const rows = normalizeRides(data)
    setRides(rows)
    setSelectedRideId((current) => current && rows.some((ride) => ride.ride_id === current) ? current : rows[0]?.ride_id ?? null)
    setLoading(false)
  }

  const loadPositions = async (rideId: string | null) => {
    if (!rideId) {
      setPositions([])
      return
    }
    setPositionsLoading(true)
    const { data } = await supabase.rpc("operator_ride_positions", { p_ride_id: rideId })
    setPositions(normalizePositions(data))
    setPositionsLoading(false)
  }

  useEffect(() => { void load() }, [])
  useEffect(() => { void loadPositions(selectedRide?.ride_id ?? null) }, [selectedRide?.ride_id])

  const staleCount = rides.filter((ride) => ride.stale_minutes >= STALE_THRESHOLD_MINUTES).length

  return (
    <>
      <PageHeader
        title="Tracking mezzi"
        subtitle="Posizioni simulate persistenti delle corse attive e storico della corsa selezionata."
        action={<Button onClick={load} disabled={loading} className="h-11 rounded-2xl btn-primary-grad px-5 font-bold">{loading ? <Spinner /> : (<><RefreshCw className="size-4" /> Aggiorna</>)}</Button>}
      />
      <PageBody>
        <div className="mb-6 grid gap-4 md:grid-cols-3">
          <StatCard label="CORSE ATTIVE" value={rides.length} tone="primary" />
          <StatCard label="FERME >5 MIN" value={staleCount} tone={staleCount ? "warning" : undefined} />
          <StatCard label="POSIZIONI STORICO" value={positions.length} />
        </div>

        {loading ? (
          <div className="flex justify-center py-10"><Spinner /></div>
        ) : rides.length === 0 ? (
          <TonalCard className="py-10 text-center text-[var(--muted-foreground)]">Nessuna corsa attiva da monitorare.</TonalCard>
        ) : (
          <div className="grid gap-5 xl:grid-cols-[1.15fr_0.85fr]">
            <TonalCard className="p-0">
              <div className="px-5 pt-5">
                <p className="label-sm text-[var(--muted-foreground)]">OP.07</p>
                <h2 className="mt-1 text-xl font-bold">Mappa posizioni attive</h2>
              </div>
              <div className="mt-4 h-[640px] overflow-hidden rounded-b-3xl bg-[var(--surface-low)]">
                <TrackingMap
                  rides={rides}
                  selectedRide={selectedRide}
                  positions={positions}
                  center={mapCenter}
                  onSelect={(ride) => setSelectedRideId(ride.ride_id)}
                />
              </div>
            </TonalCard>

            <div className="flex flex-col gap-3">
              {selectedRide && (
                <TonalCard active>
                  <div className="flex items-start justify-between gap-3">
                    <div>
                      <p className="label-sm text-[var(--muted-foreground)]">CORSA SELEZIONATA</p>
                      <h2 className="mt-1 text-xl font-bold">{selectedRide.vehicle_code}</h2>
                      <p className="mt-1 text-sm font-semibold text-[var(--muted-foreground)]">{selectedRide.user_name}</p>
                    </div>
                    <StatusChip status={selectedRide.stale_minutes >= STALE_THRESHOLD_MINUTES ? "warning" : selectedRide.pause_status === "paused" ? "paused" : "active"} />
                  </div>
                  <div className="mt-4 grid grid-cols-2 gap-2">
                    <Field label="Ride" value={selectedRide.ride_id.slice(0, 8).toUpperCase()} mono />
                    <Field label="Posizioni" value={String(selectedRide.position_count)} />
                    <Field label="Ultimo update" value={`${selectedRide.stale_minutes} min fa`} />
                    <Field label="Coordinate" value={`${selectedRide.lat.toFixed(5)}, ${selectedRide.lng.toFixed(5)}`} mono />
                  </div>
                </TonalCard>
              )}

              {rides.map((ride) => (
                <TonalCard key={ride.ride_id} active={ride.ride_id === selectedRide?.ride_id} onClick={() => setSelectedRideId(ride.ride_id)}>
                  <div className="flex items-start gap-4">
                    <div className="flex size-12 items-center justify-center rounded-2xl bg-[var(--surface-low)] text-[var(--primary)]">
                      <MapPin className="size-5" />
                    </div>
                    <div className="min-w-0 flex-1">
                      <div className="flex items-start justify-between gap-3">
                        <div>
                          <p className="label-sm text-[var(--muted-foreground)]">{ride.vehicle_code}</p>
                          <h3 className="mt-1 font-bold">{ride.user_name}</h3>
                        </div>
                        <StatusChip status={ride.stale_minutes >= STALE_THRESHOLD_MINUTES ? "warning" : ride.pause_status === "paused" ? "paused" : "active"} />
                      </div>
                      <p className="mt-2 font-mono text-xs text-[var(--muted-foreground)]">{ride.lat.toFixed(5)}, {ride.lng.toFixed(5)}</p>
                      <p className="mt-1 text-xs font-semibold text-[var(--muted-foreground)]">
                        {ride.position_count} posizioni, ultimo dato {new Date(ride.recorded_at).toLocaleTimeString("it-IT")}
                      </p>
                    </div>
                  </div>
                </TonalCard>
              ))}

              <TonalCard>
                <p className="label-sm text-[var(--muted-foreground)]">STORICO POSIZIONI</p>
                {positionsLoading ? (
                  <div className="flex justify-center py-6"><Spinner /></div>
                ) : positions.length === 0 ? (
                  <p className="mt-3 text-sm text-[var(--muted-foreground)]">Nessuna posizione salvata per questa corsa.</p>
                ) : (
                  <div className="mt-3 max-h-80 overflow-y-auto">
                    {positions.slice().reverse().map((position) => (
                      <div key={position.id} className="mb-2 rounded-2xl bg-[var(--surface-low)] p-3">
                        <p className="font-mono text-xs font-semibold">{position.lat.toFixed(6)}, {position.lng.toFixed(6)}</p>
                        <p className="mt-1 text-[0.6875rem] text-[var(--muted-foreground)]">{new Date(position.recorded_at).toLocaleString("it-IT")}</p>
                      </div>
                    ))}
                  </div>
                )}
              </TonalCard>
            </div>
          </div>
        )}
      </PageBody>
    </>
  )
}

function TrackingMap({
  rides,
  selectedRide,
  positions,
  center,
  onSelect,
}: {
  rides: OperatorActiveRide[]
  selectedRide: OperatorActiveRide | null
  positions: OperatorRidePosition[]
  center: { lat: number; lng: number }
  onSelect: (ride: OperatorActiveRide) => void
}) {
  if (!tileUrl) {
    return <div className="p-6 text-center text-sm text-[var(--muted-foreground)]">Mappa non configurata.</div>
  }

  return (
    <MapContainer center={[center.lat, center.lng]} zoom={14} className="h-full w-full" scrollWheelZoom>
      <TileLayer attribution={tileAttribution} url={tileUrl} />
      <TrackingCenter center={center} />
      {positions.length > 1 && (
        <Polyline
          positions={positions.map((position) => [position.lat, position.lng])}
          pathOptions={{ color: "#0040a1", opacity: 0.84, weight: 5 }}
        >
          <Tooltip direction="top" opacity={0.95}>Storico corsa selezionata</Tooltip>
        </Polyline>
      )}
      {rides.map((ride) => {
        const selected = ride.ride_id === selectedRide?.ride_id
        const stale = ride.stale_minutes >= STALE_THRESHOLD_MINUTES
        return (
          <CircleMarker
            key={ride.ride_id}
            center={[ride.lat, ride.lng]}
            radius={selected ? 12 : 8}
            pathOptions={{
              color: "#ffffff",
              fillColor: stale ? "#b26a00" : "#0040a1",
              fillOpacity: 0.95,
              opacity: 0.95,
              weight: selected ? 5 : 3,
            }}
            eventHandlers={{ click: () => onSelect(ride) }}
          >
            <Tooltip direction="top" opacity={0.95}>
              {ride.vehicle_code} - {ride.user_name}
            </Tooltip>
          </CircleMarker>
        )
      })}
    </MapContainer>
  )
}

function TrackingCenter({ center }: { center: { lat: number; lng: number } }) {
  const map = useMap()

  useEffect(() => {
    map.setView([center.lat, center.lng], Math.max(map.getZoom(), 14), { animate: true })
  }, [center.lat, center.lng, map])

  return null
}

function Field({ label, value, mono }: { label: string; value: string; mono?: boolean }) {
  return (
    <div className="rounded-2xl bg-[var(--surface-low)] p-3">
      <p className="label-sm text-[var(--muted-foreground)]">{label}</p>
      <p className={mono ? "mt-1 font-mono text-xs font-semibold" : "mt-1 text-sm font-semibold"}>{value}</p>
    </div>
  )
}
