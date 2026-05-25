import { useEffect, useMemo, useRef, useState } from "react"
import { Link, useNavigate } from "react-router-dom"
import { Bike, CarFront, ChevronRight, CircleDot } from "lucide-react"
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
import { supabase, type NearbyVehicle, type Reservation } from "@/lib/supabase"
import { useAuth } from "@/lib/auth-context"
import { cn } from "@/lib/utils"

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
  const loadSeq = useRef(0)

  const filteredVehicles = useMemo(() => {
    if (filter === "all") return vehicles
    return vehicles.filter((vehicle) => VehicleIconType(vehicle) === filter)
  }, [filter, vehicles])

  const selectedVehicle = filteredVehicles.find((vehicle) => vehicle.id === selectedVehicleId) ?? null

  const load = async (targetLat = lat, targetLng = lng) => {
    const seq = ++loadSeq.current
    setLoading(true)
    await supabase.rpc("reservation_expire_stale")
    const [{ data }, resQ] = await Promise.all([
      supabase.rpc("vehicles_nearby", { p_lat: targetLat, p_lng: targetLng, p_radius: DEFAULT_RADIUS }),
      supabase.from("reservations").select("*").eq("status", "active").order("created_at", { ascending: false }).limit(1).maybeSingle(),
    ])

    if (seq !== loadSeq.current) return

    setVehicles((data as NearbyVehicle[]) ?? [])
    setActiveReservation((resQ.data as Reservation) ?? null)
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
          />
        </section>

        <aside className="nearby-sidebar">
          <div className="nearby-sidebar-sticky">
            <div className="mb-4 flex items-end justify-between gap-3 px-1">
              <div>
                <p className="label-sm text-[var(--muted-foreground)]">Disponibili</p>
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
}: {
  vehicle: NearbyVehicle
  active: boolean
  onSelect: () => void
  onOpen: () => void
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
            <StatusChip status={vehicle.status} />
          </div>
          <div className="mt-3 flex items-center justify-between gap-3">
            <BatteryBar level={vehicle.battery_level} />
            <span className="text-xs font-semibold tabular-nums text-[var(--muted-foreground)]">
              {Math.round(vehicle.distance_m)} m
            </span>
          </div>
          <p className="mt-2 text-xs font-semibold text-[var(--primary)]">{VehiclePricingLabel(vehicle)}</p>
        </div>
        <Button
          type="button"
          variant="ghost"
          size="icon-sm"
          aria-label={`Apri dettaglio ${vehicle.code}`}
          className="shrink-0 rounded-full bg-[var(--surface-low)] text-[var(--primary)] hover:bg-[var(--surface-high)]"
          onClick={(event) => {
            event.stopPropagation()
            onOpen()
          }}
        >
          <ChevronRight className="size-5" />
        </Button>
      </div>
    </TonalCard>
  )
}
