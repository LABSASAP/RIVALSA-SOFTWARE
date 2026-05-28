import { useEffect, useMemo, useState } from "react"
import { Circle, CircleMarker, MapContainer, TileLayer, Tooltip, useMap } from "react-leaflet"
import { toast } from "sonner"
import { LocateFixed, LockKeyhole, RefreshCw, UnlockKeyhole } from "lucide-react"
import { BatteryBar, StatusChip, TonalCard, VehicleCategoryLabel, VehicleDisplayName } from "@/components/vehicle-card"
import { Button } from "@/components/ui/button"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Spinner } from "@/components/ui/spinner"
import {
  supabase,
  type OperatorFleetDistributionVehicle,
  type OperatorLowAvailabilityAlert,
  type VehicleCategory,
  type Vehicle,
} from "@/lib/supabase"
import { PageBody, PageHeader, StatCard } from "@/pages/operator/_shared"

type StatusFilter = "all" | Vehicle["status"] | "remote_locked"
type CategoryFilter = "all" | VehicleCategory

const DEFAULT_CENTER = { lat: 41.1175, lng: 16.872 }
const DEFAULT_TILE_URL = "https://tile.openstreetmap.org/{z}/{x}/{y}.png"
const DEFAULT_ATTRIBUTION = '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors'
const tileUrl = (import.meta.env.VITE_MAP_TILE_URL as string | undefined)?.trim() || (import.meta.env.DEV ? DEFAULT_TILE_URL : "")
const tileAttribution = (import.meta.env.VITE_MAP_ATTRIBUTION as string | undefined)?.trim() || DEFAULT_ATTRIBUTION

const CATEGORY_LABEL: Record<VehicleCategory, string> = {
  bike: "Bike",
  scooter: "Scooter",
  economy_car: "Economy",
  standard_car: "Standard",
  premium_car: "Premium",
}

const STATUS_TONE: Record<string, string> = {
  available: "#2e7d32",
  reserved: "#b26a00",
  in_use: "#0040a1",
  maintenance: "#c62828",
  remote_locked: "#c62828",
}

function normalizeVehicles(data: unknown): OperatorFleetDistributionVehicle[] {
  return ((data as OperatorFleetDistributionVehicle[] | null) ?? []).map((vehicle) => ({
    ...vehicle,
    battery_level: Number(vehicle.battery_level ?? 0),
    lat: Number(vehicle.lat ?? DEFAULT_CENTER.lat),
    lng: Number(vehicle.lng ?? DEFAULT_CENTER.lng),
    open_reports_count: Number(vehicle.open_reports_count ?? 0),
  }))
}

function normalizeAlerts(data: unknown): OperatorLowAvailabilityAlert[] {
  return ((data as OperatorLowAvailabilityAlert[] | null) ?? []).map((alert) => ({
    ...alert,
    center_lat: Number(alert.center_lat ?? DEFAULT_CENTER.lat),
    center_lng: Number(alert.center_lng ?? DEFAULT_CENTER.lng),
    radius_meters: Number(alert.radius_meters ?? 0),
    available_vehicles: Number(alert.available_vehicles ?? 0),
    total_vehicles: Number(alert.total_vehicles ?? 0),
    low_battery_vehicles: Number(alert.low_battery_vehicles ?? 0),
    maintenance_vehicles: Number(alert.maintenance_vehicles ?? 0),
    in_use_vehicles: Number(alert.in_use_vehicles ?? 0),
    threshold: Number(alert.threshold ?? 3),
  }))
}

export function OperatorFleetPage() {
  const [vehicles, setVehicles] = useState<OperatorFleetDistributionVehicle[]>([])
  const [alerts, setAlerts] = useState<OperatorLowAvailabilityAlert[]>([])
  const [statusFilter, setStatusFilter] = useState<StatusFilter>("all")
  const [categoryFilter, setCategoryFilter] = useState<CategoryFilter>("all")
  const [mapCenter, setMapCenter] = useState(DEFAULT_CENTER)
  const [selectedVehicleId, setSelectedVehicleId] = useState<string | null>(null)
  const [loading, setLoading] = useState(true)
  const [pendingId, setPendingId] = useState<string | null>(null)

  const load = async () => {
    setLoading(true)
    const [{ data: fleet }, { data: lowAvailability }] = await Promise.all([
      supabase.rpc("operator_fleet_distribution"),
      supabase.rpc("operator_low_availability_alerts", { p_threshold: 3 }),
    ])
    const rows = normalizeVehicles(fleet)
    setVehicles(rows)
    setAlerts(normalizeAlerts(lowAvailability))
    setMapCenter(rows[0] ? { lat: rows[0].lat, lng: rows[0].lng } : DEFAULT_CENTER)
    setLoading(false)
  }

  useEffect(() => { void load() }, [])

  const filteredVehicles = useMemo(() => {
    return vehicles.filter((vehicle) => {
      const statusOk =
        statusFilter === "all" ||
        (statusFilter === "remote_locked" ? vehicle.is_remote_locked : vehicle.status === statusFilter && !vehicle.is_remote_locked)
      const categoryOk = categoryFilter === "all" || vehicle.category === categoryFilter
      return statusOk && categoryOk
    })
  }, [categoryFilter, statusFilter, vehicles])

  const counts = useMemo(() => ({
    total: vehicles.length,
    available: vehicles.filter((vehicle) => vehicle.status === "available" && !vehicle.is_remote_locked).length,
    reserved: vehicles.filter((vehicle) => vehicle.status === "reserved").length,
    inUse: vehicles.filter((vehicle) => vehicle.status === "in_use").length,
    maintenance: vehicles.filter((vehicle) => vehicle.status === "maintenance").length,
    locked: vehicles.filter((vehicle) => vehicle.is_remote_locked).length,
  }), [vehicles])

  const selectedVehicle = vehicles.find((vehicle) => vehicle.id === selectedVehicleId) ?? null

  const focusVehicle = (vehicle: OperatorFleetDistributionVehicle) => {
    setSelectedVehicleId(vehicle.id)
    setMapCenter({ lat: vehicle.lat, lng: vehicle.lng })
  }

  const toggleLock = async (vehicle: OperatorFleetDistributionVehicle) => {
    const reason = !vehicle.is_remote_locked
      ? window.prompt("Motivo blocco remoto", vehicle.remote_lock_reason || "Mezzo fuori zona consentita") || "Blocco remoto da dashboard operatore"
      : null
    setPendingId(vehicle.id)
    const { error } = await supabase.rpc("operator_set_vehicle_remote_lock", {
      p_vehicle_id: vehicle.id,
      p_locked: !vehicle.is_remote_locked,
      p_reason: reason,
    })
    setPendingId(null)
    if (error) {
      toast.error(error.message)
      return
    }
    toast.success(vehicle.is_remote_locked ? "Blocco rimosso" : "Mezzo bloccato")
    void load()
  }

  return (
    <>
      <PageHeader
        title="Distribuzione flotta"
        subtitle="Monitora mezzi, aree a bassa copertura e blocco remoto simulato."
        action={<Button onClick={load} disabled={loading} className="h-11 rounded-2xl btn-primary-grad px-5 font-bold">{loading ? <Spinner /> : (<><RefreshCw className="size-4" /> Aggiorna</>)}</Button>}
      />
      <PageBody>
        <div className="mb-6 grid gap-4 md:grid-cols-3 xl:grid-cols-6">
          <StatCard label="MEZZI" value={counts.total} tone="primary" />
          <StatCard label="DISPONIBILI" value={counts.available} />
          <StatCard label="PRENOTATI" value={counts.reserved} />
          <StatCard label="IN USO" value={counts.inUse} tone="warning" />
          <StatCard label="MANUTENZIONE" value={counts.maintenance} tone="danger" />
          <StatCard label="BLOCCATI" value={counts.locked} tone="danger" />
        </div>

        {alerts.length > 0 && (
          <div className="mb-6 grid gap-3 lg:grid-cols-3">
            {alerts.map((alert) => (
              <TonalCard key={alert.area_id} className={alert.severity === "critical" ? "bg-[#ffe5e5]" : "bg-[#fff3d6]"}>
                <div className="flex items-start justify-between gap-3">
                  <div className="min-w-0">
                    <p className="label-sm text-[var(--muted-foreground)]">AREA A BASSA DISPONIBILITA</p>
                    <h3 className="mt-1 font-bold">{alert.area_name}</h3>
                    <p className="mt-1 text-sm text-[var(--muted-foreground)]">{alert.message}</p>
                    <p className="mt-2 text-xs font-semibold text-[var(--muted-foreground)]">
                      {alert.available_vehicles}/{alert.total_vehicles} disponibili, soglia {alert.threshold}
                    </p>
                  </div>
                  <StatusChip status={alert.severity} />
                </div>
                <Button
                  type="button"
                  variant="ghost"
                  onClick={() => setMapCenter({ lat: alert.center_lat, lng: alert.center_lng })}
                  className="mt-3 rounded-2xl bg-white/65 font-bold text-[var(--primary)]"
                >
                  <LocateFixed className="size-4" /> Visualizza area
                </Button>
              </TonalCard>
            ))}
          </div>
        )}

        <div className="mb-5 flex flex-wrap gap-3">
          <Select value={statusFilter} onValueChange={(value) => setStatusFilter(value as StatusFilter)}>
            <SelectTrigger className="h-12 w-56 rounded-2xl border-0 bg-[var(--surface-lowest)]"><SelectValue /></SelectTrigger>
            <SelectContent>
              <SelectItem value="all">Tutti gli stati</SelectItem>
              <SelectItem value="available">Disponibili</SelectItem>
              <SelectItem value="reserved">Prenotati</SelectItem>
              <SelectItem value="in_use">In uso</SelectItem>
              <SelectItem value="maintenance">Manutenzione</SelectItem>
              <SelectItem value="remote_locked">Blocco remoto</SelectItem>
            </SelectContent>
          </Select>
          <Select value={categoryFilter} onValueChange={(value) => setCategoryFilter(value as CategoryFilter)}>
            <SelectTrigger className="h-12 w-56 rounded-2xl border-0 bg-[var(--surface-lowest)]"><SelectValue /></SelectTrigger>
            <SelectContent>
              <SelectItem value="all">Tutte le categorie</SelectItem>
              <SelectItem value="bike">Bike</SelectItem>
              <SelectItem value="scooter">Scooter</SelectItem>
              <SelectItem value="economy_car">Auto economy</SelectItem>
              <SelectItem value="standard_car">Auto standard</SelectItem>
              <SelectItem value="premium_car">Auto premium</SelectItem>
            </SelectContent>
          </Select>
        </div>

        {loading ? (
          <div className="flex justify-center py-10"><Spinner /></div>
        ) : vehicles.length === 0 ? (
          <TonalCard className="py-10 text-center text-[var(--muted-foreground)]">Nessun mezzo censito.</TonalCard>
        ) : (
          <div className="grid gap-5 xl:grid-cols-[1.1fr_0.9fr]">
            <TonalCard className="p-0">
              <div className="px-5 pt-5">
                <p className="label-sm text-[var(--muted-foreground)]">OP.01</p>
                <h2 className="mt-1 text-xl font-bold">Mappa distribuzione flotta</h2>
              </div>
              <div className="mt-4 h-[640px] overflow-hidden rounded-b-3xl bg-[var(--surface-low)]">
                <FleetMap
                  vehicles={filteredVehicles}
                  alerts={alerts}
                  center={mapCenter}
                  selectedVehicleId={selectedVehicleId}
                  onSelect={focusVehicle}
                />
              </div>
            </TonalCard>

            <div className="flex flex-col gap-3">
              {selectedVehicle && (
                <TonalCard active>
                  <p className="label-sm text-[var(--muted-foreground)]">SELEZIONE</p>
                  <h2 className="mt-1 text-xl font-bold">{VehicleDisplayName(selectedVehicle)}</h2>
                  <p className="mt-1 text-sm font-semibold text-[var(--muted-foreground)]">{selectedVehicle.code} - {VehicleCategoryLabel(selectedVehicle)}</p>
                  <div className="mt-3 flex flex-wrap items-center gap-3">
                    <StatusChip status={selectedVehicle.is_remote_locked ? "remote_locked" : selectedVehicle.status} />
                    <BatteryBar level={selectedVehicle.battery_level} />
                    <span className="font-mono text-xs text-[var(--muted-foreground)]">{selectedVehicle.lat.toFixed(5)}, {selectedVehicle.lng.toFixed(5)}</span>
                  </div>
                  {selectedVehicle.remote_lock_reason && (
                    <p className="mt-3 rounded-2xl bg-[#ffe5e5] p-3 text-sm font-semibold text-[var(--destructive)]">{selectedVehicle.remote_lock_reason}</p>
                  )}
                </TonalCard>
              )}

              {filteredVehicles.map((vehicle) => (
                <TonalCard key={vehicle.id} active={vehicle.id === selectedVehicleId} onClick={() => focusVehicle(vehicle)}>
                  <div className="flex items-start gap-4">
                    <div className="min-w-0 flex-1">
                      <div className="flex items-start justify-between gap-3">
                        <div>
                          <p className="label-sm text-[var(--muted-foreground)]">{vehicle.code} - {CATEGORY_LABEL[vehicle.category]}</p>
                          <h3 className="mt-1 text-lg font-bold">{VehicleDisplayName(vehicle)}</h3>
                        </div>
                        <StatusChip status={vehicle.is_remote_locked ? "remote_locked" : vehicle.status} />
                      </div>
                      <div className="mt-3 flex flex-wrap items-center gap-3 text-sm text-[var(--muted-foreground)]">
                        <BatteryBar level={vehicle.battery_level} />
                        <span className="font-mono">{vehicle.lat.toFixed(5)}, {vehicle.lng.toFixed(5)}</span>
                        <span>{vehicle.open_reports_count} segnalazioni</span>
                      </div>
                      <p className="mt-2 text-xs font-semibold text-[var(--muted-foreground)]">
                        Ultimo aggiornamento {new Date(vehicle.updated_at).toLocaleString("it-IT")}
                      </p>
                    </div>
                    <Button
                      onClick={(event) => {
                        event.stopPropagation()
                        void toggleLock(vehicle)
                      }}
                      disabled={pendingId === vehicle.id}
                      variant="ghost"
                      className={vehicle.is_remote_locked ? "rounded-2xl bg-[var(--secondary-container)] text-[var(--secondary-foreground)]" : "rounded-2xl bg-[#ffe5e5] text-[var(--destructive)]"}
                    >
                      {pendingId === vehicle.id ? <Spinner /> : vehicle.is_remote_locked ? <UnlockKeyhole className="size-4" /> : <LockKeyhole className="size-4" />}
                      {vehicle.is_remote_locked ? "Sblocca" : "Blocca"}
                    </Button>
                  </div>
                </TonalCard>
              ))}
            </div>
          </div>
        )}
      </PageBody>
    </>
  )
}

function FleetMap({
  vehicles,
  alerts,
  center,
  selectedVehicleId,
  onSelect,
}: {
  vehicles: OperatorFleetDistributionVehicle[]
  alerts: OperatorLowAvailabilityAlert[]
  center: { lat: number; lng: number }
  selectedVehicleId: string | null
  onSelect: (vehicle: OperatorFleetDistributionVehicle) => void
}) {
  if (!tileUrl) {
    return <div className="p-6 text-center text-sm text-[var(--muted-foreground)]">Mappa non configurata.</div>
  }

  return (
    <MapContainer center={[center.lat, center.lng]} zoom={13} className="h-full w-full" scrollWheelZoom>
      <TileLayer attribution={tileAttribution} url={tileUrl} />
      <FleetMapCenter center={center} />
      {alerts.map((alert) => (
        <Circle
          key={alert.area_id}
          center={[alert.center_lat, alert.center_lng]}
          radius={alert.radius_meters}
          pathOptions={{
            color: alert.severity === "critical" ? "#c62828" : "#b26a00",
            fillColor: alert.severity === "critical" ? "#ffe5e5" : "#fff3d6",
            fillOpacity: 0.18,
            opacity: 0.6,
            weight: 2,
          }}
        >
          <Tooltip direction="top" opacity={0.95}>{alert.message}</Tooltip>
        </Circle>
      ))}
      {vehicles.map((vehicle) => {
        const statusKey = vehicle.is_remote_locked ? "remote_locked" : vehicle.status
        const selected = vehicle.id === selectedVehicleId
        return (
          <CircleMarker
            key={vehicle.id}
            center={[vehicle.lat, vehicle.lng]}
            radius={selected ? 12 : 8}
            pathOptions={{
              color: "#ffffff",
              fillColor: STATUS_TONE[statusKey] ?? "#0040a1",
              fillOpacity: 0.95,
              opacity: 0.95,
              weight: selected ? 5 : 3,
            }}
            eventHandlers={{ click: () => onSelect(vehicle) }}
          >
            <Tooltip direction="top" opacity={0.95}>
              {vehicle.code} - {VehicleDisplayName(vehicle)}
            </Tooltip>
          </CircleMarker>
        )
      })}
    </MapContainer>
  )
}

function FleetMapCenter({ center }: { center: { lat: number; lng: number } }) {
  const map = useMap()

  useEffect(() => {
    map.setView([center.lat, center.lng], Math.max(map.getZoom(), 13), { animate: true })
  }, [center.lat, center.lng, map])

  return null
}
