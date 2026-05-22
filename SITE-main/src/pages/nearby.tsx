import { useEffect, useState } from "react"
import { Link, useNavigate } from "react-router-dom"
import { ChevronRight, MapPin, Search } from "lucide-react"
import { AppShell } from "@/components/app-shell"
import { BatteryBar, StatusChip, TonalCard, VehicleEmoji, VehicleTypeLabel } from "@/components/vehicle-card"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Spinner } from "@/components/ui/spinner"
import { supabase, type NearbyVehicle, type Reservation } from "@/lib/supabase"
import { useAuth } from "@/lib/auth-context"

const DEFAULT_LAT = 41.1175
const DEFAULT_LNG = 16.872
const DEFAULT_RADIUS = 5000

export function NearbyPage() {
  const { profile } = useAuth()
  const navigate = useNavigate()
  const [lat, setLat] = useState(DEFAULT_LAT)
  const [lng, setLng] = useState(DEFAULT_LNG)
  const [vehicles, setVehicles] = useState<NearbyVehicle[]>([])
  const [loading, setLoading] = useState(true)
  const [activeReservation, setActiveReservation] = useState<Reservation | null>(null)

  const load = async () => {
    setLoading(true)
    await supabase.rpc("reservation_expire_stale")
    const [{ data }, resQ] = await Promise.all([
      supabase.rpc("vehicles_nearby", { p_lat: lat, p_lng: lng, p_radius: DEFAULT_RADIUS }),
      supabase.from("reservations").select("*").eq("status", "active").order("created_at", { ascending: false }).limit(1).maybeSingle(),
    ])
    setVehicles((data as NearbyVehicle[]) ?? [])
    setActiveReservation((resQ.data as Reservation) ?? null)
    setLoading(false)
  }

  useEffect(() => {
    load()
  }, [lat, lng])

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

  return (
    <AppShell title="Mezzi vicini">
      {profile?.status !== "active" && (
        <div className="mb-4 rounded-2xl bg-[#ffe5e5] p-4 text-sm text-[var(--destructive)]">
          Il tuo account è {profile?.status === "suspended" ? "sospeso" : "bloccato"}. Non puoi prenotare mezzi.
        </div>
      )}

      {activeReservation && (
        <Link to="/reservation" className="block mb-4">
          <div className="rounded-3xl btn-primary-grad p-5 text-white">
            <p className="label-sm opacity-80">PRENOTAZIONE ATTIVA</p>
            <p className="text-lg font-bold mt-1">Hai un mezzo prenotato</p>
            <p className="text-sm opacity-90 mt-1">Tocca per sbloccare il mezzo</p>
          </div>
        </Link>
      )}

      <TonalCard className="mb-5">
        <div className="flex items-center gap-2 text-[var(--muted-foreground)] mb-3">
          <MapPin className="size-4" />
          <span className="label-sm">POSIZIONE</span>
        </div>
        <div className="flex gap-2">
          <Input value={lat.toFixed(4)} readOnly className="h-11 rounded-xl bg-[var(--surface-low)] border-0 font-mono text-sm" />
          <Input value={lng.toFixed(4)} readOnly className="h-11 rounded-xl bg-[var(--surface-low)] border-0 font-mono text-sm" />
        </div>
        <Button onClick={useMyLocation} variant="ghost" className="mt-3 w-full h-10 rounded-xl bg-[var(--surface-low)] hover:bg-[var(--surface-high)] text-[var(--primary)] font-bold">
          <Search className="size-4" />
          Usa la mia posizione
        </Button>
      </TonalCard>

      <div className="flex items-center justify-between mb-3 px-1">
        <h2 className="text-lg font-bold">Disponibili</h2>
        <span className="label-sm text-[var(--muted-foreground)]">{vehicles.length} mezzi</span>
      </div>

      {loading ? (
        <div className="flex justify-center py-10"><Spinner /></div>
      ) : vehicles.length === 0 ? (
        <TonalCard className="text-center py-10">
          <p className="text-[var(--muted-foreground)]">Nessun mezzo disponibile nelle vicinanze.</p>
          <p className="mt-2 text-sm text-[var(--muted-foreground)] leading-relaxed">
            Se e il primo avvio locale, esegui la migration <span className="font-mono">20260515170000_zoosmart_local_bootstrap.sql</span> per inserire i mezzi di test.
          </p>
        </TonalCard>
      ) : (
        <div className="flex flex-col gap-3">
          {vehicles.map((v) => (
            <TonalCard key={v.id} onClick={() => navigate(`/vehicles/${v.id}`)}>
              <div className="flex items-start gap-3">
                <VehicleEmoji type={v.type} />
                <div className="flex-1 min-w-0">
                  <div className="flex items-start justify-between gap-2">
                    <div>
                      <p className="label-sm text-[var(--muted-foreground)]">{v.code}</p>
                      <h3 className="font-bold text-base leading-tight mt-0.5">{VehicleTypeLabel(v.type)}</h3>
                    </div>
                    <StatusChip status={v.status} />
                  </div>
                  <div className="mt-3 flex items-center justify-between gap-3">
                    <BatteryBar level={v.battery_level} />
                    <span className="text-xs font-semibold text-[var(--muted-foreground)] tabular-nums">{Math.round(v.distance_m)} m</span>
                  </div>
                </div>
                <ChevronRight className="size-5 text-[var(--muted-foreground)] shrink-0 mt-1" />
              </div>
            </TonalCard>
          ))}
        </div>
      )}
    </AppShell>
  )
}
