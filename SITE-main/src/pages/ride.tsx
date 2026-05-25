import { useEffect, useState } from "react"
import { useNavigate } from "react-router-dom"
import { toast } from "sonner"
import { Square } from "lucide-react"
import { AppShell } from "@/components/app-shell"
import {
  StatusChip,
  TonalCard,
  VehicleCategoryLabel,
  VehicleDisplayName,
  VehicleEmoji,
  VehicleIconType,
  VehicleModelLabel,
  VehiclePricingLabel,
} from "@/components/vehicle-card"
import { Button } from "@/components/ui/button"
import { Spinner } from "@/components/ui/spinner"
import { supabase, type Ride, type Vehicle } from "@/lib/supabase"

export function RidePage() {
  const navigate = useNavigate()
  const [ride, setRide] = useState<Ride | null>(null)
  const [vehicle, setVehicle] = useState<Vehicle | null>(null)
  const [now, setNow] = useState(Date.now())
  const [ending, setEnding] = useState(false)
  const [loading, setLoading] = useState(true)
  const [finalPosition] = useState(() => ({
    lat: 41.1185 + Math.random() * 0.001,
    lng: 16.874 + Math.random() * 0.001,
  }))

  useEffect(() => {
    ;(async () => {
      const { data: r } = await supabase
        .from("rides")
        .select("*")
        .eq("status", "active")
        .order("started_at", { ascending: false })
        .limit(1)
        .maybeSingle()
      if (r) {
        setRide(r as Ride)
        const { data: v } = await supabase.from("vehicles").select("*").eq("id", (r as Ride).vehicle_id).maybeSingle()
        setVehicle((v as Vehicle) ?? null)
      }
      setLoading(false)
    })()
  }, [])

  useEffect(() => {
    const id = setInterval(() => setNow(Date.now()), 1000)
    return () => clearInterval(id)
  }, [])

  const elapsedSec = ride ? Math.max(0, Math.floor((now - new Date(ride.started_at).getTime()) / 1000)) : 0
  const hh = Math.floor(elapsedSec / 3600)
  const mm = Math.floor((elapsedSec % 3600) / 60)
  const ss = elapsedSec % 60

  const endRide = async () => {
    if (!ride) return
    setEnding(true)
    const { data, error } = await supabase.rpc("ride_end", {
      p_ride_id: ride.id,
      p_lat: finalPosition.lat,
      p_lng: finalPosition.lng,
    })
    setEnding(false)
    if (error) {
      toast.error(error.message)
      return
    }
    toast.success("Corsa terminata")
    if (data) navigate(`/ride/${ride.id}/summary`)
  }

  if (loading) {
    return (
      <AppShell title="Corsa" back="/nearby">
        <div className="flex justify-center py-10"><Spinner /></div>
      </AppShell>
    )
  }
  if (!ride || !vehicle) {
    return (
      <AppShell title="Corsa" back="/nearby">
        <TonalCard className="text-center py-10">
          <p className="text-[var(--muted-foreground)]">Nessuna corsa attiva.</p>
          <Button onClick={() => navigate("/nearby")} className="mt-5 h-12 rounded-2xl btn-primary-grad px-6 font-bold">
            Trova un mezzo
          </Button>
        </TonalCard>
      </AppShell>
    )
  }

  return (
    <AppShell title="Corsa attiva" hideTabs>
      <TonalCard className="text-center">
        <div className="flex justify-center mb-3">
          <VehicleEmoji type={VehicleIconType(vehicle)} />
        </div>
        <p className="label-sm text-[var(--muted-foreground)]">{vehicle.code}</p>
        <h2 className="text-xl font-extrabold mt-1">{VehicleDisplayName(vehicle)}</h2>
        <p className="mt-1 text-sm font-semibold text-[var(--muted-foreground)]">{VehicleModelLabel(vehicle)}</p>
        <div className="mt-3 flex justify-center">
          <StatusChip status="in_use" />
        </div>
      </TonalCard>

      <TonalCard className="mt-4 ghost-active text-center">
        <p className="label-sm text-[var(--muted-foreground)]">DURATA CORSA</p>
        <p className="text-6xl font-extrabold tabular-nums leading-none mt-3 font-display">
          {String(hh).padStart(2, "0")}:{String(mm).padStart(2, "0")}:{String(ss).padStart(2, "0")}
        </p>
        <p className="mt-3 text-sm text-[var(--muted-foreground)]">In corso dalle {new Date(ride.started_at).toLocaleTimeString("it-IT", { hour: "2-digit", minute: "2-digit" })}</p>
      </TonalCard>

      <TonalCard className="mt-4">
        <p className="label-sm text-[var(--muted-foreground)]">TARIFFA {VehicleCategoryLabel(vehicle).toUpperCase()}</p>
        <p className="mt-2 text-sm font-bold text-[var(--primary)]">{VehiclePricingLabel(vehicle)}</p>
      </TonalCard>

      <TonalCard className="mt-4">
        <p className="label-sm text-[var(--muted-foreground)]">POSIZIONE FINALE SIMULATA</p>
        <p className="font-mono text-sm mt-2">
          {finalPosition.lat.toFixed(5)}, {finalPosition.lng.toFixed(5)}
        </p>
      </TonalCard>

      <Button onClick={endRide} disabled={ending} className="mt-6 w-full h-14 rounded-2xl bg-[var(--destructive)] text-white hover:bg-[var(--destructive)]/90 font-bold text-base">
        {ending ? <Spinner /> : (
          <>
            <Square className="size-4 fill-white" /> Termina corsa
          </>
        )}
      </Button>
    </AppShell>
  )
}
